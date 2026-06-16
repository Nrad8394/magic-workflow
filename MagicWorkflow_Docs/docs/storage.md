# Storage (MinIO / S3)

Magic Workflow uses **one MinIO object-storage pool** as the single home for all
user files — Nextcloud's primary storage **and** Mattermost's file store both
write to it. This is the "everything in our cloud" design: one pool to scale,
secure and back up.

```
   Nextcloud ──┐                      ┌── bucket: nextcloud   (all NC files)
               ├──▶  MinIO (S3)  ◀────┤
   Mattermost ─┘    (minio_data)      └── bucket: mattermost  (chat attachments)
```

## How it's wired

`scripts/minio-init.sh` runs once on first boot and:

1. creates the `nextcloud` and `mattermost` buckets,
2. creates a single scoped **service account** (`S3_ACCESS_KEY` / `S3_SECRET_KEY`)
   the apps authenticate with.

The apps are configured entirely from `.env`:

- **Nextcloud** → S3 *primary storage* via the `OBJECTSTORE_S3_*` env vars
  (path-style, `minio:9000`).
- **Mattermost** → S3 *file store* via the `MM_FILESETTINGS_AMAZONS3*` env vars.

!!! warning "Set S3 before real data"
    Nextcloud's primary storage must be S3 **from first install** (it is, here).
    Migrating an existing local-disk instance to S3 afterwards is non-trivial.

## Admin console

Browse buckets, usage and access keys at **https://s3.<domain>** with the
`MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` login.

## Capacity & production

- MinIO stores objects on the `minio_data` volume — put that on your largest,
  most durable disk (or a dedicated mount).
- For real scale, run MinIO as an **external, distributed cluster** (erasure
  coding across nodes/disks) and point `OBJECTSTORE_S3_HOST` /
  `MM_FILESETTINGS_AMAZONS3ENDPOINT` at it; then drop the bundled `minio`
  service. Same applies to using **AWS S3 / Wasabi** directly.
- Enable TLS between apps and object storage in production
  (`OBJECTSTORE_S3_SSL=true`, `MM_FILESETTINGS_AMAZONS3SSL=true`) when MinIO is
  reachable over HTTPS.

## Backups

The database captures metadata; **the object store holds the bytes**. Back up
both together — see [Backups & restore](backups.md). For MinIO specifically,
`mc mirror` to a second bucket/site or snapshot the `minio_data` volume.
