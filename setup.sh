#!/usr/bin/env bash
# =============================================================================
# Magic Workflow — bootstrap (Linux / WSL / macOS)
#   1. create .env from .env.example (generate strong random secrets)
#   2. derive per-service hostnames from BASE_DOMAIN
#   3. render the Keycloak realm import from its template
#   4. generate a self-signed wildcard TLS cert (local) — replace for production
# Idempotent: re-running keeps existing secrets/cert; pass --force-certs to rotate.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

rand() { openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32; }

echo "==> Magic Workflow setup in $(pwd)"

# ── 1. .env + secrets ────────────────────────────────────────────────────────
if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "==> Created .env; generating strong random secrets..."
  SECRET_KEYS=(
    POSTGRES_SUPER_PASSWORD NEXTCLOUD_DB_PASSWORD MATTERMOST_DB_PASSWORD
    KEYCLOAK_DB_PASSWORD REDIS_PASSWORD MINIO_ROOT_PASSWORD S3_SECRET_KEY
    KEYCLOAK_ADMIN_PASSWORD OIDC_NEXTCLOUD_SECRET OIDC_MATTERMOST_SECRET
    NEXTCLOUD_ADMIN_PASSWORD COLLABORA_PASSWORD GRAFANA_ADMIN_PASSWORD
  )
  for k in "${SECRET_KEYS[@]}"; do
    v="$(rand)"
    sed -i.bak "s|^${k}=.*|${k}=${v}|" .env
  done
  rm -f .env.bak
  echo "    Secrets written to .env (admin passwords included — keep it safe)."
else
  echo "==> .env exists, leaving secrets untouched"
fi

# ── 2. derive hostnames from BASE_DOMAIN ─────────────────────────────────────
BASE_DOMAIN="$(grep -E '^BASE_DOMAIN=' .env | cut -d= -f2- | tr -d '[:space:]')"
BASE_DOMAIN="${BASE_DOMAIN:-magic.localhost}"
set_host() { sed -i.bak "s|^$1=.*|$1=$2.${BASE_DOMAIN}|" .env && rm -f .env.bak; }
set_host NEXTCLOUD_HOST     cloud
set_host MATTERMOST_HOST    chat
set_host COLLABORA_HOST     office
set_host KEYCLOAK_HOST      id
set_host GRAFANA_HOST       grafana
set_host HOMER_HOST         dash
set_host MINIO_CONSOLE_HOST s3
echo "==> Hostnames derived from BASE_DOMAIN=${BASE_DOMAIN}"

# Load resolved values for templating
set -a; . ./.env; set +a

# ── 3. render Keycloak realm import ──────────────────────────────────────────
echo "==> Rendering Keycloak realm import"
envsubst '${KEYCLOAK_REALM} ${NEXTCLOUD_HOST} ${MATTERMOST_HOST} ${OIDC_NEXTCLOUD_SECRET} ${OIDC_MATTERMOST_SECRET}' \
  < scripts/keycloak-realm.json.template \
  > config/keycloak/magicworkflow-realm.json
echo "    -> config/keycloak/magicworkflow-realm.json"

# ── 4. self-signed wildcard TLS cert ─────────────────────────────────────────
TLS=config/proxy/tls
mkdir -p "$TLS"
if [[ ! -f "$TLS/fullchain.pem" || "${1:-}" == "--force-certs" ]]; then
  echo "==> Generating self-signed wildcard cert for *.${BASE_DOMAIN}"
  openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
    -keyout "$TLS/privkey.pem" -out "$TLS/fullchain.pem" \
    -subj "/CN=*.${BASE_DOMAIN}" \
    -addext "subjectAltName=DNS:*.${BASE_DOMAIN},DNS:${BASE_DOMAIN},DNS:localhost"
else
  echo "==> TLS cert present (pass --force-certs to rotate)"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
cat <<EOF

==> Setup complete.

For LOCAL testing add these to your hosts file (so the subdomains resolve):
  /etc/hosts (Linux/Mac) or C:\\Windows\\System32\\drivers\\etc\\hosts (Windows):

  127.0.0.1  ${NEXTCLOUD_HOST} ${MATTERMOST_HOST} ${COLLABORA_HOST} ${KEYCLOAK_HOST} ${GRAFANA_HOST} ${HOMER_HOST} ${MINIO_CONSOLE_HOST}

Then:
  make up          # start the core suite
  make urls        # print every service URL + admin login
  make logs        # follow logs

Open the dashboard:  https://${HOMER_HOST}
EOF
