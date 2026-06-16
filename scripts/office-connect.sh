#!/usr/bin/env bash
# Install the Nextcloud Office (richdocuments) app and point it at the bundled
# Collabora server. Needs outbound internet from the Nextcloud container ONCE to
# fetch the app from apps.nextcloud.com.
set -u
cd "$(dirname "$0")/.."
OCC="docker compose exec -T -u www-data nextcloud-app php occ"
HOST="$(grep -E '^COLLABORA_HOST=' .env | cut -d= -f2-)"

echo "==> Installing Nextcloud Office (richdocuments)..."
$OCC app:install richdocuments 2>/dev/null || $OCC app:enable richdocuments 2>/dev/null || true

if $OCC app:list 2>/dev/null | grep -q richdocuments; then
  $OCC config:app:set richdocuments wopi_url --value="https://${HOST}"
  # Local self-signed certs: let Nextcloud reach Collabora without CA trust.
  # On a server with real certs, set this back to 'no'.
  $OCC config:app:set richdocuments disable_certificate_verification --value=yes
  $OCC richdocuments:activate-config 2>/dev/null || true
  echo "==> Connected. Open a document in Nextcloud Files to edit with Collabora."
else
  cat <<EOF
!! Could not fetch the 'richdocuments' (Nextcloud Office) app.
   The Nextcloud container needs outbound internet to apps.nextcloud.com (got none).
   Fix container egress/DNS, then re-run:  make office-connect
   ...or install "Nextcloud Office" from Nextcloud's Apps UI and re-run this to
   point it at https://${HOST}.
EOF
fi
