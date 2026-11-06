# Kubernetes Field Manual

> A → Z: build · ship · debug · harden · air-gap
> Generated 2026-09-21. Commands marked *version-sensitive* are exactly that — check your **server** version (`kubectl version`) before relying on anything newer than your cluster.

## Contents

 1. [Every recommendation, one page](#01-every-recommendation-one-page)
 2. [The model underneath](#02-the-model-underneath)
 3. [Toolbelt and daily kubectl](#03-toolbelt-and-daily-kubectl)
 4. [Images: Dockerfile to signed OCI](#04-images-dockerfile-to-signed-oci)
 5. [A dev cluster, and the inner loop](#05-a-dev-cluster-and-the-inner-loop)
 6. [Helm, values and CRDs](#06-helm-values-and-crds)
 7. [Kustomize and the repo split](#07-kustomize-and-the-repo-split)
 8. [GitOps: Argo CD and Flux](#08-gitops-argo-cd-and-flux)
 9. [Across the air gap](#09-across-the-air-gap)
10. [Security audit you can run](#10-security-audit-you-can-run)
11. [When it breaks](#11-when-it-breaks)
12. [Day-2 ops and observability](#12-day-2-ops-and-observability)
13. [Portals and dashboards](#13-portals-and-dashboards)
14. [One-screen kubectl reference](#14-one-screen-kubectl-reference)

---


<a id="01-every-recommendation-one-page"></a>

## 01 · Every recommendation, one page

Every recommendation this guide makes, in one table, with the reason. If you read nothing else, read this and the chapter for whichever line you're about to disagree with.

**Defaults are for when you have no reason to choose otherwise.** Where a line says "close call", it means the alternative is genuinely defensible and the tiebreaker is named.

#### The stack

| Decision | Pick | Why | Chapter |
|---|---|---|---|
| Local cluster | **kind** | Upstream kubeadm, so what you debug locally is what runs in prod; the same config file runs in CI unchanged. k3d if you only need a fast smoke test | 05 |
| Build images | **docker buildx** (+ `docker-bake.hcl`) | BuildKit cache mounts and multi-arch are table stakes; bake gives you one dependency graph instead of a pile of scripts. `ko` if it's pure Go | 04 |
| Base image (Python) | **`python:3.13-slim`** pinned by digest | musl on alpine forces source builds of every wheel and changes DNS/thread behaviour | 04 |
| Base image (Go) | **`distroless/static-debian12:nonroot`** | CA certs, tzdata and a nonroot passwd entry for ~2 MB. `scratch` only if you'll supply those yourself | 04 |
| Inner dev loop | **Tilt** | Per-workload resources, live_update file sync, and `local_resource` for codegen/tests. Skaffold if the same file must serve dev *and* CI | 05 |
| Package apps | **Helm**, charts shipped as **OCI** | Every vendor ships a chart; OCI means charts move exactly like images, including through an air gap | 06 |
| Environment overlays | **Kustomize on top of Helm output**, or plain values layering | Kustomize for "same thing, slightly different"; don't template what you can patch | 07 |
| Many releases at once | **Argo CD** (multi-source / ApplicationSet) | It reconciles continuously — helmfile tells you what the last person applied, Argo tells you what is true now. helmfile only when you cannot run a controller | 06, 08 |
| GitOps engine | **Argo CD** — *close call* | Tiebreaker: the UI plus `AppProject` is the difference between seeing *which* Application is stuck and seeing that *something* timed out. Pick **Flux** instead if your team lives in the terminal, you run many clusters, and you are Helm-heavy — Flux runs a real Helm release, so hooks, history and rollback behave | 08 |
| Ordering across releases | **Argo sync-waves** (or Flux `dependsOn`) | Helm has no ordering primitive inside a release beyond hook weights | 06, 08 |
| Secrets | **External Secrets Operator** + OpenBao/Vault | The only option where the secret never enters the chart, the repo, or the render — so rotation needs no deploy and `helm template` output is safe to paste in a ticket | 06, 08 |
| Registry (connected) | **Harbor** | Scanning, replication, proxy cache, robot accounts, quotas | 03 |
| Registry (air-gapped) | **Zot** | A single static binary with no database, and no vulnerability feed that degrades into a permanent error banner offline | 03, 09 |
| Air-gap export | **`skopeo copy` into one OCI layout** | Daemonless, dedupes layers, preserves digests, has `--retry-times`. `docker save` silently discards every platform but the host's | 09 |
| Registry rewrite on the far side | **Node-level mirror** (`hosts.toml` / `registries.conf` / `ImageDigestMirrorSet`) | The only approach that preserves the digest you shipped and leaves the chart untouched | 09 |
| Policy engine | **Kyverno** | Policies are Kubernetes YAML the manifest authors can read, and `mutateDigest` pins a tag to a digest at admission. Gatekeeper only if you already run Rego elsewhere | 10 |
| Image scanning | **Trivy**, gated on `--severity HIGH,CRITICAL --ignore-unfixed` | A gate that fires on 400 findings gets disabled within a week | 10 |
| Signing | **cosign**, signing the **digest** | Signing a tag signs whatever it pointed at that second. Air-gapped builds use a key pair, not keyless — keyless needs a reachable transparency log | 04, 09 |
| Observability | **kube-prometheus-stack** + Loki + Tempo + **Alloy** | ServiceMonitor/PodMonitor/PrometheusRule are the lingua franca every chart's `metrics.serviceMonitor.enabled` flag targets | 12 |
| Cluster UI | **k9s** for you, **Headlamp** for everyone else, **Argo CD's UI** for "what's deployed" | Covers operate and deliver with no SaaS dependency, no licence, and a footprint you can ship in a bundle | 13 |
| Backups | **Velero**, with a *rehearsed restore* | The only add-on whose absence you discover at the worst possible moment | 12 |
| Manifest validation | **kubeconform** in CI | Schema validation catches most typos before the API server does | 07 |

#### The positions worth arguing about

These are opinions, not consensus. Each is stated with its reason so you can overrule it deliberately.

| Position | Reason |
|---|---|
| **Drop CPU limits. Keep CPU requests. Always keep memory limits.** | CPU is compressible — contention degrades gracefully and requests already guarantee a floor. A CPU limit buys nothing at low utilization and costs tail latency at high. Memory is not compressible: without a limit, one leak takes the node. Exception: hostile multi-tenancy, or certifying deterministic capacity |
| **Liveness checks self. Readiness checks dependencies. Startup covers boot.** | A liveness probe that dials the database turns one backing-service blip into a cluster-wide restart storm. The probe amplifies the fault it was meant to detect |
| **Dependency waits go in init containers, bounded.** | Fail fast beats hang. A pod blocking forever emits no signal at all, which is the worst state for an operator |
| **`values.schema.json` is the highest-leverage file you can add to a chart.** | Helm does not error on unknown values. A typo'd key is silent until 3 a.m.; a schema makes it an instant local error |
| **Server-side apply everywhere, especially CRDs.** | Client-side apply stores the whole object in an annotation capped at 262144 bytes. cert-manager's `issuers` CRD is ~311 KB and simply fails |
| **Separate the operator/CRD release from the app release.** | Same lifecycle → same release; different lifecycle → different release. It is also the only way to get independent rollback |
| **One controller owns each object.** | Argo self-healing against Tilt, or Terraform against Argo, is not redundancy — it is a fight you will debug at the wrong layer |
| **`kubectl wait --for=condition`, never `sleep`.** | A `sleep 30` in a deploy script is a bet on machine speed, and CI eventually loses it |
| **Never build a merged mega-kubeconfig.** | One file per cluster, selected by direnv, prod file `0400`. A merged config means one absent-minded `delete` lands wherever the last `use-context` left you |
| **Adopt an operator only if it works fully offline**, with no telemetry or licence check | Otherwise a StatefulSet, where direct control of the upgrade path beats the automation |
| **Prove air-gap fitness empirically, not by reading YAML.** | Default-deny NetworkPolicy on a CNI that actually enforces it, then watch the drops while you exercise the product |

#### One-way doors — decide these slowly

Everything else in this guide is reversible. These are not.

| Door | What it costs to change |
|---|---|
| **Autopilot vs Standard** (GKE) | Cannot be converted. Autopilot means no privileged workloads, no on-demand DaemonSets, and Warden mutates every pod spec |
| **Cluster name, region, zonal vs regional** | Immutable — changing any destroys and recreates the cluster |
| **Pod / service / master CIDR ranges** | Not editable after creation; a too-small pod CIDR caps node count permanently |
| **The CNI** | Replacing Dataplane V2 / Calico / Cilium is a cluster rebuild |
| **Adopting a service mesh** | Rewrites the traffic, identity and observability model. *Not* adopting one is cheap to reverse; adopting one is not |
| **Single vs multi-cluster tenancy** | Namespace-per-tenant → cluster-per-tenant means redoing ingress, identity and GitOps topology |
| **PVC size and StorageClass** | **PVCs only grow**, and in a StatefulSet `volumeClaimTemplate` the size is immutable. Too small wedges `helm upgrade`; too large is paid for forever |
| **Removing a CRD stored version** | You cannot drop a version still in `status.storedVersions`; force it and stored objects become unreadable |
| **Namespace force-finalize** | Abandons whatever the finalizer was going to clean up — orphaned volumes, load balancers and DNS records that keep billing |
| **Argo CD vs Flux** | Reversible, but expensive: weeks of re-plumbing waves ↔ `dependsOn`, ApplicationSets ↔ Kustomization fan-out, and re-teaching everyone |

#### If you are starting today, in order

1. Chapter 03 — install the toolbelt, set up direnv-per-cluster kubeconfigs, put the context in your prompt.
2. Chapter 05 — `kind` cluster with a local registry, ingress, metrics-server. Three minutes, disposable.
3. Chapter 04 — one service, multi-stage Dockerfile, digest-pinned base, pushed to the local registry.
4. Chapter 05 again — a Tiltfile that gets you under 30 seconds edit-to-running.
5. Chapter 06 — put it in a chart with a `values.schema.json` and layered values.
6. Chapter 08 — point Argo CD at it. Now you have the real deploy path, locally.
7. Chapter 10 — run the 15-minute audit against your own kind cluster. Fix what it finds.
8. Chapter 12 — add probes, a PDB, resources and the four alerts that matter.
9. Chapter 09 — only when you actually need to cross a gap. It is the hardest chapter and it assumes the rest.


---


<a id="02-the-model-underneath"></a>

## 02 · The model underneath

Everything in this guide is downstream of four ideas. If they're solid, the rest is vocabulary. If they're fuzzy, no amount of `kubectl` memorisation will help.

#### 1. It is a database with controllers attached

The API server is a REST API in front of etcd. That is the whole product. Every object you create is a **row you wrote saying what you want**. Nothing happens because you wrote it — something happens because a **controller** is watching that kind of row and works to make reality match.

```
   you ──apply──▶ API server ──stores──▶ etcd
                      │
                      └──watch──▶ controller ──acts──▶ reality
                                      │
                                      └──writes .status──▶ API server
```

Two direct consequences you will use constantly:

- **`spec` is what you want. `status` is what is.** When they disagree, some controller is either working, stuck, or absent. Your first diagnostic question is always *which controller owns this, and is it running?*
- **Reconciliation is level-triggered, not edge-triggered.** A controller is handed a *name*, reads current state, and drives toward desired. It does not process a queue of your edits. So a missed event is harmless, a controller restart is harmless, and applying the same manifest a thousand times is harmless. **Idempotence is the contract.**

#### 2. The object graph you actually touch

```
Deployment ──owns──▶ ReplicaSet ──owns──▶ Pod ──runs──▶ Container(s)
     │                                      │
     │                                      ├── mounts ConfigMap / Secret / PVC
     │                                      └── uses ServiceAccount (identity)
     ▼
  Service ──selects by LABEL──▶ Pods ──▶ EndpointSlice (the Ready ones only)
     ▲
     └── Ingress / Gateway + HTTPRoute ──▶ Service
```

**Labels are the only join.** A Service does not reference pods; it declares a label selector and the endpoint controller fills in whatever matches. That is why the single most common Kubernetes bug is a selector that matches nothing, and why it produces no error — an empty result set is a valid result set.

`ownerReferences` is the other edge: it drives cascading deletion and is what `kubectl tree` renders. Delete a Deployment and the ReplicaSet and Pods go with it, because they point *up* at their owner.

#### 3. Workload kinds, and how to pick

| Kind | Identity | Storage | Use for |
|---|---|---|---|
| **Deployment** | interchangeable, random names | none or shared | stateless services — the default |
| **StatefulSet** | stable ordinal names, stable DNS | one PVC per replica, retained | databases, brokers, anything with quorum or replication |
| **DaemonSet** | one per node | node-local | log shippers, CNI agents, node exporters |
| **Job** | runs to completion | ephemeral | migrations, one-shot work |
| **CronJob** | Job on a schedule | ephemeral | backups, reports |

Picking wrong is expensive later: moving a stateful service from Deployment to StatefulSet means renaming every pod and rebinding every volume.

#### 4. Everything above Pod is a pattern, not a primitive

The kubelet only knows how to run a **Pod**. Deployment, StatefulSet, DaemonSet and every operator you install are controllers that create Pods on your behalf. An **operator** is exactly this pattern applied to a domain: a CRD registers a new row type, and a controller watches those rows and creates the Deployments, Services and Secrets a database (or a message broker, or a certificate) actually needs.

This is why the troubleshooting method is always the same regardless of how exotic the resource is: **find the controller, read its logs, check its RBAC, read the `.status.conditions` on the object it owns.** Whether the controller is `kube-controller-manager` or a PostgreSQL operator makes no difference to the method.

#### The words that trip people up

| Term | What it actually is |
|---|---|
| **Namespace** | A name-scoping and RBAC boundary. **Not** a security boundary by itself — that takes NetworkPolicy + PSA + RBAC together |
| **Node** | A machine registered with the cluster. `kubectl get nodes` lists them; the kubelet on each one is an agent, not a manager |
| **Control plane** | API server + etcd + scheduler + controller-manager (+ cloud-controller-manager). On managed clusters you do not see it |
| **Scheduler** | Decides *which node* a Pod goes to, once. It does not move running pods |
| **kubelet** | The per-node agent that actually starts containers and reports status |
| **kube-proxy** | Programs iptables/IPVS so a Service ClusterIP routes to endpoints. Increasingly replaced by eBPF dataplanes |
| **CNI** | The plugin that gives pods IPs and implements (or ignores) NetworkPolicy |
| **CRI** | The container runtime interface — containerd or CRI-O. Docker is not a runtime in modern clusters |
| **Ephemeral container** | A container injected into a *running* pod for debugging. Cannot be added to a pod spec ahead of time |

#### The mental model in one paragraph

You write rows describing desired state. Controllers watch rows and drive reality toward them, writing back status. Labels connect rows to each other. Everything above `Pod` — including every operator — is that same loop wearing a different hat. When something is wrong, you are asking one of exactly three questions: *did my row get accepted?* (admission, schema, quota), *is the controller that owns this row running and permitted?* (logs, RBAC), or *is reality refusing?* (scheduling, image pull, the process itself).


---


<a id="03-toolbelt-and-daily-kubectl"></a>

## 03 · Toolbelt and daily kubectl

### Chapter A — Your toolbelt

Fedora-verified where marked **[dnf]**. `direnv fzf helm jq k9s skopeo trivy yq` are all packaged; `kubectx`/`stern`/`dive` are not.

#### The base layer

```bash
# kubectl from the official k8s repo (pkgs.k8s.io)
sudo dnf install -y kubernetes-client

# [dnf] the ones Fedora ships — take these, don't hand-roll binaries
sudo dnf install -y jq yq k9s helm skopeo direnv fzf trivy
# Fedora's `yq` IS mikefarah/yq v4, not the python wrapper. Good.

# kubecolor — colourises kubectl output, drop-in
go install github.com/kubecolor/kubecolor@latest   # or download the release binary
```

#### krew + the plugins that earn their slot

```bash
(
  set -x; cd "$(mktemp -d)"
  OS="$(uname | tr '[:upper:]' '[:lower:]')"; ARCH="$(uname -m | sed -e 's/x86_64/amd64/')"
  KREW="krew-${OS}_${ARCH}"
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz"
  tar zxvf "${KREW}.tar.gz" && ./"${KREW}" install krew
)
# zsh
echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> ~/.zshrc

kubectl krew install ctx ns neat tree view-secret df-pv score explore whoami access-matrix images resource-capacity
```

| Plugin | The one thing it's for |
|---|---|
| `ctx` / `ns` | Switch context/namespace interactively (this is kubectx/kubens — no separate install) |
| `neat` | Strip `managedFields`, `status`, defaults from `-o yaml` so it's re-appliable |
| `tree` | Show the ownerRef tree: Deployment → RS → Pods, or a CR → everything it spawned |
| `view-secret` | Decode a Secret without a base64 pipeline |
| `df-pv` | Actual disk usage inside PersistentVolumes — what `kubectl top` won't tell you |
| `score` | Static scoring of manifests (kube-score, as a plugin) |
| `explore` | Interactive `kubectl explain` — walk the schema instead of guessing paths |
| `whoami` | Which identity am I actually authenticating as (native `kubectl auth whoami` needs 1.27+) |
| `access-matrix` | Full RBAC matrix for a verb/resource — "who can delete secrets here" |
| `images` | Every image running in the cluster, deduped |
| `resource-capacity` | requests/limits vs allocatable, per node. The capacity-planning view |

#### Tools not in dnf (release binaries)

```bash
# stern — multi-pod, multi-container log tailing with colour
curl -fsSL https://github.com/stern/stern/releases/latest/download/stern_linux_amd64.tar.gz \
  | tar xz -C ~/.local/bin stern

# crane — registry surgery: copy, retag, digest, without a docker daemon
go install github.com/google/go-containerregistry/cmd/crane@latest

# helm-diff — the single most valuable helm plugin
helm plugin install https://github.com/databus23/helm-diff
```

Also worth having: **dive** (inspect image layers, find the 400 MB package cache you forgot to `rm`), **oras** (push/pull arbitrary OCI artifacts), **helmfile**, **kubent** (scan a live cluster for API versions removed in the next k8s release), **popeye** (cluster sanity report), **velero** (backup/restore + PV snapshots — the only real answer to "restore the namespace"), **kubescape** (NSA/CIS/MITRE posture scan, emits JSON a CI job can gate on).

`skopeo copy` + `crane` are the pair for moving images between registries without a daemon. `trivy image --severity HIGH,CRITICAL --exit-code 1` is a CI gate, not a log line. `dive --ci` gives you a wasted-space threshold that fails a build.

#### k9s

Config at `~/.config/k9s/config.yaml`; skins at `~/.config/k9s/skins/*.yaml` (set `ui.skin: <name>`, no extension). Hotkeys at `hotkeys.yaml`, aliases at `aliases.yaml`.

| Key | Does |
|---|---|
| `:` then resource | Jump (`:po`, `:deploy`, `:ns`, `:ctx`, `:events`) |
| `/` | Filter; `/!term` inverts; `/-l app=foo` label-filters |
| `l` `d` `y` `e` | Logs, describe, YAML, edit |
| `s` `a` | Shell into container, attach |
| `Ctrl-d` `Ctrl-k` | Delete, kill (no grace) |
| `Shift-c` / `Shift-m` | Sort by CPU / memory |
| `p` | Previous container logs |
| `0-9` | Log tail window; `f` toggles fullscreen logs |
| `x` | xray view (ownership tree) — `:xray deploy` |
| `Ctrl-a` | List every known resource alias |

**Make prod loud:** k9s config is per-context under `~/.config/k9s/clusters/<ctx>/`. A red skin on the prod context is the cheapest guard-rail you will ever build.

#### zsh: aliases and functions that earn their keep

```zsh
alias k='kubecolor'
compdef kubecolor=kubectl            # zsh completion for the alias
alias kgp='k get pods -o wide'
alias kgpa='k get pods -A -o wide'
alias kdp='k describe pod'
alias kaf='k apply -f'
alias kgy='k get -o yaml'
alias kn='k neat'
alias kctx='k ctx'
alias kns='k ns'
alias kev='k events --sort-by=.lastTimestamp'

# follow logs of a pod, all containers
klf() { k logs -f --all-containers=true --max-log-requests=20 "$@"; }

# exec a shell, trying bash then sh
kex() {
  local pod="$1"; shift
  k exec -it "$pod" "$@" -- sh -c 'command -v bash >/dev/null && exec bash || exec sh'
}

# ephemeral debug sidecar sharing the target's process namespace
kdebug() {
  local pod="${1:?usage: kdebug <pod> [image]}"
  local img="${2:-nicolaka/netshoot:latest}"
  k debug -it "$pod" --image="$img" --target="$(
    k get pod "$pod" -o jsonpath='{.spec.containers[0].name}'
  )" --share-processes -- bash
}

# node-level debug shell (host PID/net/mounts at /host)
kdebugnode() { k debug node/"${1:?node}" -it --profile=sysadmin --image=nicolaka/netshoot:latest; }

# every image actually running, deduped
kimg() {
  k get pods "${@:--A}" \
    -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' \
    | sort -u
}

# decode a secret fully
ksec() {
  k get secret "${1:?secret}" -o json \
    | jq -r '.data // {} | to_entries[] | "\(.key)=\(.value|@base64d)"'
}

# fzf pod picker -> logs
kfl() {
  local p; p=$(k get pods -o name | fzf --height 40%) || return
  k logs -f --all-containers "$p"
}
```

#### KUBECONFIG hygiene

**Never build a merged mega-config.** One file per cluster under `~/.kube/clusters/`, selected per directory by direnv. A merged config means one absent-minded `kubectl delete` lands wherever the last `use-context` left you.

```bash
sudo dnf install -y direnv
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc
```

`~/work/myapp-staging/.envrc`:
```bash
export KUBECONFIG="$HOME/.kube/clusters/myapp-staging.yaml"
export KUBE_NAMESPACE=myapp
```

`~/work/myapp-prod/.envrc`:
```bash
export KUBECONFIG="$HOME/.kube/clusters/myapp-prod.yaml"
chmod 0400 "$KUBECONFIG"        # read-only file; edits must be deliberate
```

Then `direnv allow`. The rules that follow:

- `chmod 0600` every kubeconfig; `0400` for prod.
- Prod contexts get a name that cannot be misread: `PROD-myapp-gke`, not `gke-1`.
- Put the context in your prompt with **kube-ps1** — an invisible context is the whole failure mode.
- Never `export KUBECONFIG=a:b:c` for daily work. Merge only transiently, when you genuinely need to copy a resource across clusters.

---

### Chapter B — Daily driving kubectl

Organised by what you're trying to find out, not by verb.

#### "What is out there / what does this field mean"

```bash
k get pods -A -o wide                        # every pod, with node + IP
k get all -n myapp                           # NB: "all" is a lie — no secrets, PVCs, ingress, CRs
k api-resources --verbs=list --namespaced -o name   # the real list of namespaced kinds
k api-resources --api-group=apps
k api-versions                               # every group/version served
k explain deploy.spec.strategy
k explain deploy.spec.template.spec.containers --recursive   # whole subtree, no descriptions
k explain pod --recursive | less             # the offline field reference
k get deploy myapp-api -o yaml | k neat      # re-appliable YAML, no managedFields/status
```

`kubectl get -o yaml` hides `managedFields` by default since 1.21; add `--show-managed-fields` when debugging apply conflicts.

#### Output shaping — the four one-liners worth memorising

```bash
# 1. Every image running in the cluster, deduped
k get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -u

# 2. All pods grouped by node
k get pods -A -o custom-columns=NODE:.spec.nodeName,NS:.metadata.namespace,POD:.metadata.name --sort-by=.spec.nodeName

# 3. Every container's resource requests
k get pods -A -o custom-columns='NS:.metadata.namespace,POD:.metadata.name,C:.spec.containers[*].name,CPU:.spec.containers[*].resources.requests.cpu,MEM:.spec.containers[*].resources.requests.memory'

# 4. Everything not Running (the triage query)
k get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded -o wide

# bonus: containers with no memory limit
k get pods -A -o go-template='{{range .items}}{{$ns:=.metadata.namespace}}{{$p:=.metadata.name}}{{range .spec.containers}}{{if not .resources.limits.memory}}{{$ns}}/{{$p}}/{{.name}}{{"\n"}}{{end}}{{end}}{{end}}'
```

`--sort-by` takes a JSONPath with **no** `{}` braces. `-o custom-columns` splits on commas, so quote the whole spec.

#### Logs

```bash
k logs -f deploy/myapp-api                       # follows ONE pod of the deployment
k logs pod/x -c sidecar --previous               # the crashed instance's logs
k logs -l app=myapp-api --all-containers --tail=100 --max-log-requests=20
k logs -f --since=15m --timestamps deploy/myapp-api
k logs -f -l app=myapp --prefix                  # --prefix adds pod/container labels (1.27+)

stern -n myapp 'myapp-(api|worker)' --since 10m --container-state running
stern -l app.kubernetes.io/part-of=myapp -o raw | jq .
```

Multi-pod follow with `-l` silently caps at `--max-log-requests` (default 5 when following). stern has no such trap — use stern above a handful of pods.

#### Getting inside

```bash
k exec -it deploy/myapp-api -c api -- bash
k port-forward svc/myapp-api 8080:80 --address 127.0.0.1
k port-forward pod/redpanda-0 9092:9092
k cp myapp/pod-x:/var/log/app.log ./app.log -c api    # needs `tar` in the container
k cp ./fix.json myapp/pod-x:/tmp/fix.json

# ephemeral container into a distroless pod (GA 1.25+)
k debug -it pod-x --image=nicolaka/netshoot --target=api --share-processes

# node shell: host namespaces, host fs at /host  (profiles beta 1.28+)
k debug node/gke-myapp-pool-abc -it --profile=sysadmin --image=busybox

# copy the pod with a debug shell, swapping the entrypoint — original left untouched
k debug pod-x -it --copy-to=pod-x-dbg --container=api --image=busybox -- sh
k debug pod-x -it --copy-to=pod-x-dbg --set-image=api=busybox -- sh
```

Other `--profile` values: `legacy`, `general`, `baseline`, `netadmin`, `restricted`, `sysadmin`.

#### Changing things

| Command | Semantics | Use when |
|---|---|---|
| `create -f` | Fails if it exists | One-shot, never re-run |
| `apply -f` | Three-way merge against the last-applied annotation | Client-side declarative (legacy path) |
| `apply --server-side` | Field ownership tracked by the API server | **Default choice now** (GA 1.22) |
| `replace -f` | Full overwrite, needs `resourceVersion` | Rare; `--force` = delete + recreate |
| `patch --type=strategic` | Merges lists by patchMergeKey (k8s-aware) | Tweak a container in place |
| `patch --type=merge` | RFC 7386, lists replaced wholesale | CRDs (no strategic support) |
| `patch --type=json` | RFC 6902 op/path/value | Surgical list-index removal |
| `edit` | `$EDITOR` + apply | Exploration only, never prod |

```bash
k apply --server-side --field-manager=myapp-ci -f k8s/
k apply --server-side --force-conflicts -f k8s/        # take ownership from another manager
k get deploy myapp-api --show-managed-fields -o yaml | yq '.metadata.managedFields'

k patch deploy myapp-api -p '{"spec":{"replicas":3}}'                       # strategic
k patch deploy myapp-api --type=json -p '[{"op":"remove","path":"/spec/template/spec/containers/0/livenessProbe"}]'
k patch sa default -p '{"imagePullSecrets":[{"name":"gitlab-reg"}]}'

k diff -f k8s/                     # server-side dry-run diff; exit 1 = differences
k create deploy x --image=y --dry-run=client -o yaml > base.yaml   # scaffolding
k apply -f k8s/ --dry-run=server                                   # runs admission + validation
```

`--dry-run=server` catches webhook rejections and quota. `--dry-run=client` only catches typos.

#### Rollouts, scaling, waiting

```bash
k rollout status deploy/myapp-api --timeout=5m       # exit non-zero on failure -> CI gate
k rollout history deploy/myapp-api
k rollout history deploy/myapp-api --revision=4
k rollout undo deploy/myapp-api --to-revision=4
k rollout restart deploy/myapp-api                   # bumps a pod-template annotation; re-pulls
k rollout pause deploy/myapp-api && k rollout resume deploy/myapp-api

k scale deploy/myapp-api --replicas=5
k scale deploy/myapp-api --current-replicas=3 --replicas=5    # optimistic guard

k wait --for=condition=Available deploy/myapp-api --timeout=300s
k wait --for=condition=Ready pod -l app=myapp-api --timeout=120s
k wait --for=delete pod/myapp-api-abc --timeout=90s
k wait --for=jsonpath='{.status.phase}'=Running pod/x        # 1.23+
k wait --for=create pod/x --timeout=60s                      # 1.31+
```

`rollout status` + `wait --for=condition` are the two commands a deploy job should end with. **A deploy job that doesn't wait hasn't deployed.**

#### Metadata and node lifecycle

```bash
k label pod x tier=backend --overwrite
k label nodes -l cloud.google.com/gke-nodepool=gpu accelerator=nvidia
k annotate deploy/myapp-api kubernetes.io/change-cause="bump to 1.4.2" --overwrite
k label pod x tier-                                   # trailing dash removes

k taint nodes node-1 dedicated=gpu:NoSchedule
k taint nodes node-1 dedicated-                       # remove
k cordon node-1                                       # unschedulable, nothing evicted
k drain node-1 --ignore-daemonsets --delete-emptydir-data --grace-period=60
k uncordon node-1
```

`drain` respects PodDisruptionBudgets and will hang forever on a bad PDB — that hang is the PDB working. `--disable-eviction` bypasses it and is a last resort.

#### Events and diagnosis

```bash
k events --for pod/myapp-api-abc --watch          # 1.27 alpha, beta 1.28+ — use this
k events -n myapp --types=Warning
k get events --sort-by=.lastTimestamp -A          # the old way; lossy sort, works everywhere
k describe pod myapp-api-abc                      # events are at the bottom; read them first
k top nodes
k top pods -A --containers --sort-by=memory       # needs metrics-server
k get pods -w                                     # initial list, then stream
k get pods --watch-only                           # stream only, no initial dump
```

#### Permissions

```bash
k auth can-i create deployments -n myapp
k auth can-i --list -n myapp
k auth can-i '*' '*' --all-namespaces                        # am I cluster-admin
k auth can-i get secrets --as=system:serviceaccount:myapp:runner -n myapp
k auth can-i --list --as=system:serviceaccount:myapp:runner -n myapp
k auth whoami                                                # 1.27+
k access-matrix -n myapp --verb=delete                       # krew plugin
```

Impersonation (`--as`, `--as-group`) is the right way to test an RBAC change before you ship it — cheaper and more honest than deploying a test pod.

#### Context safety

```bash
k config get-contexts
k config current-context
k config use-context PROD-myapp-gke
k config set-context --current --namespace=myapp      # stop typing -n
k config view --minify --flatten                      # just the current context, self-contained
k config delete-context stale-cluster
```

Make prod loud in three layers — **prompt** (kube-ps1, red on `PROD-*`), **isolation** (direnv per-project `KUBECONFIG`, prod file `0400`), and **friction**:

```zsh
k() {
  local ctx; ctx=$(kubectl config current-context 2>/dev/null)
  if [[ $ctx == PROD-* && "$1" =~ ^(delete|drain|apply|replace|patch|scale|cordon)$ ]]; then
    print -u2 "!! ${ctx}: $*"
    read -q "REPLY?type y to proceed: " || { print; return 1; }; print
  fi
  kubecolor "$@"
}
```

> **Version floor.** `kubectl events` 1.27+ (beta 1.28); `debug --profile` beta 1.28; ephemeral containers GA 1.25; server-side apply GA 1.22; `wait --for=jsonpath` 1.23; `wait --for=create` 1.31; `logs --prefix` 1.27. Check the **server** version (`kubectl version`) before relying on any of it.

> **Gotcha.** If `kubectl` is aliased to `kubecolor`, any script that shells out and parses output gets ANSI codes. Set `NO_COLOR=1` or `--force-colors=false` in scripts.

---

### Chapter C — The ecosystem map

The ecosystem is enormous; the set you need is not. One row per job, with the pick to take if you have no reason to take something else.

| Job | Default pick | Also good | Why the default |
|---|---|---|---|
| Local cluster | **kind** | k3d, minikube, Talos in Docker, OrbStack | Real kubeadm-style multi-node, upstream images, disposable in seconds. k3d boots faster and is closer to k3s edge deployments |
| Build images | **docker buildx** | nerdctl, podman, ko (Go), Jib (JVM), Buildpacks, kaniko | BuildKit cache mounts and multi-arch are table stakes. `ko` skips Dockerfiles entirely for Go |
| Registry | **Harbor** | zot (pure OCI, tiny), distribution/registry, ttl.sh, GHCR/ECR/GAR | Harbor gives scanning, replication, proxy cache, robot accounts, quotas. **zot** when you want a small binary that speaks OCI perfectly — the air-gap favourite |
| Package apps | **Helm** | Kustomize, helmfile, Timoni, carvel ytt+kapp, cdk8s | Every vendor ships a Helm chart. Kustomize for environment overlays on top; helmfile to orchestrate many releases |
| Inner dev loop | **Tilt** | Skaffold, DevSpace, Garden, mirrord, Telepresence | Live-update syncs files into running containers without a rebuild. mirrord/Telepresence when the service must run on your laptop against a remote cluster |
| GitOps | **Argo CD** | Flux | See the decision table in chapter 08 — it is genuinely close |
| Image copying / air-gap | **skopeo** | crane, regctl, oras, Zarf, Hauler | skopeo copies between any transports with no daemon. Zarf/Hauler package whole apps for the sneakernet |
| Policy | **Kyverno** | OPA Gatekeeper, ValidatingAdmissionPolicy (built in) | Kyverno policies are YAML you already know, and it does mutation, generation and image verification |
| Scanning and audit | **Trivy** | kube-bench (CIS), kubescape, Grype/Syft, Popeye, Polaris, Falco | Trivy scans images, IaC, SBOMs and live clusters. kube-bench is the CIS benchmark reference |
| Secrets | **External Secrets Operator** | Sealed Secrets, SOPS (Flux native), Vault Agent / CSI | ESO pulls from your real secret store into Secrets. SOPS when you must commit encrypted values to git |
| Observability | **kube-prometheus-stack** | Loki / Tempo / Alloy, OpenTelemetry Collector, VictoriaMetrics | ServiceMonitor/PodMonitor/PrometheusRule are the lingua franca every chart's `metrics.serviceMonitor.enabled` flag targets |
| Debugging | **k9s, stern, kubectl debug** | netshoot, ksniff, Kubeshark, krr, kubent | Chapter 11 |
| Cluster UI | **Headlamp** | Rancher, Lens/OpenLens, Portainer, Dashboard, Devtron | Chapter 13 |
| Manifest hygiene | **kubeconform** | kube-linter, pluto, helm-unittest | Schema validation in CI catches most typos before the API server does |

#### One-shot install

```bash
# macOS / Linux with Homebrew
brew install kubectl helm kind k3d kubectx k9s stern krew kubecolor \
  skopeo crane oras fluxcd/tap/flux argocd tilt-dev/tap/tilt skaffold \
  kustomize helmfile kubeconform trivy kube-bench kubescape yq jq fzf

# Linux without brew — arkade knows most of these CLIs
curl -sLS https://get.arkade.dev | sudo sh
arkade get kubectl helm kind k9s stern kubectx flux argocd tilt skaffold kustomize
```

#### A few more functions worth stealing

```zsh
# shell into the first pod whose name matches: kbash api
kbash(){ kubectl exec -it "$(kubectl get pod -o name | grep -m1 "$1")" -- sh -c 'bash || sh'; }

# the real "get all": every namespaced kind, including custom resources
kgall(){ kubectl api-resources --verbs=list --namespaced -o name \
  | xargs -n1 kubectl get --show-kind --ignore-not-found ${1:+-n "$1"}; }

# port-forward in the background and print the URL: kpf svc/grafana 3000:80
kpf(){ kubectl port-forward "$@" >/dev/null 2>&1 & disown; echo "http://localhost:${2%%:*}"; }

# throwaway pod with every network tool you need
knet(){ kubectl run -it --rm net-$RANDOM --image=nicolaka/netshoot --restart=Never -- bash; }
```

> **Gotcha.** `kubectl get all` is a lie — it omits Secrets, ConfigMaps, PVCs, Ingresses and every custom resource. Use `kgall` above, or the `get-all` krew plugin, whenever "is the namespace actually empty?" matters.


---


<a id="04-images-dockerfile-to-signed-oci"></a>

## 04 · Images: Dockerfile to signed OCI

#### The mental model: an image is content-addressed data, and a tag is a sticky note

An OCI image is not a file. It is a small graph of blobs in a registry:

| Object | What it is | How it's addressed |
|---|---|---|
| **Manifest** | JSON listing the config blob + ordered layer blobs, with media types and sizes | `sha256:` of the manifest bytes — **this is "the image digest"** |
| **Config** | JSON: env, entrypoint, cmd, user, labels, `rootfs.diff_ids`, `history` | digest, referenced by the manifest |
| **Layers** | gzip/zstd tarballs of filesystem changesets | digest each |
| **Index** (manifest list) | JSON listing *manifests*, each with a `platform` | digest — the "multi-arch digest" |

Two consequences do all the work for the rest of this chapter:

1. **A digest is immutable and self-verifying.** `repo/name@sha256:abc…` either resolves to exactly those bytes or fails. A registry cannot lie about it without breaking SHA-256.
2. **A tag is a mutable pointer into that graph.** `:1.2.3` is a row in the registry's tag table. Anyone with push rights can repoint it. **Every reproducibility, airgap and supply-chain problem downstream is a consequence of someone trusting a tag.**

Multi-arch: when you pull `repo/name:tag` on arm64, the registry hands you the *index*; the client picks the `linux/arm64` entry and pulls that manifest. So `repo/name@sha256:index…` and `repo/name@sha256:amd64manifest…` are both valid, both "the digest", and **not equal**. Tooling disagrees about which one it reports. Resolve explicitly when it matters:

```bash
crane digest repo/name:1.2.3                          # the index digest
crane digest --platform linux/amd64 repo/name:1.2.3   # the per-platform manifest digest
skopeo inspect --raw docker://repo/name:1.2.3 \
  | jq -r '.manifests[] | select(.platform.architecture=="amd64" and .platform.os=="linux") | .digest'
docker buildx imagetools inspect repo/name:1.2.3      # human-readable index dump
```

> **Field note.** In an airgapped appliance where images are exported and re-imported into a containerd store, the store **recomputes** digests on re-compression, so a registry digest will not resolve offline. The fix is not to give up pinning — move the pin into the build script: resolve the platform sub-manifest, pull *by digest*, re-tag, then **assert** the tag carries the pinned digest before you `save`. Check membership across *all* `RepoDigests`; the ordering is not stable and `RepoDigests[0]` will eventually be the index digest, making your check pass or fail at random.

#### Writing a Dockerfile that doesn't waste your life

```dockerfile
# syntax=docker/dockerfile:1.22@sha256:4a43a54dd1fedceb30ba47e76cfcf2b47304f4161c0caeac2db1c61804ea3c91
# Pin the frontend too. "dockerfile:1" is a mutable tag and it does change semantics.

FROM python:3.13-slim@sha256:<pin> AS build
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
COPY --from=ghcr.io/astral-sh/uv:0.9@sha256:<pin> /uv /usr/local/bin/uv

WORKDIR /app
# Dependency manifests FIRST, alone. Source changes every commit; deps do not.
# This one ordering decision is worth more than every other cache trick combined.
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv,id=uv,sharing=locked \
    uv sync --frozen --no-install-project --no-dev

COPY --link --chown=0:0 src/ ./src/
RUN --mount=type=cache,target=/root/.cache/uv,id=uv,sharing=locked \
    uv sync --frozen --no-dev

FROM python:3.13-slim@sha256:<pin> AS prod
RUN useradd --system --uid 10001 --no-create-home app
COPY --link --from=build --chown=0:0 /app /app
ENV PATH=/app/.venv/bin:$PATH
USER 10001:10001
EXPOSE 8000
ENTRYPOINT ["python", "-m", "myservice"]
```

Rules that earn their place:

- **Cache mounts need a stable `id` and `sharing=locked`.** Without the id, parallel stages get separate caches; without the lock, two stages corrupt one package-manager DB.
- **Never `ARG` a secret.** `ARG` values land in the image config and `docker history` prints them. Use `RUN --mount=type=secret,id=netrc,target=/root/.netrc` with `--secret id=netrc,src=...`. The secret is a tmpfs mount for that `RUN` only and is never a layer.
- **Mount tmpfs over scratch dirs** (`--mount=type=tmpfs,target=/tmp`) so build litter cannot land in a layer.
- **`COPY --link`** writes an independent layer that does not invalidate on parent-stage changes, and it's faster. Pair with explicit `--chown`/`--chmod` so permissions don't depend on the builder's umask.
- **`.dockerignore` is a build-speed *and* correctness control.** `.git`, `node_modules`, `.venv`, `target/`, `*.tfstate`, `.env`. Without it the whole tree is context and any local file can silently change your image.
- **`USER` a numeric UID**, not a name. Kubernetes `runAsNonRoot` validates the *numeric* UID from the config.
- **`HEALTHCHECK` does nothing under Kubernetes.** The kubelet never reads it. Probes are the only health mechanism in-cluster.
- **`ENTRYPOINT` = the binary, `CMD` = default arguments.** Exec form (JSON array) always. Shell form runs your process under `/bin/sh -c`, so **sh becomes PID 1 and does not forward SIGTERM** — your pod ignores graceful shutdown and gets SIGKILLed at the end of the grace period.
- **PID 1 and reaping.** If your process spawns children, PID 1 must reap zombies. Use `tini`, or in-cluster `shareProcessNamespace: true` gives you the pause container as a reaper. `docker run --init` has no Kubernetes equivalent.

#### Base images

| Base | libc | Size (order) | Debuggable | CVE surface | Notes |
|---|---|---|---|---|---|
| `scratch` | none | ~binary | no | ~zero | No CA certs, no tzdata, no `/etc/passwd`, no resolver config |
| distroless | glibc | 2–50 MB | no shell (`:debug` has busybox) | very low | Ships CA certs, tzdata, `nonroot` user |
| Chainguard/Wolfi | glibc | small | `-dev` variants have a shell | lowest, fastest patch cadence | Most tags paid after a short window; check licensing |
| `alpine` | **musl** | ~8 MB | full busybox shell, `apk` | low | musl breaks manylinux wheels, changes DNS/threads/`getaddrinfo`, slower malloc |
| `ubi9/ubi-minimal` | glibc | ~40 MB | `microdnf`, shell | moderate, Red Hat CVE feed | The right answer when a customer's scanner speaks RHEL errata |
| `debian:*-slim` | glibc | ~30 MB | apt, shell | moderate | Boring, predictable, huge package compatibility |

**Python service → `python:3.13-slim` (or `ubi9/ubi-minimal` + your own interpreter) pinned by digest, non-root, venv copied from a build stage.** Not alpine: musl forces source builds of every wheel, and you pay in build minutes and subtle runtime differences. Not distroless-python either, unless you're content that *Google* chooses your Python patch version.

**Go binary → `gcr.io/distroless/static-debian12:nonroot`, built `CGO_ENABLED=0`.** You get CA certs, tzdata and a `nonroot` (65532) passwd entry for ~2 MB. `scratch` only if you are prepared to `COPY` those three things yourself and never make an outbound TLS call you forgot about.

#### BuildKit and buildx

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --cache-from type=registry,ref=$REG/buildcache:svc-latest \
  --cache-to   type=registry,ref=$REG/buildcache:svc-$TAG,mode=max,image-manifest=true,oci-mediatypes=true,compression=zstd,ignore-error=true \
  --provenance mode=max \
  --sbom true \
  --secret id=npmrc,src=$HOME/.npmrc \
  -t $REG/svc:$TAG --push .
```

- `mode=max` exports intermediate-stage layers too; `mode=min` only the final image. For a multi-stage build, `min` caches almost nothing useful.
- `ignore-error=true` on `cache-to` so a registry hiccup does not fail a green build.
- `--provenance` / `--sbom` attach in-toto attestations as an **attestation manifest inside the index**. Consequence: the pushed artifact is an index even for a single platform, and old tooling expecting a bare manifest may choke. *Version-sensitive: buildx ≥ 0.11.*
- Multi-platform requires a `docker-container` or `remote` driver (`docker buildx create --driver docker-container --use`); the default `docker` driver cannot do it.

#### docker-bake.hcl

A bake file gives you what a directory of build scripts never does: **one dependency graph, evaluated once**. Targets inherit shared settings, consume each other as build contexts, and build in parallel with correct ordering.

```hcl
variable "REGISTRY" { default = "registry.example.com/team/" }
variable "TAG"      { default = "dev" }
variable "CI_CACHE" { default = "" }   # empty locally => no registry cache

function "img" { params = [s] ; result = "${REGISTRY}${s}:${TAG}" }

function "cache_to" {
  params = [s]
  result = CI_CACHE != "" ? [
    "type=registry,ref=${CI_CACHE}/buildcache:${s}-${TAG},mode=max,ignore-error=true"
  ] : []
}

# Shared settings only. Never built directly.
target "common" {
  platforms = ["linux/amd64"]
  target    = "prod"
  labels    = { "org.opencontainers.image.revision" = "${TAG}" }
}

# A real base image other targets consume as a build context, so the shared
# dependency layer is built once rather than duplicated in every service's cache.
target "runtime-base" {
  inherits = ["common"]
  context  = "images/runtime-base"
  tags     = [img("runtime-base")]
  cache-to = cache_to("runtime-base")
}

target "api" {
  inherits = ["common"]
  context  = "services/api"
  contexts = { runtime-base = "target:runtime-base" }  # FROM runtime-base
  tags     = [img("api")]
  cache-to = cache_to("api")
}

target "worker" {
  inherits = ["common"]
  context  = "services/worker"
  contexts = { runtime-base = "target:runtime-base" }
  tags     = [img("worker")]
  cache-to = cache_to("worker")
}

# Matrix: one definition, N targets (api-amd64, api-arm64, …).
target "api-arch" {
  inherits  = ["api"]
  name      = "api-${arch}"
  matrix    = { arch = ["amd64", "arm64"] }
  platforms = ["linux/${arch}"]
}

group "default" { targets = ["api", "worker"] }
```

```bash
docker buildx bake                          # group "default"
docker buildx bake api --push
docker buildx bake --print                  # resolved JSON — read this before debugging
docker buildx bake -f docker-bake.hcl -f bake.ci.hcl api   # overlay wins
TAG=$(git rev-parse --short HEAD) docker buildx bake --push
```

Overlay files beat `--set`: `--set` is for genuinely per-run values (a tag, a registry, a credential). Environment-shaped configuration belongs in a file you can diff.

**A target referenced only as another target's context is built in-graph but never runs its own exporter** — it is never pushed. If you need the base image in the registry, list it in a group.

#### Podman, buildah, Fedora

- `podman build` reads the same Dockerfile and supports `--mount=type=cache|secret|bind|tmpfs`, `--platform` and heredocs. Podman ≥ 5 is fine for everything above.
- **Rootless** uses user namespaces: `USER 10001` inside maps to a subuid outside. Files copied in are owned by the mapped UID — always set `--chown` explicitly.
- **Divergences from buildx that bite:** no bake; no `--cache-to type=registry` with the same semantics (buildah's cache format is *not* buildx's); multi-arch is manual (`podman manifest create` → `podman build --platform --manifest` → `podman manifest push`); no `--provenance`/`--sbom` exporters — sign with `cosign` afterwards instead.
- `buildah` is the scriptable layer underneath: `buildah from` / `run` / `commit` when you need a build a Dockerfile cannot express. `podman build --timestamp <epoch>` sets layer timestamps for reproducibility.

#### Reproducibility, honestly

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:<pin>
RUN microdnf install -y --nodocs curl-8.9.1-2.el9 && microdnf clean all
```

```bash
export SOURCE_DATE_EPOCH=$(git log -1 --pretty=%ct)
docker buildx build --output type=image,name=$REG/svc:$TAG,push=true,rewrite-timestamp=true .
```

- **`FROM … @sha256:` always.** A digest-pinned base is the single highest-value line in the file. Renovate can bump it; a human should not.
- **Pin package versions**, or keep a checked-in **lock file** of package names annotated by tier (must/should/may) with removal TODOs naming the condition, and bind-mount it into the `RUN`. An install list buried in a `RUN` is undiffable.
- `SOURCE_DATE_EPOCH` is honoured by BuildKit ≥ 0.11 for the image `created` field and `COPY`-produced layers. **Layers produced by `RUN` keep build-time mtimes unless you also use the `rewrite-timestamp=true` image-exporter attribute (BuildKit ≥ 0.13).**
- **How far it goes:** bit-identical rebuilds are realistic for `FROM scratch` + a Go binary compiled with `-trimpath` and `-ldflags=-buildid=`. They are *not* realistic once a package manager is involved — mirrors GC old versions, `dnf` writes an RPM DB with embedded state, CA bundles regenerate. Aim for **the honest target: identical inputs, recorded.** Digest-pinned base, locked packages, locked language deps, recorded provenance. That gets you auditability and airgap determinism, which is what you actually needed.

#### Digest pinning in Kubernetes

```yaml
# values-prod.yaml
image:
  repository: registry.example.com/team/api
  digest: "sha256:9f2c…"          # no tag
  pullPolicy: IfNotPresent
```

```yaml
image: "{{ .Values.image.repository }}@{{ .Values.image.digest }}"
```

**The anti-pattern is `:latest` (or any moving tag) plus `imagePullPolicy: Always`.** Every pod restart, every node scale-up, every eviction can land a *different* image than its neighbours. Your Deployment is no longer a description of what is running, and rollback becomes meaningless because the thing you roll back to is also a pointer. With a digest, `IfNotPresent` is correct and free: the cache key is the content.

Keep a human-readable tag as a label or annotation for triage; make the *pull* reference the digest.

#### SBOM and scanning

```bash
syft scan registry.example.com/team/api@sha256:9f2c… -o spdx-json=sbom.json
grype sbom:sbom.json --fail-on high            # scan the SBOM, not the image, in the gate
trivy image --severity HIGH,CRITICAL --exit-code 1 --ignore-unfixed $REF@$DIGEST
```

| Stage | What runs | Gate? |
|---|---|---|
| Build job, post-push | `syft` → SBOM artifact, `cosign attest` | no |
| Build job | `grype`/`trivy` on the digest just pushed | yes — `--exit-code 1`, `--ignore-unfixed` |
| Nightly | re-scan **already-released digests** | yes, but as a ticket, not a pipeline failure |
| Cluster | `trivy k8s` / an operator enumerating running images | reporting |

**Scanning an image answers "what vulnerabilities does this artifact contain".** Scanning a cluster answers "what is actually running, including the three-year-old sidecar nobody owns, and is it reachable". They find different things and you need both.

#### Signing and verification

```bash
DIGEST=$(crane digest $REG/api:$TAG)

# Keyless (OIDC, Fulcio + Rekor). Default in cosign v2.
cosign sign --yes "$REG/api@$DIGEST"

# Or long-lived key (airgap, or no OIDC issuer you trust)
cosign sign --key k8s://ci/cosign-key --yes "$REG/api@$DIGEST"

cosign verify \
  --certificate-identity-regexp '^https://gitlab\.example\.com/team/repo//\.gitlab-ci\.yml@refs/heads/main$' \
  --certificate-oidc-issuer 'https://gitlab.example.com' \
  "$REG/api@$DIGEST"

cosign attest --yes --type spdxjson --predicate sbom.json "$REG/api@$DIGEST"
cosign verify-attestation --type spdxjson --key cosign.pub "$REG/api@$DIGEST"
```

**Always sign the digest, never the tag** — signing `:1.2.3` signs whatever it pointed at that second. `cosign verify` with *no* identity flags on a keyless signature is not verification; it proves someone, somewhere, signed it. **The identity + issuer pair is the assertion.**

Keyless wants a reachable Fulcio/Rekor, so an airgapped build signs with a key and ships the public key with the bundle. Enforcement belongs at admission — Kyverno `verifyImages` or sigstore policy-controller, which also **mutates the tag to the verified digest** on admit.

#### Inspecting and debugging

```bash
crane ls repo/name                       # tags
crane manifest repo/name@sha256:… | jq   # layers + media types
crane config repo/name@sha256:… | jq '.config, .history'
skopeo inspect --raw docker://repo/name:tag | jq   # raw index, no client-side platform pick
docker history --no-trunc repo/name:tag  # which instruction cost what (and leaked what)
dive repo/name:tag                       # per-layer file diff, wasted-bytes score
```

Getting a shell "into" a distroless container — you cannot; there is no shell. Attach one alongside it:

```bash
kubectl debug -it pod/api-7f9 --image=busybox:1.36 --target=api -- sh
# --target puts the ephemeral container in the target's process namespace,
# so /proc/1/root/ is the app's filesystem and you can read its files and env.
ls /proc/1/root/app
```

If the pod won't start at all, copy it instead: `kubectl debug pod/api-7f9 --copy-to=api-dbg --set-image=api=busybox:1.36 -- sleep infinity`, then exec in and run the real entrypoint by hand.

#### Size and cache hygiene

What actually makes images huge, in the order you will find it:

1. **Build toolchain in the final stage** — compilers, headers, `-dev` packages, npm/uv caches. Multi-stage and copy only the artefact.
2. **A `RUN` that installs then a *later* `RUN` that deletes.** The bytes are in the earlier layer forever. Delete in the same `RUN`, or use a cache mount so they were never a layer.
3. **Copying the whole context** because `.dockerignore` is missing — `.git` alone is often hundreds of MB.
4. **Package-manager metadata**: `apt-get clean && rm -rf /var/lib/apt/lists/*`, `microdnf clean all`, `--no-install-recommends`, `--nodocs`.
5. **Duplicated base layers across services** because each Dockerfile built its own — share one real base target in bake so the layer is pulled once per node.

Two cheap wins beyond that: `zstd` compression on cache exports, and checking `dive`'s efficiency score in CI as a *report* — not a gate, it will flap.


---


<a id="05-a-dev-cluster-and-the-inner-loop"></a>

## 05 · A dev cluster, and the inner loop

### Chapter A — A dev cluster you can throw away

#### The options, and one recommendation

| | kind | k3d (k3s) | minikube | Docker Desktop k8s | Remote dev cluster |
|---|---|---|---|---|---|
| Multi-node | yes, cheap | yes, cheapest | yes (`--nodes`), heavy | **no** | yes |
| Time to first cluster | ~45–90s | ~20s | ~90s | already there | minutes + IAM |
| Matches prod control plane | upstream kubeadm, closest | k3s: no separate etcd/CCM, trimmed | kubeadm | opaque, vendor-patched | exact |
| Image into cluster | `kind load` / local registry | `k3d image import` | `minikube image load` | shares host daemon | must push |
| Host 80/443 | `extraPortMappings` | `--port` / built-in LB | `minikube tunnel` | native | LoadBalancer |
| Throwaway/reset | total | total | total | resets Docker Desktop too | never truly yours |
| Runs in CI unchanged | yes | yes | awkward | no | no |
| Cost of being wrong | zero | zero | zero | zero | real money, shared blast radius |

**Recommendation: kind.** One reason outweighs the rest — **kind is upstream kubeadm, so the thing you debug locally is the thing that runs in prod**, and the same config file runs in CI unchanged. k3d is faster to start and is the right pick for a smoke test, but k3s replaces enough of the control plane (traefik, servicelb, no separate CCM) that a class of bug reproduces only in one place, and then you are debugging the wrong system. Docker Desktop's k8s is disqualified: single node, no node labels you control, and tearing it down takes your whole Docker install with it.

Use a **remote** dev cluster only when the thing under test cannot exist locally — GPU nodes, a cloud load balancer, workload identity, a managed database. Then one namespace per developer, treated like prod, because it is shared.

#### A complete `kind-config.yaml`

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: dev

# Version-sensitive: kind >= 0.27 sets config_path itself, so hosts.toml drop-ins
# under /etc/containerd/certs.d are honoured without this block. Keep it: it is a
# no-op on new kind and required on old kind, where its absence shows up only as
# ImagePullBackOff with no explanation.
containerdConfigPatches:
  - |
    [plugins."io.containerd.grpc.v1.cri".registry]
      config_path = "/etc/containerd/certs.d"

nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
      - |
        kind: ClusterConfiguration
        apiServer:
          extraArgs:
            # Only needed if a Service pins port 80/443 directly (a Gateway data
            # plane does). Default NodePort floor is 30000 and such a Service is
            # rejected outright. Not needed for ingress-nginx + hostPort.
            service-node-port-range: "80-32767"
    extraPortMappings:
      - { containerPort: 80,  hostPort: 80,  protocol: TCP }
      - { containerPort: 443, hostPort: 443, protocol: TCP }
    extraMounts:
      # Absolute path, as the DOCKER DAEMON sees it. kind expands no variables
      # here, so this line is generated, not checked in.
      - hostPath: /home/you/src/myapp
        containerPath: /opt/src
        readOnly: false
  - role: worker
    labels:
      workload: general
    extraMounts:
      - { hostPath: /home/you/src/myapp, containerPath: /opt/src }
  - role: worker
    labels:
      workload: storage
```

**Two hard-won points.**

1. `extraMounts` is a **bind mount into the node container, and a bind mount can only be added at creation.** A cluster built before you added the mount cannot be repaired in place; dev-mode pods die minutes later with `hostPath type check failed`, which reports nowhere near its cause. Make the check fatal at cluster-up time, not a warning.
2. `extraMounts` is **per node**. The single-node shortcut of appending one stanza stops working the moment you add workers.

Because the hostPath is machine-specific, generate it:

```bash
# render-kind-config.sh
set -eu
SRC="${DEV_MOUNT_SOURCE:-$(git rev-parse --show-toplevel)}"   # as the daemon sees it
sed "s#__SRC__#${SRC}#g" kind-config.tmpl.yaml | tee /tmp/kind-dev.yaml
kind create cluster --config /tmp/kind-dev.yaml --wait 5m
```

Print the rendered file. **A wrapper that hides what it ran cannot be debugged or documented.**

#### Local registry, end to end

Tilt does not need this on kind — it calls `kind load` for you. You need it the moment anything **other than Tilt** pulls: an operator, a Job, Argo CD, a second cluster.

```bash
#!/usr/bin/env bash
# kind-registry.sh — registry at localhost:5001, pullable from inside the cluster.
set -euo pipefail
REG_NAME='kind-registry'; REG_PORT='5001'; CLUSTER='dev'

# 1. the registry container (idempotent)
if [ "$(docker inspect -f '{{.State.Running}}' "${REG_NAME}" 2>/dev/null || true)" != 'true' ]; then
  docker run -d --restart=always -p "127.0.0.1:${REG_PORT}:5000" \
    --network bridge --name "${REG_NAME}" registry:2
fi

# 2. tell every node where "localhost:5001" lives, via containerd hosts.d.
REG_DIR="/etc/containerd/certs.d/localhost:${REG_PORT}"
for node in $(kind get nodes --name "${CLUSTER}"); do
  docker exec "${node}" mkdir -p "${REG_DIR}"
  cat <<REGEOF | docker exec -i "${node}" cp /dev/stdin "${REG_DIR}/hosts.toml"
[host."http://${REG_NAME}:5000"]
REGEOF
done

# 3. put the registry on the kind network so those nodes can resolve it
if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${REG_NAME}")" = 'null' ]; then
  docker network connect kind "${REG_NAME}"
fi

# 4. advertise it (KEP-1755) so tools discover it instead of guessing
kubectl apply -f - <<KUBEEOF
apiVersion: v1
kind: ConfigMap
metadata: { name: local-registry-hosting, namespace: kube-public }
data:
  localRegistryHosting.v1: |
    host: "localhost:${REG_PORT}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
KUBEEOF
```

Then `docker push localhost:5001/myapp:dev` and reference the same string in the chart — the node rewrites it to `kind-registry:5000` over plain HTTP. **Exercise all four paths before trusting it:** push+pull from host; pull from a pod on the control plane; pull from a pod on each worker; pull after `docker restart kind-registry`. Skip the last one and you find out during a demo.

#### The basics, installed

```bash
# ingress-nginx — the kind provider manifest is not optional: it sets the
# nodeSelector ingress-ready=true and hostPort 80/443. Pin the tag.
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.13.1/deploy/static/provider/kind/deploy.yaml
kubectl -n ingress-nginx wait --for=condition=Ready pod \
  -l app.kubernetes.io/component=controller --timeout=180s

# cert-manager — version-sensitive flag: `crds.enabled` since v1.15,
# it was `installCRDs` before. Check the chart's values before pasting.
helm repo add jetstack https://charts.jetstack.io && helm repo update
helm upgrade --install cert-manager jetstack/cert-manager \
  -n cert-manager --create-namespace --version v1.18.2 --set crds.enabled=true

kubectl apply -f - <<ISSUEREOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: { name: selfsigned }
spec: { selfSigned: {} }
ISSUEREOF

# metrics-server — kubelet serving certs on kind are self-signed and the SANs do
# not match, so without this flag every scrape fails x509 and HPA/`kubectl top`
# silently return nothing.
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm upgrade --install metrics-server metrics-server/metrics-server \
  -n kube-system --set 'args={--kubelet-insecure-tls}'
```

**Storage.** kind ships rancher `local-path-provisioner` as the default StorageClass `standard`, `WaitForFirstConsumer`, **no volume expansion, no snapshots, and the data lives inside the node container** — `kind delete cluster` destroys it. Correct for a throwaway cluster, wrong for anything that must survive. To exercise expansion or `VolumeSnapshot`, install `csi-driver-host-path` plus the external-snapshotter CRDs; do not assume a chart that works on `standard` works on a real CSI.

> **One-way door, and it bites in dev too:** a PVC's storage request can only ever grow, and in a StatefulSet `volumeClaimTemplate` it is immutable after creation. Shrinking a size profile stalls `helm upgrade` rather than failing loudly. Recreate the cluster; do not upgrade into a smaller size.

#### Resource sizing reality

A kind cluster running a real umbrella chart — Postgres, an object store, a broker, a couple of operators, an ingress — is **not** a 4 GB laptop toy. Working numbers: **8 vCPU / 16 GB RAM / 100 GB disk** for the Docker VM. Below that, nothing errors: pods sit `Pending`, chart waits never converge, and it reads as a hang. `kubectl describe pod` → Events → `Insufficient cpu` is the tell.

- **macOS Docker Desktop:** Settings → Resources. On Apple Silicon enable VirtioFS and Rosetta if any image is amd64-only.
- **macOS Colima:** fixed at VM creation — `colima stop && colima start --cpu 8 --memory 16 --disk 100`.
- **Windows WSL2:** the Resources sliders are **greyed out**; the setting lives in `%UserProfile%\.wslconfig` and nowhere else, and needs `wsl --shutdown` to take. Restarting Docker Desktop is not enough. This is the step people get wrong most often.
- **Linux:** no VM to size. Verify anyway: `docker info --format 'mem={{.MemTotal}} cpus={{.NCPU}}'`.

**inotify — do this before you blame Kubernetes.** Tilt's watcher, vite, `uvicorn --reload` and the node's own controllers each burn instances; the default 128 goes quickly. `fs.inotify.*` is **host-global and non-namespaced**, so even root inside a container gets permission denied.

```bash
sudo sysctl -w fs.inotify.max_user_instances=1024
sudo sysctl -w fs.inotify.max_user_watches=1048576
printf 'fs.inotify.max_user_instances = 1024\nfs.inotify.max_user_watches = 1048576\n' \
  | sudo tee /etc/sysctl.d/99-kind-inotify.conf
```

Symptoms when you skip it: kube-proxy `too many open files`, then `dial tcp 10.96.0.1:443: i/o timeout` across many pods — a failure reporting a long way from its cause.

**Fedora / rootless / cgroup v2:**

```bash
export KIND_EXPERIMENTAL_PROVIDER=podman          # rootless podman as the kind provider
sudo mkdir -p /etc/systemd/system/user@.service.d
printf '[Service]\nDelegate=yes\n' | sudo tee /etc/systemd/system/user@.service.d/delegate.conf
sudo systemctl daemon-reload                       # then log out and back in
sudo setsebool -P container_manage_cgroup true     # rootless docker only; SELinux enforcing by default
```

Rootless also means **`hostPort` below 1024 will not bind** unless `net.ipv4.ip_unprivileged_port_start` is lowered — which is why the 80/443 `extraPortMappings` above work rootful and fail rootless. If you are rootless, map 8080/8443 and stop fighting it.

#### Teardown, reset, and uninstalling the dev loop

| Situation | Do this |
|---|---|
| Chart values changed, app misbehaving | `helm uninstall` + reinstall |
| CRD schema changed, or a CRD is stuck | delete the CRD (check finalizers), then reinstall |
| PVC needs to shrink, or a `volumeClaimTemplate` changed | **nuke the cluster** — immutable, will stall not fail |
| Node config changed: `extraMounts`, port mappings, labels, kubeadm patches | **nuke** — none of these are editable in place |
| Namespace stuck `Terminating` | nuke, or force-finalize knowing what you are resurrecting |
| "I don't know what state this is in" | nuke; it costs ~3 minutes and buys certainty |

Never force-finalize a namespace casually: recreating a namespace of the same name resurrects nothing, but force-finalizing leaves the *objects* — Deployments, StatefulSets, PVCs, Secrets — orphaned and alive, including raft PVCs and root-token Secrets, which then outlive the "clean" reinstall.

```bash
# ---- full uninstall of the dev loop, in order ----
tilt down --delete-namespaces        # stops Tilt's own resources first
pkill -f 'tilt up' || true
helm list -A                         # anything Tilt did not own
helm uninstall <release> -n <ns>

kind delete cluster --name dev       # takes node containers, images and local-path data

# registry + its volume (kind delete does NOT touch these)
docker rm -f kind-registry
docker volume ls -qf dangling=true | xargs -r docker volume rm

# reclaim disk. kind node images are 1-2 GB each and accumulate per kind release.
docker images 'kindest/node' --format '{{.Repository}}:{{.Tag}}'
docker image rm kindest/node:v1.32.0                 # the ones you no longer create
docker buildx du                                     # BuildKit cache is usually the big one
docker buildx prune --filter until=168h
docker system prune -a --volumes                     # last, and know what you are deleting

# leftovers people forget
rm -rf ~/.tilt-dev/ ~/.local/share/tilt-dev/         # Tilt state + downloaded extensions
kubectl config delete-context kind-dev 2>/dev/null || true
```

Order matters: `tilt down` **before** `kind delete cluster`, or Tilt's state file still claims resources in a cluster that no longer exists and the next `tilt up` spends its first minute reconciling ghosts.

---

### Chapter B — The inner dev loop

#### What the inner loop is

**Inner loop:** save a file → see it running in the cluster. Budget: **under 30 seconds, and under 3 seconds for an interpreted-language edit.** Outer loop: commit → CI → registry → GitOps → cluster, measured in minutes and *correctly* so — it is doing signing, scanning and promotion you do not want on every keystroke.

The failure mode is not a slow inner loop. It is a team that, faced with a slow inner loop, moves its debugging into the outer loop — pushing commits to watch CI logs. That converts a 30-second question into a 12-minute one and pollutes history. **Budget the inner loop like a product feature.**

#### A complete, annotated Tiltfile

```python
# Tiltfile — Starlark: Python-ish, no classes, no imports beyond load().

# ── 0. safety ───────────────────────────────────────────────────────────────
allow_k8s_contexts([])                 # empty = only kind-*/minikube/docker-desktop
# allow_k8s_contexts('gke_proj_region_dev')   # deliberate, reviewed, never prod

# ── 1. flags: tilt up -- --with=observability,tracing ───────────────────────
config.define_string_list('with', args=False, usage='optional stacks to enable')
cfg = config.parse()
WITH = cfg.get('with', [])
OBS = 'observability' in WITH

# ── 2. noise control. Tilt watches the Tiltfile's directory tree by default;
#      a generated dir in the build context rebuilds the world on every codegen.
watch_settings(ignore=[
    '.git', '**/node_modules', '**/__pycache__', '**/.venv',
    'dist', '**/*.log', '.tilt-state',
])
update_settings(max_parallel_updates=3, k8s_upsert_timeout_secs=180)

# ── 3. build ────────────────────────────────────────────────────────────────
docker_build(
    'myapp/api',                        # MUST equal image.repository in values
    context='.',
    dockerfile='deploy/api.Dockerfile',
    target='dev',                       # a dev stage that keeps symbols + a reloader
    build_args={'PYTHON_VERSION': '3.13'},
    only=['api/', 'libs/python/', 'pyproject.toml', 'uv.lock'],   # narrow the context
    ignore=['api/**/*_test.py'],        # a test edit must not rebuild an image
    live_update=[
        # fall_back_on FIRST: these files change the image itself, so syncing
        # them would produce a container that disagrees with its own Dockerfile.
        fall_back_on(['deploy/api.Dockerfile', 'uv.lock', 'pyproject.toml']),
        sync('./api', '/app/api'),
        run('uv sync --frozen', trigger=['./uv.lock']),
    ],
)

# ── 4. deploy the real chart ────────────────────────────────────────────────
# helm() is `helm template` under the hood. It does NOT run hooks and does not
# pass --include-crds; a chart whose CRDs live in crds/ will deploy CRs before
# their CRD exists and fail with "no matches for kind".
k8s_yaml(helm(
    './charts/myapp',
    name='myapp',
    namespace='dev',
    values=['./charts/myapp/values-dev.yaml'],
    set=['image.pullPolicy=IfNotPresent'],
))

# ── 5. resources: ports, deps, grouping ─────────────────────────────────────
k8s_resource('api',
    port_forwards=['8080:8080', '5678:5678'],   # app, debugpy
    resource_deps=['migrate', 'postgres'],
    labels=['backend'])
k8s_resource('web', port_forwards=['5173:5173'], labels=['frontend'])
k8s_resource('postgres', labels=['data'])

# ── 6. local work: codegen, migrations, tests ───────────────────────────────
local_resource('codegen', cmd='make codegen', deps=['./openapi.yaml'], labels=['tooling'])

local_resource('migrate',
    cmd='kubectl -n dev wait --for=condition=complete job/myapp-migrate --timeout=120s',
    resource_deps=['postgres'], labels=['data'])

local_resource('test-unit',
    cmd='uv run pytest -q api/tests',
    deps=['./api'],
    trigger_mode=TRIGGER_MODE_MANUAL, auto_init=False,   # expensive: button only
    labels=['tests'])

# ── 7. optional stack behind the flag ───────────────────────────────────────
if OBS:
    load('ext://helm_resource', 'helm_resource', 'helm_repo')
    helm_repo('prometheus-community', 'https://prometheus-community.github.io/helm-charts')
    helm_resource('kube-prom-stack', 'prometheus-community/kube-prometheus-stack',
        namespace='observability',
        flags=['--create-namespace', '-f', './deploy/values-kps-dev.yaml'],
        resource_deps=['prometheus-community'],
        port_forwards=['3000:3000'], labels=['obs'])
```

> `helm_resource`/`helm_repo` come from `ext://helm_resource` and their argument names have changed across extension revisions — read the loaded extension source under `~/.local/share/tilt-dev/tilt_modules/` before trusting a keyword.

**`restart_container()` — the trap.** In modern Tilt it is **only supported for Docker Compose resources**; for Kubernetes it is disallowed. If your process does not self-reload:

```python
load('ext://restart_process', 'docker_build_with_restart')
docker_build_with_restart('myapp/api', '.', entrypoint=['/app/bin/serve'],
    live_update=[sync('./api', '/app/api')])
```

That injects a wrapper binary into the image, so it is not free — prefer a language-native reloader (`uvicorn --reload`, `air`, `vite`) and keep the image honest.

#### `k8s_yaml(helm(...))` vs `helm_resource`

| | `k8s_yaml(helm(...))` | `helm_resource` (ext) |
|---|---|---|
| Mechanism | `helm template`, Tilt applies | real `helm upgrade --install` |
| Hooks (`pre-install`, `post-upgrade`) | **not run** | run |
| CRDs in `crds/` | **not rendered** | installed |
| Per-object `resource_deps` | yes, Tilt owns every object | no — the release is one node |
| Live image injection | automatic, Tilt rewrites the ref | via `image_deps` + `image_keys` |
| Tilt UI granularity | per workload, good logs | one resource, coarse |
| Conflict with Helm | Tilt owns objects, `helm list` shows nothing | a real release exists |

**Use `k8s_yaml(helm(...))` for the chart you are editing** — per-workload resources, dependency ordering, live image rewriting, which is the entire point. **Use `helm_resource` for charts you merely consume** (an operator, kube-prometheus-stack, Argo CD) — anything with CRDs or install hooks, where re-implementing install logic Helm already ships and tests is a waste.

Honest limit: **`k8s_yaml(helm())` cannot take `resource_deps` as a unit.** If something must complete before the whole render is applied — registry credentials, a namespace, a CRD — run it as a blocking `local()` call at Tiltfile evaluation time, not a `local_resource`, or it races the apply. And once values get genuinely complicated, `helm()`'s `set=[]`/`values=[]` stops being clearer than the Helm CLI — at that point split the release or move it to `helm_resource` and accept the coarser UI.

#### live_update rules and the classic footguns

Order is fixed and meaningful: `fall_back_on` → `sync` → `run` → (`restart_container`, Compose only). `run` fires only if a synced file matched its `trigger`.

1. **A synced path that is still a build dependency.** Tilt delivers the file *and* queues a full rebuild behind it, and the rebuild wins. It reads as "live_update is broken" rather than "a dep was never excluded". Every `sync('./api', ...)` needs `./api` excluded from what invalidates the image via `only=`/`ignore=`.
2. **A `COPY` change invalidates the sync.** live_update assumes the running container's filesystem still corresponds to the image. Edit the Dockerfile — or a file a `COPY` pulls in that you are *not* syncing — and the container silently diverges. That is what `fall_back_on` is for, and it must be first.
3. **A hostPath mount shadows the sync target.** If the chart bind-mounts `/opt/src/api` over `/app/api` for dev mode, a synced file is written into a mount that is really the host directory — two mechanisms fighting, and the bind mount wins. **One decision, two files:** mounts on means no `sync` for that path; `sync` means mounts off. A bind mount also *beats* a sync on latency — Tilt must notice, tar, exec and untar; the mount is already the same inode.

#### Skaffold, mirrord, telepresence

**Skaffold** — pick it when the same artifact definition must serve dev *and* CI, or when you want debuggers for free: `skaffold debug` rewrites container entrypoints to launch delve/debugpy/inspector and forwards the ports, which in Tilt you wire by hand. It is config-file-driven, a virtue in CI and a constraint locally — no conditional logic without profiles. One service and a pipeline → Skaffold; several services and a human watching a UI → Tilt.

**mirrord / telepresence** buy the opposite trade: the service runs as a **local process in your IDE at native speed**, with the cluster's environment, service DNS, secrets and optionally intercepted inbound traffic. Worth the weirdness when the bottleneck is the *debugger experience*. Not worth it when several services change together, or when the bug is about scheduling, resources, init containers or RBAC — exactly what running locally removes. Telepresence needs a cluster-side traffic manager (and stealing traffic in a shared cluster affects other people — say so before you do it); mirrord is per-process with no cluster install, so it is the easier one to try.

#### Debugging inside the loop

```yaml
# values-dev.yaml — one chart, a dev profile. Production values never change.
debug:
  enabled: true
  command: ["python", "-m", "debugpy", "--listen", "0.0.0.0:5678", "--wait-for-client",
            "-m", "uvicorn", "api.main:app", "--host", "0.0.0.0", "--reload"]
replicaCount: 1        # a debugger and >1 replica is a coin flip about which pod you hit
```

Ports: debugpy **5678**, delve **40000**, node inspector **9229**, JDWP **5005**. Go needs `-gcflags="all=-N -l"` and no `-s -w`, or delve shows you optimized-away variables.

```bash
kubectl debug -n dev -it deploy/api --image=nicolaka/netshoot --target=api -- bash
kubectl debug -n dev pod/api-xxxx --copy-to=api-dbg --container=api -- sleep infinity
tilt logs                       # Tilt's own engine log — where "why did it rebuild" lives
tilt dump engine | head -50     # full internal state; answers ownership questions
```

`--wait-for-client` blocks startup until you attach, which trips the readiness probe and gets the pod killed in a loop. Raise `initialDelaySeconds`/`failureThreshold` in the dev overlay, or make the attach non-blocking.

#### The honest failure modes

1. **Everything rebuilds on every save.** A watched path is inside a build context — usually a generated directory written by a codegen step that the build then invalidates, so the loop feeds itself. Fix with `only=`/`ignore=` plus `watch_settings(ignore=...)`; confirm with the build's "Changed files" list in the UI, do not guess.
2. **The new image is not running, and nothing errors.** Two distinct causes, both silent. `imagePullPolicy: Always` makes the kubelet ignore a `kind load`ed image and try a registry that does not have it. And with a **fixed tag**, a rebuilt image is not a spec change — Kubernetes only recreates a pod when the Deployment spec changes, so `IfNotPresent` keeps the *original* container forever. Let Tilt inject its own per-build tag.
3. **Stale Helm release state.** `k8s_yaml(helm())` never creates a release, so a leftover real release from an earlier `helm install` fights Tilt's apply, and `helm list` looks empty while `helm history` explains everything. Also: a failed `helm upgrade` leaves `pending-upgrade`, and every later attempt refuses. `helm rollback` or uninstall; do not `--force` past it.
4. **Tilt and GitOps fighting over the same namespace.** Argo self-heals the field Tilt just changed; Tilt re-applies; the pod restarts every few seconds and the logs look like a crashloop. Either disable auto-sync on that Application for the duration, or — better — **make ownership a stated choice**: Argo owns one namespace, Tilt gets its own.
5. **`tilt down` leaves things standing.** It only removes what Tilt applied. CRDs, PVCs, namespaces created by a chart hook and anything a `helm_resource` installed can all outlive it. On a throwaway cluster, delete the cluster; that is what "throwaway" is for.

#### The other dev clusters, one line each

```bash
# k3d: k3s in docker, ships a registry flag and a load balancer
k3d cluster create dev --servers 1 --agents 2 \
  --registry-create dev-registry:0.0.0.0:5001 \
  -p "80:80@loadbalancer" -p "443:443@loadbalancer"

# minikube: VMs or docker driver, addons for everything
minikube start --nodes 3 --cpus 4 --memory 8g --addons ingress,metrics-server,registry
eval $(minikube docker-env)                       # build straight into the node

# Talos in Docker: the same immutable OS you might run in production
talosctl cluster create --workers 2
```

```bash
# kind, daily
kind get clusters
kind load docker-image myapp:dev --name dev       # sideload without a registry
kind export logs ./kind-logs --name dev           # everything, when a node misbehaves
kind delete cluster --name dev
```

#### Skaffold, the same loop as YAML

```yaml
# skaffold.yaml
apiVersion: skaffold/v4beta11
kind: Config
metadata: { name: myapp }
build:
  local: { push: true, useBuildkit: true }
  tagPolicy: { gitCommit: { variant: AbbrevCommitSha } }
  artifacts:
    - image: localhost:5001/myapp
      docker: { dockerfile: Dockerfile.dev }
      sync:
        infer: ["**/*.py", "**/*.html"]          # or manual: [{src, dest}]
deploy:
  helm:
    releases:
      - name: myapp
        chartPath: charts/myapp
        namespace: dev
        valuesFiles: [charts/myapp/values-dev.yaml]
        setValueTemplates:
          image.repository: "{{.IMAGE_REPO_localhost_5001_myapp}}"
          image.tag: "{{.IMAGE_TAG_localhost_5001_myapp}}"
portForward:
  - { resourceType: service, resourceName: myapp, namespace: dev, port: 80, localPort: 8080 }
profiles:
  - name: prod
    build: { googleCloudBuild: {} }
```

```bash
skaffold dev                   # watch + sync + redeploy, streams logs
skaffold run -p prod           # one-shot build+deploy (CI)
skaffold render -p prod > out.yaml   # just the manifests — hand them to GitOps
skaffold delete
skaffold debug                 # attaches delve / debugpy / jdwp automatically
```

`skaffold debug` is the one thing Skaffold gives you free that Tilt makes you wire by hand.

#### Run-it-on-my-laptop tools

```bash
# DevSpace: swaps the container image for a dev image + file sync + ssh
devspace init && devspace dev        # opens a shell in the dev container
devspace purge

# mirrord: run the binary locally, with the pod's network, env and volumes
mirrord exec --target deployment/myapp -n dev -- ./bin/myapp

# Telepresence: intercept traffic to a service and route it to your laptop
telepresence connect && telepresence intercept myapp -n dev --port 8080:80
```

| | Tilt | Skaffold | DevSpace | mirrord / Telepresence |
|---|---|---|---|---|
| Config | Tiltfile (Starlark) | `skaffold.yaml` | `devspace.yaml` | none, CLI flags |
| Best at | Multi-service repos, UI, `local_resource` | CI parity — the same file dev and prod | Terminal-in-container dev, per-dev namespaces | Debugging one service against real cluster deps |
| Where code runs | in cluster | in cluster | in cluster | **on your laptop** |
| Teardown | `tilt down` | `skaffold delete` | `devspace purge` | `telepresence quit` |

> **Gotcha.** Telepresence's intercept *steals* traffic to that service for everyone on the cluster. Say so before you run it in a shared environment. mirrord is per-process with no cluster install, which makes it the safer one to try first.


---


<a id="06-helm-values-and-crds"></a>

## 06 · Helm, values and CRDs

### Chapter A — Helm, properly

#### Chart anatomy

| Path | What it is actually for |
|---|---|
| `Chart.yaml` | Identity + dependency list. `apiVersion: v2`, `version` (the chart), `appVersion` (the thing shipped), `kubeVersion` (a semver range the API server must satisfy — **a real install-time gate**, not documentation), `type: application\|library` |
| `values.yaml` | The *documented default* for every knob. Every key you template must appear here, even as `null` — an undocumented key is an undiscoverable key |
| `values.schema.json` | JSON Schema (draft-07) validated on `install`/`upgrade`/`lint`/`template` |
| `templates/` | Rendered Go templates. Anything emitting a YAML doc |
| `templates/_helpers.tpl` | Files starting `_` are never rendered as manifests. Home for `define`d named templates |
| `templates/NOTES.txt` | Rendered and printed post-install. The URL and the "now run this" line, not a changelog |
| `templates/tests/` | Pods annotated `helm.sh/hook: test`, run by `helm test` |
| `charts/` | Vendored subchart tarballs, populated by `helm dep build` |
| `crds/` | Plain YAML (**no templating**), applied before `templates/`, and **never upgraded or deleted by Helm** |
| `Chart.lock` | Resolved dependency versions + digest. Commit it |
| `.helmignore` | Keeps junk out of the packaged tarball |

#### Templating that survives contact

```yaml
{{- define "myapp.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "myapp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
```

- **`include` vs `template`.** `template` is a statement — it writes straight to output and cannot be piped. `include` is a function — it returns a string. **Always use `include`**, because the only way to indent a multi-line block correctly is `{{ include "x" . | nindent 4 }}`.
- **`toYaml | nindent`.** `nindent N` = newline + indent every line by N. `indent N` does *not* prepend the newline; pairing it with a trailing `:` on the previous line is the classic broken-YAML bug.
- **Whitespace.** `{{-` eats preceding whitespace *including the newline*; `-}}` eats following. Control-flow lines (`if`/`range`/`end`) should be `{{- ... }}` so they leave no blank line. Value-emitting lines should not chomp forward, or you glue two scalars together.
- **`required`** — `{{ required "global.domain must be set" .Values.global.domain }}` fails the render with your message. **`default`** — note it fires on any *empty* value, so `0` and `false` become the default. For booleans use `{{ if hasKey .Values "x" }}` or `dig`.
- **`fail`** — `{{- fail "Set exactly one of a.enabled / b.enabled" }}` for mutually exclusive config. Fail loudly on misconfiguration; skip silently on nothing-to-do.
- **`tpl`** — renders a *value* as a template: `{{ tpl .Values.ingress.host . }}` lets a user write `"{{ .Release.Name }}.example.com"` in their values. Cheap, and a template-injection surface if values come from untrusted input.
- **Built-ins.** `.Values`, `.Release.{Name,Namespace,Revision,IsInstall,IsUpgrade,Service}`, `.Chart.*`, `.Capabilities.{KubeVersion,APIVersions.Has "..."}`, `.Files.Get`/`.Files.Glob`/`.Files.AsConfig`, `.Template.Name`.
- **`lookup`** reads live cluster state. It returns empty during `helm template` and `--dry-run`, so any chart using it for password persistence renders *differently* offline. Know that before you debug it.

#### The commands

```bash
helm template rel ./chart -f values.yaml --debug          # primary debugging tool
helm template rel ./chart --show-only templates/deploy.yaml
helm template rel ./chart --kube-version 1.35.0 --api-versions gateway.networking.k8s.io/v1
helm lint ./chart --strict --with-subcharts
helm diff upgrade rel ./chart -f v.yaml                   # plugin: databus23/helm-diff
helm upgrade --install rel ./chart -f base.yaml -f prod.yaml \
  --atomic --timeout 15m --wait-for-jobs
helm get manifest rel        # what is actually in the release
helm get values rel -a       # -a = computed, incl. chart defaults
helm get hooks rel           # hooks are NOT in `get manifest`
helm history rel && helm rollback rel 7 --wait
helm test rel --logs
```

**`helm template` is your primary debugging tool** because it is offline, fast, and shows you the exact bytes. It does *not* validate against the API server; add `--validate` (needs a cluster) or use `helm install --dry-run=server` (Helm ≥ 3.13) to catch schema and webhook rejections.

| Flag | Meaning |
|---|---|
| `--wait` | Wait for Deployments/StatefulSets/PVCs to be ready. Does **not** wait for Jobs |
| `--wait-for-jobs` | Also wait for non-hook Jobs to complete. Use whenever a Job gates correctness |
| `--atomic` | `--wait` + auto-rollback on failure. Always pair with a generous `--timeout`; the default 5m plus a rollback storm mid-migration is worse than a slow install |
| `--force` | Delete-and-recreate on conflict. Recreates Services, drops PVC bindings. Avoid |

`helm rollback` restores manifests only. **It cannot roll back a database migration** and will not un-delete a PVC.

#### Hooks and weights

```yaml
annotations:
  helm.sh/hook: post-install,post-upgrade
  helm.sh/hook-weight: '15'            # string! ascending, lowest first
  helm.sh/hook-delete-policy: before-hook-creation
```

Phases: `pre-install`, `post-install`, `pre-upgrade`, `post-upgrade`, `pre-delete`, `post-delete`, `pre-rollback`, `post-rollback`, `test`. Delete policies: `before-hook-creation` (default), `hook-succeeded`, `hook-failed`.

**Don't use hooks when:** (a) the object must be tracked/pruned as part of the release — hooks are invisible to `helm get manifest` and are **not** deleted by `helm uninstall` unless a delete policy says so; (b) a GitOps controller also orders things — Argo CD's `argocd.argoproj.io/hook` *overrides* `helm.sh/hook`, so a chart carrying only Helm hooks gets silently re-timed; (c) ordinary dependency waiting, which belongs in an **init container**.

Prefer `before-hook-creation` over `hook-succeeded`: **a hook that deletes itself on success is indistinguishable from one that never ran**, which is exactly the question you ask at 2 a.m.

#### Dependencies

```yaml
dependencies:
  - name: gateway-helm
    version: v1.7.1
    repository: oci://docker.io/envoyproxy
    alias: envoy-gateway                 # the values key becomes `envoy-gateway:`
    condition: envoy-gateway.install     # missing key => default true
  - name: cert-manager
    version: v1.17.1
    repository: https://charts.jetstack.io
    tags: [pki]
    import-values: [{ child: service, parent: certService }]
```

- `helm dep update` re-resolves version ranges and **rewrites `Chart.lock`**. `helm dep build` installs exactly what the lock says and fails if it can't — **`build` is the CI command**, `update` is the deliberate bump.
- `condition` takes a values path (first existing wins); `tags` groups charts under one boolean. Conditions beat tags for readability.
- `alias` lets you install the same chart twice. **Two dependencies from different repos may not share a chart name**, even aliased — the fix is wrapping one in a local passthrough chart (`repository: file://charts/minio-operator-wrapper`).
- `global:` is the only values tree automatically visible to every subchart. `import-values` is the escape hatch for child→parent propagation.

#### Umbrella charts: subchart or separate release?

**Decision rule: same lifecycle, same release. Different lifecycle, different release.** "Lifecycle" = upgraded at the same moment, by the same person, with the same blast radius and the same rollback. Layer (infra vs app) is the wrong axis; cadence and ownership are the right one. Cluster-scoped CRDs and operators outlive twelve app upgrades → separate release. A frontend and the backend it talks to ship together → same release.

**Helm has no ordering primitive inside a release beyond hook weights.** Within a release it applies resources in a fixed *kind* order (Namespace → CRD → … → Deployment), which is not dependency ordering. The three honest solutions:

1. **Separate releases, explicit ordering** — operators + CRDs installed first, then the umbrella. The only approach that also gets you independent rollback.
2. **Argo CD sync-waves** — `argocd.argoproj.io/sync-wave: "N"`, ascending, each wave Healthy before the next. Powerful and a foot-gun: a hook at wave 15 in a chart whose objects are all wave 0 never gets created, because the wave it waits for never goes Healthy without it. Symptom: `kubectl get jobs` shows *nothing*, which reads as "the chart never defined the Job".
3. **Init containers that wait on a condition** — the most robust, because it works identically under Helm, Argo and Tilt. Wait on the resource that indicates readiness, never on a `sleep`.

#### Helm and OCI registries

```bash
helm registry login registry.example.com -u ci --password-stdin
helm package ./chart -d dist/ --version 1.4.2 --app-version 2.7.0
helm push dist/platform-1.4.2.tgz oci://registry.example.com/charts
helm pull oci://registry.example.com/charts/platform --version 1.4.2
helm package ./chart --sign --key 'ops@example.com' --keyring ~/.gnupg/secring.gpg
helm verify dist/platform-1.4.2.tgz          # or: helm install --verify
```

Gotchas, all of which bite once:

- **The OCI ref is the *directory*, not the chart.** `oci://registry/charts` — Helm appends the chart name from `Chart.yaml`. Putting the name in a dependency's `repository:` yields `.../platform/platform`.
- **The chart name must equal the last path segment of the pushed artifact.** Renaming the tarball does nothing; the name comes from `Chart.yaml`.
- Chart version must be strict SemVer2 — OCI tags reject `+`, which Helm rewrites to `_`.
- `helm push` uploads the `.prov` file automatically if it sits beside the `.tgz`. `--verify` needs the public key in the local keyring; there is no registry-side trust check.
- `helm search repo` does not work against OCI. There is no index; you need registry catalogue APIs.

---

### Chapter B — Values architecture

#### The layering model

Precedence, lowest to highest — **later wins**:

```
chart values.yaml  →  -f base.yaml  →  -f env/prod.yaml  →  -f cluster/gke-ca.yaml
                   →  -f secrets.dec.yaml  →  --set / --set-string / --set-json
```

```
deploy/
  base.yaml                  # true for every install: labels, probes, policy
  env/{dev,staging,prod}.yaml
  clusters/{gke-ca-1,onprem-a}.yaml   # storageClass, CNI, domain, node selectors
  contract/global.yaml       # cross-chart contract: provisioned roles, buckets
  secrets/prod.sops.yaml     # encrypted at rest, never plaintext
```

```bash
helm upgrade --install platform ./platform \
  -f deploy/base.yaml -f deploy/env/prod.yaml \
  -f deploy/clusters/gke-ca-1.yaml -f deploy/contract/global.yaml \
  --atomic --timeout 20m --wait-for-jobs
```

Keep the `-f` list *identical* between CI, the install script, the Tiltfile and the docs. Drift between "how CI installs it" and "how a human installs it" is the single most common source of "works in CI only".

#### Merge semantics — the one that surprises everyone

**Maps deep-merge. Lists are replaced wholesale.** No append, no index-merge, no exceptions.

```yaml
# base.yaml
env:
  - {name: LOG_LEVEL, value: info}
  - {name: REGION,    value: ca}
# prod.yaml
env:
  - {name: LOG_LEVEL, value: warn}
```

Result: **one** env var. `REGION` is gone. If a key will be overridden per environment, **model it as a map keyed by name** and `range` over it:

```yaml
env:
  LOG_LEVEL: info
  REGION: ca
```
```yaml
{{- range $k, $v := .Values.env }}
- name: {{ $k }}
  value: {{ $v | quote }}
{{- end }}
```

Also: setting a key to `null` in a later file **deletes** it from the merge (`--set x=null` likewise). That is the only way to remove a chart default.

#### `values.schema.json` — the highest-leverage thing you can add

It converts a typo from a silent 3 a.m. outage into an instant, local, pre-apply error. It runs on `lint`, `template`, `install` and `upgrade`, so CI catches it without a cluster.

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "global": {
      "type": "object",
      "properties": {
        "domain":   {"type": "string", "format": "hostname"},
        "registry": {"type": "string", "format": "uri-reference"},
        "size":     {"type": "string", "enum": ["small", "medium", "large"]}
      },
      "required": ["domain", "registry", "objectStore"]
    }
  },
  "required": ["global"]
}
```

Put the schema in the *parent* chart and in each subchart (subchart schemas validate their own subtree). **Avoid `additionalProperties: false` at the top level** — Helm injects `global` into every subchart's values and a strict subchart schema will reject it. `enum` on deployment-shape strings is the cheapest win available.

#### Secrets

Never in `values.yaml`, never in a committed plaintext `-f` file, never in `--set` (it lands in shell history *and* in `helm get values`). Also: **anything in values is recoverable from the release Secret in-cluster** by anyone with `get secret` in that namespace.

| Option | Shape | Cost |
|---|---|---|
| External Secrets Operator | CRD pulls from Vault/OpenBao/GSM/ASM into a `Secret` | Operator + workload-identity wiring |
| sops + helm-secrets | Encrypted file in git, decrypted at `helm` time | Key distribution to every operator and CI runner |
| sealed-secrets | Encrypted blob in git, controller decrypts in-cluster | Cluster-bound key; re-seal on cluster rebuild |

**Recommendation: External Secrets Operator.** It is the only one of the three where the secret *never enters the chart, the repo, or the render* — rotation happens without a deploy, and `helm template` output is safe to paste into a ticket. sops is the right answer only if you have no secret manager at all.

#### Globals and the subchart nesting trap

`global:` is the only tree every subchart sees at the same path. Everything else nests under the **alias** (not the chart name) declared in `Chart.yaml`:

```yaml
global:
  domain: myapp.example.com    # visible as .Values.global.domain everywhere
myapp:                          # alias of chart `myapp-chart`
  backend:
    replicas: 3
envoy-gateway:                  # alias with a hyphen => use `index .Values "envoy-gateway"`
  install: true
```

Traps: a subchart cannot read parent non-global values (use `import-values`); `--set myapp.backend.replicas=3` silently does nothing if the alias is wrong, because **Helm does not error on unknown values** — which is exactly what `values.schema.json` fixes. Keys with hyphens cannot be dotted in templates.

#### Environment promotion

The chart is immutable across environments; only values change. Per-env, pin:

| Pinned per env | Why |
|---|---|
| Image **digests** for third-party, floating tag for first-party | Digest-pin what you don't build; you rebuild your own |
| `replicas`, `resources`, HPA bounds | The only legitimate reason prod differs |
| Ingress/Gateway hostnames | **80/443 are cluster-wide**: each namespace needs a unique hostname |
| `storageClass`, access modes, volume sizes | Differs by cloud/on-prem |
| `global.size` preset | **One-way door — see below** |

> **One-way door: PVC sizes only grow.** A `size` preset smaller than what the cluster was built at wedges both `helm upgrade` and the dev-loop apply with `can't shrink existing storage from 20Gi to 10Gi`, with no path forward short of rebuilding. Make the dev default match what the installers pass.

#### Many releases: helmfile or Argo CD?

**Recommendation: Argo CD** (multi-source Applications, or an ApplicationSet), because it is *continuously reconciling* — helmfile tells you what the last person to run it applied, Argo tells you what is true right now, and drift detection is worth more than templating ergonomics. Multi-source lets the chart come from OCI and the values from git, which kills the "vendored values fork" anti-pattern. Choose helmfile only if you cannot run a controller in the cluster (air-gapped one-shot installers) — its `needs:` ordering is genuinely better than sync-waves.

**Whichever you pick: one controller owns each object.** Two reconcilers fighting over one resource is not redundancy. Where Argo owns something, Helm and your dev-loop tooling must defer.

---

### Chapter C — CRDs and operators without tears

#### What a CRD actually is

A `CustomResourceDefinition` registers a new API group/version/kind with the API server and gives it an OpenAPI v3 structural schema. After that, custom resources are ordinary API objects: etcd storage, RBAC, watch, `kubectl`, admission. **The CRD is the schema; the operator is the thing that makes it mean something.** Install a CRD with no controller and you get a perfectly valid object that does nothing forever — the #1 support ticket.

Per-version flags: `served` (reachable over the API) and `storage` (**exactly one** version, the one written to etcd). Multiple served versions need `spec.conversion`: `strategy: None` (fine when versions are field-compatible) or `strategy: Webhook` (a service the API server calls on every read/write of a non-storage version — a hard dependency on that pod being up).

#### The `crds/` directory and its permanent limitation

Helm installs `crds/*.yaml` before `templates/`, and:

- **No templating.** Plain YAML only.
- **Never upgraded.** `helm upgrade` skips `crds/` entirely.
- **Never deleted.** `helm uninstall` leaves them.

Real-world consequence: you bump a dependency chart, the new operator emits CRs with a new field, and the API server **strips the unknown field silently** because the old CRD schema is still installed. Nothing errors. The feature just doesn't work, and it looks like an application bug. **Raise this every single time a chart-dependency bump is discussed.**

Three workarounds:

1. **Separate CRD chart / release, installed first.** Best: explicit version, explicit ordering, and CRD upgrades become a decision instead of an accident.
2. **Ship CRDs in `templates/` behind a `crds.install` flag** so Helm manages them normally — then add `helm.sh/resource-policy: keep` so uninstall doesn't nuke every CR in the cluster. Widely used (cert-manager's `installCRDs`).
3. **Let the operator manage its own CRDs** at startup. Least ceremony, but the operator now needs cluster-scoped write on CRDs, which is a meaningful privilege.

#### Installing CRDs properly

```bash
kubectl apply --server-side --force-conflicts -f crds/
kubectl wait --for condition=established --timeout=120s crd/clusters.postgresql.cnpg.io
kubectl apply -f my-cluster.yaml
```

Client-side `kubectl apply` stores the whole object in the `last-applied-configuration` annotation, which trips the **262144-byte annotation limit** on big CRDs: `metadata.annotations: Too long: must have at most 262144 bytes`. **`--server-side` is the correct fix** — it uses managed fields instead of the annotation. `--force-conflicts` takes ownership from a previous applier; know whose fields you are stealing before you pass it.

`kubectl replace -f` also avoids the annotation but requires the object to exist and does a full overwrite. `kubectl create -f` works for a first install because it writes no annotation — but then the *next* `kubectl apply` behaves as a first apply and can drop fields. Pick server-side apply and stay on it.

**Always `wait --for condition=established` before applying CRs.** A CR applied in the window between CRD creation and discovery-cache refresh fails with `no matches for kind`, and inside a Job that reads as a flaky deploy. Client-side `kubectl` caches discovery for 10 minutes; `kubectl api-resources` or deleting `~/.kube/cache/discovery` forces a refresh.

#### The operator pattern

- **Controller** — watches (informer + workqueue) one or more kinds.
- **Reconcile loop** — *level-triggered*, not edge-triggered: handed a name, it reads current state and drives toward desired state. Must be idempotent and safe to run a thousand times.
- **Status conditions** — `type/status/reason/message/lastTransitionTime/observedGeneration`. `observedGeneration < metadata.generation` means **the controller has not yet seen your edit**.
- **Finalizers** — strings in `metadata.finalizers`. `DELETE` sets `deletionTimestamp` and blocks removal until the list empties. This is how external cleanup (a bucket, a DNS record) happens.
- **Owner references** — drive cascading GC. Cross-namespace owner refs, and a namespaced owner for a cluster-scoped object, are **invalid**, and the child gets garbage-collected immediately — a genuinely confusing failure.

#### Troubleshooting an operator — decision tree

**Symptom: CR created, nothing happens.** Work down in order; each step is one command.

```bash
# 1. Did the controller even see it?
kubectl get widget my-widget -o jsonpath='{.metadata.generation} {.status.observedGeneration}{"\n"}'
# 2. What does the CR say about itself?
kubectl get widget my-widget -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
kubectl describe widget my-widget          # events at the bottom
# 3. Operator logs
kubectl -n operator-ns logs deploy/widget-operator --since=10m -f
kubectl -n operator-ns get pods            # CrashLoop? OOMKilled? 0/1 Ready?
# 4. RBAC — the most common silent failure
kubectl auth can-i list widgets.example.com \
  --as=system:serviceaccount:operator-ns:widget-operator -n my-ns
kubectl auth can-i create statefulsets \
  --as=system:serviceaccount:operator-ns:widget-operator -n my-ns
# 5. Is it watching this namespace?
kubectl -n operator-ns get deploy widget-operator -o yaml | grep -iE 'WATCH_NAMESPACE|--namespace'
# 6. Does the CRD version match what the operator wants?
kubectl get crd widgets.example.com -o jsonpath='{range .spec.versions[*]}{.name} served={.served} storage={.storage}{"\n"}{end}'
```

Nine times in ten it is (4) RBAC or (5) namespace scope. RBAC failures show as `is forbidden` in the operator log and **nothing at all on the CR** — which is why you read the log before you theorize.

**Symptom: deletion stuck.** The object has `deletionTimestamp` and non-empty `finalizers`. First find out *why* the finalizer isn't clearing — usually the operator is down or lacks permission for the external cleanup. Fix that and it drains on its own. Escape hatch:

```bash
kubectl get widget my-widget -o jsonpath='{.metadata.finalizers}{"\n"}'
kubectl patch widget my-widget --type=merge -p '{"metadata":{"finalizers":null}}'
```

> **Warning.** This deletes the Kubernetes object and *skips the cleanup the finalizer existed to perform*. Buckets, load balancers, DNS records and PVs are orphaned and keep billing. Use it only after confirming what the finalizer does and cleaning up manually. Never scripted.

**Symptom: hot reconcile loop.** The controller writes, its own write triggers a watch event, it writes again.

```bash
kubectl get events -n my-ns --sort-by=.lastTimestamp | tail -40   # same reason, seconds apart, high count
kubectl get widget my-widget -o jsonpath='{.metadata.resourceVersion}{"\n"}'   # climbing with no user edits
```

In operator metrics: `controller_runtime_reconcile_total` rate and `workqueue_adds_total` climbing while `workqueue_depth` stays low. Root cause is almost always a status write that mutates spec-adjacent fields, or a defaulting webhook that changes the object on every write.

**Symptom: every apply in the cluster fails.** A dead admission webhook with `failurePolicy: Fail`. `Internal error occurred: failed calling webhook ...: connect: connection refused`.

```bash
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations
kubectl get validatingwebhookconfiguration X \
  -o jsonpath='{range .webhooks[*]}{.name} {.failurePolicy} {.clientConfig.service.namespace}/{.clientConfig.service.name}{"\n"}{end}'
kubectl -n <ns> get endpoints <svc>      # empty endpoints == dead webhook
```

Fix the backing pod if you can. If you must unblock the cluster, **back up the config first** (`kubectl get validatingwebhookconfiguration X -o yaml > /tmp/X.yaml`), then delete it — and understand you have disabled a validation gate cluster-wide until it is restored. Reinstalling the operator's chart normally recreates it.

#### CRD upgrade hazards

`status.storedVersions` lists every version ever written to etcd for that CRD.

```bash
kubectl get crd widgets.example.com -o jsonpath='{.status.storedVersions}{"\n"}'
```

**You cannot remove a version from `spec.versions` while it is still in `status.storedVersions`** — the API server rejects it, and if forced, stored objects become unreadable. The correct sequence:

1. Add the new version, mark it `storage: true`, keep the old one `served: true, storage: false`.
2. **Rewrite every existing object** so it re-persists at the new storage version — a no-op patch across all CRs, or the storage-version-migrator (`storagemigration.k8s.io/v1alpha1`, alpha as of 1.30 — *confirm against your cluster*).
3. Patch `status.storedVersions` down to the single new version.
4. Only then drop the old version from `spec.versions`.

Other hazards, all silent:

- Tightening a schema (adding `required`, narrowing an `enum`) does **not** validate existing objects. They sit there invalid until something touches them, then that write fails — typically inside an operator, at 3 a.m.
- Removing a field from the schema without `x-kubernetes-preserve-unknown-fields` **prunes the data out of etcd** on the next write. Not recoverable.
- A conversion-webhook outage makes *reads* of non-storage versions fail, which can look like the whole API group vanishing.

#### helmfile: many releases, one command

```yaml
# helmfile.yaml
environments:
  dev:  { values: [values/common.yaml, values/dev.yaml] }
  prod: { values: [values/common.yaml, values/prod.yaml] }
---
repositories:
  - name: prom
    url: https://prometheus-community.github.io/helm-charts
releases:
  - name: myapp
    namespace: payments
    chart: oci://harbor.internal/charts/myapp
    version: 1.4.2
    values: [values/common.yaml, "values/{{ .Environment.Name }}.yaml"]
  - name: kube-prometheus-stack
    namespace: monitoring
    chart: prom/kube-prometheus-stack
    version: 65.1.1
    values: [infra/monitoring/values.yaml]
    needs: []            # ordering via needs: [ns/release]
```

```bash
helmfile -e prod diff        # what would change (uses helm-diff)
helmfile -e prod apply       # diff, then upgrade only what changed
helmfile -e prod sync        # upgrade everything regardless
helmfile -e prod destroy
```

helmfile's `needs:` is genuinely better ordering than Argo sync-waves — it is a real dependency graph rather than integer buckets. The reason the recommendation still lands on Argo is reconciliation, not templating: **helmfile tells you what the last person to run it applied; Argo tells you what is true right now.** Use helmfile where you cannot run a controller — air-gapped one-shot installers, bootstrap scripts.

#### Templating habits that scale

- `{{- toYaml .Values.resources | nindent 12 }}` for pass-through blocks; `{{ include "myapp.labels" . | nindent 4 }}` for shared labels.
- **Checksum annotations restart pods when config changes** — without this, a ConfigMap edit changes nothing until the next unrelated rollout:
  ```yaml
  annotations:
    checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
  ```
- `{{ .Capabilities.APIVersions.Has "monitoring.coreos.com/v1" }}` to skip a ServiceMonitor when Prometheus Operator isn't installed. **Beware:** `helm template` without `--api-versions` sees no CRDs, so the rendered output differs from what a real install produces.
- Test with [helm-unittest](https://github.com/helm-unittest/helm-unittest): `helm unittest charts/myapp`, with snapshot tests per values file. A chart with three environments and no tests has three untested configurations.
- **Library charts** (`type: library`) for templates shared across many services; publish them as OCI too.

#### Writing an operator (kubebuilder in five lines)

```bash
kubebuilder init --domain example.com --repo github.com/example/myapp-operator
kubebuilder create api --group apps --version v1alpha1 --kind MyApp --resource --controller
make manifests generate      # CRDs from Go types (+kubebuilder markers) → config/crd/bases
make install run             # CRDs into the current cluster, controller runs locally against it
make docker-build docker-push IMG=harbor.internal/myapp-operator:$SHA && make deploy IMG=...
```

Two conventions that make your operator debuggable by everyone else's runbook: **emit `.status.conditions` as `metav1.Condition`** with the standard `Ready` / `Progressing` / `Degraded` types, and **set a finalizer only if you own external state** — otherwise `ownerReferences` garbage collection is enough, and a finalizer you don't need is a deletion that hangs.


---


<a id="07-kustomize-and-the-repo-split"></a>

## 07 · Kustomize and the repo split

Application code and cluster state change for different reasons, by different people, at different speeds. Put them in different places and connect them with exactly one artifact: **the image tag**. Kustomize is the tool for the "same thing, slightly different per environment" problem in the middle.

#### Kustomize in four moves

```
apps/myapp/
├── base/
│   ├── kustomization.yaml       # resources: [deployment.yaml, service.yaml]
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    ├── dev/kustomization.yaml
    └── prod/kustomization.yaml
```

```yaml
# overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: payments
resources: [../../base, pdb.yaml, hpa.yaml]
commonLabels: { env: prod }
images:                                   # the connection to the app repo: just the tag
  - name: harbor.internal/myapp
    newTag: sha-a1b2c3d
replicas: [{ name: myapp, count: 4 }]
patches:
  - target: { kind: Deployment, name: myapp }
    patch: |-
      - op: add
        path: /spec/template/spec/topologySpreadConstraints
        value: [{ maxSkew: 1, topologyKey: topology.kubernetes.io/zone, whenUnsatisfiable: DoNotSchedule, labelSelector: { matchLabels: { app: myapp } } }]
configMapGenerator:
  - name: myapp-config
    files: [config.yaml]                  # hashed name → pods roll on change
helmCharts:                               # inflate a Helm chart inside kustomize (needs --enable-helm)
  - name: redis
    repo: oci://registry-1.docker.io/bitnamicharts
    version: 20.1.0
    releaseName: cache
    valuesFile: redis-values.yaml
```

```bash
kustomize build overlays/prod | kubeconform -strict
kubectl apply -k overlays/prod
kubectl diff -k overlays/prod
kustomize edit set image harbor.internal/myapp=harbor.internal/myapp:sha-$SHA   # what CI runs
kustomize build --enable-helm overlays/prod
```

**`configMapGenerator` earns its place on its own.** It appends a content hash to the ConfigMap name and rewrites every reference, so a config change *is* a pod-template change and the rollout happens automatically. Doing that by hand in Helm needs a `checksum/config` annotation, which people forget.

#### Helm or Kustomize?

Not a rivalry. They solve different halves.

| | Helm | Kustomize |
|---|---|---|
| Model | Templating + a release lifecycle | Patching rendered YAML |
| Strength | Distribution — a versioned artifact with dependencies, hooks, rollback | Environment variance without a template language |
| Weakness | Template logic gets unreadable fast | No packaging, no versioning, no release history |
| Use it for | The chart **you ship** or **consume** | The per-environment deltas on top |

**Rule: don't template what you can patch.** If a value differs per environment, it belongs in a values file or an overlay. If the *structure* differs, that's a patch. If you find yourself writing `{{ if eq .Values.env "prod" }}` in a template, you've put environment logic in the wrong layer.

#### Two repositories, one contract

```
                 ┌──────────────── App repo: myapp ────────────────┐
                 │  src/ · Dockerfile · chart or kustomize base    │
                 │           ↓                                     │
                 │  CI: test → build → scan → push image + chart   │
                 └───────────────┬─────────────────┬───────────────┘
                                 │ image sha-a1b2c3d│ PR: bump tag
                                 ▼                  ▼
                            Registry        ┌─── GitOps repo: platform ───┐
                                 │          │ clusters/  infrastructure/  │
                                 │          │ apps/      policies/        │
                                 │          └──────────────┬──────────────┘
                                 │                         ▼
                                 │                  Flux / Argo CD
                                 └────── pull ──────────▶ Clusters
```

**CI writes images and a tag bump; it never touches the cluster. The GitOps agent is the only thing holding cluster credentials.**

```
platform/
├── clusters/
│   ├── dev-kind/                 # what this cluster runs: pointers only
│   │   ├── flux-system/          # (Flux) bootstrap output
│   │   ├── infrastructure.yaml   # Kustomization → ../../infrastructure/overlays/dev
│   │   └── apps.yaml             # Kustomization → ../../apps/overlays/dev
│   └── prod-eu-west-1/
├── infrastructure/
│   ├── base/                     # cert-manager, ingress, external-secrets, kyverno, monitoring
│   │   └── cert-manager/{namespace.yaml, helmrelease.yaml, kustomization.yaml}
│   └── overlays/{dev,prod}/      # sizes, storage classes, issuers
├── apps/
│   ├── base/myapp/               # HelmRelease or kustomize base
│   └── overlays/{dev,staging,prod}/myapp/   # values, tags, replicas
└── policies/                     # Kyverno ClusterPolicies, applied first
```

- **App repo owns:** code, tests, Dockerfile, the chart (or kustomize base) describing how *this* app runs, and CI that produces an image and a chart version.
- **Platform repo owns:** which clusters exist, what infrastructure they run, which app versions are deployed where, and the policies. **Merges here *are* deployments.**
- **The handoff** is a PR changing one line — a tag — opened by CI or by Flux image automation. Humans approve production; dev auto-merges.
- A monorepo is fine for a small team. The point is not the repo count: it is that **the deploy path goes through git and a reconciler, never through `kubectl apply` from a laptop or a CI runner**.


---


<a id="08-gitops-argo-cd-and-flux"></a>

## 08 · GitOps: Argo CD and Flux

### Chapter A — GitOps: Argo CD and Flux

#### The principle, in three lines

1. **Git is the desired state.** Not a deploy script's input — the state itself. Nothing reaches the cluster except by being in a commit.
2. **A controller reconciles.** It runs in-cluster, pulls, diffs live vs desired, and applies. Nobody pushes from CI; CI writes to git.
3. **Drift is corrected or reported.** Corrected = `selfHeal`. Reported = you get a diff and a human decides. Both are legitimate; choosing wrongly is the most common GitOps injury.

#### The honest part — what GitOps does not solve

| Problem | Why GitOps doesn't fix it |
|---|---|
| **Secrets** | Git is a plaintext broadcast medium. You need a second system. GitOps only moves *references* to secrets |
| **Ordering** | Git is a set, not a sequence. CRDs before CRs, cert-manager before anything with a webhook. Argo solves it with waves, Flux with `dependsOn` — both are additions on top of the model, not consequences of it |
| **One-off migrations** | A DB migration is not idempotent state, it's an event. Hooks/Jobs are the escape hatch and they are the leakiest part of both tools |
| **Bootstrap chicken-and-egg** | The controller that installs everything cannot install itself, and it needs credentials to read the repo holding its own config. Something imperative always runs first |
| **Cluster-external state** | Terraform's job. GitOps does not create the cluster it runs in |

#### Argo CD vs Flux — decision table

| Dimension | Argo CD | Flux (GitOps Toolkit) |
|---|---|---|
| Architecture | One app: `application-controller`, `repo-server`, API+UI, `redis`, `applicationset-controller`, notifications, optional `dex` | Independent controllers: source, kustomize, helm, notification, image-reflector, image-automation |
| UI | First-class, and genuinely why many teams pick it | None official (Weave GitOps / Capacitor are third-party) |
| Multi-tenancy | `AppProject` with `sourceRepos`/`destinations`/resource allow-lists, enforced at admission | Namespace + `serviceAccountName` impersonation on `Kustomization` |
| Helm handling | **Renders with `helm template` and applies the output.** No release secret, so `helm rollback`, `helm list` and Helm **hooks** don't behave as expected — Argo reinterprets hook annotations as its own | `HelmController` performs a **real Helm release** with history and remediation |
| Multi-cluster | One control plane, many registered clusters | One Flux per cluster is the norm |
| Fan-out | `ApplicationSet` generators (git, cluster, list, matrix, merge, PR, SCM) | `Kustomization` per env + post-build substitution |
| RBAC / SSO | Built-in RBAC model, OIDC/Dex, per-project roles | Delegates entirely to Kubernetes RBAC |
| Footprint | Heavier — ~7 pods | Lighter, 4–6 controllers |
| Airgap | Good; charts can come from an in-cluster OCI registry. Caveat: a Helm `targetRevision` is a **tag, not a digest** | Good, and `OCIRepository` **does** support digest pinning |

**Recommendation: Argo CD**, for one reason — the UI plus `AppProject` is the difference between an operator seeing *which* Application is stuck and seeing that *something* timed out. In a fixed-topology, human-operated perimeter, legibility beats Flux's better ordering graph and digest pinning.

**This is reversible but expensive.** Both read the same manifests; migrating is weeks of re-plumbing waves→`dependsOn`, ApplicationSets→Kustomization fan-out, and re-teaching everyone. Decide once, deliberately.

> **Version-sensitive.** Helm-hook semantics, `valuesObject` and multi-source apps all moved across Argo CD 2.6→2.11. Flux's `helm.toolkit.fluxcd.io/v2` (dropping `v2beta2`) landed in Flux 2.3. Check your version before copying YAML.

#### Argo CD in practice

Install — two releases, in order, always:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
  --version 10.2.1 -f values-argocd.yaml
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=120s
helm upgrade --install gitops ./chart -n argocd -f chart/values.yaml
```

The `kubectl wait` is not decoration. Helm orders CRDs before CRs, but the API server must also have **Established** the CRD before a CR validates — the race shows as `no matches for kind "Application"` on a fresh cluster and works on retry.

**App-of-apps:** one hand-committed Application whose source is a directory of Applications. Everything else follows from git. Keep it *off* if in-chart Applications also exist — two owners plus `selfHeal` is a fight, not redundancy.

**Application anatomy:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
  finalizers: [resources-finalizer.argocd.argoproj.io]   # cascade delete
spec:
  project: infra
  source:
    repoURL: https://charts.jetstack.io
    chart: cert-manager
    targetRevision: v1.17.1        # chart version for Helm, git ref for git
    helm:
      valuesObject:                # structured YAML, schema-checked. `values:` is a STRING
        resources: {requests: {cpu: 50m, memory: 128Mi}}
      skipCrds: false
  destination: {server: https://kubernetes.default.svc, namespace: cert-manager}
  syncPolicy:
    automated: {prune: true, selfHeal: true, allowEmpty: false}
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
      - RespectIgnoreDifferences=true
      - PruneLast=true
    retry: {limit: 5, backoff: {duration: 15s, factor: 2, maxDuration: 5m}}
```

**`ServerSideApply=true` is the single most important option for an operator stack.** Client-side apply stores the whole object in the `last-applied-configuration` annotation, capped at 262144 bytes. cert-manager's `issuers` CRD is ~311 KB; CNPG's `poolers` ~648 KB. Without SSA those simply fail to apply.

**Ordering — waves and phases.** `argocd.argoproj.io/sync-wave: "<int>"` (negatives legal). Argo syncs every object in wave N, waits for Healthy, then N+1. Phases run PreSync → Sync → PostSync via `argocd.argoproj.io/hook`. **This is how you solve the ordering problem Helm cannot** — Helm's `--wait` is per-release; waves sequence across releases. The trade: a wave is coarser than a graph, but **a wave number cannot cycle**, whereas a `dependsOn` cycle in Flux is a real deadlock.

**Ignore-differences for mutating admission.** Any webhook that writes to your object will fight `selfHeal` forever:

```yaml
ignoreDifferences:
  - group: admissionregistration.k8s.io
    kind: ValidatingWebhookConfiguration
    jqPathExpressions: ['.webhooks[]?.clientConfig.caBundle']   # cert-manager cainjector
  - group: apps
    kind: Deployment
    jsonPointers: ['/spec/template/spec/containers/0/resources/requests/ephemeral-storage']
```

The second is GKE Autopilot's Warden injecting requests into any container declaring none. Symptom: Application reports `successfully synced` while its Deployment sits permanently `OutOfSync`. Ignoring it stops the fight but **does not stop the billing** — Autopilot bills on requests. The real fix is explicit requests everywhere. And note the trap: a blanket ignore on `.resources` also makes *desired* request changes produce no diff, so Argo never applies the fix.

**ApplicationSet — matrix of git directories × clusters:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata: {name: myapp-envs, namespace: argocd}
spec:
  goTemplate: true
  generators:
    - matrix:
        generators:
          - git:
              repoURL: https://gitlab.example/myapp.git
              revision: develop
              directories: [{path: k8s/envs/*}]
          - clusters:
              selector: {matchLabels: {example.com/tier: nonprod}}
  template:
    metadata: {name: 'myapp-{{.path.basename}}-{{.name}}'}
    spec:
      project: infra
      source: {repoURL: ..., targetRevision: develop, path: '{{.path.path}}'}
      destination: {server: '{{.server}}', namespace: 'myapp-{{.path.basename}}'}
      syncPolicy: {automated: {prune: true, selfHeal: true}}
```

The `clusters` generator reads Argo's registered-cluster Secrets — no extra inventory to maintain.

**Multi-source app — chart from OCI, values from git:**

```yaml
spec:
  sources:
    - repoURL: oci://registry.example.local/charts
      chart: platform
      targetRevision: 1.42.0
      helm:
        valueFiles: ['$values/k8s/envs/prod/values.yaml']
    - repoURL: https://gitlab.example/myapp.git
      targetRevision: develop
      ref: values          # ref-only source, contributes no manifests
```

**CLI worth knowing:**

```bash
argocd app diff myapp --local k8s/helm/platform   # local render vs live — best pre-merge check
argocd app sync myapp --prune --dry-run
argocd app wait myapp --health --timeout 600   # what CI should block on
argocd app set myapp --helm-set image.tag=1.2.3   # writes to the Application, NOT git. Sparingly
argocd app history myapp && argocd app rollback myapp 42
```

#### Flux in practice

```bash
flux bootstrap gitlab --owner=org/team --repository=myapp \
  --branch=develop --path=clusters/prod --personal=false
```

`bootstrap` commits Flux's own manifests into the repo and installs them — Flux then manages Flux.

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata: {name: myapp, namespace: flux-system}
spec:
  interval: 1m
  url: https://gitlab.example/myapp.git
  ref: {branch: develop}
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata: {name: apps, namespace: flux-system}
spec:
  interval: 10m
  path: ./k8s/envs/prod
  prune: true
  sourceRef: {kind: GitRepository, name: myapp}
  dependsOn: [{name: infra-controllers}]     # the ordering primitive
  healthChecks: [{apiVersion: apps/v1, kind: Deployment, name: myapp-api, namespace: myapp}]
```

`HelmRelease` (`helm.toolkit.fluxcd.io/v2`, Flux ≥ 2.3) gives a real Helm release with `install.remediation`, `upgrade.remediation.strategy: rollback`, and `driftDetection.mode: enabled` — the analogue of `selfHeal`. `OCIRepository` accepts a digest, the one thing Argo's Application source cannot pin.

Image automation: `ImageRepository` → `ImagePolicy` → `ImageUpdateAutomation` (commits the new tag back to git).

```bash
flux reconcile kustomization apps --with-source
flux diff kustomization apps --path ./k8s/envs/prod
flux trace deployment/myapp-api        # which object came from which commit
```

#### Secrets under GitOps

| Option | Model | Airgap | Notes |
|---|---|---|---|
| **external-secrets (ESO)** | Operator pulls from a backend into a `Secret` | **Yes, with OpenBao/Vault in-perimeter.** With the `gcpsm` provider it is **untranslatable** | Git holds only a reference. `ClusterSecretStore` + `ClusterExternalSecret` cover namespaces that don't exist yet |
| sops + age | Encrypted values in git, decrypted at apply | Yes, fully offline | Rotation = rewrite every file. Flux decrypts natively; Argo needs a plugin |
| sealed-secrets | Controller-held keypair, encrypted CRs in git | Yes | Cluster-bound ciphertext: rebuild the cluster, lose the key, lose everything |

**Recommendation: external-secrets with OpenBao.** It is the only one whose source of truth is a real secrets manager with leases, audit and rotation.

**The airgap caveat, as a category:** ESO's *provider* is the divergence point, not ESO. Keep the `ExternalSecret` objects identical across both worlds and let only the store differ — that is what keeps the self-hosted path tested rather than theoretical.

#### Promotion between environments

| Pattern | Shape | Verdict |
|---|---|---|
| Branch-per-env | `dev`/`staging`/`main`, promote by merge | Rejected. Long-lived branches drift, cherry-picks accumulate, and "what is in prod" becomes git archaeology |
| **Directory-per-env, one branch** | `k8s/envs/{dev,staging,prod}/`, same commit | **Recommended.** One HEAD, a promotion is a one-line diff, reviewable in isolation |

Image promotion, two mechanisms:

- **CI writes the digest back** (a commit to `envs/prod/images.yaml`). Auditable, works offline, and the digest — not the tag — is what moves.
- **Image automation controller** (Flux) or Argo Image Updater. Less ceremony, but it **polls a registry on an interval**. Inside a perimeter that registry only changes when a human walks in with a disk, so the automation buys you nothing. Use CI-writes-digest there and keep the same file format in the cloud.

#### Drift, and when to turn selfHeal off

Turn `selfHeal: false` (or `prune: false`) for:

- **CRDs** — pruning a CRD garbage-collects every CR of that kind, cluster-wide.
- **PVCs** — a pruned PVC is data loss with a `Delete` reclaim policy, and PVCs only grow; a smaller size in git plus selfHeal gets you a wedged sync, not a shrink.
- **Objects an operator mutates** — CNPG rewrites its `Cluster` status, HPAs write `replicas`, cainjector writes `caBundle`, Autopilot writes resources. Either `ignoreDifferences` the field (with `RespectIgnoreDifferences=true`) or drop selfHeal for that Application.
- **Quorum StatefulSets during an incident.** An operator is mid-recovery, Argo reverts their change, and you lose the third member. Set the Application to manual sync for the duration, deliberately, and record it.

`allowEmpty: false` is the cheap seatbelt: a bad render producing zero manifests will not delete the namespace's contents.

---

### Chapter B — Infra vs app: splitting the repos and the pipeline

#### The split that works

| Repo | Contains | Changes when |
|---|---|---|
| **infra** | Terraform: VPC, GKE cluster, DNS, IAM, static IPs, state backend | Rarely. Quarterly |
| **platform** | Cluster add-ons and GitOps config: Argo/Flux install, AppProject, Applications, operator pins, StorageClasses, gateways, policies | Weekly |
| **apps** | Application charts and code | Every merge |

**Boundary rule: if it must exist before the cluster can run a workload, it is platform. If it must exist before the cluster exists, it is infra.**

These can be directories rather than repos. **The boundary is what matters; the repo count is a delivery detail.** A monorepo keeps a cross-cutting change in one MR; separate repos give independent blast radii and RBAC. With three tiers and one team, one repo with enforced CODEOWNERS on the infra directory is the better trade.

#### Terraform for a GKE cluster

**Module boundary:** one module = one cluster and *its* front door — cluster, Workload Identity binding, certificate, cert map, static IP, DNS records. Instantiated once per entry in a `gke_clusters` map so each environment is identical and independent, sharing only the VPC and a secret.

```hcl
resource "google_container_cluster" "autopilot" {
  name                = var.name
  location            = var.region        # regional, not zonal — one-way door
  enable_autopilot    = true              # one-way door
  deletion_protection = var.deletion_protection
  network             = var.network_self_link
  ip_allocation_policy {}                 # VPC-native
}
```

**Remote state:** never local. One state file per environment. State is the only thing that cannot be rebuilt from git.

**What should NOT be in Terraform:** anything that changes per deploy. Image tags, replica counts, app config, secret *values*, ConfigMaps. If it changes more often than the cluster, it belongs in the GitOps repo.

**The classic mistake: managing Kubernetes objects with the Terraform `kubernetes` provider.** Three reasons it goes wrong:

1. **Provider config depends on a resource in the same apply.** The kubeconfig comes from the cluster Terraform is creating; `terraform plan` on a not-yet-created cluster fails at provider init. You cannot cleanly `destroy`.
2. **Terraform's state is a poor model for Kubernetes.** Server-side defaulting and mutating webhooks mean every plan shows drift for fields Terraform never set — Autopilot's Warden alone would make every Deployment perpetually dirty.
3. **Two reconcilers, one object.** Terraform applies on merge; Argo applies continuously. They will overwrite each other.

**Instead:** Terraform creates the cluster and exactly **one** in-cluster thing — secret-zero. Everything else is Argo's.

Two Terraform-on-Autopilot traps: `node_config { spot = true }` passes `terraform validate` on an Autopilot cluster — validate is schema-only — and is not a working config; and a `master_authorized_networks_config` block with zero `cidr_blocks` is valid and admits **nobody**, so it must be conditionally rendered or it locks every operator out on apply.

#### Cluster bootstrap ordering

```
1. terraform apply
     └─ VPC · GKE cluster · Workload Identity pool · DNS · static IP · secret store entry
2. bootstrap secret-zero                        [imperative, ONCE, out of band]
     └─ repo credential (deploy token) + the ESO/WI binding
        Perimeter variant: unseal OpenBao and write the root policy instead
3. helm install argocd (upstream chart)         [imperative]
     └─ kubectl wait --for=condition=Established crd/applications.argoproj.io
4. helm install gitops-config (AppProject + Applications)   [imperative, last manual step]
5. Argo CD converges by wave:
     wave 0  cert-manager                     (everything with a webhook needs it)
     wave 1  external-secrets · gateway · CNPG · MinIO · ClickHouse · broker operators
     wave 2  observability operators · policy · backup
     wave 3  the app chart (CRs the wave-1 operators reconcile)
6. CI from here on: commit → Argo syncs. No further kubectl.
```

Steps 2–4 are the chicken-and-egg, and they are irreducible. **Make them one idempotent script, keep it in the repo, and run it from a workstation — not from CI with standing cluster-admin.** Gate step 5 on convergence: poll until every Application is Synced *and* Healthy, and on timeout **name the stuck ones**; `kubectl wait` only tells you something timed out, and "which one" is the whole question.

#### Cluster add-on baseline

| Add-on | What it's for |
|---|---|
| Gateway/ingress controller | North-south traffic, TLS termination, host/path routing |
| cert-manager | Issues and renews certificates; cainjector wires CA bundles into webhooks |
| external-secrets | Bridges the secret store into `Secret` objects so git holds references only |
| metrics-server | `kubectl top` and the resource metrics HPAs read |
| Observability stack (Prometheus, Grafana, Loki, Tempo, Alloy) | Metrics, logs, traces, degraded-state signals |
| Policy engine (Kyverno / Gatekeeper) | Admission-time enforcement: required labels, no `:latest`, digest pinning, baseline PSS |
| Velero | Cluster-object and PV backup — the only add-on whose absence you discover at the worst moment |

**On GKE specifically:** the `gateway-api-crds` addon owns the standard-channel Gateway API CRDs and a `ValidatingAdmissionPolicy` rejects any `*.gateway.networking.k8s.io` CRD not annotated `channel: standard`. A chart shipping the experimental set gets one CRD rejected, which fails the whole sync. Fix: `skipCrds: true` on the Application and apply the filtered CRDs out of band. **Cost, stated:** no `GRPCRoute`/`TCPRoute`/`UDPRoute`.

#### Environment parity

**Identical dev → prod (non-negotiable):**

- The chart and its template logic — same chart, different values
- Operator versions and CRD versions
- The GitOps path itself (run Argo on kind too, so a bug on one is a bug on both)
- Ingress topology, service names, DNS shape, auth flow
- Storage *class semantics* and access modes
- Replica count of anything quorum-based. **Three is three everywhere** — a one-replica "dev" broker tests nothing about partition behaviour

**Legitimately allowed to differ:** node capacity type (spot on non-prod, resolving the cluster from the live kubectl context so a stale context cannot put prod on preemptible capacity); resource *requests*; retention windows and log verbosity; data volume and PVC size; public hostname and certificate.

Each divergence gets a name, a reason, and a test that covers the other side.

#### One-way doors in cluster design

| Door | Why it's one-way |
|---|---|
| **Cluster name and region** | Immutable. Changing either destroys and recreates. Regional vs zonal is fixed at creation |
| **CIDR ranges** (pod / service / master) | Not editable after creation; a too-small pod CIDR caps node count permanently |
| **VPC-native vs routes-based** | Set once |
| **Autopilot vs Standard** | Cannot be converted. Autopilot means no DaemonSets-on-demand, no privileged workloads, and Warden mutates every pod spec |
| **Node OS image** | COS↔Ubuntu means new node pools and a drain |
| **CNI** | Replacing Dataplane V2 / Calico is a cluster rebuild |
| **Service mesh** | Adopting one rewrites the traffic, identity and observability model. Not adopting one is cheap to reverse; adopting one is not |
| **Single vs multi-cluster tenancy** | Namespace-per-tenant → cluster-per-tenant means redoing ingress, identity and GitOps topology |
| **PVC size and StorageClass** | **PVCs only grow.** Right-size at creation |

#### The pattern-import rule

Every well-architected reference you read assumes elastic capacity, managed services and persistent connectivity. Standard output for an imported pattern: **what it assumes → whether you share that assumption → the translated form, or "untranslatable, and here is why."** Cloud Storage for MinIO, Cloud SQL for CNPG, Pub/Sub for a broker, Secret Manager for OpenBao: each is a reasonable cloud choice and each is **untranslatable** to an air-gapped target. That is a category difference, not a preference — and adopting one makes the self-hosted path the untested one.

---

### Chapter C — Flux in depth

The recommendation lands on Argo CD, but it is close, and Flux is the right answer for a terminal-native platform team running many clusters with a lot of Helm. Here is enough to run it properly.

#### Bootstrap

```bash
flux check --pre
export GITHUB_TOKEN=ghp_...
flux bootstrap github --owner=example --repository=platform --branch=main \
  --path=clusters/dev-kind --personal=false \
  --components-extra=image-reflector-controller,image-automation-controller

# generic git (GitLab, Gitea, Bitbucket, Azure DevOps)
flux bootstrap git --url=ssh://git@git.internal/platform.git --branch=main \
  --path=clusters/prod --private-key-file=./id_ed25519
```

**Air-gapped, or no git access from the cluster — use OCI as the source of truth:**

```bash
flux install --registry=harbor.internal/fluxcd          # controllers from your registry
flux push artifact oci://harbor.internal/manifests/platform:$(git rev-parse --short HEAD) \
  --path=./ --source=$(git config --get remote.origin.url) \
  --revision=$(git branch --show-current)@sha1:$(git rev-parse HEAD)
flux create source oci platform --url=oci://harbor.internal/manifests/platform --tag-semver='*' --interval=5m
flux create kustomization platform --source=OCIRepository/platform --path=./clusters/prod --prune=true --interval=10m
```

That OCI path is Flux's real advantage in a perimeter: **`OCIRepository` accepts a digest**, which an Argo CD `Application` source cannot pin.

#### The objects

```yaml
# clusters/prod/infrastructure.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata: { name: infrastructure, namespace: flux-system }
spec:
  interval: 10m
  sourceRef: { kind: GitRepository, name: flux-system }
  path: ./infrastructure/overlays/prod
  prune: true                       # delete what was removed from git
  wait: true                        # health-check every applied object
  timeout: 5m
  decryption: { provider: sops, secretRef: { name: sops-age } }
  postBuild:
    substituteFrom:                 # ${CLUSTER_NAME} style variables from a ConfigMap
      - { kind: ConfigMap, name: cluster-vars }
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata: { name: apps, namespace: flux-system }
spec:
  interval: 10m
  dependsOn: [{ name: infrastructure }]     # CRDs and ingress exist before apps
  sourceRef: { kind: GitRepository, name: flux-system }
  path: ./apps/overlays/prod
  prune: true
  healthChecks:
    - { apiVersion: apps/v1, kind: Deployment, name: myapp, namespace: payments }
```

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata: { name: platform-charts, namespace: flux-system }
spec:
  type: oci
  url: oci://harbor.internal/charts
  interval: 30m
  secretRef: { name: harbor-pull }
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata: { name: myapp, namespace: payments }
spec:
  interval: 10m
  releaseName: myapp
  chart:
    spec:
      chart: myapp
      version: "1.4.x"                       # semver range → automatic patch upgrades
      sourceRef: { kind: HelmRepository, name: platform-charts, namespace: flux-system }
      verify: { provider: cosign }           # refuse unsigned charts
  install:
    crds: CreateReplace
    remediation: { retries: 3 }
  upgrade:
    crds: CreateReplace
    cleanupOnFail: true
    remediation: { retries: 3, remediateLastFailure: true }
  driftDetection: { mode: enabled }          # undo kubectl edits
  values:
    replicaCount: 4
  valuesFrom:
    - { kind: ConfigMap, name: myapp-values, valuesKey: values.yaml }
    - { kind: Secret, name: myapp-secrets, valuesKey: db-password, targetPath: db.password }
```

`crds: CreateReplace` is Flux's answer to the Helm CRD problem from chapter 06 — it *will* upgrade CRDs, which plain `helm upgrade` never does. That is a genuine advantage and also a genuine hazard: read the CRD upgrade hazards section before turning it on.

#### Image automation

```bash
flux create image repository myapp --image=harbor.internal/myapp --interval=1m --secret-ref=harbor-pull
flux create image policy myapp --image-ref=myapp --select-semver='>=1.0.0'
flux create image update platform --git-repo-ref=flux-system --git-repo-path=./apps/overlays/dev \
  --checkout-branch=main --push-branch=flux-image-updates \
  --author-name=flux --author-email=flux@example.com
```

Then mark the field to update, in the manifest itself:

```yaml
image: harbor.internal/myapp:1.4.2 # {"$imagepolicy": "flux-system:myapp"}
# or in a HelmRelease values block:
tag: 1.4.2 # {"$imagepolicy": "flux-system:myapp:tag"}
```

#### Operating Flux

```bash
flux get all -A                       # every source, kustomization, helmrelease + status
flux get kustomizations --watch
flux reconcile source git flux-system # pull now instead of waiting for the interval
flux reconcile kustomization apps --with-source
flux suspend kustomization apps       # freeze during an incident
flux resume  kustomization apps
flux diff kustomization apps --path ./apps/overlays/prod   # local dry-run against the cluster
flux logs --level=error -A --since=10m
flux trace deployment myapp -n payments      # which Kustomization/HelmRelease owns this object
flux events --for HelmRelease/myapp -n payments
flux stats                            # object counts and reconcile durations
```

`flux trace` answers the question that costs the most time in any GitOps cluster: **"what put this here?"**

#### SOPS secrets in git

```bash
age-keygen -o age.key                                          # public key goes in .sops.yaml
kubectl -n flux-system create secret generic sops-age --from-file=age.agekey=age.key
sops --encrypt --in-place apps/overlays/prod/myapp/secret.yaml # encrypted_regex: ^(data|stringData)$
```

The Kustomization's `decryption` block decrypts at apply time; plaintext never leaves the controller. This is the one place SOPS beats External Secrets: it works with **no secret manager at all**, which matters in a perimeter that has none.

> **Gotcha — stuck HelmRelease.** The chart is usually in a failed Helm state; `helm history myapp -n payments` shows `pending-upgrade`. Fix: `flux suspend hr myapp -n payments`, then `helm rollback myapp N -n payments` (or `helm uninstall --keep-history` for a clean reinstall), then `flux resume hr myapp -n payments`. Prevent it with the `upgrade.remediation` block above. If a Kustomization reports "dependency not ready", check its `dependsOn` target first — **the error is always upstream of where it is reported.**

#### Flux or Argo CD — the short version

| | Flux | Argo CD |
|---|---|---|
| Model | Kubernetes objects and a CLI; composes with kubectl | A product: API server, UI, SSO, RBAC, projects |
| Helm | Real `helm upgrade` — hooks, tests, history, rollback all work | `helm template` then apply; hooks remapped to Argo hooks, no Helm release history |
| Multi-cluster | One Flux per cluster, pointed at its own path | Hub-and-spoke from one instance, or per-cluster |
| Image automation | Built in | Argo CD Image Updater (separate project) |
| Secrets in git | SOPS native | Plugins (argocd-vault-plugin) or ESO |
| Digest pinning of sources | `OCIRepository` accepts a digest | `targetRevision` is a tag only |
| Drift visibility | `flux diff`, `driftDetection`, events | Diff view in the UI, OutOfSync state |
| **Pick when** | Platform team lives in the terminal, many clusters, Helm-heavy | Developers self-serve through a UI; SSO and audit requirements; app-centric |


---


<a id="09-across-the-air-gap"></a>

## 09 · Across the air gap

An air gap is not a firewall rule. It is a physical discontinuity, and the only thing that crosses it is a file you carried. Everything here follows from one rule: **if it is not in the bundle, it does not exist on the other side** — and you find out which things you forgot at 02:00, on site, with no way to fetch them.

This is a pipeline. Each stage produces an artifact the next consumes. Run it end to end in a lab that is genuinely disconnected before you run it for a customer.

#### Stage 1 — Know what you need

The image list is the hard part of air gap. Everything else is logistics.

The naive way, which you will see in every blog post:

```bash
helm template platform ./platform -f values.yaml | grep 'image:'
```

This is wrong in a way that passes a smoke test and fails in production. What it misses:

| Source of image | Why `grep image:` misses it | How to catch it |
|---|---|---|
| CR fields not named `image` | CNPG uses `spec.imageName` | Walk all keys, not one |
| Operator-injected sidecars | Never appears in any rendered template | Live-cluster ground truth |
| Operator defaults compiled into the binary | CNPG's default PostgreSQL image; Envoy Gateway's `envoy` and `ratelimit` images | Read the operator's values/docs; confirm live |
| CRDs | `helm template` omits them unless asked | `--include-crds` |
| Conditional sub-charts | Only the licensed permutation renders | Render every permutation |
| Helm hooks / Jobs | Render, but easy to miss in an eyeballed grep | Machine-parse, never eyeball |
| CronJobs that have not fired | Not in `get pods` | Parse the workload spec too |

Do it with `yq` over every key, at every depth:

```bash
helm template platform ./platform -f values.yaml --include-crds \
     --kube-version "$(kubectl version -o json | jq -r .serverVersion.gitVersion)" \
  | yq -N '.. | select(has("image")) | .image, .. | select(has("imageName")) | .imageName' \
  | grep -v '^null$' | sort -u > images.declared.txt
```

`..` recurses, so this catches `containers`, `initContainers`, `ephemeralContainers`, and arbitrary CR fields in one pass. Add any other field name you discover; the set is open-ended, which is precisely why the next step is mandatory.

**Ground truth is a live reference cluster, not a template.** Stand the product up connected, exercise every feature the customer licensed (upload a file, run a migration, trigger the backup CronJob manually), then ask the nodes what they actually pulled:

```bash
# Every image any pod is currently using
kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{range .spec.initContainers[*]}{.image}{"\n"}{end}{end}' | sort -u

# Stronger: every image the node has in its content store, including
# ones from pods that have since been deleted.
kubectl get node -o json | jq -crM '.items[].status.images[].names[1]' | sort -u
```

That second command is the only honest answer, because it includes the image an operator created a pod from and then garbage-collected.

`comm -13 images.declared.txt images.observed.txt` is your gap list. Every line in it is a defect in the chart, an operator that pulls at runtime, or both. Fix the chart where you can; declare it in the bundle manifest where you cannot.

On OpenShift, `oc-mirror` does this discovery for operator catalogues, with an explicit `additionalImages:` block for everything the catalogue does not know about. If your target is OpenShift, use `oc-mirror` for the operator half and this pipeline for the other half.

#### Stage 2 — Pin everything to digests

Do this **before** export, not after.

A tag is a mutable pointer in a registry you are about to lose access to. `latest`, `prod`, `8.19.0` — all of them can and will move upstream between the day you build the bundle and the day someone asks "what version is actually running?" Once the bundle crosses the gap, a tag carries no evidence of what it resolved to.

```bash
while read -r ref; do
  digest="$(crane digest "$ref")"        # or: skopeo inspect --format '{{.Digest}}' "docker://$ref"
  printf '%s@%s\n' "${ref%%:*}" "$digest"
done < images.observed.txt > images.txt
```

Rules:

- Third-party images **MUST** be pinned by digest in the bundle manifest.
- First-party images **MUST** also be pinned by digest in the manifest, even though the chart addresses them by a floating tag. The chart uses the tag; the manifest records the digest. **The manifest is the audit record.**
- Pin the tool versions used to *build* the bundle too, and record them. "Which skopeo made this" is a question you will be asked.

#### Stage 3 — Pull and package the images

| Tool | Format | Multi-arch | Preserves digest | Verdict |
|---|---|---|---|---|
| `docker save` | Docker archive | No — flattens to one platform, silently | No, rewrites manifests | Only for loading into a local dev VM |
| `crane pull` | OCI / tarball | Index via `crane index`/`copy` | Yes | Fine; fewer knobs |
| `skopeo copy` | `oci-archive:`, `dir:`, `docker-archive:` | `--all` / `--multi-arch` | Yes, with `--preserve-digests` | **Use this** |

**Recommendation: `skopeo copy` into a single OCI layout directory**, then tar the directory once.

Why: skopeo is a daemonless single binary, speaks OCI layout natively so layers dedupe across images, preserves the manifest digest end to end, and has `--retry-times` for the flaky pull you *will* hit part-way through a 40 GB export. `docker save` requires a daemon, rewrites manifests, and — the disqualifying one — quietly discards everything but the host platform from a multi-arch index.

```bash
mkdir -p bundle/images
while read -r ref; do
  name="$(printf '%s' "$ref" | tr '/:@' '___')"
  skopeo copy \
      --retry-times 5 \
      --preserve-digests \
      --override-os linux --override-arch amd64 \
      "docker://$ref" \
      "oci:bundle/images:${name}"
done < images.txt

tar -C bundle -cf bundle/images.tar images/
```

**Multi-arch:** `--all` copies the whole index, every platform. You almost never want that — the target's architecture is in the deployment contract, and copying arm64 variants you will never run can double the bundle. `--all` only when the customer genuinely runs mixed nodes; if they do, **say so in the bundle README**, because a single-arch bundle on a mixed cluster produces a scheduling-dependent `ImagePullBackOff` that looks random.

**Non-image OCI artifacts** — Helm charts in an OCI registry, SBOMs, signatures, policy bundles — use `oras copy` into the same layout.

#### Stage 4 — Package the charts

The chart must be self-contained. It cannot resolve a single dependency on the other side.

```bash
helm dependency update ./platform
helm dependency build ./platform        # materialises charts/ from Chart.lock
helm package ./platform --destination bundle/charts/
```

Two traps.

**`helm dep update` does not recurse into `file://` subcharts.** Build the leaves first or you package an empty `charts/`. Encode it as a Make dependency on every nested `Chart.lock`:

```make
SUBCHART_LOCKS := $(patsubst %/Chart.yaml,%/Chart.lock,$(wildcard charts/*/Chart.yaml))
Chart.lock: Chart.yaml $(SUBCHART_LOCKS)
	@helm dependency update
```

**A chart referencing an OCI dependency it cannot reach.** On the far side that URL is unreachable. Two fixes, in preference order:

1. **Vendor it.** `helm dependency build` writes the dependency tarball into `charts/`. Ship the packaged `.tgz` and Helm never resolves anything. This is the right answer.
2. **Mirror it.** Push the dependency to the internal OCI registry and rewrite `repository:`. Only if the customer needs to re-run `helm dep update` themselves, which they should not.

Do not ship an unpackaged chart directory and hope. `helm package` output is the deliverable; the source tree is not.

> `oci://` chart repositories require Helm 3.8+. `helm push` handles charts only, not arbitrary artifacts.

#### Stage 5 — The bundle

```
platform-2.7.0-airgap/
├── README.md                 # install + rollback, for someone who has never seen this
├── VERSION                   # product version, build date, git SHA, tool versions
├── MANIFEST.sha256           # checksums of every file below
├── MANIFEST.sha256.sig       # detached signature over MANIFEST.sha256
├── images.txt                # digest-pinned image list, the contract
├── images.tar                # OCI layout, all images
├── charts/
│   ├── platform-operators-2.7.0.tgz
│   └── platform-2.7.0.tgz
├── values/
│   ├── values-airgap.yaml    # registry rewrite, pull policy, storage class
│   └── values-<customer>.yaml
└── bin/
    ├── install.sh            # idempotent, re-runnable, verifies before acting
    └── load-images.sh
```

```bash
cd platform-2.7.0-airgap
find . -type f ! -name 'MANIFEST.sha256*' -print0 \
  | sort -z | xargs -0 sha256sum > MANIFEST.sha256
```

`sort -z` matters: an unsorted manifest diffs noisily between builds and you lose the ability to compare bundle N to N-1.

**Sign it.** Sign the manifest, not each file — one signature covers everything transitively. Use a **key pair, not keyless/OIDC signing**: keyless verification requires reaching a certificate transparency log, which is exactly what you do not have.

```bash
cosign sign-blob --key cosign.key --output-signature MANIFEST.sha256.sig MANIFEST.sha256
# far side:
cosign verify-blob --key cosign.pub --signature MANIFEST.sha256.sig MANIFEST.sha256
```

The public key must already be on the far side, delivered by a **different route** than the bundle. A signature shipped alongside the thing it signs, verified with a key from the same box, proves nothing.

#### Stage 6 — Transfer

You get one shot per transfer window. Sometimes one per week. Sometimes one per quarter. Design for that.

```bash
split -b 4000M -d platform-2.7.0-airgap.tar platform-2.7.0-airgap.tar.part-
sha256sum platform-2.7.0-airgap.tar.part-* > PARTS.sha256

# far side
sha256sum -c PARTS.sha256 || exit 1
cat platform-2.7.0-airgap.tar.part-* > platform-2.7.0-airgap.tar
```

- Split below the **filesystem limit** of the transfer medium, not its capacity. FAT32 caps a single file at 4 GiB; exFAT does not. Confirm the medium's filesystem before you leave.
- Verify checksums **on arrival**, before anything else. A truncated final part produces a tar that extracts most of the way and then fails on the one image nobody notices.
- Every script in `bin/` **MUST** be idempotent. Re-running `load-images.sh` after a partial failure must resume, not corrupt. Skopeo copying an image that is already present is a no-op; lean on that instead of tracking state.
- Scripts **MUST** fail loudly on a missing input. Never `|| true`, never a `default ""` that lets the install proceed half-populated.

#### Stage 7 — Load on the other side

**Registry choice for air gap: Zot.** Single static binary, no database, no external dependencies, OCI-conformant, CNCF-hosted. Harbor is the better registry in a connected environment and the worse one here: it needs PostgreSQL and Redis, and its scanning path expects to refresh a vulnerability database from the internet — a feature that degrades into a permanent error banner offline, which trains operators to ignore error banners. Plain `registry:2` is acceptable and dependency-free but has no auth story beyond htpasswd and no UI.

```bash
REG=registry.internal.example:5000
skopeo login "$REG"

tar -xf images.tar
while read -r ref; do
  name="$(printf '%s' "$ref" | tr '/:@' '___')"
  repo="${ref#*/}"; repo="${repo%%@*}"
  skopeo copy --retry-times 5 --preserve-digests \
      "oci:images:${name}" \
      "docker://${REG}/${repo}:${TAG}"
done < images.txt
```

`--dest-tls-verify=false` exists and works against a self-signed registry. Use it only in a lab. In production put the internal CA in the trust store on the nodes and the workstation — the kubelet needs to trust that registry anyway, and `--dest-tls-verify=false` on the copy does nothing for the kubelet.

**Retagging is the real problem.** The images now live at `registry.internal.example:5000/...`, and every reference in the chart still points upstream. Four ways to fix it, ranked:

| Approach | Digest preserved | Chart untouched | Failure mode |
|---|---|---|---|
| **Node-level mirror** (`hosts.toml` for containerd, `registries.conf` for CRI-O, `ImageDigestMirrorSet` on OpenShift) | Yes | Yes | Needs node config access; applies cluster-wide |
| Chart `global.registry` | No, tag-addressed | Yes for your charts | Every third-party sub-chart names the key differently |
| Values overlay generated from `images.txt` | No | Yes | Must be regenerated per bundle; drifts silently |
| Kyverno `mutate` at admission | Depends on policy | Yes | Invisible; the webhook's own image must already be present — chicken and egg |

**Node-level mirroring is least bad**, and the only one that preserves the digest you shipped. Per-chart registry overrides are a last resort: no two charts agree on the key name (`global.images.envoyGateway.pullPolicy`, `image.pullPolicy`, `webhook.image.pullPolicy`, …), and you end up aliasing a YAML anchor into five differently-named keys.

Kyverno mutation is last because it makes `kubectl get deploy -o yaml` disagree with what is running. At 02:00 with no internet, **the manifest lying to you is the worst possible property.**

#### Stage 8 — Install

```bash
helm registry login "$REG"
helm push charts/platform-operators-2.7.0.tgz "oci://${REG}/charts"
helm push charts/platform-2.7.0.tgz            "oci://${REG}/charts"

# Operators first. They must be Ready and serving webhooks before any CR exists.
helm upgrade --install platform-operators "oci://${REG}/charts/platform-operators" \
    --version 2.7.0 -n platform-operators --create-namespace --wait --timeout 20m

helm upgrade --install platform "oci://${REG}/charts/platform" \
    --version 2.7.0 -n platform --create-namespace \
    -f values/values-airgap.yaml -f values/values-customer.yaml --timeout 20m
```

The two-release ordering is not stylistic. Helm applies everything in one release in parallel once CRDs are in place; it cannot wait for an operator pod to become Ready before creating the custom resources that depend on its admission webhook. **Splitting the install is what makes that wait happen.**

**CRDs on upgrade.** Helm does not upgrade CRDs on `helm upgrade`, in any Helm 3 version. If bundle N bumps a CRD, `kubectl apply --server-side` the CRDs before the `helm upgrade` and say so in the README with the exact command. This bites every air-gapped upgrade because nobody is watching a CI job to catch it.

Verify, in this order:

```bash
# 1. What you expect vs what you got
helm template platform "oci://${REG}/charts/platform" --version 2.7.0 \
    -f values/values-airgap.yaml -f values/values-customer.yaml > expected.yaml
helm get manifest -n platform platform > actual.yaml
diff -u expected.yaml actual.yaml

# 2. Nothing unhealthy
kubectl get pods -A | grep -Ev 'Running|Completed'

# 3. Every running image resolves inside the perimeter — this MUST be empty
kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' \
  | sort -u | grep -v "^${REG}/"
```

**Proving nothing reaches outward.** Not by reading YAML. Empirically:

- **Default-deny NetworkPolicy** in the namespace, with explicit egress allows for DNS and the internal registry only. A dev environment MUST enforce what production enforces — use a CNI that actually implements NetworkPolicy locally (Cilium on minikube/kind). **Flannel ignores policies**, so a policy that would have caught this failure silently passes in dev, which is worse than no policy because it teaches people the policy works.
- **Watch the drops while exercising the product.** `hubble observe --verdict DROPPED -f` on Cilium. Every dropped egress to an external address is a thing that would have phoned home.
- **Watch DNS.** An external name resolution attempt is the earliest, loudest signal of an air-gap violation, and it fires before the connection times out.
- **Watch for `ImagePullBackOff` for the full soak.** The image you missed is usually on a CronJob that fires weekly. Leave the lab cluster up for a full cycle.

#### Stage 9 — The things that bite you

| Symptom | Root cause | Fix |
|---|---|---|
| `ImagePullBackOff` on one pod, days in | One image missed — almost always operator-injected or a CronJob | Stage 1 ground truth on a node content store |
| Operator pulls at runtime | Operator's default image is compiled in | Pin it explicitly in operator values; add to `images.txt` |
| Pod ignores your registry override | Chart hardcodes the registry, or names the key differently | Node-level mirror; file an upstream issue |
| CRs rejected: `no matches for kind` | CRDs not shipped, or not upgraded | `--include-crds` when templating; `kubectl apply --server-side` before `helm upgrade` |
| Webhook `x509: certificate signed by unknown authority` | Webhook CA bundle references an external issuer, or cert-manager cannot reach ACME | Self-signed `ClusterIssuer` only; never ACME offline |
| Install hangs at a hook | A `pre-install` Job that curls something | Audit every hook; hooks MUST be network-free |
| Certificates invalid on a freshly-booted cluster | Time skew — air-gapped sites often have no NTP | Internal NTP source; check `timedatectl` on every node before installing |
| Product starts, then degrades after N days | Licence server phoning home | Do not adopt components with licence checks |

The last row is the operator-selection rule stated as a consequence: adopt an operator only when operational complexity is genuinely high, the project is mature and CNCF- or vendor-backed, **and it functions fully offline with no telemetry or licence checks**. Otherwise a StatefulSet, where direct control over the upgrade path beats the automation.

#### Stage 10 — Keeping it maintainable

**Ship deltas.** Bundle N-1 is already on the far side. Layers are content-addressed, so most of bundle N is already present.

```bash
comm -13 <(sort bundle-N-1/images.txt) <(sort bundle-N/images.txt) > images.delta.txt
```

Export only the delta into the OCI layout. Typical result on a patch release: a 40 GB bundle becomes 3 GB, and the transfer fits in a window it otherwise would not. Always ship the **full** `MANIFEST.sha256` and full `images.txt` even in a delta bundle — the manifest describes the intended end state, not the diff, and the install script verifies against the end state.

Keep every shipped `images.txt` in git, tagged by release. It is the only record of what a customer is running.

#### The airgap fitness checklist

A new service does not enter the bundle until it passes all of these. Not "should" — the bundle build script rejects it.

1. **No runtime downloads.** No `pip install`, `npm ci`, `apt-get`, model weights, GeoIP databases, or vulnerability feeds at container start.
2. **No external DNS.** Verified empirically under default-deny NetworkPolicy with DNS logging on, not by reading the code.
3. **Digest-pinned.** Every third-party image by digest. Build-tool versions as `ARG`s so Renovate can bump them.
4. **Image list declared.** The service's images are enumerable from `helm template`, or the undeclared ones are documented in the chart with the reason. An operator-injected image that is not written down is a defect.
5. **CRDs in-chart or shipped separately**, with the manual upgrade step documented in the bundle README.
6. **No licence check, no telemetry, no call-home.** Including "anonymous usage statistics" defaulted on.
7. **Probes check self, not dependencies.** In an air-gapped site a single backing-store hiccup restarting every dependent pod turns a five-minute blip into an outage nobody on site can debug.
8. **Migrations run as init containers** that complete before new application pods start, and the deploy stops if they fail.

Undocumented workarounds are defects. When you discover that an operator needs `--force-conflicts` on upgrade, you do not remember it — you write a "Known issues" entry and wire the fix into the install script, so the next person hits the fix instead of the problem.

#### Purpose-built alternatives to rolling your own

| Tool | Model | Good for |
|---|---|---|
| **Zarf** | Declarative `zarf.yaml` package — charts, manifests, images, files, actions → a single tarball. Ships its own registry and git server for the inside; `zarf init` then `zarf package deploy` | Whole-platform bundles for clusters that have *nothing*; regulated environments; repeatable deploys by operators who aren't Kubernetes experts |
| **Hauler** | `hauler store add image\|chart\|file`, `hauler store save` → `haul.tar.zst`; `hauler store serve registry` on the inside | Lightweight image/chart hauling; Rancher/RKE2 shops |
| **oras** | Push and pull any file as an OCI artifact | Shipping binaries, SBOMs and configs through the same registry pipeline |
| **Harbor replication** | Registry-to-registry replication rules, filtered by project/tag | Semi-connected sites with a scheduled window — **not** true sneakernet |

**When to use one instead of the pipeline above:** Zarf if the far side has literally nothing and the person deploying is not a Kubernetes engineer — it solves the "where does the registry itself come from" problem that costs you a day the first time. Roll your own when the bundle must fit an existing signing, provenance and manifest process, which is the usual case once compliance is involved.

#### Things that break *only* in the air gap

A checklist to run against every new component before it enters the bundle:

- Charts with `latest` or floating tags — the tag resolves to nothing inside.
- Init containers and webhook-injected sidecars missing from your image list. **Enumerate from a running reference cluster**, never from `helm template` alone.
- CRDs that fetch OpenAPI schemas at runtime.
- Operators that pull operand images from a hard-coded registry — look for a `--related-image` flag or `RELATED_IMAGE_*` environment variables.
- Let's Encrypt / ACME. Use an internal CA with cert-manager; there is no ACME offline.
- **NTP.** Air-gapped sites often have none, and time skew breaks certificate validation on a freshly-booted cluster in a way that looks like a TLS bug.
- DNS for your internal registry hostname *from inside pods*, which is a different resolver path than from the node.

> **Test it properly before you burn the media.** `docker network create --internal` gives you a kind cluster with no route out. Install the full bundle there and leave it running for a full CronJob cycle. Everything that would have phoned home fails visibly, in a lab, instead of silently, on site.


---


<a id="10-security-audit-you-can-run"></a>

## 10 · Security audit you can run

An audit is not a scan. A scan tells you what a tool noticed; an audit tells you what an attacker can reach. Work outward from identity, because in Kubernetes almost every escalation path starts as a token in a pod and ends as a node.

Run this top to bottom on an unfamiliar cluster. Every item has the command that proves it, not the doc that requires it. **A control you cannot demonstrate failing is not a control.**

#### 1. RBAC — who can become cluster-admin

```bash
# every binding to cluster-admin, with its subjects
kubectl get clusterrolebindings -o json | jq -r '
  .items[]
  | select(.roleRef.name == "cluster-admin")
  | "\(.metadata.name)\t" + ((.subjects // [])
      | map(.kind + ":" + ((.namespace // "-") + "/") + .name) | join(", "))'
```

Expect `cluster-admin/system:masters` and little else. Every ServiceAccount in that list is a finding until justified in writing.

Now the indirect grants — roles that don't say `cluster-admin` but are equivalent:

```bash
kubectl get clusterroles,roles -A -o json | jq -r '
  .items[] | . as $r | (.rules // [])[]
  | select(
      (.verbs[]?     | IN("*","escalate","bind","impersonate")) or
      (.resources[]? | IN("*","secrets","pods/exec","pods/attach",
                          "serviceaccounts/token","nodes/proxy",
                          "ephemeralcontainers"))
    )
  | "\($r.kind)\t\($r.metadata.namespace // "cluster")\t\($r.metadata.name)\t\(.verbs|join(","))\t\(.resources|join(","))"
' | sort -u | column -t
```

The escalation paths that matter, in the order an attacker tries them:

| Grant | Why it is cluster-admin in practice |
|---|---|
| `create pods` in any namespace | Mount any Secret in that namespace; `hostPath: /` or `hostPID` → node filesystem → kubelet credentials → every workload on the node |
| `get`/`list secrets` | Reads other ServiceAccount tokens, registry creds, DB passwords. Cluster-wide `list secrets` is game over |
| `create pods/exec`, `pods/attach` | Exec into an existing privileged pod, inherit its identity and mounts |
| `escalate` on roles | Grant yourself permissions you don't hold — the flag that exists specifically to bypass the escalation check |
| `bind` on rolebindings | Bind an existing powerful role to yourself |
| `impersonate` users/groups | `--as=system:admin`, or `--as-group=system:masters` |
| `create serviceaccounts/token` | Mint a token for a more privileged SA |
| `patch nodes`, `update nodes/status` | Label/taint manipulation → schedule onto a control-plane node |
| `create` on `certificatesigningrequests/approval` + signer | Issue yourself a client cert for any group |

Prove what a specific identity can do rather than reading rules:

```bash
kubectl auth can-i --list --as=system:serviceaccount:prod:api
kubectl auth can-i create pods --as=system:serviceaccount:prod:api -n prod
kubectl auth whoami                                  # 1.28+
```

```bash
kubectl krew install access-matrix rbac-tool who-can view-secret
kubectl access-matrix --sa prod:api -n prod          # verb × resource grid
kubectl rbac-tool policy-rules -e '^system:serviceaccount:prod'
kubectl rbac-tool viz --include-subjects              # graphviz of the whole mess
kubectl who-can get secrets -n prod
```

**Token automounting.** Every pod gets a projected SA token unless you say otherwise. Most workloads never call the API server — for them that token is pure downside: an SSRF or RCE turns straight into API access.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: {name: api, namespace: prod}
automountServiceAccountToken: false
---
# only the pods that genuinely call the API opt back in
spec:
  serviceAccountName: api
  automountServiceAccountToken: true
```

```bash
kubectl get pods -A -o json | jq -r '
  .items[] | select(.spec.automountServiceAccountToken != false)
  | "\(.metadata.namespace)/\(.metadata.name)\t\(.spec.serviceAccountName)"'
```

> Since **1.24** ServiceAccounts no longer get auto-generated long-lived token Secrets; pods get bound, audience-scoped, expiring projected tokens. Any `kubernetes.io/service-account-token` Secret you still find is legacy, non-expiring, and should be deleted.

#### 2. Pod Security Admission

PSA is built into the API server and **stable since 1.25** — it replaced PodSecurityPolicy, which is gone in 1.25+. Enforced by namespace label, three modes × three profiles:

```bash
kubectl label ns prod \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=v1.31 \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted
```

Pin `enforce-version` to a concrete version, not `latest` — otherwise a cluster upgrade can tighten the profile under you and reject pods on a Friday night.

`restricted` requires: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`, no `privileged`, no `hostNetwork`/`hostPID`/`hostIPC`, no `hostPath`, no host ports, and only a restricted volume-type allowlist.

```yaml
spec:
  securityContext:                 # pod level
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: app
      securityContext:             # container level — both are needed
        allowPrivilegeEscalation: false
        privileged: false
        readOnlyRootFilesystem: true
        runAsNonRoot: true
        capabilities: {drop: ["ALL"]}
        seccompProfile: {type: RuntimeDefault}
      volumeMounts:
        - {name: tmp, mountPath: /tmp}
  volumes:
    - {name: tmp, emptyDir: {}}
```

`readOnlyRootFilesystem` is **not** part of `restricted` — add it anyway; it is one of the cheapest runtime controls you will ever ship.

**Find violations before you enforce.** The dry-run label evaluates every existing pod in the namespace and returns warnings without changing anything:

```bash
kubectl label --dry-run=server --overwrite ns prod \
  pod-security.kubernetes.io/enforce=restricted

# cluster-wide sweep
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  echo "== $ns"
  kubectl label --dry-run=server --overwrite ns "$ns" \
    pod-security.kubernetes.io/enforce=restricted 2>&1 | grep -i warn
done
```

Roll out `warn` + `audit` first (visible, non-breaking), fix, then `enforce`.

#### 3. Network — default deny, both directions

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny-all, namespace: prod}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-dns-egress, namespace: prod}
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels: {kubernetes.io/metadata.name: kube-system}
          podSelector:
            matchLabels: {k8s-app: kube-dns}
      ports:
        - {protocol: UDP, port: 53}
        - {protocol: TCP, port: 53}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: api-to-postgres, namespace: prod}
spec:
  podSelector: {matchLabels: {app: api}}
  policyTypes: [Egress]
  egress:
    - to: [{podSelector: {matchLabels: {app: postgres}}}]
      ports: [{protocol: TCP, port: 5432}]
```

**The DNS exception is the one everyone forgets.** Apply default-deny egress without it and every pod hangs on name resolution with timeouts that look like anything but a network policy. `kubernetes.io/metadata.name` is auto-applied to namespaces since 1.21, so the selector above is safe; confirm the kube-dns pod label before trusting it.

**CNI support matters, and this is the trap.** NetworkPolicy objects are accepted by the API server whether or not anything implements them. **Flannel does not.** The policy applies cleanly, `kubectl get netpol` looks great, and nothing is enforced. Test it, every time:

```bash
kubectl get pods -n kube-system -l k8s-app --show-labels   # identify the CNI
kubectl run probe --rm -it --image=nicolaka/netshoot -n prod --restart=Never -- \
  sh -c 'nc -zv -w2 postgres 5432; nc -zv -w2 1.1.1.1 443; nslookup kubernetes.default'
```

Expected: 5432 open, 1.1.1.1 refused/timeout, DNS resolves. Anything else is a finding.

Limits to state in the report: NetworkPolicy is L3/L4 only — **no L7, no method/path rules, no egress by DNS name**, no TLS-SNI matching. Cilium's `CiliumNetworkPolicy` adds `toFQDNs`, L7 HTTP rules and identity-based policy; it is the step up when "allow egress to `registry.internal` only" becomes a requirement. Also: policies are namespaced and **additive** — there is no deny rule, only the absence of an allow, so one over-broad policy silently defeats a tight one.

#### 4. Secrets

They are base64, not encryption. Prove it in one line so nobody argues:

```bash
kubectl get secret db -n prod -o jsonpath='{.data.password}' | base64 -d; echo
kubectl view-secret db -n prod          # krew plugin, decodes all keys
```

**Encryption at rest** is an API-server flag plus a config file; without it, anyone with etcd access — or an etcd backup, or a snapshot on a NAS — reads every secret in plaintext.

```yaml
# EncryptionConfiguration, passed via --encryption-provider-config=/etc/k8s/enc.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources: [secrets, configmaps]
    providers:
      - kms:                 # KMS v2 — stable in 1.29+; prefer over static keys
          apiVersion: v2
          name: vault-kms
          endpoint: unix:///var/run/kmsplugin/socket.sock
      - aescbc:
          keys: [{name: key1, secret: <base64-32-bytes>}]
      - identity: {}         # must be LAST, or nothing is encrypted
```

`identity` first means plaintext. Verify:

```bash
kubectl -n kube-system get pod -l component=kube-apiserver -o yaml \
  | grep -E 'encryption-provider-config|anonymous-auth|audit-'
ETCDCTL_API=3 etcdctl get /registry/secrets/prod/db --cacert=... --cert=... --key=... | hexdump -C | head
```

Encrypted data is prefixed `k8s:enc:`. Plaintext will be obvious. Re-encrypting existing secrets after enabling requires rewriting them: `kubectl get secrets -A -o json | kubectl replace -f -`.

**External Secrets Operator is the real answer** — keep material in OpenBao/Vault/KMS, sync via `ExternalSecret`, let short-lived dynamic credentials expire on their own. The audit question then shifts to the right one: which identity can read which path, and is the runtime role narrower than the migration role.

Find secrets that aren't Secrets:

```bash
# plaintext-looking values in env vars
kubectl get pods -A -o json | jq -r '
  .items[] | .metadata as $m | .spec.containers[]
  | .env[]? | select(.value != null)
  | select(.name | test("(?i)pass|secret|token|key|cred"))
  | "\($m.namespace)/\($m.name)\t\(.name)"'
# configmaps carrying credentials
kubectl get cm -A -o json | jq -r '.items[] | .metadata as $m | .data // {}
  | to_entries[] | select(.key|test("(?i)pass|secret|token|key"))
  | "\($m.namespace)/\($m.name)\t\(.key)"'
# images and git history
trivy image --scanners secret ghcr.io/org/app:1.4.2@sha256:...
gitleaks detect --source . --redact
trufflehog git file://. --only-verified
```

**Secrets never travel as Docker build args.** `ARG`/`ENV` land in image history forever; use `RUN --mount=type=secret`. An `ARG TOKEN` sitting next to a secret mount is a defect, not a style choice.

#### 5. Supply chain and admission

Three rules, all enforceable at admission: pin by digest, verify the signature, allowlist the registry.

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: {name: verify-and-pin-images}
spec:
  validationFailureAction: Enforce     # see version note below
  background: false
  webhookTimeoutSeconds: 30
  rules:
    - name: verify-signature
      match:
        any: [{resources: {kinds: [Pod]}}]
      verifyImages:
        - imageReferences: ["registry.internal/team/*"]
          mutateDigest: true           # rewrites tag -> digest on admission
          verifyDigest: true
          required: true
          attestors:
            - entries:
                - keys:
                    publicKeys: |-
                      -----BEGIN PUBLIC KEY-----
                      MFkwEwYHKoZIzj0CAQYIKoZIzj...
                      -----END PUBLIC KEY-----
    - name: no-latest-tag
      match: {any: [{resources: {kinds: [Pod]}}]}
      validate:
        message: "Image tag ':latest' is not allowed; pin :version@sha256:..."
        pattern:
          spec:
            containers:
              - image: "!*:latest"
    - name: registry-allowlist
      match: {any: [{resources: {kinds: [Pod]}}]}
      validate:
        message: "Images must come from registry.internal"
        pattern:
          spec:
            containers:
              - image: "registry.internal/*"
    - name: require-limits
      match: {any: [{resources: {kinds: [Pod]}}]}
      validate:
        message: "CPU and memory requests and limits are required"
        pattern:
          spec:
            containers:
              - resources:
                  requests: {memory: "?*", cpu: "?*"}
                  limits:   {memory: "?*"}
```

> **Version-sensitive.** `validationFailureAction` at `spec` level moved to a per-rule `failureAction` in **Kyverno 1.13+** (the old field still works but is deprecated). Keyless/Rekor verification needs a reachable transparency log — **in an air-gapped cluster use a static public key**, and check current field names before trusting a snippet.

**Recommendation: Kyverno over Gatekeeper/OPA.** One reason — policies are Kubernetes YAML, so the people who write the manifests can read the policy, and Kyverno does image verification and mutation natively (`mutateDigest` turns a tag into a digest at admission, the single highest-value control here). Gatekeeper is the better choice only if you already run Rego elsewhere.

**Hunt the tags Renovate cannot see** — image references assembled from `ARG`s or Helm value concatenation are invisible to the pinner and will silently float.

#### 6. Scanning tools and where each belongs

| Tool | What it finds | Where it runs |
|---|---|---|
| `trivy` | Image CVEs, IaC misconfig, secrets, SBOM, live cluster | pre-commit, CI, cluster |
| `grype` | Image/SBOM CVEs (pairs with `syft`) | CI, second opinion |
| `kubescape` | NSA, CIS, MITRE ATT&CK frameworks; image CVEs | CI and in-cluster audit |
| `kube-bench` | CIS Kubernetes Benchmark on node/control-plane files | on the node, audit |
| `polaris` | Workload best practice (limits, probes, securityContext) | CI + dashboard |
| `kube-score` | Static manifest scoring, pre-apply | pre-commit, CI |
| `popeye` | Live-cluster sanity: dead resources, bad refs | audit |
| `kubeaudit` | Security-specific manifest/cluster audit | CI, audit |
| `kubent` | Deprecated/removed API versions before upgrade | pre-upgrade |
| `checkov` / `tfsec` | Terraform and IaC misconfiguration | pre-commit, CI |

```bash
# images: fail only on fixable high/critical
trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 \
  registry.internal/team/api:1.4.2@sha256:abc...
trivy config --severity HIGH,CRITICAL ./k8s        # manifests and charts
trivy k8s --report summary cluster                 # live cluster

kubescape scan framework nsa,cis-v1.10.0 --format sarif --output kubescape.sarif
kubescape scan control C-0016 --verbose            # allowPrivilegeEscalation

kube-bench run --targets master,node,etcd,policies
kubectl run kube-bench --rm -it --image=aquasec/kube-bench:latest \
  --overrides='{"spec":{"hostPID":true}}' --restart=Never -- node
```

#### Reading the results without drowning

The first `trivy image` run on any Debian-based image returns 400 findings and 30 criticals. If your gate fails on all of them, **the gate gets disabled within a week** — which is worse than no gate.

Triage in this order:

1. **Is it fixable?** `--ignore-unfixed`. A critical with no upstream patch is a backlog item and a base-image decision, not a build failure.
2. **Is the vulnerable code reachable?** A CVE in `libxml2` inside an image that never parses XML is not exploitable. Trivy tells you what's installed; only you know what's called.
3. **Is it reachable from a trust boundary?** A CVE behind three network hops with default-deny egress is not the same risk as one in the pod terminating browser TLS. **Rank by exposure, not by CVSS.**
4. **Has the severity been contextualized?** Distro maintainers frequently rate lower than NVD for good reasons. Prefer the distro's rating where it exists.

```bash
# fail the build only on fixable HIGH/CRITICAL
trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 \
  --ignorefile .trivyignore "$IMAGE"
# everything else: report, don't block
trivy image --severity MEDIUM,LOW --exit-code 0 --format sarif -o trivy.sarif "$IMAGE"
```

`.trivyignore` entries must carry an expiry date and a reason in a comment, and the file itself should be reviewed in the MR. **A permanent ignore is an accepted risk and needs an owner.**

#### 7. API server and control plane

```bash
kubectl -n kube-system get pod -l component=kube-apiserver -o yaml | grep -E -- '--(anonymous-auth|enable-admission-plugins|audit-log|audit-policy|encryption-provider|authorization-mode|service-account-lookup|tls-cipher)'
kubectl get --raw /metrics | head        # anonymous access here is a finding
kubectl get --raw '/readyz?verbose'
kubectl get --raw /livez --as=system:anonymous   # expect 403 if anonymous-auth is off
```

What you want: `--anonymous-auth=false`, `--authorization-mode=Node,RBAC`, admission plugins including `NodeRestriction`, `PodSecurity`, `ServiceAccount`, `ValidatingAdmissionPolicy`. *Version note: 1.32+ adds configurable anonymous endpoints — check the exact field against your release.*

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages: [RequestReceived]
rules:
  - level: None                                     # drop the noise first
    users: [system:kube-scheduler, system:kube-controller-manager]
  - level: None
    resources: [{group: "", resources: [events]}]
  - level: RequestResponse                          # the crown jewels
    resources:
      - {group: "", resources: [secrets, serviceaccounts/token]}
      - {group: rbac.authorization.k8s.io, resources: ["*"]}
  - level: Request
    verbs: [create, update, patch, delete]
    resources: [{group: "", resources: [pods, pods/exec, pods/portforward]}]
  - level: Metadata                                 # catch-all
```

Log secret *reads* at `Metadata`, not `RequestResponse`, if you are worried about the value landing in your log store — **the audit log is a log store, and log retention is not a security boundary.**

etcd: confirm it is not listening on a routable address, that `--client-cert-auth=true` and `--peer-client-cert-auth=true` are set, and that backups are encrypted. `ss -lntp | grep 2379` on the control-plane node; anything other than loopback/peer addresses is a critical finding.

#### 8. Runtime

Everything above is admission-time. Runtime detection (Falco with eBPF, or Tetragon) watches syscalls and answers the question admission cannot: what did the container do *after* it started. Tetragon additionally enforces; Falco alerts. Both need kernel access and a tuning budget — expect two weeks of false positives before the signal is usable.

The minimum three rules, whatever the tool:

1. **Exec or attach into a production pod** — alert every time, with the invoking user from the audit log, not just the pod name.
2. **A new pod with `privileged: true`, `hostPID`, or a `hostPath` mount of `/` or `/var/lib/kubelet`** — should be impossible after §2 and §5; alert if it happens anyway, because it means admission was bypassed.
3. **ServiceAccount token used from an unexpected source** — a token issued to `prod/api` presenting from outside the cluster, or from a different pod IP than it was bound to.

#### 9. The 15-minute audit

```bash
# 1. version, and what's about to break
kubectl version; kubent
# 2. cluster-admin bindings
kubectl get clusterrolebindings -o json | jq -r '.items[]|select(.roleRef.name=="cluster-admin")|.metadata.name + " <- " + ((.subjects//[])|map(.kind+":"+.name)|join(","))'
# 3. dangerous verbs (the jq from §1)
# 4. PSA coverage — namespaces with no enforce label at all
kubectl get ns -o json | jq -r '.items[]|select(.metadata.labels["pod-security.kubernetes.io/enforce"]==null)|.metadata.name'
# 5. privileged / host-namespace pods running right now
kubectl get pods -A -o json | jq -r '.items[]|select(any(.spec.containers[]; .securityContext.privileged==true) or .spec.hostNetwork==true or .spec.hostPID==true)|"\(.metadata.namespace)/\(.metadata.name)"'
# 6. namespaces with no NetworkPolicy
comm -23 <(kubectl get ns -o name|cut -d/ -f2|sort) <(kubectl get netpol -A -o json|jq -r '.items[].metadata.namespace'|sort -u)
# 7. does the CNI enforce? (netshoot probe from §3)
# 8. encryption at rest + anonymous auth + audit flags
kubectl -n kube-system get pod -l component=kube-apiserver -o yaml | grep -E -- '--(anonymous-auth|encryption-provider-config|audit-policy-file)'
# 9. unpinned / :latest images
kubectl get pods -A -o json | jq -r '.items[].spec.containers[].image' | sort -u | grep -v '@sha256:'
# 10. tokens automounted where unnecessary (jq from §1)
# 11. framework sweep
kubescape scan framework nsa --format json --output ks.json
# 12. node benchmark
kube-bench run --targets master,node,etcd,policies | grep -E '^\[FAIL\]'
```

**Findings template** — one row per finding, and no finding ships without a testable requirement and a named owner:

```markdown
### F-00N <short title>
Severity:      critical | high | medium | low
Component:     <namespace/workload or control-plane element>
Boundary:      <which trust boundary this crosses>
Evidence:      <command + trimmed output, file:line for manifests>
Impact:        <what an attacker gets, concretely>
Requirement:   <testable control, e.g. "PSA enforce=restricted on ns prod,
               verified by `kubectl label --dry-run=server` returning no warnings">
Enforced by:   <CI stage / admission policy / NetworkPolicy> | NOT ENFORCED
Owner:         <name>   Due: <date>
```

The last two lines are the chapter. **"Required" and "enforced" are different words**, and an audit that does not distinguish them has produced a document rather than a change.


---


<a id="11-when-it-breaks"></a>

## 11 · When it breaks

### Chapter A — When it breaks: decision trees

Every subsection is the same shape: **symptom → the small set of causes that actually occur → the command that discriminates between them → the fix.** Ordering is by base rate, not by elegance.

**The universal first three commands.** Run these before any hypothesis:

```bash
kubectl describe pod <pod> -n <ns> | sed -n '/Events:/,$p'   # events expire; read them first
kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -30
kubectl get pod <pod> -n <ns> -o yaml | yq '.status'         # conditions + containerStatuses
```

`.status.conditions` (PodScheduled, Initialized, ContainersReady, Ready) tells you *which stage* failed. That alone picks the subsection below.

#### Pod Pending

Pending means **no kubelet has accepted it**: the scheduler could not place it, a volume could not bind, or admission rejected it.

1. `kubectl describe pod` → the `FailedScheduling` event names the reason per node (`Insufficient cpu`, `node(s) had untolerated taint`, `didn't match Pod's node affinity/selector`, `node(s) had volume node affinity conflict`).
2. **Insufficient cpu/memory** — compare requests against *allocatable*, not capacity.
3. **Selector/affinity mismatch** — the label you require does not exist on any node.
4. **Taints** — control-plane and GPU nodes are tainted; you need a matching toleration.
5. **Arch/OS mismatch** — an `amd64` image on `arm64` nodes fails at schedule time if `kubernetes.io/arch` is constrained, at pull time otherwise.
6. **PVC unbound** — no default StorageClass, or `volumeBindingMode: WaitForFirstConsumer` (the PVC is *supposed* to stay Pending until a pod schedules — expected, not broken), or a zonal volume in a zone with no schedulable node.
7. **Quota** — `exceeded quota` appears as a **ReplicaSet** event, not a pod event, because the pod was never created.

```bash
kubectl describe node <node> | sed -n '/Allocated resources/,$p'
kubectl get nodes -L kubernetes.io/arch,kubernetes.io/os,topology.kubernetes.io/zone
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
kubectl get pvc -n <ns>; kubectl get sc                     # exactly one SC should say (default)
kubectl describe pvc <pvc> -n <ns>                          # ProvisioningFailed / WaitForFirstConsumer
kubectl get resourcequota -n <ns> -o wide
kubectl describe replicaset <rs> -n <ns>                     # quota + PSA rejections land here
kubectl resource-capacity --pods --util -n <ns>              # krew: requests vs limits vs real usage
```

**Fix:** right-size requests (the usual real cause), add the toleration, label the node, set a default StorageClass, or raise quota. Do not "fix" WaitForFirstConsumer.

#### ImagePullBackOff / ErrImagePull

The kubelet asked the runtime for an image and was refused. **The event text discriminates completely — read it verbatim.**

| Event text | Cause | Fix |
|---|---|---|
| `manifest unknown` / `not found` | wrong repo or tag | fix the tag; `crane ls <repo>` |
| `unauthorized` / `authentication required` | private registry, no/wrong `imagePullSecrets` | create a `dockerconfigjson` secret, attach to the pod **and** the ServiceAccount |
| `toomanyrequests` | Docker Hub rate limit | mirror/pull-through cache, authenticate |
| `dial tcp … i/o timeout`, `no such host` | airgap / DNS / proxy — image not in the local registry | preload with `crane copy`, verify the mirror in the runtime config |
| `no matching manifest for linux/arm64` | wrong architecture | multi-arch build or pin `nodeSelector` |

```bash
kubectl describe pod <pod> | grep -A5 -i 'failed to pull'
kubectl get secret <pull-secret> -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq '.auths|keys'
# the registry host in the secret must match the image prefix EXACTLY (index.docker.io != docker.io)
crane manifest <image> | jq '.manifests[].platform'      # confirm the arch is published
```

#### CrashLoopBackOff

The container started and exited repeatedly; the kubelet is backing off (10s → 20s → … → 5m). **CrashLoopBackOff is not a cause, it is a rate limiter.**

```bash
kubectl logs <pod> -c <container> --previous          # THE command — logs of the dead instance
kubectl get pod <pod> -o jsonpath='{range .status.containerStatuses[*]}{.name}{"\t"}{.lastState.terminated.exitCode}{"\t"}{.lastState.terminated.reason}{"\n"}{end}'
```

| Exit code | Meaning | Look at |
|---|---|---|
| 0 | clean exit, but restartPolicy=Always | a Job/one-shot process shipped as a Deployment |
| 1 / 2 | application error | `--previous` logs, first 20 lines |
| 126 | entrypoint found but not executable | file mode, shell shebang, wrong binary format |
| 127 | command not found | `command:` overriding entrypoint; distroless image with no shell |
| 128+n | killed by signal n | see below |
| 137 | SIGKILL — OOM, or a liveness kill that ignored SIGTERM | `lastState.terminated.reason: OOMKilled` |
| 143 | SIGTERM — something asked it to stop | liveness probe failure, eviction, rollout |
| 139 | SIGSEGV | native crash; get a core, check CPU features |

Causes in base-rate order: **missing config/secret** (`CreateContainerConfigError` on the way there), **a failing liveness probe restarting a perfectly healthy app** (exit 143/137 with clean logs and `Liveness probe failed` events), **wrong `command`/`args`**, **file permissions on a mounted volume** (set `securityContext.fsGroup`; ConfigMap mounts are always read-only), and **a dependency that isn't up** — which belongs in an init container, not in the app's crash loop.

Get a shell without fighting the restart loop:

```bash
kubectl debug <pod> -it --copy-to=<pod>-dbg --container=<c> -- sh   # same spec, different command
kubectl debug <pod> -it --copy-to=<pod>-dbg --set-image=<c>=busybox:1.36 -- sh
kubectl debug <pod> -it --image=nicolaka/netshoot --target=<c>      # ephemeral, shares PID ns
kubectl delete pod <pod>-dbg                                        # copies are NOT owned by the RS
```

#### OOMKilled

```bash
kubectl get pod <pod> -o jsonpath='{.status.containerStatuses[0].lastState.terminated}' | jq
kubectl describe pod <pod> | grep -E 'Reason|Exit Code|Limits|Requests'
kubectl top pod <pod> --containers          # instantaneous only; use working_set for trend
```

`reason: OOMKilled`, exit 137. The cgroup hit `resources.limits.memory` — **requests are irrelevant here; the limit is the kill line.** Two distinct shapes: a slow climb (leak, or an unbounded cache/queue — an unbounded buffer is a deferred outage) versus a spike at a specific request (batch size). Distinguish them on `container_memory_working_set_bytes` before touching the limit.

**The runtime-vs-container trap:** a JVM without `-XX:MaxRAMPercentage`, a Python worker whose `workers × per-worker RSS` exceeds the limit, a Go service with no `GOMEMLIMIT` — these are configured to exceed the container and will do so again at any limit. Set the heap/soft limit to ~70–80% of the container limit and leave headroom for the non-heap.

**Why raising the limit is sometimes wrong:** it converts a fast, contained, self-healing kill into a slow node-level memory-pressure eviction that takes *neighbouring* pods with it. Raise the limit only when you've shown the workload's true working set — otherwise fix the allocator.

#### Pod Running but not Ready (`1/2`, endpoints empty)

```bash
kubectl get pod <pod> -o jsonpath='{.status.conditions}' | jq
kubectl describe pod <pod> | grep -iE 'readiness|liveness|startup'
kubectl exec <pod> -c <c> -- curl -sv localhost:8080/readyz   # from inside, as the kubelet sees it
```

1. Readiness probe genuinely failing — the app says it isn't ready. Believe it; read its logs.
2. **Probe config wrong:** path typo, port name that doesn't resolve to a `containerPort` name, `scheme: HTTP` against a TLS listener, probe hitting `0.0.0.0` vs `127.0.0.1` binding.
3. `initialDelaySeconds` too short for a slow boot — do not inflate it; that's what `startupProbe` is for.
4. A dependency isn't up and readiness correctly reports it. That's the probe working. Fix the dependency.

#### Service has no endpoints

```bash
kubectl get endpointslices -n <ns> -l kubernetes.io/service-name=<svc> -o yaml
kubectl get svc <svc> -o jsonpath='{.spec.selector}'; echo
kubectl get pods -n <ns> -l <that-selector> -o wide       # returns nothing? found your bug
```

1. **Selector/label mismatch — the #1 cause.** The Service selector must match the pod *template* labels, not the Deployment's `metadata.labels`.
2. **Pods not Ready** — endpoints only include Ready pods.
3. **`port` vs `targetPort` vs `containerPort`** — `port` is the Service's own port; `targetPort` is the pod's; `containerPort` is documentation plus name resolution. The right `port` with the wrong `targetPort` gives connection-refused, not an empty endpoint list.
4. **Named port mismatch** — `targetPort: http` requires a container port literally `name: http`.

#### DNS not resolving

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=50      # SERVFAIL, upstream timeout, plugin errors
kubectl run -it --rm dns -n <ns> --image=busybox:1.28 --restart=Never -- \
  sh -c 'nslookup <svc>; nslookup <svc>.<ns>.svc.cluster.local; cat /etc/resolv.conf'
```

`ndots:5` means any name with fewer than 5 dots is tried against every search domain first: `svc` → 4–5 failed queries before the real one. **Use the FQDN with a trailing dot for external/high-QPS lookups**, or set `dnsConfig.options: [{name: ndots, value: "2"}]`. CoreDNS OOM/throttling shows up as intermittent timeouts under load. A default-deny NetworkPolicy without an egress rule for **UDP and TCP 53 to kube-system** breaks DNS for the whole namespace and looks like an application bug.

> `busybox:1.28` is pinned in that one-liner on purpose — later busybox tags have known `nslookup` regressions.

#### Ingress / Gateway 404 or 503

**404 = no rule matched. 503 = rule matched, backend has no healthy endpoints.** That split isolates the layer immediately.

```bash
kubectl get ingress <ing> -o yaml | yq '.spec'           # ingressClassName set? host? pathType?
kubectl -n ingress-nginx logs -l app.kubernetes.io/component=controller --tail=100 | grep <host>
kubectl get endpointslices -l kubernetes.io/service-name=<backend-svc>
kubectl run -it --rm curl --image=curlimages/curl --restart=Never -- \
  curl -sv http://<svc>.<ns>.svc.cluster.local:<port>/healthz    # bypass ingress
kubectl run -it --rm curl --image=curlimages/curl --restart=Never -- \
  curl -sv -H 'Host: app.example.com' http://ingress-nginx-controller.ingress-nginx/   # bypass the LB
```

Causes: missing `ingressClassName` (the controller ignores the object entirely, **silently**), wrong backend service name/port, `pathType: Exact` where you meant `Prefix`, a missing or mis-namespaced TLS secret (ingress TLS secrets must live in the **same namespace** as the Ingress), or annotations for a controller you aren't running.

#### Node NotReady / pressure

```bash
kubectl describe node <node> | sed -n '/Conditions:/,/Addresses:/p'
kubectl get nodes -o json | jq -r '.items[]|[.metadata.name,(.status.conditions[]|select(.status=="True")|.type)]|@tsv'
journalctl -u kubelet -n 200 --no-pager   # or: kubectl debug node/<node> -it --image=busybox → chroot /host
```

`Ready=Unknown` means the kubelet stopped heartbeating — pods get `NodeNotReady`-tainted and evicted after `tolerationSeconds` (default 300s). `DiskPressure` triggers image GC then pod eviction; `MemoryPressure` evicts BestEffort first; `PIDPressure` is usually a fork bomb or a zombie-leaking sidecar.

```bash
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --timeout=10m   # honours PDBs
kubectl uncordon <node>
```

If drain hangs, a PDB is (correctly) blocking it: `kubectl get pdb -A` and check `ALLOWED DISRUPTIONS: 0`.

#### Everything is slow / throttled

```promql
rate(container_cpu_cfs_throttled_periods_total[5m]) / rate(container_cpu_cfs_periods_total[5m])
```

Throttling above ~5% with CPU usage *well below* the limit is the signature of CFS quota: a multi-threaded runtime burns its 100 ms quota in 20 ms and then stalls for 80 ms. Latency collapses at p99 while dashboards show "low CPU usage" — **the single most misdiagnosed performance problem in Kubernetes.** Also check disk (`node_disk_io_time_seconds_total`, a PVC on a slow class) and neighbouring pods with no limits at all.

**Position: drop CPU limits, keep CPU requests, always keep memory limits.** CPU is compressible — contention degrades gracefully and requests already guarantee a floor via cgroup shares. A CPU limit buys nothing at low utilization and costs tail latency at high utilization. Memory is *not* compressible: without a limit, one leak takes the node. The one case for CPU limits is hostile multi-tenancy, or when you must certify deterministic capacity.

#### Terminating forever

```bash
kubectl get <res> <name> -o jsonpath='{.metadata.finalizers}'; echo
kubectl describe <res> <name> | grep -i -A5 finalizer
```

An object stuck Terminating is almost always **a finalizer whose controller is gone or failing**. Fix the controller if you can; removing a finalizer skips real cleanup and leaks cloud resources.

- **Pod:** `kubectl delete pod <p> --grace-period=0 --force` only if the node is confirmed gone — otherwise you get two copies of a StatefulSet pod.
- **PVC/PV:** `kubernetes.io/pvc-protection` clears when the last consuming pod is gone; a stuck PV needs `.spec.claimRef` cleared or the CSI driver fixed.
- **Namespace:** first find what actually remains, then finalize:

```bash
kubectl api-resources --verbs=list --namespaced -o name \
  | xargs -n1 kubectl get --show-kind --ignore-not-found -n <ns>
kubectl get apiservices | grep -v True        # an unavailable APIService blocks namespace deletion
kubectl get ns <ns> -o json | jq '.spec.finalizers=[]' \
  | kubectl replace --raw "/api/v1/namespaces/<ns>/finalize" -f -
```

> That last command is a **one-way door**: it abandons whatever the finalizer was going to clean up.

---

### Chapter B — Making workloads that don't page you

#### Probes done right

| | Asks | On failure | Runs |
|---|---|---|---|
| **startupProbe** | "has boot finished?" | kills the container | boot only; disables the other two until it passes |
| **livenessProbe** | "is this process wedged?" | restarts the container | for the container's whole life |
| **readinessProbe** | "should I get traffic *right now*?" | removes from Service endpoints | for the container's whole life |

**Liveness checks self. Readiness checks dependencies. Startup covers boot only.** That is the whole rule.

**The classic mistake:** a liveness probe that reaches the database. The database blips, every dependent pod fails liveness, every pod restarts simultaneously, cold caches hammer the recovering database, and one backing-service outage becomes a cluster-wide restart storm. **The liveness probe amplified the fault it was supposed to detect.**

**Dependency waits belong in an init container**, and they must be bounded. Fail fast beats hang: a pod blocking forever on a missing dependency emits no signal at all.

```yaml
initContainers:
  - name: wait-for-db
    image: postgres:16-alpine
    command: ["sh","-c","for i in $(seq 1 30); do pg_isready -h db -t 3 && exit 0; sleep 2; done; echo 'db unreachable after 60s' >&2; exit 1"]
containers:
  - name: app
    startupProbe:   { httpGet: {path: /healthz, port: http}, periodSeconds: 5,  failureThreshold: 60 } # 5 min budget
    livenessProbe:  { httpGet: {path: /healthz, port: http}, periodSeconds: 10, failureThreshold: 3, timeoutSeconds: 2 }
    readinessProbe: { httpGet: {path: /readyz,  port: http}, periodSeconds: 5,  failureThreshold: 2, timeoutSeconds: 2, successThreshold: 1 }
```

`startupProbe` exists so you can be **patient at boot and impatient afterwards** — a 5-minute JVM warmup no longer forces a 5-minute `initialDelaySeconds` on liveness, which would leave a wedged process unrestarted for five minutes. Keep `timeoutSeconds` below `periodSeconds`; liveness `successThreshold` must be 1.

#### Requests and limits

**Requests are a scheduling contract** (what the scheduler reserves, and the cgroup CPU-shares floor). **Limits are runtime enforcement** (CFS quota for CPU, the OOM kill line for memory). Different jobs; setting them from the same number by reflex is how you get Guaranteed pods you didn't want.

| QoS | Condition | Evicted |
|---|---|---|
| **Guaranteed** | every container sets limits == requests for *both* cpu and memory | last |
| **Burstable** | at least one request set, not Guaranteed | second — worst offender over its request goes first |
| **BestEffort** | no requests or limits anywhere | **first** |

**A BestEffort pod is a pod you have volunteered for deletion.**

Defensible default policy:

- CPU request = observed p50–p75 usage. **No CPU limit.**
- Memory request = observed p95 working set. Memory limit = request × 1.3–1.5.
- Set the runtime's own ceiling from the container limit: `GOMEMLIMIT`, `-XX:MaxRAMPercentage=75`.
- Anything latency-critical and pinned: go Guaranteed deliberately, and say why.
- Set a `LimitRange` per namespace so nothing lands BestEffort by accident.

#### PDBs, topology spread, anti-affinity

Three different jobs. **PDB protects during voluntary disruption. Spread and anti-affinity decide placement.** A PDB cannot save you from a node that simply dies.

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
spec:
  minAvailable: 2                 # 3-replica quorum: survives one drain, blocks the second
  selector: { matchLabels: {app: redpanda} }
  unhealthyPodEvictionPolicy: AlwaysAllow   # otherwise an already-broken pod deadlocks the drain
```

```yaml
topologySpreadConstraints:        # even placement — default posture for a stateless Deployment
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway     # DoNotSchedule turns a zone outage into Pending pods
    labelSelector: { matchLabels: {app: api} }
```

```yaml
affinity:                          # hard separation — quorum members that must not share a node
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - topologyKey: kubernetes.io/hostname
        labelSelector: { matchLabels: {app: clickhouse} }
```

Rule of thumb: `preferred`/`ScheduleAnyway` for stateless replicas; `required`/`DoNotSchedule` only when co-location is a correctness violation, because `required` converts capacity shortage into permanent Pending.

> `unhealthyPodEvictionPolicy` is beta from 1.27. On older clusters, drop that line.

#### Graceful shutdown

The race that causes "deploys drop requests": **on pod deletion the kubelet sends SIGTERM and the endpoint controller removes the endpoint — concurrently, not in order.** Every kube-proxy and ingress controller then needs time to observe the removal. If your app exits promptly on SIGTERM, in-flight and newly-routed requests hit a dead pod.

```yaml
terminationGracePeriodSeconds: 60          # must exceed preStop + longest in-flight request
lifecycle:
  preStop:
    exec: { command: ["sh","-c","sleep 10"] }   # do nothing for 10s while endpoint removal propagates
```

`preStop` runs **before** SIGTERM and its duration is deducted from the grace period. Order you want: readiness flips to failing → `preStop` sleep → SIGTERM → stop accepting new connections, drain in-flight, close upstreams → exit 0 before the grace period expires, or you get SIGKILL and exit 137.

#### Rolling updates

```yaml
spec:
  minReadySeconds: 15               # must stay Ready this long before it counts — kills flapping rollouts
  progressDeadlineSeconds: 600      # sets Progressing=False, reason ProgressDeadlineExceeded
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxSurge: 25%, maxUnavailable: 0 }   # 0 = never dip below desired capacity
```

`maxUnavailable: 0` + `maxSurge: 1` is the safe default when you have spare capacity; `maxUnavailable: 1, maxSurge: 0` is the only option when capacity is fixed. Gate CI on the condition, never on a duration:

```bash
kubectl rollout status deploy/<name> -n <ns> --timeout=10m || { kubectl rollout undo deploy/<name> -n <ns>; exit 1; }
kubectl wait --for=condition=Available deploy/<name> -n <ns> --timeout=5m
```

**A `sleep 30` in a deploy script is a bet on machine speed, and CI eventually loses it.** Note `rollout status` only fails on `progressDeadlineSeconds` — without it set, the command can wait forever.

#### HPA and its trap

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: api}
  minReplicas: 3
  maxReplicas: 20
  metrics:
    - type: Resource
      resource: {name: cpu, target: {type: Utilization, averageUtilization: 70}}
  behavior:
    scaleDown: {stabilizationWindowSeconds: 300}   # damp the flapping
```

`averageUtilization` is a percentage **of the CPU request** — an HPA on a container with no CPU request does nothing at all.

**The trap:** the Deployment template still carries `replicas: {{ .Values.replicaCount }}`. Every `helm upgrade` (and every Tilt/Argo sync) resets replicas to the chart value, the HPA scales back up, and your service oscillates on each deploy — usually mid-incident. **Remove `replicas` from any Deployment managed by an HPA**, or use Argo's `ignoreDifferences`. And never point an HPA at a workload whose replica count is a quorum property.

#### Production readiness checklist

A service ships when every line is true:

- [ ] **Probes** — startup (boot budget), liveness (self only, no dependencies), readiness (dependencies, and it flips on shutdown).
- [ ] **Resources** — CPU+memory requests from measured usage; memory limit set; CPU limit omitted deliberately; runtime heap capped below the container limit.
- [ ] **PDB** — `minAvailable` consistent with the replica count; drain tested.
- [ ] **Graceful shutdown** — SIGTERM handled, `preStop` sleep ≥ endpoint propagation, grace period ≥ longest request.
- [ ] **Logs to stdout/stderr**, structured JSON, one event per line, **secrets redacted before they leave the process**.
- [ ] **Metrics endpoint** — `/metrics`, scrape annotations or a ServiceMonitor; rate, errors, duration plus queue-drop counters. Alert on drop *rate*, never on queue depth.
- [ ] **Image** — immutable tag or digest, never `:latest`; multi-arch if the fleet is mixed.
- [ ] **Security** — `runAsNonRoot`, `readOnlyRootFilesystem`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, dedicated ServiceAccount, `automountServiceAccountToken: false` unless needed.
- [ ] **Placement** — topology spread across zones; anti-affinity for quorum members.
- [ ] **Backup/restore** — for stateful services, a *restore* actually rehearsed, with a stated RPO/RTO and any manual step named.
- [ ] **Runbook link in the alert annotation** — an alert without a runbook line is a page you cannot action.
- [ ] **Every alert fires on a condition that is still happening.** An alert on a resolved condition is noise, and noise is how a real page gets missed.


---


<a id="12-day-2-ops-and-observability"></a>

## 12 · Day-2 ops and observability

Once the loop runs, the job becomes keeping it boring: upgrades without downtime, capacity that follows demand, backups that actually restore, and enough telemetry that chapter 11's troubleshooting trees are rarely needed. All of it installs through the same Helm-and-GitOps path as the apps.

#### The observability stack

```bash
helm repo add prom https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts

helm upgrade --install kube-prometheus-stack prom/kube-prometheus-stack -n monitoring --create-namespace \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues=false \
  --set prometheus.prometheusSpec.retention=15d \
  --set grafana.sidecar.dashboards.searchNamespace=ALL   # dashboards from ConfigMaps in any namespace

helm upgrade --install loki  grafana/loki  -n monitoring -f loki-values.yaml   # single-binary for small clusters
helm upgrade --install alloy grafana/alloy -n monitoring -f alloy-values.yaml  # logs+metrics+traces shipper (replaces promtail)
helm upgrade --install tempo grafana/tempo -n monitoring
```

> **Gotcha.** Those three `...SelectorNilUsesHelmValues=false` flags are not decoration. Left at the default, Prometheus only discovers ServiceMonitors carrying the stack's own release label — so your app's ServiceMonitor is created, looks correct, and is silently never scraped. This is the single most common "why is there no data" in the whole stack.

#### The contract every chart should offer

```yaml
{{- if .Values.metrics.serviceMonitor.enabled }}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ include "myapp.fullname" . }}
  labels: {{- include "myapp.labels" . | nindent 4 }}
    {{- with .Values.metrics.serviceMonitor.labels }}{{ toYaml . | nindent 4 }}{{ end }}
spec:
  selector: { matchLabels: {{- include "myapp.selectorLabels" . | nindent 6 }} }
  endpoints:
    - port: metrics
      interval: {{ .Values.metrics.serviceMonitor.interval | default "30s" }}
{{- end }}
---
# dashboards as ConfigMaps, picked up by the Grafana sidecar
apiVersion: v1
kind: ConfigMap
metadata:
  name: myapp-dashboard
  labels: { grafana_dashboard: "1" }
  annotations: { grafana_folder: "Payments" }
data:
  myapp.json: |- {{ .Files.Get "dashboards/myapp.json" | nindent 4 }}
```

**Ship the dashboard with the chart.** A dashboard that lives only in someone's Grafana is lost on the next cluster rebuild, and it is never the version that matches the running code.

#### Proving the telemetry actually works

```bash
# is Prometheus scraping me?
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090 &
curl -s localhost:9090/api/v1/targets \
  | jq '.data.activeTargets[] | select(.labels.namespace=="payments") | {job, health, lastError}'

kubectl get servicemonitor -A; kubectl get prometheusrule -A
promtool check rules rules/*.yaml          # syntax-check alert rules before commit

logcli query '{namespace="payments", app="myapp"} |= "error" | json | status >= 500' --since=1h
```

#### Cluster upgrades

```bash
# check what breaks BEFORE you touch anything
kubectl deprecations                  # krew plugin
pluto detect-all-in-cluster -o wide
kubent

# kubeadm: one minor at a time, control plane first
kubeadm upgrade plan && kubeadm upgrade apply v1.3X.Y      # first control-plane node
kubectl drain NODE --ignore-daemonsets --delete-emptydir-data
# ...upgrade kubelet/kubeadm on the node, kubeadm upgrade node, restart kubelet...
kubectl uncordon NODE
```

On managed clusters (GKE/EKS/AKS, Talos, RKE2) the provider rotates nodes for you. **Your job is then exactly two things: PDBs that allow a drain to finish, and graceful shutdown that doesn't drop requests.** Both are chapter 11. Skipping them means the provider's rolling upgrade becomes your outage.

> **One-way door.** Kubernetes skips no minor versions on the way up, and there is no downgrade. Read the removed-API list for every minor you cross, and run `kubent`/`pluto` against the *manifests in git*, not just the live cluster — a resource that isn't deployed today still breaks the next `apply`.

#### Backups that restore

```bash
# etcd snapshot (kubeadm / self-managed only)
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /backup/etcd-$(date +%F).db
etcdutl snapshot status /backup/etcd-*.db -w table

# application-level: objects + volume snapshots
velero install --provider aws --bucket k8s-backups --secret-file ./creds \
  --use-node-agent --plugins velero/velero-plugin-for-aws
velero schedule create daily --schedule="0 2 * * *" --include-namespaces payments --ttl 720h
velero backup create pre-upgrade --include-namespaces payments --wait

# THE important line: restore into a different namespace and check it, on a schedule
velero restore create --from-backup pre-upgrade --namespace-mappings payments:payments-restore
```

**An unrehearsed restore is not a backup, it is a hope.** Put the rehearsal on the calendar and make it a ticket that someone closes with evidence — the number of rows, not a green checkmark.

#### Capacity and autoscaling

```bash
kubectl autoscale deploy myapp --min=2 --max=10 --cpu-percent=70   # HPA on CPU
helm upgrade --install keda kedacore/keda -n keda --create-namespace  # scale on queue depth, cron, etc.

krr simple -n payments        # right-size requests from actual Prometheus history
kubectl resource-capacity --pods --util     # requests vs limits vs reality, per node
```

Node autoscaling is Karpenter (AWS/Azure) or cluster-autoscaler. Both need **accurate requests** to work — an under-requested fleet looks empty to the autoscaler while pods throttle, and an over-requested one burns money scaling out nodes that sit idle. Fix requests before you add autoscaling; `krr` reads your real Prometheus history and tells you what they should be.

#### The four alerts that matter first

Before you tune the ~200 rules that ship with kube-prometheus-stack, get these four quiet:

| Alert | Expression, roughly |
|---|---|
| Pods restarting repeatedly | `increase(kube_pod_container_status_restarts_total[15m]) > 3` |
| Deployment below desired replicas for 10 min | `kube_deployment_status_replicas_available < kube_deployment_spec_replicas` |
| Node disk or memory pressure | `kube_node_status_condition{condition=~"DiskPressure|MemoryPressure",status="true"} == 1` |
| Certificate expiring within 14 days | `certmanager_certificate_expiration_timestamp_seconds - time() < 14*24*3600` |

**Everything else is noise until these are quiet.** An alert that fires on a resolved condition, or that nobody acts on, trains the team to ignore the channel — and that is how a real page gets missed.

#### Availability primitives that must exist before the first incident

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: myapp, namespace: payments }
spec:
  minAvailable: 1                      # never minAvailable == replicas: drains hang forever
  selector: { matchLabels: { app: myapp } }
---
# in the Deployment pod template
spec:
  terminationGracePeriodSeconds: 30
  topologySpreadConstraints:
    - { maxSkew: 1, topologyKey: topology.kubernetes.io/zone, whenUnsatisfiable: ScheduleAnyway, labelSelector: { matchLabels: { app: myapp } } }
  containers:
    - name: myapp
      lifecycle: { preStop: { exec: { command: [sleep, "5"] } } }   # let endpoints drain before SIGTERM
      startupProbe:   { httpGet: { path: /healthz, port: 8080 }, failureThreshold: 30, periodSeconds: 2 }
      readinessProbe: { httpGet: { path: /ready,   port: 8080 }, periodSeconds: 5 }
      livenessProbe:  { httpGet: { path: /healthz, port: 8080 }, periodSeconds: 10, failureThreshold: 3 }
      resources:
        requests: { cpu: 200m, memory: 256Mi }
        limits:   { memory: 512Mi }    # no CPU limit — see chapter 11
```

#### The day-2 checklist

- [ ] Every service has a ServiceMonitor **and you have verified the target is `up`** in Prometheus, not just that the object exists.
- [ ] Every service ships its dashboard as a ConfigMap in its own chart.
- [ ] The four alerts above are quiet, and each has a runbook link in its annotation.
- [ ] A restore has been rehearsed this quarter, into a scratch namespace, with evidence.
- [ ] `kubent` / `pluto` run in CI against the manifests in git, not only the live cluster.
- [ ] Requests are set from measured usage (`krr`), not from guesses, before any autoscaler is enabled.
- [ ] Every PDB has been tested with a real `kubectl drain` on a real node.
- [ ] The cluster upgrade path is written down, including which team approves it and what the rollback is.


---


<a id="13-portals-and-dashboards"></a>

## 13 · Portals and dashboards

You will spend most of your time in `kubectl` and `k9s`. The question this chapter answers is the other one: **what do you put in front of people who are not you** — a teammate who deploys twice a month, an on-call engineer at 3 a.m., a customer operator inside an air gap.

#### The honest framing

There are three distinct jobs, and most tools do one of them well and the others badly:

1. **Operate** — see live state, read logs, restart a thing. (k9s, Headlamp, Lens)
2. **Deliver** — what version is where, sync it, roll it back. (Argo CD UI, Flux + Capacitor)
3. **Catalogue** — who owns this service, where are its docs, runbook, dashboards, and what's our tech radar. (Backstage and its derivatives)

Buying a tool for job 3 and expecting job 1 is the most common disappointment.

#### The survey

| Tool | Job | Install | Airgap | The one-line verdict |
|---|---|---|---|---|
| **k9s** | operate | single binary, no cluster footprint | trivial | **The default.** Nothing beats it for speed once the keys are muscle memory |
| **Headlamp** | operate | in-cluster Deployment or desktop app | good — CNCF, no phone-home | **The one to give other people.** Clean web UI, OIDC, plugin API, actually maintained |
| **Lens** | operate | desktop app | licensing friction, account required | Polished, but the account requirement makes it a poor fit for a perimeter |
| **Rancher** | operate + multi-cluster mgmt | a full platform, its own controllers | supported, heavy | Pick it when you're managing *fleets* of clusters, not one. It brings opinions about everything |
| **Portainer** | operate | in-cluster | good | Approachable, Docker-heritage. Fine for small teams; thin on CRDs |
| **Argo CD UI** | deliver | comes with Argo | good | The best "what's deployed and is it healthy" view you will get for free. Use its tree view as a debugging tool, not just a dashboard |
| **Devtron** | deliver + operate | heavy platform | possible | An opinionated PaaS on top of k8s. Powerful, large surface area |
| **Backstage** | catalogue | app you build and host | good, but you own a Node app | The service catalogue + **Tech Radar** plugin. This is what people usually mean by "a radar" |
| **Komodor / Datadog / etc.** | operate + observe | SaaS agent | **no** | Genuinely good products, structurally unavailable behind an air gap |
| **Grafana** | observe | in-cluster | excellent | Not a k8s console, but the place your dashboards and alerts live. Standardize them |

#### Recommendation

**k9s for you, Headlamp for everyone else, Argo CD's UI for "what's deployed".** That trio covers the operate and deliver jobs with no SaaS dependency, no licence, and a combined footprint small enough to ship in an air-gapped bundle.

Add **Backstage** only when the question you keep answering is "who owns this and where are its docs" — it is a product you maintain, not a chart you install, and it is worth it only at a certain team size.

#### Headlamp, concretely

```bash
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm upgrade --install headlamp headlamp/headlamp -n kube-system \
  --set config.oidc.clientID=headlamp \
  --set config.oidc.issuerURL=https://keycloak.example/realms/example \
  --set config.oidc.scopes=openid,profile,email
```

The important part is that Headlamp **authenticates the human and then uses their own RBAC** — it does not run as a shared cluster-admin behind a login page. Any console that does is a privilege-escalation surface wearing a UI, and it should be treated as a finding.

#### The dashboard you actually need

A per-service Grafana dashboard beats a generic cluster console for the on-call question. Standardize it so every service's dashboard has the same panels in the same positions:

1. **Rate, errors, duration** (the three you page on)
2. **Pod restarts and current replica count vs desired**
3. **CPU throttling fraction** and **memory working set vs limit** — the two that explain "it's slow" and "it died"
4. **Queue depth and drop rate** for anything with a buffer
5. **The deploy annotation stream** so a graph change lines up with a release

Consistency matters more than cleverness: at 3 a.m. the value of a dashboard is that you already know where to look.

#### The rule that governs all of it

**Every alert carries a runbook link in its annotation, and every runbook names the exact commands.** A console that shows you a red box without telling you what to do has moved the problem, not solved it. The chapters above are, in effect, that runbook — the console's job is just to get you to the right chapter faster.

#### The full table

| Tool | What it is | Install | Choose it when |
|---|---|---|---|
| **Headlamp** | CNCF web UI, plugin system, runs in-cluster or as a desktop app, uses your kubeconfig/OIDC and RBAC as-is | `helm upgrade --install headlamp headlamp/headlamp -n kube-system` | You want a clean, read-mostly UI with SSO and zero extra control plane. **The modern default** |
| **Rancher** | Multi-cluster management platform: provisions clusters (RKE2, k3s, cloud), central auth, projects, Helm catalog, Fleet GitOps, monitoring bundle | `helm upgrade --install rancher rancher-stable/rancher -n cattle-system --set hostname=...` (needs cert-manager) | Many clusters, many teams, and you want lifecycle + RBAC + catalog in one place. Heavy but complete; strong air-gap story |
| **Lens / OpenLens** | Desktop IDE for clusters: metrics, logs, shell, Helm, extensions | Download; `brew install --cask openlens` | Individual power users who want a desktop app. Lens is commercial beyond personal use |
| **Portainer** | Simple UI for Docker *and* Kubernetes, app templates, GitOps polling, RBAC | `helm upgrade --install portainer portainer/portainer -n portainer --create-namespace` | Mixed Docker/Kubernetes estates, edge sites, teams new to Kubernetes |
| **Kubernetes Dashboard** | The upstream UI; Helm-only now, Kong in front, token login | `helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard -n kubernetes-dashboard --create-namespace` | Something official and minimal already exists. Most teams outgrow it |
| **Devtron** | Developer portal: CI/CD, Helm app management, security scanning, RBAC | Helm chart | You want an internal developer platform out of the box rather than assembling one |
| **Backstage** | Developer portal framework (CNCF): service catalog, software templates, **Tech Radar**, a Kubernetes plugin that shows pods per service | A Node app you host | Service ownership and documentation are the problem, not cluster admin |
| **k9s** | Terminal UI (chapter 03) | `brew install k9s` | Always. It complements every option above |

#### The rule that makes all of them safe

**Wire SSO once, at the API server.** Configure OIDC on kube-apiserver (or put kubelogin / Dex / Pinniped in front of it) and bind groups to ClusterRoles. Then Headlamp, Lens, Argo CD *and* kubectl all show each person exactly what RBAC allows, and every action is attributed in the audit log.

```bash
helm repo add headlamp https://kubernetes-sigs.github.io/headlamp/
helm upgrade --install headlamp headlamp/headlamp -n kube-system \
  --set config.oidc.clientID=headlamp \
  --set config.oidc.issuerURL=https://sso.internal/realms/example \
  --set config.oidc.clientSecret=$SECRET \
  --set ingress.enabled=true --set ingress.hosts[0].host=headlamp.internal

# a viewer role for "everyone else"
kubectl create clusterrolebinding viewers --clusterrole=view --group=engineering
```

> **One-way door.** A console that manages its own user database, or runs as a shared cluster-admin behind a login page, bypasses all of that. It becomes a second thing to audit and a privilege-escalation surface wearing a UI — and once people have accounts in it, migrating them off is a project. Treat it as a finding, not a convenience.


---


<a id="14-one-screen-kubectl-reference"></a>

## 14 · One-screen kubectl reference

The output tricks that turn `kubectl` into a query language. This is the section to print.

#### Shaping output

```bash
kubectl get pods -o wide                       # node, IP, nominated node
kubectl get pods -o yaml | kubectl neat         # strip managedFields and status noise
kubectl get pods -o name                        # pod/xyz, for xargs
kubectl get pods -o custom-columns='NAME:.metadata.name,NODE:.spec.nodeName,IMG:.spec.containers[*].image,RESTARTS:.status.containerStatuses[*].restartCount'
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}'
kubectl get pods -o json | jq -r '.items[] | select(.status.phase!="Running") | .metadata.name'
kubectl get deploy -o yaml | yq '.items[].spec.template.spec.containers[].image'
kubectl get pods --sort-by=.status.startTime
kubectl get pods --sort-by='.status.containerStatuses[0].restartCount' -A | tail
kubectl get events --sort-by=.lastTimestamp -A --field-selector type=Warning
```

#### Selecting

```bash
kubectl get pods -l app=web,tier!=cache                 # label selectors
kubectl get pods -l 'env in (dev,staging)'
kubectl get pods --field-selector status.phase=Pending,spec.nodeName=NODE
kubectl get pods -A --field-selector metadata.namespace!=kube-system
kubectl get all,ing,pvc,cm,secret -n NS                 # "all" is not all; add what you need
kubectl get-all -n NS                                   # krew: actually all, including CRs
```

#### Discovering

```bash
kubectl api-resources --namespaced=true -o wide | column -t
kubectl api-versions
kubectl explain deploy.spec.strategy.rollingUpdate
kubectl explain pod.spec --recursive | grep -i -B2 -A8 securityContext
kubectl get --raw /metrics | grep apiserver_request_total | head
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes | jq
kubectl version; kubectl cluster-info
kubectl cluster-info dump --output-directory=./dump
```

#### Creating without writing YAML

```bash
kubectl create deploy web --image=nginx --replicas=3 --port=80 --dry-run=client -o yaml > deploy.yaml
kubectl expose deploy web --port=80 --target-port=8080 --type=ClusterIP
kubectl create job manual --from=cronjob/nightly-report
kubectl create secret generic db --from-literal=password=x --from-file=ca.crt
kubectl create configmap cfg --from-file=config.yaml --from-env-file=.env
kubectl create ingress web --rule="web.example.com/*=web:80,tls=web-tls" --class=nginx
```

#### Changing

```bash
kubectl apply -f dir/ --recursive --prune -l app=web    # prune what you removed (prefer GitOps)
kubectl apply --server-side --field-manager=ci -f manifest.yaml
kubectl diff -f manifest.yaml
kubectl patch deploy web -p '{"spec":{"replicas":5}}'
kubectl patch deploy web --type json -p '[{"op":"add","path":"/spec/template/metadata/annotations/restartedAt","value":"'"$(date -Is)"'"}]'
kubectl set env deploy/web LOG_LEVEL=debug
kubectl set resources deploy/web -c web --limits=memory=1Gi
kubectl scale deploy web --replicas=0                   # the universal "turn it off"
kubectl annotate --overwrite deploy web kubernetes.io/change-cause="hotfix $(git rev-parse --short HEAD)"
kubectl label pods -l app=web canary=true
kubectl replace --force -f pod.yaml                     # delete + create
kubectl delete pod POD --grace-period=0 --force         # ONLY when the node is confirmed gone
kubectl wait --for=condition=available deploy/web --timeout=120s
kubectl wait --for=delete pod/POD --timeout=60s
kubectl rollout pause deploy/web; kubectl rollout resume deploy/web
```

#### Moving data

```bash
kubectl cp NS/POD:/var/log/app.log ./app.log -c web
kubectl port-forward svc/web 8080:80 --address 0.0.0.0
kubectl proxy &  curl localhost:8001/api/v1/namespaces/NS/services/web:80/proxy/
kubectl exec POD -- tar cf - /data | tar xf - -C ./data
```

#### Context and safety

```bash
kubectl config current-context
kubectl --context prod --namespace payments get pods    # never switch — always specify, for anything destructive
kubectl auth whoami
kubectl auth can-i '*' '*'                              # am I cluster-admin here?
kubectl get pods -v=8 2>&1 | grep -E "GET|Response Status"   # see the REST calls kubectl makes
```

#### Short names worth memorising

| Short | Kind | Short | Kind | Short | Kind |
|---|---|---|---|---|---|
| `po` | pods | `deploy` | deployments | `rs` | replicasets |
| `sts` | statefulsets | `ds` | daemonsets | `cj` | cronjobs |
| `svc` | services | `ing` | ingresses | `ep` / `epslice` | endpoints / endpointslices |
| `cm` | configmaps | `sa` | serviceaccounts | `netpol` | networkpolicies |
| `pvc` | persistentvolumeclaims | `pv` | persistentvolumes | `sc` | storageclasses |
| `hpa` | horizontalpodautoscalers | `pdb` | poddisruptionbudgets | `quota` | resourcequotas |
| `ns` | namespaces | `no` | nodes | `crd` | customresourcedefinitions |
| `ev` | events | `crb` / `rb` | clusterrolebindings / rolebindings | `hr` / `ks` / `gitrepo` | Flux: helmreleases / kustomizations / gitrepositories |

#### When this page is out of date

Where a tool changes faster than this guide, **its own `--help` wins**: `kubectl explain`, `helm --help`, `flux --help`, `argocd --help`. The upstream references worth bookmarking are the [kubectl quick reference](https://kubernetes.io/docs/reference/kubectl/quick-reference/), [Helm docs](https://helm.sh/docs/), [Flux docs](https://fluxcd.io/flux/), [Argo CD docs](https://argo-cd.readthedocs.io/), the [Kyverno policy library](https://kyverno.io/policies/), [kind](https://kind.sigs.k8s.io/) and [Tilt](https://docs.tilt.dev/).


---
