#!/bin/bash
# Creates one database + owner role per app inside the shared PostgreSQL instance.
# Runs automatically on first cluster init (mounted into /docker-entrypoint-initdb.d).
# Passwords come from env vars injected by docker-compose.
set -euo pipefail

create_db() {
  local db="$1" user="$2" pw="$3"
  echo "  -> creating role '$user' and database '$db'"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-SQL
    DO \$\$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$user') THEN
        CREATE ROLE "$user" LOGIN PASSWORD '$pw';
      END IF;
    END
    \$\$;
    SELECT 'CREATE DATABASE "$db" OWNER "$user"'
      WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$db')\gexec
    GRANT ALL PRIVILEGES ON DATABASE "$db" TO "$user";
SQL
}

create_db "nextcloud"  "nextcloud"  "${NEXTCLOUD_DB_PASSWORD}"
create_db "mattermost" "mattermost" "${MATTERMOST_DB_PASSWORD}"
create_db "keycloak"   "keycloak"   "${KEYCLOAK_DB_PASSWORD}"

echo "==> Magic Workflow databases initialised."
