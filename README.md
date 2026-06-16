# Magic Workflow

**A production-ready, self-hosted collaboration suite for organisations.**
One command brings up files, chat, online office, single sign-on, object
storage and monitoring — all behind one TLS reverse proxy, all your data on
infrastructure you control.

```
                          ┌──────────── nginx edge (TLS, routes by hostname) ───────────┐
   users ── https ──▶     │   cloud.· / chat.· / office.· / id.· / s3.· / grafana.·     │
                          └───┬──────────┬───────────┬───────────┬──────────┬───────────┘
                       Nextcloud    Mattermost   Collabora    Keycloak    Grafana
                       (files)       (chat)       (office)     (SSO)     (monitoring)
                            └─────────┬──────────────┬──────────┬─────────┘
                              PostgreSQL (multi-db)  Redis    MinIO (S3 — shared
                                                              object storage for
                                                              Nextcloud + Mattermost)
```

| Capability            | Component                         |
|-----------------------|-----------------------------------|
| Files / calendar / contacts | **Nextcloud** (FPM)          |
| Online office editing | **Collabora Online**              |
| Team chat / calls     | **Mattermost**                    |
| Single sign-on        | **Keycloak** (OIDC for both apps) |
| Object storage        | **MinIO** (one S3 pool for all)   |
| Database / cache      | **PostgreSQL** (multi-db) + **Redis** |
| Edge / TLS            | **nginx** reverse proxy           |
| Monitoring            | **Prometheus + Grafana + Loki**   |
| Ops                   | nightly **backups** + **Watchtower** + **Homer** dashboard |

Full documentation: [`MagicWorkflow_Docs/`](MagicWorkflow_Docs/) (MkDocs site).

---

## Quick start (local)

> Prereqs: Docker Engine 24+ & Compose v2, `openssl`, `make`. On Windows use
> Docker Desktop (WSL2) and run from inside WSL.

```bash
make setup        # .env + strong random secrets + Keycloak realm + self-signed TLS
```

Add the printed line to your hosts file so the subdomains resolve locally:

```
127.0.0.1  cloud.magic.localhost chat.magic.localhost office.magic.localhost \
           id.magic.localhost grafana.magic.localhost dash.magic.localhost s3.magic.localhost
```

Then:

```bash
make up           # start the core suite
make urls         # print every URL + admin login
make health       # probe each service
```

Open the dashboard at **https://dash.magic.localhost** (accept the self-signed
cert warning). First boot pulls images + installs — give it a few minutes;
watch with `make logs`.

Add monitoring + backups + auto-update:

```bash
make up-full      # core + Prometheus/Grafana/Loki + nightly backups + Watchtower
```

---

## Production (server)

1. Point real DNS A-records at the server for each subdomain
   (`cloud.`, `chat.`, `office.`, `id.`, `s3.`, `grafana.`, `dash.`).
2. Edit `.env`: set `BASE_DOMAIN=yourcompany.com`, `TLS_MODE=letsencrypt`,
   `ACME_EMAIL=...`, and review every secret.
3. `make setup` (regenerates hostnames + realm), then provision real TLS certs
   into `config/proxy/tls/` (see the docs → *Install on a server*).
4. `make up-full`.

See [`MagicWorkflow_Docs`](MagicWorkflow_Docs/) → **Install on a server**,
**Single sign-on**, **Backups & restore**, **Operations** for the full runbook.

---

## Single sign-on

Keycloak ships pre-loaded with a realm + OIDC clients for Nextcloud and
Mattermost. After the stack is up:

```bash
make sso-info     # prints the exact occ / System Console steps + secrets
```

---

## Common commands

```bash
make            # list every target
make status     # container health
make logs-nextcloud / logs-mattermost / logs-keycloak
make occ CMD="status"            # Nextcloud admin CLI
make mmctl CMD="user list"       # Mattermost admin CLI
make backup                      # on-demand DB backup
make down                        # stop (keep data)
make down-volumes                # stop + DELETE all data (asks to confirm)
```

---

## Data & storage

Everything lives in named Docker volumes — portable across Linux/macOS/Windows:

- **MinIO** (`minio_data`) is the single object store: Nextcloud primary storage
  *and* Mattermost's file store both write here. One storage pool to back up.
- **PostgreSQL** (`db_data`) holds the `nextcloud`, `mattermost` and `keycloak`
  databases (created automatically on first boot).
- Nextcloud app code (`nextcloud_app`), Mattermost config/plugins, Redis, and
  monitoring data each have their own volume.

`make backup` dumps all databases; back up the `minio_data` volume for files.

---

## Why this layout

- **One identity** (Keycloak) → one login across every app.
- **One object store** (MinIO) → all user files in a single S3 pool you control.
- **One edge** (nginx) → one place for TLS, one set of ports (80/443).
- **Profiles** → run lean (`core`) or full (`core + monitoring + ops`).
- **`.env`-driven** → the same compose runs locally and on a server; flip
  `BASE_DOMAIN` + `TLS_MODE` to go to production.
