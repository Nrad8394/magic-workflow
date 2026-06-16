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
errors.

## Why `magic.test` and not `magic.localhost`?

The local default base domain is **`magic.test`**, not `.localhost`, on purpose.
`curl` and PHP's HTTP client hardcode any `*.localhost` name to the loopback
address (RFC 6761), ignoring Docker's DNS. That breaks **server-side** calls
between containers (Nextcloud → Collabora/Keycloak resolve to the container's own
loopback instead of the proxy). `.test` is also reserved for local use but is
**not** loopback-pinned, so the proxy's network aliases resolve correctly inside
the containers. Use a real domain in production.

## "Could not reach the OpenID Connect provider" (or Office won't open)

Two server-side causes, both handled by `make configure` (and `make up`):

1. **SSRF protection** — Nextcloud blocks its HTTP client from reaching
   private/local IPs. Our services resolve to the internal Docker network, so
   the OIDC discovery and Collabora WOPI calls raise
   `LocalServerException: ... violates local access rules`. Fix:
   ```bash
   make occ CMD="config:system:set allow_local_remote_servers --value=true --type=boolean"
   ```
2. **Self-signed cert** — Nextcloud's HTTP client verifies TLS using its own
   bundle; import the edge cert:
   ```bash
   make occ CMD="security:certificates:import /magic-ca.pem"
   ```

Verify Nextcloud can actually reach Keycloak (should print `OK http=200`):
```bash
docker compose cp scripts/_oidc-test.php nextcloud-app:/tmp/t.php
docker compose exec -u www-data nextcloud-app php /tmp/t.php
```
`make doctor` checks both settings and that the login endpoint returns a 30x
redirect to Keycloak.

## App store unreachable / `app:install ... not found on the appstore`

Some networks block `apps.nextcloud.com` (e.g. SNI-based filtering — the TLS
connection is reset even though general internet works). That breaks
`occ app:install` for **every** app.

This suite works around it: the required apps (`user_oidc`, `richdocuments`) are
installed **from GitHub** automatically on Nextcloud start, and via:

```bash
make nc-apps          # (re)install user_oidc + richdocuments from GitHub
```

GitHub must be reachable from the Nextcloud container (it usually is even when
the app store isn't). To confirm the block is SNI-based:

```bash
# connects, then TLS resets -> middlebox filtering that hostname
echo | openssl s_client -connect apps.nextcloud.com:443 -servername apps.nextcloud.com
```

Workarounds for full app-store access: a VPN, or a different network.

## "office.<domain> just shows OK / isn't an app"

Expected — Collabora is a **backend**, not a page you browse. You edit documents
**inside Nextcloud**. `richdocuments` auto-installs on start; then connect it:

```bash
make office-connect      # points Nextcloud Office at Collabora
```

The edge proxy has internal network aliases so Nextcloud ↔ Collabora resolve
each other's hostnames on a single host. The admin console (basic-auth with
`COLLABORA_USERNAME`/`PASSWORD`) is at `…/browser/dist/admin/admin.html`.

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
