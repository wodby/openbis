ARG BASE_IMAGE

FROM ${BASE_IMAGE}

ARG OPENBIS_VER

ENV OPENBIS_VER="${OPENBIS_VER}" \
    OPENBIS_HOME=/home/openbis

USER root

COPY java /usr/src/wodby-openbis/java
COPY build /usr/src/wodby-openbis/build
COPY bin/ /usr/local/bin/

# Changes to the upstream image, each verified so a new upstream release cannot drop one silently:
# - openBIS names databases <basic>_<kind>; NamedDatabaseConfigurationContext takes the application server's two
#   database names as a whole, as Wodby creates them.
# - Without superuser rights openBIS cannot create its read-only group role, so it is neither created nor granted.
# - Configuration is read from /data/etc, where the start script renders it from the image's defaults.
# - The servers log to /var/log/openbis and may take as long as a first start needs.
RUN set -eux; \
    servers="${OPENBIS_HOME}/servers"; \
    webinf="${servers}/openBIS-server/jetty/webapps/openbis/WEB-INF"; \
    javac -nowarn -d "${webinf}/classes" -cp "${webinf}/lib/*" \
        /usr/src/wodby-openbis/java/ch/wodby/openbis/NamedDatabaseConfigurationContext.java; \
    xml="${webinf}/classes/dbConfigurationContext.xml"; \
    python3 -I /usr/src/wodby-openbis/build/patch-db-context.py "${xml}"; \
    grep -rliE '^\s*GRANT .* TO GROUP OPENBIS_READONLY;\s*$' "${webinf}/classes/sql" \
        | xargs sed -i -E '/^\s*GRANT .* TO GROUP OPENBIS_READONLY;\s*$/Id'; \
    if grep -rqiE '^\s*GRANT .*OPENBIS_READONLY' "${webinf}/classes/sql"; then exit 1; fi; \
    for script in \
        "${servers}/openBIS-server/jetty/bin/startup.sh" \
        "${servers}/datastore_server/datastore_server.sh" \
        "${servers}/afs-server/bin/afs_server.sh"; do \
        grep -q '^TIMEOUT=120$' "${script}"; \
        sed -i 's/^TIMEOUT=120$/TIMEOUT="${OPENBIS_START_TIMEOUT:-1800}"/' "${script}"; \
    done; \
    sed -i 's|^STARTUPLOG=.*|STARTUPLOG=log/dss_startup.out|' "${servers}/datastore_server/datastore_server.sh"; \
    sed -i 's|^STARTUP_LOG=.*|STARTUP_LOG=$LOG_FOLDER/afs_startup.out|' "${servers}/afs-server/bin/afs_server.sh"; \
    mkdir -p /data /var/log/openbis; \
    for pair in openBIS-server/jetty:as datastore_server:dss afs-server:afs; do \
        dir="${servers}/${pair%%:*}"; \
        mv "${dir}/etc" "${dir}/etc.default"; \
        ln -s "/data/etc/${pair##*:}" "${dir}/etc"; \
    done; \
    for dir in openBIS-server/jetty datastore_server afs-server; do \
        rm -rf "${servers}/${dir}/log" "${servers}/${dir}/logs"; \
        ln -s /var/log/openbis "${servers}/${dir}/log"; \
        ln -s /var/log/openbis "${servers}/${dir}/logs"; \
    done; \
    rm -rf /data/openbis /data/runtime; \
    chown -R openbis:openbis /data /var/log/openbis "${webinf}/classes/ch"; \
    chown -h openbis:openbis "${webinf}/classes/dbConfigurationContext.xml" "${servers}"/*/etc "${servers}"/*/log* \
        "${servers}"/openBIS-server/jetty/etc "${servers}"/openBIS-server/jetty/log*; \
    find "${OPENBIS_HOME}" -xdev -user root -exec chown -h openbis:openbis {} +; \
    rm -rf /usr/src/wodby-openbis

USER openbis

WORKDIR /home/openbis

EXPOSE 8080 8081 8085

HEALTHCHECK NONE

ENTRYPOINT ["openbis-start"]
