# Troubleshooting

## General

```bash
make status                 # who's up / healthy
make logs-<service>         # proxy | nextcloud | mattermost | keycloak | db
docker compose logs <svc>   # full logs
```

## Proxy / port conflicts

`Bind for 0.0.0.0:80 failed: port is already allocated`

Something else owns 80/443 on the host. Either free it, or set different
`HTTP_PORT`/`HTTPS_PORT` in `.env` and `docker compose up -d proxy`. (Locally you
can use e.g. 8090/8443 and browse `https://host:8443`.)

## A subdomain doesn't resolve

Locally you must add the hosts-file entry `make setup` prints. On a server, the
DNS A-records must exist. Test routing without DNS:

```bash
curl -sk --resolve cloud.example.com:443:<server-ip> https://cloud.example.com/status.php
```

## Keycloak crash-loops

`The '--optimized' flag was used for first ever server start`

The compose uses `start --import-realm` (auto-build). If you customised it back
to `--optimized`, either remove that flag or bake `kc.sh build` into a custom
image. First boot takes ~30 s while it builds.

## Nextcloud "untrusted domain" or wrong URLs

The app is configured with `OVERWRITEHOST` / `OVERWRITEPROTOCOL=https` /
`TRUSTED_PROXIES`. If you changed `BASE_DOMAIN`, re-run `make setup` and
recreate: `docker compose up -d nextcloud-app`. To add a domain:

```bash
make occ CMD="config:system:set trusted_domains 3 --value=cloud.new.example"
```

## Mattermost can't write files / S3 errors

The file store is MinIO. Check `minio-init` completed and the key exists:

```bash
docker compose logs minio-init
docker compose exec minio mc admin user svcacct list local <root-user>
```

## Collabora unhealthy but "Ready to accept connections"

The image has no `curl`/`wget`; the healthcheck uses a bash `/dev/tcp` probe.
The systemplate "read-only" warnings in its log are performance notes, not
errors. Office editing works once Nextcloud's **Nextcloud Office** app points at
`https://office.<domain>`.

## SSO login fails / redirect mismatch

- Verify discovery resolves:
  `curl -sk https://id.<domain>/realms/magicworkflow/.well-known/openid-configuration`
- Redirect URIs in the realm must match the app host exactly (they're derived
  from `BASE_DOMAIN` — re-run `make setup` after changing it).
- Behind the proxy, Keycloak needs `KC_PROXY_HEADERS=xforwarded` + correct
  `KC_HOSTNAME` (both set in compose).

## PostgreSQL won't init on a bind mount

This stack uses **named volumes** for all data, avoiding the Windows `/mnt/c`
`chmod` issue. If you switched to host bind mounts on `/mnt/c`, Postgres
`initdb` will fail — revert to named volumes or run from a Linux-native path.

## Reset everything (DESTRUCTIVE)

```bash
make down-volumes     # deletes DBs, files, object storage — asks to confirm
make setup            # fresh secrets/cert/realm (or keep existing .env)
make up
```

## Getting help

- Nextcloud: <https://docs.nextcloud.com> · Mattermost: <https://docs.mattermost.com>
- Keycloak: <https://www.keycloak.org/documentation> · MinIO: <https://min.io/docs>
- Collabora: <https://sdk.collaboraonline.com>
