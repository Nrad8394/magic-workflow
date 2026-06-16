# Architecture

## Topology

```
                          ┌──────────── nginx edge (TLS, routes by hostname) ───────────┐
   users ── https ──▶     │   cloud.· / chat.· / office.· / id.· / s3.· / grafana.·     │
                          └───┬──────────┬───────────┬───────────┬──────────┬───────────┘
                       Nextcloud    Mattermost   Collabora    Keycloak    Grafana
                      (web+fpm+cron)  (app)        (CODE)       (SSO)     (monitoring)
                            │             │            │           │
                            └─────────────┼────────────┼───────────┘
                                          │            │
                         ┌────────────────┴───┐   ┌────┴───────────────┐
                         │ PostgreSQL          │   │ MinIO (S3)         │
                         │  nextcloud /        │   │  nextcloud bucket  │
                         │  mattermost /       │   │  mattermost bucket │
                         │  keycloak DBs       │   └────────────────────┘
                         └─────────────────────┘   Redis (cache + NC file locking)
```

## Networks

Two Docker bridge networks isolate concerns:

- **`edge`** — only the proxy is attached on the public side.
- **`internal`** — every service; not published to the host except via the proxy.

Only the **proxy** publishes ports (80/443). Nothing else is reachable from
outside the Docker network — Postgres, Redis, MinIO, Keycloak, the apps are all
internal-only.

## Request flow

1. Browser hits `https://cloud.example.com` → **nginx edge** (TLS termination).
2. The edge matches `server_name` and reverse-proxies to the internal service
   (`nextcloud-web`, `mattermost`, `collabora`, `keycloak`, …).
3. For Nextcloud, `nextcloud-web` (nginx) serves static assets and forwards PHP
   to `nextcloud-app` (FPM). Files read/write to **MinIO**; metadata to
   **PostgreSQL**; cache/locks to **Redis**.

Hostname routing is templated: the edge uses the official nginx image's
`envsubst` template mechanism, restricted to `*_HOST` variables so nginx's own
`$host`/`$scheme` are preserved.

## Shared backends

### PostgreSQL (one instance, many databases)
`config/postgres/init-databases.sh` runs on first boot and creates a database +
owner role for `nextcloud`, `mattermost` and `keycloak`. For large deployments,
point each app at a managed Postgres instead (see [Enterprise](enterprise.md)).

### Redis
Shared, password-protected. Nextcloud uses it for the distributed cache **and**
transactional file locking.

### MinIO (S3)
One object-storage pool. `scripts/minio-init.sh` creates the `nextcloud` and
`mattermost` buckets plus a single scoped access key both apps use. This is the
heart of "all our data in one cloud" — see [Storage](storage.md).

## Identity

**Keycloak** owns users. The bundled realm (`magicworkflow`) is imported on first
boot with OIDC clients for Nextcloud and Mattermost already created. See
[Single sign-on](sso.md).

## Profiles

| Profile | Services | Start with |
|---------|----------|------------|
| core (default) | proxy, db, redis, minio(+init), keycloak, nextcloud(web/app/cron), mattermost, collabora, homer | `make up` |
| + monitoring/ops | prometheus, grafana, loki, promtail, node-exporter, watchtower, backup | `make up-full` |

## Configuration surface

Everything is driven by **`.env`** (rendered from `.env.example` by `make setup`).
`BASE_DOMAIN` derives every hostname; `TLS_MODE` switches local self-signed vs
production certificates. No service-specific files need editing for a standard
deployment.
