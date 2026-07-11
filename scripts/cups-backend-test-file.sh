#!/bin/sh
set -eu

readonly output=/tmp/savapage-ci-output.prn

if test "$#" -eq 0; then
    printf '%s\n' 'direct savapage-ci-file "Unknown" "SavaPage CI file printer"'
    exit 0
fi

# CUPS intentionally sanitizes backend environments, so activation is
# controlled by creating the CI-only queue. The backend itself only permits
# this one harmless tmpfs destination.
test "${DEVICE_URI:-}" = "savapage-ci-file:${output}" || {
    echo 'Test file backend refused an unexpected output path' >&2
    exit 1
}

if test "$#" -ge 6; then
    cp "$6" "${output}"
else
    cat > "${output}"
fi
