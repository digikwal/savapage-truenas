# SavaPage for TrueNAS SCALE

Production-oriented packaging for [SavaPage](https://www.savapage.org/) with
local CUPS, PostgreSQL, optional AirPrint discovery, and optional USB devices.
It includes a standalone Docker Compose deployment and the image consumed by
the TrueNAS Community App in `truenas/apps`.

This is a community project. It is not an official SavaPage, Datraverse,
TrueNAS, or iXsystems product. PostgreSQL is the production default. Network
printers are preferred over USB printers.

Important operational facts:

- Back up `/opt/savapage/server/data/encryption.properties`. Losing it can
  make encrypted database values and document signatures unusable.
- Do not directly share CUPS queues to bypass SavaPage.
- AirPrint uses host-network mDNS discovery and can conflict with TrueNAS.
  Cross-VLAN discovery normally needs an mDNS reflector.
- USB is optional, host-coupled, and identifiers can change after reconnects.
- TrueNAS maintenance or reboot interrupts printing and SavaPage.
- The official SavaPage installer is x86-64 only; this image is amd64 only.

## Quick start with Docker Compose

```sh
cp .env.example .env
chmod 600 .env
# Set POSTGRES_PASSWORD in .env.
docker compose build
docker compose up -d
docker compose ps
```

The defaults bind HTTP/HTTPS to `127.0.0.1`. Set `SAVAPAGE_BIND_IP` to a
specific LAN address when clients need direct access. Open
`https://HOST:8632/admin`; the initial upstream login is `admin` / `admin` and
must be changed immediately.

Optional modes:

```sh
# RAW and CUPS admin ports (also enable and secure them in .env)
docker compose -f compose.yaml -f compose.advanced-ports.yaml up -d

# AirPrint discovery sidecar; set AIRPRINT_HOSTNAME first
docker compose -f compose.yaml -f compose.host-network.yaml up -d

# PAM setuid mode (advanced security exception)
docker compose -f compose.yaml -f compose.pam.yaml up -d
```

Operational documentation:

- [Installation](docs/INSTALL.md)
- [Configuration](docs/CONFIGURATION.md)
- [Networking and AirPrint](docs/NETWORKING.md)
- [USB printers](docs/USB_PRINTERS.md)
- [Backup and restore](docs/BACKUP_RESTORE.md)
- [Upgrades and rollback](docs/UPGRADING.md)
- [Security and licensing](docs/SECURITY.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Research](docs/RESEARCH.md)

## Backup and restore

```sh
scripts/backup.sh /secure/backup/location
RESTORE_CONFIRM=restore scripts/restore.sh /secure/backup/location/savapage-TIMESTAMP
```

See the backup guide before relying on snapshots or performing an upgrade.

## Uninstall without deleting data

Stop/remove containers without `--volumes`:

```sh
docker compose down
```

On TrueNAS, uninstall the application without selecting the dataset deletion
option. Record the app configuration and dataset paths first.
