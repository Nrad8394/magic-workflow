# Single sign-on

Keycloak is the identity provider for the whole suite. The bundled realm
(`magicworkflow`) is imported on first boot with **OIDC clients for Nextcloud
and Mattermost already created** — you only need to connect each app to it.

```bash
make sso-info     # prints the endpoints, secrets and exact commands
```

## The realm

| | |
|---|---|
| Realm | `magicworkflow` (set by `KEYCLOAK_REALM`) |
| Issuer | `https://id.<domain>/realms/magicworkflow` |
| Discovery | `…/realms/magicworkflow/.well-known/openid-configuration` |
| Clients | `nextcloud`, `mattermost` (secrets in `.env`) |
| Test user | `demo` / `demo` (temporary password) |

Manage users at **https://id.<domain>** with the `KEYCLOAK_ADMIN` login from
`.env`. Connect Keycloak to your LDAP/AD or an upstream IdP (Azure, Google) under
*User Federation* / *Identity Providers* to bring in your real directory.

## Connect Nextcloud

```bash
make occ CMD="app:install user_oidc"
make occ CMD="user_oidc:provider Keycloak \
  --clientid=nextcloud \
  --clientsecret=<OIDC_NEXTCLOUD_SECRET from .env> \
  --discoveryuri=https://id.<domain>/realms/magicworkflow/.well-known/openid-configuration \
  --mapping-uid=preferred_username --mapping-email=email --mapping-displayName=name"
```

The Nextcloud login page now offers **Log in with Keycloak**. (Keep the local
admin account as a break-glass login.)

## Connect Mattermost

System Console → **Authentication → OpenID Connect**:

| Field | Value |
|-------|-------|
| Discovery Endpoint | `https://id.<domain>/realms/magicworkflow/.well-known/openid-configuration` |
| Client ID | `mattermost` |
| Client Secret | `OIDC_MATTERMOST_SECRET` from `.env` |

Team Edition exposes OpenID Connect via the GitLab/OpenID settings; the
pre-created client already lists Mattermost's redirect URIs.

## Connect Collabora / others

Collabora authenticates **through Nextcloud** (WOPI), so once Nextcloud uses
Keycloak, Office editing inherits the same identity. To add more apps later,
create a new client in the realm and point the app's OIDC config at it.

## Notes

- All redirect URIs in the realm use `https://<service-host>` — they're derived
  from `BASE_DOMAIN`, so re-run `make setup` if you change the domain.
- Behind the edge proxy, `KC_PROXY_HEADERS=xforwarded` and `KC_HOSTNAME` are set
  so Keycloak builds correct external URLs.
- For production, replace the `demo` user and rotate the OIDC secrets.
