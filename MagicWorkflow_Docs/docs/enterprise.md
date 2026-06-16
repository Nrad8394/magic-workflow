# Enterprise guide

Guidance for running Magic Workflow at organisational scale.

## High availability

The bundled Compose is a **single-host** reference. For HA, externalise the
stateful tiers and run the stateless apps in multiples:

| Tier | HA approach |
|------|-------------|
| PostgreSQL | Managed/clustered Postgres (Patroni, RDS, Cloud SQL). Point each app's `*_DB_*` at it; drop the `db` service. |
| Object storage | Distributed MinIO (erasure coding) or cloud S3. |
| Redis | Redis Sentinel/cluster or managed (ElastiCache/Memorystore). |
| Nextcloud | Multiple FPM replicas behind the web tier (state is in S3 + DB + Redis). |
| Mattermost | Enterprise HA mode + S3 file store (already wired). |
| Keycloak | Multiple replicas with a shared DB + Infinispan cache stack. |
| Edge | Run the proxy on 2+ nodes behind an L4 load balancer, or move TLS to it. |

For full clustering, migrate to [Kubernetes](kubernetes.md) with the upstream
Helm charts / operators (Nextcloud, Mattermost operator, Keycloak operator,
MinIO operator, CloudNativePG).

## Identity & access

- Federate Keycloak to your corporate **LDAP/AD** (User Federation) or chain to
  an upstream IdP (Azure AD, Google, Okta) as an Identity Provider.
- Use Keycloak **groups/roles** to drive app permissions; map claims into
  Nextcloud groups and Mattermost teams.
- Enforce MFA, password policies and session limits centrally in Keycloak.
- Keep one **break-glass** local admin per app for IdP outages.

## Security hardening

- Only 80/443 exposed; all backends are on the internal network.
- `no-new-privileges` on infrastructure containers; read-only roots where supported.
- Secrets are random by default — store `.env` in a secrets manager; `chmod 600`.
- Terminate TLS with strong ciphers (TLS 1.2/1.3 configured); enable HSTS (set).
- Turn on app-level protections: Nextcloud server-side encryption + antivirus
  (ClamAV), Mattermost compliance exports, brute-force protection.
- Enable object-store + DB encryption at rest on your storage layer.

## Compliance & data residency

- All data stays on infrastructure **you** control — key for data-residency
  requirements (e.g. Kenya Data Protection Act, GDPR).
- Centralised audit: Keycloak events, Nextcloud audit log, Mattermost compliance
  exports — ship them to Loki/SIEM.
- Document retention via backup policy + MinIO object lifecycle rules.

## Capacity planning

| Users | App RAM (total) | DB | Object storage |
|-------|-----------------|-----|----------------|
| ≤ 100 | 8–12 GB | 2 GB | grows with files |
| 100–1000 | 16–32 GB | 4–8 GB | distributed |
| 1000+ | externalise everything; horizontal scale | managed cluster | distributed/cloud |

## Cost model

Self-hosting trades per-seat SaaS fees for infrastructure + ops time. The whole
suite is open-source (Mattermost Team Edition, Nextcloud, Keycloak, MinIO,
Collabora CODE are free); only optional Enterprise features (Mattermost E-plans)
carry licences.

## Support & updates

- Track upstream releases; subscribe to security advisories for each component.
- Stage upgrades on a non-prod copy (restore a backup) before production.
- Use Watchtower (opt-in by label) for patch automation on stateless services
  only; gate stateful upgrades behind manual review + backups.
