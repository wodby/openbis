# openBIS Docker image

[![Build Status](https://github.com/wodby/openbis/workflows/Build%20docker%20image/badge.svg)](https://github.com/wodby/openbis/actions)
[![Docker Pulls](https://img.shields.io/docker/pulls/wodby/openbis.svg)](https://hub.docker.com/r/wodby/openbis)
[![Docker Stars](https://img.shields.io/docker/stars/wodby/openbis.svg)](https://hub.docker.com/r/wodby/openbis)

[openBIS](https://openbis.ch) lab notebook and inventory manager for Kubernetes, based on the
[official image](https://hub.docker.com/r/openbis/openbis-app). It runs the application server, the data store server
and the file server in one container, against PostgreSQL databases that already exist and belong to a user without
superuser rights.

- [Tags](#tags)
- [Environment variables](#environment-variables)
- [Databases](#databases)
- [Volume](#volume)
- [Ports](#ports)
- [What differs from the official image](#what-differs-from-the-official-image)
- [Deployment](#deployment)

## Tags

| Tag   | openBIS | Base image                       |
|-------|---------|----------------------------------|
| `7.0` | 7.0.0   | `openbis/openbis-app:7.0.0`      |

Every tag is published for `linux/amd64` and `linux/arm64`. Releases add `<version>-r<N>` tags, such as `7.0-r0`.

## Environment variables

| Variable                          | Default                  | Description |
|-----------------------------------|--------------------------|-------------|
| `OPENBIS_ADMIN_PASSWORD`          |                          | Required. Password of the openBIS user `admin`, set on every start |
| `OPENBIS_HOST`                    | `$WODBY_PRIMARY_HOST`    | Required unless `WODBY_PRIMARY_HOST` is set. Public host name, optionally with a port |
| `OPENBIS_PUBLIC_SCHEME`           | `https`                  | Scheme of the public address |
| `OPENBIS_DB_HOST`                 |                          | Required. PostgreSQL host |
| `OPENBIS_DB_PORT`                 | `5432`                   | PostgreSQL port |
| `OPENBIS_DB_NAME`                 |                          | Required. Main database |
| `OPENBIS_DB_MESSAGES_NAME`        |                          | Required. Messages database, named `<basic>_<kind>` |
| `OPENBIS_DB_PATHINFO_NAME`        |                          | Required. Path info database, named `<basic>_<kind>` |
| `OPENBIS_DB_USER`                 |                          | Required. Owner of the three databases |
| `OPENBIS_DB_PASSWORD`             |                          | Required. Its password |
| `SMTP_HOST`                       |                          | SMTP server for email; email is not sent without it |
| `SMTP_PORT`                       | `25`                     | SMTP port |
| `SMTP_USER`, `SMTP_PASSWORD`      |                          | SMTP credentials, if the server needs them |
| `OPENBIS_MAIL_FROM`               | `noreply@<public host>`  | Sender address |
| `OPENBIS_AS_MAX_RAM_PERCENTAGE`   | `45`                     | Java heap of the application server, in percent of the container's memory limit |
| `OPENBIS_DSS_MAX_RAM_PERCENTAGE`  | `12`                     | Java heap of the data store server |
| `OPENBIS_AFS_MAX_RAM_PERCENTAGE`  | `12`                     | Java heap of the file server |
| `OPENBIS_START_TIMEOUT`           | `1800`                   | Seconds each server may take to start |

## Databases

openBIS needs three PostgreSQL databases owned by one user: the main database, a messages database and a path info
database. The user needs no superuser, create-role or create-database rights. On the first start the image marks each
empty database so openBIS creates its schema there as that user; it refuses a database that has tables but no openBIS
version log.

The server must allow prepared transactions (`max_prepared_transactions` above 0). openBIS commits changes that span
its application server and file server with PostgreSQL's two-phase commit, and those fail without it. The image logs a
warning when the server has them off.

openBIS also opens an administrative connection without a database name, which PostgreSQL connects to the database
named after the user. That database must exist and accept the user; the image stops with an error otherwise. Wodby
names the main database and its user alike.

## Volume

Everything that must survive a restart is on `/data`:

- `/data/openbis`: the store, uploaded files, session workspaces and transaction logs.
- `/data/etc`: configuration of the three servers. It is rendered from the image's defaults on every start; user
  passwords (`/data/etc/as/passwd`) and openBIS's own version markers are kept. Put your own properties into
  `/data/etc/<as|dss|afs>/service.properties.local`; they are appended to the server's `service.properties`, and later
  lines win.
- `/data/.wodby`: keys generated on the first start (transaction keys and the passwords the servers use to sign in to
  each other) and the personal access tokens.

The image runs as `openbis` (uid and gid 1001); the volume must be writable by it.

## Ports

| Port | Server                                 | Path                |
|------|----------------------------------------|---------------------|
| 8080 | Application server and lab notebook    | `/openbis`          |
| 8081 | Data store server                      | `/datastore_server` |
| 8085 | File server                            | `/afs-server`       |

Put a reverse proxy in front that routes the three paths and terminates TLS. The lab notebook is at
`/openbis/webapp/eln-lims/`. The RO-Crate and SFTP servers of the official image are not started.

## What differs from the official image

- Its own start script runs as `openbis` instead of root and exits as soon as one of the three Java servers stops.
- Databases are named as given instead of `openbis_prod`, `messages_prod` and `pathinfo_prod`.
- openBIS does not create the `openbis_readonly` role or grant it access, which needs superuser rights.
- Every installation generates its own transaction keys and server passwords instead of the defaults shipped in the
  official image.
- Public addresses come from `OPENBIS_HOST` or `WODBY_PRIMARY_HOST`; servers reach each other on `localhost`.

## Deployment

Deploy openBIS on your own server or Kubernetes cluster with [Wodby](https://wodby.com).
