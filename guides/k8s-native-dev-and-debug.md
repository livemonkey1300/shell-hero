# Kubernetes-Native Development, Build, Linting & Debugging

How to build, lint, and **fully debug** software (Node, Python/Flask, Go, and more)
running natively in Kubernetes — driven from a Helm chart with a dev values overlay.

The core idea: keep **one** chart, and toggle a `dev` profile via values that
swaps the container command to a debugger, exposes the debug port, drops to one
replica, and relaxes the security context. Production values never change.

---

## Table of Contents
1. [The cloud-native dev loop — pick a tool](#1-the-cloud-native-dev-loop--pick-a-tool)
2. [Building images in/for Kubernetes](#2-building-images-infor-kubernetes)
3. [Linting & configuration (code + manifests)](#3-linting--configuration-code--manifests)
4. [The Helm dev-overlay pattern](#4-the-helm-dev-overlay-pattern)
5. [Full remote debugging by language](#5-full-remote-debugging-by-language)
6. [Wiring it together with Skaffold / Tilt](#6-wiring-it-together-with-skaffold--tilt)
7. [Quick reference](#7-quick-reference)

---

## 1. The cloud-native dev loop — pick a tool

These tools watch your source, rebuild the image, redeploy to the cluster, and
forward ports/logs — turning Kubernetes into a live dev environment.

| Tool | Best for | How it works | Debug support |
| --- | --- | --- | --- |
| **Skaffold** | General-purpose, CI-friendly, language-agnostic | Watch → build → deploy → port-forward; integrates with Helm | `skaffold debug` auto-configures debuggers + ports |
| **Tilt** | Multi-service local dev, great UI | `Tiltfile` (Starlark); live update syncs files into running containers | Manual (expose port + attach) |
| **DevSpace** | Per-developer namespaces, file sync | `devspace.yaml`; sync + reverse port-forward | Built-in via dev container config |
| **Telepresence** | Run/debug ONE service locally while it joins the cluster network | Intercepts traffic to a real cluster service to your local process | Debug locally with full IDE, native speed |
| **Garden** | Monorepos, complex dependency graphs | Declarative graph of build/deploy/test actions | Per-action |
| **mirrord** | Run local process with cluster's env/traffic/files | Plugs local process into a pod's context | Local IDE debug |

**Recommendation:**
- **Skaffold + Helm** for an iterate-in-cluster loop with the least glue — and
  `skaffold debug` gives you debuggers for free.
- **Telepresence/mirrord** when you want your IDE driving a local process while
  everything else stays in the cluster (fastest debug experience).

```bash
# Skaffold: build + deploy your Helm chart and stream logs, rebuilding on save
skaffold dev

# Skaffold: same, but launch language debuggers and forward their ports
skaffold debug
```

---

## 2. Building images in/for Kubernetes

You usually don't need a Docker daemon. Cluster-native / daemonless builders:

| Tool | Language scope | Notes |
| --- | --- | --- |
| **BuildKit** (`docker buildx`) | Any (Dockerfile) | Fast, cache mounts, multi-arch. The default modern builder. |
| **kaniko** | Any (Dockerfile) | Builds **inside** a cluster pod, no privileged daemon — ideal for CI in k8s. |
| **Cloud Native Buildpacks** (`pack`) | Node, Python, Go, Java, Ruby… | **No Dockerfile** — auto-detects and produces optimized, reproducible images. |
| **ko** | Go only | Dockerfile-free, blazing-fast Go container builds; pairs great with k8s. |
| **Jib** | Java only | Maven/Gradle plugin; layered images without a daemon. |

### Examples

```bash
# BuildKit multi-arch
docker buildx build --platform linux/amd64,linux/arm64 -t myrepo/app:dev --push .

# Buildpacks — no Dockerfile needed
pack build myrepo/app:dev --builder paketobuildpacks/builder-jammy-base

# ko — Go, no Dockerfile
KO_DOCKER_REPO=myrepo ko build ./cmd/server

# kaniko (run as a Job/Pod in-cluster)
# /kaniko/executor --dockerfile=Dockerfile --context=git://github.com/org/repo --destination=myrepo/app:dev
```

> **Build-time vs debug-time:** ship two image targets. A slim production image,
> and a `debug` target that includes the debugger (`delve`, `debugpy`) and is
> **not** stripped of symbols. Select the target per Skaffold/Helm profile.

### Compiling Go for debug (keep symbols!)

```dockerfile
# Debug build target — DO NOT strip symbols, disable inlining/optimizations
RUN go build -gcflags="all=-N -l" -o /app ./cmd/server
# Production build target — strip for size
# RUN go build -ldflags="-s -w" -trimpath -o /app ./cmd/server
```

---

## 3. Linting & configuration (code + manifests)

A Kubernetes-native project has **two layers** to lint: your application code and
your Kubernetes/Helm artifacts.

### 3a. Application code linters

| Language | Linter / formatter | Config file |
| --- | --- | --- |
| **Node / JS / TS** | ESLint + Prettier (or **Biome** = both in one) | `eslint.config.js`, `.prettierrc`, `biome.json` |
| **Python** | **Ruff** (lint + format, replaces flake8/isort/black), mypy for types | `pyproject.toml` / `ruff.toml` |
| **Go** | **golangci-lint** (aggregates vet, staticcheck, etc.), `gofmt`/`goimports` | `.golangci.yml` |
| **Shell** | shellcheck + shfmt | — |

Minimal configs:

```toml
# pyproject.toml  (Ruff)
[tool.ruff]
line-length = 100
target-version = "py312"
[tool.ruff.lint]
select = ["E", "F", "I", "B", "UP"]   # pycodestyle, pyflakes, isort, bugbear, pyupgrade
```

```yaml
# .golangci.yml
run:
  timeout: 3m
linters:
  enable: [gofmt, goimports, govet, staticcheck, errcheck, gosimple, unused, gosec]
```

```jsonc
// biome.json  (Node — lint + format in one fast tool)
{ "linter": { "enabled": true }, "formatter": { "enabled": true, "indentWidth": 2 } }
```

### 3b. Kubernetes / Helm / Dockerfile linters

| Target | Tool | What it catches |
| --- | --- | --- |
| Helm chart | `helm lint` | Template & Chart.yaml errors |
| Rendered manifests vs schema | **kubeconform** | Invalid/typo'd k8s fields, wrong apiVersions |
| Manifest best practices | **kube-linter** | Missing limits, runAsNonRoot, latest tags, etc. |
| Policy as code | **conftest** (OPA/Rego) / **Kyverno CLI** | Org policies (no privileged, required labels…) |
| Dockerfile | **hadolint** | Bad practices, pinning, layer hygiene |
| YAML syntax | **yamllint** | Formatting/indent |

```bash
helm lint ./mychart
helm template ./mychart | kubeconform -strict -summary
helm template ./mychart | kube-linter lint -
hadolint Dockerfile
helm template ./mychart | conftest test -
```

### 3c. Tie it together with pre-commit + CI

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.6.0
    hooks: [{id: ruff}, {id: ruff-format}]
  - repo: https://github.com/golangci/golangci-lint
    rev: v1.60.1
    hooks: [{id: golangci-lint}]
  - repo: https://github.com/hadolint/hadolint
    rev: v2.13.0
    hooks: [{id: hadolint}]
  - repo: local
    hooks:
      - id: helm-lint
        name: helm lint
        entry: helm lint ./mychart
        language: system
        pass_filenames: false
```

```bash
pre-commit install        # run automatically on git commit
pre-commit run --all-files
```

---

## 4. The Helm dev-overlay pattern

Keep one chart. Add a `debug` block to `values.yaml`, and a `values-dev.yaml`
that turns it on. The Deployment template reads it to swap the command, expose the
port, and adjust the security context.

### `values.yaml` (defaults — production-safe, debug OFF)

```yaml
image:
  repository: myrepo/app
  tag: latest
replicaCount: 3

debug:
  enabled: false           # master switch
  port: 0                  # set per-language below
  command: []              # override container command in dev
  args: []
```

### `values-dev.yaml` (overlay — debug ON)

```yaml
image:
  tag: debug               # the image target that includes the debugger
replicaCount: 1            # one pod so the debugger always attaches to the same target

debug:
  enabled: true
  # port/command/args filled in per language in §5
```

### `templates/deployment.yaml` (the conditional bits)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "mychart.fullname" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels: { app: {{ include "mychart.name" . }} }
  template:
    metadata:
      labels: { app: {{ include "mychart.name" . }} }
    spec:
      {{- if .Values.debug.enabled }}
      # delve needs ptrace; most debuggers are happier without a read-only FS
      securityContext:
        runAsNonRoot: false
      {{- end }}
      containers:
        - name: app
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          {{- with .Values.debug.command }}
          command: {{ toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.debug.args }}
          args: {{ toYaml . | nindent 12 }}
          {{- end }}
          ports:
            - { name: http, containerPort: 8080 }
            {{- if .Values.debug.enabled }}
            - { name: debug, containerPort: {{ .Values.debug.port }} }
            {{- end }}
          {{- if .Values.debug.enabled }}
          securityContext:
            capabilities:
              add: ["SYS_PTRACE"]     # required by delve (Go); harmless for others
            readOnlyRootFilesystem: false
          # don't let probes kill the pod while you're paused at a breakpoint
          livenessProbe: null
          readinessProbe: null
          {{- end }}
```

Install the dev profile, then forward the debug port:

```bash
helm upgrade --install myapp ./mychart -n dev --create-namespace -f values-dev.yaml
kubectl port-forward deploy/myapp <debug-port>:<debug-port> -n dev
# then "attach" your IDE to localhost:<debug-port>
```

> **Why disable probes & extra replicas in debug:** when you hit a breakpoint the
> process stops responding; liveness probes would restart the pod and multiple
> replicas mean your debugger might attach to the wrong one.

---

## 5. Full remote debugging by language

For each: the debug port, the container `command`/`args` to put in `values-dev.yaml`,
and the IDE attach config.

### 5a. Node.js — Inspector protocol (port **9229**)

```yaml
# values-dev.yaml
debug:
  enabled: true
  port: 9229
  # --inspect-brk waits for the debugger before running (drop "-brk" to not wait)
  command: ["node"]
  args: ["--inspect-brk=0.0.0.0:9229", "dist/server.js"]
```

For TypeScript/auto-restart in dev: `["npx","nodemon","--inspect=0.0.0.0:9229","src/server.ts"]`.

```bash
kubectl port-forward deploy/myapp 9229:9229 -n dev
```

VS Code `.vscode/launch.json`:
```jsonc
{ "type": "node", "request": "attach", "name": "k8s attach",
  "address": "localhost", "port": 9229,
  "localRoot": "${workspaceFolder}", "remoteRoot": "/app" }
```
Or open `chrome://inspect` in Chrome.

---

### 5b. Python / Flask — debugpy (port **5678**)

Add `debugpy` to the debug image, then run the app under it.

```yaml
# values-dev.yaml
debug:
  enabled: true
  port: 5678
  command: ["python", "-m", "debugpy"]
  # --wait-for-client pauses until the IDE attaches; remove to start immediately
  args: ["--listen", "0.0.0.0:5678", "--wait-for-client", "-m", "flask", "run",
         "--host=0.0.0.0", "--port=8080", "--no-reload"]
```

> Use `--no-reload`: Flask's reloader forks a child process, and the debugger
> ends up attached to the wrong one. Set `FLASK_APP`/`FLASK_DEBUG` via env if needed.

Dockerfile debug target:
```dockerfile
RUN pip install debugpy
```

```bash
kubectl port-forward deploy/myapp 5678:5678 -n dev
```

VS Code `.vscode/launch.json`:
```jsonc
{ "type": "debugpy", "request": "attach", "name": "k8s Flask attach",
  "connect": { "host": "localhost", "port": 5678 },
  "pathMappings": [{ "localRoot": "${workspaceFolder}", "remoteRoot": "/app" }] }
```

---

### 5c. Go — Delve (port **40000**)

Build with symbols (`-gcflags="all=-N -l"`, see §2), run the binary under `dlv`.

```yaml
# values-dev.yaml
debug:
  enabled: true
  port: 40000
  command: ["/dlv"]
  args: ["--listen=:40000", "--headless=true", "--api-version=2",
         "--accept-multiclient", "exec", "/app"]
```

Dockerfile debug target:
```dockerfile
RUN go install github.com/go-delve/delve/cmd/dlv@latest && cp $(go env GOPATH)/bin/dlv /dlv
RUN go build -gcflags="all=-N -l" -o /app ./cmd/server
```

> Delve **requires** the `SYS_PTRACE` capability (added in the template in §4).

```bash
kubectl port-forward deploy/myapp 40000:40000 -n dev
```

VS Code `.vscode/launch.json`:
```jsonc
{ "type": "go", "request": "attach", "name": "k8s Delve attach",
  "mode": "remote", "host": "localhost", "port": 40000,
  "substitutePath": [{ "from": "${workspaceFolder}", "to": "/" }] }
```
GoLand: *Go Remote* run config → host `localhost`, port `40000`.

---

### 5d. Java / JVM — JDWP (port **5005**) — for completeness

```yaml
debug:
  enabled: true
  port: 5005
  args: ["-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005",
         "-jar", "/app.jar"]
```
Attach: VS Code/IntelliJ *Remote JVM Debug* → `localhost:5005`.

---

## 6. Wiring it together with Skaffold / Tilt

`skaffold debug` automates the per-language debugger wiring + port-forward, so you
often don't even hand-edit the command/args.

```yaml
# skaffold.yaml
apiVersion: skaffold/v4beta11
kind: Config
build:
  artifacts:
    - image: myrepo/app
      docker: { dockerfile: Dockerfile, target: debug }   # build the debug target
deploy:
  helm:
    releases:
      - name: myapp
        chartPath: ./mychart
        namespace: dev
        createNamespace: true
        valuesFiles: [values-dev.yaml]
portForward:
  - { resourceType: deployment, resourceName: myapp, port: 5678, localPort: 5678 }
```

```bash
skaffold dev      # live build + deploy + logs, rebuild on save
skaffold debug    # same, plus launches debuggers and forwards their ports
```

Tilt equivalent (`Tiltfile`):
```python
docker_build('myrepo/app', '.', target='debug')
helm_resource('myapp', './mychart', namespace='dev', flags=['-f','values-dev.yaml'])
k8s_resource('myapp', port_forwards=['5678:5678', '8080:8080'])
```

---

## 7. Quick reference

### Debug ports & launch commands

| Language | Tool | Port | Command (in container) |
| --- | --- | --- | --- |
| Node | Inspector | 9229 | `node --inspect-brk=0.0.0.0:9229 app.js` |
| Python/Flask | debugpy | 5678 | `python -m debugpy --listen 0.0.0.0:5678 --wait-for-client -m flask run --no-reload` |
| Go | Delve | 40000 | `dlv --listen=:40000 --headless --api-version=2 exec /app` |
| Java | JDWP | 5005 | `-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005` |

### Debug-mode checklist (Helm dev overlay)
- [ ] `replicaCount: 1`
- [ ] Image = the **debug** target (symbols kept, debugger installed)
- [ ] Debug port added to container `ports`
- [ ] Liveness/readiness probes disabled (won't kill a paused process)
- [ ] `SYS_PTRACE` capability (required for Go/delve)
- [ ] `readOnlyRootFilesystem: false`, `runAsNonRoot: false` if the debugger needs it
- [ ] `kubectl port-forward` the debug port, then attach the IDE

### One-liner: switch a running release into debug
```bash
helm upgrade myapp ./mychart -n dev -f values-dev.yaml --reuse-values \
  && kubectl port-forward deploy/myapp 5678:5678 -n dev   # pick your port
```

### Tooling summary
| Concern | Recommended |
| --- | --- |
| In-cluster dev loop | Skaffold (+ Helm), or Telepresence/mirrord for local-process debug |
| Image build (no daemon) | BuildKit, kaniko (CI), Buildpacks, `ko` (Go), Jib (Java) |
| Code lint | Ruff (Py), golangci-lint (Go), ESLint/Biome (Node) |
| Manifest/chart lint | helm lint, kubeconform, kube-linter, hadolint, conftest |
| Glue | pre-commit + CI running all of the above |
