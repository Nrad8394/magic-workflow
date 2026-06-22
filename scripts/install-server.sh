#!/usr/bin/env bash
# =============================================================================
# Magic Workflow — Debian / Ubuntu production host setup + hardening.
#
# Installs Docker Engine (if absent), a firewall (ufw: 22/80/443), fail2ban,
# automatic security updates, and a systemd unit so the stack starts on boot.
# Run once as root (or with sudo) from the repo dir, then:
#
#   make setup                 # .env + secrets + realm + TLS
#   sudo systemctl start magic-workflow
#
# Idempotent. Does not touch .env/secrets. For RHEL/Podman use install-rhel.sh.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
REPO_DIR="$(pwd)"

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

command -v apt-get >/dev/null 2>&1 || {
  echo "ERROR: apt-get not found — this script targets Debian/Ubuntu." >&2
  echo "       For RHEL-family hosts use scripts/install-rhel.sh." >&2
  exit 1
}

echo "==> Magic Workflow — Debian/Ubuntu server setup ($REPO_DIR)"
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -y

# ── container engine ─────────────────────────────────────────────────────────
if command -v docker >/dev/null 2>&1; then
  echo "==> Docker already installed: $(docker --version)"
elif command -v podman >/dev/null 2>&1; then
  echo "==> Podman detected — skipping Docker. Run the stack with ENGINE=podman."
else
  echo "==> Installing Docker Engine (get.docker.com) ..."
  curl -fsSL https://get.docker.com | $SUDO sh
  $SUDO systemctl enable --now docker
fi

# ── helpers ──────────────────────────────────────────────────────────────────
$SUDO apt-get install -y make openssl ufw fail2ban unattended-upgrades

# ── firewall ─────────────────────────────────────────────────────────────────
echo "==> Configuring ufw (allow OpenSSH + 80/443) ..."
$SUDO ufw allow OpenSSH >/dev/null 2>&1 || $SUDO ufw allow 22/tcp
$SUDO ufw allow 80/tcp
$SUDO ufw allow 443/tcp
$SUDO ufw --force enable
$SUDO ufw status verbose | sed 's/^/    /'

# ── fail2ban (protect SSH) ───────────────────────────────────────────────────
echo "==> Enabling fail2ban ..."
$SUDO systemctl enable --now fail2ban || true

# ── automatic security updates ───────────────────────────────────────────────
echo "==> Enabling unattended-upgrades (security) ..."
echo 'APT::Periodic::Update-Package-Lists "1";' | $SUDO tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null
echo 'APT::Periodic::Unattended-Upgrade "1";'   | $SUDO tee -a /etc/apt/apt.conf.d/20auto-upgrades >/dev/null

# ── systemd unit (start the stack on boot) ───────────────────────────────────
echo "==> Installing systemd unit (start on boot) ..."
UNIT=/etc/systemd/system/magic-workflow.service
$SUDO cp config/systemd/magic-workflow.service "$UNIT"
$SUDO sed -i "s|/opt/magic-workflow|${REPO_DIR}|" "$UNIT"
$SUDO systemctl daemon-reload
$SUDO systemctl enable magic-workflow >/dev/null 2>&1 || true
echo "    enabled magic-workflow.service (WorkingDirectory=${REPO_DIR})"

cat <<EOF

==> Server prepared and hardened. Next:

  make setup                          # .env + secrets + Keycloak realm + TLS cert
  # provision real TLS into config/proxy/tls/ for production (see docs)
  sudo systemctl start magic-workflow # bring the stack up now (and on every boot)
  make doctor                         # verify

Hardening applied: ufw (22/80/443), fail2ban, unattended security upgrades.
Remember: keep .env off-host in a secret manager, and back up the MinIO volume.
EOF
