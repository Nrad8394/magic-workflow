#!/bin/sh
# =============================================================================
# Auto-install required Nextcloud apps from GitHub release tarballs.
#
# Why: the Nextcloud app store (apps.nextcloud.com) may be unreachable on some
# networks (e.g. SNI-based filtering), which breaks `occ app:install`. GitHub
# release tarballs are an equivalent, app-store-independent source.
#
# Runs automatically as a Nextcloud "before-starting" hook (idempotent), and can
# be re-run manually with `make nc-apps`.
#
# Pinned for Nextcloud 32. When you upgrade Nextcloud, bump the versions below.
# Rule of thumb: richdocuments major = Nextcloud major - 23 (NC32->9, NC34->11);
# user_oidc supports a wide range (29-34) so one recent build covers upgrades.
# =============================================================================
set -u

WWW=/var/www/html
APPS="$WWW/custom_apps"
mkdir -p "$APPS"
# (The edge cert is trusted by the container entrypoint wrapper, which runs as
#  root — this before-starting hook runs as www-data, so it can't update CAs.)

# Run occ as the web user regardless of who invokes this script.
occ() {
  if [ "$(id -u)" = "0" ]; then
    su -s /bin/sh -c "php $WWW/occ $*" www-data
  else
    php "$WWW/occ" "$@"
  fi
}

install_app() {  # name  tarball-url
  name="$1"; url="$2"
  if [ ! -e "$APPS/$name/appinfo/info.xml" ]; then
    echo "[nc-apps] downloading $name ..."
    tmp="$(mktemp)"
    if curl -fsSL "$url" -o "$tmp"; then
      tar -xzf "$tmp" -C "$APPS" || { echo "[nc-apps] !! extract failed: $name"; rm -f "$tmp"; return 0; }
      [ "$(id -u)" = "0" ] && chown -R www-data:www-data "$APPS/$name"
    else
      echo "[nc-apps] !! could not download $name (no internet to GitHub?) — skipping"
      rm -f "$tmp"; return 0
    fi
    rm -f "$tmp"
  else
    echo "[nc-apps] $name already present"
  fi
  occ app:enable "$name" >/dev/null 2>&1 && echo "[nc-apps] $name enabled" \
    || echo "[nc-apps] !! enable failed for $name (incompatible version? check 'occ app:enable $name')"
}

# ── Required apps (pinned for Nextcloud 32) ──────────────────────────────────
install_app user_oidc     "https://github.com/nextcloud-releases/user_oidc/releases/download/v8.10.1/user_oidc-v8.10.1.tar.gz"
install_app richdocuments "https://github.com/nextcloud-releases/richdocuments/releases/download/v9.1.0/richdocuments-v9.1.0.tar.gz"
# External Sites: adds the other suite apps (Mattermost, etc.) into Nextcloud's nav.
install_app external      "https://github.com/nextcloud-releases/external/releases/download/v7.0.1/external-v7.0.1.tar.gz"

echo "[nc-apps] done."
