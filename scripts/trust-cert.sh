#!/usr/bin/env bash
# Add the self-signed edge cert to the OS trust store so browsers stop warning.
# Detects WSL (-> Windows store via certutil.exe), native Linux, and macOS.
# Re-run after rotating the cert (make setup --force-certs).
set -u
cd "$(dirname "$0")/.."
CERT="config/proxy/tls/fullchain.pem"

if [[ ! -f "$CERT" ]]; then
  echo "No cert at $CERT — run 'make setup' first."; exit 1
fi

# Robust WSL detection: custom kernels may omit "microsoft" from /proc/version,
# so also check the WSL env var, the interop binfmt, and wslpath availability.
is_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}" ] \
    || [ -e /proc/sys/fs/binfmt_misc/WSLInterop ] \
    || [ -e /run/WSL ] \
    || command -v wslpath >/dev/null 2>&1 \
    || grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null
}

if is_wsl && command -v certutil.exe >/dev/null 2>&1; then
  WINCERT="$(wslpath -w "$CERT")"
  echo "==> WSL detected — trusting cert in the WINDOWS user Root store"
  echo "    (this is what your Windows browser reads)"
  certutil.exe -addstore -user -f Root "$WINCERT" \
    && echo "==> Trusted. Fully restart Chrome/Edge to pick it up." \
    || echo "!! certutil failed — run it from an elevated PowerShell instead:
       certutil -addstore -user Root \"$(wslpath -w "$CERT")\""
  echo "    (Firefox uses its own store — import $CERT via Settings if you use it.)"

elif [[ "$(uname -s)" == "Darwin" ]]; then
  echo "==> macOS — adding to the system keychain (sudo)"
  sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain "$CERT" \
    && echo "==> Trusted. Restart your browser."

elif [[ "$(uname -s)" == "Linux" ]]; then
  echo "==> Linux — adding to the system CA bundle (sudo)"
  sudo cp "$CERT" /usr/local/share/ca-certificates/magic-workflow.crt
  sudo update-ca-certificates \
    && echo "==> Trusted at the OS level. Browsers using their own store (Chrome/Firefox NSS) may need a separate import or 'certutil -d sql:\$HOME/.pki/nssdb -A ...'."
else
  echo "Unsupported OS. Manually import $CERT into your trust store."
fi

echo
echo "Tip: for a zero-warning local setup, install 'mkcert' and re-run 'make setup'."
