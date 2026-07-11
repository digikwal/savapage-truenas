# Installation

## TrueNAS Community catalog

After catalog acceptance, open **Apps**, select **SavaPage**, and complete the
form. Use ixVolumes for a simple installation or one parent dataset with
subdirectories for controlled snapshots. Set a unique database password. Keep
AirPrint, USB, PAM, RAW, and CUPS administration disabled for the first boot.

The image `ghcr.io/digikwal/savapage-truenas:1.6.0` must be published before
catalog installation. Prefer a digest pin after publication.

## TrueNAS Install via YAML

Use the fully rendered Compose output from the TrueNAS app renderer, not the
Jinja template. In the TrueNAS UI choose **Discover Apps → Install via YAML**,
paste the rendered YAML, verify dataset bind paths and secrets, and install.
TrueNAS catalog installations are preferred because they retain UI validation.

## Standalone Compose

Requirements: Docker Engine 24+ with Compose v2, amd64 Linux, 4 GiB RAM, two
CPUs, and persistent storage.

```sh
cp .env.example .env
chmod 600 .env
editor .env
docker compose config --quiet
docker compose build
docker compose up -d
docker compose ps
```

Wait for both services to become healthy. Visit `/admin`, change the initial
admin password, set locale/currency, configure LDAP if applicable, and add/test
CUPS network queues. SavaPage supports IPP/IPPS, AppSocket/JetDirect, LPD, and
driverless IPP Everywhere where the printer supports those protocols.

Do not uninstall with `docker compose down --volumes` unless permanent deletion
is intended.

