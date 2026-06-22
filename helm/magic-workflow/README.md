# Magic Workflow — Helm chart

An umbrella chart that deploys the whole Magic Workflow suite — Nextcloud,
Mattermost, Collabora Online, Keycloak (SSO), MinIO (shared S3), PostgreSQL,
Redis, an optional monitoring stack (Prometheus/Grafana/Loki) and nightly
database backups — onto vanilla Kubernetes or OpenShift.

It mirrors the Docker Compose stack in the repo root: same images, same wiring
(shared MinIO, auto-installed Nextcloud apps, Keycloak realm import, SSO + Office
configuration), expressed as native Kubernetes objects. The edge nginx proxy is
replaced by an Ingress (or OpenShift Route).

## Layout

| File | Purpose |
|------|---------|
| `values.yaml` | All defaults (mirrors `.env`). |
| `values-dev.yaml` | kind / k3s / minikube, small footprint, plain HTTP. |
| `values-prod.yaml` | Managed cluster: cert-manager TLS, monitoring, backups. |
| `values-openshift.yaml` | Routes + SCC-safe pods. |
| `values-airgap.yaml` | Private-registry image prefix + pull secret. |
| `files/` | Init/wiring scripts mirrored from the repo (loaded via `.Files.Get`). |
| `templates/` | One file per component + Ingress/Route + hook Jobs. |

## Prerequisites

- Kubernetes 1.25+ (or OpenShift 4.12+), `helm` 3.10+.
- A default StorageClass that provisions **ReadWriteOnce** volumes (set
  `global.storageClass` to pick a specific one).
- An Ingress controller (e.g. ingress-nginx) on vanilla Kubernetes.
- DNS: each hostname in `hosts.*` must resolve to the Ingress/Route — **and
  resolve the same way from inside the cluster**, because Nextcloud calls
  Keycloak (OIDC discovery) and Collabora (WOPI) server-side over those public
  names. Use real DNS, a CoreDNS rewrite, or pod `hostAliases`.

## Quick start (dev)

```bash
helm install mw helm/magic-workflow -n magic --create-namespace \
  -f helm/magic-workflow/values-dev.yaml
kubectl -n magic get pods -w
```

## Production

```bash
# 1. Provide credentials out-of-band (recommended over values).
kubectl -n magic create secret generic mw-secrets \
  --from-literal=POSTGRES_SUPER_USER=mwadmin \
  --from-literal=POSTGRES_SUPER_PASSWORD=... \
  --from-literal=NEXTCLOUD_DB_PASSWORD=... \
  --from-literal=MATTERMOST_DB_PASSWORD=... \
  --from-literal=KEYCLOAK_DB_PASSWORD=... \
  --from-literal=MINIO_ROOT_USER=mwminio --from-literal=MINIO_ROOT_PASSWORD=... \
  --from-literal=S3_ACCESS_KEY=mw-app-access --from-literal=S3_SECRET_KEY=... \
  --from-literal=KEYCLOAK_ADMIN=admin --from-literal=KEYCLOAK_ADMIN_PASSWORD=... \
  --from-literal=OIDC_NEXTCLOUD_SECRET=... --from-literal=OIDC_MATTERMOST_SECRET=... \
  --from-literal=NEXTCLOUD_ADMIN_USER=admin --from-literal=NEXTCLOUD_ADMIN_PASSWORD=... \
  --from-literal=COLLABORA_USERNAME=admin --from-literal=COLLABORA_PASSWORD=... \
  --from-literal=GRAFANA_ADMIN_USER=admin --from-literal=GRAFANA_ADMIN_PASSWORD=... \
  --from-literal=MM_DATASOURCE='postgres://mattermost:...@mw-magic-workflow-postgres:5432/mattermost?sslmode=disable&connect_timeout=10'

# 2. Install (edit hosts + storageClass in values-prod.yaml first).
helm install mw helm/magic-workflow -n magic --create-namespace \
  -f helm/magic-workflow/values-prod.yaml --set existingSecret=mw-secrets
```

> The Keycloak **realm import** JSON embeds the two OIDC client secrets at
> template time, so even when you use `existingSecret` you must also pass
> `secrets.oidcNextcloudSecret` and `secrets.oidcMattermostSecret` (matching the
> values in your secret) so the imported realm agrees with what the apps send.
> Alternatively set `keycloak.importRealm=false` and configure the realm yourself.

## OpenShift

```bash
oc new-project magic
# Collabora needs MKNOD + a flexible UID — grant anyuid to the chart's SA:
helm template mw helm/magic-workflow -f helm/magic-workflow/values-openshift.yaml | oc apply -f -
oc adm policy add-scc-to-user anyuid -z mw-magic-workflow -n magic
oc -n magic rollout restart deploy/mw-magic-workflow-collabora
```

Routes are created automatically (`platform: openshift`); no Ingress controller
needed.

## Air-gapped

1. Mirror images: `make mirror-images REGISTRY=registry.internal.example.com`
   (or `scripts/mirror-images.sh push`).
2. Set `global.imageRegistry` (trailing slash) in `values-airgap.yaml` and a
   pull secret if the registry needs auth.
3. `helm install ... -f values-airgap.yaml`.

The Nextcloud `before-starting` hook downloads `user_oidc`, `richdocuments` and
`external` from GitHub. Offline, either bake them into a custom Nextcloud image
or allow egress to github.com for those release tarballs.

## Common overrides

| Value | Default | Notes |
|-------|---------|-------|
| `platform` | `kubernetes` | `openshift` for Routes + SCC. |
| `global.imageRegistry` | `""` | Private mirror prefix (trailing `/`). |
| `global.storageClass` | `""` | Applies to every PVC. |
| `hosts.*` | `*.magic.test` | Per-service hostnames. |
| `ingress.tls.wildcardSecretName` | `""` | One cert for all hosts. |
| `ingress.certManager.enabled` | `false` | Auto-issue per-host certs. |
| `monitoring.enabled` | `false` | Prometheus/Grafana/Loki/exporters. |
| `backup.enabled` | `false` | Nightly `pg_dumpall` CronJob. |
| `existingSecret` | `""` | Use a pre-created Secret for all credentials. |

## Notes & limitations

- Single-replica stateful components (Postgres, MinIO, Redis, Nextcloud,
  Mattermost) — this chart targets a self-hosted single-instance suite, not HA.
  For HA, run the upstream operators for each app.
- Nextcloud's app/web/cron share one RWO volume by running in **one pod**.
- Back up the MinIO PVC (user files) in addition to the database CronJob.
