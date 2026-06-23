#!/usr/bin/env bash
# =============================================================================
# Shared container-engine resolver — sourced by the helper scripts so the suite
# runs identically on Docker and on Podman/RHEL.
#
#   ENGINE   docker | podman          (override: ENGINE=podman make up)
#   COMPOSE  the compose command line  ("docker compose" / "podman-compose")
#
# Detection order: honour an explicit $ENGINE, otherwise prefer docker, then
# fall back to podman. Exposes helpers used across the scripts:
#   dc ...        run a core-compose command
#   cid <svc>     print the container id for a compose service (engine-neutral)
#   chealth <svc> print a service's health status (healthy / starting / ...)
# =============================================================================

# Resolve the engine binary.
if [ -z "${ENGINE:-}" ]; then
  if command -v docker >/dev/null 2>&1; then
    ENGINE=docker
  elif command -v podman >/dev/null 2>&1; then
    ENGINE=podman
  else
    echo "ERROR: neither 'docker' nor 'podman' found on PATH." >&2
    return 1 2>/dev/null || exit 1
  fi
fi

# Resolve the compose command for the chosen engine.
if [ -z "${COMPOSE:-}" ]; then
  case "$ENGINE" in
    docker)
      COMPOSE="docker compose" ;;
    podman)
      if command -v podman-compose >/dev/null 2>&1; then
        COMPOSE="podman-compose"
      else
        # Podman >= 4 ships a `podman compose` shim that drives an installed
        # podman-compose/docker-compose. Use it as the fallback.
        COMPOSE="podman compose"
      fi ;;
    *)
      COMPOSE="$ENGINE compose" ;;
  esac
fi

# Compose project name (for name-based container lookup). Honour the env, else
# read .env (helper scripts cd to the repo root first), else the compose default.
if [ -z "${COMPOSE_PROJECT_NAME:-}" ]; then
  COMPOSE_PROJECT_NAME="$(grep -E '^COMPOSE_PROJECT_NAME=' .env 2>/dev/null | cut -d= -f2- | tr -d '[:space:]')"
  : "${COMPOSE_PROJECT_NAME:=magicworkflow}"
fi

export ENGINE COMPOSE COMPOSE_PROJECT_NAME

# Run a core-compose command (no monitoring overlay).
dc() { $COMPOSE "$@"; }

# Print the container id for a compose service, '' if not running.
# `docker compose ps -q <svc>` works for Docker; podman-compose's `ps -q` does
# not filter by service, so fall back to the conventional container names
# (docker-compose uses `project-svc-1`, podman-compose uses `project_svc_1`).
cid() {
  local id proj="$COMPOSE_PROJECT_NAME" n
  id="$($COMPOSE ps -q "$1" 2>/dev/null | head -n1)"
  if [ -z "$id" ]; then
    for n in "${proj}_$1_1" "${proj}-$1-1" "${proj}_$1" "${proj}-$1"; do
      id="$($ENGINE inspect -f '{{.Id}}' "$n" 2>/dev/null)" && [ -n "$id" ] && break
    done
  fi
  printf '%s\n' "$id"
}

# Print a service's health status ('healthy', 'starting', 'none', ...).
chealth() {
  local id; id="$(cid "$1")"
  [ -n "$id" ] || { echo "absent"; return; }
  $ENGINE inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id" 2>/dev/null || echo "unknown"
}
