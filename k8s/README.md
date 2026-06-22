# Kubernetes

The Kubernetes deployment lives in the umbrella Helm chart at
[`../helm/magic-workflow/`](../helm/magic-workflow/). It deploys the whole suite
— Nextcloud, Mattermost, Collabora, Keycloak, MinIO, PostgreSQL, Redis, optional
monitoring + backups — onto vanilla Kubernetes or OpenShift, mirroring the Docker
Compose stack.

Quick start:

```bash
helm install mw ../helm/magic-workflow -n magic --create-namespace \
  -f ../helm/magic-workflow/values-dev.yaml
```

Per-environment values: `values-dev.yaml`, `values-prod.yaml`,
`values-openshift.yaml`, `values-airgap.yaml`.

Full guide:

- **Chart reference** — [`helm/magic-workflow/README.md`](../helm/magic-workflow/README.md)
- **Docs → Kubernetes** — `MagicWorkflow_Docs/docs/kubernetes.md`

For large multi-node HA you may instead run the upstream per-app operators
(CloudNativePG, MinIO Operator, Keycloak/Mattermost operators) — see the docs.
