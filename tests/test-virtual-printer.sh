#!/bin/sh
set -eu

compose_files='-f compose.yaml -f compose.test.yaml'
queue=savapage-ci-file
output=/tmp/savapage-ci-output.prn

# Remove a prior CI queue without touching administrator-managed queues.
# shellcheck disable=SC2086
docker compose ${compose_files} exec -T savapage lpadmin -x "${queue}" 2>/dev/null || true
# shellcheck disable=SC2086 # Deliberate Compose file argument list.
docker compose ${compose_files} exec -T savapage \
    lpadmin -p "${queue}" -E -v "savapage-ci-file:${output}" -m raw
# SavaPage requires proxy candidates to be shared locally, while Browsing Off
# and the CUPS policy prevent LAN bypass.
# shellcheck disable=SC2086
docker compose ${compose_files} exec -T savapage lpadmin -p "${queue}" -o printer-is-shared=true
# shellcheck disable=SC2086
job=$(docker compose ${compose_files} exec -T savapage \
    lp -d "${queue}" /usr/share/cups/data/testprint | sed -n 's/^request id is \([^ ]*\).*/\1/p')
test -n "${job}"

attempt=0
while :; do
    # shellcheck disable=SC2086
    state=$(docker compose ${compose_files} exec -T savapage lpstat -W completed -o "${queue}" || true)
    printf '%s\n' "${state}" | grep -q "${job}" && break
    attempt=$((attempt + 1))
    test "${attempt}" -lt 30 || {
        echo "Virtual CUPS job did not complete: ${job}" >&2
        exit 1
    }
    sleep 1
done

# shellcheck disable=SC2086
docker compose ${compose_files} exec -T savapage test -s "${output}"
printf 'Virtual CUPS job completed and history was preserved: %s\n' "${job}"
