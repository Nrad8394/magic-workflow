#!/usr/bin/env bash
# Register the bundled Keycloak realm as an OIDC login provider in Nextcloud.
# The user_oidc app is auto-installed on Nextcloud start (and by `make nc-apps`).
set -u
cd "$(dirname "$0")/.."
OCC="docker compose exec -T -u www-data nextcloud-app php occ"
get() { grep -E "^$1=" .env | cut -d= -f2-; }

KC_HOST="$(get KEYCLOAK_HOST)"; REALM="$(get KEYCLOAK_REALM)"
SECRET="$(get OIDC_NEXTCLOUD_SECRET)"
DISCO="https://${KC_HOST}/realms/${REALM}/.well-known/openid-configuration"

if ! $OCC app:list 2>/dev/null | grep -q user_oidc; then
  echo "==> user_oidc not present yet — installing from GitHub..."
  docker compose exec -u root nextcloud-app sh /docker-entrypoint-hooks.d/before-starting/install-apps.sh || true
fi

if ! $OCC app:list 2>/dev/null | grep -q user_oidc; then
  echo "!! user_oidc still not installed — see 'make nc-apps' output / network to GitHub."; exit 1
fi

# Idempotent: skip if a 'Keycloak' provider already exists.
if $OCC user_oidc:provider 2>/dev/null | grep -q Keycloak; then
  echo "==> OIDC provider 'Keycloak' already registered."
else
  $OCC user_oidc:provider Keycloak \
    --clientid=nextcloud \
    --clientsecret="${SECRET}" \
    --discoveryuri="${DISCO}" \
    --mapping-uid=preferred_username --mapping-email=email --mapping-display-name=name
  echo "==> Registered Keycloak OIDC provider."
fi
echo "    The Nextcloud login page now offers 'Log in with Keycloak'."
echo "    (Keycloak must be reachable from the Nextcloud container at ${DISCO})"
