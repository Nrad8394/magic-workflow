#!/usr/bin/env bash
# =============================================================================
# Mirror every Magic Workflow image for an air-gapped / offline install.
#
#   scripts/mirror-images.sh list                 # print the image list
#   scripts/mirror-images.sh save [bundle.tar]    # pull + save to a tar bundle
#   scripts/mirror-images.sh load [bundle.tar]    # load the bundle on the target
#   scripts/mirror-images.sh push <registry/>     # pull + retag + push to a registry
#
# Engine-aware (Docker or Podman, via scripts/lib/engine.sh). Image tags are read
# from .env so they stay in sync with the compose stack.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib/engine.sh

[ -f .env ] || { echo "ERROR: .env not found (run make setup)" >&2; exit 1; }
set -a; . ./.env; set +a

# Base image refs (without any IMAGE_REGISTRY prefix).
images() {
  cat <<EOF
nginx:${NGINX_IMAGE_TAG}
postgres:${POSTGRES_IMAGE_TAG}
redis:${REDIS_IMAGE_TAG}
minio/minio:${MINIO_IMAGE_TAG}
minio/mc:${MC_IMAGE_TAG}
quay.io/keycloak/keycloak:${KEYCLOAK_IMAGE_TAG}
nextcloud:${NEXTCLOUD_IMAGE_TAG}
mattermost/${MATTERMOST_IMAGE}:${MATTERMOST_IMAGE_TAG}
collabora/code:${COLLABORA_IMAGE_TAG}
b4bz/homer:${HOMER_IMAGE_TAG}
prom/prometheus:${PROMETHEUS_IMAGE_TAG}
grafana/grafana:${GRAFANA_IMAGE_TAG}
grafana/loki:${LOKI_IMAGE_TAG}
grafana/promtail:${PROMTAIL_IMAGE_TAG}
prom/node-exporter:${NODE_EXPORTER_IMAGE_TAG}
containrrr/watchtower:${WATCHTOWER_IMAGE_TAG}
EOF
}

CMD="${1:-list}"

case "$CMD" in
  list)
    images
    ;;

  save)
    BUNDLE="${2:-magic-workflow-images.tar}"
    echo "==> Pulling ${ENGINE} images ..."
    while read -r img; do [ -n "$img" ] && $ENGINE pull "$img"; done < <(images)
    echo "==> Saving bundle -> $BUNDLE"
    # shellcheck disable=SC2046
    $ENGINE save -o "$BUNDLE" $(images | tr '\n' ' ')
    echo "==> Done. Copy $BUNDLE to the air-gapped host and run: $0 load $BUNDLE"
    ;;

  load)
    BUNDLE="${2:-magic-workflow-images.tar}"
    [ -f "$BUNDLE" ] || { echo "ERROR: $BUNDLE not found" >&2; exit 1; }
    echo "==> Loading $BUNDLE with $ENGINE ..."
    $ENGINE load -i "$BUNDLE"
    echo "==> Done."
    ;;

  push)
    REG="${2:-${IMAGE_REGISTRY:-}}"
    [ -n "$REG" ] || { echo "ERROR: give a registry, e.g. $0 push registry.example.com/" >&2; exit 1; }
    case "$REG" in */) ;; *) REG="$REG/";; esac
    echo "==> Mirroring to ${REG} ..."
    while read -r img; do
      [ -n "$img" ] || continue
      $ENGINE pull "$img"
      $ENGINE tag "$img" "${REG}${img}"
      $ENGINE push "${REG}${img}"
      echo "    pushed ${REG}${img}"
    done < <(images)
    echo "==> Done. Set IMAGE_REGISTRY=${REG} in .env (compose) or"
    echo "    global.imageRegistry=${REG} in Helm values."
    ;;

  *)
    echo "usage: $0 {list|save [bundle.tar]|load [bundle.tar]|push <registry/>}" >&2
    exit 1
    ;;
esac
