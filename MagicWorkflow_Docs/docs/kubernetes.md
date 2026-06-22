# Kubernetes

Magic Workflow ships an **umbrella Helm chart** at
[`helm/magic-workflow/`](https://github.com/Nrad8394/magic-workflow/tree/main/helm/magic-workflow)
that deploys the whole suite onto vanilla Kubernetes or OpenShift. It mirrors the
Compose stack — same images, same wiring (shared MinIO, auto-installed Nextcloud
apps, Keycloak realm import, SSO + Office configuration) — as native objects. The
edge nginx proxy is replaced by an Ingress (or an OpenShift Route).

For large, multi-node HA you may still prefer the upstream per-app operators
(see *Building blocks* at the end); this chart targets a self-contained,
single-instance suite that's easy to run and back up.

## Prerequisites

- Kubernetes 1.25+ (or OpenShift 4.12+) and `helm` 3.10+.
- A default StorageClass providing **ReadWriteOnce** volumes
  (`--set global.storageClass=…` to pick one).
- An Ingress controller (e.g. ingress-nginx) on vanilla Kubernetes.
- **DNS:** every `hosts.*` name must resolve to the Ingress/Route — and resolve
  the same way *from inside the cluster*, because Nextcloud reaches Keycloak
  (OIDC discovery) and Collabora (WOPI) server-side over those public names.
  Use real DNS, a CoreDNS rewrite, or pod `hostAliases`.

## Quick start (dev cluster)

```bash
helm install mw helm/magic-workflow -n magic --create-namespace \
  -f helm/magic-workflow/values-dev.yaml
kubectl -n magic get pods -w
```

`values-dev.yaml` uses a small footprint and plain HTTP — good for kind / k3s /
minikube. For a quick look without DNS:

```bash
kubectl -n magic port-forward svc/mw-magic-workflow-nextcloud-web 8080:80
```

## Production

Provide credentials out-of-band as a Secret, then install with
`values-prod.yaml` (edit hostnames + `global.storageClass` first):

```bash
kubectl -n magic create secret generic mw-secrets \
  --from-literal=POSTGRES_SUPER_USER=mwadmin \
  --from-literal=POSTGRES_SUPER_PASSWORD=… \
  # … all keys (see helm/magic-workflow/README.md) …

helm install mw helm/magic-workflow -n magic --create-namespace \
  -f helm/magic-workflow/values-prod.yaml --set existingSecret=mw-secrets
```

`values-prod.yaml` enables cert-manager TLS (per-host certs via the configured
`clusterIssuer`), the monitoring stack, and the nightly `pg_dumpall` CronJob.

## OpenShift

```bash
oc new-project magic
helm template mw helm/magic-workflow -f helm/magic-workflow/values-openshift.yaml | oc apply -f -
# Collabora needs MKNOD + a flexible UID — grant anyuid to the chart SA:
oc adm policy add-scc-to-user anyuid -z mw-magic-workflow -n magic
oc -n magic rollout restart deploy/mw-magic-workflow-collabora
```

`platform: openshift` emits **Routes** (no Ingress controller needed) and drops
the pod `securityContext` so the `restricted-v2` SCC assigns the UID range.

## Air-gapped

Mirror the images to a private registry and point the chart at it — see the
[air-gapped guide](air-gapped.md):

```bash
make push-images REGISTRY=registry.internal.example.com/
helm install mw helm/magic-workflow -n magic --create-namespace \
  -f helm/magic-workflow/values-airgap.yaml
```

## What the chart creates

- StatefulSet: PostgreSQL. Deployments: Redis, MinIO, Keycloak, Nextcloud
  (fpm + nginx + cron in one pod), Mattermost, Collabora, Homer.
- A `post-install` Job seeds the MinIO buckets + scoped key (reuses
  `minio-init.sh`); Nextcloud's SSO/Office wiring runs as a `before-starting`
  hook (the in-cluster equivalent of `scripts/configure.sh`).
- Optional Prometheus/Grafana/Loki/promtail/node-exporter (`monitoring.enabled`)
  and a backup CronJob (`backup.enabled`).

See [`helm/magic-workflow/README.md`](https://github.com/Nrad8394/magic-workflow/blob/main/helm/magic-workflow/README.md)
for the full values reference.

## Building blocks for HA (alternative)

If you outgrow the single-instance chart, run the production operators per app
and point them at a shared DB/S3/realm:

| Component | Production option on K8s |
|-----------|--------------------------|
| Ingress / TLS | ingress-nginx (or Traefik) + cert-manager |
| Identity | [Keycloak Operator](https://www.keycloak.org/operator/installation) |
| PostgreSQL | [CloudNativePG](https://cloudnative-pg.io/) or Crunchy operator |
| Object storage | [MinIO Operator](https://min.io/docs/minio/kubernetes/upstream/) |
| Nextcloud | [Nextcloud Helm chart](https://github.com/nextcloud/helm) (S3 primary storage) |
| Mattermost | [Mattermost Operator](https://github.com/mattermost/mattermost-operator) |
| Monitoring | kube-prometheus-stack + Loki stack |

The Compose `.env` values map directly onto the chart values — same databases,
buckets and OIDC clients — so migration is a dump/restore + DNS cutover.
