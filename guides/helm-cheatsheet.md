# Helm Cheatsheet

Helm is the package manager for Kubernetes. A **chart** is the package, a
**release** is an installed instance of a chart, and **values** are the config
you override at install time.

> Tip: `alias h=helm` and `alias hl='helm list -A'`

---

## 1. Repositories

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add jetstack https://charts.jetstack.io
helm repo update                         # refresh local cache of all repos
helm repo list
helm repo remove bitnami

# Search
helm search repo nginx                   # search added repos
helm search hub wordpress                # search Artifact Hub (public)
helm search repo bitnami/postgresql --versions   # list all chart versions
```

---

## 2. Creating a Chart (scaffold)

```bash
# Scaffold a new chart with sane defaults (templates/, values.yaml, Chart.yaml...)
helm create mychart

# Resulting structure:
#   mychart/
#   ├── Chart.yaml          # chart metadata (name, version, appVersion)
#   ├── values.yaml         # default config values
#   ├── charts/             # subcharts / fetched dependencies live here
#   ├── templates/          # k8s manifests templated with Go templating
#   │   ├── _helpers.tpl
#   │   ├── deployment.yaml
#   │   ├── service.yaml
#   │   └── ...
#   └── .helmignore
```

`Chart.yaml` essentials:

```yaml
apiVersion: v2            # v2 = Helm 3
name: mychart
description: My application chart
type: application         # or "library"
version: 0.1.0            # chart version  -> bump on every chart change
appVersion: "1.0.0"       # version of the app being deployed (informational)
```

---

## 3. Dependencies (subcharts)

Declare dependencies in `Chart.yaml`:

```yaml
dependencies:
  - name: postgresql
    version: "15.5.x"
    repository: https://charts.bitnami.com/bitnami
    condition: postgresql.enabled        # toggle via values
  - name: redis
    version: "19.x.x"
    repository: https://charts.bitnami.com/bitnami
    alias: cache                         # optional rename
```

Manage them:

```bash
# Download deps listed in Chart.yaml into charts/ and write Chart.lock
helm dependency build          # uses existing Chart.lock if present
helm dependency update         # re-resolve versions and regenerate Chart.lock
helm dependency list           # show declared deps and their status
```

- **`helm dependency update`** — re-resolves versions from the repos and rewrites
  `Chart.lock`. Run this when you change a dependency version.
- **`helm dependency build`** — rebuilds `charts/` from the existing `Chart.lock`
  (reproducible; use in CI). If `Chart.lock` is missing it behaves like update.

> Subchart values are set under the subchart's name in your `values.yaml`:
> ```yaml
> postgresql:
>   enabled: true
>   auth:
>     username: app
> ```

---

## 4. Validating & Rendering (before installing)

```bash
helm lint ./mychart                      # static checks
helm template myrelease ./mychart        # render manifests locally (no cluster)
helm template myrelease ./mychart -f prod-values.yaml
helm install myrelease ./mychart --dry-run --debug   # render against the API server
```

---

## 5. Installing & Namespaces

```bash
# Install a release (release name = myapp) into a namespace, creating it if needed
helm install myapp ./mychart -n my-namespace --create-namespace

# From a repo chart instead of a local dir
helm install myapp bitnami/postgresql -n data --create-namespace

# Override values
helm install myapp ./mychart -n my-ns --create-namespace \
  --set image.tag=1.2.3 \
  --set replicaCount=3 \
  -f custom-values.yaml                  # -f files layer on top; later wins

# Pin a chart version
helm install myapp bitnami/nginx --version 15.4.4 -n web --create-namespace

# install-or-upgrade in one idempotent command (great for CI/CD)
helm upgrade --install myapp ./mychart -n my-ns --create-namespace -f values.yaml

# Wait until resources are Ready (or roll back on timeout)
helm install myapp ./mychart -n my-ns --create-namespace --wait --timeout 5m --atomic
```

> Helm does **not** create namespaces unless you pass `--create-namespace`.
> The namespace also scopes where the release is recorded.

---

## 6. Upgrading, Rolling Back, Uninstalling

```bash
helm upgrade myapp ./mychart -n my-ns -f values.yaml
helm upgrade myapp ./mychart -n my-ns --set image.tag=2.0.0 --reuse-values

helm history myapp -n my-ns              # list revisions
helm rollback myapp 1 -n my-ns           # roll back to revision 1
helm rollback myapp -n my-ns             # roll back to the previous revision

helm uninstall myapp -n my-ns            # remove the release
helm uninstall myapp -n my-ns --keep-history
```

---

## 7. Inspecting Releases & Values

```bash
helm list                                # releases in current namespace
helm list -A                             # all namespaces
helm list -a                             # include failed/pending too

helm status myapp -n my-ns               # release status + notes
helm get values myapp -n my-ns           # user-supplied values
helm get values myapp -n my-ns -a        # ALL computed values (incl. defaults)
helm get manifest myapp -n my-ns         # rendered manifests that were applied
helm get notes myapp -n my-ns
helm get all myapp -n my-ns              # everything about the release

# Show chart metadata / default values WITHOUT installing
helm show chart bitnami/postgresql
helm show values bitnami/postgresql      # the chart's default values.yaml
helm show readme bitnami/postgresql
```

---

## 8. Packaging & Publishing

```bash
helm package ./mychart                   # -> mychart-0.1.0.tgz
helm package ./mychart --version 0.2.0 --app-version 1.1.0

# Push to an OCI registry (Helm 3.8+)
helm push mychart-0.1.0.tgz oci://registry.example.com/charts

# Install directly from OCI
helm install myapp oci://registry.example.com/charts/mychart --version 0.1.0
```

---

## 9. Typical Workflow (cheat-recipe)

```bash
# 1. Scaffold
helm create mychart

# 2. Add a dependency in Chart.yaml, then pull it
helm dependency update ./mychart

# 3. Lint and preview the rendered output
helm lint ./mychart
helm template myapp ./mychart -f values.yaml | less

# 4. Dry-run against the cluster
helm upgrade --install myapp ./mychart -n my-ns --create-namespace \
  -f values.yaml --dry-run --debug

# 5. Real install (idempotent), wait for Ready, auto-rollback on failure
helm upgrade --install myapp ./mychart -n my-ns --create-namespace \
  -f values.yaml --wait --atomic --timeout 5m

# 6. Verify
helm status myapp -n my-ns
helm get values myapp -n my-ns -a
kubectl get all -n my-ns
```

---

## 10. Quick Flag Reference

| Flag | Purpose |
| --- | --- |
| `-n <ns>` | Target namespace |
| `--create-namespace` | Create the namespace if absent |
| `-f file.yaml` | Values file (repeatable; later overrides earlier) |
| `--set key=val` | Inline value override (highest precedence) |
| `--set-file key=path` | Set a value from a file's contents |
| `--version X.Y.Z` | Pin chart version |
| `--dry-run --debug` | Render without applying |
| `--wait` | Block until resources are Ready |
| `--atomic` | Roll back automatically if the install/upgrade fails |
| `--reuse-values` | Keep previous values, apply only new overrides |
| `--timeout 5m` | Max wait duration |
