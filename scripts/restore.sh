#!/bin/sh
set -eu

backup_dir=${1:?Usage: RESTORE_CONFIRM=restore scripts/restore.sh BACKUP_DIRECTORY}
compose=${COMPOSE_FILE:-compose.yaml}
test "${RESTORE_CONFIRM:-}" = restore || {
    echo 'Set RESTORE_CONFIRM=restore to acknowledge destructive replacement of the clean target deployment.' >&2
    exit 1
}
test -s "${backup_dir}/postgres.dump"
test -s "${backup_dir}/files.tar.gz"

(cd "${backup_dir}" && sha256sum -c SHA256SUMS)

docker compose -f "${compose}" down
docker compose -f "${compose}" up -d postgres
until docker compose -f "${compose}" exec -T postgres \
    pg_isready --quiet --username "${POSTGRES_USER:-savapage}" --dbname "${POSTGRES_DB:-savapage}"; do
    sleep 1
done

docker compose -f "${compose}" exec -T postgres \
    dropdb --if-exists --force --username "${POSTGRES_USER:-savapage}" "${POSTGRES_DB:-savapage}"
docker compose -f "${compose}" exec -T postgres \
    createdb --username "${POSTGRES_USER:-savapage}" --owner "${POSTGRES_USER:-savapage}" "${POSTGRES_DB:-savapage}"
docker compose -f "${compose}" exec -T postgres \
    pg_restore --no-owner --no-acl --exit-on-error \
    --username "${POSTGRES_USER:-savapage}" --dbname "${POSTGRES_DB:-savapage}" \
    < "${backup_dir}/postgres.dump"

docker compose -f "${compose}" run --rm --no-deps --entrypoint tar savapage \
    --extract --gzip --directory / --preserve-permissions \
    < "${backup_dir}/files.tar.gz"
docker compose -f "${compose}" up -d

printf '%s\n' 'Restore submitted. Complete the verification checklist in docs/BACKUP_RESTORE.md.'

