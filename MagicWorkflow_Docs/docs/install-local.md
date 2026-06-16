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
`BASE_DOMAIN` (default `magic.test`), renders the Keycloak realm, and
generates a self-signed wildcard TLS certificate.

## 3. Hosts file

The subdomains must resolve to your machine. `make setup` prints the exact line;
add it to your hosts file:

=== "Linux / macOS / WSL"
    `/etc/hosts`:
    ```
    127.0.0.1  cloud.magic.test chat.magic.test office.magic.test id.magic.test grafana.magic.test dash.magic.test s3.magic.test
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

- Dashboard: **https://dash.magic.test**
- Nextcloud: **https://cloud.magic.test**
- Mattermost: **https://chat.magic.test** (first account becomes admin)
- Keycloak: **https://id.magic.test**

!!! warning "Self-signed certificate"
    Your browser will warn about the local cert — that's expected. Accept it to
    continue. Production uses real certificates (see
    [Install on a server](install-server.md)).

## 6. SSO + Office are already wired

Nothing to do — on `make up` the suite auto-installs the required Nextcloud apps
(`user_oidc`, `richdocuments`) from GitHub and the one-shot
`nextcloud-configure` service registers Keycloak SSO and connects Nextcloud
Office to Collabora. Log in to Nextcloud and you'll see **Log in with Keycloak**;
open a document to edit it with Collabora.

Re-run any piece manually if needed:

```bash
make nc-apps         # reinstall user_oidc + richdocuments from GitHub
make sso-connect     # re-register Keycloak login in Nextcloud
make office-connect  # re-point Nextcloud Office at Collabora
```

For **Mattermost** SSO (a System Console step), see:

```bash
make sso-info        # endpoints + secrets + the Mattermost steps
```

## 7. Tear down

```bash
make down            # stop, keep data
make down-volumes    # stop + delete ALL data (asks to confirm)
```
