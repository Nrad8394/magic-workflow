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

The `user_oidc` app is **installed automatically** when Nextcloud starts (from
GitHub — see [Required apps](operations.md#required-nextcloud-apps)). Then one
command registers the provider:

```bash
make sso-connect
```

That's idempotent — it installs `user_oidc` if missing and registers the
`Keycloak` provider using the secret from `.env`. The Nextcloud login page then
offers **Log in with Keycloak**. (Keep the local admin account as a break-glass
login.)

??? note "Manual equivalent"
    ```bash
    make occ CMD="user_oidc:provider Keycloak \
      --clientid=nextcloud \
      --clientsecret=<OIDC_NEXTCLOUD_SECRET from .env> \
      --discoveryuri=https://id.<domain>/realms/magicworkflow/.well-known/openid-configuration \
      --mapping-uid=preferred_username --mapping-email=email --mapping-display-name=name"
    ```

## Connect Mattermost

Mattermost SSO is **pre-wired via environment variables** (the `mattermost`
service points its GitLab-OAuth slot at the Keycloak realm — that's how Team
Edition does OIDC). A "GitLab" login button appears and redirects to Keycloak;
the Mattermost container trusts the edge cert for the server-side token calls.

!!! warning "Team Edition limitation"
    Mattermost **Team Edition** maps logins through its GitLab provider, which
    expects a **numeric** user `id`. Keycloak's `sub` is a UUID, so the login may
    be rejected after authentication unless you add a Keycloak protocol mapper
    that emits a numeric `id` claim on the `mattermost` client (see the
    [community guide](https://medium.com/@anseliv/configure-keycloak-22-as-sso-instead-of-gitlab-for-mattermost-teams-edition-dff21f489eba)).
    Native, fully-supported OIDC is a Mattermost **Enterprise** feature. Until
    then, Mattermost local accounts work normally, and **Nextcloud SSO is the
    clean, fully-working showcase**.

The pre-created realm `mattermost` client already lists the redirect URIs and the
secret is wired from `OIDC_MATTERMOST_SECRET`.

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
