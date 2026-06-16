# Magic Workflow

**A production-ready, self-hosted collaboration suite for organisations.**

Magic Workflow bundles the best open-source building blocks into one coherent,
single-sign-on platform that you run on your own infrastructure:

- **Nextcloud** — files, calendar, contacts, sharing
- **Collabora Online** — collaborative document editing (Nextcloud Office)
- **Mattermost** — team chat, calls, playbooks
- **Keycloak** — single sign-on (one login for everything)
- **MinIO** — one S3 object-storage pool backing all user files
- **PostgreSQL + Redis** — shared database and cache
- **nginx** — one TLS edge routing every service by hostname
- **Prometheus + Grafana + Loki** — monitoring & logs (optional profile)
- **Homer, Watchtower, automated backups** — operations

## Design principles

| Principle | What it means |
|-----------|---------------|
| **One identity** | Keycloak is the single source of truth for users; every app federates to it. |
| **One object store** | All files (Nextcloud + Mattermost) live in one MinIO pool — one thing to back up and scale. |
| **One edge** | A single nginx terminates TLS and routes by hostname. Only 80/443 are exposed. |
| **`.env`-driven** | The same Compose runs locally and in production; flip `BASE_DOMAIN` + `TLS_MODE`. |
| **Profiles** | Run lean (`core`) or full (`core + monitoring + ops`). |
| **Data in named volumes** | Portable across Linux/macOS/Windows; no host-path permission traps. |

## Where to go next

<div class="grid cards" markdown>

- :material-rocket-launch: **[Install locally](install-local.md)** — try the whole suite on your laptop in minutes.
- :material-server: **[Install on a server](install-server.md)** — real DNS, real TLS, production hardening.
- :material-sitemap: **[Architecture](architecture.md)** — how the pieces fit and talk.
- :material-account-key: **[Single sign-on](sso.md)** — wire Nextcloud + Mattermost to Keycloak.

</div>

## Requirements

| | Local trial | Small org (≤100 users) | Larger |
|---|---|---|---|
| CPU | 4 vCPU | 4–8 vCPU | 8+ |
| RAM | 8 GB | 16 GB | 32 GB+ |
| Disk | 20 GB | 100 GB+ | scale with files |
| Software | Docker 24+, Compose v2, openssl, make | same | + managed DB/object store |

!!! note "Kenya / locale"
    Defaults to `TZ=Africa/Nairobi`. Change it in `.env`.
