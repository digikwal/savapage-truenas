#!/bin/sh
set -eu

compose_files='-f compose.yaml -f compose.test.yaml'
queue=savapage-ci-file
ipp_port=18634
ipp_spool=/tmp/savapage-ci-ipp-spool
ipp_pid=/tmp/savapage-ci-ipp.pid

cleanup() {
    # shellcheck disable=SC2086
    docker compose ${compose_files} exec -T savapage sh -c \
        "test ! -f '${ipp_pid}' || kill \"\$(cat '${ipp_pid}')\" 2>/dev/null || true" \
        >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

# Run a local driverless IPP Everywhere printer. This exercises modern CUPS
# queue discovery and job handling without relying on deprecated RAW queues.
# ippeveprinter registers through DNS-SD, so start disposable local D-Bus and
# Avahi daemons for this fixture only; production AirPrint remains optional.
# shellcheck disable=SC2086
docker compose ${compose_files} exec -T savapage sh -c \
    'mkdir -p /run/dbus; dbus-daemon --system --fork; avahi-daemon --daemonize --no-drop-root --no-chroot'
# shellcheck disable=SC2086
docker compose ${compose_files} exec -T savapage sh -c \
    "rm -rf '${ipp_spool}'; mkdir -p '${ipp_spool}'; ippeveprinter --no-web-forms -k -p '${ipp_port}' -d '${ipp_spool}' 'SavaPage CI Printer' > /tmp/savapage-ci-ipp.log 2>&1 & echo \$! > '${ipp_pid}'"

attempt=0
# shellcheck disable=SC2086 # Deliberate Compose file argument list.
until docker compose ${compose_files} exec -T savapage \
    ipptool -t "ipp://127.0.0.1:${ipp_port}/ipp/print" \
    /usr/share/cups/ipptool/get-printer-attributes.test >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    test "${attempt}" -lt 30 || {
        echo 'Virtual IPP Everywhere printer did not become ready' >&2
        # shellcheck disable=SC2086
        docker compose ${compose_files} exec -T savapage cat /tmp/savapage-ci-ipp.log >&2 || true
        exit 1
    }
    sleep 1
done

# Remove a prior CI queue without touching administrator-managed queues.
# shellcheck disable=SC2086
docker compose ${compose_files} exec -T savapage lpadmin -x "${queue}" 2>/dev/null || true
# shellcheck disable=SC2086 # Deliberate Compose file argument list.
docker compose ${compose_files} exec -T savapage \
    lpadmin -p "${queue}" -E -v "ipp://127.0.0.1:${ipp_port}/ipp/print" -m everywhere
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

# ippeveprinter keeps completed job data in its isolated spool with -k.
# shellcheck disable=SC2086
docker compose ${compose_files} exec -T savapage sh -c \
    "find '${ipp_spool}' -type f -size +0c -print -quit | grep -q ."
printf 'Virtual CUPS job completed and history was preserved: %s\n' "${job}"
