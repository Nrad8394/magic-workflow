#!/usr/bin/env bash
# Print every service URL and its admin login (read from .env).
set -u
cd "$(dirname "$0")/.."
get() { grep -E "^$1=" .env | cut -d= -f2-; }

cat <<EOF

  Magic Workflow — service URLs
  =============================
  Dashboard (Homer) : https://$(get HOMER_HOST)

  Nextcloud         : https://$(get NEXTCLOUD_HOST)
      admin login   : $(get NEXTCLOUD_ADMIN_USER) / $(get NEXTCLOUD_ADMIN_PASSWORD)
  Mattermost        : https://$(get MATTERMOST_HOST)   (first account = system admin)

  Collabora (Office backend) — NOT a page you browse; Nextcloud drives it.
      used by Nextcloud : https://$(get COLLABORA_HOST)   (root just returns "OK")
      admin console     : https://$(get COLLABORA_HOST)/browser/dist/admin/admin.html
      admin login       : $(get COLLABORA_USERNAME) / $(get COLLABORA_PASSWORD)
      to enable editing : in Nextcloud install the "Nextcloud Office" app and set the
                          server to  https://$(get COLLABORA_HOST)  (or: make office-connect)

  Keycloak (SSO)    : https://$(get KEYCLOAK_HOST)
      admin login   : $(get KEYCLOAK_ADMIN) / $(get KEYCLOAK_ADMIN_PASSWORD)
      realm         : $(get KEYCLOAK_REALM)
  MinIO Console     : https://$(get MINIO_CONSOLE_HOST)
      root login    : $(get MINIO_ROOT_USER) / $(get MINIO_ROOT_PASSWORD)
  Grafana           : https://$(get GRAFANA_HOST)   (monitoring profile)
      admin login   : $(get GRAFANA_ADMIN_USER) / $(get GRAFANA_ADMIN_PASSWORD)

  (Self-signed cert locally — your browser will warn; accept to proceed.)
EOF
