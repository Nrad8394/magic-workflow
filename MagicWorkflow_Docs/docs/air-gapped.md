# Air-gapped / offline install

Magic Workflow can run with **no internet** on the target host. Two things
normally reach the network at install time — container images and the Nextcloud
app tarballs — and both can be pre-staged from a connected machine.

## 1. Mirror the container images

On a machine **with** internet (and the same engine, Docker or Podman):

=== "To a private registry (recommended)"

    ```bash
    make push-images REGISTRY=registry.internal.example.com/
    ```

    Then tell the stack to pull from it:

    - **Compose:** set `IMAGE_REGISTRY=registry.internal.example.com/` in `.env`.
    - **Helm:** set `global.imageRegistry: registry.internal.example.com/`
      (see `values-airgap.yaml`).

=== "To a tar bundle (no registry)"

    ```bash
    make mirror-images                 # -> magic-workflow-images.tar
    # copy the tar to the air-gapped host, then:
    bash scripts/mirror-images.sh load magic-workflow-images.tar
    ```

The image list and tags come from `.env`, so they always match the stack.
`scripts/mirror-images.sh list` prints exactly what will be mirrored.

## 2. Pre-stage the Nextcloud apps

Nextcloud auto-installs `user_oidc`, `richdocuments` and `external` from GitHub
on first boot. Fetch them ahead of time (connected machine):

```bash
make fetch-nc-apps     # -> config/nextcloud/apps-offline/*.tar.gz
```

Copy `config/nextcloud/apps-offline/` to the air-gapped checkout. `install-apps.sh`
installs from there first and only falls back to GitHub if a tarball is missing —
so the offline host never needs egress.

> Keep the versions in `scripts/fetch-nc-apps.sh` in sync with
> `config/nextcloud/hooks/install-apps.sh` when you upgrade Nextcloud.

## 3. TLS without ACME

Let's Encrypt needs outbound reachability, so offline installs supply certs
directly:

- **Compose:** drop your `fullchain.pem` / `privkey.pem` into `config/proxy/tls/`
  (keep `TLS_MODE=selfsigned` to skip ACME), or run `make setup` for a
  self-signed cert.
- **Helm:** create a TLS Secret and set `ingress.tls.wildcardSecretName`
  (`values-airgap.yaml` does this) — leave `ingress.certManager.enabled=false`.

## 4. Install

=== "Compose"

    ```bash
    make setup
    make up-full          # images now come from IMAGE_REGISTRY
    make doctor
    ```

=== "Kubernetes"

    ```bash
    helm install mw helm/magic-workflow -n magic --create-namespace \
      -f helm/magic-workflow/values-airgap.yaml
    ```

## Checklist

- [ ] Images mirrored (`push-images` or `mirror-images save`/`load`)
- [ ] `IMAGE_REGISTRY` / `global.imageRegistry` set
- [ ] Nextcloud apps staged in `config/nextcloud/apps-offline/`
- [ ] TLS certs provided (no ACME)
- [ ] Registry pull secret created if the registry needs auth (`imagePullSecrets`)
