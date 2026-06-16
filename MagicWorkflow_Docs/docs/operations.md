# Operations

Day-2 runbook. Every command has a `make` target — run `make` for the list.

## Daily

```bash
make status        # container health
make health        # per-service probe
make logs          # follow everything (or logs-nextcloud / logs-mattermost / ...)
make urls          # links + admin logins
```

## Updating

Bump the relevant `*_IMAGE_TAG` in `.env`, then:

```bash
make backup        # always back up first
make update        # pull + recreate; apps run their own migrations on boot
make logs-nextcloud   # watch the Nextcloud upgrade
```

!!! warning "One major at a time"
    Upgrade Nextcloud **one major version at a time** (32 → 33 → 34). Mattermost
    and Keycloak: read their release notes for breaking changes.

`Watchtower` (ops profile) can auto-update **opt-in** containers (label
`com.centurylinklabs.watchtower.enable=true`). It's off by label by default —
review before enabling auto-update for stateful services in production.

## Nextcloud admin

```bash
make occ CMD="status"
make occ CMD="app:list"
make occ CMD="user:add jane"
make nc-fix                       # recommended DB indices etc. after install/upgrade
make occ CMD="maintenance:mode --on"   # before manual maintenance
```

## Mattermost admin

```bash
make mmctl CMD="user list"
make mmctl CMD="user create --email a@b.com --username admin2 --password 'S3cret!' --system-admin"
make mmctl CMD="channel list <team>"
```

## Scaling guidance

| Bottleneck | Action |
|------------|--------|
| Web/PHP under load | raise Nextcloud FPM `pm.max_children`; add app replicas (needs shared storage — already S3) |
| Database | move to a managed/clustered PostgreSQL; point apps' `*_DB_*` at it and drop the `db` service |
| Object storage | external distributed MinIO or cloud S3 |
| Chat scale | Mattermost Enterprise (HA), S3 file store (already wired) |
| TLS/edge | front the proxy with a load balancer; or move TLS to it |

## Health & restarts

- `restart: unless-stopped` on every service.
- Healthchecks gate `depends_on` so apps wait for ready dependencies.
- Logs are capped (10 MB × 3 per container) to protect host disk.

## Secrets rotation

Rotate a secret in `.env`, then recreate the affected service(s):

```bash
docker compose up -d --force-recreate <service>
```

For DB/OIDC secret changes, update both sides (e.g. realm secret **and** the
app's OIDC config) — `make sso-info` shows the current values.
