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

# 0. Force Keycloak's client secrets to match .env. Keycloak only imports the
#    realm once, so an older secret can get stuck in its DB while the apps use
#    the current .env value -> "Invalid client credentials" at token exchange.
KC="docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh"
REALM="$(get KEYCLOAK_REALM)"
if $KC config credentials --server http://localhost:8080 --realm master \
     --user "$(get KEYCLOAK_ADMIN)" --password "$(get KEYCLOAK_ADMIN_PASSWORD)" >/dev/null 2>&1; then
  sync_secret() { # clientId  secret
    local cid
    cid=$($KC get clients -r "$REALM" -q "clientId=$1" --fields id 2>/dev/null | grep -oiE '[0-9a-f]{8}-[0-9a-f-]{27}' | head -1)
    if [ -n "$cid" ]; then
      $KC update "clients/$cid" -r "$REALM" -s "secret=$2" >/dev/null 2>&1 \
        && echo "   [ok] synced Keycloak '$1' client secret to .env"
    fi
  }
  sync_secret nextcloud  "$(get OIDC_NEXTCLOUD_SECRET)"
  sync_secret mattermost "$(get OIDC_MATTERMOST_SECRET)"
else
  echo "   [!!] kcadm auth failed — client secrets not synced"
fi

# 1a. Allow Nextcloud's HTTP client to reach our services on the internal Docker
#     network (private IPs). Without this, SSRF protection raises
#     LocalServerException and OIDC discovery + Collabora WOPI both fail.
$OCC config:system:set allow_local_remote_servers --value=true --type=boolean >/dev/null 2>&1 \
  && echo "   [ok] allow_local_remote_servers enabled" \
  || echo "   [!!] could not set allow_local_remote_servers"

# 1b. Trust the edge cert in Nextcloud's own bundle (server-side OIDC/WOPI).
$OCC security:certificates:import /magic-ca.pem >/dev/null 2>&1 \
  && echo "   [ok] edge cert trusted by Nextcloud" \
  || echo "   [!!] cert import failed"

# 2. Keycloak OIDC login provider — upsert every run so the stored client secret
#    always matches .env (the `Keycloak` identifier makes this idempotent).
if $OCC user_oidc:provider Keycloak \
     --clientid=nextcloud \
     --clientsecret="$(get OIDC_NEXTCLOUD_SECRET)" \
     --discoveryuri="https://$(get KEYCLOAK_HOST)/realms/$(get KEYCLOAK_REALM)/.well-known/openid-configuration" \
     --mapping-uid=preferred_username --mapping-email=email --mapping-display-name=name >/dev/null 2>&1; then
  echo "   [ok] Keycloak OIDC provider configured"
else
  echo "   [!!] OIDC provider registration failed (re-run 'make configure')"
fi

# 3. Nextcloud Office -> Collabora.
$OCC config:app:set richdocuments wopi_url --value="https://$(get COLLABORA_HOST)" >/dev/null 2>&1
$OCC config:app:set richdocuments disable_certificate_verification --value=yes >/dev/null 2>&1
$OCC richdocuments:activate-config >/dev/null 2>&1 \
  && echo "   [ok] Nextcloud Office connected to Collabora" \
  || echo "   [ok] Office WOPI set (discovery activates on first open)"

# 4. Preview providers: pin to image/text only. richdocuments otherwise registers
#    Office/PDF thumbnail providers that render via Collabora's convert-to API,
#    which fails on this setup and spams 500s on /core/preview. Generic icons
#    instead. (Editing is unaffected.)
i=0
for p in 'OC\Preview\PNG' 'OC\Preview\JPEG' 'OC\Preview\GIF' 'OC\Preview\BMP' 'OC\Preview\TXT' 'OC\Preview\MarkDown'; do
  $OCC config:system:set enabledPreviewProviders $i --value "$p" >/dev/null 2>&1
  i=$((i+1))
done
echo "   [ok] preview providers pinned (no Office/PDF thumbnail 500s)"

echo "==> Configuration complete."
