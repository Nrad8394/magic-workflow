# Kubernetes

The Compose stack is the supported single-host deployment. For clusters, run each
component with its upstream, production-grade Helm chart / operator rather than
hand-translating this Compose file — they handle HA, scaling and upgrades.

## Recommended building blocks

| Component | Production option on K8s |
|-----------|--------------------------|
| Ingress / TLS | ingress-nginx (or Traefik) + cert-manager |
| Identity | [Keycloak Operator](https://www.keycloak.org/operator/installation) |
| PostgreSQL | [CloudNativePG](https://cloudnative-pg.io/) or Crunchy operator |
| Object storage | [MinIO Operator](https://min.io/docs/minio/kubernetes/upstream/) |
| Redis | Bitnami Redis chart / Redis operator |
| Nextcloud | [Nextcloud Helm chart](https://github.com/nextcloud/helm) (S3 primary storage) |
| Mattermost | [Mattermost Operator](https://github.com/mattermost/mattermost-operator) |
| Collabora | Collabora Online Helm chart |
| Monitoring | kube-prometheus-stack + Loki stack |

## Reference layout

```
namespace: magicworkflow
  ├─ cert-manager (cluster-wide)         TLS for all Ingresses
  ├─ ingress-nginx (cluster-wide)        single edge
  ├─ cnpg Cluster (postgres)             nextcloud / mattermost / keycloak DBs
  ├─ minio Tenant                        nextcloud + mattermost buckets
  ├─ redis
  ├─ keycloak (Keycloak CR + realm import)
  ├─ nextcloud (Helm release, S3 + redis + OIDC)
  ├─ mattermost (Mattermost CR, S3 + OIDC)
  └─ collabora
```

Each app's Ingress maps the same hostnames used by the Compose edge
(`cloud.`, `chat.`, `office.`, `id.`, …), so DNS and SSO config carry over
unchanged.

## Migration path

1. Stand up the cluster add-ons (cert-manager, ingress, CNPG, MinIO operator).
2. Restore the database dump (`pg_dumpall`) into the CNPG cluster.
3. Mirror the MinIO buckets (`mc mirror`) into the new MinIO tenant.
4. Deploy each app chart pointing at the shared DB/Redis/S3 + Keycloak realm.
5. Cut DNS over once verified.

The single-host Compose values (`.env`) map directly onto each chart's values —
same databases, same buckets, same OIDC clients.

> The companion single-app repos (`nextcloud-docker/k8s`,
> `mattermost-docker/k8s`) contain plain Kustomize manifests if you prefer a
> manifest-first start before adopting the operators.
