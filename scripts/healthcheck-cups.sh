#!/bin/sh
set -eu

for path in /var/lib/cups /var/cache/cups /var/spool/cups; do
    if ! test -d "${path}" || ! test -w "${path}"; then
        echo "CUPS state path is not writable: ${path}" >&2
        exit 1
    fi
done

lpstat -r 2>/dev/null | grep -q 'scheduler is running'
ipptool -q ipp://127.0.0.1:631/ get-system-attributes.test >/dev/null 2>&1 \
    || curl --fail --silent --show-error --output /dev/null http://127.0.0.1:631/
