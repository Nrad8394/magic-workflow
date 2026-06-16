# =============================================================================
# Magic Workflow — Operations Makefile   (run `make` for the full list)
# =============================================================================

COMPOSE      := docker compose
FULL         := docker compose -f docker-compose.yml -f docker-compose.monitoring.yml
ENV_FILE     := .env
OCC          := $(COMPOSE) exec -u www-data nextcloud-app php occ

check-env:
	@test -f $(ENV_FILE) || (echo "ERROR: .env not found. Run: make setup" && exit 1)

# ── SETUP ────────────────────────────────────────────────────────────────────
.PHONY: setup
setup:                 ## First-time setup: .env + secrets + Keycloak realm + TLS cert
	@bash setup.sh

.PHONY: trust-cert
trust-cert:            ## Trust the local self-signed cert in your OS store (stops browser warnings)
	@bash scripts/trust-cert.sh

# ── LIFECYCLE ────────────────────────────────────────────────────────────────
.PHONY: up
up: check-env          ## Start the CORE suite (proxy, db, redis, minio, keycloak, apps)
	$(COMPOSE) up -d
	@echo "Up. Run 'make urls' for links, 'make logs' to watch boot."

.PHONY: up-full
up-full: check-env     ## Start core + monitoring + ops (Prometheus/Grafana/Loki/backup/watchtower)
	$(FULL) up -d

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
