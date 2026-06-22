#!/bin/sh
# =============================================================================
# Nextcloud SSO + Office wiring — runs as a `before-starting` hook (as www-data)
# every container start, so it's idempotent across upgrades. The Helm chart's
# Kubernetes equivalent of scripts/configure.sh (no docker exec / cert import:
# in-cluster TLS is expected to be a real, trusted cert at the Ingress).
#
# Reads its parameters from env injected by the Deployment:
#   KEYCLOAK_HOST KEYCLOAK_REALM OIDC_NC_SECRET COLLABORA_HOST
#   MATTERMOST_HOST GRAFANA_HOST MINIO_HOST
# =============================================================================
set -u
WWW=/var/www/html
occ() { php "$WWW/occ" "$@"; }

# occ only works once Nextcloud is installed; bail quietly otherwise.
occ status >/dev/null 2>&1 || { echo "[configure] Nextcloud not installed yet — skipping"; exit 0; }

echo "[configure] wiring SSO + Office ..."

# Internal service calls (OIDC discovery, WOPI) need the SSRF allow-list.
occ config:system:set allow_local_remote_servers --value=true --type=boolean >/dev/null 2>&1 || true

# Keycloak OIDC login provider (idempotent on the "Keycloak" identifier).
if occ user_oidc:provider Keycloak \
     --clientid=nextcloud \
     --clientsecret="${OIDC_NC_SECRET:-}" \
     --discoveryuri="https://${KEYCLOAK_HOST}/realms/${KEYCLOAK_REALM}/.well-known/openid-configuration" \
     --mapping-uid=preferred_username --mapping-email=email --mapping-display-name=name >/dev/null 2>&1; then
  echo "[configure] Keycloak OIDC provider configured"
else
  echo "[configure] OIDC provider not set (user_oidc enabled yet?) — re-runs on next start"
fi

# Nextcloud Office -> Collabora.
occ config:app:set richdocuments wopi_url --value="https://${COLLABORA_HOST}" >/dev/null 2>&1
occ richdocuments:activate-config >/dev/null 2>&1 \
  && echo "[configure] Office connected to Collabora" \
  || echo "[configure] Office WOPI set (discovery activates on first open)"

# Pin preview providers to image/text (avoid Office/PDF thumbnail 500s).
i=0
for p in 'OC\Preview\PNG' 'OC\Preview\JPEG' 'OC\Preview\GIF' 'OC\Preview\BMP' 'OC\Preview\TXT' 'OC\Preview\MarkDown'; do
  occ config:system:set enabledPreviewProviders $i --value "$p" >/dev/null 2>&1
  i=$((i+1))
done

# External Sites: surface the other suite apps in Nextcloud's app menu.
if occ app:list 2>/dev/null | grep -q "external:"; then
  MM="https://${MATTERMOST_HOST}"; GF="https://${GRAFANA_HOST}"; S3="https://${MINIO_HOST}"
  SITES='{"1":{"id":1,"name":"Mattermost","url":"'"$MM"'","lang":"","type":"link","device":"","icon":"external.svg","groups":[],"redirect":true},"2":{"id":2,"name":"Monitoring","url":"'"$GF"'","lang":"","type":"link","device":"","icon":"external.svg","groups":[],"redirect":true},"3":{"id":3,"name":"Storage","url":"'"$S3"'","lang":"","type":"link","device":"","icon":"external.svg","groups":[],"redirect":true}}'
  occ config:app:set external sites --value "$SITES" >/dev/null 2>&1
  occ config:app:set external max_site --value 3 >/dev/null 2>&1
  echo "[configure] External Sites menu set"
fi

echo "[configure] done."
