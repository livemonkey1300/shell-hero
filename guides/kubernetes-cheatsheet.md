# Kubernetes Cheatsheet

A practical reference covering everyday `kubectl`, plus an extensive section on
reading **Operator** and **CRD** configuration with proper parsing and clean output.

> Tip: set an alias once and use `k` everywhere below: `alias k=kubectl`

---

## 0. Aliases & Shell Helpers

Drop this into your `~/.bashrc` or `~/.zshrc`, then `source` it (or open a new shell).

```bash
# --- core alias ---
alias k=kubectl

# enable completion for the alias (bash)
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
# zsh: source <(kubectl completion zsh); compdef __start_kubectl k

# --- everyday shortcuts ---
alias kg='kubectl get'
alias kd='kubectl describe'
alias kgp='kubectl get pods'
alias kga='kubectl get all'
alias kgpa='kubectl get pods -A'
alias kaf='kubectl apply -f'
alias kdf='kubectl delete -f'
alias kl='kubectl logs -f'
alias kx='kubectl exec -it'
alias kctx='kubectl config use-context'
alias kns='kubectl config set-context --current --namespace'

# default namespace for the session
export ns='-n'           # usage: k get pods $ns kube-system

# --- functions ---
# clean, re-appliable YAML for any resource:  kneat pod my-pod
kneat() { kubectl get "$1" "$2" -o yaml | kubectl neat | ${PAGER:-less}; }

# follow logs for a deployment:  klogs my-operator kube-system
klogs() { kubectl logs -f "deployment/$1" -n "${2:-default}"; }

# quick describe + events for a resource:  kev pod my-pod
kev() { kubectl describe "$1" "$2" ${3:+-n $3}; }
```

---

## 1. Context, Namespaces & Setup

| Action | Command |
| --- | --- |
| List contexts | `kubectl config get-contexts` |
| Show current context | `kubectl config current-context` |
| Switch context | `kubectl config use-context <ctx>` |
| Set default namespace for context | `kubectl config set-context --current --namespace=<ns>` |
| List namespaces | `kubectl get ns` |
| Show full client/server versions | `kubectl version` |
| Cluster endpoint info | `kubectl cluster-info` |

Handy tools: [`kubectx` / `kubens`](https://github.com/ahmetb/kubectx) for fast
context/namespace switching.

---

## 2. Everyday Resource Commands

```bash
# Listing
kubectl get pods                          # current namespace
kubectl get pods -A                       # all namespaces
kubectl get pods -o wide                  # + node, IP
kubectl get pods --show-labels
kubectl get pods -l app=nginx             # filter by label
kubectl get all -n <ns>                   # common resources in a namespace

# Inspecting
kubectl describe pod <pod> -n <ns>        # events + full state (great for debugging)
kubectl get pod <pod> -o yaml             # raw manifest
kubectl explain pod.spec.containers       # schema/docs for any field

# Logs
kubectl logs <pod> -n <ns>
kubectl logs -f <pod>                     # follow
kubectl logs <pod> -c <container>         # specific container
kubectl logs <pod> --previous            # crashed/restarted container
kubectl logs -f deployment/<name>         # follow a deployment's pods

# Exec / debug
kubectl exec -it <pod> -- /bin/bash
kubectl exec -it <pod> -c <container> -- sh
kubectl debug -it <pod> --image=busybox --target=<container>   # ephemeral container
kubectl port-forward svc/<svc> 8080:80

# Apply / delete
kubectl apply -f manifest.yaml
kubectl apply -k ./overlay               # kustomize
kubectl delete -f manifest.yaml
kubectl diff -f manifest.yaml            # preview changes before apply

# Rollouts
kubectl rollout status deployment/<name>
kubectl rollout restart deployment/<name>
kubectl rollout undo deployment/<name>

# Scaling
kubectl scale deployment/<name> --replicas=3
```

---

## 2b. Creating Deployments, Services & Port-Forwarding

### Create a Deployment

```bash
# Imperative — fastest way to spin one up
kubectl create deployment nginx --image=nginx:1.27 --replicas=3

# Generate a manifest WITHOUT creating it (best practice: review, edit, apply)
kubectl create deployment nginx --image=nginx:1.27 --replicas=3 \
  --dry-run=client -o yaml > deployment.yaml
kubectl apply -f deployment.yaml

# Set / change the image on an existing deployment
kubectl set image deployment/nginx nginx=nginx:1.28

# Expose a port the container listens on (just records it)
kubectl create deployment nginx --image=nginx --port=80
```

Minimal Deployment manifest (`deployment.yaml`):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  labels: { app: nginx }
spec:
  replicas: 3
  selector:
    matchLabels: { app: nginx }
  template:
    metadata:
      labels: { app: nginx }
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
```

### Create a Service (expose the Deployment)

```bash
# ClusterIP (default) — reachable inside the cluster only
kubectl expose deployment nginx --port=80 --target-port=80

# NodePort — reachable on every node's IP at a high port (30000-32767)
kubectl expose deployment nginx --type=NodePort --port=80 --target-port=80

# LoadBalancer — provisions an external LB (cloud)
kubectl expose deployment nginx --type=LoadBalancer --port=80 --target-port=80

# Generate the Service manifest instead of creating it
kubectl expose deployment nginx --port=80 --target-port=80 \
  --dry-run=client -o yaml > service.yaml

# Inspect it
kubectl get svc nginx
kubectl get endpoints nginx        # which pod IPs back the service
```

Minimal Service manifest (`service.yaml`):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx
spec:
  type: ClusterIP            # or NodePort / LoadBalancer
  selector:
    app: nginx               # must match the Deployment's pod labels
  ports:
    - port: 80               # service port
      targetPort: 80         # container port
```

### Port-forward (reach a pod/service from your laptop)

```bash
# Forward localhost:8080 -> service port 80
kubectl port-forward svc/nginx 8080:80

# Forward to a deployment (picks one of its pods)
kubectl port-forward deployment/nginx 8080:80

# Forward directly to a pod
kubectl port-forward pod/<pod-name> 8080:80

# Same local & remote port
kubectl port-forward svc/nginx 80

# Listen on all interfaces (not just 127.0.0.1) — e.g. to share on your LAN
kubectl port-forward --address 0.0.0.0 svc/nginx 8080:80

# In a specific namespace, run in background
kubectl port-forward svc/nginx 8080:80 -n my-ns &
```

Then hit it: `curl http://localhost:8080`. Port-forward runs in the foreground
until you `Ctrl-C` (or kill the backgrounded job).

---

## 3. Discovering CRDs & Operators

CRDs (CustomResourceDefinitions) register new resource types; Operators are
controllers that reconcile instances of those types.

```bash
# List every CRD installed in the cluster
kubectl get crds
kubectl get crd                                   # same thing

# Full list of resource types, including those added by CRDs
kubectl api-resources
kubectl api-resources --api-group=<group>         # e.g. monitoring.coreos.com
kubectl api-resources --namespaced=true           # only namespaced kinds

# Which API groups/versions exist
kubectl api-versions

# Find the short name, group, and kind for a CRD
kubectl get crd <crd-name> -o jsonpath='{.spec.names.kind} {.spec.group} {.spec.names.shortNames}{"\n"}'

# List all instances (custom resources) of a CRD across the cluster
kubectl get <plural-or-shortname> -A
# e.g. kubectl get prometheuses -A   /   kubectl get certificates -A
```

### Finding the Operator that owns a CRD

```bash
# Operators usually run as Deployments. Search by name:
kubectl get deploy -A | grep -iE 'operator|controller|manager'

# Follow the operator's reconcile logs (the #1 way to see WHY a CR isn't applying)
kubectl logs -f deployment/<operator-deploy> -n <ns>

# See what the operator is reacting to via events
kubectl get events -A --sort-by=.lastTimestamp | tail -n 40
kubectl describe <crd-kind> <instance> -n <ns>    # shows reconcile events at bottom
```

---

## 4. Reading CRD Definitions (the schema)

```bash
# The whole CRD object
kubectl get crd <crd-name> -o yaml

# Versions served and which is stored
kubectl get crd <crd-name> -o jsonpath='{range .spec.versions[*]}{.name}{"  served="}{.served}{"  storage="}{.storage}{"\n"}{end}'

# Extract the OpenAPI validation schema (the field definitions) for a version
kubectl get crd <crd-name> -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema}'

# Cleaner: dump the schema as YAML for a specific version
kubectl get crd <crd-name> -o yaml | yq '.spec.versions[] | select(.name=="v1") | .schema.openAPIV3Schema'

# Use explain against the live CRD schema — best for learning fields interactively
kubectl explain <crd-kind>                        # top level
kubectl explain <crd-kind>.spec                    # drill into spec
kubectl explain <crd-kind>.spec --recursive        # entire field tree
```

> `kubectl explain` reads the schema the CRD registered, so it works for *any*
> custom resource the same way it does for built-in ones.

---

## 5. Reading Custom Resource Instances (the config)

```bash
# Full instance
kubectl get <kind> <name> -n <ns> -o yaml

# Just the spec (the user-supplied config)
kubectl get <kind> <name> -n <ns> -o jsonpath='{.spec}' | jq .

# Spec + status side by side
kubectl get <kind> <name> -n <ns> -o json | jq '{spec, status}'

# Reconcile conditions (is the operator happy?)
kubectl get <kind> <name> -n <ns> -o json | jq '.status.conditions'

# Tabular view of all instances with selected fields
kubectl get <kind> -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'
```

### Custom columns (clean tables without jq)

```bash
kubectl get <kind> -A \
  -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,PHASE:.status.phase,AGE:.metadata.creationTimestamp'
```

---

## 6. Parsing & Pretty-Printing Output

### 6a. Built-in: `-o jsonpath`
No external tools required. Good for scripts.

```bash
# Single value
kubectl get pod <pod> -o jsonpath='{.status.podIP}'

# Loop over a list
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'

# Container images in a deployment
kubectl get deploy <name> -o jsonpath='{.spec.template.spec.containers[*].image}'
```

### 6b. `jq` — the JSON power tool
```bash
# Colorized, indented full object
kubectl get <kind> <name> -o json | jq .

# Filter CRDs by owning group/domain
kubectl get crds -o json | jq -r '.items[] | select(.spec.group | test("coreos|cert-manager")) | .metadata.name'

# Pull every image used by an operator
kubectl get deploy <op> -n <ns> -o json | jq -r '.spec.template.spec.containers[].image'

# All CRs whose status is not Ready
kubectl get <kind> -A -o json \
  | jq -r '.items[] | select((.status.conditions[]?|select(.type=="Ready").status) != "True") | .metadata.name'
```

### 6c. `yq` — `jq` for YAML
```bash
# Pretty + highlighted YAML
kubectl get <kind> <name> -o yaml | yq

# Extract a nested field
kubectl get <kind> <name> -o yaml | yq '.spec.replicas'

# Operator container images
kubectl get deploy <op> -n <ns> -o yaml | yq '.spec.template.spec.containers[].image'
```

---

## 7. "Read It Properly" — Clean, Reusable Output

Raw `-o yaml` is polluted with `managedFields`, `resourceVersion`, timestamps,
and `status`. Strip the noise:

### `kubectl neat` (recommended)
```bash
# Install via Krew (the kubectl plugin manager)
kubectl krew install neat

# Pristine, re-appliable manifest
kubectl get <kind> <name> -n <ns> -o yaml | kubectl neat

# Ultimate combo: clean + highlighted
kubectl get <kind> <name> -n <ns> -o yaml | kubectl neat | yq
```

### Without neat — strip managedFields manually
```bash
kubectl get <kind> <name> -o json \
  | jq 'del(.metadata.managedFields, .metadata.resourceVersion, .metadata.uid,
            .metadata.generation, .metadata.creationTimestamp, .status,
            .metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"])' \
  | yq -P
```

### Useful plugins (all installable via `kubectl krew install <name>`)
| Plugin | Purpose |
| --- | --- |
| `neat` | Remove clutter from manifests |
| `ctx` / `ns` | Fast context/namespace switching |
| `tree` | Show ownerReference tree (CR → child resources the operator created) |
| `view-secret` | Decode a secret's data without manual base64 |
| `get-all` | Truly get *all* resources, including CRs `get all` misses |

```bash
# See everything an operator created from one custom resource
kubectl tree <kind> <name> -n <ns>
```

---

## 8. Operator/CRD Debugging Workflow (cheat-recipe)

```bash
# 1. Confirm the CRD is installed and which versions are served
kubectl get crd <crd-name> -o jsonpath='{range .spec.versions[*]}{.name}{" served="}{.served}{"\n"}{end}'

# 2. Confirm the operator pod is running
kubectl get pods -n <op-ns> -l <operator-label>

# 3. Look at your custom resource's status/conditions
kubectl get <kind> <name> -n <ns> -o json | jq '.status'

# 4. Read the operator logs for reconcile errors
kubectl logs -f deploy/<operator> -n <op-ns> | grep -iE 'error|reconcile|<name>'

# 5. Inspect events for the resource
kubectl describe <kind> <name> -n <ns>

# 6. See what the operator actually created
kubectl tree <kind> <name> -n <ns>
```

---

## 9. Quick Reference: Output Formats

| Flag | Result |
| --- | --- |
| `-o wide` | Extra columns (node, IP) |
| `-o yaml` / `-o json` | Full object |
| `-o name` | `kind/name` only |
| `-o jsonpath='{...}'` | Extract specific fields |
| `-o custom-columns=...` | Custom table |
| `-o go-template='{{...}}'` | Go template formatting |
| `--no-headers` | Drop the header row (scripting) |
| `--sort-by=.metadata.name` | Sort output |
