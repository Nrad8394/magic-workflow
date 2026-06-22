#!/usr/bin/env bash
# =============================================================================
# Magic Workflow — RHEL / Rocky / Alma / Fedora prerequisite bootstrap.
#
# Installs Podman + podman-compose, opens the firewall, and (for rootless) lets
# unprivileged containers bind 80/443. Run once, as root (or with sudo), then:
#
#   make setup
#   make up ENGINE=podman          # core
#   make up-full ENGINE=podman     # core + monitoring + ops
#
# Re-running is safe (idempotent). Does NOT touch .env/secrets — that's setup.sh.
# =============================================================================
set -euo pipefail

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

echo "==> Magic Workflow — RHEL prerequisites"

# ── package manager ──────────────────────────────────────────────────────────
if command -v dnf >/dev/null 2>&1; then PKG="dnf"
elif command -v yum >/dev/null 2>&1; then PKG="yum"
else echo "ERROR: no dnf/yum found — is this a RHEL-family host?" >&2; exit 1; fi

# ── podman + compose + helpers ───────────────────────────────────────────────
echo "==> Installing podman, podman-compose, openssl, make, git ..."
$SUDO "$PKG" install -y podman openssl make git || true
# podman-compose ships in EPEL on RHEL; try the package, fall back to pip.
if ! command -v podman-compose >/dev/null 2>&1; then
  $SUDO "$PKG" install -y podman-compose 2>/dev/null \
    || $SUDO "$PKG" install -y python3-pip && $SUDO pip3 install podman-compose \
    || echo "   [!!] install podman-compose manually (pip3 install podman-compose)"
fi

podman --version || { echo "ERROR: podman not installed" >&2; exit 1; }

# ── firewall: open 80/443 ────────────────────────────────────────────────────
if command -v firewall-cmd >/dev/null 2>&1 && $SUDO firewall-cmd --state >/dev/null 2>&1; then
  echo "==> Opening firewalld ports 80/443 ..."
  $SUDO firewall-cmd --permanent --add-service=http  >/dev/null
  $SUDO firewall-cmd --permanent --add-service=https >/dev/null
  $SUDO firewall-cmd --reload >/dev/null
  echo "    firewalld: http + https allowed"
else
  echo "    firewalld inactive — skipping (open 80/443 in your firewall manually)"
fi

# ── rootless low-port binding (so the edge proxy can bind 80/443) ─────────────
# Rootless Podman can't bind <1024 unless the host lowers the threshold.
CONF=/etc/sysctl.d/99-magic-workflow.conf
if [ ! -f "$CONF" ]; then
  echo "==> Allowing unprivileged binding of ports >= 80 (rootless Podman) ..."
  echo "net.ipv4.ip_unprivileged_port_start=80" | $SUDO tee "$CONF" >/dev/null
  $SUDO sysctl -p "$CONF" >/dev/null || true
fi

# ── Podman API socket (needed by watchtower/promtail in the ops profile) ──────
echo "==> Enabling the Podman API socket (for the monitoring/ops profile) ..."
if [ "$(id -u)" -ne 0 ]; then
  systemctl --user enable --now podman.socket 2>/dev/null \
    && echo "    rootless socket: /run/user/$(id -u)/podman/podman.sock" \
    && echo "    -> use: PODMAN_SOCK=/run/user/$(id -u)/podman/podman.sock make up-full ENGINE=podman" \
    || echo "    [!!] could not enable rootless podman.socket (ops profile optional)"
else
  systemctl enable --now podman.socket 2>/dev/null \
    && echo "    rootful socket: /run/podman/podman.sock" \
    || echo "    [!!] could not enable podman.socket (ops profile optional)"
fi

# ── SELinux note ─────────────────────────────────────────────────────────────
if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" = "Enforcing" ]; then
  echo "==> SELinux is Enforcing (good). Bind mounts use :z labels — no extra steps."
fi

cat <<EOF

==> RHEL prerequisites ready. Next:

  make setup                    # generate .env + secrets + realm + TLS cert
  make up ENGINE=podman         # start the core suite on Podman
  make doctor ENGINE=podman     # verify

Tip: export ENGINE=podman in your shell to drop the flag from every command.
EOF
