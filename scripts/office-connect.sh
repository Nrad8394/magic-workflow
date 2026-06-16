#!/usr/bin/env bash
# Point the Nextcloud Office (richdocuments) app at the bundled Collabora server.
# The app is auto-installed from GitHub on Nextcloud start (and by `make nc-apps`),
# so this just ensures it's present and sets the WOPI URL.
set -u
cd "$(dirname "$0")/.."
OCC="docker compose exec -T -u www-data nextcloud-app php occ"
HOST="$(grep -E '^COLLABORA_HOST=' .env | cut -d= -f2-)"

if ! $OCC app:list 2>/dev/null | grep -q richdocuments; then
  echo "==> richdocuments not present yet — installing from GitHub..."
  docker compose exec -u root nextcloud-app sh /docker-entrypoint-hooks.d/before-starting/install-apps.sh || true
fi

if $OCC app:list 2>/dev/null | grep -q richdocuments; then
  $OCC config:app:set richdocuments wopi_url --value="https://${HOST}"
  # Local self-signed certs: let Nextcloud reach Collabora without CA trust.
  # On a server with real certs, set this back to 'no'.
  $OCC config:app:set richdocuments disable_certificate_verification --value=yes
  $OCC richdocuments:activate-config 2>/dev/null || true
  echo "==> Nextcloud Office connected to Collabora (https://${HOST})."
  echo "    Open a document in Nextcloud Files to edit."
else
  echo "!! richdocuments still not installed — see 'make nc-apps' output / network to GitHub."
fi
