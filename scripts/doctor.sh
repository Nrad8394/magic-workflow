#!/usr/bin/env bash
# Health-check the whole suite from the host (server side) and print the
# browser-side setup the user must do (hosts file + cert trust).
set -u
cd "$(dirname "$0")/.."
get() { grep -E "^$1=" .env | cut -d= -f2-; }
HP="$(get HTTPS_PORT)"; HP="${HP:-443}"

probe() { # label host path
  local code
  code=$(curl -sk -m 8 -o /dev/null -w "%{http_code}" \
    --resolve "$2:${HP}:127.0.0.1" "https://$2$3" 2>/dev/null)
  case "$code" in
    2*|30*) printf "  [\033[32m %s \033[0m] %-26s %s\n" "$code" "$1" "https://$2";;
    *)      printf "  [\033[31m%s\033[0m] %-26s %s\n" "${code:-000}" "$1" "https://$2";;
  esac
}

echo "Magic Workflow — doctor"
echo "── Containers ─────────────────────────────────────────"
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml ps \
  --format "  {{.Name}}  {{.Status}}" 2>/dev/null | sed "s/magicworkflow-//"

echo "── Endpoints via the proxy (server side) ──────────────"
probe Nextcloud  "$(get NEXTCLOUD_HOST)"  /status.php
probe Mattermost "$(get MATTERMOST_HOST)" /api/v4/system/ping
probe Keycloak   "$(get KEYCLOAK_HOST)"   /realms/$(get KEYCLOAK_REALM)/.well-known/openid-configuration
probe Collabora  "$(get COLLABORA_HOST)"  /hosting/discovery
probe Dashboard  "$(get HOMER_HOST)"      /
probe MinIO      "$(get MINIO_CONSOLE_HOST)" /

echo "── Nextcloud wiring ───────────────────────────────────"
OCC="docker compose exec -T -u www-data nextcloud-app php occ"
$OCC app:list 2>/dev/null | grep -q user_oidc     && echo "  [ OK ] user_oidc installed"     || echo "  [FAIL] user_oidc missing (make nc-apps)"
$OCC app:list 2>/dev/null | grep -q richdocuments && echo "  [ OK ] richdocuments installed" || echo "  [FAIL] richdocuments missing (make nc-apps)"
$OCC user_oidc:provider 2>/dev/null | grep -q Keycloak && echo "  [ OK ] Keycloak OIDC provider registered" || echo "  [FAIL] OIDC provider missing (make configure)"
$OCC security:certificates 2>/dev/null | grep -q magic && echo "  [ OK ] edge cert trusted by Nextcloud" || echo "  [FAIL] edge cert not trusted (make configure)"

echo "── What YOU must do in the browser ────────────────────"
echo "  1) hosts file (C:\\Windows\\System32\\drivers\\etc\\hosts on Windows):"
echo "     127.0.0.1  $(get NEXTCLOUD_HOST) $(get MATTERMOST_HOST) $(get COLLABORA_HOST) $(get KEYCLOAK_HOST) $(get HOMER_HOST) $(get MINIO_CONSOLE_HOST) $(get GRAFANA_HOST)"
echo "  2) trust the local cert:  make trust-cert   (then fully restart the browser)"
echo "  3) open https://$(get HOMER_HOST)"
