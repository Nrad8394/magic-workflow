#!/usr/bin/env bash
# Print the OIDC details + the exact steps to connect Nextcloud and Mattermost
# to the bundled Keycloak realm (which already has both clients pre-created).
set -u
cd "$(dirname "$0")/.."
get() { grep -E "^$1=" .env | cut -d= -f2-; }

KC="https://$(get KEYCLOAK_HOST)"
REALM="$(get KEYCLOAK_REALM)"
ISS="$KC/realms/$REALM"

cat <<EOF

  Single Sign-On (Keycloak)
  =========================
  Issuer / discovery : $ISS/.well-known/openid-configuration
  Realm              : $REALM
  Pre-created clients: nextcloud, mattermost  (secrets in .env)

  ── Nextcloud ────────────────────────────────────────────────────────────────
  1. make occ CMD="app:install user_oidc"
  2. make occ CMD="user_oidc:provider Keycloak \\
       --clientid=nextcloud \\
       --clientsecret=$(get OIDC_NEXTCLOUD_SECRET) \\
       --discoveryuri=$ISS/.well-known/openid-configuration \\
       --mapping-uid=preferred_username --mapping-email=email --mapping-displayName=name"
  3. Login page now shows 'Log in with Keycloak'.

  ── Mattermost ───────────────────────────────────────────────────────────────
  System Console -> Authentication -> OpenID Connect:
    Discovery Endpoint : $ISS/.well-known/openid-configuration
    Client ID          : mattermost
    Client Secret      : $(get OIDC_MATTERMOST_SECRET)
  (Team Edition includes OpenID Connect via GitLab/OpenID settings.)

  Test user in the realm: demo / demo  (must reset password on first login)
EOF
