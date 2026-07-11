#!/bin/bash
set -eu
set -o pipefail

readonly server_home=/opt/savapage/server
readonly pid_file=${server_home}/logs/service.pid

test -s "${pid_file}"
pid=$(cat "${pid_file}")
test -d "/proc/${pid}"
grep -aq 'org.savapage.server.WebServer' "/proc/${pid}/cmdline"

test -s "${server_home}/logs/server.started.txt"

if test "${ENABLE_HTTP:-true}" = true; then
    curl --fail --silent --show-error --max-time 10 --output /dev/null \
        "http://127.0.0.1:${SAVAPAGE_HTTP_PORT:-8631}/"
else
    curl --insecure --fail --silent --show-error --max-time 10 --output /dev/null \
        "https://127.0.0.1:${SAVAPAGE_HTTPS_PORT:-8632}/"
fi

PGPASSWORD=${SAVAPAGE_DB_PASSWORD:?} pg_isready --quiet \
    --host "${SAVAPAGE_DB_HOST:?}" --port "${SAVAPAGE_DB_PORT:-5432}" \
    --username "${SAVAPAGE_DB_USER:?}" --dbname "${SAVAPAGE_DB_NAME:?}"

/usr/local/bin/healthcheck-cups
