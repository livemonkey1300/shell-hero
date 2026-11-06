# Tilt + Helm + kind — Local Dev Guide

How to use **Tilt** to build an image, **load it into a `kind` cluster**, and
deploy it through your **Helm chart** for fast local development.

---

## Is Tilt the right tool?

**Yes — for local, multi-service development on kind, Tilt is one of the best choices.**

Why it fits:
- **Native kind support.** Tilt detects a `kind-*` kube-context and automatically
  loads built images straight into the kind nodes (`kind load docker-image` under
  the hood). **No registry, no `docker push`, no `imagePullPolicy` headaches.**
- **First-class Helm support.** Render and deploy your real chart, not a copy.
- **Live update.** Sync changed files into the running container and re-run a
  build step *without* rebuilding the image — sub-second loops.
- **A real UI** (`localhost:10350`) showing per-service logs, build status, and errors.

When something else is better:
- **Telepresence / mirrord** — if you want to run/debug **one** service as a local
  process (in your IDE, native speed) while the rest stays in the cluster.
- **Skaffold** — if you want the same loop but config-file-driven and more
  CI-aligned (it can reuse the exact same artifacts in pipelines).

For "iterate on several services live against a kind cluster with a nice UI," **stick with Tilt.**

---

## The key concept: how images get into kind

A `kind` cluster runs in Docker containers and has its **own** image store,
separate from your host Docker. A pod referencing `myapp:dev` will fail with
`ErrImagePull` because that tag only exists on your host — unless you either:

1. **Load** the image into kind's store: `kind load docker-image myapp:dev --name <cluster>`, **or**
2. Push to a registry kind can reach.

For local dev you want option 1 — and **Tilt does this automatically.** You almost
never call `kind load` yourself once Tilt is wired up.

> Crucial Helm detail: set **`imagePullPolicy: IfNotPresent`** (or `Never`) on the
> container. With the default `Always`, the kubelet ignores the locally-loaded
> image and tries to pull from a registry, which fails.

---

## 1. Create the kind cluster

```bash
kind create cluster --name dev
kubectl config current-context        # -> kind-dev
```

Optional config to expose a host port (so a NodePort/ingress is reachable):

```yaml
# kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - { containerPort: 30080, hostPort: 8080, protocol: TCP }
```
```bash
kind create cluster --name dev --config kind-config.yaml
```

---

## 2. The Helm chart bits that matter for kind

Make the image reference and pull policy configurable so dev can use a local tag.

```yaml
# mychart/values.yaml
image:
  repository: myapp
  tag: dev
  pullPolicy: IfNotPresent     # NOT "Always" — let kind use the loaded image
replicaCount: 1
service:
  type: ClusterIP
  port: 8080
```

```yaml
# mychart/templates/deployment.yaml (relevant lines)
containers:
  - name: app
    image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
    imagePullPolicy: {{ .Values.image.pullPolicy }}
    ports:
      - containerPort: 8080
```

---

## 3. The Tiltfile (the whole thing)

This is the complete dev wiring: build the image, deploy the Helm chart, forward ports.

```python
# Tiltfile

# --- safety: only ever deploy to local clusters ---
allow_k8s_contexts('kind-dev')              # refuse prod contexts by default

# --- 1. build the image ---
# Tilt tags it and, on a kind context, loads it into the cluster automatically.
docker_build(
    'myapp',                                # image name — must match values.yaml repository
    '.',                                    # build context
    dockerfile='Dockerfile',
    # live_update makes edits fast: sync files in + re-run a step, no image rebuild
    live_update=[
        sync('./src', '/app/src'),
        run('pip install -r requirements.txt', trigger=['./requirements.txt']),
    ],
)

# --- 2. deploy via your real Helm chart ---
# helm() renders the chart; k8s_yaml feeds the manifests to Tilt.
k8s_yaml(helm(
    './mychart',
    name='myapp',
    namespace='dev',
    values=['./mychart/values-dev.yaml'],   # optional dev overlay
    # set=['image.tag=dev'],                # or override individual values
))

# --- 3. expose ports & group logs ---
k8s_resource(
    'myapp',
    port_forwards=['8080:8080'],            # localhost:8080 -> container 8080
    labels=['backend'],
)
```

Run it:

```bash
tilt up            # opens the UI at http://localhost:10350
# edit code -> Tilt rebuilds/live-syncs -> redeploys automatically
tilt down          # tear down everything Tilt created
```

> Note on the image name: the string in `docker_build('myapp', ...)` **must match**
> `image.repository` in your chart. Tilt rewrites the deployed manifest to the
> exact tag it just built and loaded, so you don't hardcode tags.

### Using `helm_resource` instead (Tilt's extension)

If you prefer Tilt to run Helm directly (handles `helm install/upgrade` lifecycle):

```python
load('ext://helm_resource', 'helm_resource', 'helm_repo')

docker_build('myapp', '.')

helm_resource(
    'myapp',
    './mychart',
    namespace='dev',
    flags=['--create-namespace', '-f', './mychart/values-dev.yaml'],
    image_deps=['myapp'],                   # tie the release to the built image
    image_keys=[('image.repository', 'image.tag')],   # Tilt injects repo+tag
    port_forwards=['8080:8080'],
)
```

`image_deps` + `image_keys` is the clean way: Tilt passes the freshly built
repository and tag into the Helm release via `--set`, so kind always runs the
image you just built.

---

## 4. Doing it manually (no Tilt) — for reference

If you ever need to load an image into kind by hand and deploy with plain Helm:

```bash
# 1. Build on the host
docker build -t myapp:dev .

# 2. Load it into the kind cluster's image store
kind load docker-image myapp:dev --name dev

# 3. Verify it's there
docker exec -it dev-control-plane crictl images | grep myapp

# 4. Install the chart pointing at the local tag (pull policy must allow local)
helm upgrade --install myapp ./mychart -n dev --create-namespace \
  --set image.repository=myapp \
  --set image.tag=dev \
  --set image.pullPolicy=IfNotPresent

# 5. Forward the port
kubectl port-forward deploy/myapp 8080:8080 -n dev
```

Repeat steps 1–2 every time you change code — which is exactly the toil Tilt removes.

---

## 5. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `ErrImagePull` / `ImagePullBackOff` on a local tag | Image not in kind, or `pullPolicy: Always` | `kind load docker-image ...` (or let Tilt do it) **and** set `pullPolicy: IfNotPresent` |
| Tilt deploys but uses an old image | Pod cached an old layer with same tag | Tilt uses unique tags per build — ensure the chart reads the tag Tilt injects (don't hardcode `tag: dev` when using `image_keys`) |
| Tilt refuses to start | Context not allowed | Add it to `allow_k8s_contexts('kind-dev')` |
| Changes not reflected | No `live_update` and image rebuild slow | Add `sync()`/`run()` live_update rules |
| Port-forward not working | Wrong resource/port | Match `k8s_resource` name to the deployed workload; check `service.port` |

### Quick checklist
- [ ] kind cluster up, context is `kind-dev`
- [ ] `docker_build('myapp', ...)` name == chart `image.repository`
- [ ] chart `imagePullPolicy: IfNotPresent`
- [ ] `allow_k8s_contexts('kind-dev')` in Tiltfile
- [ ] `tilt up` → edit code → watch it redeploy
