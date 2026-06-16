#!/bin/sh
# =============================================================================
# Plug-and-play post-start configurator (runs as the one-shot
# `nextcloud-configure` service once Keycloak + Collabora are healthy).
#
# Wires the pieces that need other services to be up:
#   * registers Keycloak as a Nextcloud OIDC login provider
#   * points Nextcloud Office (richdocuments) at Collabora
# Idempotent — safe to run on every `make up`.
# =============================================================================
set -u
WWW=/var/www/html
occ() { su -s /bin/sh -c "php $WWW/occ $*" www-data; }

# Trust the edge proxy cert so OIDC discovery / WOPI server-side calls verify.
if [ -f /magic-ca.pem ]; then
  cp /magic-ca.pem /usr/local/share/ca-certificates/magic-workflow.crt 2>/dev/null \
    && update-ca-certificates >/dev/null 2>&1 || true
fi

echo "[configure] ensuring required apps are enabled"
occ app:enable user_oidc     >/dev/null 2>&1 || true
occ app:enable richdocuments >/dev/null 2>&1 || true

# ── Nextcloud single sign-on (Keycloak) ──────────────────────────────────────
if occ user_oidc:provider 2>/dev/null | grep -q Keycloak; then
  echo "[configure] OIDC provider 'Keycloak' already registered"
else
  echo "[configure] registering Keycloak OIDC provider"
  occ user_oidc:provider Keycloak \
    --clientid=nextcloud \
    --clientsecret="$OIDC_NEXTCLOUD_SECRET" \
    --discoveryuri="https://$KEYCLOAK_HOST/realms/$KEYCLOAK_REALM/.well-known/openid-configuration" \
    --mapping-uid=preferred_username --mapping-email=email --mapping-display-name=name \
    || echo "[configure] !! OIDC provider registration failed (will retry next 'make up')"
fi

# ── Nextcloud Office (Collabora) ─────────────────────────────────────────────
echo "[configure] pointing Nextcloud Office at Collabora"
occ config:app:set richdocuments wopi_url --value="https://$COLLABORA_HOST" >/dev/null
# Local self-signed certs: allow Nextcloud->Collabora without CA trust.
# On a server with real certs, set this to 'no'.
occ config:app:set richdocuments disable_certificate_verification --value=yes >/dev/null
occ richdocuments:activate-config >/dev/null 2>&1 \
  && echo "[configure] Office discovery activated" \
  || echo "[configure] (Office discovery will activate on first document open)"

echo "[configure] done — SSO + Office wired."
