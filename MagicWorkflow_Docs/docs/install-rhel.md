# Install on RHEL (Podman)

Red Hat Enterprise Linux — and Rocky, Alma, CentOS Stream and Fedora — ship
**Podman** rather than Docker, with **SELinux** enforcing. Magic Workflow runs
unchanged on Podman: the Compose stack is engine-agnostic and every `make`
target accepts `ENGINE=podman`. Bind mounts already carry SELinux `:z` labels.

## 1. Prerequisites (run once)

```bash
sudo bash scripts/install-rhel.sh
```

This installs `podman` + `podman-compose`, opens firewalld for 80/443, lets
rootless containers bind ports ≥ 80, and enables the Podman API socket (used by
the optional monitoring/ops profile). It does **not** create secrets — that's
`make setup`.

??? note "What it changes"
    - `dnf install podman podman-compose openssl make git`
    - `firewall-cmd --add-service=http --add-service=https`
    - `/etc/sysctl.d/99-magic-workflow.conf` → `net.ipv4.ip_unprivileged_port_start=80`
    - enables `podman.socket` (rootless: `--user`)

## 2. Bootstrap + start

```bash
make setup                 # .env + secrets + Keycloak realm + TLS cert
make up ENGINE=podman      # core suite
make doctor ENGINE=podman  # verify
```

Add the printed line to `/etc/hosts` (local testing) or point real DNS at the
host (server). Tip: `export ENGINE=podman` in your shell to drop the flag.

Full stack (monitoring + ops):

```bash
make up-full ENGINE=podman
```

## Rootless vs rootful

- **Rootful** (`sudo`) is simplest for a dedicated server: ports 80/443 bind
  directly and the watchtower/promtail socket is `/run/podman/podman.sock`.
- **Rootless** is more secure. `install-rhel.sh` sets the unprivileged-port
  sysctl so the edge proxy can bind 80/443. For the ops profile, pass your
  user socket:

  ```bash
  PODMAN_SOCK=/run/user/$(id -u)/podman/podman.sock make up-full ENGINE=podman
  ```

## SELinux

Leave SELinux **Enforcing**. All host bind mounts use the shared-relabel `:z`
suffix, so Podman relabels them automatically — no `setenforce 0`, no custom
policy. If you add your own bind mount, append `:ro,z` (or `:z`).

## How Podman differs from Docker here

| Concern | Handling |
|---------|----------|
| Compose command | `podman-compose` (or `podman compose`), auto-detected |
| Container names | resolved via `compose ps -q` (format-agnostic) |
| Log shipping | a journald-reading promtail (`docker-compose.podman.yml`); needs persistent journald (install-rhel.sh enables it) |
| Auto-update | watchtower is Docker-only and **not run** on Podman — use `podman auto-update` (label images `io.containers.autoupdate=registry` + enable `podman-auto-update.timer`) |
| Low ports | `ip_unprivileged_port_start=80` for rootless |

## Boot persistence

For a server, enable the stack on boot. The bundled systemd unit targets Docker;
on Podman use a generated unit instead:

```bash
# rootful example
cd /opt/magic-workflow
sudo podman-compose -f docker-compose.yml -f docker-compose.monitoring.yml -f docker-compose.podman.yml up -d
```

…and wrap that in a small systemd service, or use `podman generate systemd`
(quadlets) for individual containers.
