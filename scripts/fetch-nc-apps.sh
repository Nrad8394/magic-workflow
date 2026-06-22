#!/usr/bin/env bash
# =============================================================================
# Pre-download the required Nextcloud app tarballs for an air-gapped install.
#
# Run this on a machine WITH internet; the files land in
# config/nextcloud/apps-offline/ (committed dir, ignored content). On the target
# host, install-apps.sh installs from there instead of reaching out to GitHub.
#
# Keep the versions here in sync with config/nextcloud/hooks/install-apps.sh.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="config/nextcloud/apps-offline"
mkdir -p "$OUT"

# name|url  (saved as <name>.tar.gz, matching install-apps.sh's lookup)
APPS="
user_oidc|https://github.com/nextcloud-releases/user_oidc/releases/download/v8.10.1/user_oidc-v8.10.1.tar.gz
richdocuments|https://github.com/nextcloud-releases/richdocuments/releases/download/v9.1.0/richdocuments-v9.1.0.tar.gz
external|https://github.com/nextcloud-releases/external/releases/download/v7.0.1/external-v7.0.1.tar.gz
"

echo "==> Fetching Nextcloud apps into $OUT"
for line in $APPS; do
  name="${line%%|*}"; url="${line#*|}"
  dest="$OUT/$name.tar.gz"
  if [ -f "$dest" ]; then
    echo "    [skip] $name (already present)"
    continue
  fi
  echo "    [get ] $name"
  curl -fsSL "$url" -o "$dest"
done

echo "==> Done. $(ls -1 "$OUT"/*.tar.gz 2>/dev/null | wc -l) tarball(s) staged in $OUT"
echo "    Commit/copy this dir to the air-gapped host; install-apps.sh will use it."
