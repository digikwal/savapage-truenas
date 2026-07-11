# Upgrading and rollback

Never change the PostgreSQL major version casually. Read SavaPage release notes,
record image digests, and create/test a full backup first.

```sh
scripts/backup.sh /secure/backups
docker compose pull
docker compose up -d
docker compose ps
```

The image contains the target over-the-top SavaPage installation while the
persistent data/configuration is retained. On an image-version change the
entrypoint creates a critical-configuration archive before starting. SavaPage's
schema logic runs once; downgrades are refused.

Rollback is not “start the old image against a migrated database.” Stop the
deployment, restore the pre-upgrade PostgreSQL dump and SavaPage/CUPS datasets,
pin the previous image digest, and start it. Verify encryption keys, queues,
login, and a test job. Retain the failed deployment and logs for diagnosis.

TrueNAS app configuration migrations and PostgreSQL major upgrades are separate
operations. Snapshot/backup before either and never suppress migration errors.

