#!/bin/sh
set -eu

shellcheck scripts/*.sh tests/*.sh
POSTGRES_PASSWORD=static-test docker compose config --quiet
POSTGRES_PASSWORD=static-test AIRPRINT_HOSTNAME=savapage.local \
    docker compose -f compose.yaml -f compose.host-network.yaml config --quiet
POSTGRES_PASSWORD=static-test \
    docker compose -f compose.yaml -f compose.pam.yaml config --quiet

if docker compose config --quiet >/dev/null 2>&1; then
    echo 'Compose unexpectedly accepted a missing database password' >&2
    exit 1
fi

test "$(grep -c '^FROM .*:.*' Dockerfile)" -ge 2
if grep -R --line-number -E 'image:.*:latest|FROM .*:latest' Dockerfile compose*.yaml; then
    echo 'Mutable latest tag found' >&2
    exit 1
fi
grep -q 'b5c388a35b707946ca8f4264605b6b252c6620769e2e32dbf910425fd381433c' Dockerfile
grep -q 'uses: aquasecurity/trivy-action@v[0-9]' .github/workflows/ci.yml
test "$(grep -c '^  - id: CVE-' .trivyignore.yaml)" -eq 16
test "$(grep -c '^    expired_at: 2026-10-10$' .trivyignore.yaml)" -eq 16
grep -q 'trivyignores: .trivyignore.yaml' .github/workflows/ci.yml
