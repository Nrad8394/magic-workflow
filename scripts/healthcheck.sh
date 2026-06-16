#!/usr/bin/env bash
# Probe each core service via the running containers.
set -u
cd "$(dirname "$0")/.."
C="docker compose"

probe() { # name  cmd...
  local name="$1"; shift
  if $C exec -T "$@" >/dev/null 2>&1; then
    printf "  [\033[32m OK \033[0m] %s\n" "$name"
  else
    printf "  [\033[31mFAIL\033[0m] %s\n" "$name"
  fi
}

echo "Magic Workflow — health:"
probe "postgres"   db        pg_isready -U "$(grep ^POSTGRES_SUPER_USER .env | cut -d= -f2)"
probe "redis"      redis     sh -c 'redis-cli -a "$REDIS_PASSWORD" ping'
probe "minio"      minio     mc ready local
probe "keycloak"   keycloak  sh -c 'exec 3<>/dev/tcp/localhost/9000; echo ok'
probe "nextcloud"  nextcloud-app sh -c 'php occ status >/dev/null 2>&1 || true; exec 3<>/dev/tcp/localhost/9000; echo ok'
probe "mattermost" mattermost curl -fsS http://localhost:8065/api/v4/system/ping
probe "collabora"  collabora  sh -c 'wget -q -O /dev/null http://127.0.0.1:9980/'
echo "(FAIL may just mean a service is still starting — re-run in a minute.)"
