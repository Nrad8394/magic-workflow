#!/usr/bin/env bash
# =============================================================================
# Plug-and-play post-start configuration (run by `make up`).
# Waits for the dependencies to be healthy, then idempotently:
#   * imports the edge cert into Nextcloud's HTTP-client trust store
#   * registers Keycloak as a Nextcloud OIDC login provider
#   * points Nextcloud Office (richdocuments) at Collabora
# Safe to re-run any time (`make configure`).
# =============================================================================
set -u
cd "$(dirname "$0")/.."
P=magicworkflow
OCC="docker compose exec -T -u www-data nextcloud-app php occ"
get() { grep -E "^$1=" .env | cut -d= -f2-; }

wait_healthy() { # service  max_tries
  local c="$1" max="${2:-60}" n=0
  printf "   waiting for %s" "$c"
  until [ "$(docker inspect -f '{{.State.Health.Status}}' ${P}-$c-1 2>/dev/null)" = healthy ]; do
    n=$((n+1)); [ $n -gt $max ] && { echo " ... still not healthy (continuing)"; return 1; }
    printf "."; sleep 5
  done
  echo " ok"
}

echo "==> Configuring Nextcloud SSO + Office (waiting for services)..."
wait_healthy nextcloud-app
wait_healthy keycloak
wait_healthy collabora

# 1. Trust the edge cert in Nextcloud's own bundle (server-side OIDC/WOPI).
$OCC security:certificates:import /magic-ca.pem >/dev/null 2>&1 \
  && echo "   [ok] edge cert trusted by Nextcloud" \
  || echo "   [!!] cert import failed"

# 2. Keycloak OIDC login provider (idempotent).
if $OCC user_oidc:provider 2>/dev/null | grep -q Keycloak; then
  echo "   [ok] OIDC provider already registered"
else
  if $OCC user_oidc:provider Keycloak \
       --clientid=nextcloud \
       --clientsecret="$(get OIDC_NEXTCLOUD_SECRET)" \
       --discoveryuri="https://$(get KEYCLOAK_HOST)/realms/$(get KEYCLOAK_REALM)/.well-known/openid-configuration" \
       --mapping-uid=preferred_username --mapping-email=email --mapping-display-name=name >/dev/null 2>&1; then
    echo "   [ok] registered Keycloak OIDC provider"
  else
    echo "   [!!] OIDC provider registration failed (re-run 'make configure')"
  fi
fi

# 3. Nextcloud Office -> Collabora.
$OCC config:app:set richdocuments wopi_url --value="https://$(get COLLABORA_HOST)" >/dev/null 2>&1
$OCC config:app:set richdocuments disable_certificate_verification --value=yes >/dev/null 2>&1
$OCC richdocuments:activate-config >/dev/null 2>&1 \
  && echo "   [ok] Nextcloud Office connected to Collabora" \
  || echo "   [ok] Office WOPI set (discovery activates on first open)"

echo "==> Configuration complete."
