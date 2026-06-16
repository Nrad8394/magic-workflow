# Kubernetes

Magic Workflow's supported single-host deployment is the Docker Compose stack in
the repo root. For clusters, deploy each component with its upstream
production-grade Helm chart / operator rather than translating this Compose file
by hand — they provide HA, scaling and managed upgrades.

See the full guidance (recommended charts/operators, reference layout and a
migration path from Compose) in the docs:

- **MagicWorkflow_Docs → Kubernetes** (`MagicWorkflow_Docs/docs/kubernetes.md`)

Manifest-first starting points for the two main apps also live in the companion
single-app repos:

- `../nextcloud-docker/k8s/` — Kustomize manifests for Nextcloud
- `../mattermost-docker/k8s/` — Kustomize manifests for Mattermost
