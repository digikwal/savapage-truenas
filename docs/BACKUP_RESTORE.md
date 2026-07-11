# Backup and restore

An application-consistent backup coordinates a PostgreSQL logical dump with a
file archive. Stop user printing or place SavaPage in maintenance mode first:

```sh
scripts/backup.sh /secure/backups
```

The bundle contains `pg_dump` custom format, SavaPage data/logs, CUPS config,
`printers.conf`, `/var/cache/cups` job-ID state, spool metadata, image metadata,
and redacted Compose configuration. The script fails if
`encryption.properties` is absent. Store the bundle encrypted and separately
from the NAS.

A ZFS snapshot taken while containers run is only crash-consistent across
independent datasets. An application-consistent snapshot requires quiescing
SavaPage and PostgreSQL or combining a logical database dump with filesystem
snapshots. Snapshot the single parent dataset atomically where possible.

Restore into clean volumes/datasets with the same or newer compatible image:

```sh
RESTORE_CONFIRM=restore scripts/restore.sh /secure/backups/savapage-TIMESTAMP
```

Then verify:

1. PostgreSQL reports no recovery/schema errors and SavaPage is healthy.
2. Admin login works.
3. The restored `encryption.properties` checksum matches the backup.
4. Encrypted secrets, user data, and document metadata are readable.
5. CUPS queues and job history exist.
6. A test page completes and its status reaches SavaPage.

For TrueNAS also export/record the app configuration, image digest, app
version, and every dataset path.

