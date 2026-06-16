# Backups & restore

Two things must be backed up **together**: the **databases** (metadata) and the
**object store** (the actual files).

## Automated database backups

The `backup` service (in the monitoring/ops profile) runs `pg_dumpall` on a
schedule into the `backups` volume and prunes dumps older than
`BACKUP_KEEP_DAYS` (default 14).

```bash
make up-full              # starts the backup service (among others)
make backup               # run an on-demand dump now
```

Dumps land as `backups/magicworkflow-all-<date>.sql.gz` and capture **all**
databases (`nextcloud`, `mattermost`, `keycloak`) plus roles in one file.

## Object storage (files)

The database backup does **not** include user files — those live in MinIO. Back
up the object store with either:

=== "Snapshot the volume"
    ```bash
    VOL=$(docker volume ls --format '{{.Name}}' | grep _minio_data$)
    docker run --rm -v $VOL:/data:ro -v "$PWD/backups":/backup alpine \
      tar czf /backup/minio-$(date +%F).tar.gz -C /data .
    ```

=== "Mirror to another site (preferred)"
    ```bash
    # from a host with mc configured for both ends
    mc mirror --overwrite local/nextcloud  remote/nextcloud
    mc mirror --overwrite local/mattermost remote/mattermost
    ```

## Restore

```bash
# 1. Stop apps (keep db + minio)
make stop

# 2. Restore all databases
gunzip -c backups/magicworkflow-all-<date>.sql.gz | \
  docker compose exec -T db psql -U "$POSTGRES_SUPER_USER" -d postgres

# 3. Restore object storage (reverse of whichever method above)

# 4. Start again
make up
```

## Recommended policy

| What | How | Frequency |
|------|-----|-----------|
| Databases | `backup` service (`pg_dumpall`) | nightly, keep 14 days |
| Object store | `mc mirror` to off-site bucket | nightly/continuous |
| Config (`.env`, certs, realm) | store in a secrets manager / encrypted vault | on change |
| Test restores | rehearse on a throwaway host | quarterly |

!!! tip
    Always take a fresh backup **before upgrading** any component.
