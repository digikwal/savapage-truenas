# Troubleshooting

Start with redacted diagnostics:

```sh
docker compose exec savapage savapage-diagnostics
docker compose logs --tail=200 savapage postgres
```

- PostgreSQL unhealthy: verify the password, data ownership, disk space, and
  that the selected major matches the existing data.
- SavaPage reports missing tables: use a clean database or restore a complete
  dump. The entrypoint refuses partial schemas and uses official `db-init` only
  for an empty database.
- CUPS unhealthy: run `lpstat -r`, inspect `/var/log/cups/error_log`, and verify
  `/var/lib/cups`, cache, and spool are writable. Never clear the cache.
- Job status missing: confirm the `savapage` notifier exists, queue is shared
  locally, and CUPS history is preserved.
- AirPrint absent: verify the sidecar, UDP 5353, hostname/ports, VLAN boundary,
  and absence of another host Avahi service.
- USB absent: compare host/container `lsusb`, device path, and permissions.
- HTTPS warning: the first boot uses SavaPage's self-signed certificate; install
  a trusted certificate through supported SavaPage configuration.

