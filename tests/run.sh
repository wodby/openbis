#!/usr/bin/env bash
#
# Runs the image against PostgreSQL with three pre-created databases owned by a user without superuser, create-role
# or create-database rights, and checks sign-in, a transaction across the application and file servers, a restart and
# that the container stops when a server dies.

set -eo pipefail

if [[ -n "${DEBUG}" ]]; then
    set -x
fi

: "${IMAGE:?IMAGE is required}"
NAME="${NAME:-openbis}"
POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:18}"
START_TIMEOUT="${START_TIMEOUT:-1200}"

network="${NAME}-test-$$"
pg="${NAME}-pg-$$"
app="${NAME}-app-$$"
volume="${NAME}-data-$$"
admin_password='Adm1n "pass" $x\y'
db_password='k3y-with-dash-0123456789abcdef'

cleanup() {
    status=$?
    if [[ "${status}" != 0 ]]; then
        docker logs --tail 200 "${app}" 2>&1 || true
    fi
    docker rm -vf "${app}" "${pg}" >/dev/null 2>&1 || true
    docker volume rm "${volume}" >/dev/null 2>&1 || true
    docker network rm "${network}" >/dev/null 2>&1 || true
    exit "${status}"
}
trap cleanup EXIT

docker network create "${network}" >/dev/null
docker volume create "${volume}" >/dev/null

docker run -d --name "${pg}" --network "${network}" -e POSTGRES_PASSWORD=rootpw "${POSTGRES_IMAGE}" \
    -c max_prepared_transactions=64 >/dev/null
for i in $(seq 1 60); do
    docker exec "${pg}" pg_isready -U postgres >/dev/null 2>&1 && break
    sleep 1
done
sleep 2
docker exec -i "${pg}" psql -q -v ON_ERROR_STOP=1 -U postgres <<SQL
CREATE ROLE app_dev LOGIN PASSWORD '${db_password}' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE app_dev OWNER app_dev;
CREATE DATABASE app_dev_messages OWNER app_dev;
CREATE DATABASE app_dev_pathinfo OWNER app_dev;
SQL

start_app() {
    docker run -d --name "${app}" --network "${network}" -v "${volume}:/data" \
        -e WODBY_PRIMARY_HOST=openbis.example.com \
        -e OPENBIS_ADMIN_PASSWORD="${admin_password}" \
        -e OPENBIS_DB_HOST="${pg}" \
        -e OPENBIS_DB_NAME=app_dev \
        -e OPENBIS_DB_MESSAGES_NAME=app_dev_messages \
        -e OPENBIS_DB_PATHINFO_NAME=app_dev_pathinfo \
        -e OPENBIS_DB_USER=app_dev \
        -e OPENBIS_DB_PASSWORD="${db_password}" \
        "${IMAGE}" >/dev/null
}

wait_running() {
    local elapsed=0
    until docker logs "${app}" 2>&1 | grep -q "openBIS is running"; do
        if [[ "$(docker inspect -f '{{.State.Running}}' "${app}")" != true ]]; then
            echo "openBIS stopped while starting" >&2
            return 1
        fi
        if (( elapsed >= START_TIMEOUT )); then
            echo "openBIS did not start in ${START_TIMEOUT}s" >&2
            return 1
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
}

# rpc SERVICE JSON posts a JSON-RPC request to the application server inside the container.
rpc() {
    docker exec "${app}" curl -sS --fail -H 'content-type: application/json' \
        --data-binary "$2" "http://localhost:8080/openbis/openbis/$1"
}

login() {
    local body
    body="$(python3 -c 'import json,sys; print(json.dumps({"method":"login","params":["admin",sys.argv[1]],"id":"1","jsonrpc":"2.0"}))' "$1")"
    rpc rmi-application-server-v3.json "${body}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("result") or "")'
}

echo -n "Starting openBIS... "
start_app
wait_running
echo "OK"

echo -n "Checking the database user has no special rights... "
[[ "$(docker exec "${pg}" psql -tA -U postgres -c "SELECT rolsuper OR rolcreatedb OR rolcreaterole FROM pg_roles WHERE rolname = 'app_dev'")" == f ]]
[[ "$(docker exec "${pg}" psql -tA -U postgres -c "SELECT count(*) FROM pg_roles WHERE rolname = 'openbis_readonly'")" == 0 ]]
echo "OK"

echo -n "Checking schemas in all three databases... "
for db in app_dev app_dev_messages app_dev_pathinfo; do
    [[ "$(docker exec "${pg}" psql -tA -U postgres -d "${db}" -c "SELECT count(*) > 1 FROM pg_tables WHERE schemaname = 'public'")" == t ]]
done
echo "OK"

echo -n "Checking the lab notebook and sign-in... "
docker exec "${app}" curl -sS --fail -o /dev/null http://localhost:8080/openbis/webapp/eln-lims/version.txt
token="$(login "${admin_password}")"
[[ -n "${token}" ]]
[[ -z "$(login wrong-password)" ]]
echo "OK"

echo -n "Checking public URLs... "
docker exec "${app}" grep -qx 'download-url = https://openbis.example.com' /data/etc/as/service.properties
docker exec "${app}" grep -qx 'httpServerPublicUrl = https://openbis.example.com/afs-server' /data/etc/afs/service.properties
echo "OK"

echo -n "Checking installation keys replace the upstream defaults... "
for key in d102608b-8700-454c-b041-6f037e328264 c31503e6-5464-4148-8ff1-7f28a73fd60c; do
    if docker exec "${app}" grep -rq "${key}" /data/etc; then
        echo "upstream default key ${key} is still configured" >&2
        exit 1
    fi
done
[[ "$(docker exec "${app}" stat -c %a /data/.wodby/keys.env)" == 600 ]]
echo "OK"

echo -n "Checking a transaction across the application and file servers... "
interactive_key="$(docker exec "${app}" sh -c '. /data/.wodby/keys.env && echo "${INTERACTIVE_SESSION_KEY}"')"
tx="$(python3 -c 'import uuid; print(uuid.uuid4())')"
coordinator() {
    rpc rmi-transaction-coordinator.json "$1" | python3 -c 'import json,sys; r=json.load(sys.stdin); sys.exit("error: %s" % r["error"]["message"] if "error" in r else 0)'
}
coordinator "{\"method\":\"beginTransaction\",\"params\":[\"${tx}\",\"${token}\",\"${interactive_key}\"],\"id\":\"1\",\"jsonrpc\":\"2.0\"}"
coordinator "{\"method\":\"executeOperation\",\"params\":[\"${tx}\",\"${token}\",\"${interactive_key}\",\"application-server\",\"createSpaces\",[\"${token}\",[{\"@type\":\"as.dto.space.create.SpaceCreation\",\"code\":\"WODBY_TEST\"}]]],\"id\":\"1\",\"jsonrpc\":\"2.0\"}"
coordinator "{\"method\":\"commitTransaction\",\"params\":[\"${tx}\",\"${token}\",\"${interactive_key}\"],\"id\":\"1\",\"jsonrpc\":\"2.0\"}"
[[ "$(docker exec "${pg}" psql -tA -U postgres -d app_dev -c "SELECT count(*) FROM spaces WHERE code = 'WODBY_TEST'")" == 1 ]]
echo "OK"

echo -n "Checking a restart keeps data, keys and the admin password... "
keys_before="$(docker exec "${app}" cat /data/.wodby/keys.env | sha256sum)"
docker stop -t 120 "${app}" >/dev/null
[[ "$(docker inspect -f '{{.State.ExitCode}}' "${app}")" == 0 ]]
docker rm "${app}" >/dev/null
start_app
wait_running
[[ "$(docker exec "${app}" cat /data/.wodby/keys.env | sha256sum)" == "${keys_before}" ]]
token="$(login "${admin_password}")"
[[ -n "${token}" ]]
[[ "$(docker exec "${pg}" psql -tA -U postgres -d app_dev -c "SELECT count(*) FROM spaces WHERE code = 'WODBY_TEST'")" == 1 ]]
echo "OK"

echo -n "Checking the container stops when a server dies... "
docker exec "${app}" sh -c 'kill -9 "$(cat /home/openbis/servers/afs-server/afs_server.pid)"'
for i in $(seq 1 30); do
    [[ "$(docker inspect -f '{{.State.Running}}' "${app}")" == false ]] && break
    sleep 2
done
[[ "$(docker inspect -f '{{.State.Running}}' "${app}")" == false ]]
[[ "$(docker inspect -f '{{.State.ExitCode}}' "${app}")" != 0 ]]
echo "OK"
