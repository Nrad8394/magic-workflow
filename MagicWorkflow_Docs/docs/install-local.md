# Install locally

Run the whole suite on your laptop to evaluate it.

## 1. Prerequisites

- Docker Engine 24+ and Compose v2 (`docker compose version`)
- `openssl`, `make`, `envsubst` (gettext)
- 8 GB RAM free
- On Windows: Docker Desktop (WSL2 backend); run everything **inside WSL**.

## 2. Bootstrap

```bash
make setup
```

This creates `.env` with **strong random secrets**, derives all hostnames from
`BASE_DOMAIN` (default `magic.localhost`), renders the Keycloak realm, and
generates a self-signed wildcard TLS certificate.

## 3. Hosts file

The subdomains must resolve to your machine. `make setup` prints the exact line;
add it to your hosts file:

=== "Linux / macOS / WSL"
    `/etc/hosts`:
    ```
    127.0.0.1  cloud.magic.localhost chat.magic.localhost office.magic.localhost id.magic.localhost grafana.magic.localhost dash.magic.localhost s3.magic.localhost
    ```

=== "Windows"
    `C:\Windows\System32\drivers\etc\hosts` (edit as Administrator) — same line.

## 4. Start

```bash
make up           # core suite
# ...or the full stack with monitoring + backups:
make up-full
```

First boot pulls images (Collabora alone is large) and runs installers — allow
a few minutes. Watch progress:

```bash
make logs
make status       # until everything is healthy
make health       # per-service probe
```

## 5. Open it

```bash
make urls         # prints every URL + admin login
```

- Dashboard: **https://dash.magic.localhost**
- Nextcloud: **https://cloud.magic.localhost**
- Mattermost: **https://chat.magic.localhost** (first account becomes admin)
- Keycloak: **https://id.magic.localhost**

!!! warning "Self-signed certificate"
    Your browser will warn about the local cert — that's expected. Accept it to
    continue. Production uses real certificates (see
    [Install on a server](install-server.md)).

## 6. Wire single sign-on (optional but recommended)

```bash
make sso-info     # prints the exact steps + secrets
```

## 7. Tear down

```bash
make down            # stop, keep data
make down-volumes    # stop + delete ALL data (asks to confirm)
```
