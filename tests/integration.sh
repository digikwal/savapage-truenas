#!/bin/sh
set -eu

project=savapage-ci
export COMPOSE_PROJECT_NAME=${project}
export POSTGRES_PASSWORD=ci-only-password
export POSTGRES_USER=savapage
export POSTGRES_DB=savapage
export SAVAPAGE_IMAGE=savapage-truenas:test
export SAVAPAGE_HTTP_HOST_PORT=18631
export SAVAPAGE_HTTPS_HOST_PORT=18632
export SAVAPAGE_LOCAL_HTTPS_HOST_PORT=18633

cleanup() {
    docker compose -f compose.yaml -f compose.test.yaml down --volumes --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM
cleanup

docker compose -f compose.yaml -f compose.test.yaml up -d --no-build --wait --wait-timeout 600
key_before=$(docker compose exec -T savapage sha256sum /opt/savapage/server/data/encryption.properties | awk '{print $1}')
test -n "${key_before}"
docker compose exec -T postgres psql -U savapage -d savapage -Atc 'select count(*) from tbl_config' | grep -Eq '^[1-9][0-9]*$'

docker compose restart savapage
docker compose up -d --wait --wait-timeout 600
key_after=$(docker compose exec -T savapage sha256sum /opt/savapage/server/data/encryption.properties | awk '{print $1}')
test "${key_before}" = "${key_after}"

tests/test-virtual-printer.sh
docker compose logs --no-color | grep -Fq "${POSTGRES_PASSWORD}" && {
    echo 'Database password appeared in logs' >&2
    exit 1
}

backup_root=$(mktemp -d)
scripts/backup.sh "${backup_root}"
test -s "$(find "${backup_root}" -name postgres.dump -print -quit)"

# Validation must reject AirPrint without host networking before contacting DB.
if docker run --rm \
    -e SAVAPAGE_DB_HOST=missing -e SAVAPAGE_DB_PORT=5432 \
    -e SAVAPAGE_DB_NAME=savapage -e SAVAPAGE_DB_USER=savapage \
    -e SAVAPAGE_DB_PASSWORD=not-secret -e SAVAPAGE_DB_POOL_MAX=20 \
    -e SAVAPAGE_HTTP_PORT=8631 -e SAVAPAGE_HTTPS_PORT=8632 \
    -e SAVAPAGE_LOCAL_HTTPS_PORT=8633 -e SAVAPAGE_RAW_PORT=9100 \
    -e CUPS_MAX_JOBS=500 -e ENABLE_AIRPRINT=true -e HOST_NETWORK=false \
    savapage-truenas:test >/dev/null 2>&1; then
    echo 'Invalid AirPrint bridge configuration unexpectedly started' >&2
    exit 1
fi

