# Install on a server

Production deployment on a single host (VM or bare metal). For clusters see
[Kubernetes](kubernetes.md).

## 1. Provision

- A Linux host (Ubuntu/Debian/RHEL) with Docker Engine 24+ and Compose v2.
- 16 GB RAM+ for a small org; put `minio_data` and `db_data` on durable storage.
- Open inbound **80** and **443** only. Everything else stays internal.

## 2. DNS

Create A/AAAA records pointing each subdomain at the server:

```
cloud.example.com    chat.example.com    office.example.com
id.example.com       s3.example.com      grafana.example.com    dash.example.com
```

(Or a wildcard `*.example.com`.)

## 3. Configure

```bash
git clone <your-fork> magic-workflow && cd magic-workflow
make setup
$EDITOR .env
```

Set at least:

```ini
BASE_DOMAIN=example.com
TLS_MODE=letsencrypt
ACME_EMAIL=ops@example.com
HTTP_PORT=80
HTTPS_PORT=443
```

Re-run `make setup` after changing `BASE_DOMAIN` so hostnames + the Keycloak
realm regenerate. **Review every secret** in `.env` (setup generated strong
random ones; keep them in your secrets manager).

## 4. TLS certificates

`make setup` produces a self-signed cert. For production replace
`config/proxy/tls/fullchain.pem` + `privkey.pem` with real certificates:

=== "Let's Encrypt (certbot, DNS or webroot)"
    ```bash
    # webroot challenge is served by the proxy at /.well-known/acme-challenge/
    certbot certonly --webroot -w /var/www/certbot \
      -d cloud.example.com -d chat.example.com -d office.example.com \
      -d id.example.com -d s3.example.com -d grafana.example.com -d dash.example.com
    # then copy/symlink the fullchain.pem + privkey.pem into config/proxy/tls/
    docker compose restart proxy
    ```
    A wildcard cert (`*.example.com`, DNS-01 challenge) is simplest — one cert
    for every subdomain.

=== "Bring your own"
    Drop your CA-issued `fullchain.pem` + `privkey.pem` into `config/proxy/tls/`
    and `docker compose restart proxy`.

> Automate renewal with a cron job that renews then `docker compose restart proxy`.

## 5. Launch

```bash
make up-full       # core + monitoring + backups + watchtower
make status
make health
make urls
```

## 6. Post-install hardening

- [ ] Confirm only 80/443 are exposed (`ss -tlnp`); firewall the rest.
- [ ] Wire [SSO](sso.md); keep one break-glass local admin per app.
- [ ] Verify [backups](backups.md) run and **test a restore**.
- [ ] Set Nextcloud `make nc-fix`; check Settings → Overview is clean.
- [ ] Configure SMTP in Nextcloud + Mattermost for email.
- [ ] Set MinIO + DB to durable/replicated storage; consider managed services.
- [ ] Review Watchtower auto-update policy (opt-in by label).
- [ ] Document the `.env` secrets in your vault; restrict file perms (`chmod 600 .env`).

See the [Enterprise guide](enterprise.md) for HA, external services and
compliance considerations.
