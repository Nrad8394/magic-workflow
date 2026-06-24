# =============================================================================
# Magic Workflow — Operations Makefile   (run `make` for the full list)
# =============================================================================

# Container engine — auto-detected: Docker if present, else Podman. Override
# explicitly with `make <target> ENGINE=podman` (or `ENGINE=docker`).
ENGINE       ?= $(shell command -v docker >/dev/null 2>&1 && echo docker || echo podman)
ifeq ($(ENGINE),podman)
  COMPOSE_BIN    := $(shell command -v podman-compose >/dev/null 2>&1 && echo podman-compose || echo "podman compose")
  # Podman: journald-based promtail, no watchtower (Docker-socket bound).
  OPS_OVERLAY    := -f docker-compose.podman.yml
else
  COMPOSE_BIN    := docker compose
  # Docker: promtail (docker logs) + watchtower auto-update.
  OPS_OVERLAY    := -f docker-compose.ops.yml
endif
# Core uses the default compose file; the ops overlay (engine-specific) only
# adds the log-shipping / auto-update services, so it rides on FULL alone.
COMPOSE      := $(COMPOSE_BIN)
FULL         := $(COMPOSE_BIN) -f docker-compose.yml -f docker-compose.monitoring.yml $(OPS_OVERLAY)
ENV_FILE     := .env
OCC          := $(COMPOSE) exec -u www-data nextcloud-app php occ
# Exported so the helper scripts (via scripts/lib/engine.sh) use the same engine.
export ENGINE

check-env:
	@test -f $(ENV_FILE) || (echo "ERROR: .env not found. Run: make setup" && exit 1)

# ── SETUP ────────────────────────────────────────────────────────────────────
.PHONY: setup
setup:                 ## First-time setup: .env + secrets + Keycloak realm + TLS cert
	@bash setup.sh

.PHONY: install-rhel
install-rhel:          ## RHEL/Rocky/Alma/Fedora: install Podman + open firewall (run once, then `make setup`)
	@bash scripts/install-rhel.sh

.PHONY: install-server
install-server:        ## Debian/Ubuntu: install engine + firewall + systemd unit (production hardening)
	@bash scripts/install-server.sh

.PHONY: trust-cert
trust-cert:            ## Trust the local self-signed cert in your OS store (stops browser warnings)
	@bash scripts/trust-cert.sh

# ── LIFECYCLE ────────────────────────────────────────────────────────────────
.PHONY: up
up: check-env          ## Start the CORE suite + auto-wire SSO/Office (plug-and-play)
	$(COMPOSE) up -d
	@bash scripts/configure.sh
	@echo "Up. Run 'make urls' for links, 'make doctor' to verify."

.PHONY: up-full
up-full: check-env     ## Start core + monitoring + ops, then auto-wire SSO/Office
	$(FULL) up -d
	@bash scripts/configure.sh

.PHONY: configure
configure: check-env   ## (Re)apply SSO + Office wiring (idempotent)
	@bash scripts/configure.sh

.PHONY: doctor
doctor: check-env      ## Health-check every service + print browser setup you must do
	@bash scripts/doctor.sh

.PHONY: up-build
up-build: check-env    ## Pull latest images then start core
	$(COMPOSE) pull && $(COMPOSE) up -d

.PHONY: down
down:                  ## Stop and remove containers (named volumes/data preserved)
	$(FULL) down

.PHONY: down-volumes
down-volumes:          ## Stop containers AND delete ALL data volumes (DESTRUCTIVE)
	@echo "WARNING: deletes databases, files, object storage — everything."
	@read -p "Type 'yes' to confirm: " c && [ "$$c" = "yes" ]
	$(FULL) down -v

.PHONY: restart
restart: check-env     ## Restart all core services
	$(COMPOSE) restart

.PHONY: stop
stop:                  ## Stop services without removing containers
	$(FULL) stop

# ── UPDATES ──────────────────────────────────────────────────────────────────
.PHONY: pull
pull:                  ## Pull latest images (bump tags in .env first)
	$(FULL) pull

.PHONY: update
update: pull           ## Pull and recreate (apps run their own migrations on boot)
	$(FULL) up -d

# ── STATUS / HEALTH / URLS ───────────────────────────────────────────────────
.PHONY: status
status:                ## Show container status + health
	$(FULL) ps

.PHONY: health
health:                ## Probe each core service's health endpoint
	@bash scripts/healthcheck.sh

.PHONY: urls
urls: check-env        ## Print every service URL + admin credentials
	@bash scripts/urls.sh

# ── LOGS ─────────────────────────────────────────────────────────────────────
.PHONY: logs
logs:                  ## Follow logs for all services
	$(FULL) logs -f --tail=100

.PHONY: logs-proxy
logs-proxy:            ## Follow edge proxy logs
	$(COMPOSE) logs -f --tail=100 proxy

.PHONY: logs-nextcloud
logs-nextcloud:        ## Follow Nextcloud app logs (install/upgrade)
	$(COMPOSE) logs -f --tail=100 nextcloud-app

.PHONY: logs-mattermost
logs-mattermost:       ## Follow Mattermost logs
	$(COMPOSE) logs -f --tail=100 mattermost

.PHONY: logs-keycloak
logs-keycloak:         ## Follow Keycloak logs
	$(COMPOSE) logs -f --tail=100 keycloak

.PHONY: logs-db
logs-db:               ## Follow Postgres logs
	$(COMPOSE) logs -f --tail=100 db

# ── APP ADMIN ────────────────────────────────────────────────────────────────
.PHONY: occ
occ:                   ## Run a Nextcloud occ command: make occ CMD="status"
	$(OCC) $(CMD)

.PHONY: nc-fix
nc-fix:                ## Apply Nextcloud recommended DB indices etc. (after first boot)
	$(OCC) db:add-missing-indices
	$(OCC) db:add-missing-columns
	$(OCC) maintenance:repair --include-expensive

.PHONY: nc-apps
nc-apps:               ## (Re)install required Nextcloud apps from GitHub (user_oidc, richdocuments)
	$(COMPOSE) exec -u root nextcloud-app sh /docker-entrypoint-hooks.d/before-starting/install-apps.sh

.PHONY: office-connect
office-connect:        ## Point Nextcloud Office at Collabora (auto-installs richdocuments if needed)
	@bash scripts/office-connect.sh

.PHONY: sso-connect
sso-connect:           ## Register Keycloak as an OIDC login provider in Nextcloud
	@bash scripts/sso-connect.sh

.PHONY: mmctl
mmctl:                 ## Run a Mattermost mmctl command: make mmctl CMD="user list"
	$(COMPOSE) exec mattermost mmctl --local $(CMD)

.PHONY: dbshell
dbshell:               ## psql into the shared Postgres (DB=nextcloud|mattermost|keycloak)
	$(COMPOSE) exec db psql -U $${POSTGRES_SUPER_USER:-mwadmin} -d $${DB:-postgres}

# ── SSO ──────────────────────────────────────────────────────────────────────
.PHONY: sso-info
sso-info: check-env    ## Print the OIDC endpoints + steps to connect Nextcloud & Mattermost
	@bash scripts/sso-info.sh

# ── BACKUP ───────────────────────────────────────────────────────────────────
.PHONY: backup
backup: check-env      ## Run an on-demand DB backup now (into the backups volume)
	$(FULL) run --rm backup /usr/local/bin/backup.sh

# ── OFFLINE / AIR-GAPPED ──────────────────────────────────────────────────────
.PHONY: fetch-nc-apps
fetch-nc-apps:         ## Pre-download Nextcloud apps for offline install (-> config/nextcloud/apps-offline)
	@bash scripts/fetch-nc-apps.sh

.PHONY: mirror-images
mirror-images:         ## Pull+save all images to a tar bundle (ENGINE-aware). Override: BUNDLE=...
	@bash scripts/mirror-images.sh save $(BUNDLE)

.PHONY: push-images
push-images:           ## Pull+retag+push all images to a registry: make push-images REGISTRY=reg.example.com/
	@bash scripts/mirror-images.sh push $(REGISTRY)

# ── KUBERNETES / HELM ─────────────────────────────────────────────────────────
HELM_CHART   := helm/magic-workflow
HELM_RELEASE ?= mw
HELM_NS      ?= magic
HELM_VALUES  ?= $(HELM_CHART)/values-dev.yaml

.PHONY: helm-lint
helm-lint:             ## Lint the umbrella Helm chart
	helm lint $(HELM_CHART)

.PHONY: helm-template
helm-template:         ## Render the chart with HELM_VALUES (default: values-dev.yaml)
	helm template $(HELM_RELEASE) $(HELM_CHART) -f $(HELM_VALUES)

.PHONY: helm-install
helm-install:          ## Install/upgrade into a cluster (HELM_RELEASE/HELM_NS/HELM_VALUES overridable)
	helm upgrade --install $(HELM_RELEASE) $(HELM_CHART) -n $(HELM_NS) --create-namespace -f $(HELM_VALUES)

.PHONY: helm-uninstall
helm-uninstall:        ## Remove the release (keeps PVCs)
	helm uninstall $(HELM_RELEASE) -n $(HELM_NS)

.PHONY: helm-sync
helm-sync:             ## Re-copy repo config/scripts into the chart's files/ dir
	@cp config/postgres/init-databases.sh $(HELM_CHART)/files/init-databases.sh
	@cp scripts/minio-init.sh $(HELM_CHART)/files/minio-init.sh
	@cp config/nextcloud/hooks/install-apps.sh $(HELM_CHART)/files/install-apps.sh
	@cp config/nextcloud/nginx.conf $(HELM_CHART)/files/nextcloud-nginx.conf
	@cp config/nextcloud/php/zz-custom.ini $(HELM_CHART)/files/php-custom.ini
	@cp config/loki/loki-config.yml $(HELM_CHART)/files/loki-config.yml
	@cp config/backup/backup.sh $(HELM_CHART)/files/backup.sh
	@echo "Synced repo config -> $(HELM_CHART)/files/ (nc-configure.sh is chart-only)"

# ── DOCS ─────────────────────────────────────────────────────────────────────
.PHONY: docs
docs:                  ## Serve the docs locally (http://127.0.0.1:8000)
	cd MagicWorkflow_Docs && (uv run mkdocs serve 2>/dev/null || mkdocs serve)

.PHONY: docs-build
docs-build:            ## Build the static docs site
	cd MagicWorkflow_Docs && (uv run mkdocs build 2>/dev/null || mkdocs build)

# ── HELP ─────────────────────────────────────────────────────────────────────
.PHONY: help
help:                  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
