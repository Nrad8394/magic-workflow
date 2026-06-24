# Expose Magic Workflow through Windows Server / IIS

This runbook puts a **Windows Server + IIS** reverse proxy in front of a Magic
Workflow stack running in a VM, so the suite is reachable from the rest of the
network — without changing the stack.

It is the multi-service equivalent of a single-app IIS reverse proxy: Magic
Workflow routes **seven services by `Host` header**, so IIS must *preserve* the
hostname (not override it) and forward to the VM's nginx edge over HTTPS.

## Topology

```
   client browser                 Windows Server (IIS + ARR)            VM
   *.magic.test ──https──▶  10.153.1.189  ──https (Host preserved)──▶  192.168.121.148:443
   (hosts file →                  reverse proxy                        nginx edge
    10.153.1.189)                 (web.config)                         routes by Host
                                                                       → Nextcloud / Keycloak / …
```

| Role | IP |
|------|----|
| VM (stack nginx edge, ports 80/443) | **192.168.121.148** |
| Windows Server (IIS, what clients hit) | **10.153.1.189** |

The 7 hostnames: `cloud.` `chat.` `office.` `id.` `dash.` `s3.` `grafana.` `magic.test`.

!!! warning "Why not a bare IP?"
    A single IP can't distinguish the 7 services (nginx decides by `Host`), and the
    apps emit absolute URLs (`https://id.magic.test/...` for SSO,
    `https://office.magic.test` for Office). So the **hostnames must resolve** to
    the Windows Server. With no DNS, that's done with `hosts` files (below).

## 1. Name resolution (no DNS required)

Two **separate** `hosts` mappings on two machines:

=== "Windows Server — so IIS can reach the VM"
    `C:\Windows\System32\drivers\etc\hosts`
    ```
    192.168.121.148  cloud.magic.test chat.magic.test office.magic.test id.magic.test dash.magic.test s3.magic.test grafana.magic.test
    ```

=== "Each client PC — so browsers reach IIS"
    Windows: `C:\Windows\System32\drivers\etc\hosts` · Linux/macOS: `/etc/hosts`
    ```
    10.153.1.189  cloud.magic.test chat.magic.test office.magic.test id.magic.test dash.magic.test s3.magic.test grafana.magic.test
    ```

!!! note "Keep each entry on ONE line"
    `hosts` files do **not** support `\` line continuation — a wrapped line
    silently drops every host after the break.

If editing each client is impractical, see [the `nip.io` alternative](#alternative-nipio) at the end.

## 2. IIS prerequisites (one-time)

1. Install [URL Rewrite 2.1](https://www.iis.net/downloads/microsoft/url-rewrite) and
   [Application Request Routing 3.0](https://www.iis.net/downloads/microsoft/application-request-routing).
2. **Enable the proxy:** IIS Manager → server node → *Application Request Routing
   Cache* → *Server Proxy Settings* → tick **Enable proxy**. Set **Time-out
   (seconds) = 600** (Collabora + large uploads).
3. Add the **WebSocket Protocol** Windows feature (Server Manager → Add Roles &
   Features → Web Server → Application Development → WebSocket Protocol). Required
   for Mattermost, Collabora and Nextcloud live updates.

## 3. TLS (self-signed, internal network)

There's no public DNS here, so use the VM's existing self-signed `*.magic.test`
wildcard. On the VM:

```bash
openssl pkcs12 -export -out magicworkflow.pfx \
  -inkey config/proxy/tls/privkey.pem -in config/proxy/tls/fullchain.pem
# (set/skip an export password)
```

Copy `magicworkflow.pfx` **and** `config/proxy/tls/fullchain.pem` to the Windows
Server, then:

1. **Import the wildcard for the binding:** IIS Manager → *Server Certificates* →
   **Import** `magicworkflow.pfx`.
2. **Trust the backend cert:** `certlm.msc` → *Trusted Root Certification
   Authorities* → *Certificates* → **Import** `fullchain.pem`. This lets ARR
   validate the VM's HTTPS backend.

Clients get a one-time certificate warning; import `fullchain.pem` into each
client's trust store (or push via GPO) to remove it. Swap in a real cert later if
you get a domain.

## 4. Create the IIS site

1. IIS Manager → **Add Website** (e.g. `MagicWorkflow`), point the physical path
   at a folder containing the `web.config` below (e.g. `C:\inetpub\magicworkflow`).
2. **Binding:** type `https`, port `443`, SSL certificate = the imported
   `*.magic.test` wildcard. Leave the host name blank so the one binding serves
   all seven subdomains. (If port 443 is already used by another site, add an
   SNI binding per hostname instead.)
3. Drop in the `web.config` from
   [`config/iis/web.config`](https://github.com/Nrad8394/magic-workflow/blob/main/config/iis/web.config):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <rule name="ReverseProxy-MagicWorkflow" stopProcessing="true">
          <match url="(.*)" />
          <!-- Forward to the VM's nginx over HTTPS, keeping the original Host
               so nginx routes by subdomain. {HTTP_HOST} resolves to the VM via
               the Windows Server hosts file; the *.magic.test cert matches. -->
          <action type="Rewrite" url="https://{HTTP_HOST}/{R:0}" />
        </rule>
      </rules>
    </rewrite>
    <security>
      <requestFiltering>
        <requestLimits maxAllowedContentLength="10737418240" />
      </requestFiltering>
    </security>
    <httpErrors existingResponse="PassThrough" />
  </system.webServer>
</configuration>
```

> The canonical copy lives in the repo at `config/iis/web.config`.

The rule forwards every request to `https://{HTTP_HOST}/{R:0}` — keeping the
original `Host` (so nginx routes) and connecting to the VM via the Windows hosts
entry, with the matching `*.magic.test` cert.

## 5. Test

From a client that has the hosts entry:

```text
https://dash.magic.test      → Homer dashboard
https://cloud.magic.test     → Nextcloud (log in: admin / see `make urls`)
https://id.magic.test/       → Keycloak
```

Server-side sanity (on the VM) is unchanged: `make doctor` should still be all
`[200]` / `[OK]`. SSO login round-trips Nextcloud → Keycloak → back, because both
hostnames now resolve end-to-end.

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| `502.3` / `ARR` errors | ARR proxy not enabled (step 2.2), or VM unreachable from the server — `Test-NetConnection 192.168.121.148 -Port 443`. |
| Cert error reaching backend | `fullchain.pem` not in **Trusted Root** (step 3.2), or the Windows hosts entry is missing so the name doesn't match `*.magic.test`. |
| One service works, another "can't connect" | A hostname missing from a `hosts` file (wrapped `\` line?). |
| Mattermost/Collabora won't load live | WebSocket Protocol feature not installed (step 2.3). |
| Large upload fails at ~30 MB | `requestLimits maxAllowedContentLength` missing (it's in the `web.config`). |
| SSO redirect goes to an unreachable URL | The client's `hosts` file is missing `id.magic.test → 10.153.1.189`. |

## Alternative: nip.io (no client hosts edits)

If you can't edit every client and they have internet for DNS resolution, use
[`nip.io`](https://nip.io) — `cloud.10.153.1.189.nip.io` auto-resolves to
`10.153.1.189`, no DNS config. This requires **re-keying the stack** to that base
domain:

```bash
# in .env on the VM
BASE_DOMAIN=10.153.1.189.nip.io
make setup        # regenerates hostnames, Keycloak realm, self-signed cert
make up ENGINE=podman
```

The proxy's internal container aliases are pinned to `magic.test`, so they also
need updating to the new names for server-side SSO/Office to keep working — open
an issue / ask and we'll wire `BASE_DOMAIN`-driven aliases. Until then, the
`hosts`-file approach above is the recommended path.
