# Docker Field Manual

> model · build · compose · network · harden · supply chain · debug
> Generated 2026-09-23.

## Contents

- 00 · [Every recommendation, one page](#00-every-recommendation-one-page)
- 01 · [The model underneath](#01-the-model-underneath)
- 02 · [Daily CLI by intent](#02-daily-cli-by-intent)
- 03 · [Dockerfiles that behave](#03-dockerfiles-that-behave)
- 04 · [BuildKit, buildx and bake](#04-buildkit-buildx-and-bake)
- 05 · [Compose for real stacks](#05-compose-for-real-stacks)
- 06 · [Networking and storage](#06-networking-and-storage)
- 07 · [Runtime security: least privilege](#07-runtime-security-least-privilege)
- 08 · [Host and daemon hardening](#08-host-and-daemon-hardening)
- 09 · [Image supply chain](#09-image-supply-chain)
- 10 · [Running containers for real](#10-running-containers-for-real)
- 11 · [When it breaks](#11-when-it-breaks)
- 12 · [One-screen Docker reference](#12-one-screen-docker-reference)

---


<a id="00-every-recommendation-one-page"></a>

## 00 · Every recommendation, one page

*Every default this guide picks, with the reason and the chapter that defends it. Read this page and the chapter for whichever line you are about to disagree with.*

**Defaults are for when you have no reason to choose otherwise.** Where a line says "close call", the alternative is genuinely defensible and the tiebreaker is named. Chapter numbers are the file numbers used throughout the guide (01 model, 02 CLI, 03 Dockerfile, 04 buildx, 05 Compose, 06 network and storage, 07 runtime security, 08 daemon hardening, 09 supply chain, 10 runtime ops, 11 troubleshooting, 12 reference).

### Engine and tooling

| Decision | Pick | Why | Ch |
|---|---|---|---|
| Engine on a Fedora workstation | **Podman rootless**; rootful Docker only where a tool hard-requires the Docker API | No root daemon, user namespaces, SELinux `container_t` by default, Quadlet for services. Tiebreaker: can the tool point at `podman.socket`? If yes, Podman | 01, 07 |
| If you run Docker anyway | **Rootless Docker**, rootful daemon stopped, user out of the `docker` group | The `docker` group is passwordless root; rootless Docker removes that path only if the rootful one is gone | 07 |
| Image store | **containerd image store** (Docker 29 default for fresh installs) | Keeps multi-platform indexes and attestations locally; `--load` of multi-arch works | 01, 04 |
| Remote daemon access | **SSH context** (`docker context create --docker host=ssh://…`) | Reuses SSH keys; no TCP socket, no TLS PKI to run | 02, 08 |
| Switching daemons | **`DOCKER_CONTEXT` via direnv**, context in your prompt | `docker context use` is global and sticky, like a merged kubeconfig | 02 |
| Daily TUI | **lazydocker**; **dive** for image layers | One screen for containers, logs, stats and Compose; dive shows what each layer added | 02 |
| Debug a shell-less container | **Attach a tools container** (`--network container:X --pid container:X nicolaka/netshoot`) | Nothing changes in the target; `docker debug` isn't in Docker CE | 02, 11 |

### Build

| Decision | Pick | Why | Ch |
|---|---|---|---|
| Build tool | **docker buildx + `docker-bake.hcl`** | One BuildKit session, parallel targets, `--print` dry run, same file for local and CI. Compose v5 delegates to bake anyway | 04 |
| Dockerfile header | **`# syntax=docker/dockerfile:1`** + **`# check=error=true`** | Current frontend features on any daemon; build checks become failures | 03 |
| Lint | **`docker build --check`** *and* **hadolint** | `--check` understands heredocs and new syntax; hadolint adds ShellCheck and package rules but can't parse heredocs | 03 |
| Base: Python | **`python:3.14-slim`** pinned by digest, uv in the build stage | glibc wheels install as binaries; musl on alpine forces source builds | 03, 09 |
| Base: Go / Rust | **`gcr.io/distroless/static-debian13:nonroot`** | CA certs, tzdata, UID 65532, ~2 MB, no shell. `scratch` only if you supply those yourself | 03, 09 |
| Base: Node | **`node:24-slim`** — *close call* with `distroless/nodejs24-debian13` | Tiebreaker: native addons or a need for a shell → slim; neither → distroless | 03, 09 |
| Base: JVM | **`distroless/java25-debian13:nonroot`** | JRE only, no shell | 03, 09 |
| Base pinning | **`image:tag@sha256:INDEX_DIGEST`**, bumped by **Renovate** (`docker:pinDigests`) | Tags move; the index digest pins every platform; Renovate turns updates into reviewable MRs | 03, 09 |
| Build-time secrets | **`RUN --mount=type=secret`** (file or `env=`) | Never in a layer, history or cache key. `ARG`/`ENV` secrets are visible forever | 03, 09 |
| Dependency caching | **`RUN --mount=type=cache`** for the package manager's *download* cache | Fast rebuilds without caches in the image; never mount over the install target | 03 |
| Layer order | **Lockfile → install → source → build** | One changed source file must not reinstall every dependency | 03 |
| PID 1 | **Exec-form `ENTRYPOINT`/`CMD`**; `--init` / `init: true` when the app doesn't handle SIGTERM | Shell form swallows SIGTERM: ten-second stops and exit 137 | 03 |
| Image user | **Numeric UID** (`USER 10001:10001`, `65532` on distroless) | `runAsNonRoot` can only verify a numeric UID | 03, 07 |
| Multi-arch | **Cross-compile with `FROM --platform=$BUILDPLATFORM`**; native nodes next; QEMU last | QEMU is 5–20x slower and fails like an app bug | 04 |
| Local builder | **The default `docker` driver** (on the containerd store) | Exports `mode=max` cache and loads multi-arch images directly; no `--load` tar round-trip | 04 |
| CI cache | **Registry cache, `mode=max`**, read main + branch, write branch, `image-manifest=true` | `mode=min` caches only the final stage; cache mounts aren't exported | 04 |
| CI builder (GitLab) | **buildx client (`docker:29-cli`) → rootless `moby/buildkit` as a job service** | No privileged runner, and unlike `buildctl-daemonless` it runs bake. dind only if privileged runners already exist; kaniko is archived | 04 |
| Build attestations | **`--provenance=mode=max --sbom=true`** in CI | SLSA provenance and SPDX SBOM attached to the index; consumed by scanning and signing | 04, 09 |
| BuildKit GC | **Cap it** (`builder.gc.defaultMaxUsedSpace` in `daemon.json`; `defaultKeepStorage` is now a floor, not a cap) | The default policy on this machine allows ~710 GiB; 148 GB of cache had accumulated | 04, 10 |

### Compose

| Decision | Pick | Why | Ch |
|---|---|---|---|
| Compose version | **`docker compose` plugin** (v5 here; v2.20+ minimum) | The Python `docker-compose` v1 is dead; `version:` key is obsolete | 05 |
| File layout | **Production-shaped `compose.yaml`** + dev-only `compose.override.yaml` + `-f` for CI/prod | The base is what ships; the dev loop can't leak into prod | 05 |
| Project identity | **`name:` in the file** | Renaming the directory otherwise orphans volumes | 05 |
| Startup ordering | **`depends_on: condition: service_healthy`** / `service_completed_successfully` | Plain `depends_on` waits for "started", not "ready" | 05 |
| Scripted startup | **`docker compose up -d --wait`** | The Compose `kubectl wait`; never `sleep` | 05 |
| Dev loop | **`develop.watch`** (sync / sync+restart / rebuild) | Keeps the container self-contained; bind mounts drag UID and SELinux problems in | 05 |
| Runtime secrets | **`secrets:` + `*_FILE` env vars** | Values never appear in `docker inspect` | 05 |
| Optional services | **Profiles** for tools and debug UIs, never for environments | Environments are override files | 05 |
| Review | **`docker compose config`** before trusting a merge; `--lock-image-digests` for reproducible deploys | Shows exactly what interpolation and merging produced | 05 |
| Compose on Podman | **`podman compose` with the docker-compose provider** + `podman.socket` | Full spec fidelity; podman-compose lags | 05 |

### Network and storage

| Decision | Pick | Why | Ch |
|---|---|---|---|
| Port publishing | **`127.0.0.1:HOST:CONTAINER` on every publish** | Bare `-p` binds `0.0.0.0` and `[::]`, and Docker's DNAT bypasses firewalld | 02, 06, 08 |
| Loopback by default | **`host_binding_ipv4: 127.0.0.1` on user/Compose networks**, `"ip": "127.0.0.1"` in `daemon.json` for the default bridge | The daemon key only covers the default bridge | 06, 08 |
| Container networks | **User-defined bridge**, `internal: true` for backend tiers | Embedded DNS; the default bridge has none; internal networks have no egress | 06 |
| Address pools | **Pin `default-address-pools`** (e.g. `10.200.0.0/16`) | 172.16/12 defaults collide with VPNs and office LANs | 06, 08 |
| Firewall backend | **iptables** (default); nftables backend stays experimental in 29 | nftables mode has no `DOCKER-USER` and needs forwarding enabled by you | 06, 08 |
| Restricting LAN access | **`DOCKER-USER` rules** (plus `ip6tables` twins) | Evaluated before Docker's own accept rules; firewalld zones aren't | 06, 08 |
| Persistent data | **Named volumes**; bind mounts for dev source and host config only | Volumes bypass overlayfs, avoid UID/SELinux problems, back up cleanly | 06 |
| SELinux on bind mounts | **`:Z` for private data dirs, `:z` for shared**, never on home or system paths | Required under Podman and SELinux-enabled Docker; recursive relabel of `/home` breaks the host | 06, 07 |
| Volume backup | **Throwaway container + `tar`**; database-native dump for databases; restore into a *new* volume | Engine-agnostic; file copies of live databases are at best crash-consistent | 06, 10 |
| Registry credentials | **`credHelpers` per host** (glab, gcloud) + `credsStore: secretservice` for the rest | `auths` stores base64 passwords in plain text | 06 |
| Local registry | **`registry:3` on `127.0.0.1:5000`** | Loopback is insecure-by-default allowed; Harbor or Zot for anything shared | 06 |

### Runtime, security and operations

| Decision | Pick | Why | Ch |
|---|---|---|---|
| Container hardening baseline | **`--cap-drop ALL`**, **`no-new-privileges`**, **non-root**, **`--read-only` + tmpfs**, builtin seccomp | Removes the privileges a container inherits by default; each is cheap | 07 |
| SELinux for Docker CE | **`"selinux-enabled": true`** | Docker CE containers here run `spc_t`, i.e. unconfined; `:z`/`:Z` are no-ops until this is on | 01, 06, 08 |
| Hardened daemon | **The `daemon.json` in chapter 08** (`live-restore`, `no-new-privileges`, `icc: false`, `log-driver: local`, `init: true`, address pools) | Makes forgotten flags fail closed | 08 |
| Memory | **Always set `--memory`**, with `--memory-swap` equal to it | Memory isn't compressible; swap hides leaks as latency | 01, 07, 10 |
| CPU | **Drop CPU limits for latency-sensitive services**; use `cpu.weight` | `cpu.max` throttles even on an idle host | 07, 10 |
| PIDs | **`--pids-limit`** (≈256) | Stops fork bombs; Docker's default is unlimited | 07 |
| Log driver | **`local`** on Docker (rotated, compressed); **`journald`** for Podman/Quadlet | The default `json-file` has no rotation and fills `/var/lib/docker` | 02, 10 |
| Supervising services | **systemd via Podman Quadlet**; `restart: unless-stopped` for Docker dev services | Quadlet gives restart, dependencies, logging and auto-update with rollback | 10 |
| Image updates | **Renovate bumps the digest, CI deploys**; `podman auto-update` only for tags you control | Updates become reviewable, revertible MRs; Watchtower needs the socket | 10 |
| The Docker socket | **Never mount it**; a verb/path-restricted socket proxy if a tool insists | `:ro` does not restrict API calls; socket access is root | 07 |
| Scanner | **Trivy** (pinned by digest), gating on `--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1` | A gate that fires on everything gets disabled; Grype as the second opinion | 09 |
| Signing | **cosign, signing the digest** — keyless in connected CI, **key pair for air-gapped** | Signing a tag signs whatever it pointed at that second; keyless needs Rekor/Fulcio | 09 |
| Prune policy | **Containers >24 h, images >7 days (`-a --filter until=168h`), build cache capped by size, volumes never automatically** | 384 GB was reclaimable on this machine; volume pruning deletes data | 02, 10 |
| Daemon audit | **docker-bench-security** + auditd rules on the socket and binaries | Evidence, not assumptions | 08 |

### Positions worth arguing about

These are opinions, not consensus. Each is stated with its reason so you can overrule it deliberately.

| Position | Reason |
|---|---|
| **Podman rootless is the Fedora default; Docker is the exception you justify.** | The biggest Docker risk isn't in a container; it's the root-equivalent socket and the group that reaches it. Podman removes both and adds SELinux confinement by default |
| **Keep `:z`/`:Z` in every file even on Docker CE, where they do nothing.** | The same Compose file then works on Podman, on Fedora's `moby-engine`, and after you turn SELinux on for Docker. A no-op today is a `Permission denied` avoided tomorrow |
| **The base Compose file is production-shaped; the dev loop is the override.** | `read_only`, dropped capabilities and limits in the base mean the stack you test is the stack you ship. The override relaxes; it never hardens |
| **`--mount` in anything shared, `-v` only at the prompt.** | `-v` with a typo silently creates an empty root-owned directory and runs anyway; `--mount` fails |
| **Cross-compile or don't build multi-arch.** | QEMU-emulated compiles are slow and produce failures that look like app bugs. If a stack can't cross-compile, add a native arm64 node rather than eat emulation |
| **One `docker-bake.hcl`, no build scripts.** | Scripts that loop `docker build` lose BuildKit's shared session, have no dry run, and drift from what CI does |
| **Healthchecks check the process, not its dependencies.** | A healthcheck that dials the database marks every service unhealthy on one database blip, and in Compose that cascades through `depends_on` |
| **Pin apt/apk packages? No. Pin the base digest and let Renovate move it.** | Package pins rot within weeks as mirrors drop old versions; a digest-pinned base plus scheduled bumps is reproducible *and* maintainable (hence ignoring hadolint DL3008) |
| **No `sleep` in any script that waits for a container.** | `up --wait`, `condition: service_healthy`, or a bounded retry loop. A sleep is a bet on machine speed |
| **`docker compose down -v` does not belong in a README.** | It is "reset" to the author and "deleted the database" to the reader |
| **Treat any exposed 2375 as a compromise.** | Rebuild, don't clean. There is no reliable way to prove nothing ran |

### One-way doors

Everything else in this guide is reversible. These are not, or are only reversible at real cost.

| Door | What it costs | Ch |
|---|---|---|
| **`docker system prune -a --volumes`** / **`docker volume prune -a`** | Every unused image and all build cache (hundreds of GB of re-pulls and rebuilds), and with `volume prune -a`, **named volumes of stopped stacks** — database data. No trash, no undo | 02, 10 |
| **`docker compose down -v`** | The project's named volumes. Two characters away from a safe command | 05 |
| **Adding a user to the `docker` group** | Grants passwordless root with no sudo log. Removing them later doesn't undo anything they already did; it is `wheel` + `NOPASSWD` in practice | 07 |
| **Exposing the daemon socket over TCP** (`-H tcp://0.0.0.0:2375`) | An unauthenticated remote root shell, found by scanners within minutes. Minutes of exposure mean rebuilding the host | 08 |
| **Publishing on `0.0.0.0`** on a machine that joins untrusted networks | firewalld doesn't filter Docker-published ports; everyone on the segment reaches the service. For a database with a default password, that exposure is the incident | 02, 06 |
| **`:Z`/`:z` on a home or system directory** | Recursive SELinux relabel of the host tree; logins and services fail on AVC denials until you find and `restorecon` the right path | 06 |
| **Mounting `docker.sock` into a container** | Any RCE in that container is host root, permanently, for as long as it runs | 07 |
| **Switching image stores** (classic ↔ containerd) | Existing images and containers become invisible (not deleted); disk is double-used until you clean the old store | 01 |
| **Enabling `selinux-enabled` on a Docker host with existing bind mounts** | Reversible, but every bind mount without `:z`/`:Z` starts failing with `Permission denied` at once | 08 |
| **`default-address-pools` and network CIDRs** | Changing later means recreating every network and the containers on them | 06, 08 |
| **`docker buildx rm` on a CI builder** | Deletes its cache volume; the next builds are cold | 04 |
| **`podman system reset`** | Deletes all Podman containers, images, volumes and networks for that user | 02 |

### If you're starting today, in order

1. **Chapter 01** — read the model. Twenty minutes that make every later chapter vocabulary.
2. **Chapter 07** — decide the engine: rootless Podman as the default, rootless Docker where a tool needs it. Get out of the `docker` group.
3. **Chapter 08** — apply the hardened `daemon.json` to any rootful Docker you keep: SELinux on, `local` logs, address pools, `live-restore`.
4. **Chapter 02** — install the zsh block and lazydocker; run `dexposed` and fix every `0.0.0.0` publish.
5. **Chapter 03** — one service: multi-stage Dockerfile, digest-pinned base, cache and secret mounts, non-root, exec-form entrypoint. `docker build --check` and hadolint clean.
6. **Chapter 04** — a `docker-bake.hcl` for it; `--print` it; build multi-arch by cross-compiling.
7. **Chapter 05** — a production-shaped `compose.yaml` with healthchecks and `depends_on` conditions, a dev override with `develop.watch`, `up --wait`.
8. **Chapter 06** — user-defined networks with loopback binding, named volumes, `:Z` where Podman needs it, a tested volume backup and restore.
9. **Chapter 09** — Trivy gate, SBOM, cosign signature on the digest, Renovate keeping digests fresh.
10. **Chapter 04 again** — move the build into GitLab CI with the rootless BuildKit service and registry cache.
11. **Chapter 10** — run anything long-lived as a Quadlet unit; put the prune policy on a timer.
12. **Chapter 11** — read it once before you need it, so you know where the decision trees are.


---


<a id="01-the-model-underneath"></a>

## 01 · The model underneath

*A container is not a thing. It is an ordinary Linux process that the kernel has been told to lie to: about its filesystem, its PID, its network and its resource budget. Every Docker behaviour that surprises you is one of those lies showing through.*

Everything later in this guide is downstream of five ideas. Get them solid and the rest is vocabulary.

1. **A container is a process** with namespaces (what it can see) and cgroups (what it can use) applied.
2. **An image is a content-addressed tree of JSON and tarballs.** The digest is the identity; the tag is a mutable pointer.
3. **The filesystem is layers stacked by overlayfs**, with one writable layer on top that dies with the container.
4. **Docker is a stack of daemons** — dockerd, containerd, a shim, runc — and knowing which one owns a failure tells you where to look.
5. **Podman is the same kernel mechanics without the long-lived daemon**, which changes the security model more than the command line.

### What a container actually is

Run a container and look at it from the host. It is just a process.

```bash
docker run -d --name sleeper --rm alpine:3.22 sleep 3600
PID=$(docker inspect -f '{{.State.Pid}}' sleeper)
ps -o pid,user,cmd -p "$PID"          # a normal host process
ls -l /proc/$PID/ns                     # its namespace handles
cat /proc/$PID/cgroup                   # its cgroup path
sudo nsenter -t "$PID" -m -u -n -p -i sh   # "exec" without docker
docker rm -f sleeper
```

There is no container object in the kernel. There is a process whose `/proc/PID/ns/*` links point at namespaces other than the host's, sitting in a cgroup with limits set, with a root filesystem that `pivot_root` swapped to an overlay mount, with some capabilities dropped and a seccomp filter attached. **That set of settings is the container.**

```text
                    host kernel (one, shared)
 ┌─────────────────────────────────────────────────────────────┐
 │  process 48213  "python app.py"                              │
 │                                                              │
 │  namespaces ─── what it can SEE                              │
 │    mnt  → its own mount table, root = overlay mount           │
 │    pid  → it believes it is PID 1                            │
 │    net  → its own interfaces, routes, iptables, ports         │
 │    uts  → its own hostname                                    │
 │    ipc  → its own SysV IPC / POSIX mqueues                    │
 │    cgroup → sees its cgroup as "/"                            │
 │    user → (off by default in Docker; on in rootless/Podman)   │
 │                                                              │
 │  cgroup v2 ──── what it can USE                              │
 │    memory.max  cpu.max  pids.max  io.max                      │
 │                                                              │
 │  security ───── what it may DO                               │
 │    capabilities (14 of ~41 kept)  seccomp  SELinux/AppArmor   │
 └─────────────────────────────────────────────────────────────┘
```

Consequences you will hit:

- **The kernel is shared.** A container cannot run a different kernel, cannot load a module it lacks, and a kernel exploit is a host exploit. This is the whole reason VMs (and Kata/gVisor) exist.
- **`uname -r` inside the container prints the host kernel.** "It works on my laptop" with a 7.x kernel and fails on a 5.x CI runner is a real class of bug for anything touching io_uring, eBPF or new syscalls.
- **Root in the container is root on the host** unless a user namespace remaps it. The namespaces hide things; they do not reduce the UID. Capabilities, seccomp and SELinux are what actually keep container root from being host root.

#### Namespaces, one line each

| Namespace | Isolates | Docker default | You notice it when |
|---|---|---|---|
| `mnt` | Mount table | New | Bind mounts, `--read-only`, overlay root |
| `pid` | PID numbering | New | Your app is PID 1 and ignores SIGTERM |
| `net` | Interfaces, routes, ports, netfilter | New (bridge) | `--network host` removes it |
| `uts` | Hostname, domainname | New | `--hostname` |
| `ipc` | SysV IPC, `/dev/shm` | New (private) | Postgres/Chrome complain about tiny `/dev/shm` (64 MB default) |
| `cgroup` | View of `/sys/fs/cgroup` | New (cgroupns private on v2) | Tools inside see their own tree |
| `user` | UID/GID mapping | **Not used** (rootful) | Rootless Docker, `--userns-remap`, Podman rootless |
| `time` | Monotonic/boot clocks | Not used | Almost never |

Share a namespace deliberately with `--pid=host`, `--network=container:NAME`, `--ipc=shareable`. **Sharing the net namespace between containers is exactly what a Kubernetes pod or a Podman pod is.**

#### cgroups v2: the budget

Fedora has been cgroup v2 only since F31, and `docker info` here reports `Cgroup Driver: systemd`, `Cgroup Version: 2` (**verified**). With the systemd driver, each container is a transient scope unit.

```bash
CID=$(docker run -d --rm --memory 256m --cpus 0.5 --pids-limit 100 alpine:3.22 sleep 600)
systemctl status "docker-${CID}.scope" --no-pager | head -5
cat /sys/fs/cgroup/system.slice/docker-${CID}.scope/memory.max   # 268435456
cat /sys/fs/cgroup/system.slice/docker-${CID}.scope/cpu.max      # 50000 100000
cat /sys/fs/cgroup/system.slice/docker-${CID}.scope/pids.max     # 100
cat /sys/fs/cgroup/system.slice/docker-${CID}.scope/memory.events  # oom_kill counter
docker rm -f "$CID"
```

| Flag | cgroup v2 file | Behaviour at the limit |
|---|---|---|
| `--memory 256m` | `memory.max` | Kernel OOM-kills a process in the cgroup. Exit **137**, `.State.OOMKilled=true` |
| `--memory-reservation` | `memory.low` | Soft floor; reclaimed last under host pressure |
| `--cpus 0.5` | `cpu.max` (`50000 100000`) | Throttled — slow, never killed |
| `--cpu-shares` | `cpu.weight` | Relative weight only under contention |
| `--pids-limit 100` | `pids.max` | `fork()` fails with EAGAIN; fork bombs stop here |
| `--device-read-bps` etc. | `io.max` | Throttled I/O |

> **Gotcha.** The default memory limit is **none**. A leaking container grows until the host OOM killer picks a victim, and on a workstation that victim may be your browser or `dockerd` itself. Set `--memory` (or `mem_limit` / `deploy.resources.limits.memory` in Compose) on anything long-running.

> **Gotcha.** Runtimes that size themselves from host resources read the host, not the cgroup, unless they are cgroup-aware. The JVM (since 10) and Go 1.25+ `GOMAXPROCS` respect cgroup limits; Node sizes its heap from the cgroup memory limit but `os.cpus()` still reports host cores. Python multiprocessing pools, `nproc`-based build scripts and many worker-count heuristics still see all 24 cores.

#### Capabilities, seccomp, LSM

Rootful Docker keeps 14 capabilities by default (`CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `FSETID`, `KILL`, `SETGID`, `SETUID`, `SETPCAP`, `SETFCAP`, `NET_BIND_SERVICE`, `NET_RAW`, `SYS_CHROOT`, `MKNOD`, `AUDIT_WRITE`) and drops the rest, including `SYS_ADMIN`. The builtin seccomp profile blocks around 40–60 syscalls (`mount`, `kexec_load`, `bpf`, `unshare` of user ns, …). `docker info` here shows `seccomp Profile: builtin` and `cgroupns` (**verified**).

**SELinux is the one that surprises Fedora users.** Docker CE (the `docker-ce` package from download.docker.com, which is what is installed here) ships with `selinux-enabled` **off**. Result on this machine (**verified** with `ps -o label=`): unprivileged containers run as `spc_t` — the "super privileged container" type, effectively unconfined by SELinux. Fedora's own `moby-engine` package and Podman both enable it, so their containers run as `container_t` with per-container MCS categories. The *Networking and storage* chapter covers what this does to `:z`/`:Z`; the security chapter covers turning it on.

```bash
docker info --format '{{.SecurityOptions}}'      # no "name=selinux" → not confining
docker run -d --rm --name t alpine:3.22 sleep 60
ps -o label= -p "$(docker inspect -f '{{.State.Pid}}' t)"
podman run -d --rm --name t2 alpine:3.22 sleep 60
ps -o label= -p "$(podman inspect -f '{{.State.Pid}}' t2)"   # container_t:s0:cX,cY
```

### The Docker daemon stack

`docker` the CLI is a thin REST client. The work happens four processes down.

```text
 docker CLI ──HTTP over /var/run/docker.sock──▶ dockerd
   (you)                                          │  API, networking (bridge, iptables/nftables),
                                                  │  volumes, logging drivers, build (BuildKit embedded),
                                                  │  image pulls/pushes
                                                  │
                                    gRPC /run/containerd/containerd.sock
                                                  ▼
                                             containerd
                                                  │  image content store, snapshotters (overlayfs),
                                                  │  container + task lifecycle
                                                  │
                                           fork/exec per container
                                                  ▼
                                   containerd-shim-runc-v2   (one per container, long-lived)
                                                  │  owns stdio, reaps, reports exit code,
                                                  │  keeps the container alive if containerd/dockerd restart
                                                  │
                                              exec once
                                                  ▼
                                                runc    (creates namespaces, cgroup, pivot_root,
                                                  │      applies seccomp/caps, execs your process, EXITS)
                                                  ▼
                                          your process (PID 1 in its pid ns;
                                          parent on the host = the shim)
```

What each layer is responsible for, and therefore where to look:

| Symptom | Layer | Where to look |
|---|---|---|
| `Cannot connect to the Docker daemon` | CLI ↔ dockerd | `systemctl status docker docker.socket`, `docker context show`, `$DOCKER_HOST` |
| Port publish or DNS broken | dockerd (libnetwork) | `nft list ruleset`, `iptables -t nat -S DOCKER`, `journalctl -u docker` |
| Image pull, snapshot, "no space left" | containerd | `journalctl -u containerd`, `docker system df` |
| `OCI runtime create failed` | runc | The message after it: usually a bad mount, missing binary, or seccomp/LSM denial |
| Exit 137 with no OOMKilled | your process / the kernel | Something sent SIGKILL: `docker stop` timeout, `docker kill`, host OOM |

Two design consequences:

- **The shim is why containers survive a daemon restart** — with `"live-restore": true` in `daemon.json`, `systemctl restart docker` leaves running containers running. `docker info` here reports `Live Restore Enabled: false` (**verified**), which is the default.
- **Everything runs as root under dockerd**, and anyone who can write to `/var/run/docker.sock` can ask dockerd to bind-mount `/` into a container. That is why the docker group is root-equivalent (see the one-way doors in *Every recommendation*).

```bash
systemctl status docker containerd --no-pager | grep -E 'Active|Main PID'
pstree -p "$(pgrep -x containerd)" | head      # the shims hang off containerd's scope
docker info --format '{{.DefaultRuntime}} {{.Driver}} {{.CgroupDriver}}'
```

#### The containerd image store (Docker 29 default)

> **Version-sensitive.** Docker Engine 29 made the **containerd image store** the default for *fresh* installs; upgraded hosts keep the old graph-driver store until you switch. Check yours: `docker info` shows `Storage Driver: overlayfs` with `driver-type: io.containerd.snapshotter.v1` on the containerd store (this machine, **verified**), versus `Storage Driver: overlay2` on the classic store.

What changes when you are on the containerd store:

| Behaviour | Classic `overlay2` store | containerd store |
|---|---|---|
| Multi-platform images locally | Only the host platform survives `--load` | Whole index kept; `docker image ls --tree` shows platforms |
| Attestations (SBOM, provenance) | Dropped on load | Kept alongside the image |
| `docker build` default output | Loads single-platform image | Can load multi-platform image directly |
| Disk | Unpacked layers only | Compressed blobs **and** unpacked snapshots, so often larger |
| Where bytes live | `/var/lib/docker/overlay2` | `/var/lib/containerd` (content + snapshots) |
| Image ID shown | Config digest | Manifest/index digest |

> **Gotcha.** Switching stores (`"features": {"containerd-snapshotter": true}` in `daemon.json`, or back) makes your existing images and containers **invisible** — not deleted, just in the other store. People "lose" 200 GB of images this way and then pull them all again while the old ones still sit on disk.

### Images: a content-addressed tree

An image is not a file. It is a small graph of JSON documents and tar blobs, each named by the SHA-256 of its bytes. Change one byte anywhere and every digest above it changes.

```text
 registry.example.com/team/app:1.4.2          ← tag: a mutable pointer, lives only in the registry
             │
             ▼
 IMAGE INDEX   sha256:9f2c…   application/vnd.oci.image.index.v1+json
   │   (a.k.a. "manifest list" / "fat manifest")
   ├── manifest for linux/amd64   sha256:a11e…
   ├── manifest for linux/arm64   sha256:b72d…
   └── attestation manifest       sha256:c3e0…   platform unknown/unknown
          (vnd.docker.reference.type=attestation-manifest → SBOM, provenance)
             │
             ▼
 IMAGE MANIFEST  sha256:a11e…   application/vnd.oci.image.manifest.v1+json
   ├── config  sha256:44fa…   application/vnd.oci.image.config.v1+json
   │     { "architecture":"amd64", "config":{ "Env":[…], "Entrypoint":[…], "User":"65532" },
   │       "rootfs":{ "diff_ids":[ uncompressed layer digests ] }, "history":[…] }
   ├── layer   sha256:1d0b…   …image.layer.v1.tar+gzip   (base OS)
   ├── layer   sha256:77ca…   …image.layer.v1.tar+gzip   (pip install)
   └── layer   sha256:e901…   …image.layer.v1.tar+gzip   (COPY app/)
```

The rules that fall out of this:

- **A digest is immutable and a tag is not.** `app:1.4.2` can be re-pushed to point at different bytes; `app@sha256:9f2c…` cannot. Pinning by digest is the only way to guarantee what runs. Pin the **index** digest (so every platform resolves), not a per-platform manifest digest.
- **Layers are shared by digest.** Two images built `FROM python:3.14-slim` store the base layers once, locally and in the registry. This is why base-image choice and layer ordering matter for disk and pull time.
- **Deleting a file in a later layer does not shrink the image.** The earlier layer still contains the bytes; the later one just adds a "whiteout" marker. Secrets `COPY`d in and `rm`'d later are still in the image. See *Dockerfiles that behave* for secret mounts.
- **Compressed and uncompressed digests differ.** The manifest lists compressed blob digests; the config's `diff_ids` are uncompressed. Recompressing (gzip → zstd) changes the manifest digest while the filesystem is identical.

Look at the real thing:

```bash
docker buildx imagetools inspect python:3.14-slim                 # the index, per-platform manifests
docker buildx imagetools inspect python:3.14-slim --raw | jq .    # raw index JSON
docker buildx imagetools inspect python:3.14-slim \
  --format '{{json .Manifest}}' | jq '.manifests[] | {platform, digest}'
skopeo inspect --raw docker://docker.io/library/python:3.14-slim | jq .mediaType
skopeo inspect docker://docker.io/library/python:3.14-slim | jq '{Digest, Layers}'
docker image inspect python:3.14-slim --format '{{json .RootFS.Layers}}' | jq .
docker image history --no-trunc python:3.14-slim                 # the instruction per layer
```

> **Note.** `docker buildx imagetools` talks to the registry directly and never pulls. It is the fastest way to answer "which platforms does this tag have" and "what digest is `:latest` today" without touching local disk.

#### Image vs container

```text
     IMAGE (read-only, shared)                CONTAINER (one per `docker run`)
 ┌──────────────────────────┐          ┌──────────────────────────────┐
 │ layer 3  COPY app/        │          │ writable layer (upperdir)     │ ← dies with `docker rm`
 │ layer 2  pip install      │ ◀─────── │ + config: env, cmd, mounts,   │
 │ layer 1  debian base      │  lower   │   network, restart policy     │
 └──────────────────────────┘   dirs    │ + a process (maybe)           │
                                        └──────────────────────────────┘
```

A container is image layers + a thin writable layer + runtime config + (while running) a process. **Stopped containers keep their writable layer and config** until `docker rm`, which is why `docker ps -a` fills up and why `--rm` should be your habit for anything interactive.

### Layers and overlayfs

The root filesystem you see inside a container is an overlay mount: the image layers are read-only `lowerdir`s, and the container gets one `upperdir`.

```text
  what the process sees  ──▶  merged/        /etc/app.conf  /usr/bin/python  /tmp/new.txt
                                ▲
                  overlayfs     │  lookup: upper first, then lowers top-down
                                │
  upperdir (container, rw)  ─── /tmp/new.txt   /etc/app.conf (copied up on first write)
  lowerdir 3 (COPY app/)    ─── /app/...
  lowerdir 2 (pip install)  ─── /usr/local/lib/python3.14/...
  lowerdir 1 (debian base)  ─── /etc/app.conf  /usr/bin/...  /etc/passwd
```

Semantics worth knowing:

| Operation | What overlayfs does | Cost |
|---|---|---|
| Read a file | First layer (top-down) that has it wins | Free |
| First write to a lower file | **Copy-up**: whole file copied to upper, then modified | Proportional to file size, not the write |
| Delete a lower file | Whiteout char device in upper | Bytes stay in the lower layer |
| Rename a lower directory | Copy-up of the directory (redirect_dir) | Can be slow on big trees |
| `fsync`-heavy writes | Goes to upper on the host fs | Fine, but slower than a volume on some fs |

**Never put a database's data directory in the container's writable layer.** Copy-up on a multi-GB file on first write, no persistence across `docker rm`, and `docker system df` shows it as container size you cannot easily reclaim. Use a volume — volumes bypass overlayfs entirely.

```bash
docker run -d --name ov --rm alpine:3.22 sleep 300
docker inspect ov --format '{{json .GraphDriver}}' | jq .   # classic store: LowerDir/UpperDir/MergedDir
findmnt -t overlay | head -3                                # the live overlay mounts
docker diff ov                                              # A/C/D against the image
docker rm -f ov
```

> **Note.** On the containerd store, `.GraphDriver` may be empty or report the snapshotter; the overlay mount still exists and `findmnt -t overlay` shows it. `docker diff` works on both.

### Podman: same kernel, different shape

Podman uses the same OCI runtime model (crun by default on Fedora, runc optional), the same images, the same namespaces and cgroups. What it removes is the long-lived root daemon.

```text
   DOCKER (rootful)                               PODMAN (rootless, default on Fedora)

 you ─▶ docker CLI                              you ─▶ podman  (fork/exec, no daemon)
          │ socket (root-owned)                           │
          ▼                                               │  runs as YOUR uid, in a user namespace
       dockerd (root, always on)                           │  where you are "root" (uid 0 → 1001)
          ▼                                               │  and uids 1..65536 → /etc/subuid range
       containerd (root)                                  ▼
          ▼                                            conmon   (per container; the shim equivalent)
       shim ─▶ runc ─▶ process (host root)                 ▼
                                                        crun ─▶ process (host uid 1001 or subuid)
   parent of containers: dockerd's shims              parent of containers: conmon, under your
   survives your logout                               systemd user session (enable linger for services)
```

| Aspect | Docker (rootful) | Podman (rootless) |
|---|---|---|
| Daemon | dockerd + containerd, root | None; `podman.socket` optional for API clients |
| Container root = | Host root | Your UID (via user namespace) |
| Networking | Bridge + iptables/nftables | `pasta` (rootless), netavark for bridges |
| Binding ports < 1024 | Yes | No, unless `net.ipv4.ip_unprivileged_port_start` lowered |
| SELinux | Off in docker-ce | `container_t` + MCS by default |
| Image storage | `/var/lib/docker` / `/var/lib/containerd` | `~/.local/share/containers/storage` |
| Service management | Restart policies in dockerd | systemd via **Quadlet** `.container` units |
| Multi-container unit | Compose project | **Pod** (shared net/ipc/uts, infra container) or Compose |
| Kubernetes YAML | No | `podman kube play` / `podman kube generate` |

`podman info` on this machine reports rootless `true`, network backend `netavark`, rootless network command `pasta`, graph driver `overlay`, cgroups `v2`, SELinux `true` (**verified**).

#### Rootless: what the user namespace does

```bash
podman unshare cat /proc/self/uid_map
#         0       1001          1        ← container uid 0 = you
#         1     524288      65536        ← container uids 1.. = your subuid range
grep "$USER" /etc/subuid /etc/subgid
podman run --rm alpine:3.22 id                # uid=0(root) — inside
podman run -d --rm --name u alpine:3.22 sleep 60
ps -o user,pid,cmd -p "$(podman inspect -f '{{.State.Pid}}' u)"   # your user — outside
```

> **Gotcha.** Files a rootless container writes as its uid 1000 land on the host owned by `524288+999`. Bind-mounting your source tree into a container that runs as a non-root user gets you permission errors or root-owned files you can't delete. Fixes: `--userns=keep-id` (maps your UID to the same UID inside), `podman unshare chown`, or `:U` on the volume to chown it to the container user.

#### Pods

A Podman pod is a Kubernetes pod on one host: an **infra container** holds the network, IPC and UTS namespaces; the other containers join them and talk over `localhost`.

```bash
podman pod create --name web -p 127.0.0.1:8080:80
podman run -d --pod web --name app  docker.io/library/nginx:1.29-alpine
podman run -d --pod web --name side docker.io/library/alpine:3.22 sleep infinity
podman exec side wget -qO- http://localhost:80 | head -3
podman pod ps; podman ps --pod
podman kube generate web > web.yaml          # emits a Pod manifest
podman pod rm -f web
podman kube play web.yaml                    # recreate from YAML
podman kube down web.yaml
```

Ports are published on the **pod**, not the containers, exactly as with a Kubernetes pod behind a hostPort.

### The mental model, compressed

| Question | Answer |
|---|---|
| What is running? | A process. `ps` on the host sees it. |
| Why can't it see my files? | mount namespace + overlay root. Mount them in. |
| Why can it still hurt the host? | Shared kernel; root is root without userns; caps/seccomp/LSM are the real fence. |
| Why did it die with 137? | SIGKILL: OOM (check `.State.OOMKilled`) or a stop timeout. |
| Why is my image huge? | Every layer is additive; deletes don't shrink. |
| What is `:latest`? | Whatever someone pushed last. Use the digest. |
| Who owns my container when dockerd restarts? | The shim. With live-restore, it keeps running. |
| Why is Podman "safer"? | No root daemon, user namespaces, SELinux on by default. Same kernel attack surface otherwise. |

### Traps

- **Thinking a container is a VM.** No separate kernel, no separate boot, no init unless you add one (`--init`).
- **Trusting tags.** Tags move. `FROM`, `image:` and deploy manifests should carry digests (Renovate keeps them fresh).
- **Deleting secrets in a later layer.** They are still in the earlier layer. `docker history` and `dive` will show them.
- **No memory limit.** The default is unbounded. The host OOM killer does not respect your priorities.
- **Assuming SELinux protects Docker containers on Fedora.** With docker-ce defaults, containers run `spc_t`. Podman and `moby-engine` do confine; docker-ce doesn't until you enable it.
- **Switching image stores without planning.** Existing images vanish from view, not from disk.
- **Assuming docker group is "just convenience".** It is passwordless root.


---


<a id="02-daily-cli-by-intent"></a>

## 02 · Daily CLI by intent

*Twenty flags do ninety percent of the work, and three of them (-p without an address, -v with a typo'd path, no --rm) cause most of the mess. Learn the CLI by what you are trying to do, and let --format and inspect replace grep.*

Every command in this chapter was checked against `docker <cmd> --help` on Docker 29.8.1. Podman accepts nearly all of them verbatim (`alias docker=podman` works for daily use); differences are called out.

### Run a container

#### The flags that matter

| Flag | Does | Use it when |
|---|---|---|
| `--rm` | Delete the container (and its anonymous volumes) on exit | **Every interactive or one-shot run.** Without it, `ps -a` fills with corpses |
| `-d` | Detach; print the ID | Services |
| `-it` | Interactive + TTY | Shells. Omit `-t` when piping output (TTY mangles `\n` to `\r\n`) |
| `--name NAME` | Stable name instead of `quirky_turing` | Anything you will `exec`/`logs` later |
| `--init` | Run `docker-init` (tini) as PID 1 | Your process doesn't reap zombies or handle SIGTERM (most shells, Node, Python without handlers) |
| `-e KEY=VAL` / `-e KEY` | Set env / pass through from your shell | Single values; `-e KEY` avoids the value in shell history |
| `--env-file FILE` | Read `KEY=VAL` lines | Many vars. **No quotes processing, no interpolation** — quotes become part of the value |
| `-p 127.0.0.1:8080:80` | Publish container 80 on host loopback 8080 | **Default form for dev.** Bare `-p 8080:80` binds `0.0.0.0` *and* `[::]` |
| `--mount type=bind,src=…,dst=…` | Bind mount, errors if src is missing | Scripts and anything important |
| `-v SRC:DST[:opts]` | Same, terser | Interactive; see the gotcha below |
| `--read-only` | Root filesystem read-only | Production-shaped runs; pair with `--tmpfs /tmp` |
| `--user 1000:1000` | Run as that UID:GID | Images that default to root; matching host file ownership |
| `--memory 512m --cpus 1` | cgroup limits | Anything long-running |
| `--restart unless-stopped` | dockerd restarts it | Long-lived services on a workstation |
| `--pull always` | Re-resolve the tag before run | Moving tags you actually want fresh |
| `--platform linux/arm64` | Run a foreign arch (via QEMU) | Testing multi-arch images; needs binfmt |
| `--network NAME` | Attach to a user-defined network | Container-to-container by name |
| `--entrypoint sh` | Override ENTRYPOINT | Debugging an image whose entrypoint exits immediately |

A sane dev-service invocation:

```bash
docker run -d --name pg \
  --restart unless-stopped \
  --memory 1g \
  -e POSTGRES_PASSWORD \
  -p 127.0.0.1:5432:5432 \
  --mount type=volume,src=pgdata,dst=/var/lib/postgresql \
  postgres:18-alpine
```

A production-shaped one-off, to check an image survives hardening before it reaches a cluster:

```bash
docker run --rm -it \
  --read-only --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --user 65532:65532 \
  --cap-drop ALL --security-opt no-new-privileges \
  --memory 256m --pids-limit 200 \
  -p 127.0.0.1:8080:8080 \
  IMAGE
```

If it starts under those flags, it will start under a restricted Kubernetes PodSecurity profile.

> **Gotcha.** `-p 8080:80` publishes on **every interface**, and Docker's DNAT rules run before firewalld's filtering, so the port is reachable from your LAN (or café Wi-Fi) whatever your firewall zone says. **Always write `-p 127.0.0.1:HOST:CONTAINER`** unless you mean it. The daemon's `"ip": "127.0.0.1"` setting only changes the default for the **default bridge**, not user-defined or Compose networks. Full mechanics in *Networking and storage*.

> **Gotcha.** `-v ./data:/data` with a path that doesn't exist **silently creates an empty root-owned directory** on the host and mounts that. `--mount type=bind` fails loudly instead: `invalid mount config: bind source path does not exist`. And `-v data:/data` (no `./` or `/`) is a *named volume* called `data`, not your directory.

#### -v vs --mount

| | `-v` / `--volume` | `--mount` |
|---|---|---|
| Missing bind source | Creates empty dir (root-owned) | **Error** |
| Syntax | Positional `src:dst:opts` | `key=value` pairs, self-describing |
| tmpfs | No (use `--tmpfs`) | `type=tmpfs,dst=/x,tmpfs-size=64m` |
| SELinux `:z`/`:Z` | Yes | No equivalent key; use `-v` for relabel |
| Volume subpath | No | `volume-subpath=…` |
| Recommendation | Interactive | **Scripts, docs, anything shared** |

```bash
--mount type=bind,src="$PWD",dst=/src,readonly
--mount type=volume,src=cache,dst=/root/.cache
--mount type=tmpfs,dst=/run,tmpfs-size=16m
-v "$PWD":/src:ro,Z            # Podman / SELinux-enabled daemon: private relabel
```

#### Pick the right --restart

| Policy | Restarts after crash | After `docker stop` + daemon restart | Use |
|---|---|---|---|
| `no` (default) | No | No | One-shots |
| `on-failure[:N]` | On non-zero exit, N times | No | Batch jobs that may flake |
| `unless-stopped` | Yes | **No** (respects your stop) | **Workstation services** |
| `always` | Yes | Yes | Rarely what you want; resurrects things you stopped |

> **Note.** In Podman, restart policies only apply while something is watching. For containers that must survive a reboot, generate a Quadlet unit instead (covered in the runtime chapter). `podman generate systemd` is deprecated.

### Get inside a running container

```bash
docker exec -it NAME sh                        # bash may not exist; sh nearly always does
docker exec -it -u 0 NAME sh                   # as root, even if the image sets USER
docker exec -w /app -e DEBUG=1 NAME python -m pdb main.py
docker exec NAME cat /proc/1/status | grep -E 'Name|Sig(Blk|Ign|Cgt)'   # does PID 1 handle signals?
```

When the image has **no shell at all** (distroless, scratch), borrow one by joining its namespaces from a tooling container:

```bash
docker run --rm -it --pid container:NAME --network container:NAME \
  nicolaka/netshoot                            # ss, dig, tcpdump, curl, strace against the target
# its filesystem, via /proc:
docker run --rm -it --pid container:NAME busybox:1.37 ls /proc/1/root/app
```

Or from the host, with nothing extra:

```bash
PID=$(docker inspect -f '{{.State.Pid}}' NAME)
sudo nsenter -t "$PID" -n ss -tlnp             # host ss binary, container network ns
sudo nsenter -t "$PID" -n -m -p ls /app
```

> **Note.** `docker debug` (a shell with tools injected into any container) is a proprietary **Docker Desktop** plugin (GA in Desktop 4.33; Docker's announcement ties it to a Pro, Team or Business subscription) and is **not** in Docker CE — `docker debug --help` here falls through to the top-level help (**verified**). The request to ship it for Engine (`docker/roadmap#893`) is still open as of September 2026. The `--pid container:` trick is the free equivalent.

### Read logs

```bash
docker logs -f --tail 100 NAME                 # follow from the last 100 lines
docker logs --since 10m NAME
docker logs --since 2026-09-23T09:00:00 --until 2026-09-23T09:15:00 NAME
docker logs -t NAME 2>&1 | grep -i error       # -t prefixes timestamps; logs go to both streams
docker logs NAME 2>/dev/null                   # stdout only
```

`docker logs` only works for the `json-file`, `local` and `journald` drivers (and with dual logging for others). The default here is `json-file` (**verified**, `docker info`) — **with no rotation**, so one chatty container can fill `/var/lib/docker`. The runtime chapter sets `local` with size caps as the daemon default.

> **Gotcha.** `docker logs` shows what the process wrote to stdout/stderr. An app logging to `/var/log/app.log` inside the container shows nothing. The official nginx image symlinks its log files to `/dev/stdout` for exactly this reason; do the same.

### Inspect with Go templates

`docker inspect` returns everything as JSON. `--format` / `-f` takes a Go template, which is faster than piping to `jq` and needs no extra tool. Both are useful; learn the handful of template forms.

| Template | Gives |
|---|---|
| `{{.State.Status}}` | `running`, `exited`, … |
| `{{.State.ExitCode}} {{.State.OOMKilled}}` | Why it died |
| `{{.State.Pid}}` | Host PID for nsenter |
| `{{json .State.Health}}` | Healthcheck status and last 5 results |
| `{{.Config.Image}}` | Image reference as requested |
| `{{.Image}}` | Resolved image ID |
| `{{range $k, $v := .NetworkSettings.Networks}}{{$k}}={{$v.IPAddress}} {{end}}` | IP per network |
| `{{json .HostConfig.PortBindings}}` | What's published, and on which address |
| `{{range .Mounts}}{{.Type}}:{{.Source}}->{{.Destination}} {{end}}` | Mounts |
| `{{join .Config.Cmd " "}}` | Command as a string |
| `{{index .Config.Labels "com.docker.compose.service"}}` | A label with dots in the key |
| `{{.HostConfig.RestartPolicy.Name}}` | Restart policy |
| `{{.HostConfig.Memory}}` | Memory limit in bytes (0 = unlimited) |

All of these were run against a live container on this machine (**verified**). Real uses:

```bash
# Why did it die?
docker inspect -f '{{.State.ExitCode}} oom={{.State.OOMKilled}} err={{.State.Error}} at={{.State.FinishedAt}}' NAME

# Health history, readable
docker inspect -f '{{json .State.Health}}' NAME | jq '.Status, (.Log[] | {ExitCode, Output})'

# Which containers publish on 0.0.0.0? (the audit you should run now)
docker ps -q | xargs docker inspect -f \
  '{{.Name}} {{range $p, $b := .HostConfig.PortBindings}}{{range $b}}{{.HostIp}}:{{.HostPort}}->{{$p}} {{end}}{{end}}' \
  | grep -E ' (0\.0\.0\.0|::)?:[0-9]'

# Containers with no memory limit
docker ps -q | xargs docker inspect -f '{{.Name}} {{.HostConfig.Memory}}' | awk '$2==0'

# Env of a container (careful: secrets)
docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' NAME

# Image metadata without running it
docker image inspect -f '{{.Config.User}} {{json .Config.Entrypoint}} {{json .Config.Cmd}}' IMAGE
docker image inspect -f '{{json .Config.ExposedPorts}} {{json .Config.Healthcheck}}' IMAGE
```

> **Gotcha.** Anything passed with `-e` or `environment:` is visible in plain text to anyone who can run `docker inspect` — which is everyone in the docker group. Real secrets go through files (Compose secrets, `--mount` of a file) or a secret manager.

### List things: ps and friends

```bash
docker ps                                      # running
docker ps -a --filter status=exited            # the dead
docker ps --filter label=com.docker.compose.project=PROJECT
docker ps --filter publish=5432
docker ps --filter ancestor=postgres:18-alpine
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker ps --format '{{.Names}}\t{{.Label "com.docker.compose.project"}}'
docker ps --format json | jq -r '.Names'
docker ps -aq --filter status=exited | xargs -r docker rm
```

| Placeholder | For `ps` |
|---|---|
| `.ID` `.Names` `.Image` `.Command` | Identity |
| `.Status` `.State` `.RunningFor` `.CreatedAt` | Lifecycle |
| `.Ports` `.Networks` `.Mounts` | Wiring |
| `.Size` | Needs `-s`; writable layer + virtual |
| `.Label "KEY"` / `.Labels` | Labels |

Make your preferred format permanent in `~/.docker/config.json`:

```json
{
  "psFormat": "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}",
  "imagesFormat": "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"
}
```

#### Images

```bash
docker image ls --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}' | sort -k2 -h | tail
docker image ls --digests
docker image ls --filter dangling=true
docker image ls --tree                         # multi-platform view (experimental; containerd store)
docker image history --no-trunc --format '{{.Size}}\t{{.CreatedBy}}' IMAGE | sort -h | tail
docker system df                               # what is using disk
docker system df -v | less
```

### Move files: cp

```bash
docker cp NAME:/app/config.yaml ./config.yaml
docker cp ./fix.py NAME:/app/fix.py
docker cp NAME:/var/log/ - | tar -tv           # stream a tar to stdout
docker cp -a ./data NAME:/data                 # preserve uid/gid
```

`docker cp` works on **stopped** containers too, which is how you get the core dump or the log file out of something that crashed on start. It does not work through a `--read-only` root to write, and it cannot reach into volumes of a stopped container via the volume path — copy from the mount destination instead.

### Watch resources: stats and events

```bash
docker stats                                    # live top for containers
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.PIDs}}'
docker stats --no-stream --format json | jq -s 'sort_by(.MemPerc) | reverse | .[:5]'
```

`MemUsage` excludes page cache (inactive file), so it tracks what the OOM killer cares about. `MemPerc` is against the container limit, or host RAM if unlimited.

`docker events` is the daemon's audit stream — the answer to "who restarted that and when":

```bash
docker events --since 1h --filter type=container --filter event=die \
  --format '{{.Time}} {{.Actor.Attributes.name}} exit={{.Actor.Attributes.exitCode}}'
docker events --filter event=oom
docker events --filter type=container --filter event=health_status
docker events --filter type=network --since 30m
docker events --format json | jq -c '{t: .time, type: .Type, a: .Action, n: .Actor.Attributes.name}'
```

> **Note.** Events are kept in a small in-memory buffer; after a daemon restart, `--since` only goes back to the restart. For history, ship them.

### Switch daemons: contexts

A context bundles an endpoint (and TLS) under a name. It replaces exporting `DOCKER_HOST` by hand.

```bash
docker context ls
docker context show
docker context create build-box --docker "host=ssh://you@build-box.internal"
docker context create podman --docker "host=unix:///run/user/$(id -u)/podman/podman.sock"
docker context use build-box                   # sticky: every shell, until changed
docker --context build-box ps                  # one command
DOCKER_CONTEXT=podman docker compose up -d     # per-shell (direnv-friendly)
docker context use default
```

| Mechanism | Scope | Wins over |
|---|---|---|
| `--context NAME` / `-H` | One command | Everything |
| `DOCKER_HOST` | Shell | `DOCKER_CONTEXT` and `use` |
| `DOCKER_CONTEXT` | Shell | `docker context use` |
| `docker context use` | Global (`~/.docker/config.json`) | Default |

> **Gotcha.** `docker context use` is global and sticky, like `kubectl config use-context`. Switch to the build server, forget, and your `docker system prune` runs *there*. Prefer `DOCKER_CONTEXT` via direnv per project, and put the context in your prompt.

**SSH contexts are the right way to reach a remote daemon.** They reuse your SSH keys and agent, need no TLS setup, and never expose the daemon on TCP. Enable `ControlMaster` in `~/.ssh/config` or every `docker` call pays an SSH handshake.

To drive rootless Podman with the docker CLI (and docker compose), start its socket:

```bash
systemctl --user enable --now podman.socket
docker --context podman ps                     # docker CLI, Podman engine
```

### A zsh block worth stealing

```bash
# ~/.zshrc.d/docker.zsh

alias d='docker'
alias dc='docker compose'
alias dps='docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
alias dpsa='docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"'
alias di='docker image ls --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}"'
alias ddf='docker system df'
alias dlf='docker logs -f --tail 200'
alias dcu='docker compose up -d --wait'
alias dcd='docker compose down'
alias dcl='docker compose logs -f --tail 200'

# shell into anything: bash if present, else sh
dsh() { docker exec -it "${1:?container}" sh -c 'command -v bash >/dev/null && exec bash || exec sh'; }

# run a throwaway shell in an image, overriding its entrypoint, cwd mounted
drun() { docker run --rm -it --entrypoint sh -v "$PWD":/w:ro -w /w "${1:?image}"; }

# why did it die?
dwhy() {
  docker inspect -f 'exit={{.State.ExitCode}} oom={{.State.OOMKilled}} error="{{.State.Error}}" finished={{.State.FinishedAt}} restarts={{.RestartCount}}' "${1:?container}"
  docker logs --tail 30 "$1" 2>&1
}

# IPs of a container per network
dip() { docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}	{{$v.IPAddress}}{{"\n"}}{{end}}' "${1:?container}"; }

# net-debug any container, even distroless
dnet() { docker run --rm -it --network "container:${1:?container}" --pid "container:$1" nicolaka/netshoot; }

# ports published on all interfaces (should be empty on a laptop)
dexposed() {
  docker ps -q | xargs -r docker inspect -f '{{.Name}} {{range $p,$b := .HostConfig.PortBindings}}{{range $b}}{{.HostIp}}:{{.HostPort}}->{{$p}} {{end}}{{end}}' \
    | grep -E ' (0\.0\.0\.0|::)?:[0-9]' || echo "none"
}

# which digest does this tag point at right now (no pull)
ddigest() { docker buildx imagetools inspect "${1:?image}" --format '{{json .Manifest}}' | jq -r .digest; }

# fzf-pick a container for logs
dfl() { local c; c=$(docker ps --format '{{.Names}}' | fzf) && docker logs -f --tail 200 "$c"; }

# prompt segment: show non-default context
docker_ctx() { local c=${DOCKER_CONTEXT:-$(docker context show 2>/dev/null)}; [[ $c != default ]] && print -n "[ctx:$c] "; }
```

> **Note.** Zsh completion for docker ships with the package (`/usr/share/zsh/site-functions/_docker`); if `docker compose` subcommands don't complete, add `docker completion zsh > "${fpath[1]}/_docker"`.

### TUIs and inspectors

None of these are installed on this machine (**verified**, `which`); install per below.

| Tool | Use it for | Install on Fedora |
|---|---|---|
| **lazydocker** | One-screen containers/logs/stats/compose, keyboard-driven. **Default pick** | `go install github.com/jesseduffield/lazydocker@latest` or release binary |
| **dive** | Layer-by-layer image explorer: what each instruction added, wasted bytes | Release RPM from GitHub (v0.13.1, March 2025, is current), or `docker run --rm -it -v /var/run/docker.sock:/var/run/docker.sock ghcr.io/wagoodman/dive IMAGE` |
| **ctop** | `top` for containers only | Release binary; unmaintained since 2022 — `docker stats` or lazydocker cover it |
| **skopeo** | Registry inspect/copy without a daemon | Installed (`/usr/bin/skopeo`) |

```bash
dive IMAGE                          # Tab switches panes; Ctrl-U shows only unmodified
CI=true dive IMAGE --lowestEfficiency 0.95 --highestUserWastedPercent 0.05   # CI gate (a .dive-ci file, if present, overrides these)
lazydocker                          # works against DOCKER_HOST / current context
DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock lazydocker    # against Podman
```

> **Gotcha.** Running dive (or anything) with `-v /var/run/docker.sock:/var/run/docker.sock` hands that container root on your host. Fine for a tool you trust, pinned by digest; not fine for a random image from a blog post.

### Clean up

```bash
docker container prune -f --filter until=24h   # stopped containers older than a day
docker image prune -f                          # dangling (untagged) images only
docker image prune -a -f --filter until=168h   # ALL unused images older than a week
docker builder prune -f --keep-storage 20GB    # trim build cache to 20 GB
docker buildx du                               # build cache usage per record
docker volume prune -f                         # ANONYMOUS unused volumes only (Docker 23+)
docker volume prune -a -f                      # also NAMED unused volumes — see below
docker system prune -f                         # containers, networks, dangling images, cache
```

> **One-way door.** `docker system prune -a --volumes` deletes every image not used by a container (hundreds of GB of re-pulls and rebuilds), all build cache, and **anonymous** volumes. `docker volume prune -a` removes **named** volumes not attached to a container — which includes the Postgres data of any Compose stack that is currently `down`. There is no undo and no trash. Prune images and cache freely; prune volumes by name.

`docker system df` on this machine shows **268 GB reclaimable images and 116 GB reclaimable build cache** (**verified**). The prune policy in *Every recommendation* is the fix: images by age, cache by size cap, volumes never automatically.

### Podman differences that bite

| Docker | Podman | Difference |
|---|---|---|
| `docker run -p 80:80` | Fails rootless (<1024) | Use `8080:80`, or lower `ip_unprivileged_port_start` |
| `docker ps` | `podman ps` | Also `podman ps --pod` |
| `docker logs` | `podman logs` | Default driver is `journald` on Fedora; `journalctl CONTAINER_NAME=x` works |
| `-v src:dst` | Same, plus `:U` (chown to container user) and `:O` (overlay) | |
| Short names `nginx` | Prompt or error per `registries.conf` short-name mode | **Always use fully-qualified names** (`docker.io/library/nginx`) in anything shared |
| `docker context` | `podman system connection` | Podman's own remote mechanism; `podman --connection NAME` |
| `docker system prune` | `podman system prune` | Same semantics; also `podman system reset` (**deletes everything**) |
| `docker events` | `podman events` | Backed by journald; history survives restarts |

### Checklist

- `--rm` on every interactive run; `--name` on every service.
- `-p 127.0.0.1:…` unless you mean the LAN. Run `dexposed` now.
- `--mount` in scripts, `-v` at the prompt.
- `--memory` on anything long-running.
- `--init` when PID 1 is a shell or an interpreter without signal handlers.
- `inspect -f` before `grep`; `events` before guessing.
- Context in your prompt; `DOCKER_CONTEXT` via direnv over `docker context use`.
- Prune images and cache on a schedule; never prune volumes on autopilot.


---


<a id="03-dockerfiles-that-behave"></a>

## 03 · Dockerfiles that behave

*A Dockerfile is a build graph with a cache, not a shell script. Order instructions by how often their inputs change, keep secrets and caches out of layers with mounts, and make PID 1 a process that actually handles SIGTERM.*

Three properties separate a Dockerfile that behaves from one that merely builds:

1. **It rebuilds fast** because the expensive steps sit above the inputs that change often.
2. **Its image carries only the runtime** — no compilers, no package-manager caches, no secrets, no source it doesn't run.
3. **It stops cleanly** because PID 1 receives SIGTERM and exits, instead of waiting ten seconds to be SIGKILLed.

Everything below serves one of those. The examples assume BuildKit (the default builder since Docker 23) and the `docker/dockerfile:1` frontend.

### Start every file the same way

```dockerfile
# syntax=docker/dockerfile:1
# check=error=true
```

- **`# syntax=docker/dockerfile:1`** pulls the latest stable 1.x Dockerfile frontend at build time, so heredocs, `COPY --exclude`, `--mount` types and new checks work regardless of how old the daemon's embedded frontend is. Pin it (`docker/dockerfile:1.19`) if you need reproducibility, or pin by digest in an air gap.
- **`# check=error=true`** turns build-check warnings into build failures. Run the checks without building with `docker build --check .`.

`docker build --check` on a deliberately bad file here reported (**verified**): `ConsistentInstructionCasing`, `SecretsUsedInArgOrEnv` for `ARG API_TOKEN` and `ENV DB_PASSWORD`, and `JSONArgsRecommended` for a shell-form `CMD`. That is free linting built into the tool you already run; hadolint (end of chapter) adds shell-level rules on top.

### Instruction semantics that matter

| Instruction | Creates a layer | Cache key | Trap |
|---|---|---|---|
| `FROM img` | Base | Image digest | Tag re-resolves on `--pull`; pin by digest |
| `RUN cmd` | Yes | **The command string** (+ mounts) | `apt-get update` alone caches stale indexes forever |
| `COPY src dst` | Yes | **Checksums of the files** | One changed file busts every layer below |
| `ADD` | Yes | Contents / URL | Auto-extracts tars; fetches URLs. Use `COPY` unless you want that |
| `ENV K=V` | Metadata | Value | Persists into the running container and into child images |
| `ARG K` | No | Value (if used) | Build-time only, but visible in `docker history` for `RUN`s that use it |
| `WORKDIR` | Metadata (+ mkdir) | Path | Creates the dir as root |
| `USER` | Metadata | Value | Affects `RUN`, `CMD`, `ENTRYPOINT` below it; not `COPY` ownership |
| `ENTRYPOINT` / `CMD` | Metadata | Value | Shell form breaks signals (below) |
| `EXPOSE` | Metadata | Value | **Documentation only.** Publishes nothing |
| `HEALTHCHECK` | Metadata | Value | Ignored by Kubernetes |
| `STOPSIGNAL` | Metadata | Value | For apps that shut down on SIGINT/SIGQUIT |
| `SHELL` | Metadata | Value | Set `["/bin/bash","-o","pipefail","-c"]` for pipes |

**The cache rule:** a step is reused if its instruction, its inputs, and **every step above it** are unchanged. The first miss rebuilds everything below. Hence the ordering rule.

### Order layers by change rate

```text
   changes rarely ──▶  FROM base@sha256:…
                       RUN  install OS packages
                       COPY lockfile only            ◀── dependency manifest
                       RUN  install dependencies      ◀── expensive; cached until lockfile changes
                       COPY source                   ◀── changes every commit
   changes often  ──▶  RUN  build / compile
```

The canonical mistake:

```dockerfile
COPY . .                        # any file change → cache miss here
RUN pip install -r requirements.txt   # → reinstalls every dependency, every build
```

The fix is to copy the lockfile first, install, then copy the rest. Every example below does this.

#### .dockerignore is part of the cache key

`COPY . .` hashes everything in the context. A `.git` directory, `node_modules`, `.venv`, build output or a 2 GB test fixture both slows the context upload and busts the cache on unrelated changes.

```text
# .dockerignore
.git
.gitignore
**/__pycache__
**/*.pyc
.venv
node_modules
dist
build
coverage
.pytest_cache
.mypy_cache
.ruff_cache
*.log
.env
.env.*
!.env.example
Dockerfile*
compose*.yaml
.dockerignore
docs
**/*.md
!README.md
```

> **Gotcha.** `.env` in the build context plus `COPY . .` bakes your local secrets into a layer. Ignore `.env*` by default and un-ignore the example with `!`.

> **Note.** A file named `Dockerfile.dockerignore` (or `NAME.Dockerfile.dockerignore`) next to the Dockerfile takes precedence over the root `.dockerignore`. Use it when one repo builds several images with different contexts.

> **Version-sensitive.** `COPY --exclude=PATTERN` (exclude without a `.dockerignore`) is accepted with `# syntax=docker/dockerfile:1` (**verified** — `docker build --check` accepted it). Older pinned frontends before it went stable need `# syntax=docker/dockerfile:1-labs`.

### Multi-stage builds

A stage is a `FROM`. Only the last stage (or the `--target`) becomes the image; earlier stages are scratch space whose outputs you `COPY --from`.

```dockerfile
# syntax=docker/dockerfile:1
FROM golang:1.26 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/app ./cmd/app

FROM build AS test                       # built only if targeted
RUN go test ./...

FROM gcr.io/distroless/static-debian13:nonroot AS runtime
COPY --from=build /out/app /app
ENTRYPOINT ["/app"]
```

What BuildKit gives you here:

- **Unreferenced stages are skipped.** `docker build .` builds `build` and `runtime`; `test` never runs. `docker build --target test .` runs the tests.
- **Independent stages build in parallel.** A frontend stage and a backend stage with no dependency between them run concurrently.
- **`COPY --from` takes an image too:** `COPY --from=ghcr.io/astral-sh/uv:0.12 /uv /bin/uv` copies a binary out of any image without a stage.
- **Named stages become bake/CI targets.** `--target test`, `--target lint`, `--target runtime` from one file.

### Mounts: cache, secret, ssh, bind

`RUN --mount` attaches something to a single `RUN` step **without it becoming part of any layer**. This is the most important BuildKit feature for image hygiene.

| Mount | Syntax | Use for |
|---|---|---|
| `cache` | `--mount=type=cache,target=/root/.cache/uv` | Package-manager caches that persist across builds on this builder |
| `secret` | `--mount=type=secret,id=npmrc,target=/root/.npmrc` | Tokens, `.netrc`, cloud creds. Never in a layer, never in history |
| `ssh` | `--mount=type=ssh` | `git clone` of private repos via your agent |
| `bind` | `--mount=type=bind,source=uv.lock,target=uv.lock` | Read files from the context without a `COPY` layer |
| `tmpfs` | `--mount=type=tmpfs,target=/tmp` | Scratch space that must not persist |

#### Cache mounts

```dockerfile
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && apt-get install -y --no-install-recommends ca-certificates curl
```

| Ecosystem | Cache target |
|---|---|
| uv | `/root/.cache/uv` (set `UV_LINK_MODE=copy`) |
| pip | `/root/.cache/pip` |
| npm | `/root/.npm` |
| pnpm | `/root/.local/share/pnpm/store` (or `pnpm config get store-dir`) |
| Go | `/go/pkg/mod` and `/root/.cache/go-build` |
| Cargo | `/usr/local/cargo/registry`, `/app/target` |
| Maven | `/root/.m2` |
| apt | `/var/cache/apt`, `/var/lib/apt` with `sharing=locked` |

`sharing=locked` serialises concurrent builds using the same cache (apt's lock files require it). `sharing=shared` (default) allows concurrent use, `private` gives each build its own copy.

> **Gotcha.** Cache mounts live **in the builder**, not the image or the registry. A fresh CI runner has an empty one. `--cache-to type=registry` exports *layers*, not cache mounts. On ephemeral CI, cache mounts help within a job only; the *BuildKit and buildx* chapter covers what does persist.

> **Gotcha.** A cache mount at a path the final image needs (e.g. mounting a cache over `node_modules`) means the files are **not in the layer**. Mount the package manager's download cache, never the install target.

#### Secret mounts

```dockerfile
RUN --mount=type=secret,id=pip_index,env=PIP_INDEX_URL \
    pip install -r requirements.txt

RUN --mount=type=secret,id=npmrc,target=/root/.npmrc \
    npm ci
```

```bash
docker build --secret id=npmrc,src="$HOME/.npmrc" .
docker build --secret id=pip_index,env=PIP_INDEX_URL .        # from an env var
# GitLab CI: file-type variable
docker build --secret id=npmrc,src="$NPMRC_FILE" .
```

The `env=` target (expose the secret as an environment variable for that one `RUN`) avoids writing a file at all. The secret is absent from every layer, from `docker history`, and from the build cache key.

> **Gotcha.** A secret that changes does **not** bust the cache for the step that uses it. If a step's output depends on which token was used (rare), add a non-secret `ARG` that changes with it.

#### SSH mounts

```dockerfile
RUN --mount=type=ssh \
    mkdir -p -m 0700 ~/.ssh && ssh-keyscan gitlab.example.com >> ~/.ssh/known_hosts && \
    git clone git@gitlab.example.com:group/private-lib.git /deps/private-lib
```

```bash
docker build --ssh default .           # forwards $SSH_AUTH_SOCK
```

Hard-code the host key instead of `ssh-keyscan` in anything serious; keyscan trusts whatever answers.

### Heredocs

Multi-line `RUN` without `&& \` chains, and inline files without a separate `COPY`:

```dockerfile
RUN <<EOF
set -eux
apt-get update
apt-get install -y --no-install-recommends ca-certificates tzdata
rm -rf /var/lib/apt/lists/*
EOF

COPY <<EOF /etc/app/config.toml
[server]
port = 8080
EOF

RUN <<EOF bash
set -euo pipefail
curl -fsSL https://example.com/install.sh | sh
EOF
```

A heredoc `RUN` is still **one layer**. Put `set -eux` (or `set -euo pipefail` with bash) on the first line: without it, a failing middle command is ignored and the build reports success.

> **Gotcha.** hadolint 2.15.1 **cannot parse heredocs** — it stops with `unexpected 'C' expecting a new line` at the first instruction after one (**verified**). Either skip hadolint for those files or rely on `docker build --check` there.

### ARG vs ENV

| | `ARG` | `ENV` |
|---|---|---|
| Available during build | Yes (after declaration, in that stage) | Yes |
| Present in running container | **No** | **Yes** |
| Set from CLI | `--build-arg K=V` | No (use ARG then `ENV K=$K`) |
| Inherited by child images | No | Yes |
| Scope | Per stage; `ARG` before first `FROM` only feeds `FROM` lines | From declaration down, and into children |
| Safe for secrets | **No** (in history) | **No** (in image config) |

```dockerfile
ARG PYTHON_VERSION=3.14              # global: usable only in FROM lines
FROM python:${PYTHON_VERSION}-slim
ARG PYTHON_VERSION                   # re-declare to use inside the stage
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}       # promote to runtime when the app needs it
LABEL org.opencontainers.image.version=${APP_VERSION}
```

BuildKit predefines platform args in the global scope: `BUILDPLATFORM`, `TARGETPLATFORM`, `TARGETOS`, `TARGETARCH`, `TARGETVARIANT`. Re-declare them (`ARG TARGETARCH`) inside a stage to use them.

> **Gotcha.** Putting a changing value (`ARG GIT_SHA`) near the top busts the cache for every step after its **first use**. Declare it at the bottom, just before the `LABEL` that uses it.

### ENTRYPOINT, CMD and PID 1

#### Exec form or you lose signals

| Form | Written as | What runs as PID 1 | SIGTERM from `docker stop` |
|---|---|---|---|
| Exec | `CMD ["python", "app.py"]` | `python` | Delivered to your app |
| Shell | `CMD python app.py` | `/bin/sh -c "python app.py"` | Delivered to **sh**, which does not forward it. App gets SIGKILL after 10 s → exit **137** |

That ten-second hang on every `docker stop` / `compose down`, and exit 137 in the logs, is almost always shell form.

#### How ENTRYPOINT and CMD combine

| | No `ENTRYPOINT` | `ENTRYPOINT ["/app"]` | `ENTRYPOINT /app` (shell) |
|---|---|---|---|
| No `CMD` | Error | `/app` | `sh -c /app` |
| `CMD ["serve"]` | `serve` | `/app serve` | `sh -c /app` (**CMD ignored**) |
| `docker run IMG migrate` | `migrate` | `/app migrate` | `sh -c /app` (**args ignored**) |

**Default: `ENTRYPOINT ["/binary"]` + `CMD ["default-args"]`.** The image then behaves like a command: `docker run img --help` works.

#### Wrapper scripts must exec

```bash
#!/bin/sh
# docker-entrypoint.sh
set -eu
if [ "${1:-}" = "serve" ] && [ "${RUN_MIGRATIONS:-0}" = "1" ]; then
  /app/manage migrate
fi
exec "$@"                 # replace the shell; the app becomes PID 1
```

```dockerfile
COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["serve"]
```

Without `exec`, the shell stays PID 1 and the app is its child: signals stop at the shell.

#### PID 1 is special

The kernel treats PID 1 differently: **signals with no installed handler are ignored**, including SIGTERM and SIGINT. A Python or Node process that never registers a SIGTERM handler will ignore `docker stop` even in exec form. PID 1 must also reap orphaned zombies, which most apps never do.

| Situation | Fix |
|---|---|
| App handles SIGTERM, spawns no children | Exec form is enough |
| App ignores SIGTERM, or spawns subprocesses | **`docker run --init`** / Compose `init: true` (Docker's bundled tini) |
| Must work under Kubernetes (no `--init`) | Install tini in the image: `ENTRYPOINT ["tini", "--", "/app"]` |
| App shuts down gracefully on a different signal | `STOPSIGNAL SIGQUIT` (nginx), `SIGINT` |
| Needs longer to drain | `docker stop -t 30` / Compose `stop_grace_period: 30s` |

```bash
docker exec NAME cat /proc/1/status | grep SigCgt    # bitmask of caught signals; bit 15 = SIGTERM
time docker stop NAME                                # ~10.0 s means SIGTERM was ignored
```

### HEALTHCHECK

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --start-interval=2s --retries=3 \
  CMD ["curl", "-fsS", "http://127.0.0.1:8080/healthz"]
```

| Option | Default | Meaning |
|---|---|---|
| `--interval` | 30s | Time between checks once started |
| `--timeout` | 30s | A check taking longer counts as failed |
| `--start-period` | 0s | Grace period: failures don't count |
| `--start-interval` | 5s | Check frequency *during* start period |
| `--retries` | 3 | Consecutive failures → `unhealthy` |

> **Version-sensitive.** `--start-interval` needs Docker Engine 25 / API 1.44 or later.

What a healthcheck does and does not do:

- It sets `.State.Health.Status` to `starting` / `healthy` / `unhealthy`. **Docker does not restart an unhealthy container** (Swarm does). Compose uses it for `depends_on: condition: service_healthy`, which is its main value.
- **Kubernetes ignores `HEALTHCHECK`** entirely; it uses probes.
- Distroless has no `curl` or shell. Give the binary a `healthcheck` subcommand: `HEALTHCHECK CMD ["/app", "healthcheck"]`.
- Check *this* process's liveness, not the database. The same rule as Kubernetes liveness probes applies.

### USER and non-root

```dockerfile
# Debian-based
RUN groupadd --system --gid 10001 app && \
    useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app
COPY --chown=app:app --from=build /out /app
USER 10001:10001
```

- **Use a numeric UID in `USER`.** Kubernetes `runAsNonRoot: true` can only verify a numeric UID; `USER app` fails admission with "image has non-numeric user".
- Distroless `:nonroot` images ship UID/GID **65532**. Node images ship `node` (1000). Python images ship none.
- **`COPY` creates files as root** regardless of `USER`. Use `COPY --chown=` and `--chmod=`, and keep app code **not writable** by the app user where you can.
- Anything the app must write (`/tmp`, a cache dir) should be a `tmpfs` or a volume at runtime, so `--read-only` works.

### Pin the base image

```dockerfile
FROM python:3.14-slim@sha256:caaf356f40667c496d405780745b9ac25771c189a51dfcc42430d531ea09f8a2
```

Keep the tag for humans and Renovate; the digest is what gets used. That is the index digest for `python:3.14-slim` as resolved on 2026-09-23 via `skopeo inspect` (**verified**; it will have moved by the time you read this). Get the current one with:

```bash
docker buildx imagetools inspect python:3.14-slim --format '{{json .Manifest}}' | jq -r .digest
```

Renovate's `docker` manager updates tag+digest pairs in place and opens MRs; that is the maintenance model. The supply-chain chapter covers it.

### Base image choices

| Language | Build stage | Runtime stage | Why |
|---|---|---|---|
| Python | `python:3.14-slim` + uv | **`python:3.14-slim`** | glibc wheels install as binaries. Alpine's musl forces source builds and changes DNS behaviour |
| Node | `node:24-slim` | **`node:24-slim`**, or `gcr.io/distroless/nodejs24-debian13:nonroot` | Close call. Slim keeps a shell and apt for native addons; distroless (entrypoint is already `node`) wins when there are no native addons and you want the smaller CVE surface the supply-chain chapter asks for |
| Go (static) | `golang:1.26` | **`gcr.io/distroless/static-debian13:nonroot`** | CA certs, tzdata, passwd entry; ~2 MB; no shell to exploit |
| Go (cgo) | `golang:1.26` | `gcr.io/distroless/base-debian13:nonroot` | Adds glibc |
| Rust | `rust:1-slim` | distroless `cc` or `static` | Same logic as Go |
| Java | `eclipse-temurin:25-jdk` | `gcr.io/distroless/java25-debian13:nonroot` (or `eclipse-temurin:25-jre`) | JRE only at runtime; distroless drops the shell |
| "Just a shell" | — | `alpine:3.22` or `debian:trixie-slim` | Debug/tooling images, not apps |

`gcr.io/distroless/static-debian13:nonroot` and `static-debian12:nonroot` both resolve today, as do `nodejs24-debian13`, `java25-debian13` and `python3-debian13` (**verified** with `skopeo inspect`); prefer the debian13 (trixie) variants for new work.

> **Note.** Close call: Chainguard / Wolfi images give near-zero-CVE bases with a shell-less default and daily rebuilds. The tiebreaker is licence and pinning: free tier gives `:latest` only, so digest pinning to an old version means paying. Distroless is free and pins fine.

### Full examples: what was tested

The three Dockerfiles below were built and run on this machine against minimal apps (**verified**): all pass `docker build --check` with no warnings, reach `healthy`, run as the intended non-root user, and stop in under a second.

| Example | Runtime user | Image size | `docker stop` |
|---|---|---|---|
| Python (uv, FastAPI) | `10001:10001` | 200 MB | 0.5 s |
| Node (`node:24-slim`) | `node` | 328 MB | 0.7 s (app handles SIGTERM) |
| Go (distroless static) | `65532:65532` | 16 MB | 0.3 s |

> **Gotcha.** `npm ci` with **zero** production dependencies creates no `node_modules`, and `COPY --from=deps /app/node_modules` then fails with `"/app/node_modules": not found` (**verified**). Real apps never hit it; template repos and hello-worlds do.

### Full example: Python with uv

```dockerfile
# syntax=docker/dockerfile:1
# check=error=true

ARG PYTHON_IMAGE=python:3.14-slim

# ---------- build: resolve and install into /app/.venv ----------
FROM ${PYTHON_IMAGE} AS build
COPY --from=ghcr.io/astral-sh/uv:0.12 /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0 \
    UV_PROJECT_ENVIRONMENT=/app/.venv

WORKDIR /app

# 1) dependencies only — cached until pyproject.toml / uv.lock change
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project --no-dev

# 2) the project itself
COPY . /app
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-editable

# ---------- test: optional target ----------
FROM build AS test
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked
RUN /app/.venv/bin/pytest -q

# ---------- runtime: no uv, no build tools ----------
FROM ${PYTHON_IMAGE} AS runtime

RUN groupadd --system --gid 10001 app && \
    useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

COPY --from=build --chown=10001:10001 /app/.venv /app/.venv

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app
USER 10001:10001
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --start-interval=2s \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2).status == 200 else 1)"]

ENTRYPOINT ["uvicorn", "myapp.main:app"]
CMD ["--host", "0.0.0.0", "--port", "8000"]
```

Why each line is there:

- **`COPY --from=ghcr.io/astral-sh/uv:0.12`** — uv as a static binary, no pip bootstrap. Pin a minor (or digest); `:latest` changes resolver behaviour under you.
- **`--mount=type=bind` for the lockfiles** — dependencies install without a `COPY` layer, and the step is cached on the lockfile content.
- **`--no-install-project` then full sync** — the dependency layer survives source edits.
- **`--no-editable`** — the project is installed into site-packages, so the runtime stage needs only `.venv`, not the source.
- **`UV_LINK_MODE=copy`** — the cache mount is a different filesystem; hardlinks would fail noisily.
- **`UV_COMPILE_BYTECODE=1`** — compile `.pyc` at build time, not first request (with a read-only root it would never be cached).
- **Same base image in build and runtime** — the venv's `python` symlink points at `/usr/local/bin/python3.14`, which must exist at the same path.
- **Uvicorn binds `0.0.0.0` inside the container** — that's the container's own network namespace; `127.0.0.1` there would be unreachable from the host. Host exposure is controlled by `-p`.

> **Version-sensitive.** `ghcr.io/astral-sh/uv:0.12` is illustrative; check the current minor with `docker buildx imagetools inspect ghcr.io/astral-sh/uv:latest` and pin that.

### Full example: Node

```dockerfile
# syntax=docker/dockerfile:1
# check=error=true

ARG NODE_IMAGE=node:24-slim

FROM ${NODE_IMAGE} AS deps
WORKDIR /app
RUN --mount=type=cache,target=/root/.npm \
    --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=package-lock.json,target=package-lock.json \
    npm ci --omit=dev --ignore-scripts

FROM ${NODE_IMAGE} AS build
WORKDIR /app
RUN --mount=type=cache,target=/root/.npm \
    --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=package-lock.json,target=package-lock.json \
    --mount=type=secret,id=npmrc,target=/root/.npmrc \
    npm ci
COPY . .
RUN npm run build && npm run test --if-present

FROM ${NODE_IMAGE} AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY --from=deps  --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/dist ./dist
COPY --chown=node:node package.json ./
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD ["node", "-e", "fetch('http://127.0.0.1:3000/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
ENTRYPOINT ["node"]
CMD ["dist/server.js"]
```

Notes:

- **Separate `deps` stage with `--omit=dev`** gives production-only `node_modules` for the runtime, while `build` has devDependencies for TypeScript/bundling.
- **`--ignore-scripts`** in the production install blocks install-time scripts from dependencies. Drop it only for packages that need a postinstall (native addons), and know which they are.
- **Never `npm start`** as the command. npm spawns your server as a child and does not forward SIGTERM reliably; run `node` directly.
- **Node ignores SIGTERM as PID 1 unless you handle it.** Add `process.on('SIGTERM', () => server.close(() => process.exit(0)))`, or run with `--init`.
- **`USER node`** is UID 1000 in the official image. For Kubernetes `runAsNonRoot`, write `USER 1000`.

### Full example: Go with distroless

```dockerfile
# syntax=docker/dockerfile:1
# check=error=true

FROM --platform=$BUILDPLATFORM golang:1.26 AS build
ARG TARGETOS TARGETARCH
WORKDIR /src

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=bind,source=go.mod,target=go.mod \
    --mount=type=bind,source=go.sum,target=go.sum \
    go mod download -x

ARG VERSION=dev
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=bind,target=. \
    CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" -o /out/app ./cmd/app

FROM build AS test
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=bind,target=. \
    go test ./...

FROM gcr.io/distroless/static-debian13:nonroot AS runtime
COPY --from=build /out/app /app
USER 65532:65532
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s CMD ["/app", "healthcheck"]
ENTRYPOINT ["/app"]
CMD ["serve"]
```

- **`FROM --platform=$BUILDPLATFORM`** runs the compiler natively on the build host and cross-compiles with `GOOS/GOARCH`. A multi-arch build then needs no QEMU at all for the Go step. This is the single biggest multi-platform speed-up.
- **`--mount=type=bind,target=.`** compiles straight from the context with no `COPY` layer; the build stage stays tiny and the cache key is the source content.
- **`-trimpath`** removes local paths from the binary (reproducibility, no leaked usernames).
- **The binary implements `healthcheck`** — a few lines that GET `/healthz` and exit 0/1 — because there is no shell or curl.

### Lint with hadolint

```bash
docker run --rm -i hadolint/hadolint:latest < Dockerfile
docker run --rm -i -v "$PWD/.hadolint.yaml":/.config/hadolint.yaml:ro hadolint/hadolint < Dockerfile
docker run --rm -i hadolint/hadolint hadolint --format gitlab_codeclimate - < Dockerfile > gl-codequality.json
```

On a sample file here, hadolint 2.15.1 flagged (**verified**): `DL3008` (pin apt versions), `DL3009` (delete apt lists), `DL3015` (`--no-install-recommends`), `DL4006` (set `pipefail` before a piped `RUN`), `DL3025` (JSON form for `CMD`).

```yaml
# .hadolint.yaml
failure-threshold: warning
ignored:
  - DL3008        # apt version pins: digest-pinned base + Renovate is the control; pins rot
  - DL3059        # consecutive RUNs: heredocs and cache-mount steps are deliberate
trustedRegistries:
  - docker.io
  - gcr.io
  - ghcr.io
  - registry.gitlab.example.com
```

Inline suppression on the line above the instruction: `# hadolint ignore=DL3018`.

| Rule | Says | Default stance |
|---|---|---|
| DL3006 / DL3007 | Tag your base image; don't use `latest` | Enforce |
| DL3008 / DL3018 | Pin apt/apk versions | **Ignore**; pin the base digest instead |
| DL3025 | JSON form for CMD/ENTRYPOINT | Enforce |
| DL3002 | Last USER should not be root | Enforce |
| DL4006 | `pipefail` before pipes | Enforce |
| DL3009 | Remove apt lists | Enforce, or use apt cache mounts |
| SC* | ShellCheck on `RUN` bodies | Enforce |

`docker build --check` and hadolint overlap on JSON form and casing; hadolint adds the ShellCheck and package-manager rules, `--check` understands heredocs and newer syntax. **Run both in CI**; `--check` is free.

### Traps

- **Shell-form `CMD`/`ENTRYPOINT`.** Ten-second stops, exit 137. Use JSON arrays.
- **`COPY . .` before dependency install.** Every code change reinstalls everything.
- **No `.dockerignore`.** `.git`, `node_modules` and `.env` in the context: slow, cache-busting, and a secret leak.
- **Secrets via `ARG`/`ENV`.** Visible in history and config. Use `--mount=type=secret`.
- **`rm` in a later layer.** Doesn't shrink or un-leak anything.
- **`apt-get update` in its own `RUN`.** Cached indexes go stale; install fails months later. Update and install in one step.
- **Cache mount over the install target.** The files never reach the image.
- **`USER name` instead of a numeric UID.** Breaks `runAsNonRoot`.
- **App binding `127.0.0.1` inside the container.** Unreachable through `-p`. Bind `0.0.0.0` in-container; restrict exposure at `-p`.
- **Unpinned `FROM`.** Yesterday's build and today's differ silently.
- **`HEALTHCHECK` that checks dependencies.** One database blip marks every service unhealthy.
- **hadolint on heredoc files.** It fails to parse; don't let that silently disable the lint job.


---


<a id="04-buildkit-buildx-and-bake"></a>

## 04 · BuildKit, buildx and bake

*docker build is a thin client for BuildKit, and buildx is the full client. Once you choose the builder, the cache backend and the output deliberately, multi-arch images, CI cache hits, SBOMs and a one-file build graph all come from the same three decisions.*

Where this machine stands (**verified**): buildx v0.37.1, BuildKit v0.33.0 in the default `docker`-driver builder, containerd image store, no QEMU binfmt handlers registered, and a stopped `docker-container` builder named `mybuilder`. `docker buildx ls` shows both.

### The pieces

```text
  docker build / docker buildx build / docker buildx bake / docker compose build
                         │   (all are buildx clients; compose v5 delegates to bake)
                         ▼
                 buildx: picks a BUILDER  (docker buildx ls / use / --builder)
                         │
        ┌────────────────┼──────────────────────┬──────────────────────┐
        ▼                ▼                      ▼                      ▼
   driver: docker   driver: docker-container  driver: remote      driver: kubernetes
   BuildKit inside  BuildKit in a container    buildkitd you run   buildkitd pods
   dockerd          (moby/buildkit image)      (TCP + mTLS/unix)   in a cluster
        │                │                      │                      │
        └────────────────┴──────── BuildKit solver ────────────────────┘
                         │  LLB graph, parallel stages, content-addressed cache,
                         │  cache mounts, secrets, attestations
                         ▼
                 OUTPUT: image in local store | registry push | OCI/docker tar | local dir | cacheonly
                 CACHE:  inline | registry | local | gha | s3 | azblob
```

> **Version-sensitive.** Docker Compose v5 (installed here as v5.5.1) removed its internal builder and **always delegates `docker compose build` to bake** when BuildKit is available. Compose build keys map onto bake target attributes; `docker compose build --print` shows the generated bake definition.

### Builders and drivers

| Driver | What it is | Multi-platform | Cache export | Output to local image store | Use for |
|---|---|---|---|---|---|
| `docker` | BuildKit embedded in dockerd | **Yes, on containerd store**; host-only on classic store | Inline only on classic store; more on containerd store | Direct, instant | **Local dev** |
| `docker-container` | `moby/buildkit` container managed by buildx | Yes (QEMU or native nodes) | All backends, `mode=max` | Needs `--load` (a tar round-trip) | CI on a Docker host; BuildKit config (mirrors, GC) you control |
| `remote` | Connect to a buildkitd you run | Yes | All | `--load` | **Shared CI builder** with persistent cache |
| `kubernetes` | buildx creates buildkitd Deployments | Yes (per-arch node selectors) | All | `--load` | Clusters with arm64 + amd64 node pools |

On this machine's containerd store, the `docker` driver exported a `type=local,mode=max` cache and loaded a two-platform image with `--load` (**verified**), both of which fail on the classic store. **That removes most reasons to run a `docker-container` builder locally.**

```bash
docker buildx ls
docker buildx inspect --bootstrap                   # current builder, platforms, GC policy
docker buildx create --name ci --driver docker-container \
  --driver-opt network=host \
  --buildkitd-config ~/.config/buildkit/buildkitd.toml \
  --bootstrap --use
docker buildx use default
docker buildx build --builder ci .                  # one-off without switching
docker buildx stop ci; docker buildx rm ci          # rm also deletes its cache volume
docker buildx du --builder ci                       # cache usage for that builder
```

A `buildkitd.toml` for the container builder, with a registry mirror and a GC cap:

```toml
# ~/.config/buildkit/buildkitd.toml
[registry."docker.io"]
  mirrors = ["mirror.gitlab.example.com"]

[registry."registry.gitlab.example.com"]
  ca = ["/etc/pki/ca-trust/source/anchors/internal-ca.pem"]

[worker.oci]
  gc = true
  maxUsedSpace = "30GB"     # hard cap; gckeepstorage is deprecated (= reservedSpace, a floor)
  minFreeSpace = "20GB"
```

> **Gotcha.** A `docker-container` builder's cache lives in a Docker volume named `buildx_buildkit_NAME0_state`. `docker buildx rm` deletes it; `docker system prune` does not touch it; `docker buildx prune --builder NAME` does. People lose a warm CI cache by "cleaning up" builders.

#### The default builder's GC is sized for a server

`docker buildx inspect default` here shows the default GC policy (**verified**): cache mounts and local sources kept 48 h up to 12.35 GiB, but everything else capped at **709.7 GiB max used** with 177.9 GiB min free — percentages of a large disk. That is why `docker system df` here reports 148 GB of build cache. Cap it in `daemon.json`:

```json
{
  "builder": {
    "gc": {
      "enabled": true,
      "defaultMaxUsedSpace": "30GB",
      "defaultMinFreeSpace": "20GB"
    }
  }
}
```

> **Version-sensitive.** Since Docker 28 / BuildKit's space-based GC, **`defaultKeepStorage` is deprecated and now means `defaultReservedSpace`** — a floor GC will *not* reclaim below, not a cap (moby `daemon/config/builder.go`; the same for `keepStorage` in `policy` rules and `gckeepstorage` / `keepBytes` in `buildkitd.toml`). The cap is `defaultMaxUsedSpace` (per rule: `maxUsedSpace`); `minFreeSpace` sets a free-disk target. An old `"defaultKeepStorage": "30GB"` therefore no longer limits the cache. The docs.docker.com garbage-collection page still shows `defaultKeepStorage` as a size limit as of 2026-09-23; the source (`UnmarshalJSON` copies it into `DefaultReservedSpace`) is what the daemon actually does, so set `defaultMaxUsedSpace` explicitly and you're right under either reading. Restart dockerd after changing it — the security chapter covers daemon changes.

### Multi-platform builds

Three ways to produce an arm64 image on an amd64 host, fastest first:

| Method | How | Speed | Use when |
|---|---|---|---|
| **Cross-compile** | `FROM --platform=$BUILDPLATFORM` + `GOOS/GOARCH` (or Rust targets, `npm` without native addons) | Native | **Go, Rust, JVM, pure-JS.** Always try this first |
| **Native nodes** | `docker buildx create --append` an arm64 node (SSH context to an arm box, or k8s arm pool) | Native | Heavy native compilation (C extensions, Python wheels from source) |
| **QEMU emulation** | binfmt_misc handlers + BuildKit runs arm64 `RUN` steps emulated | 5–20x slower | Anything else; small `RUN`s only |

The Go example in *Dockerfiles that behave* built `linux/amd64,linux/arm64` here with **no QEMU registered** (**verified**: `/proc/sys/fs/binfmt_misc/` holds only `register` and `status`) because only the final `COPY` touches the arm64 stage. `docker image ls --tree` then showed both platforms under one index.

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t IMAGE:TAG --push .
docker buildx build --platform linux/amd64,linux/arm64 -t IMAGE:TAG --load .   # containerd store only
docker image ls --tree IMAGE:TAG
docker buildx imagetools inspect IMAGE:TAG                                     # after push
```

**You may not need to install anything.** Docker's multi-platform docs state that official BuildKit releases bundle QEMU user-mode emulators; that means the `moby/buildkit` image behind a `docker-container` builder. The default `docker` driver uses the BuildKit inside dockerd, and the docker-ce RPM ships no emulators (**verified**: `rpm -ql docker-ce` has no `qemu` files), so on the default builder you register host handlers. Installing them (needs root; this guide did not run it):

```bash
# Option A: Fedora packages — persistent across reboots via systemd-binfmt
sudo dnf install qemu-user-static-aarch64    # one arch; qemu-user-static pulls every arch
systemctl status systemd-binfmt
grep flags /proc/sys/fs/binfmt_misc/qemu-aarch64   # must include F (fix_binary)

# Option B: the binfmt image (privileged, one-shot, lost on reboot)
docker run --privileged --rm tonistiigi/binfmt --install arm64,riscv64
```

The Fedora 43 subpackages drop `/usr/lib/binfmt.d/qemu-*-static.conf` files (**verified** with `dnf repoquery -l`). Docker requires static binaries registered with the `F` flag ([docs.docker.com](https://docs.docker.com/build/building/multi-platform/)).

> **Gotcha.** Emulated builds fail in ways that look like app bugs: `Illegal instruction`, segfaults in `npm install`, Go runtime crashes under old QEMU. If an arm64 `RUN` misbehaves only in CI, suspect QEMU before your code. Cross-compile or use a native node.

> **Gotcha.** A multi-platform build **without** `--push` or `--load` builds everything and then discards it, with only a warning. That's fine for a CI "does it build" check (`--output type=cacheonly` makes the intent explicit) and baffling otherwise.

#### Platform args in the Dockerfile

```dockerfile
FROM --platform=$BUILDPLATFORM golang:1.26 AS build
ARG TARGETOS TARGETARCH TARGETVARIANT
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH GOARM=${TARGETVARIANT#v} go build -o /out/app .

FROM --platform=$BUILDPLATFORM alpine:3.22 AS fetch
ARG TARGETARCH
RUN wget -O /kubectl "https://dl.k8s.io/release/v1.36.1/bin/linux/${TARGETARCH}/kubectl"
```

### Cache backends

The **layer cache** (not cache mounts) can be exported and imported so a fresh builder starts warm.

| Backend | `--cache-to` example | Stores | `mode=max` | Use for |
|---|---|---|---|---|
| `inline` | `type=inline` | Cache metadata inside the pushed image | **No** (min only) | Simplest; final stage only |
| `registry` | `type=registry,ref=REG/cache/app:main,mode=max` | Separate cache manifest in a registry | Yes | **CI default** |
| `local` | `type=local,dest=.buildx-cache,mode=max` | Directory | Yes | CI with a persistent cache dir or GitLab `cache:` |
| `gha` | `type=gha,mode=max` | GitHub Actions cache | Yes | GitHub only |
| `s3` / `azblob` | `type=s3,region=…,bucket=…` | Object storage | Yes | Large caches, many runners |

**`mode=min` vs `mode=max`:** `min` (the default) exports only the layers of the final image. `max` exports **every intermediate stage** — the dependency-install step in your `build` stage, the test stage. In a multi-stage build, `min` caches almost nothing useful. **Use `mode=max`** for registry and local caches.

```bash
docker buildx build \
  --cache-from type=registry,ref=REG/cache/app:main \
  --cache-from type=registry,ref=REG/cache/app:${BRANCH} \
  --cache-to   type=registry,ref=REG/cache/app:${BRANCH},mode=max,image-manifest=true,oci-mediatypes=true \
  -t REG/app:${SHA} --push .
```

- **Read from `main` and the branch, write to the branch.** Feature branches start from main's cache without polluting it.
- **`image-manifest=true,oci-mediatypes=true`** stores the cache as an OCI image manifest rather than an index-only artifact. GitLab's registry and Harbor handle it; older registries choke on the index form.
- **Keep cache in its own repository path** (`cache/app`) so cleanup policies and scanners can treat it differently from releasable images.

> **Gotcha.** Changing a build arg, a secret-derived `ARG`, or a base image digest invalidates everything below it, cache or not. When a "warm" CI build is still slow, run `docker buildx build --progress=plain` and look for the first step without `CACHED`.

### Outputs

| `--output` | Result | Shorthand |
|---|---|---|
| `type=image,name=REG/app:tag,push=true` | Pushed image | `--push` |
| `type=docker` | Loaded into local store | `--load` |
| `type=oci,dest=app.tar` | OCI layout tarball (keeps all platforms) | |
| `type=docker,dest=app.tar` | `docker load`-able tar | |
| `type=local,dest=./out` | The final stage's **filesystem** as files | |
| `type=tar,dest=out.tar` | Same, tarred | |
| `type=cacheonly` | Nothing; just populate cache | |
| `type=registry,compression=zstd,force-compression=true` | Pushed with zstd layers | |

`type=local` is the underrated one: build artifacts without an image.

```dockerfile
FROM build AS artifacts
FROM scratch AS export
COPY --from=build /out/app /app-linux-amd64
```

```bash
docker buildx build --target export --output type=local,dest=./dist .
ls dist/                       # app-linux-amd64, straight from the build
```

> **Note.** zstd layers decompress faster and compress smaller than gzip, and containerd, CRI-O and Podman all pull them. Any consumer still on an old runtime cannot. Use `compression=zstd` for internal images you control end-to-end.

### Attestations: SBOM and provenance

BuildKit can attach an SPDX SBOM and SLSA provenance to the image index as attestation manifests (the `unknown/unknown` platform entries described in *The model underneath*).

```bash
docker buildx build \
  --sbom=true \
  --provenance=mode=max \
  -t REG/app:${SHA} --push .

docker buildx imagetools inspect REG/app:${SHA} --format '{{json .SBOM}}' | jq '.SPDX.packages | length'
docker buildx imagetools inspect REG/app:${SHA} --format '{{json .Provenance}}' | jq '.SLSA.invocation'
```

| Flag | Produces | Notes |
|---|---|---|
| `--provenance=mode=min` | SLSA provenance: builder, source, platform | **Default for pushed images** since buildx 0.10 |
| `--provenance=mode=max` | + build args, full Dockerfile, every step | **Leaks build-arg values**; never pass secrets as args (you weren't anyway) |
| `--provenance=false` | None | For registries that reject attestation manifests |
| `--sbom=true` | SPDX SBOM from a Syft-based scanner in BuildKit | Scans the final stage |
| `--attest type=sbom,scan-stage=true` | SBOM for build stages too | Set `ARG BUILDKIT_SBOM_SCAN_STAGE=true` per stage |

> **Gotcha.** Attestations make the pushed reference an **index even for a single platform**. Tools that expected a plain manifest (old Helm charts pinning a per-arch digest, some registries' UIs, a few scanners) show `unknown/unknown` as a platform or reject the push. `--provenance=false` is the fix for those consumers; the better fix is updating them.

> **Note.** BuildKit attestations are *unsigned* statements attached to the image. Signing (cosign), verifying and gating on them belongs to the supply-chain chapter. The SBOM generated here is what that chapter's Trivy and cosign steps consume.

### Build checks and history

```bash
docker buildx build --check .                   # lint only (same as --call=check)
docker buildx build --call=outline .            # build args and secrets the Dockerfile expects
docker buildx build --call=targets .            # stages you can --target
docker buildx history ls                        # recent builds on this builder
docker buildx history inspect                   # last build: duration, cache ratio, errors
docker buildx history logs REF                  # replay the plain progress of a past build
docker buildx history trace REF                 # OpenTelemetry trace of the build
```

`--call=outline` is how you learn what a stranger's Dockerfile needs (`--build-arg`s, `--secret` ids) without reading it.

### Bake: the build graph in one file

`docker buildx bake` builds many targets from one declarative file, in parallel, sharing one BuildKit session (so shared stages build once). It is the replacement for the `build.sh` that loops over images with slightly different flags.

#### Anatomy

| Block | Purpose |
|---|---|
| `variable "NAME" { default = … }` | Overridable from env (`NAME=x docker buildx bake`) or `--var NAME=x` |
| `function "f" { params = [...]  result = … }` | Reusable expressions (tag lists, cache refs) |
| `target "name" { … }` | One build: context, dockerfile, target stage, tags, platforms, args, cache, attest, output |
| `inherits = ["_base"]` | Pull attributes from other targets; later wins |
| `matrix = { k = [...] }` + `name = "…${k}"` | Expand one target block into many |
| `group "name" { targets = [...] }` | Named sets; `default` runs with no arguments |

#### A complete docker-bake.hcl

```hcl
# docker-bake.hcl
variable "REGISTRY" {
  default = "registry.gitlab.example.com/group/project"
}

variable "TAG" {
  default = "dev"
}

variable "GIT_SHA" {
  default = ""
}

variable "CI" {
  type    = bool
  default = false
}

variable "PLATFORMS" {
  type    = list(string)
  default = ["linux/amd64"]
}

# tags: always :TAG, plus :GIT_SHA when set
function "tags" {
  params = [name]
  result = compact([
    "${REGISTRY}/${name}:${TAG}",
    notequal(GIT_SHA, "") ? "${REGISTRY}/${name}:${GIT_SHA}" : "",
  ])
}

# read main's cache and this branch's; write this branch's (CI only)
function "cache_from" {
  params = [name]
  result = [
    "type=registry,ref=${REGISTRY}/cache/${name}:main",
    "type=registry,ref=${REGISTRY}/cache/${name}:${TAG}",
  ]
}

function "cache_to" {
  params = [name]
  result = CI ? ["type=registry,ref=${REGISTRY}/cache/${name}:${TAG},mode=max,image-manifest=true,oci-mediatypes=true"] : []
}

group "default" {
  targets = ["api", "worker"]
}

group "ci" {
  targets = ["lint", "test", "api", "worker", "tools"]
}

# abstract base: leading underscore by convention, never built directly
target "_common" {
  dockerfile = "Dockerfile"
  platforms  = PLATFORMS
  labels = {
    "org.opencontainers.image.source"   = "https://gitlab.example.com/group/project"
    "org.opencontainers.image.revision" = GIT_SHA
  }
  args = {
    VERSION = TAG
  }
  attest = CI ? ["type=provenance,mode=max", "type=sbom"] : []
}

target "_go" {
  inherits = ["_common"]
  context  = "services/go"
  target   = "runtime"
}

target "api" {
  inherits   = ["_go"]
  tags       = tags("api")
  cache-from = cache_from("api")
  cache-to   = cache_to("api")
}

target "worker" {
  inherits   = ["_go"]
  tags       = tags("worker")
  args = {
    COMPONENT = "worker"
  }
  cache-from = cache_from("worker")
  cache-to   = cache_to("worker")
}

target "test" {
  inherits  = ["_go"]
  target    = "test"
  platforms = ["linux/amd64"]
  output    = ["type=cacheonly"]
  attest    = []
}

target "lint" {
  context    = "services/go"
  dockerfile = "Dockerfile"
  call       = "check"
}

# one block → tools-hadolint, tools-trivy
target "tools" {
  name      = "tools-${tool}"
  matrix    = {
    tool = ["hadolint", "trivy"]
  }
  inherits  = ["_common"]
  context   = "tools/${tool}"
  tags      = tags("tools-${tool}")
  platforms = ["linux/amd64"]
}
```

This file parses and resolves as described with buildx 0.37.1: `--list targets` shows `tools` expanding to `tools-hadolint` and `tools-trivy`; with `CI=true GIT_SHA=abc123 TAG=main`, `api` gets both tags, a `mode=max` cache export and both attestations (**verified** with `--print`).

#### Driving it

```bash
docker buildx bake --list targets                  # what can I build
docker buildx bake --list variables                # what can I override
docker buildx bake --print                          # resolved JSON for 'default' — no build
docker buildx bake                                  # build group "default"
docker buildx bake api                              # one target
docker buildx bake ci --push                        # the CI group, pushing
docker buildx bake --load api                       # into local store
TAG=feature-x GIT_SHA=$(git rev-parse --short HEAD) docker buildx bake --push
docker buildx bake --var TAG=feature-x --print api
PLATFORMS=linux/amd64,linux/arm64 docker buildx bake --push     # list vars take CSV from env
docker buildx bake --set '*.platform=linux/arm64' api            # override any attribute
docker buildx bake --set 'api.args.DEBUG=1' --set 'api.no-cache=true' api
docker buildx bake -f docker-bake.hcl -f docker-bake.override.hcl   # layer files; later wins
docker buildx bake --metadata-file bake-meta.json --push  # digests per target, for signing
```

> **Gotcha.** List attributes like **`cache-from`, `cache-to` and `attest` are appended on `inherits`, not replaced** — a `worker` that inherits `api` also reads `api`'s cache refs (**verified** with `--print`). Maps like `args` merge key by key (the `worker` above gets both `VERSION` and `COMPONENT`). `tags` and scalars are replaced. Inherit from abstract `_base` targets that don't set per-image lists, as above, rather than from sibling images.

> **Gotcha.** A `list(string)` variable overridden from the environment is parsed as **CSV**: `PLATFORMS=linux/amd64,linux/arm64` works; `PLATFORMS='["linux/arm64"]'` fails with `failed to convert variable PLATFORMS from CSV` (**verified**).

> **Note.** Bake also reads `compose.yaml` and `docker-bake.json`. Default file lookup is `compose.yaml`, `compose.yml`, `docker-compose.y*ml`, `docker-bake.json`, `docker-bake.hcl` and their `.override` variants. Keeping build config in `docker-bake.hcl` and runtime config in `compose.yaml` stops the two from fighting.

#### Why bake over a script

- **One BuildKit session.** Shared base stages across targets build once; independent targets build in parallel.
- **`--print` is a dry run** that shows the fully resolved config — reviewable in an MR.
- **`--metadata-file`** writes each target's pushed digest to JSON, which is exactly what `cosign sign` needs next (no re-resolving tags).
- **The same file drives local dev (`--load api`) and CI (`ci --push`)**, so "works locally" means the same build.

### Building in GitLab CI

Four real options on self-hosted GitLab. The deciding questions are: **can your runners run privileged containers**, and **do you want bake**.

| Option | Needs privileged | Bake | Cache persistence | Verdict |
|---|---|---|---|---|
| **buildx client → buildkitd as a service** | No (rootless buildkitd; runner needs a seccomp profile allowing `unshare`/`mount`) | **Yes** | Registry cache | **Default pick** |
| docker:dind service | **Yes** | Yes | Registry cache (dind is empty each job) | If you already run privileged runners |
| Shared remote buildkitd (long-lived) | No for jobs | Yes | **Local, warm** | High-volume monorepos; you operate a service |
| `buildctl-daemonless.sh` in `moby/buildkit:rootless` with `BUILDKITD_FLAGS: --oci-worker-no-process-sandbox` | No (same runner caveat) | **No** | Registry cache | GitLab's documented kaniko replacement; fine for single images |

> **Note.** kaniko is dead: the upstream repository was archived read-only in June 2025, and GitLab's docs now point at rootless BuildKit instead. Treat any kaniko job as tech debt with an end date.

#### Default: buildx + rootless buildkitd service

Run BuildKit as a job `service`, and drive it with the `docker:29-cli` image, which ships buildx v0.37.1 and compose v5.5.1 (**verified** by running it).

```yaml
# .gitlab-ci.yml
build:
  stage: build
  image: docker:29-cli
  services:
    - name: moby/buildkit:rootless
      alias: buildkitd
      entrypoint: ["rootlesskit", "buildkitd"]
      command: ["--addr", "tcp://0.0.0.0:1234", "--oci-worker-no-process-sandbox"]
  before_script:
    - mkdir -p ~/.docker
    - echo "{\"auths\":{\"$CI_REGISTRY\":{\"username\":\"$CI_REGISTRY_USER\",\"password\":\"$CI_REGISTRY_PASSWORD\"}}}" > ~/.docker/config.json
    - docker buildx create --name ci --driver remote tcp://buildkitd:1234 --use
    - docker buildx inspect --bootstrap
  script:
    - >
      CI=true TAG=$CI_COMMIT_REF_SLUG GIT_SHA=$CI_COMMIT_SHORT_SHA REGISTRY=$CI_REGISTRY_IMAGE
      docker buildx bake ci --push --metadata-file bake-meta.json
  artifacts:
    paths: [bake-meta.json]
    expire_in: 1 week
```

- **The service alias is reachable by name** on the Docker executor and on `localhost` on the Kubernetes executor (services share the pod's network namespace). On Kubernetes, use `tcp://localhost:1234`.
- **Registry auth sits in the client's `~/.docker/config.json`**; buildx forwards credentials to BuildKit per session.
- **`--metadata-file`** gives the signing job exact digests.
- Unencrypted TCP between job and service is acceptable because it never leaves the job's network namespace/pod. **Never** expose buildkitd TCP beyond that without mTLS (`--tlscacert`, `--tlscert`, `--tlskey`).

> **Gotcha.** `--oci-worker-no-process-sandbox` makes build steps share the buildkitd container's PID namespace; buildkitd's own help warns it lets build containers kill or ptrace other processes there (**verified** in `buildkitd --help`). Inside a throwaway CI service that is acceptable. On a long-lived shared buildkitd, it lets one project's build interfere with another's.

> **Gotcha.** Rootless BuildKit needs `unshare` and `mount`, which the default seccomp and AppArmor profiles block; BuildKit's [rootless docs](https://github.com/moby/buildkit/blob/master/docs/rootless.md) run it with `seccomp=unconfined` and `apparmor=unconfined` (plus `systempaths=unconfined`, which `--oci-worker-no-process-sandbox` makes unnecessary). On a non-privileged Docker-executor runner the symptom is `fork/exec /proc/self/exe: operation not permitted`. [GitLab's BuildKit page](https://docs.gitlab.com/ci/docker/using_buildkit/) says **not** to fix it with `security_opt = ["seccomp:unconfined"]`: give the runner's `security_opt` a custom seccomp profile that adds only what BuildKit needs, and AppArmor unconfined where the host runs AppArmor (Fedora uses SELinux instead). On the Kubernetes executor, BuildKit's rootless example sets `seccompProfile` and `appArmorProfile` to `Unconfined` in the securityContext. GitLab.com hosted runners are privileged and need nothing.

#### docker:dind (privileged runners)

```yaml
build-dind:
  image: docker:29-cli
  services:
    - name: docker:29-dind
      alias: docker
  variables:
    DOCKER_HOST: tcp://docker:2376
    DOCKER_TLS_CERTDIR: "/certs"
    DOCKER_TLS_VERIFY: "1"
    DOCKER_CERT_PATH: "/certs/client"
  before_script:
    - echo "$CI_REGISTRY_PASSWORD" | docker login -u "$CI_REGISTRY_USER" --password-stdin "$CI_REGISTRY"
    - docker buildx create --name ci --driver docker-container --use --bootstrap
  script:
    - CI=true TAG=$CI_COMMIT_REF_SLUG GIT_SHA=$CI_COMMIT_SHORT_SHA REGISTRY=$CI_REGISTRY_IMAGE docker buildx bake ci --push
```

- **Keep TLS on** (`DOCKER_TLS_CERTDIR`). Disabling it to "fix" a connection error exposes an unauthenticated root daemon on the job network.
- dind starts with an empty cache every job, so registry cache is mandatory.
- **A privileged runner is root on the runner host** for anyone who can push a `.gitlab-ci.yml`. Restrict those runners to protected branches or trusted projects via tags.

#### buildctl-daemonless (no bake)

GitLab's documented pattern, for when you need one image and nothing else:

```yaml
build-rootless:
  image:
    name: moby/buildkit:rootless
    entrypoint: [""]
  variables:
    BUILDKITD_FLAGS: --oci-worker-no-process-sandbox
  before_script:
    - mkdir -p ~/.docker
    - echo "{\"auths\":{\"$CI_REGISTRY\":{\"username\":\"$CI_REGISTRY_USER\",\"password\":\"$CI_REGISTRY_PASSWORD\"}}}" > ~/.docker/config.json
  script:
    - |
      buildctl-daemonless.sh build \
        --frontend dockerfile.v0 \
        --local context=. --local dockerfile=. \
        --opt platform=linux/amd64,linux/arm64 \
        --import-cache type=registry,ref=$CI_REGISTRY_IMAGE/cache:main \
        --export-cache type=registry,ref=$CI_REGISTRY_IMAGE/cache:$CI_COMMIT_REF_SLUG,mode=max \
        --output type=image,name=$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA,push=true
```

`entrypoint: [""]` is mandatory: without it the job runs the daemon and hangs.

#### Podman and buildah in CI

`podman build` / `buildah bud` also build rootless and read Dockerfiles, including `RUN --mount=type=cache` and `type=secret`. They don't run bake, and cache export is `--cache-to REG/cache` (layer cache only, no `mode=max` equivalent). Use them when the runner fleet is Podman-only; otherwise BuildKit's cache and bake win.

```bash
podman build --platform linux/amd64,linux/arm64 --manifest REG/app:TAG .
podman manifest push --all REG/app:TAG
podman farm build --platforms linux/amd64,linux/arm64 -t REG/app:TAG .   # native remote nodes
```

### Traps

- **`mode=min` cache on a multi-stage build.** Caches the final stage only. Use `mode=max`.
- **Relying on cache mounts in ephemeral CI.** They are not exported. Registry layer cache is what persists.
- **Multi-platform build with no `--push`/`--load`.** Built and discarded.
- **QEMU for compiled languages.** Cross-compile with `$BUILDPLATFORM`.
- **Inheriting from a sibling target in bake.** Cache lists append; you read the wrong cache.
- **`--provenance=mode=max` with secret build args.** It records their values.
- **Attestation index surprises.** A single-platform push is still an index; old consumers break.
- **Privileged dind with TLS disabled.** An open root daemon on the job network.
- **kaniko.** Archived. Migrate.
- **`docker buildx rm` on the CI builder.** Deletes its warm cache volume.


---


<a id="05-compose-for-real-stacks"></a>

## 05 · Compose for real stacks

*A compose.yaml is a declarative description of one project on one host: services, networks, volumes and the order they become healthy. Write the base file production-shaped, put the dev loop in an override, and render with docker compose config before you trust anything.*

Installed here: **Docker Compose v5.5.1** as a CLI plugin (**verified**). Compose skipped v3 and v4 as version numbers to avoid confusion with the old file-format versions; v5 is the same `docker compose` you know from v2, with builds delegated to bake. Everything in this chapter applies to v2.20+ unless flagged.

> **Note.** The top-level `version:` key is obsolete and ignored (Compose warns about it). The file format is the Compose Specification; there is one format, not v2/v3 variants. Name the file `compose.yaml`.

### The shape of a project

```text
  project "shop"  (name: key, -p, or directory name)
  ├── network  shop_frontend  ── proxy
  ├── network  shop_backend (internal: no egress) ── proxy, app, worker×2, migrate, db, cache
  ├── volume   shop_pgdata, shop_redisdata, shop_caddy_data
  ├── secret   db_password  → /run/secrets/db_password in each consumer
  └── config   caddyfile    → /etc/caddy/Caddyfile in proxy

  startup order, driven by depends_on conditions:

   db ──healthy──▶ migrate ──completed_successfully──▶ app ──healthy──▶ proxy
   cache ──healthy──────────────────────────────────▶ app
                               migrate ──completed──▶ worker ◀──healthy── cache
```

Every resource is prefixed with the project name, and every container carries `com.docker.compose.project` and `com.docker.compose.service` labels. **The project name is the identity**: run the same file from two directories with different names and you get two independent stacks, with two sets of volumes.

### A complete, realistic compose.yaml

App (FastAPI from *Dockerfiles that behave*), a worker, a one-shot migration, Postgres 18, Redis 8 and Caddy as the reverse proxy. This exact file was brought up here with `docker compose up -d --wait --build`: migration ran and exited 0, then `app`, both `worker` replicas and `proxy` came up in order and `curl http://127.0.0.1:8080/healthz` through Caddy returned `{"ok":true}` (**verified**).

```yaml
name: shop

x-app: &app
  build:
    context: .
    target: runtime
    args:
      APP_VERSION: ${APP_VERSION:-dev}
  image: ${REGISTRY:-local}/shop-app:${APP_VERSION:-dev}
  init: true
  restart: unless-stopped
  env_file:
    - path: .env.app
      required: false
  environment:
    DATABASE_HOST: db
    DATABASE_NAME: shop
    DATABASE_USER: shop
    DATABASE_PASSWORD_FILE: /run/secrets/db_password
    REDIS_URL: redis://cache:6379/0
    LOG_LEVEL: ${LOG_LEVEL:-info}
  secrets:
    - db_password
  networks: [backend]
  read_only: true
  tmpfs:
    - /tmp:size=64m
  security_opt:
    - no-new-privileges:true
  cap_drop: [ALL]
  deploy:
    resources:
      limits:
        memory: 512m
        cpus: "1.0"

services:
  proxy:
    image: caddy:2-alpine
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:80"
      - "127.0.0.1:8443:443"
    configs:
      - source: caddyfile
        target: /etc/caddy/Caddyfile
    volumes:
      - caddy_data:/data
    networks: [frontend, backend]
    depends_on:
      app:
        condition: service_healthy
        restart: true

  app:
    <<: *app
    command: ["--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
    expose: ["8000"]
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2).status == 200 else 1)"]
      interval: 10s
      timeout: 3s
      retries: 3
      start_period: 20s
      start_interval: 2s
    depends_on:
      migrate:
        condition: service_completed_successfully
      db:
        condition: service_healthy
      cache:
        condition: service_healthy
  worker:
    <<: *app
    entrypoint: ["python", "-m", "myapp.worker"]
    command: []
    healthcheck:
      disable: true          # the image's HTTP HEALTHCHECK doesn't apply to a worker
    depends_on:
      migrate:
        condition: service_completed_successfully
      cache:
        condition: service_healthy
    deploy:
      replicas: 2
      resources:
        limits:
          memory: 256m

  migrate:
    <<: *app
    entrypoint: ["python", "-m", "myapp.migrate"]
    command: []
    healthcheck:
      disable: true
    restart: "no"
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:18-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: shop
      POSTGRES_USER: shop
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets:
      - db_password
    volumes:
      - pgdata:/var/lib/postgresql
    networks: [backend]
    shm_size: 256m
    stop_grace_period: 30s
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U shop -d shop"]
      interval: 5s
      timeout: 3s
      retries: 10
      start_period: 10s
    deploy:
      resources:
        limits:
          memory: 1g

  cache:
    image: redis:8-alpine
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes", "--maxmemory", "200mb", "--maxmemory-policy", "allkeys-lru"]
    volumes:
      - redisdata:/data
    networks: [backend]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    deploy:
      resources:
        limits:
          memory: 256m

  adminer:
    image: adminer:5
    profiles: [debug]
    ports:
      - "127.0.0.1:8081:8080"
    networks: [backend]
    depends_on: [db]

  psql:
    image: postgres:18-alpine
    profiles: [tools]
    entrypoint: ["psql", "-h", "db", "-U", "shop", "shop"]
    environment:
      PGPASSFILE: /run/secrets/pgpass
    networks: [backend]
    depends_on:
      db:
        condition: service_healthy

networks:
  frontend: {}
  backend:
    internal: true

volumes:
  pgdata: {}
  redisdata: {}
  caddy_data: {}

secrets:
  db_password:
    file: ./secrets/db_password.txt

configs:
  caddyfile:
    content: |
      :80 {
        encode zstd gzip
        reverse_proxy app:8000 {
          health_uri /healthz
        }
      }
```

Decisions worth defending, line by line:

| Line | Why |
|---|---|
| `name: shop` | Pins the project name. Without it, renaming the checkout directory orphans your volumes |
| `x-app: &app` + `<<: *app` | Extension fields plus YAML anchors: one definition for app, worker and migrate |
| `"127.0.0.1:8080:80"` | Only the proxy publishes, and only on loopback |
| `backend: internal: true` | App, DB and cache have **no route out**. Proxy bridges frontend and backend |
| `expose: ["8000"]` | Documentation only; containers on the same network reach each other on any port |
| `init: true` | tini as PID 1; signals and zombie reaping without changing the image |
| `read_only` + `tmpfs` + `cap_drop: [ALL]` + `no-new-privileges` | Production-shaped by default; relaxed in the dev override |
| `deploy.resources.limits` | Honoured by `docker compose up` (not just Swarm) since Compose v2 |
| `*_FILE` env vars + `secrets:` | Password is a file in `/run/secrets`, never in `docker inspect` output |
| `pgdata:/var/lib/postgresql` | **Postgres 18 images moved the volume** to `/var/lib/postgresql` (data under `18/docker`); mounting the old `/var/lib/postgresql/data` path is the pre-18 layout |
| `shm_size: 256m` | Postgres parallel queries die on Docker's 64 MB `/dev/shm` default |
| `stop_grace_period: 30s` | Postgres gets time for a clean shutdown instead of SIGKILL at 10 s |
| `healthcheck: disable: true` on worker/migrate | They inherit the image's HTTP `HEALTHCHECK`, which can never pass for a worker |
| `configs: content:` | Small config inline, no extra file to lose |

> **Gotcha.** The first run of this file **failed** `--wait` with `container shop-worker-2 is unhealthy` (**verified**): the worker reused the app image, inherited its `HEALTHCHECK` curling port 8000, and nothing listens there. Any service that reuses an image for a different role needs its own `healthcheck:` or `disable: true`.

> **Gotcha.** YAML merge keys (`<<: *app`) are **shallow**. The worker's `deploy:` replaced the whole anchored `deploy:` mapping, so its `cpus: "1.0"` limit silently disappeared; only `memory: 256m` survived (**verified** in `docker compose config --format json`). Override a nested block and you must restate all of it. Compose's own override-file merge (below) is deep; YAML anchors are not.

### depends_on that actually waits

| Form | Waits for | Use |
|---|---|---|
| `depends_on: [db]` | Container **started** (not ready) | Almost never enough |
| `condition: service_started` | Same, long form | Explicit version of the above |
| `condition: service_healthy` | Healthcheck passes | **Databases, caches, anything with a readiness signal** |
| `condition: service_completed_successfully` | Container **exited 0** | Migrations, seeders, init jobs |
| `restart: true` | Restart this service when the dependency is restarted by Compose | Proxies and clients that cache connections |
| `required: false` | Start even if the dependency isn't in the model / enabled profile | Optional sidecars |

`restart: true` is not decorative: during the `develop.watch` test below, a `sync+restart` of `app` also restarted `proxy` (**verified** in the watch output), because proxy declares `app` with `restart: true`.

```bash
docker compose up -d --wait                 # block until all running/healthy; non-zero if not
docker compose up -d --wait --wait-timeout 120
docker compose up --abort-on-container-failure --exit-code-from tests tests   # CI: test runner decides
```

> **Gotcha.** `depends_on` orders **startup only within one `up`**. It does not restart the app when the database dies later, and it does not apply when you `docker compose restart db`. The app must still retry its connections. Readiness gating at startup and resilience at runtime are different problems.

> **Note.** `docker compose up --wait` is the Compose equivalent of `kubectl wait --for=condition=Ready`. Use it in scripts and CI instead of `sleep`.

### Profiles

Services with `profiles:` are off unless a matching profile is enabled. Services without `profiles:` are always on.

```bash
docker compose config --profiles                        # debug, tools (verified)
docker compose --profile debug up -d                    # + adminer
COMPOSE_PROFILES=debug,tools docker compose up -d
docker compose run --rm psql                            # naming a service enables its profile
docker compose --profile '*' config --services          # everything
```

Good profile uses: debug UIs (adminer, mailpit, redis-insight), one-shot tools (`psql`, `pgdump`), load generators, an observability sidecar set. **Bad use:** environments. `dev`/`prod` as profiles leads to every service being duplicated; use override files for that.

### Override files and -f layering

`docker compose` with no `-f` reads `compose.yaml` **and** `compose.override.yaml` if present, merged in that order. `-f` replaces that default with an explicit list, merged left to right.

```text
  compose.yaml              production-shaped base, committed
  compose.override.yaml     dev loop (ports, watch, debug env), committed, auto-loaded
  compose.ci.yaml           CI tweaks (no ports, test runner), used with -f
  compose.prod.yaml         prod host specifics, used with -f
```

The dev override for this stack, which moves the dev loop out of the base file:

```yaml
# compose.override.yaml — merged automatically by `docker compose up`; dev only
services:
  app:
    read_only: false                 # watch sync writes into the container
    ports:
      - "127.0.0.1:8000:8000"        # hit the app directly, bypassing the proxy
    environment:
      LOG_LEVEL: debug
    develop:
      watch:
        - action: sync+restart
          path: ./src/myapp
          target: /app/.venv/lib/python3.14/site-packages/myapp
          ignore:
            - "**/__pycache__"
        - action: rebuild
          path: uv.lock
        - action: rebuild
          path: pyproject.toml
  db:
    ports:
      - "127.0.0.1:5432:5432"
```

```bash
docker compose up -d                                        # compose.yaml + compose.override.yaml
docker compose -f compose.yaml -f compose.ci.yaml up -d     # override NOT loaded
docker compose -f compose.yaml -f compose.prod.yaml config  # render the prod view
COMPOSE_FILE=compose.yaml:compose.prod.yaml docker compose up -d   # colon-separated, direnv-friendly
```

#### How merging works

| Field kind | Merge behaviour | Example |
|---|---|---|
| Scalars (`image`, `command`, `read_only`) | Later file **replaces** | `read_only: false` wins |
| Mappings (`environment`, `labels`, `deploy`) | **Deep merge** by key | `LOG_LEVEL: debug` added/replaced, other keys kept |
| Sequences (`ports`, `expose`, `dns`, `volumes`) | **Merged** (appended/unique by target) | Override adds `8000:8000` next to base ports |
| `!reset` tag | Set the field back to empty/default | `deploy: !reset {}` removes limits |
| `!override` tag | Replace a sequence/mapping wholesale | `ports: !override [...]` drops base ports |

`!override` on `ports` replaced the base list, and `!reset {}` on `deploy` removed it entirely, while `environment` merged by key (**verified** with `docker compose config --format json`).

> **Gotcha.** Without `!override`, you **cannot remove** a port or volume from the base in an override; you can only add. People discover this when prod still publishes the debug port from the base file.

### include

`include` pulls another Compose file into the model as a sub-project, with **its own project directory** for relative paths and its own `.env`. It is the answer to "the platform team maintains the observability stack, we maintain the app".

```yaml
# compose.yaml
include:
  - path: ../platform/observability/compose.yaml
    env_file: ../platform/observability/.env
  - infra/mailpit.compose.yaml

services:
  app:
    # can depend_on and share networks with included services
    depends_on: [otel-collector]
```

| | `include` | `-f a -f b` | `extends` |
|---|---|---|---|
| Relative paths resolve from | **The included file's dir** | The first file's dir | The extended file's dir |
| Conflicting service names | **Error** | Merge | N/A (per service) |
| Granularity | Whole file | Whole file | One service |
| Use for | Composing independently owned stacks | Environment layering | Reusing one service definition across files |

A two-file include test resolved services from both (**verified**). Include is strict on purpose: a name collision is an error rather than a silent merge.

### Environment: interpolation vs container env

Two separate mechanisms that people conflate:

```text
  INTERPOLATION  (Compose reads ${VAR} in the YAML, before anything runs)
     shell env  >  --env-file FILE(s)  >  .env in project dir  >  ${VAR:-default}
                   (if --env-file is given, .env is NOT read)

  CONTAINER ENV  (what the process sees)
     compose run -e  >  environment:  >  env_file:  >  image ENV
```

Precedence for interpolation, all **verified** on the stack above with `LOG_LEVEL` (`${LOG_LEVEL:-info}` in the file):

| Setup | Result |
|---|---|
| `.env` has `LOG_LEVEL=warn` | `warn` |
| `.env` has `warn`, shell has `LOG_LEVEL=debug` | `debug` — shell wins |
| `--env-file other.env` (no LOG_LEVEL in it), `.env` has `warn` | `info` — **`.env` ignored**, default used |
| `--env-file .env --env-file other.env` | `warn` — multiple env files merge |

Interpolation syntax:

| Syntax | Unset | Empty | Use |
|---|---|---|---|
| `${VAR}` | `""` + warning | `""` | Rarely; the warning is easy to miss |
| `${VAR:-default}` | default | default | **Normal default** |
| `${VAR-default}` | default | `""` | Allow explicit empty |
| `${VAR:?message}` | **error** | **error** | **Required values** (`${DB_PASSWORD:?set DB_PASSWORD}`) |
| `${VAR?message}` | error | `""` | Required but may be empty |
| `${VAR:+alt}` | `""` | `""` | `alt` only when set, e.g. optional flags |
| `$$` | literal `$` | | Shell variables in `command:` evaluated in the container |

```bash
docker compose config --variables             # every ${VAR}, whether required, default (verified)
docker compose config --environment           # the interpolation environment Compose resolved
docker compose config | grep -n LOG_LEVEL     # what actually landed
```

> **Gotcha.** A `.env` file in the project directory is read for **interpolation**, not injected into containers. To give a container its variables, use `env_file:`. Two files, two purposes; naming the container file `.env.app` (as above) keeps them apart.

> **Gotcha.** `env_file:` parsing is not shell parsing: quoting and `${}` handling differ between Compose versions and from `docker run --env-file`. Keep values simple, and check what landed with `docker compose config` rather than assuming.

### develop.watch: the dev loop

`docker compose watch` (or `up --watch`) watches paths on the host and applies an action per rule.

| Action | Does | Use for |
|---|---|---|
| `sync` | Copy changed files into the running container | Code with hot reload (Vite, `uvicorn --reload`, nodemon) |
| `sync+restart` | Copy, then restart the container | Code without hot reload |
| `sync+exec` | Copy, then run a command in the container | Rebuild assets, `kill -HUP 1` |
| `restart` | Restart only | Config files read at start |
| `rebuild` | Rebuild the image and recreate the container | Lockfiles, Dockerfile, system deps |

```bash
docker compose up --watch                     # up + watch in one, logs attached
docker compose watch                          # up, then watch
docker compose watch --no-up app              # watch an already-running stack
```

With the override above, an edit to `src/myapp/main.py` appeared inside the container within seconds and the output read `service(s) ["app"] restarted`; `app` returned to `healthy` (**verified**).

Why the override sets `read_only: false`: sync writes into the container filesystem, which fails on a read-only root. **Watch belongs in the dev override precisely because the base file is production-shaped.**

> **Gotcha.** `sync` targets must match where the image actually runs code from. With the uv example's `--no-editable` install, the code lives in `site-packages/myapp`, not `/app/src`, so the sync target is the site-packages path. Get it wrong and syncs succeed, nothing changes, and you debug your app for an hour.

> **Note.** Watch versus bind-mounting the source: bind mounts are instant and bidirectional but drag host UID/GID and SELinux labels into the container, and on Fedora with Podman need `:Z`. Watch keeps the container self-contained and the image honest. **Default: watch**; bind mounts only for tools that must write back to the host (formatters, codegen).

### Secrets and configs

| | `secrets:` | `configs:` |
|---|---|---|
| Mounted at | `/run/secrets/NAME` (default) | `/NAME` or `target:` |
| Sources | `file:`, `environment:` | `file:`, `environment:`, `content:` |
| Encrypted at rest | No (plain file bind) on standalone Compose | No |
| Visible in `docker inspect` | Path only, not the value | Path only |
| Use | Passwords, tokens, keys | Config files |

```yaml
secrets:
  db_password:
    file: ./secrets/db_password.txt          # gitignored; created by a bootstrap script
  api_token:
    environment: API_TOKEN                   # from the shell / CI variable at up time

services:
  app:
    secrets:
      - db_password
      - source: api_token
        target: api_token
        mode: 0400
```

On standalone Compose, secrets are bind mounts of files: **the value never enters `docker inspect` or the process environment**, which is the entire point. The official Postgres, MySQL and many other images accept `*_FILE` variants of their password variables for exactly this.

> **Gotcha.** File-based secrets are bind mounts, so the file keeps its **host** ownership and permissions; the [Compose spec](https://github.com/compose-spec/compose-spec/blob/main/05-services.md) says Docker Compose does not implement `uid`/`gid`/`mode` when the source is `file:`, because a bind mount cannot remap ownership. The restriction is stated only for `file:`; `environment:` (and, on configs, `content:`) sources are copied into the container rather than bind-mounted, so the attributes apply there (not tested here). That is why the `mode: 0400` above sits on `api_token`. A non-root container user must be able to read a file-sourced secret on the host. `chmod 0444` the dev secret, or use `environment:` as the source.

### Render before you trust

`docker compose config` resolves interpolation, merges every `-f` file and override, applies profiles, normalises short syntax, and prints the canonical model. **Diff it, review it, lint it.**

```bash
docker compose config                              # full resolved YAML
docker compose config -q                           # validate only; exit code
docker compose config --services
docker compose config --images                     # every image, for pre-pull or scanning
docker compose config --volumes
docker compose config --format json | jq '.services.app.environment'
docker compose config --resolve-image-digests      # tags → digests in the output
docker compose config --lock-image-digests -o compose.digests.yaml   # override file pinning digests
docker compose config --no-interpolate             # see the raw ${VAR} form
docker compose -f compose.yaml -f compose.prod.yaml config > rendered.prod.yaml
docker compose build --print                       # the bake definition Compose will build (v5)
```

`--lock-image-digests` is the underrated one: it writes an override that pins every service image to the digest resolved now, so a deploy is reproducible without editing the base file.

> **Gotcha.** `docker compose config` **prints secrets passed via `environment:` interpolation** in cleartext. Don't paste its output into an MR or ticket without checking.

### Daily Compose commands

```bash
docker compose up -d --wait --build              # build if needed, start, wait for healthy
docker compose ps --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'
docker compose logs -f --tail 100 app worker
docker compose exec app sh
docker compose run --rm migrate                  # one-off container from a service definition
docker compose run --rm --no-deps app python -m myapp.shell
docker compose restart app
docker compose up -d --no-deps --force-recreate app    # recreate one service only
docker compose pull && docker compose up -d --wait     # update images
docker compose stop                              # stop, keep containers
docker compose down                              # remove containers + networks, KEEP volumes
docker compose down --remove-orphans             # also containers of removed services
docker compose ls                                # all projects on this daemon
docker compose -p shop ps                        # by project name, from anywhere
docker compose top; docker compose stats
docker compose cp app:/app/report.csv .
```

> **One-way door.** `docker compose down -v` removes the project's **named volumes** — the Postgres data. It is the same command as `down` with two characters added, and it appears in countless READMEs as "reset everything". Alias it to something you cannot type by accident, or never alias it at all.

### Podman and Compose

`podman compose` is a thin wrapper that runs an external provider against Podman's socket. On this machine it executes `/usr/libexec/docker/cli-plugins/docker-compose` (Compose v5.5.1) because `docker-compose` takes precedence over `podman-compose` when installed (**verified**, `podman compose version`).

| Approach | What runs | Fidelity | Use when |
|---|---|---|---|
| `podman compose` → docker-compose provider | Real Compose against Podman's Docker-compatible API | **High**; `watch`, profiles, include all work | **Default** if you want Compose on Podman |
| `DOCKER_HOST=unix://…/podman.sock docker compose` | Same thing, explicitly | High | Scripts |
| `podman-compose` (Python) | Translates to `podman` CLI calls, can put services in a pod | Lower: lags the spec, `develop.watch` and newer keys vary | No Docker packages allowed |
| Quadlet `.container` / `.pod` units | systemd-managed containers | Not Compose | **Production on Podman** (runtime chapter) |

```bash
systemctl --user enable --now podman.socket      # the provider needs the API socket
podman compose up -d --wait
podman compose ps
export PODMAN_COMPOSE_PROVIDER=podman-compose    # force the Python implementation
```

> **Gotcha.** `podman.socket` is **inactive** for this user right now (**verified**, `systemctl --user is-active podman.socket`). `podman compose` with the docker-compose provider needs it; enable it first or the provider can't reach an engine.

> **Gotcha.** Rootless Podman can't publish ports below 1024 by default, and SELinux is enforcing for its containers, so bind mounts need `:Z` (or `:z`). A compose file that works on docker-ce, where SELinux isn't confining containers, can fail on Podman with `permission denied` on every bind mount. Add the suffix, or prefer volumes.

### Traps

- **No `name:`.** Rename the directory and your data volumes are orphaned under the old project name.
- **Plain `depends_on: [db]`.** Waits for "started", not "ready". Use `condition: service_healthy`.
- **Reused images inheriting a `HEALTHCHECK`.** Workers go `unhealthy`; `--wait` fails.
- **Shallow YAML anchors.** Overriding a nested key drops its siblings.
- **Trying to remove base ports in an override.** Needs `!override` or `!reset`.
- **`.env` expected inside containers.** It's for interpolation. Use `env_file:`.
- **`--env-file` silently dropping `.env`.** Pass both if you need both.
- **Watch with a read-only root, or the wrong sync target.** Silent no-op.
- **Secrets via `environment:`.** Visible in `inspect` and in `config` output.
- **`down -v` as "reset".** Deletes the database.
- **`0.0.0.0` ports in a compose file on a laptop.** Write `127.0.0.1:` explicitly on every `ports:` entry.


---


<a id="06-networking-and-storage"></a>

## 06 · Networking and storage

*Docker networking is Linux bridges plus NAT rules that dockerd writes into netfilter ahead of your firewall, and Docker storage is either managed by Docker (volumes) or borrowed from the host (bind mounts). On Fedora, the firewall and SELinux are where both of those assumptions bite.*

State of this machine, because it drives several recommendations below (**verified**): firewalld is **inactive**, Docker's firewall backend is `iptables` with the userland proxy enabled, SELinux is **enforcing** for the host but docker-ce runs containers as `spc_t`, and three running containers publish ports on all interfaces.

### Network drivers

| Driver | What the container gets | Isolation | Use for |
|---|---|---|---|
| `bridge` (default `docker0`) | veth into `docker0`, 172.17.0.0/16, NAT out | Own netns | Legacy; **no DNS between containers** |
| **user-defined `bridge`** | veth into `br-XXXX`, own subnet, **embedded DNS** | Own netns | **Default for everything** |
| `host` | The host's network namespace | None; `-p` ignored | Network tools, max throughput, apps that need many ports |
| `none` | Loopback only | Total | Batch jobs that must not talk |
| `macvlan` | Its own MAC and IP on your LAN | L2 on the physical network | Appliances that must look like a real host (DHCP, mDNS) |
| `ipvlan` (L2/L3) | LAN IP, shares the parent's MAC | L2/L3 | macvlan on Wi-Fi, or where the switch limits MACs |
| `overlay` | VXLAN across Swarm nodes | Multi-host | Swarm only |
| `container:NAME` | Another container's netns | Shared | Sidecars, debugging (`netshoot`) |

```text
            host network namespace
  ┌────────────────────────────────────────────────────────────────┐
  │  eth0 / wlp0s20f3  192.168.0.42                                  │
  │     │                                                            │
  │     │  netfilter:  PREROUTING DNAT  :8080 ─▶ 172.25.0.3:80        │
  │     │              POSTROUTING MASQUERADE 172.25.0.0/16 ─▶ eth0   │
  │     │              FORWARD  DOCKER-USER ─▶ DOCKER-FORWARD ─▶ …     │
  │     ▼                                                            │
  │  br-3f1a (172.25.0.1)          docker0 (172.17.0.1)               │
  │   ├─ vethA ──┐                   └─ vethC ──┐                     │
  │   └─ vethB ──┼──┐                           │                     │
  └──────────────┼──┼───────────────────────────┼─────────────────────┘
          ┌──────┘  └──────┐              ┌─────┘
     ┌────▼─────┐     ┌────▼─────┐   ┌────▼──────┐
     │ netns    │     │ netns    │   │ netns     │
     │ eth0     │     │ eth0     │   │ eth0      │
     │172.25.0.2│     │172.25.0.3│   │172.17.0.2 │
     │ "db"     │     │ "app"    │   │ (default  │
     │ DNS via  │     │          │   │  bridge,  │
     │127.0.0.11│     │          │   │  no DNS)  │
     └──────────┘     └──────────┘   └───────────┘
```

### User-defined networks and DNS

**Always create a network**; never rely on the default bridge. Compose does this for you (one `PROJECT_default` network).

```bash
docker network create app-net
docker run -d --name db  --network app-net postgres:18-alpine
docker run -d --name api --network app-net --network-alias backend IMAGE
docker run --rm --network app-net alpine:3.22 getent hosts db backend
docker network connect other-net api            # a container can join several networks
docker network inspect app-net -f '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
```

Verified here: on a user-defined network, `/etc/resolv.conf` points at **`nameserver 127.0.0.11`** (Docker's embedded resolver), container names and `--network-alias` values resolve, and on the default bridge the same lookup fails.

| Resolves on a user-defined network | How |
|---|---|
| Container name | Embedded DNS |
| `--network-alias` / Compose service name | Embedded DNS; several containers can share an alias (round-robin) |
| Anything else | Forwarded to the host's resolvers (from the host `/etc/resolv.conf`) |

> **Gotcha.** Fedora uses systemd-resolved, so the host's `/etc/resolv.conf` points at `127.0.0.53`, which is unreachable from inside a container. Docker detects this and uses the upstream servers from `/run/systemd/resolve/resolv.conf` instead — a default-bridge container here got `nameserver 192.168.0.1`, the router, not `127.0.0.53` (**verified**). When DNS works on the host but not in containers after a VPN connects, the VPN's split-DNS servers usually live only in resolved's per-link config. Fix with `"dns": [...]` in `daemon.json` or `--dns` per container.

> **Note.** `internal: true` networks (`docker network create --internal`) have no gateway: containers can talk to each other but not to the outside. It's the cheapest egress control you have, and the Compose example in *Compose for real stacks* uses it for the backend tier.

#### Reaching the host from a container

```bash
docker run --rm --add-host host.docker.internal:host-gateway alpine:3.22 \
  wget -qO- http://host.docker.internal:8000/
```

`host-gateway` resolves to the bridge gateway IP (`172.17.0.1` here, per the BuildKit worker label). The host service must listen on that address or `0.0.0.0`, not just `127.0.0.1`. Podman provides `host.containers.internal` automatically.

### Port publishing and the rules Docker writes

`-p HOST_IP:HOST_PORT:CONTAINER_PORT` makes dockerd write NAT and filter rules, and (with the userland proxy on, as here) start a `docker-proxy` process per published port for traffic that originates on the host itself.

```text
 packet from LAN ─▶ PREROUTING (nat) ─▶ DOCKER chain: DNAT dport 8080 → 172.25.0.3:80
                          │
                          ▼  destination is now a container IP, so it is FORWARDED, not INPUT
                     FORWARD (filter) ─▶ DOCKER-USER (your rules; empty by default)
                          │            ─▶ Docker's forward/accept rules for published ports
                          ▼
                     br-XXXX ─▶ veth ─▶ container :80

 host firewall INPUT zone rules never see this packet.
```

| Publish form | Binds | Reachable from |
|---|---|---|
| `-p 8080:80` | `0.0.0.0:8080` **and** `[::]:8080` | **Everything that can route to you** |
| `-p 127.0.0.1:8080:80` | Loopback only | This host |
| `-p 192.168.0.42:8080:80` | One interface | That network |
| `-p 8080:80/udp` | UDP | As above |
| `-p 127.0.0.1::80` | Random high port on loopback | This host; `docker port NAME` tells you which |
| `-P` | Every `EXPOSE`d port to random high ports on `0.0.0.0` | Everything; avoid |

Look at the rules (read-only, needs root):

```bash
sudo iptables -t nat -S DOCKER                 # the DNATs
sudo iptables -S DOCKER-USER                   # your hook
sudo iptables -S FORWARD | head               # jumps to DOCKER-USER, DOCKER-FORWARD, DOCKER-INGRESS
sudo iptables -S DOCKER-FORWARD                # then DOCKER-BRIDGE, DOCKER-CT, DOCKER-INTERNAL, DOCKER
sudo nft list ruleset | less                   # iptables-nft rules appear as nft tables too
sudo nft list table ip docker-bridges          # nftables backend only
ss -tlnp | grep docker-proxy                   # userland proxy listeners
docker port NAME
```

> **Version-sensitive.** Docker 29 removed the `DOCKER-ISOLATION-STAGE-1/2` chains and adds **experimental** native nftables support via `"firewall-backend": "nftables"` in `daemon.json` (`dockerd --help` here lists `--firewall-backend string  iptables or nftables`, **verified**; 29.0.0 release notes). iptables remains the default and is what this machine uses. In nftables mode Docker writes the `ip docker-bridges` / `ip6 docker-bridges` tables, does not enable IP forwarding for you (it errors instead), refuses Swarm mode, and has no `DOCKER-USER` chain: you add rules in your own nft table with base chains at a **lower priority number** than Docker's (docs.docker.com, "Docker with nftables").

#### The firewalld interaction on Fedora

This is the single most common Docker security surprise on Fedora and RHEL.

1. **Published ports bypass firewalld zones.** DNAT happens in PREROUTING, the packet is forwarded to the bridge, and firewalld's zone rules for INPUT never apply. `firewall-cmd --list-all` looks locked down; `-p 5432:5432` is open to the LAN anyway.
2. **When firewalld is running**, dockerd puts its bridges into a firewalld zone named **`docker`** (target `ACCEPT`) and adds a `docker-forwarding` policy, so container egress works. Reloading firewalld used to flush Docker's rules and break container networking until `systemctl restart docker`; Docker 29's release notes say firewalld reloads no longer cause that outage.
3. **Fedora Workstation's default zone already allows inbound TCP/UDP 1025–65535**, so on a Workstation install firewalld wouldn't have blocked most dev ports even if Docker respected it.
4. **If firewalld is inactive, nothing filters inbound traffic at all**, and every `-p PORT:PORT` is reachable from any network the machine joins. Audit what you actually expose with the `dexposed` function from *Daily CLI by intent*: a `kind` cluster on `0.0.0.0:80/443` or a dev registry on all interfaces is the usual finding.

**The fix, in order of preference:**

1. **Write `127.0.0.1:` on every publish** — `-p 127.0.0.1:5432:5432`, and every Compose `ports:` entry. This is the only form that is correct on every host and every network type.
2. **Make loopback the default for user-defined networks**, which is where Compose puts everything. The daemon-wide `"ip"` key does **not** cover them:

```yaml
# compose.yaml — every un-addressed publish on this network binds 127.0.0.1
networks:
  default:
    driver_opts:
      com.docker.network.bridge.host_binding_ipv4: "127.0.0.1"
```

```bash
docker network create -o com.docker.network.bridge.host_binding_ipv4=127.0.0.1 app-net
```

A container on such a network published with a bare `-p 18999:80` bound only `127.0.0.1:18999` (**verified**, `docker port`).
3. **Set `"ip": "127.0.0.1"` in `/etc/docker/daemon.json`** for the **default bridge only** — Docker's port-publishing docs are explicit that this key applies to the default bridge network, and user-defined networks need the driver option above. It's still worth setting (the hardened `daemon.json` in the daemon chapter includes it), but it will not protect a Compose stack on its own.

- **Filter in `DOCKER-USER`** when you must publish on the LAN but restrict sources:

```bash
# allow only the office subnet to reach published container ports arriving on wlp0s20f3
sudo iptables -I DOCKER-USER -i wlp0s20f3 ! -s 10.20.0.0/16 -j DROP
# with firewalld running, the persistent equivalent is a direct rule or a policy on the docker zone
```

> **One-way door.** Publishing a port on `0.0.0.0` on a machine that ever joins untrusted networks (conference Wi-Fi, a hotel, a client site) exposes that service to everyone on the segment, and firewalld will not stop it. For a database with a default password, that exposure is the whole incident. **Default to `127.0.0.1`.**

> **Version-sensitive.** In releases older than **28.0.0**, hosts on the same L2 segment (same switch) can reach ports published to `127.0.0.1` (docs.docker.com port-publishing page; fixed in 28.0.0 by moby#49325, which also stopped remote hosts reaching published ports via the container IP). On Docker 27 or older, loopback publishing is not a complete boundary against a neighbour on the LAN. Not reproduced here.

#### IPv6

```bash
docker network create --ipv6 v6-net
docker network inspect v6-net -f '{{json .IPAM.Config}}'
```

On Docker 29 here, `--ipv6` with no subnet auto-allocated a ULA `/64` (`fdc9:b770:44d3::/64`) alongside the IPv4 subnet (**verified**). `ip6tables` rules are on by default (`--ip6tables` default true in `dockerd --help`).

| Need | Setting |
|---|---|
| IPv6 on user-defined networks | `docker network create --ipv6` (Compose: `enable_ipv6: true`) |
| IPv6 on the default bridge | `"ipv6": true, "fixed-cidr-v6": "fd00:dead:beef::/64"` in `daemon.json` |
| Your own ULA pools | `"default-address-pools"` with IPv6 entries |
| Published ports | `-p 8080:80` binds `[::]:8080` too; `-p '[::1]:8080:80'` for v6 loopback |

> **Gotcha.** A published port on `[::]` is reachable over IPv6 even if you only thought about IPv4 filtering. Any source filter in `DOCKER-USER` needs an `ip6tables` twin.

#### Address pool collisions

Docker allocates bridge subnets from `172.17.0.0/16` upward and `192.168.x`. The `kind` network here is `172.18.0.0/16` and a test network got `172.25.0.0/16` (**verified**). If your VPN or office LAN uses 172.16/12, containers lose routes to it. Pin the pools once:

```json
{
  "default-address-pools": [
    { "base": "10.200.0.0/16", "size": 24 },
    { "base": "fd00:200::/48", "size": 64 }
  ]
}
```

#### host, macvlan and ipvlan

```bash
docker run --rm --network host nicolaka/netshoot ss -tlnp      # sees host sockets
docker network create -d macvlan \
  --subnet 192.168.0.0/24 --gateway 192.168.0.1 --ip-range 192.168.0.224/27 \
  -o parent=enp5s0 lan
docker run -d --network lan --ip 192.168.0.230 --name dns-appliance IMAGE
docker network create -d ipvlan -o parent=wlp0s20f3 -o ipvlan_mode=l2 \
  --subnet 192.168.0.0/24 --gateway 192.168.0.1 wifi-lan
```

> **Gotcha.** With macvlan, **the host cannot talk to its own macvlan containers** (the kernel doesn't hairpin between a parent and its macvlan children). Add a macvlan sub-interface on the host with an IP in the range, or use ipvlan. And most Wi-Fi access points drop frames from extra MACs, so macvlan on a laptop's wireless NIC fails silently; ipvlan L2 works.

#### Podman networking

| | Docker (rootful) | Podman rootless (here: `pasta`, `netavark`, **verified**) |
|---|---|---|
| Container egress | NAT via bridge | `pasta` user-mode networking, copies host addresses into the netns |
| Port publishing | DNAT in netfilter | `pasta` listens on the host port and forwards; **no firewall bypass** |
| Container-to-container DNS | Embedded 127.0.0.11 | `aardvark-dns` on user-defined networks |
| Source IP seen by the app | Real client IP | Real client IP with pasta (was a problem with slirp4netns) |
| Host from container | `host-gateway` | `host.containers.internal` |

Rootless Podman publishing is a normal userspace listener, so firewalld (when running) filters it like any other process's port. That is a real security difference, not just a mechanism difference.

### Storage: volumes, bind mounts, tmpfs

| | Named volume | Bind mount | tmpfs |
|---|---|---|---|
| Lives at | `/var/lib/docker/volumes/NAME/_data` (Podman: `~/.local/share/containers/storage/volumes`) | Wherever you point it | RAM |
| Managed by | Docker (`docker volume …`) | You | Kernel |
| Pre-populated from image | **Yes**, if empty on first mount | No; hides image content | No |
| Survives `docker rm` | Yes | Yes | No |
| Host UID/SELinux issues | Minimal | **Yes** | No |
| Portable across hosts | Via backup | Path must exist | N/A |
| Performance | Native fs | Native fs | RAM |
| Use for | **Databases, app state** | Source code in dev, host config files | Secrets scratch, `/tmp` with `--read-only` |

```bash
docker volume create pgdata
docker volume ls --filter dangling=true              # not used by any container
docker volume inspect pgdata -f '{{.Mountpoint}} {{.CreatedAt}}'
docker system df -v | sed -n '/Local Volumes/,/Build cache/p'
docker run --rm --mount type=volume,src=pgdata,dst=/data,volume-nocopy alpine:3.22 ls /data
```

> **Gotcha.** A new, empty named volume is **populated with whatever the image has at the mount path** on first use. That's convenient for Postgres, and a trap for app code: mount a volume over `/app/node_modules`, and the first run copies the image's modules into it; rebuild the image with new modules and the stale volume wins forever. Use `volume-nocopy` or don't volume-mount build output.

> **Gotcha.** A bind mount **hides** the image's content at that path. `-v "$PWD":/app` over an image that installed dependencies into `/app` makes them vanish.

#### SELinux: `:z` and `:Z`

With SELinux confining containers, a process labelled `container_t` may only read files labelled `container_file_t` (or a few other types). `:z` and `:Z` tell the engine to relabel the bind source:

| Suffix | Relabels to | Shared between containers | Use for |
|---|---|---|---|
| `:z` | `container_file_t:s0` | **Yes** | A directory several containers read |
| `:Z` | `container_file_t:s0:cX,cY` (this container's MCS pair) | **No**, private | One container's data dir |
| none | Unchanged | — | Fails with `Permission denied` under Podman |

What actually happens on this machine (**verified** in a scratch directory labelled `user_tmp_t`):

| Engine | No suffix | `:z` | `:Z` |
|---|---|---|---|
| **docker-ce** (SELinux off in daemon; containers are `spc_t`) | Reads fine | **No relabel** (label stays `user_tmp_t`) | **No relabel** |
| **Podman** (SELinux on) | `cat: can't open '/d/f': Permission denied` | Relabels shared | Relabelled to `container_file_t:s0:c70,c320`, read works |

So on docker-ce as installed here, the suffixes are harmless no-ops, and containers are not SELinux-confined at all. Compose files and scripts should still carry `:z`/`:Z` so they work on Podman, on Fedora's `moby-engine`, and on a docker-ce daemon with `"selinux-enabled": true`.

> **One-way door.** **Never `:Z` (or `:z`) a system or home directory**: `-v /home/you:/h:Z` or `-v /etc:/etc:z` relabels the host tree recursively. `:Z` then makes it readable only by that container's MCS pair, and your own login, sshd or systemd services can start failing on AVC denials. Recovery is `sudo restorecon -Rv PATH`, if you notice which path it was. Relabel only dedicated data directories.

```bash
ls -Zd ./data                                   # before
podman run --rm -v ./data:/data:Z alpine:3.22 ls /data
ls -Zd ./data                                   # container_file_t:s0:cX,cY
sudo restorecon -Rv ./data                      # undo
sudo ausearch -m AVC -ts recent | tail          # denials when you forget the suffix
podman run --rm --security-opt label=disable -v ./data:/data alpine:3.22 ls /data   # opt out per container
```

For rootless Podman UID problems (as opposed to label problems), the suffix is `:U` (chown the source to the container user) or `--userns=keep-id`. *The model underneath* covers why.

#### tmpfs

```bash
docker run --rm --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --mount type=tmpfs,dst=/run,tmpfs-size=16m,tmpfs-mode=1777 \
  IMAGE
```

tmpfs counts against the container's memory cgroup. A 1 GB tmpfs in a 512 MB container is an OOM kill waiting for a big upload.

### Back up and restore a volume

The pattern: a throwaway container mounts the volume and a host directory, and `tar` does the work. No need to know where Docker keeps the files, and it works identically on Podman.

```bash
# back up (read-only mount of the volume)
docker run --rm \
  -v pgdata:/data:ro \
  -v "$PWD":/backup \
  alpine:3.22 tar -czf /backup/pgdata-$(date +%F).tgz -C /data .

# restore into a NEW volume, then point the service at it
docker volume create pgdata-restored
docker run --rm \
  -v pgdata-restored:/data \
  -v "$PWD":/backup:ro \
  alpine:3.22 sh -c 'cd /data && tar -xzf /backup/pgdata-2026-09-23.tgz'

# copy volume to volume
docker run --rm -v pgdata:/from:ro -v pgdata-copy:/to alpine:3.22 cp -a /from/. /to/

# stream to another host over SSH
docker run --rm -v pgdata:/data:ro alpine:3.22 tar -cz -C /data . \
  | ssh other-host 'docker run --rm -i -v pgdata:/data alpine:3.22 tar -xz -C /data'
```

> **Gotcha.** A file-level copy of a **running** database's data directory is a crash-consistent snapshot at best, and a corrupt one at worst. For Postgres, either `docker compose stop db` first, or take a logical dump with the database's own tool:

```bash
docker compose exec -T db pg_dump -U shop -Fc shop > shop-$(date +%F).dump
docker compose exec -T db pg_restore -U shop -d shop --clean < shop-2026-09-23.dump
```

**Restore into a new volume, never over the live one.** If the restore is bad, the original is still there. Podman adds `podman volume export NAME > vol.tar` and `podman volume import NAME vol.tar`, which do the tar step for you.

### Registries

#### Login and credential helpers

```bash
docker login registry.gitlab.example.com            # prompts; stores per config below
echo "$TOKEN" | docker login -u USER --password-stdin registry.gitlab.example.com
docker logout registry.gitlab.example.com
glab auth configure-docker                          # wires docker-credential-glab for GitLab hosts
```

Where credentials land, in `~/.docker/config.json`:

| Key | Stores | Verdict |
|---|---|---|
| `auths.HOST.auth` | **base64 `user:password`** in the file — not encrypted | Avoid on workstations |
| `credsStore` | All hosts via one helper (`secretservice`, `pass`) | Good default for everything else |
| `credHelpers.HOST` | Per-host helper (`glab`, `gcloud`, `ecr-login`) | **Best**: short-lived tokens minted on demand |

On this machine, `credHelpers` covers `gitlab.com`, `registry.gitlab.com` and a GCP Artifact Registry host via `docker-credential-glab` and `docker-credential-gcloud`, `auths` holds no entries, and there is no `credsStore` (**verified**, key names only). So a `docker login` to any *other* registry would write a base64 password into the file. Add a store for the rest:

```json
{
  "credsStore": "secretservice",
  "credHelpers": {
    "registry.gitlab.example.com": "glab",
    "northamerica-northeast1-docker.pkg.dev": "gcloud"
  }
}
```

`docker-credential-secretservice` (GNOME Keyring via libsecret) ships in the `docker-credential-helpers` releases on GitHub; it is not installed here.

> **Gotcha.** Podman reads `${XDG_RUNTIME_DIR}/containers/auth.json` first and falls back to `~/.docker/config.json`. The runtime dir is tmpfs, so `podman login` credentials vanish at logout, and a `podman pull` that "worked yesterday" is actually using stale Docker credentials. Use `podman login --authfile` explicitly in scripts, or configure `credential-helpers` in `containers-registries.conf`.

#### A local registry

```bash
docker run -d --name registry --restart unless-stopped \
  -p 127.0.0.1:5000:5000 \
  -v registry-data:/var/lib/registry \
  registry:3

docker tag IMAGE localhost:5000/IMAGE:dev
docker push localhost:5000/IMAGE:dev
curl -s http://localhost:5000/v2/_catalog | jq
docker buildx imagetools inspect localhost:5000/IMAGE:dev
```

- **`registry:3`** is the current CNCF Distribution image (it resolves today, **verified**); `registry:2` still exists and behaves the same for this use.
- **`127.0.0.0/8` and `::1` are insecure-registries by default** (`docker info` here, **verified**), so plain HTTP to `localhost:5000` works with no config. Any other hostname needs TLS or an `insecure-registries` entry.
- **kind and k3d** want a registry on the same Docker network plus a containerd mirror config on the nodes; the Kubernetes field manual covers that wiring.
- Deleting images from `registry:3` needs `REGISTRY_STORAGE_DELETE_ENABLED=true` plus a garbage-collect run; for anything beyond a dev cache, run Harbor or Zot instead.

#### Mirrors and pull-through caches

For Docker Hub, `daemon.json` has a first-class mirror setting:

```json
{
  "registry-mirrors": ["https://mirror.gitlab.example.com"]
}
```

| Scope | Docker | Podman / containerd |
|---|---|---|
| Docker Hub | `registry-mirrors` in `daemon.json` | `registries.conf` `[[registry]] location="docker.io"` + `[[registry.mirror]]` |
| Any other registry | **No daemon setting**; rewrite references or use BuildKit `buildkitd.toml` mirrors for builds | `registries.conf` mirrors work for any registry |
| Build-time only | `buildkitd.toml` `[registry."docker.io"] mirrors = [...]` (*BuildKit, buildx and bake*) | `registries.conf` |

```toml
# ~/.config/containers/registries.conf — Podman: mirror Docker Hub and ghcr through an internal cache
[[registry]]
location = "docker.io"
[[registry.mirror]]
location = "mirror.gitlab.example.com/dockerhub"

[[registry]]
location = "ghcr.io"
[[registry.mirror]]
location = "mirror.gitlab.example.com/ghcr"
```

> **Gotcha.** Docker's `registry-mirrors` applies only to Docker Hub pulls and falls back to Hub silently if the mirror fails. You won't notice the mirror is down until Hub's anonymous pull rate limit (counted per source IP) hits a whole office behind one NAT. Authenticate pulls (`docker login` to Hub) or front Hub with a pull-through cache that has its own account.

> **Note.** Podman on this machine runs with `short-name-mode = "enforcing"` and searches `registry.fedoraproject.org`, `registry.access.redhat.com`, then `docker.io` (**verified**, `/etc/containers/registries.conf`). `podman pull nginx` prompts or fails in a script. Fully qualified names (`docker.io/library/nginx:1.29-alpine`) are the only portable form.

### Traps

- **Default bridge.** No DNS between containers. Always use a user-defined network.
- **`-p` without an address.** `0.0.0.0` and `[::]`, past firewalld. Write `127.0.0.1:`; `"ip"` in `daemon.json` only covers the default bridge, so set `host_binding_ipv4` on Compose networks.
- **Trusting `firewall-cmd --list-all`.** It doesn't describe Docker-published ports.
- **Subnet collisions with the VPN.** Pin `default-address-pools`.
- **macvlan on Wi-Fi or host-to-macvlan traffic.** Use ipvlan or a host shim.
- **Volume over build output.** First-run copy wins forever.
- **`:Z` on a home or system directory.** Recursive relabel; `restorecon` to undo.
- **Assuming `:z`/`:Z` matter on docker-ce.** They're no-ops unless the daemon has SELinux enabled; keep them for Podman portability.
- **File-level backup of a live database.** Stop it or use the database's dump tool; restore into a new volume.
- **`auths` with base64 passwords.** Use credential helpers.
- **Hub mirror as a silent fallback.** Monitor it, authenticate pulls.


---


<a id="07-runtime-security-least-privilege"></a>

## 07 · Runtime security: least privilege

*A container is a process with a few kernel features switched on. Every flag in this chapter either removes a privilege that process inherited by default or refuses to hand it a new one — and the biggest privilege of all sits outside the container, on whoever can reach the daemon socket.*

### The threat model in one diagram

Two separate questions, and people answer the wrong one:

1. **Who can drive the engine?** Anyone who can talk to the Docker API can start a container that mounts `/` from the host. That is root on the host, full stop.
2. **What can a compromised process inside a container do?** That depends on the user it runs as, the capabilities it holds, the syscalls seccomp lets through, the SELinux label, the filesystem it can write, and the user namespace it lives in.

```text
  you (docker group) ──▶ /run/docker.sock ──▶ dockerd (root) ──▶ containerd ──▶ runc
        │                                              │
        │   question 1: who can reach this socket?     │ question 2: what does the
        └──────────── = who is root on this host ──────┘ process get by default?
                                                          ├─ uid 0 (unless USER/--user)
                                                          ├─ 14 capabilities
                                                          ├─ default seccomp profile
                                                          ├─ SELinux label (only if enabled)
                                                          ├─ writable rootfs
                                                          └─ no pid / memory / cpu limits
```

Everything below is ordered from biggest win to smallest. If you only do the first three sections, you have done most of the work.

### The docker group is root

**Membership in the `docker` group is equivalent to passwordless sudo.** The socket is `root:docker 0660` (verified on this host: `srw-rw----. 1 root docker /var/run/docker.sock`), and anyone who can write to it can do this:

```bash
# Illustration only — do not run on a machine you care about.
docker run --rm -it -v /:/host alpine chroot /host sh
# You are now root on the host filesystem, with no password prompt and no sudo log entry.
```

There is no flag, no daemon setting and no SELinux policy that makes rootful Docker's API safe to hand out. **Treat adding a user to `docker` exactly like adding them to `wheel` with `NOPASSWD`.**

Check who holds it right now:

```bash
getent group docker
id -nG          # your own groups
```

What to do instead, in order of preference:

| Need | Do this | Why |
|---|---|---|
| Developer workstation | **Podman rootless**, or rootless Docker | Containers run inside your user namespace; escaping one gets an attacker your UID, not root |
| CI runner building images | Rootless BuildKit / Podman / Buildah, or a dedicated throwaway VM per job | The runner host is compromised by design the moment any job can run arbitrary Dockerfiles |
| Shared host, several operators | `sudo docker` with an audited sudoers rule, not the group | At least you get a log line per command |
| A tool that "needs the socket" | A socket proxy that allows only read endpoints (see [never mount docker.sock](#never-mount-dockersock)) | Narrow the API instead of handing over the whole thing |

> **Gotcha.** Rootless Docker only helps if the *rootful* daemon is also stopped and the user is removed from the `docker` group. Running both leaves the root-equivalent path exactly where it was.

### Rootless: the default pick

**Default: Podman rootless on Fedora.** It is the distribution default, needs no daemon, integrates with systemd through Quadlet (chapter 10), and has the best SELinux integration. Pick **rootless Docker** when a toolchain hard-depends on the Docker API or on Docker-only features (Compose-specific behaviour, `buildx` builders, Testcontainers defaults) — the tiebreaker is whether the tool can be pointed at Podman's Docker-compatible socket.

#### How rootless actually works

The daemon (or Podman itself) runs as your UID inside a user namespace. Container UID 0 maps to your UID; container UIDs 1–65535 map to your subordinate range from `/etc/subuid`.

```bash
grep "^$USER:" /etc/subuid /etc/subgid
podman unshare cat /proc/self/uid_map
```

Verified on this host:

```text
         0       1001          1        # container root  = host UID 1001 (me)
         1     589824      65536        # container 1..    = host 589824..655359
```

**A container "root" that escapes lands as an unprivileged host user** who cannot read `/etc/shadow`, load kernel modules or touch other users' files. That is the whole point.

#### Podman rootless

Nothing to install on Fedora; it is the default when you run `podman` as a normal user.

```bash
podman info --format '{{.Host.Security.Rootless}} cgroups={{.Host.CgroupsVersion}} selinux={{.Host.Security.SELinuxEnabled}}'
# true cgroups=v2 selinux=true
```

Useful rootless-specific flags:

| Flag | Does | When |
|---|---|---|
| `--userns keep-id` | Maps your host UID to the same UID inside the container | Bind-mounting your source tree and wanting files owned by you, not by a subordinate UID |
| `--userns auto` | Allocates a fresh, non-overlapping range per container | Rootful Podman, to get per-container isolation without thinking about ranges |
| `--uidmap` / `--gidmap` | Explicit mapping | You need a specific host UID to own a volume |
| `podman unshare CMD` | Runs `CMD` inside your user namespace | `chown` a volume directory to a container UID: `podman unshare chown 10001:10001 ./data` |

```bash
podman run --rm --userns keep-id docker.io/library/alpine:3 id
# uid=1001(you) gid=1002(you) groups=1002(you)
```

> **Version-sensitive.** Podman 5.0 made **pasta** the default rootless network backend (replacing slirp4netns). Source IP is preserved and performance is better; if you are reading an older guide that tunes slirp4netns, ignore it.

#### Rootless Docker

```bash
# The rootful daemon must be off, and you must not be in the docker group.
sudo systemctl disable --now docker.service docker.socket
dockerd-rootless-setuptool.sh install        # ships with docker-ce on Fedora: /usr/bin/dockerd-rootless-setuptool.sh
sudo loginctl enable-linger "$USER"          # keep the user daemon running after logout
docker context use rootless
docker info --format '{{.SecurityOptions}}'  # expect name=rootless in the list
```

The installer creates a `rootless` CLI context; the socket is `unix:///run/user/UID/docker.sock`.

Known limitations (from the upstream rootless docs; verify against your version):

| Limitation | Workaround |
|---|---|
| Ports below 1024 | `sysctl net.ipv4.ip_unprivileged_port_start=80` (host-wide), or publish on 8080 and front it |
| Resource limits (`--memory`, `--cpus`, `--pids-limit`) | Need cgroup v2 **and** systemd delegation of the controllers to the user slice |
| Source IP of clients | The default `builtin` port driver hides it; set `"userland-proxy": false` or switch `DOCKERD_ROOTLESS_ROOTLESSKIT_NET` to `pasta`/`slirp4netns` |
| Not supported | AppArmor, checkpoint, overlay networks (Swarm), SCTP ports, NFS as `data-root` |

> **Version-sensitive.** Until Docker Engine 29.5, ports a rootless container listened on with `--net=host` were not reachable from the real host network namespace. On 29.5+ they are.

Check controller delegation for resource limits:

```bash
cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/cgroup.controllers
# must include: cpu memory pids   (io optional)
```

#### Rootful plus userns-remap

The middle option: rootful daemon, but every container runs in one shared remapped range owned by a `dockremap` user. It is covered in chapter 08 because it is a daemon setting. **Short version: prefer rootless.** userns-remap is one range for all containers, it hides every existing image and container when you turn it on, and it is incompatible with `--privileged` (unless `--userns=host`), `--pid=host` and `--network=host`.

### Run as a non-root user

**Every image you build sets `USER` to a numeric UID.** Numeric, because Kubernetes' `runAsNonRoot` and some admission policies cannot resolve names, and because a name that does not exist in the image's `/etc/passwd` fails at start.

```dockerfile
# In the final stage
USER 10001:10001
```

At run time, override or enforce:

```bash
docker run --user 10001:10001 IMAGE
docker run --user 65534:65534 IMAGE      # nobody:nobody, for images that ship no user
```

Verify what an image defaults to before you run it:

```bash
docker image inspect IMAGE --format '{{.Config.User}}'   # empty string = root
```

> **Gotcha.** A non-root user inside a rootful container is still a real host UID. `--user 1000` in a rootful container is *your* UID on most workstations, which means it can write your home directory if you bind-mount it. Pick a UID that does not exist on the host (10001+).

### Capabilities: drop ALL, add back one

The default Docker capability set is 14 capabilities, including `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, `SETGID`, `NET_RAW`, `NET_BIND_SERVICE`, `KILL`, `MKNOD`, `AUDIT_WRITE`, `SYS_CHROOT`, `SETPCAP`, `SETFCAP` and `FSETID`. Verified here — a default container's effective set:

```bash
docker run --rm alpine:3 grep CapEff /proc/self/status
# CapEff: 00000000a80425fb
```

and with `--cap-drop ALL`:

```text
CapEff: 0000000000000000
CapBnd: 0000000000000000
```

Decode a mask with `capsh` (from `libcap`). Docker's default versus Podman's, both verified here:

```bash
capsh --decode=00000000a80425fb   # Docker: 14 caps, includes net_raw, mknod, audit_write
capsh --decode=00000000800405fb   # Podman: 11 caps, none of those three
```

**Default: `--cap-drop ALL`, then add back only what fails.** Almost every web service needs nothing at all once it runs as non-root on a port above 1024.

| Capability | Add it when | Better alternative |
|---|---|---|
| `NET_BIND_SERVICE` | Must listen on <1024 inside the container | Listen on 8080 and publish `-p 80:8080` |
| `CHOWN`, `FOWNER`, `DAC_OVERRIDE` | Entrypoint `chown`s a volume at start (many official DB images) | Pre-own the volume (`podman unshare chown`, or an init step) and drop them |
| `SETUID`, `SETGID` | Entrypoint drops from root to a service user (`gosu`, `su-exec`) | Start as that user with `--user` so no switch is needed |
| `NET_RAW` | `ping`, raw sockets | Almost never in production; it enables ARP/ICMP spoofing on the bridge |
| `SYS_PTRACE` | Debugging only | A debug sidecar, removed afterwards |
| `NET_ADMIN` | VPN / routing containers | A dedicated, reviewed exception |
| `SYS_ADMIN` | Never — it is "most of root" | Find the specific capability or syscall the tool needs |

Find what a failing process wanted:

```bash
# Rerun with the default set and look at what is in use; or trace the denial
docker run --rm --cap-drop ALL IMAGE 2>&1 | head    # read the EPERM
journalctl -k | grep -i 'capability'                 # some denials are logged by the kernel/audit
```

> **Gotcha.** Official images like `postgres`, `redis` and `nginx` start as root and step down. With `--cap-drop ALL` they fail with `chown: Operation not permitted` or `setgroups: Operation not permitted`. Either add back exactly `CHOWN SETUID SETGID` (and `DAC_OVERRIDE` if it complains), or use the image's documented non-root mode (`--user` plus a pre-owned data directory).

### no-new-privileges

`--security-opt no-new-privileges=true` sets the kernel's `PR_SET_NO_NEW_PRIVS` bit on the container's init. After that, **setuid binaries and file capabilities cannot grant more privilege than the process already has** — `sudo`, `su`, `ping` with file caps, and any setuid-root binary an attacker drops into `/tmp` all stop working as privilege escalations.

Verified:

```bash
docker run --rm --security-opt no-new-privileges=true alpine:3 grep NoNewPrivs /proc/self/status
# NoNewPrivs: 1
```

There is almost no reason not to set it. Make it the daemon default (`"no-new-privileges": true` in `daemon.json`, chapter 08) so you cannot forget.

> **Gotcha.** Images whose entrypoint uses `su`, `sudo` or `gosu` to switch users break under `no-new-privileges` *only* if they rely on setuid bits. `gosu`/`su-exec` use `setuid()` directly with `CAP_SETUID` and still work; `sudo` does not. The fix is the same as above: start as the target user.

### Seccomp profiles

Seccomp filters syscalls. Docker's default profile blocks around 40–50 syscalls that have no business in a normal container (`kexec_load`, `init_module`, `mount`, `umount2`, `swapon`, `reboot`, `bpf` for unprivileged, `keyctl`, `add_key`, `userfaultfd`, `perf_event_open`, `unshare` with namespace flags, and friends). It is applied automatically:

```bash
docker info --format '{{.SecurityOptions}}'     # [name=seccomp,profile=builtin name=cgroupns]  (verified)
docker run --rm alpine:3 grep Seccomp /proc/self/status
# Seccomp: 2      (2 = filter mode; 0 would mean unconfined)
```

**Default: keep the builtin profile. Never run `--security-opt seccomp=unconfined` in production.** It is the first thing a container-escape exploit hopes you did.

#### Custom profiles

Write one only when (a) you want to *tighten* for a high-value service, or (b) the default blocks something legitimate and you want to allow exactly that syscall rather than disable the filter.

Start from the upstream default rather than from scratch:

```bash
curl -fsSLo seccomp-default.json \
  https://raw.githubusercontent.com/moby/profiles/main/seccomp/default.json
```

Allow one extra syscall (example: an app that genuinely needs `personality` with a flag the default refuses):

```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "defaultErrnoRet": 1,
  "archMap": [ { "architecture": "SCMP_ARCH_X86_64", "subArchitectures": ["SCMP_ARCH_X86", "SCMP_ARCH_X32"] } ],
  "syscalls": [
    { "names": ["read", "write", "openat", "close", "..."], "action": "SCMP_ACT_ALLOW" }
  ]
}
```

```bash
docker run --security-opt seccomp=./seccomp-app.json IMAGE
podman run --security-opt seccomp=./seccomp-app.json IMAGE
```

Generating a tight profile from observed behaviour:

| Tool | How | Notes |
|---|---|---|
| **`oci-seccomp-bpf-hook`** (Podman) | `podman run --annotation io.containers.trace-syscall=of:/tmp/profile.json IMAGE` | Needs root and the hook package; records syscalls via eBPF. Fedora packages it |
| `strace -f -c` | Run the binary outside a container and collect the syscall list | Crude but dependency-free |
| Inspektor Gadget `advise seccomp-profile` | Kubernetes-side | For when the target is a pod, not a local container |

> **Gotcha.** A recorded profile only contains the syscalls your test exercised. The error path, the log-rotation path and the TLS-renegotiation path you did not hit will fail in production with `EPERM`. Record under a realistic load test and keep `defaultAction` as `SCMP_ACT_ERRNO`, not `SCMP_ACT_KILL`, so failures are visible errors rather than silent deaths.

### SELinux labels on Fedora

On Fedora with SELinux enforcing, Podman runs every container as `container_t` with a **unique MCS category pair**, so container A cannot read container B's files even if both run as the same UID. Verified on this host:

```bash
podman run --rm docker.io/library/alpine:3 cat /proc/self/attr/current
# system_u:system_r:container_t:s0:c352,c533
```

**Docker only does this if the daemon runs with `--selinux-enabled`.** On this host it does not — `docker info` lists only `seccomp` and `cgroupns` under Security Options, and a Docker container runs unconfined:

```bash
docker run --rm alpine:3 cat /proc/self/attr/current
# system_u:system_r:spc_t:s0          <- "super privileged container": no SELinux confinement
```

That is the docker-ce default. Turn it on with `"selinux-enabled": true` in `daemon.json` (chapter 08) — and then expect bind mounts that worked before to fail until you relabel them.

#### Volume labels: :z and :Z

| Suffix | Relabels the host path to | Use when |
|---|---|---|
| `:Z` | `container_file_t` with **this container's** MCS pair | The directory belongs to one container |
| `:z` | `container_file_t` with **no** MCS pair (shared) | Several containers share the directory |
| none | unchanged | The path is already labelled for containers, or SELinux is off for the engine |

Verified with rootless Podman:

```bash
podman run --rm -v ./data:/data alpine cat /data/f       # Permission denied
podman run --rm -v ./data:/data:Z alpine cat /data/f     # hi
ls -Z ./data/f
# system_u:object_r:container_file_t:s0:c145,c537 ./data/f
```

> **One-way door.** `:Z` / `:z` **permanently relabel the host path**. Never put them on `/`, `/home`, `/usr`, `/etc`, `/var` or your whole home directory — you will relabel system files and break logins or services, and the only fix is `restorecon -R` on the affected tree (or a full relabel on reboot). Label the narrowest directory possible.

Other SELinux knobs:

```bash
--security-opt label=disable            # run this container unconfined (spc_t). Last resort, per container
--security-opt label=type:container_t   # choose a type (udica can generate custom ones)
--security-opt label=level:s0:c100,c200 # pin an MCS pair so two containers share files
```

**udica** generates a tailored SELinux policy from a container's inspect output when `container_t` is too tight and `label=disable` is too loose:

```bash
podman inspect CONTAINER > container.json
sudo udica -j container.json my_app
sudo semodule -i my_app.cil /usr/share/udica/templates/base_container.cil
podman run --security-opt label=type:my_app.process IMAGE
```

### Read-only root filesystem

`--read-only` mounts the container's root filesystem read-only. An attacker who gets code execution cannot drop a binary into `/usr/local/bin`, rewrite your app, or persist anything. **Give the app writable scratch space explicitly with `--tmpfs`**, and put real data on a volume.

```bash
docker run --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=64m \
  --tmpfs /run:rw,noexec,nosuid,nodev,size=8m \
  -v app-data:/data \
  IMAGE
```

Verified — root is read-only, `/tmp` works:

```text
touch: /x: Read-only file system
tmp-ok
```

Podman differs usefully here: `--read-only` automatically mounts writable tmpfs on `/dev`, `/dev/shm`, `/run`, `/tmp` and `/var/tmp` (`--read-only-tmpfs`, default `true`). Set `--read-only-tmpfs=false` to get the strict Docker-like behaviour.

Find what an app writes before you lock it down:

```bash
docker run -d --name probe IMAGE
# exercise it, then:
docker diff probe          # A = added, C = changed, D = deleted
docker rm -f probe
```

Every path in that output needs a tmpfs, a volume, or a config change to stop writing it.

> **Gotcha.** `noexec` on `/tmp` breaks tools that extract and execute native code there — JNA/JNI libraries in the JVM, some Python wheels, Node native addons. Point them elsewhere (`-Djava.io.tmpdir=/app/tmp` on a separate exec-allowed tmpfs) rather than dropping `noexec` everywhere.

### Resource limits

Without limits, one container can take the whole host. On cgroup v2 (verified: `Cgroup Version: 2`, `Cgroup Driver: systemd`) these map directly to files you can read inside the container.

| Flag | cgroup v2 file | Default | Recommendation |
|---|---|---|---|
| `--pids-limit N` | `pids.max` | Docker: unlimited; Podman: 2048 | **Always set.** 256 is plenty for most services; it stops fork bombs cold |
| `--memory 512m` | `memory.max` | unlimited | **Always set.** Memory is not compressible |
| `--memory-swap 512m` | `memory.swap.max` (as memory+swap) | 2× memory if swap exists | Set equal to `--memory` to disable swap for the container |
| `--memory-reservation` | `memory.low` | none | Soft floor under pressure |
| `--cpus 1.5` | `cpu.max` | unlimited | Optional. See chapter 10 for why CPU limits often hurt |
| `--cpu-shares` / `--cpu-weight` | `cpu.weight` | 1024 / 100 | Relative priority, only matters under contention |
| `--ulimit nofile=4096:8192` | rlimit | inherited | Set when the app opens many sockets |

Verified inside a limited container:

```bash
docker run --rm --pids-limit 64 --memory 64m --memory-swap 64m --cpus 0.5 alpine:3 \
  cat /sys/fs/cgroup/pids.max /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.max
# 64
# 67108864
# 50000 100000
```

**Never use `--oom-kill-disable` without a memory limit.** With no limit, it lets a leaking container push the host kernel into OOM-killing *host* processes instead.

### Never --privileged

`--privileged` turns off almost every protection in this chapter at once:

- all capabilities, including `SYS_ADMIN`, `SYS_MODULE`, `SYS_RAWIO`
- seccomp disabled
- SELinux / AppArmor confinement disabled (`spc_t` / unconfined)
- every host device visible in `/dev`, including disks
- `/sys` and `/proc` writable

From a privileged container, `mount /dev/sda1 /mnt` or loading a kernel module is a one-liner host takeover. **A privileged container is not a container; it is a root shell with extra steps.**

What people actually needed, and what to use instead:

| Wanted | Use instead |
|---|---|
| Access one device (GPU, serial, USB) | `--device /dev/ttyUSB0` or CDI: `--device nvidia.com/gpu=all` |
| Mount filesystems inside the container | Do the mount on the host and bind it in |
| Docker-in-Docker for CI | Rootless BuildKit (`moby/buildkit:rootless`), Podman/Buildah in a container, Kaniko-style builders, or a VM per job |
| `sysctl` changes | `--sysctl net.core.somaxconn=1024` for namespaced sysctls |
| Debugging with ptrace/perf | `--cap-add SYS_PTRACE` on a throwaway debug container, or `nsenter` from the host |
| systemd inside a container | Podman does this unprivileged: `podman run --systemd=always IMAGE` |

Find privileged containers on a host:

```bash
docker ps -q | xargs -r docker inspect --format '{{.Name}} privileged={{.HostConfig.Privileged}} caps={{.HostConfig.CapAdd}}' | grep -E 'privileged=true|SYS_ADMIN'
```

### Never mount docker.sock

`-v /var/run/docker.sock:/var/run/docker.sock` gives the container the root-equivalent API from [the first section](#the-docker-group-is-root). Anything with RCE in that container — your Traefik, your Portainer, your CI agent, your "auto-updater" — is now root on the host. **A read-only bind (`:ro`) does not help**: `:ro` stops the process writing the socket *file*, not sending API requests over it.

What to do instead:

| Tool wanted the socket for | Instead |
|---|---|
| Service discovery (Traefik, Caddy-docker-proxy) | A socket proxy (for example `tecnativa/docker-socket-proxy`) that allows only `GET /containers` and `GET /events`, on an internal network; or static file-based config |
| Metrics (cAdvisor, Alloy) | Read cgroup files from `/sys/fs/cgroup` read-only, or use the Podman / Docker metrics endpoint from the host |
| Auto-update (Watchtower-style) | `podman auto-update` from systemd (chapter 10), or a Renovate MR that bumps the digest |
| Building images in CI | Rootless BuildKit as a service with its own socket, not the host engine |
| Log shipping | `journald` log driver plus a host-level collector |

If you must proxy, restrict by verb and path, and put the proxy on a network that nothing else can reach.

> **Gotcha.** Podman's API socket (`podman.socket`) is just as powerful for the user that owns it. The rootless one is *your* UID rather than root, which is better, but a container holding it can still start containers that mount your home directory and read your SSH keys.

### Hardened docker run template

The template. Start here and remove restrictions only when something breaks and you know why. Every line was exercised on this host (Docker 29.8) except the seccomp file path, which is a placeholder.

```bash
docker run -d \
  --name APP \
  --user 10001:10001 \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,size=64m \
  --cap-drop ALL \
  --security-opt no-new-privileges=true \
  --pids-limit 256 \
  --memory 512m --memory-swap 512m \
  --cpus 1.5 \
  --ulimit nofile=4096:8192 \
  --init \
  --restart unless-stopped \
  --health-cmd '/app/healthcheck' --health-interval 30s --health-timeout 3s --health-retries 3 \
  --log-driver local --log-opt max-size=10m --log-opt max-file=3 \
  -p 127.0.0.1:8080:8080 \
  -v APP-data:/data \
  REGISTRY/APP@sha256:DIGEST
```

Why each line:

| Line | Reason |
|---|---|
| `--user 10001:10001` | Non-root, and a UID that does not exist on the host |
| `--read-only` + `--tmpfs` | No persistence for an attacker; scratch is RAM-backed and size-capped |
| `--cap-drop ALL` | Zero capabilities. Add one back with `--cap-add` only on proven need |
| `no-new-privileges` | setuid binaries cannot escalate |
| `--pids-limit`, `--memory`, `--memory-swap` | One container cannot take the host down |
| `--init` | PID 1 reaps zombies and forwards signals (tini) |
| `-p 127.0.0.1:…` | Not exposed on every interface; a reverse proxy fronts it (see chapter 06 on how Docker bypasses firewalld) |
| `@sha256:DIGEST` | You run exactly what you scanned and signed (chapter 09) |

The builtin seccomp profile applies automatically; add `--security-opt seccomp=PROFILE.json` only for a custom one. On Podman the same command works, with SELinux labelling applied by default — add `:Z` to bind mounts.

#### Verify a running container

```bash
docker inspect APP --format '
user={{.Config.User}}
readonly={{.HostConfig.ReadonlyRootfs}}
capdrop={{.HostConfig.CapDrop}} capadd={{.HostConfig.CapAdd}}
secopt={{.HostConfig.SecurityOpt}}
privileged={{.HostConfig.Privileged}}
pids={{.HostConfig.PidsLimit}} mem={{.HostConfig.Memory}}
ports={{json .HostConfig.PortBindings}}'
docker exec APP grep -E '^(CapEff|NoNewPrivs|Seccomp):' /proc/1/status
```

### The compose equivalent

Validated with `docker compose config` on Compose v5.5.1.

```yaml
services:
  app:
    image: REGISTRY/APP@sha256:DIGEST
    user: "10001:10001"
    read_only: true
    tmpfs:
      - /tmp:rw,noexec,nosuid,nodev,size=64m
    cap_drop: [ALL]
    # cap_add: [NET_BIND_SERVICE]     # only on proven need
    security_opt:
      - no-new-privileges:true
      # - seccomp=./seccomp-app.json
      # - label=type:container_t      # Podman / SELinux-enabled Docker
    pids_limit: 256
    mem_limit: 512m
    memswap_limit: 512m
    cpus: 1.5
    ulimits:
      nofile: { soft: 4096, hard: 8192 }
    init: true
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "/app/healthcheck"]
      interval: 30s
      timeout: 3s
      retries: 3
      start_period: 20s
      start_interval: 2s
    logging:
      driver: local
      options: { max-size: "10m", max-file: "3" }
    ports:
      - "127.0.0.1:8080:8080"
    volumes:
      - app-data:/data
      # - ./config:/config:ro,Z       # bind mount, SELinux-labelled

volumes:
  app-data: {}
```

> **Gotcha.** Setting both service-level `cpus:` and `deploy.resources.limits.cpus` is an error in current Compose (`can't set distinct values on 'cpus' and 'deploy.resources.limits.cpus'`). Pick one style per file. Service-level keys (`mem_limit`, `cpus`, `pids_limit`) are the plain-Compose default; `deploy.resources` is the Swarm-era spelling that Compose also honours.

Use YAML anchors to apply the hardening to every service without repeating it:

```yaml
x-hardened: &hardened
  read_only: true
  cap_drop: [ALL]
  security_opt: ["no-new-privileges:true"]
  pids_limit: 256
  init: true

services:
  api:
    <<: *hardened
    image: REGISTRY/API@sha256:DIGEST
    mem_limit: 512m
  worker:
    <<: *hardened
    image: REGISTRY/WORKER@sha256:DIGEST
    mem_limit: 1g
```

### Podman equivalents

| Docker | Podman | Difference |
|---|---|---|
| `--user` | `--user` | Same |
| `--read-only` | `--read-only` | Podman also mounts tmpfs on `/tmp`, `/run`, `/var/tmp`, `/dev/shm` unless `--read-only-tmpfs=false` |
| `--cap-drop ALL` | `--cap-drop ALL` | Podman's default set is smaller (11; no `NET_RAW`, `MKNOD`, `AUDIT_WRITE`) |
| `--security-opt no-new-privileges=true` | `--security-opt no-new-privileges` | Same effect |
| `--pids-limit` | `--pids-limit` | Podman defaults to 2048, Docker to unlimited |
| (daemon `selinux-enabled`) | on by default | Podman labels every container with a unique MCS pair |
| `--userns` / daemon `userns-remap` | `--userns keep-id`, `auto`, `host` | Per container rather than per daemon |
| Quadlet `.container` keys | `User=`, `ReadOnly=`, `DropCapability=`, `NoNewPrivileges=`, `PidsLimit=`, `Memory=`, `SeccompProfile=` | See chapter 10 |

### Checklist

- [ ] Nobody is in the `docker` group who you would not give `sudo NOPASSWD` (`getent group docker`).
- [ ] Workstations use Podman rootless or rootless Docker; the rootful daemon is stopped where it is not needed.
- [ ] Every image sets a numeric non-root `USER`; `docker image inspect --format '{{.Config.User}}'` is not empty.
- [ ] `--cap-drop ALL` with an explicit, commented `--cap-add` list.
- [ ] `no-new-privileges` is on — ideally as a daemon default.
- [ ] Seccomp is never `unconfined`; custom profiles use `SCMP_ACT_ERRNO`.
- [ ] Docker on Fedora: decide deliberately whether to enable `selinux-enabled`; Podman: bind mounts carry `:Z`/`:z` on narrow paths only.
- [ ] `--read-only` with explicit `--tmpfs`; `docker diff` shows nothing unexpected.
- [ ] `--pids-limit` and `--memory` on every long-running container.
- [ ] No `--privileged`, no `docker.sock` mounts; the one-liner inspect above returns nothing.

### Traps

- **"It's fine, it's in a container."** A root process in a rootful container with default capabilities, no seccomp changes and a bind-mounted host path is one kernel bug away from the host. Defence in depth means each layer assumes the one above failed.
- **`:ro` on docker.sock.** Does nothing to the API. Removing the mount is the only fix.
- **`:Z` on a home directory.** Relabels everything under it; SSH and GNOME start failing in odd ways. `restorecon -Rv ~` to recover.
- **Assuming Docker on Fedora is SELinux-confined.** It is not unless `selinux-enabled` is set — check `/proc/self/attr/current` inside a container for `spc_t`.
- **Dropping capabilities from an image that starts as root.** It fails with `Operation not permitted` on `chown`/`setgroups`; start as the service user instead of adding caps back.
- **A recorded seccomp profile deployed as-is.** It misses every code path you did not exercise.
- **`--oom-kill-disable` without `--memory`.** Moves the OOM kill from the container to your host.


---


<a id="08-host-and-daemon-hardening"></a>

## 08 · Host and daemon hardening

*dockerd is a root daemon with an HTTP API that can create root processes. Hardening it means three things: make its defaults safe so a forgotten flag fails closed, make its API reachable by as few principals as possible, and make every use of it leave an audit trail.*

### What you are protecting

```text
                     ┌──────────── host (Fedora 43) ─────────────────────────┐
  user in docker ───▶│ /run/docker.sock (root:docker 0660)                    │
  group              │        │                                               │
  remote client ─X──▶│ tcp://0.0.0.0:2375   <- never. 2376 + mTLS or ssh://   │
                     │        ▼                                               │
                     │  dockerd (root) ── /etc/docker/daemon.json  (defaults) │
                     │        │           /var/lib/docker          (state)    │
                     │        ▼                                               │
                     │  containerd ── containerd-shim-runc-v2 ── runc          │
                     │        │                                               │
                     │  nftables/iptables rules (Docker writes these itself)  │
                     └───────────────────────────────────────────────────────┘
```

The container-level flags in chapter 07 protect you *when someone remembers them*. The daemon config in this chapter is what happens when nobody remembers anything.

### Start from a known state

Before changing anything, record what the daemon is doing now.

```bash
docker info --format '
version={{.ServerVersion}}
rootless={{.SecurityOptions}}
cgroup={{.CgroupVersion}}/{{.CgroupDriver}}
storage={{.Driver}} {{.DriverStatus}}
logging={{.LoggingDriver}}
live-restore={{.LiveRestoreEnabled}}'
cat /etc/docker/daemon.json 2>/dev/null || echo "no daemon.json: all defaults"
systemctl cat docker.service | grep -E '^ExecStart'
```

On this host (verified): Docker 29.8.1, `[name=seccomp,profile=builtin name=cgroupns]`, cgroup v2 with the systemd driver, the containerd image store (`driver-type io.containerd.snapshotter.v1`), `json-file` logging, live-restore **off**, and **no `daemon.json` at all**. That is the docker-ce default, and it is not a hardened one: no log rotation, no SELinux labelling, inter-container traffic open on the default bridge.

> **Note.** Flags in `ExecStart` and keys in `daemon.json` must not overlap. If the unit passes `-H fd://` and `daemon.json` also sets `"hosts"`, dockerd refuses to start with a "directives are specified both as a flag and in the configuration file" error. Keep the unit stock and put everything in `daemon.json`.

### The hardened daemon.json

JSON has no comments, so the file is below and the reasoning is in the table after it. Validated offline with `dockerd --validate --config-file` on 29.8 (everything except `userns-remap`, which `--validate` tries to create a user for and so needs root).

```json
{
  "live-restore": true,
  "no-new-privileges": true,
  "selinux-enabled": true,
  "icc": false,
  "userland-proxy": false,
  "ip": "127.0.0.1",
  "iptables": true,
  "ip6tables": true,
  "log-driver": "local",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "default-ulimits": {
    "nofile": { "Name": "nofile", "Soft": 4096, "Hard": 65536 },
    "nproc":  { "Name": "nproc",  "Soft": 4096, "Hard": 8192 }
  },
  "default-address-pools": [ { "base": "10.200.0.0/16", "size": 24 } ],
  "default-cgroupns-mode": "private",
  "default-ipc-mode": "private",
  "init": true,
  "max-concurrent-downloads": 6
}
```

| Key | Effect | Why | Cost |
|---|---|---|---|
| `live-restore` | Containers keep running while `dockerd` restarts | Patch upgrades and config restarts stop being outages | Standalone containers only (not Swarm services); supported across **patch** upgrades (`YY.MM.x`) only, not `YY.MM` jumps; if the daemon stays down long, the 64 KB log FIFO fills and containers block on stdout |
| `no-new-privileges` | Every container gets `PR_SET_NO_NEW_PRIVS` | setuid escalation blocked even when nobody passes the flag | Images that `sudo` inside break (they were wrong anyway) |
| `selinux-enabled` | Containers run as `container_t` with an MCS pair instead of `spc_t` | On this host Docker containers currently run **unconfined** (`spc_t`, verified) | Existing bind mounts need `:z`/`:Z` or they get `Permission denied` |
| `icc: false` | Containers on the **default bridge** cannot talk to each other | Lateral movement between unrelated containers | Only affects `docker0`; user-defined networks ignore it (see below) |
| `userland-proxy: false` | Published ports use NAT rules only, not a `docker-proxy` process per port | Fewer root processes, real client source IPs | Hairpin/loopback edge cases on some kernels; test before rollout |
| `ip: 127.0.0.1` | `-p 8080:80` on the default bridge binds to loopback, not `0.0.0.0` | A forgotten `127.0.0.1:` prefix no longer exposes a port to the LAN | Only the default bridge honours it; set `com.docker.network.bridge.host_binding_ipv4` on user networks |
| `iptables` / `ip6tables: true` | Docker manages its own firewall rules | Setting `false` breaks container networking in ways that look like DNS or routing bugs | Docker bypasses firewalld zones for published ports (below) |
| `log-driver: local` + `log-opts` | Rotated, compressed logs, 30 MB cap per container | The default `json-file` has **no rotation** and fills `/var/lib/docker` | `local` files are not meant to be read by other tools; `docker logs` still works |
| `default-ulimits` | Sane nofile/nproc for every container | Inherited host limits are either tiny or effectively unlimited | Apps needing more must ask with `--ulimit` |
| `default-address-pools` | Networks come from a range you chose | Default `172.17–31.x` and `192.168.x` collide with VPNs and office LANs | Changing later means recreating networks |
| `default-cgroupns-mode` / `default-ipc-mode: private` | Per-container namespaces | Already the defaults on cgroup v2; pinning them documents intent | None |
| `init: true` | tini as PID 1 in every container | Zombie reaping and signal forwarding without per-image fixes | Images with their own init get two; harmless |

Apply and verify:

```bash
sudo install -m 0644 -o root -g root daemon.json /etc/docker/daemon.json
sudo dockerd --validate --config-file /etc/docker/daemon.json
sudo systemctl restart docker
docker info --format '{{.SecurityOptions}} live-restore={{.LiveRestoreEnabled}} log={{.LoggingDriver}}'
docker run --rm alpine:3 cat /proc/self/attr/current      # expect container_t, not spc_t
```

> **Gotcha.** `log-driver` and `log-opts` apply **only to containers created after the restart**. Existing containers keep their old config until recreated (`docker compose up -d --force-recreate`). The same is true of `default-ulimits` and `no-new-privileges`.

> **Version-sensitive.** A subset of keys is live-reloadable with `sudo systemctl reload docker` (SIGHUP) — among them `debug`, `labels`, `live-restore`, `max-concurrent-downloads` and registry mirrors / insecure registries. Check the "Configuration reload behaviour" list in the `dockerd` reference for your version; everything else needs a restart, which `live-restore` makes non-disruptive.

#### userns-remap: where it fits

```json
{ "userns-remap": "default" }
```

With `default`, dockerd creates a `dockremap` user and a subordinate range in `/etc/subuid` / `/etc/subgid`, then runs every container with container-root mapped to an unprivileged host UID.

> **One-way door.** Turning on `userns-remap` moves Docker's state to a new subdirectory (`/var/lib/docker/UID.GID/`). **Every existing image, container and volume becomes invisible**; turning it back off hides everything created while it was on. Plan it as a migration, not a toggle.

> **Version-sensitive.** The containerd image store — **the default on fresh Docker 29 installs, and what this host uses** — is not available with `userns-remap` (docs.docker.com, "containerd image store"; 29.0.0 release notes, [moby#47377](https://github.com/moby/moby/issues/47377)). On 29.x the daemon **silently falls back to the classic graph-driver store** when remap is on, and **refuses to start** if `"features": { "containerd-snapshotter": true }` is set explicitly. Either way you lose multi-platform image storage and native attestation handling — and the fallback store is a different directory, so your containerd-store images vanish too. Upstream calls this a temporary workaround.

Other limits (docs.docker.com, "Isolate containers with a user namespace"): sharing the host PID or network namespace (`--pid=host`, `--network=host`), volume or storage drivers unaware of the remap, and `--privileged` without `--userns=host`. `--userns=host` opts one container out of the remap, but its filesystem ownership is still remapped, so tools that check ownership (`sudo`) can misbehave.

**Recommendation: don't.** Use rootless Docker or Podman rootless (chapter 07). userns-remap is one shared range for all containers, costs you the modern image store, and is a state migration either way. It is the right answer only when you must stay rootful (a legacy tool needs host networking for *some* containers) and still want container-root to be non-root for the rest.

#### icc false: what it does and doesn't do

`icc: false` only affects the legacy default bridge (`docker0`). **User-defined bridge networks — which is what Compose creates — ignore it.** On those, every container on the same network can reach every other on any port.

The real segmentation tool is networks:

```yaml
services:
  web:
    networks: [frontend]
  api:
    networks: [frontend, backend]
  db:
    networks: [backend]

networks:
  frontend: {}
  backend:
    internal: true        # no route to the outside world at all
```

For per-network control, `com.docker.network.bridge.enable_icc=false` as a driver option disables intra-network traffic on a user network too.

#### Firewall: Docker, iptables, nftables and firewalld

**Docker writes its own firewall rules, and published ports bypass your host firewall's INPUT rules.** The DNAT happens in `PREROUTING`, before the packet ever reaches the `INPUT` chain where firewalld's zone rules live. `-p 5432:5432` on a host whose firewalld zone does not allow 5432 is **still reachable from the network**.

```text
packet ──▶ PREROUTING (DOCKER DNAT: host:5432 → 172.18.0.2:5432)
                │
                └──▶ FORWARD (DOCKER chains)  ──▶ container
          INPUT (firewalld zone rules) is never consulted for this packet
```

What to do:

| Goal | Do this |
|---|---|
| Service only for local reverse proxy | Publish on loopback: `-p 127.0.0.1:8080:8080` (and `"ip": "127.0.0.1"` as a safety net) |
| Restrict who can reach a published port | Rules in the `DOCKER-USER` chain (iptables backend), which Docker evaluates before its own |
| firewalld integration | Docker puts its bridges in a firewalld zone called `docker`; manage forwarding policy there |
| Not published at all | Don't `-p`; reach it over a Docker network from the proxy container |

```bash
# iptables backend: allow only one subnet to reach published ports on eth0
sudo iptables -I DOCKER-USER -i eth0 ! -s 10.0.0.0/8 -j DROP
sudo iptables -L DOCKER-USER -n -v
```

> **Version-sensitive.** Docker 29.0 added an **experimental** nftables backend: `"firewall-backend": "nftables"`. Docker then does **not** enable IP forwarding itself (it errors if forwarding is needed but off), it cannot run in Swarm mode, and `DOCKER-USER` does not exist — Docker's rules live in the `ip docker-bridges` / `ip6 docker-bridges` tables, and you write your own table whose base chains have a **lower `priority` number** than Docker's so they run first (docs.docker.com, "Docker with nftables"). Stay on the iptables backend for anything you depend on until it leaves experimental.

> **Version-sensitive.** Docker **28.0.0** closed two holes (moby#49325, 28.0.0 release notes): remote hosts with a route could reach a container's published ports on its **container IP**, and L2 neighbours could reach ports published on **`127.0.0.1`**. It also blocks direct-routed access to **unpublished** container ports in the `DOCKER` chain. `"allow-direct-routing": true` (added in **28.2.0**, also `--allow-direct-routing`) disables that filtering for packets addressed straight to containers. If a routed-network setup broke after an upgrade, this is why.

> **Gotcha.** Never set `"iptables": false` to "let firewalld handle it". Containers lose NAT and outbound connectivity; the symptom looks like broken DNS (chapter 11).

### Protecting the socket

`/run/docker.sock` is the root API. The socket unit on Fedora (verified: `/usr/lib/systemd/system/docker.socket`) creates it `0660 root:docker`.

Controls, in order:

1. **Keep the `docker` group empty or near-empty.** `getent group docker`. Every member is root.
2. **Do not change `SocketMode` to anything more permissive.** `0666` means every local user and every process running as any UID is root.
3. **Never bind-mount the socket into a container** (chapter 07).
4. **Audit writes to it** (auditd section below).
5. **If you need a non-root path to the API, use rootless Docker**, which gives each user their own daemon and socket, rather than widening the root one.

Check nothing has quietly widened it:

```bash
stat -c '%a %U:%G %n' /run/docker.sock
systemctl cat docker.socket | grep -E 'Socket(Mode|User|Group)|ListenStream'
ss -xlp | grep docker.sock
```

Authorisation plugins (`--authorization-plugin`, for example OPA-based) can filter API calls, but they are a policy engine in front of a root API — useful for audit and guardrails in shared environments, not a substitute for keeping the socket private.

### Never TCP without TLS

`-H tcp://0.0.0.0:2375` is an **unauthenticated remote root shell**. Internet-wide scanners find exposed 2375 within minutes and drop cryptominers; it is one of the most-exploited misconfigurations there is.

**Default: don't expose TCP at all. Use SSH.**

```bash
docker context create prod-box --docker "host=ssh://deploy@prod-box.example.com"
docker context use prod-box
docker ps                     # runs against the remote daemon over SSH
docker context use default
```

SSH gives you authentication, your existing key management, and the remote user still needs to be in the remote `docker` group (so the root-equivalence moves to that host, where it belongs). Podman's equivalent is `podman system connection add NAME ssh://user@host/run/user/UID/podman/podman.sock`.

If TCP is genuinely required (a management plane that cannot use SSH), it is **port 2376 with mutual TLS**, never anything less:

```json
{
  "hosts": ["unix:///run/docker.sock", "tcp://0.0.0.0:2376"],
  "tls": true,
  "tlsverify": true,
  "tlscacert": "/etc/docker/tls/ca.pem",
  "tlscert": "/etc/docker/tls/server-cert.pem",
  "tlskey": "/etc/docker/tls/server-key.pem"
}
```

```bash
docker --tlsverify \
  --tlscacert ca.pem --tlscert cert.pem --tlskey key.pem \
  -H tcp://HOST:2376 version
```

- `tlsverify` (not just `tls`) is what forces **client certificate** authentication. `tls` alone encrypts but lets anyone in.
- Anyone holding a client cert signed by that CA is root on the host. Use a dedicated CA, short-lived certs, and firewall 2376 to the management subnet.
- Remember the `hosts` / `-H fd://` conflict from the note above: add a systemd drop-in that clears `ExecStart` and restarts dockerd without `-H`.

> **One-way door.** An exposed 2375 for even a few minutes should be treated as a host compromise: rebuild, don't clean. There is no reliable way to prove nothing ran.

### docker-bench-security

`docker/docker-bench-security` is a shell script that checks a host against the CIS Docker Benchmark. It is not installed on this host; it runs from a clone.

```bash
git clone https://github.com/docker/docker-bench-security.git
cd docker-bench-security
sudo sh docker-bench-security.sh -l /tmp/docker-bench.log
sudo sh docker-bench-security.sh -c container_images,container_runtime   # only sections 4 and 5
sudo sh docker-bench-security.sh -e check_2_8                            # exclude one check
```

| Flag | Does |
|---|---|
| `-c CHECK` | Run only the named checks or groups |
| `-e CHECK` | Exclude checks |
| `-l FILE` | Log output (and a `.json` alongside) |
| `-i` / `-x PATTERN` | Include / exclude containers and images by name |
| `-t LABEL` | Only containers/images with a label |
| `-u USERS` | Comma-separated list of users you trust in the `docker` group (for 1.1.x checks) |

> **Version-sensitive.** The script still implements **CIS Docker Benchmark v1.6.0** (per its README, September 2026); CIS's current benchmark is **v1.8.0** (announced in CIS's August 2025 update, covering Docker Server 28), so v1.7/v1.8 changes are not checked. The prebuilt `docker/docker-bench-security` image is out of date — run from the git clone. Its container mode needs host PID, network and filesystem access, so running the script directly with `sudo` is less privilege than the container, not more.

#### Reading the output

| Marker | Means | What to do |
|---|---|---|
| `[PASS]` | Compliant | Nothing |
| `[WARN]` | Non-compliant with a scored check | Fix, or document why not |
| `[INFO]` | Not scored, or needs a human to judge | Read it; often a list of things to review |
| `[NOTE]` | Advisory | Usually process, not config |

The findings that matter, and which ones to accept:

| Check (v1.6 numbering) | Typical finding | Meaning | Verdict |
|---|---|---|---|
| 1.1.x Audit rules | "Ensure auditing is configured for …" | No auditd watch on the daemon, config, socket or runtime binaries | **Fix** — see auditd below; costs nothing |
| 1.1.1 separate partition | `/var/lib/docker` on `/` | A runaway container fills the root filesystem | Fix on servers (separate LV); accept on workstations |
| 2.x icc | `--icc` not false | Default bridge allows lateral traffic | Fix via `daemon.json`; also segment Compose networks |
| 2.x userns | user namespace support not enabled | Container root is host root | Satisfy with rootless instead; mark accepted with that reason |
| 2.x live-restore | not enabled | Daemon restart = outage | Fix |
| 2.x userland-proxy | enabled | Extra root process per port | Fix after testing |
| 2.x no-new-privileges | not set | setuid escalation possible | Fix |
| 2.x authorization plugin | none | No API-level policy | Accept on single-admin hosts |
| 2.x centralised logging | local only | Logs die with the host | Fix on servers (journald + collector) |
| 4.1 image user | container running as root | No `USER` in the image | Fix in the Dockerfile |
| 4.5 content trust | `DOCKER_CONTENT_TRUST` not set | Notary v1 signing | **Accept**: use cosign verification instead (chapter 09) |
| 4.6 HEALTHCHECK | missing in image | No health status | Fix for services |
| 5.x AppArmor | no AppArmor profile | Fedora uses SELinux | **Accept**, and make sure 5.x SELinux passes instead |
| 5.x SELinux | options not set | `selinux-enabled` is off | Fix on Fedora/RHEL |
| 5.x capabilities / privileged / sensitive mounts / docker.sock mounted | specific container named | Chapter 07 violations | **Fix every one** |
| 5.x memory / CPU / PIDs limits | not set | Noisy-neighbour and fork-bomb exposure | Fix for long-running containers |
| 5.x read-only rootfs | not read-only | Writable container | Fix where the app allows |
| 5.x bound to host interface | ports on `0.0.0.0` | Exposed on all interfaces | Fix (`127.0.0.1:` or a specific IP) |
| 7.x Swarm | various | Only if you use Swarm | Ignore otherwise |

Run it before and after the `daemon.json` change and diff the WARN counts; that is your evidence for an audit.

```bash
grep -c '\[WARN\]' /tmp/docker-bench.log
```

### CIS Docker Benchmark highlights

The benchmark itself is a free PDF from cisecurity.org (non-commercial use). Its sections, and the one line from each that matters most:

| Section | Covers | The line that matters |
|---|---|---|
| 1 Host configuration | Partitioning, hardened host, audit rules, keeping Docker current | Audit the daemon, config and runtime binaries |
| 2 Daemon configuration | Flags / `daemon.json` | No TCP without TLS; icc, userns, live-restore, no-new-privileges, logging |
| 3 Daemon files | Ownership and permissions of units, sockets, certs, `daemon.json` | `docker.sock` is `660 root:docker`, `daemon.json` is `644 root:root`, TLS keys `400` |
| 4 Images and build files | USER, trusted bases, HEALTHCHECK, no secrets, no `ADD` from URLs | Non-root user and no secrets in layers (chapter 09) |
| 5 Container runtime | Everything in chapter 07 | No privileged, no host namespaces, no socket mounts, caps dropped, limits set |
| 6 Security operations | Image and container sprawl | Prune, and know what is running |
| 7 Swarm | Swarm mode | Skip unless you use it |

File-permission checks (section 3) are quick to self-audit:

```bash
stat -c '%a %U:%G %n' \
  /usr/lib/systemd/system/docker.service \
  /usr/lib/systemd/system/docker.socket \
  /etc/docker /etc/docker/daemon.json \
  /run/docker.sock /etc/containerd/config.toml 2>/dev/null
```

Expected: units `644 root:root`, `/etc/docker` `755 root:root`, `daemon.json` `644 root:root`, socket `660 root:docker`.

### Auditing Docker with auditd

**Every use of the Docker API and every change to its binaries should leave a record.** auditd is installed on Fedora (`/usr/bin/auditctl`), and CIS section 1 asks for watches on the following. Paths below are verified for docker-ce on this Fedora 43 host.

```bash
# /etc/audit/rules.d/50-docker.rules
-w /usr/bin/dockerd                         -p rwxa -k docker
-w /usr/bin/containerd                      -p rwxa -k docker
-w /usr/bin/containerd-shim-runc-v2         -p rwxa -k docker
-w /usr/bin/runc                            -p rwxa -k docker
-w /var/lib/docker                          -p rwxa -k docker
-w /etc/docker                              -p rwxa -k docker
-w /etc/docker/daemon.json                  -p rwxa -k docker
-w /etc/containerd/config.toml              -p rwxa -k docker
-w /usr/lib/systemd/system/docker.service   -p rwxa -k docker
-w /usr/lib/systemd/system/docker.socket    -p rwxa -k docker
-w /usr/lib/systemd/system/containerd.service -p rwxa -k docker
-w /run/containerd                          -p rwxa -k docker
-w /run/docker.sock                         -p rwxa -k docker-sock
```

Load and check:

```bash
sudo augenrules --check
sudo augenrules --load
sudo auditctl -l | grep -E 'docker|containerd|runc'
```

Query:

```bash
sudo ausearch -k docker-sock -ts today -i | aureport -f -i --summary
sudo ausearch -k docker -ts recent -i
sudo aureport -k --summary
```

> **Gotcha.** A watch on `/var/lib/docker` with `-p rwxa` is **extremely noisy** — every container write through overlay can generate records. On busy hosts, narrow it to `-p wa` on `/var/lib/docker` or drop it and rely on the binary, config and socket watches, which are what the benchmark auditors actually look at. Check `auditctl -s` for `lost` climbing after you load rules.

> **Note.** The socket watch records *which process* connected (the `docker` CLI, a CI agent, a rogue container that has the socket mounted), not what API call it made. For a record of what was done, stream `docker events` to your log pipeline — it emits every create, start, exec, pull and delete with the container and image:

```bash
docker events --filter type=container --format '{{.Time}} {{.Action}} {{.Actor.Attributes.name}} {{.Actor.Attributes.image}}'
```

### Host hygiene

The daemon is only as safe as the host under it.

| Item | Command / setting | Why |
|---|---|---|
| Keep Docker current | `sudo dnf upgrade docker-ce docker-ce-cli containerd.io` | runc and containerd escape CVEs appear a few times a year |
| Keep the kernel current | reboot after kernel updates | Container isolation is kernel isolation |
| SELinux enforcing | `getenforce` → `Enforcing` | Without it, `container_t` is meaningless |
| `/var/lib/docker` on its own LV | `lsblk`, `findmnt /var/lib/docker` | Disk exhaustion from a container stays contained |
| Nothing else on the box | a container host is a container host | Every extra service is a new route to the socket |
| Scan the host itself | `sudo lynis audit system` | Covers the host baseline CIS section 1 assumes |

### Podman: what replaces all this

Podman has no daemon, so most of this chapter collapses:

| Docker concern | Podman |
|---|---|
| Root daemon and socket | None by default; `podman.socket` is opt-in, and rootless per user |
| `daemon.json` defaults | `/etc/containers/containers.conf` (system) and `~/.config/containers/containers.conf` (user) |
| `no-new-privileges` default | **No `containers.conf` equivalent** (verified: not in `man containers.conf` from containers-common 0.67 / Podman 5.8.4, nor in the upstream `containers.conf.5.md` on `main`) — set it per container (`--security-opt no-new-privileges`) or per Quadlet (`NoNewPrivileges=true`) |
| Log rotation | `log_driver = "journald"` (Fedora default) or `log_size_max` |
| Default ulimits | `default_ulimits = ["nofile=4096:65536"]` |
| `pids-limit` default | `pids_limit` (the CLI reports a 2048 default on this host) |
| SELinux | `label = true` (already the default) |
| Audit | watch `/usr/bin/podman`, `/etc/containers`, `~/.config/containers`, and the user's `podman.sock` if enabled |

```ini
# ~/.config/containers/containers.conf
[containers]
default_ulimits = ["nofile=4096:65536"]
log_driver = "journald"
```

### Checklist

- [ ] `/etc/docker/daemon.json` exists, is `644 root:root`, and passes `dockerd --validate`.
- [ ] `live-restore`, `no-new-privileges`, log rotation (`local` or `json-file` with `max-size`) are set.
- [ ] On Fedora: `selinux-enabled: true`, and a container shows `container_t` rather than `spc_t`.
- [ ] `ip: 127.0.0.1` or every `-p` has an explicit bind address; published ports are not bypassing a firewall you think protects them.
- [ ] No `tcp://` host without `tlsverify`; remote access is `ssh://` contexts.
- [ ] `docker.sock` is `660 root:docker` and the `docker` group is audited.
- [ ] auditd rules for binaries, config, units and socket are loaded (`auditctl -l`).
- [ ] docker-bench-security run saved before and after; every remaining WARN has a written reason.
- [ ] userns-remap decision recorded — and if yes, the containerd-snapshotter trade-off accepted.

### Traps

- **Assuming firewalld protects published ports.** It does not; Docker's DNAT runs first. Bind to `127.0.0.1` or filter in `DOCKER-USER`.
- **Changing `log-opts` and expecting existing containers to rotate.** Only new containers pick it up.
- **Setting `hosts` in `daemon.json` while the unit passes `-H fd://`.** dockerd refuses to start; add a drop-in that clears `ExecStart`.
- **`tls: true` without `tlsverify: true`.** Encrypted, unauthenticated root.
- **Enabling userns-remap on Docker 29 with the containerd store.** The daemon falls back to the classic store and your images disappear (or it refuses to start if the snapshotter is pinned on); plan the storage switch or go rootless.
- **`icc: false` as network segmentation.** It only covers `docker0`; Compose networks ignore it.
- **`iptables: false`.** Breaks outbound networking; looks like DNS failure.
- **Running the stale docker-bench image.** Clone the repo; the image lags the script.


---


<a id="09-image-supply-chain"></a>

## 09 · Image supply chain

*You cannot secure an image you cannot identify. A digest names exactly one set of bytes; everything else in this chapter — scanning, SBOMs, signatures, provenance — is a claim attached to that digest, and it is worthless the moment you deploy by a tag that has since moved.*

### The chain, end to end

```text
 base image ──▶ build ──▶ image@sha256:D ──▶ registry ──▶ deploy @sha256:D
   │ pin by       │ secrets   │                               │
   │ digest       │ mounted,  ├─ scan (Trivy/Grype)  gate     │ verify signature
   │ (Renovate    │ never     ├─ SBOM (Syft / buildx)         │ of D before run
   │  refreshes)  │ in layers ├─ provenance (SLSA, buildx)    │
                              └─ sign D (cosign)  ────────────┘
```

**Every artifact after the build refers to the digest `D`.** Sign a tag and you have signed whatever the tag pointed to that second. Scan a tag and you have scanned something you may never deploy.

### Choose a minimal base

Every package in the base is attack surface and scanner noise you have to triage forever. Pick the smallest base that runs your app.

| Base | Size (approx.) | Shell / pkg manager | libc | Pick when |
|---|---|---|---|---|
| **`gcr.io/distroless/static-debian12:nonroot`** | ~2 MB | none | none | Static Go / Rust binaries. **Default for compiled languages** |
| `gcr.io/distroless/base-debian12` / `cc-debian12` | ~20 MB | none | glibc | Dynamically linked binaries needing glibc / libstdc++ |
| `gcr.io/distroless/python3-debian12`, `java21-debian12` | 50–200 MB | none | glibc | Interpreted runtimes without a shell |
| **Chainguard / Wolfi** (`cgr.dev/chainguard/*`) | small | none in runtime tags, `-dev` tags have apk | glibc | You want near-zero CVE counts and daily rebuilds; free tier is `:latest` only |
| **UBI micro** (`registry.access.redhat.com/ubi9/ubi-micro`) | ~10 MB compressed | none | glibc | RHEL-supported base, customers ask for Red Hat provenance, or you run on OpenShift |
| UBI minimal (`ubi9/ubi-minimal`) | ~40 MB | `microdnf` | glibc | Need to install RPMs in the final stage |
| `debian:*-slim` / `python:*-slim` | 30–150 MB | bash, apt | glibc | Interpreted apps with native wheels — the safe general default for Python |
| `alpine` | ~4 MB | busybox, apk | **musl** | Small utility images where you control every binary |
| `scratch` | 0 | none | none | Static binaries, and you supply CA certs, tzdata, `/etc/passwd` yourself |

**Defaults: distroless static for Go/Rust, `-slim` pinned by digest for Python, distroless or Chainguard for JVM and Node.**

#### The alpine trade-off

Alpine is small, but **musl is not glibc**, and that difference costs real time:

- Python wheels on PyPI are mostly `manylinux` (glibc). On alpine, pip falls back to building from source — minutes of compile time, a compiler toolchain in the build stage, and occasionally different behaviour. `musllinux` wheels exist for popular packages, not all.
- musl's DNS resolver behaves differently: historically no TCP fallback for large responses, and `search`/`ndots` handling that surprises people in Kubernetes.
- musl's default thread stack size is smaller (128 KB vs glibc's 8 MB), so deep recursion crashes where it worked on Debian.
- Memory allocator performance differs; some workloads are measurably slower.

Use alpine when you own every binary in the image. Do not use it as a reflex to shrink a Python or JVM image.

#### Distroless has no shell — plan for debugging

No shell means `docker exec -it APP sh` fails. That is the point, and chapter 11 covers how to debug anyway (`nsenter`, a `--network container:` sidecar, `:debug` tags for distroless). Do not add busybox back "just in case".

### Pin by digest

A tag is a mutable pointer. `python:3.13-slim` today and next week are different bytes. **Pin every `FROM` by digest, and keep the tag alongside for humans and for Renovate.**

```dockerfile
FROM python:3.13-slim@sha256:DIGEST AS runtime
```

With both present, the digest wins; the tag is documentation.

Find a digest without pulling:

```bash
skopeo inspect --format '{{.Digest}}' docker://docker.io/library/python:3.13-slim
docker buildx imagetools inspect python:3.13-slim --format '{{.Manifest.Digest}}'
```

Or from what you already have locally (verified here):

```bash
docker image inspect alpine:3 --format '{{index .RepoDigests 0}}'
# alpine@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
```

While this chapter was being written, a re-pull of the same `alpine:3` tag on the same host returned `alpine@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6`. Same tag, different bytes, hours apart — that is the whole argument for digests.

> **Gotcha.** Pin the **index** (multi-platform manifest list) digest, not a per-platform manifest digest. `skopeo inspect` and `imagetools inspect` return the index digest for a multi-arch tag; `docker image inspect` on a single-platform pull may show a platform manifest. Pinning a platform digest silently breaks your arm64 build.

#### Keeping digests fresh: Renovate

A pinned digest that nobody updates is a pinned vulnerability. **Renovate is the default**: it understands `tag@sha256:digest`, opens MRs when either moves, and works with self-hosted GitLab.

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended", "docker:pinDigests"],
  "packageRules": [
    {
      "matchDatasources": ["docker"],
      "matchUpdateTypes": ["digest"],
      "groupName": "base image digests",
      "schedule": ["before 6am on monday"],
      "automerge": true,
      "automergeType": "branch"
    },
    {
      "matchDatasources": ["docker"],
      "matchUpdateTypes": ["major"],
      "automerge": false
    }
  ]
}
```

- `docker:pinDigests` adds digests to any `FROM`, Compose `image:` or CI `image:` that lacks one.
- **Digest-only updates** (same tag, rebuilt upstream for CVE fixes) are the safe, high-volume ones; automerge them behind a passing pipeline that includes the scan gate.
- Major bumps get a human.

Dependabot handles Dockerfiles on GitHub; on self-hosted GitLab, Renovate is the tool.

> **Note.** Digest pinning also makes builds reproducible in the one sense that matters day to day: a rebuild of last month's commit uses last month's base, so a regression bisects to your code rather than to an upstream push.

### Scan with Trivy

**Default scanner: Trivy.** One binary scans images, filesystems, SBOMs, IaC and secrets; the DB works offline once downloaded. Not installed on this host; every flag below is in the trivy.dev CLI reference for the current release (**v0.74.0**, August 2026).

```bash
trivy image REGISTRY/APP@sha256:DIGEST
```

> **Gotcha.** Trivy itself was a supply-chain target: advisory GHSA-69fq-xp46-6x23 (CVE-2026-33634) covers a malicious **v0.69.4** release (19 March 2026), malicious **v0.69.5/v0.69.6** Docker Hub images, and hijacked `trivy-action`/`setup-trivy` tags. Pin the scanner image or binary by digest/checksum like any other dependency, and never float `aquasec/trivy:latest` in CI.

#### Gate the pipeline, not the dashboard

A gate that fires on 400 findings gets disabled within a week. **Gate on what you can act on: HIGH and CRITICAL with a fix available.**

```bash
trivy image \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --exit-code 1 \
  --ignorefile .trivyignore.yaml \
  REGISTRY/APP@sha256:DIGEST
```

| Flag | Does | Why |
|---|---|---|
| `--severity HIGH,CRITICAL` | Only report these | The gate should be about risk, not volume |
| `--ignore-unfixed` | Drop findings with no fixed version (shorthand for `--ignore-status affected,will_not_fix,fix_deferred,end_of_life`) | You cannot fix what upstream has not fixed; track those separately |
| `--exit-code 1` | Non-zero if anything remains | This is what makes it a gate |
| `--ignorefile FILE` | Explicit, reviewed exceptions | Suppression lives in the repo, visible in MRs |
| `--scanners vuln,secret` | Also look for secrets in layers | Catches the `COPY .env` mistake |
| `--format sarif -o trivy.sarif` | Machine output | `artifacts:reports:sarif` ingests it (GitLab Ultimate, GA in 19.2) — **only when the job succeeds**, so emit it from the non-gating scan |
| `--show-suppressed` | List what was ignored | Audit the ignore file |

Run a **second, non-gating** scan that reports everything, for the security team's backlog:

```bash
trivy image --format json -o trivy-full.json REGISTRY/APP@sha256:DIGEST
```

#### Exceptions with expiry

An ignore without an expiry is a permanent vulnerability. **Every exception carries a date and a reason.**

Plain `.trivyignore`:

```text
# CVE in libfoo's XML parser; we never parse XML. Revisit when base bumps.
CVE-2025-12345 exp:2026-12-31
```

Structured `.trivyignore.yaml` (preferred — scoped to a package and carries a statement; still marked **experimental** in the Trivy docs and never auto-loaded, so `--ignorefile` is mandatory):

```yaml
vulnerabilities:
  - id: CVE-2025-12345
    purls:
      - "pkg:deb/debian/libfoo"
    expired_at: 2026-12-31
    statement: "XML parser path unreachable; tracked in SEC-123"
```

When the date passes, the finding returns and the pipeline fails — which is the point. Review the file in the same MR cadence as Renovate.

#### Offline and air-gapped scanning

```bash
# Connected side
trivy image --download-db-only --cache-dir ./trivy-cache
trivy image --download-java-db-only --cache-dir ./trivy-cache
# Carry ./trivy-cache across, then on the far side:
trivy image --skip-db-update --skip-java-db-update --offline-scan --cache-dir ./trivy-cache IMAGE
```

> **Note.** The Trivy DB is an OCI artifact. Current releases default `--db-repository` to `mirror.gcr.io/aquasec/trivy-db:2,ghcr.io/aquasecurity/trivy-db:2` (tried in order), and `--java-db-repository` likewise. Air-gapped sites can mirror both into their own registry and point the two flags at it instead of copying a cache directory.

### Scan with Grype

Grype (Anchore) is the alternative. **Tiebreaker: pick Grype if you already produce Syft SBOMs and want to scan the SBOM rather than the image**, or want EPSS/KEV-based prioritisation surfaced in the output. Not installed on this host; syntax checked against the Anchore CLI reference (oss.anchore.com). Current release **v0.119.0** (September 2026); anything older than v0.88.0 stopped receiving DB updates when the v5 schema reached end of life on 6 March 2026.

```bash
grype REGISTRY/APP@sha256:DIGEST --only-fixed --fail-on high
grype sbom:./sbom.spdx.json --fail-on critical
grype db status
grype db update
```

`--fail-on high` exits **2** on high *or above*. Ignore rules go in `.grype.yaml`:

```yaml
ignore:
  - vulnerability: CVE-2025-12345
    package:
      name: libfoo
  - fix-state: not-fixed
```

> **Gotcha.** Grype's ignore rules have no expiry field (the documented keys are `vulnerability`, `package`, `fix-state` and friends; confirmed in the Anchore filtering docs). If you use Grype as the gate, put the expiry in a comment and enforce review some other way — or gate with Trivy and use Grype as the second opinion.

**Running both is cheap and catches database differences.** Trivy and Grype use different advisory sources and matching logic; a CVE in one and not the other is common.

### Docker Scout

Docker Scout is Docker's hosted analysis: `docker scout cves`, `docker scout recommendations` (suggests a better base tag), and policy evaluation tied to Docker Hub.

```bash
docker scout quickview IMAGE
docker scout cves --only-severity critical,high --exit-code IMAGE   # --exit-code is a boolean; exits 2 on findings
docker scout recommendations IMAGE
```

The `scout` CLI plugin is **not installed with docker-ce on Fedora** (verified: only `buildx` and `compose` in `/usr/libexec/docker/cli-plugins`). On Engine it installs from `github.com/docker/scout-cli` (install script or release binary into `~/.docker/scout`, per docs.docker.com). It needs a Docker account and sends image metadata (the SBOM) to Docker's service. **Use it only if you already live in Docker Hub/Docker Business**; for self-hosted GitLab and anything air-gapped, Trivy.

### SBOMs

An SBOM is the ingredient list: every package, version and licence in the image. It lets you answer "are we affected by CVE-X?" across every image without re-scanning, and it is increasingly a contractual deliverable.

#### buildx --sbom (at build time)

```bash
docker buildx build \
  --sbom=true \
  --provenance=mode=max \
  -t REGISTRY/APP:TAG --push .
```

BuildKit runs a Syft-based scanner during the build and attaches an SPDX SBOM as an **attestation** in the image index. It sees build stages too, which a post-build scan cannot.

Inspect:

```bash
docker buildx imagetools inspect REGISTRY/APP:TAG --format '{{json .SBOM}}'
docker buildx imagetools inspect REGISTRY/APP:TAG --format '{{json .Provenance}}'
```

> **Version-sensitive.** Attestations live in the image index, which **the classic image store cannot hold**. `--load` keeps them only with the containerd image store (the default on fresh Docker 29 installs, and what this host uses) or when you `--push`. If an SBOM "disappears", check `docker info` for `driver-type io.containerd.snapshotter.v1`.

#### Syft (after the fact, or for anything)

```bash
syft REGISTRY/APP@sha256:DIGEST -o spdx-json=sbom.spdx.json -o cyclonedx-json=sbom.cdx.json   # syft v1.52.0
syft dir:. -o cyclonedx-json          # source tree
```

**Default format: SPDX JSON for compliance deliverables, CycloneDX JSON when the consumer is a security tool** (Dependency-Track ingests CycloneDX natively). Close call; the tiebreaker is what your customer's contract names.

Attach an SBOM you generated separately to the image, signed:

```bash
cosign attest --key cosign.key --type spdxjson --predicate sbom.spdx.json REGISTRY/APP@sha256:DIGEST
```

### Sign and verify with cosign

**Sign the digest. Verify the digest before you run it.** cosign stores the signature in the registry next to the image (as a Sigstore bundle attached as an OCI 1.1 referrer by default in cosign v3.1). It is a separate artifact: move it with `cosign save` / `cosign load` or a referrers-aware copy (`oras cp -r`). `cosign copy` is deprecated in v3.1 and slated for removal in v4.

Not installed on this host; commands below follow the cosign v3.1 reference in `sigstore/cosign/doc`. Current release **v3.1.3** (6 August 2026), which fixes a verification bypass (GHSA-fx35-mq7g-6g98); v2 users need at least **v2.6.5**.

#### Key pair or keyless

| Mode | How it works | Pick when |
|---|---|---|
| **Keyless** (Fulcio + Rekor) | CI's OIDC token gets a short-lived certificate; the signature is logged in the public Rekor transparency log | Connected CI with OIDC (GitLab CI `id_tokens`), public or internet-reachable consumers |
| **Key pair** | You hold `cosign.key` (ideally in KMS/HSM/OpenBao), consumers hold `cosign.pub` | **Air-gapped**, or the verifier cannot reach Fulcio/Rekor, or policy forbids public transparency logs |

**Air-gapped needs keys.** Keyless verification needs the Sigstore trust root and, by default, the Rekor log; on the far side of a gap you have neither unless you run your own Sigstore stack.

#### Key-pair workflow

```bash
cosign generate-key-pair                               # writes cosign.key (encrypted) + cosign.pub
# Or keep the private key in a KMS:
cosign generate-key-pair --kms hashivault://cosign     # Vault/OpenBao transit (the Sigstore docs list both)

cosign sign --key cosign.key REGISTRY/APP@sha256:DIGEST
cosign verify --key cosign.pub REGISTRY/APP@sha256:DIGEST
```

For an air-gapped site that must not contact Rekor at all, give `cosign sign` a signing config that lists no transparency log:

```bash
cosign signing-config create --out offline-signing-config.json   # no --rekor / --tsa services
cosign sign --key cosign.key --signing-config offline-signing-config.json REGISTRY/APP@sha256:DIGEST
cosign verify --key cosign.pub --insecure-ignore-tlog=true REGISTRY/APP@sha256:DIGEST
```

> **Version-sensitive.** cosign v3.1 signs in the **Sigstore bundle format** by default and verifies both old and new formats. `--tlog-upload=false`, `--new-bundle-format` and `--use-signing-config` still work in v3.x but are **deprecated** (hidden from `--help`, removed in v4); the signing config is the replacement. Mixed fleets with v2 verifiers can sign with `--new-bundle-format=false` until the v2 side is upgraded. That an empty `signing-config create` is accepted by `sign --key` is read from the v3.1 docs and an upstream issue, not run here.

#### Keyless workflow (GitLab CI)

```yaml
sign:
  image: REGISTRY/tools/cosign@sha256:DIGEST
  id_tokens:
    SIGSTORE_ID_TOKEN:
      aud: sigstore
  script:
    - cosign sign --yes "$CI_REGISTRY_IMAGE@$IMAGE_DIGEST"
```

```bash
cosign verify \
  --certificate-identity "https://GITLAB_HOST/GROUP/PROJECT//.gitlab-ci.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://GITLAB_HOST" \
  REGISTRY/APP@sha256:DIGEST
```

**Always pin `--certificate-identity` to the exact pipeline and ref.** `--certificate-identity-regexp '.*'` verifies that *someone* signed it, which is not a control.

> **Gotcha.** Keyless with a *self-hosted* GitLab works against public Sigstore only if Fulcio can reach your GitLab's OIDC discovery endpoint. An internal-only GitLab cannot use public Fulcio; use key pairs, or run your own Fulcio.

#### Enforce verification

Signing without verification is theatre. Enforce at the point of deploy:

| Where | How |
|---|---|
| Podman / CRI-O hosts | `/etc/containers/policy.json` with a `sigstoreSigned` requirement per registry — Podman refuses unsigned images at pull |
| Kubernetes | Kyverno `verifyImages` or Sigstore policy-controller |
| Deploy script | `cosign verify` must succeed before `docker run` (fail the script otherwise) |

Podman policy example (verifies cosign signatures natively):

```json
{
  "default": [{ "type": "reject" }],
  "transports": {
    "docker": {
      "REGISTRY/team": [
        { "type": "sigstoreSigned", "keyPath": "/etc/containers/cosign.pub", "signedIdentity": { "type": "matchRepository" } }
      ],
      "registry.access.redhat.com": [{ "type": "insecureAcceptAnything" }]
    }
  }
}
```

Podman also needs `use-sigstore-attachments: true` for that registry in `/etc/containers/registries.d/*.yaml` to find the signatures.

> **One-way door.** Setting `"default": [{"type": "reject"}]` in the system `policy.json` will stop every pull that is not explicitly allowed — including the images your Quadlet units need at boot. Roll it out with the allowlist complete, test with a user-level `~/.config/containers/policy.json` first.

### SLSA provenance

Provenance is a signed statement of **how** an image was built: source repo and commit, builder, build parameters, materials (base image digests). SLSA levels grade how trustworthy that statement is.

| SLSA build level | Requires | You get it by |
|---|---|---|
| L1 | Provenance exists | `docker buildx build --provenance=mode=max` |
| L2 | Provenance signed by a hosted build platform | Build in CI, sign provenance (cosign attest / buildx attestation pushed and signed) |
| L3 | Hardened, isolated builder; provenance unforgeable by the build steps | Ephemeral, isolated runners where the job cannot touch signing keys |

BuildKit adds `mode=min` provenance by default (Docker docs, "Build attestations"). **Set `mode=max` in CI** — it records the full build parameters and materials. Be aware it also records build-arg values, which is one more reason secrets never go in build args.

```bash
docker buildx imagetools inspect REGISTRY/APP:TAG --format '{{json .Provenance.SLSA}}' | jq '.materials'
```

Verify provenance attested with cosign:

```bash
cosign verify-attestation --key cosign.pub --type slsaprovenance REGISTRY/APP@sha256:DIGEST   # slsaprovenance1 for SLSA v1 predicates
```

### Secrets never in layers

**Every layer is a tarball anyone with pull access can extract.** A file deleted in a later layer is still in the earlier one; an `ARG` value is recorded in the image history. Both were demonstrated on this host with a throwaway image.

#### Prove it: docker history

```dockerfile
# Dockerfile.bad — do not do this
FROM busybox:latest
ARG API_TOKEN
RUN echo "using $API_TOKEN" > /dev/null
COPY token.txt /tmp/token.txt
RUN rm /tmp/token.txt
```

```bash
docker build -f Dockerfile.bad --build-arg API_TOKEN=fake-token-123 -t sectest:bad .
docker history --no-trunc --format '{{.CreatedBy}}' sectest:bad
```

Verified output:

```text
RUN |1 API_TOKEN=fake-token-123 /bin/sh -c rm /tmp/token.txt # buildkit
COPY token.txt /tmp/token.txt # buildkit
RUN |1 API_TOKEN=fake-token-123 /bin/sh -c echo "using $API_TOKEN" > /dev/null # buildkit
ARG API_TOKEN=fake-token-123
```

**The build-arg value is in plain text in the image config.** `ENV` is the same — `docker history` on `python:3.13-slim` shows `ENV PYTHON_SHA256=…` for the same reason.

#### Prove it: the "deleted" file

```bash
mkdir out && docker save sectest:bad | tar -x -C out
for b in out/blobs/sha256/*; do
  tar -xOf "$b" 2>/dev/null | grep -aq fake-token && { echo "found in $b"; tar -tf "$b"; }
done
```

Verified:

```text
found in out/blobs/sha256/8f3a243b084a…
tmp/
tmp/token.txt
```

`rm` in a later layer only adds a whiteout; the bytes remain.

#### dive

`dive IMAGE` shows each layer's file changes interactively, which makes "what did this `COPY` actually add?" obvious, and flags wasted space from files added then deleted. Not installed here; it is a single Go binary (`github.com/wagoodman/dive`, v0.13.1 current). In CI, `CI=true dive IMAGE` (or `--ci`) runs non-interactively against the thresholds in `.dive-ci`.

#### BuildKit catches the ARG case

BuildKit's build checks flag it (verified on 29.8):

```bash
docker build --check -f Dockerfile.bad .
# Do not use ARG or ENV instructions for sensitive data (ARG "API_TOKEN")
```

Run `docker build --check` in CI; it costs seconds and also catches other Dockerfile lint.

#### The fix: secret mounts

```dockerfile
# syntax=docker/dockerfile:1
FROM busybox:latest
# As an environment variable, only for this RUN:
RUN --mount=type=secret,id=api_token,env=API_TOKEN \
    test -n "$API_TOKEN" && echo ok
# As a file at /run/secrets/ID (tmpfs, not in the layer):
RUN --mount=type=secret,id=api_token \
    wc -c /run/secrets/api_token
```

```bash
API_TOKEN=... docker build --secret id=api_token,env=API_TOKEN -t sectest:good .
docker buildx build --secret id=api_token,src=$HOME/.config/app/token -t sectest:good .
```

Verified history — the secret appears nowhere:

```text
RUN /bin/sh -c wc -c /run/secrets/api_token # buildkit
RUN /bin/sh -c test -n "$API_TOKEN" && echo ok # buildkit
```

| Need at build time | Use |
|---|---|
| Registry / package index token | `--mount=type=secret` (pip `PIP_INDEX_URL`, npm `.npmrc`, Maven `settings.xml`) |
| Git over SSH for private deps | `--mount=type=ssh` with `docker buildx build --ssh default` |
| Certificates for an internal CA | `COPY` is fine — CA certs are public — but prefer `--mount=type=secret` for client keys |
| Runtime secrets | Not in the image at all: env from a secret store, files from a mounted volume, Podman `--secret` |

> **Gotcha.** A secret mount keeps the secret out of the layer, but **not out of what the command writes**. `RUN --mount=type=secret,id=npmrc,target=/root/.npmrc npm ci` is safe; `RUN --mount=… cp /run/secrets/npmrc /root/.npmrc && npm ci` bakes it in. So does a tool that caches credentials into its config directory.

> **One-way door.** A secret that has been pushed in a layer is compromised. Deleting the tag does not help — anyone who pulled has it, and registries often keep untagged manifests. **Rotate the credential first**, then rebuild and purge.

### A CI pipeline that does all of it

```yaml
stages: [build, scan, sign]

build:
  stage: build
  script:
    - docker buildx build --check .
    - docker buildx build --sbom=true --provenance=mode=max
        --secret id=pip_index,env=PIP_INDEX_URL
        --metadata-file meta.json
        -t "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA" --push .
    - echo "IMAGE_DIGEST=$(jq -r '."containerimage.digest"' meta.json)" >> build.env
  artifacts:
    reports: { dotenv: build.env }

scan:
  stage: scan
  script:
    - trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1
        --ignorefile .trivyignore.yaml "$CI_REGISTRY_IMAGE@$IMAGE_DIGEST"

sign:
  stage: sign
  rules: [{ if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH' }]
  script:
    - cosign sign --yes --key "$COSIGN_KEY_REF" "$CI_REGISTRY_IMAGE@$IMAGE_DIGEST"
```

The digest comes from `--metadata-file`, never from re-resolving the tag. Scan and sign reference the same digest the build produced.

### Checklist

- [ ] Every `FROM` is `tag@sha256:digest`, pinned to the index digest.
- [ ] Renovate opens digest MRs weekly; digest-only bumps automerge behind the scan gate.
- [ ] Final stages use distroless, Chainguard, UBI micro or `-slim`; alpine only where musl is understood.
- [ ] Trivy gates on `--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1`; every ignore has `expired_at` and a statement.
- [ ] An SBOM is attached (`--sbom=true` or `cosign attest`) for every released image.
- [ ] Images are signed by digest; air-gapped consumers have `cosign.pub` and verify before run.
- [ ] Provenance is `mode=max` in CI, and build args contain nothing sensitive.
- [ ] `docker build --check` runs in CI; secrets use `--mount=type=secret`.
- [ ] `docker history --no-trunc` on a release image shows no credentials.

### Traps

- **Signing or scanning a tag.** You attested to bytes you may never deploy. Always `@sha256:`.
- **`rm` of a secret in a later layer.** The earlier layer still has it; `docker save` and `tar` prove it.
- **Secrets in `--build-arg`.** Recorded in history and in `mode=max` provenance.
- **`.trivyignore` entries without expiry.** They become permanent silent risk.
- **Keyless signing for an air-gapped consumer.** They cannot verify it; use a key pair.
- **`--certificate-identity-regexp '.*'`.** Verifies nothing useful.
- **Alpine as a reflex for Python.** Source builds of every wheel, and musl DNS/stack surprises.
- **Pinned digests with no bot.** Frozen CVEs; the pin is only safe with Renovate behind it.
- **Classic image store + `--load`.** Attestations are silently dropped.


---


<a id="10-running-containers-for-real"></a>

## 10 · Running containers for real

*Outside Kubernetes, something still has to restart the process, rotate its logs, cap its memory, update its image and reclaim the disk. On a single host that something should be systemd — and on Fedora, Podman Quadlet is how you hand containers to it.*

### Who supervises the container?

Pick one supervisor per container. Two supervisors fighting (a Docker restart policy *and* a systemd unit that also restarts) is the most common single-host outage pattern: restarts double, stop does not stop, and logs land in two places.

| Setup | Supervisor | Pick when |
|---|---|---|
| **Podman + Quadlet** | systemd | **Default on Fedora.** Boot ordering, dependencies, journald, `systemctl` everything, auto-update, no daemon |
| Docker + `--restart` | dockerd | You are committed to Docker and the containers are independent |
| Docker Compose + `restart:` | dockerd (Compose only creates) | Multi-container app you already describe in Compose |
| systemd unit wrapping `docker run` | systemd *and* dockerd | Avoid — both think they own the lifecycle |

### Restart policies (Docker)

| Policy | Restarts when | After daemon restart / reboot | Use for |
|---|---|---|---|
| `no` (default) | never | not started | One-shot jobs, debugging |
| `on-failure[:N]` | exit code non-zero, up to `N` times | started if it was running | Batch workers that may legitimately exit 0 |
| `always` | any exit | **started, even if you had stopped it manually** | Rarely what you mean |
| **`unless-stopped`** | any exit | started, **unless you stopped it** | **Default for long-running services** |

```bash
docker run -d --restart unless-stopped IMAGE
docker update --restart unless-stopped CONTAINER      # change it on an existing container
docker inspect CONTAINER --format '{{.HostConfig.RestartPolicy.Name}} count={{.RestartCount}}'
```

Behaviour worth knowing:

- Docker backs off between restarts, doubling the delay from 100 ms, and resets the back-off once a container has stayed up for 10 seconds. A crash-looping container shows `Restarting (1) 3 seconds ago` in `docker ps`.
- `on-failure:N` really does cap it: `docker run -d --restart on-failure:3 alpine:3 false` ends `exited` with `RestartCount=3` (verified). `always` / `unless-stopped` have no cap — a crash loop continues forever with back-off.
- `docker stop` marks the container as manually stopped; with `unless-stopped` it stays stopped across reboots.

> **Gotcha.** Restart policies do not react to **health**. A container that is `unhealthy` but still running is left running by plain Docker. See the next section.

### Healthchecks and who acts on them

A healthcheck runs a command inside the container on an interval and sets `.State.Health.Status` to `starting`, `healthy` or `unhealthy`. **What reads that status is the part people get wrong.**

| Consumer | Acts on health? |
|---|---|
| `docker run` standalone | **No.** Status is informational only |
| Docker Compose `depends_on: condition: service_healthy` | Yes — at **startup ordering** only |
| `docker compose up --wait` | Yes — waits for healthy, fails if unhealthy |
| Docker Swarm | Yes — replaces unhealthy tasks |
| Podman `--health-on-failure` (`kill`, `restart`, `stop`) | **Yes** — and with Quadlet, `kill` hands the restart to systemd |
| Podman Quadlet `Notify=healthy` | Yes — the unit is not "started" until healthy, so dependants wait |
| Kubernetes | **Ignores** the image `HEALTHCHECK`; uses its own probes |
| Autoheal-style containers | Yes, via the socket — which you should not mount (chapter 07) |

Define it in the image:

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --start-interval=2s --retries=3 \
  CMD ["/app/healthcheck"]
```

Or at run time:

```bash
docker run -d \
  --health-cmd '/app/healthcheck' \
  --health-interval 30s --health-timeout 3s --health-retries 3 \
  --health-start-period 20s --health-start-interval 2s \
  IMAGE
```

Read it:

```bash
docker inspect CONTAINER --format '{{.State.Health.Status}}'
docker inspect CONTAINER --format '{{json .State.Health}}' | jq '.Log[-3:]'
docker events --filter event=health_status --format '{{.Time}} {{.Actor.Attributes.name}} {{.Status}}'
```

Rules for the check itself:

- **Check the process, not its dependencies.** A healthcheck that queries the database marks every app container unhealthy when the database blips — and with `--health-on-failure=kill` that becomes a restart storm.
- **Use a binary in the image, not `curl`.** Distroless images have no curl or shell. Ship a tiny `/app/healthcheck` (or a `--healthcheck` flag on your own binary).
- `--start-period` gives slow starters time; failures during it do not count. `--start-interval` (Docker Engine 25+) probes more often during that window so healthy is reported quickly.
- Timeouts count as failures. Make the timeout shorter than the interval.

> **Version-sensitive.** `--health-start-interval` / `start_interval` needs Docker Engine 25.0 or later. Podman's equivalent is the separate startup healthcheck (`--health-startup-cmd`, `--health-startup-interval`), which can differ from the regular check.

### Logging drivers

Docker's default is `json-file` **with no rotation** — verified on this host (`Logging Driver: json-file`, no `daemon.json`). Unrotated logs are the most common cause of a full `/var/lib/docker`.

| Driver | `docker logs` works | Rotation | Pick when |
|---|---|---|---|
| **`local`** | yes | built in (defaults: 20 MB × 5 files, compressed) | **Default for Docker hosts**: efficient, rotated, nothing to configure |
| `json-file` | yes | only with `max-size` / `max-file` | A log shipper tails `/var/lib/docker/containers/*/*-json.log` |
| **`journald`** | yes | journald's own (`SystemMaxUse=`) | **Default for Podman / Quadlet**, and Docker hosts that already ship the journal |
| `syslog`, `fluentd`, `gelf`, `awslogs` … | yes, via dual logging (Engine 20.10+) | remote side | You have that pipeline already |
| `none` | no | n/a | Truly noisy containers you never read |

Per container:

```bash
docker run -d --log-driver local --log-opt max-size=10m --log-opt max-file=3 IMAGE
docker run -d --log-driver json-file --log-opt max-size=10m --log-opt max-file=3 --log-opt compress=true IMAGE
docker run -d --log-driver journald --log-opt tag='{{.Name}}' IMAGE
```

Daemon-wide defaults go in `daemon.json` (chapter 08); they apply only to containers created afterwards.

Reading logs:

```bash
docker logs --since 10m --tail 200 -f CONTAINER
docker logs -t CONTAINER 2>&1 | grep -i error        # stderr and stdout are separate streams
journalctl CONTAINER_NAME=CONTAINER --since -1h       # journald driver (Docker)
journalctl --user -u app.service -f                   # Quadlet unit (Podman rootless)
podman logs -f app
```

Find the containers with the largest logs:

```bash
sudo du -sh /var/lib/docker/containers/*/*-json.log 2>/dev/null | sort -h | tail
docker ps -q | xargs -r docker inspect --format '{{.Name}} {{.HostConfig.LogConfig.Type}} {{.HostConfig.LogConfig.Config}}'
```

> **Gotcha.** Truncating a live json log (`: > file-json.log`) works but races with the writer; recreating the container with rotation is the fix. Deleting the file does not free the space while dockerd holds it open.

### Resource limits and OOM on cgroup v2

On cgroup v2 (verified: `Cgroup Version: 2`, systemd driver) each container is a cgroup under `system.slice` (Docker) or your user slice (rootless Podman). Limits are files in that cgroup.

```bash
docker inspect CONTAINER --format '{{.Id}}'
cat /sys/fs/cgroup/system.slice/docker-ID.scope/memory.max
cat /sys/fs/cgroup/system.slice/docker-ID.scope/memory.events
```

#### Memory

- `--memory 512m` sets `memory.max`. When usage (including page cache that cannot be reclaimed) hits it, the **kernel OOM killer kills a process inside that cgroup** — not the host's biggest process.
- If the killed process is PID 1, the container exits with **137** (128 + SIGKILL) and Docker sets `.State.OOMKilled=true`.
- If a child is killed and PID 1 survives, the container keeps running and `OOMKilled` stays `false` — only `memory.events` (`oom_kill` counter) shows it.

Verified on this host:

```bash
docker run --name oomtest --memory 32m --memory-swap 32m alpine:3 sh -c 'x=a; while true; do x="$x$x"; done'
docker inspect oomtest --format 'exit={{.State.ExitCode}} oom={{.State.OOMKilled}}'
# exit=137 oom=true
docker rm oomtest
```

| Setting | Effect |
|---|---|
| `--memory-swap` equal to `--memory` | No swap for the container. **Recommended** — swapping hides leaks as latency |
| `--memory-swap` unset | Container may use swap equal to its memory limit |
| `--memory-reservation` | `memory.low`: protected from reclaim under host pressure |
| `--oom-score-adj` | Makes this container more or less likely to be the host OOM killer's choice |
| `--oom-kill-disable` | Only safe *with* `--memory`; otherwise dangerous (chapter 07) |

#### CPU

**Drop CPU limits for latency-sensitive services; keep memory limits always.** A CPU limit (`--cpus`, which sets `cpu.max`) throttles the container even when the host is idle, which shows up as tail-latency spikes. Use `--cpu-shares` (`cpu.weight`) for relative priority under contention instead. Exception: noisy batch jobs on a shared box, where a hard cap is the point.

Check throttling:

```bash
cat /sys/fs/cgroup/system.slice/docker-ID.scope/cpu.stat    # nr_throttled, throttled_usec
```

#### Change limits live

```bash
docker update --memory 1g --memory-swap 1g --pids-limit 512 CONTAINER
podman update --memory 1g CONTAINER
```

### docker stats

```bash
docker stats                                 # live, running containers
docker stats --no-stream                     # one sample, scriptable
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.PIDs}}\t{{.NetIO}}\t{{.BlockIO}}'
podman stats --no-stream
```

- `MEM USAGE` excludes reclaimable page cache (inactive file), so it is what counts toward the OOM limit.
- `MEM %` is against the container limit, or host RAM if there is none — a container at 3% of 64 GB with no limit is not "fine", it is uncapped.
- `PIDS` near `--pids-limit` means fork failures are coming.

For history rather than a snapshot, scrape cgroup metrics with cAdvisor or Grafana Alloy (read-only `/sys/fs/cgroup`, no socket), or Podman's `podman system service` metrics via Prometheus exporters.

### Podman Quadlet

**Quadlet is Fedora's recommended way to run containers as services.** You write a declarative `.container` file; a systemd generator turns it into a normal `.service` at `daemon-reload`. `podman generate systemd` is deprecated (verified: `[DEPRECATED] Generate systemd units` in 5.8).

#### Where files go

| Scope | Directory |
|---|---|
| Rootless (your user) | `~/.config/containers/systemd/` |
| Rootful (system) | `/etc/containers/systemd/` |
| All users' sessions | `/etc/containers/systemd/users/` (or `users/UID/` for one) |

Unit types: `.container`, `.volume`, `.network`, `.pod`, `.kube`, `.image`, `.build`, `.artifact`.

#### A hardened .container

`~/.config/containers/systemd/app.container` — dry-run verified with the 5.8 generator:

```ini
[Unit]
Description=APP web service
After=network-online.target
Wants=network-online.target

[Container]
Image=registry.example.com/team/app:1.4
ContainerName=app
AutoUpdate=registry
User=10001
Group=10001
ReadOnly=true
Tmpfs=/tmp:rw,noexec,nosuid,size=64m
DropCapability=ALL
NoNewPrivileges=true
PidsLimit=256
Memory=512m
PublishPort=127.0.0.1:8080:8080
Volume=app-data.volume:/data:Z
Environment=APP_ENV=prod
Secret=app-db-password,type=env,target=DB_PASSWORD
HealthCmd=/app/healthcheck
HealthInterval=30s
HealthRetries=3
HealthStartPeriod=20s
HealthOnFailure=kill
Notify=healthy
LogDriver=journald

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=default.target
```

`~/.config/containers/systemd/app-data.volume`:

```ini
[Volume]
VolumeName=app-data
```

What the generator produces (abridged, verified):

```text
Requires=app-data-volume.service
After=app-data-volume.service
Type=notify
NotifyAccess=all
Delegate=yes
KillMode=mixed
ExecStart=/usr/bin/podman run --name app --replace --rm --log-driver journald --cgroups=split
  --memory 512m --pids-limit 256 --tmpfs /tmp:rw,noexec,nosuid,size=64m --sdnotify=healthy -d
  --security-opt=no-new-privileges --cap-drop all --read-only --user 10001:10001
  -v app-data:/data:Z --label io.containers.autoupdate=registry --publish 127.0.0.1:8080:8080 ...
```

Key choices:

| Key | Why |
|---|---|
| `Volume=app-data.volume:…` | Referencing the `.volume` unit adds `Requires=`/`After=` automatically |
| `HealthOnFailure=kill` + `Restart=always` | Podman kills the unhealthy container; **systemd** restarts it — one supervisor |
| `Notify=healthy` | Units that `After=app.service` wait until it is actually healthy |
| `AutoUpdate=registry` | Adds the `io.containers.autoupdate` label for `podman auto-update` |
| `Secret=` | Podman secret created beforehand with `podman secret create` (reads the value from stdin), never in the unit file |
| `--rm --replace` (generated) | Each start is a fresh container from the image: no drift |

#### Operate it

```bash
/usr/libexec/podman/quadlet -dryrun -user      # render and validate without installing
systemctl --user daemon-reload                 # generate app.service
systemctl --user start app.service
systemctl --user status app.service
journalctl --user -u app.service -f
loginctl enable-linger "$USER"                 # rootless units start at boot, without a login
```

`podman quadlet list`, `podman quadlet install FILE` and `podman quadlet print NAME` (present in 5.8, verified) manage the files for you.

> **Gotcha.** `[Install]` in a Quadlet file is honoured by the generator — you do **not** run `systemctl enable` on the generated unit (it errors, because generated units are transient). `WantedBy=default.target` is what makes it start at boot.

> **Gotcha.** Rootless units without `loginctl enable-linger` stop when your last session ends and do not start at boot. It is the first thing to check when "the service vanished overnight".

> **Note.** For Compose-style multi-container apps, write one `.container` per service plus a `.network` unit and reference it with `Network=app.network`, or group them with a `.pod`. `podman kube play` via a `.kube` unit is the alternative if you already have Kubernetes YAML.

### Image updates

#### podman auto-update

With `AutoUpdate=registry`, Podman compares the digest behind the image **tag** in the registry with what the container runs; if it moved, it pulls, restarts the unit, and **rolls back** if the restarted unit fails (`--rollback`, default true, verified).

```bash
podman auto-update --dry-run                   # what would update
podman auto-update                             # do it now
systemctl --user enable --now podman-auto-update.timer    # daily at midnight
systemctl --user list-timers podman-auto-update.timer
```

| Policy | Checks |
|---|---|
| `registry` | Remote digest of the fully-qualified tag. Requires `Image=` to be a full reference |
| `local` | A newer image with the same name in local storage (you built or pulled it yourself) |

Rollback is only as good as your health signal: with `Notify=healthy` a new image that never becomes healthy fails the unit start and is rolled back. Without it, "started" means "process launched".

> **Gotcha.** Auto-update follows a **tag**, which is exactly the mutable pointer chapter 09 tells you not to deploy by. Use it for images whose tag you control and gate (your own `:stable` or `:prod` tag, retagged only after scan and sign), or for low-risk utilities — not for `:latest` from a public registry. Combine with `policy.json` signature enforcement so an update cannot pull an unsigned image.

#### Docker

Docker has no built-in equivalent. **Default: Renovate bumps the digest in Compose or your deploy repo, CI deploys it** — the update is an MR you can review and revert. Watchtower-style containers need the socket (chapter 07) and have been unmaintained at times; avoid.

```bash
docker compose pull && docker compose up -d     # after the digest bump lands
```

### Disk management and prune policy

On this host (verified, `docker system df`): 426 images holding 348 GB with 268 GB reclaimable, and 149 GB of build cache with 116 GB reclaimable. That is a typical developer machine that never prunes.

```bash
docker system df
docker system df -v              # per image, container, volume and cache entry
podman system df
```

#### What each prune removes

Verified against `--help` on Docker 29.8:

| Command | Removes | Keeps |
|---|---|---|
| `docker container prune` | Stopped containers | Running containers |
| `docker image prune` | **Dangling** images (untagged, unreferenced) | Tagged images |
| `docker image prune -a` | Every image not used by a container | Images used by any container, running or stopped |
| `docker builder prune` | Dangling build cache | Cache still referenced |
| `docker builder prune -a` | All build cache | Nothing |
| `docker builder prune --max-used-space 50GB` | Oldest cache until under 50 GB | Most recent cache |
| `docker network prune` | Networks with no containers | Default networks |
| `docker volume prune` | **Anonymous** volumes not used by a container | Named volumes |
| `docker volume prune -a` | **All** unused volumes, including named | Volumes in use |
| `docker system prune` | Stopped containers, unused networks, dangling images, dangling build cache | Volumes, tagged images |
| `docker system prune -a` | Above, plus all unused images and all build cache | Volumes |
| `docker system prune --volumes` | Above, plus **anonymous** volumes | Named volumes |

> **One-way door.** `docker volume prune -a` (and `podman system prune --volumes`) deletes **named volumes that no container currently uses** — which includes the database volume of a Compose stack you ran `docker compose down` on. There is no undo. Never put it in a cron job; back up first, and prefer `--filter label!=keep`.

#### A prune policy

Default for CI runners and build hosts:

```bash
# daily, via a systemd timer
docker container prune -f --filter 'until=24h'
docker image prune -a -f --filter 'until=168h'
docker builder prune -f --max-used-space 50GB
docker network prune -f --filter 'until=24h'
```

Default for workstations: the same, weekly, without the image prune if you rely on large local base images. Never automate volume pruning anywhere.

BuildKit can also garbage-collect itself; set a policy in `daemon.json` so the cache never outgrows its budget. Use the space-based keys, which match the `--reserved-space`, `--max-used-space` and `--min-free-space` flags on `docker builder prune` (they pass `dockerd --validate` on 29.8, verified):

```json
{
  "builder": {
    "gc": {
      "enabled": true,
      "defaultReservedSpace": "10GB",
      "defaultMaxUsedSpace": "50GB",
      "defaultMinFreeSpace": "20GB"
    }
  }
}
```

> **Version-sensitive.** The space-based keys arrived with Docker 28 (28.0.0 renamed the prune API's `keep-bytes` to `reserved-space`). **`defaultKeepStorage` is deprecated and is now equivalent to `defaultReservedSpace`** — a floor GC keeps, not a cap (moby `daemon/config/builder.go`) — so an old `"defaultKeepStorage": "50GB"` stops limiting anything. The cap is `defaultMaxUsedSpace`. Engines before 28 only understand `defaultKeepStorage`, where it *was* the cap. Since 28.2 the containerd image store enables BuildKit GC by default.

Podman:

```bash
podman system prune -f                    # stopped containers, dangling images, unused networks, build cache
podman system prune -a -f                 # plus all unused images
podman image prune -a -f --filter until=168h
```

### Backups

**Back up volumes and configuration, not containers.** A container should be reproducible from an image digest plus its config (Compose file, Quadlet unit). The data in volumes is the only thing that is not.

#### What to back up

| Item | Where | How |
|---|---|---|
| Named volumes | `docker volume inspect VOL --format '{{.Mountpoint}}'` | Application-level dump first, then files |
| Bind-mounted data | the host path | Normal host backup |
| Compose files, Quadlet units, `.env` templates | git | Already versioned (secrets excluded) |
| `/etc/docker/daemon.json`, `/etc/containers/` | host config | Configuration management |
| Images | registry | Already backed up if your registry is; otherwise `skopeo copy` to an OCI archive |

#### Consistent backups

**Use the application's dump tool for databases.** Copying a live PostgreSQL data directory produces a backup that may not restore.

```bash
docker exec DB_CONTAINER pg_dump -U postgres -Fc DBNAME > "db-$(date +%F).dump"
docker exec DB_CONTAINER pg_dumpall -U postgres | gzip > "all-$(date +%F).sql.gz"
```

For plain file volumes, stop (or pause) the writer and archive the volume through a throwaway container:

```bash
docker stop APP
docker run --rm \
  -v APP-data:/data:ro \
  -v "$PWD":/backup \
  alpine:3 tar -C /data -czf "/backup/APP-data-$(date +%F).tgz" .
docker start APP
```

Restore:

```bash
docker volume create APP-data
docker run --rm -v APP-data:/data -v "$PWD":/backup alpine:3 \
  tar -C /data -xzf /backup/APP-data-DATE.tgz
```

Podman has this built in:

```bash
podman volume export app-data --output app-data.tar
podman volume import app-data app-data.tar
```

> **Gotcha.** `tar` inside a container preserves the **container's** numeric UIDs. Restoring into a rootless Podman volume, or a Docker host with a different `userns-remap`, gives files the wrong host owner. Restore through a container with the same user namespace as the one that will read it, or `podman unshare chown` afterwards.

**A backup you have never restored is a hypothesis.** Restore into a scratch volume on a schedule and run the app against it.

### Checklist

- [ ] Every long-running container has exactly one supervisor (`unless-stopped` *or* systemd, not both).
- [ ] Services have a healthcheck that checks the process itself, with a binary that exists in the image.
- [ ] Something acts on health: Quadlet `HealthOnFailure=kill` + `Restart=always`, or Compose `depends_on: service_healthy`.
- [ ] Logging is rotated (`local`, `json-file` with `max-size`, or journald).
- [ ] Every container has `--memory` (with `--memory-swap` equal) and `--pids-limit`; CPU limits only where you mean it.
- [ ] Fedora services are Quadlet units; rootless ones have `enable-linger`.
- [ ] Auto-update follows only tags you control, with signature policy enforced.
- [ ] A prune timer exists for containers, images and build cache — and never for volumes.
- [ ] Volume backups use app-level dumps and have been restored at least once.

### Traps

- **`restart: always` plus a systemd unit.** Two supervisors; `systemctl stop` does not stop.
- **Expecting Docker to restart unhealthy containers.** It doesn't, outside Swarm.
- **`curl` in a distroless healthcheck.** It isn't there; the container is permanently `unhealthy`.
- **Default `json-file` logging.** No rotation; eventually fills the disk.
- **Looking only at `OOMKilled`.** A killed child leaves it `false`; read `memory.events`.
- **`systemctl --user enable` on a Quadlet unit.** Generated units can't be enabled; use `[Install]`.
- **No linger.** Rootless services die at logout.
- **`docker volume prune -a` in cron.** Deletes named volumes of stopped stacks.
- **Copying a live database directory as a backup.** Use the dump tool.


---


<a id="11-when-it-breaks"></a>

## 11 · When it breaks

*Almost every container failure is one of a dozen shapes, and the exit code, the inspect output and the last twenty log lines tell you which one before you touch anything. Read state first, change things second.*

### The first five commands

Before any theory, collect this. It answers most questions and it is what someone else will ask you for.

```bash
docker ps -a --filter name=CONTAINER --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
docker inspect CONTAINER --format 'exit={{.State.ExitCode}} oom={{.State.OOMKilled}} err={{.State.Error}} restarts={{.RestartCount}} started={{.State.StartedAt}} finished={{.State.FinishedAt}}'
docker logs --tail 50 -t CONTAINER
docker inspect CONTAINER --format 'cmd={{json .Config.Cmd}} entrypoint={{json .Config.Entrypoint}} user={{.Config.User}} workdir={{.Config.WorkingDir}}'
docker events --since 30m --filter container=CONTAINER
```

Podman: the same commands with `podman`; for Quadlet units add `systemctl --user status UNIT` and `journalctl --user -u UNIT -n 100`.

```text
                      container won't stay up
                                │
                 ┌──────────────┴──────────────┐
          exit code 125–127?              exit code ≥128?
        (never really started)          (killed by a signal)
                 │                              │
   125 engine/flag error          137 SIGKILL ── OOMKilled=true? → memory
   126 not executable             139 SIGSEGV → arch / libc / real crash
   127 not found                  143 SIGTERM → something stopped it
                 │                              │
          exit 0 or 1–124: the app itself exited — read the logs
```

### Exit codes

| Code | Means | Typical cause | Confirm | Fix |
|---|---|---|---|---|
| **0** | Main process finished | The command is not a long-running server (`bash` with no TTY, a script that returns) | `docker inspect --format '{{json .Config.Cmd}}'` | Run the server in the foreground; no `&`, no `service start` |
| **1**, other <125 | App error | Bad config, missing env var, can't reach dependency | `docker logs` | Fix the app input |
| **125** | The engine could not create/run the container | Bad flag, name conflict, invalid mount, unknown runtime option | The error is printed by the `docker` CLI itself | Fix the command line |
| **126** | Command found but **not executable** | Missing `+x`, a directory, `noexec` mount, wrong shebang interpreter permissions | `docker run --entrypoint sh IMAGE -c 'ls -l /path'` | `chmod +x` in the Dockerfile (`COPY --chmod=0755`) |
| **127** | Command **not found** | Typo, not on `PATH`, shell-form CMD on an image without `/bin/sh`, missing dynamic loader (musl binary on glibc or vice versa) | `docker run --entrypoint /bin/sh IMAGE -c 'command -v X'` | Correct path; build for the right libc |
| **137** | SIGKILL (128+9) | **OOM kill**, `docker kill`, or `docker stop` timeout expired | `OOMKilled` field; `memory.events` | Raise the limit or fix the leak; handle SIGTERM so stop doesn't escalate |
| **139** | SIGSEGV (128+11) | Native crash, wrong-arch binary under emulation, libc mismatch | `docker image inspect --format '{{.Architecture}}'`; `dmesg` | Build for the host arch; debug the native crash |
| **143** | SIGTERM (128+15) | `docker stop`, systemd stop, orchestrator scale-down | `docker events` shows `kill`/`stop` | Expected on stop; if unexpected, find who stopped it |

Verified on Docker 29.8: `nosuchcmd` → 127, running `/etc/hostname` → 126, an unknown flag → 125, a memory-limited allocation loop → 137 with `OOMKilled=true`.

> **Gotcha.** A process running as **PID 1** gets no default signal handlers: SIGTERM is ignored unless the program installs a handler. `docker stop` then waits 10 seconds and sends SIGKILL, and you see **137 on every stop**. Fix with `--init` (tini as PID 1) or exec-form `ENTRYPOINT ["app"]` in an app that handles SIGTERM. The same PID-1 rule is why `kill -SEGV $$` inside a shell container does *not* produce 139.

### Container exits immediately

**Symptom:** `docker ps` shows nothing; `docker ps -a` shows `Exited (N) 2 seconds ago`.

| Cause | Check | Fix |
|---|---|---|
| CMD is not a foreground process | `docker inspect --format '{{json .Config.Cmd}}'` — `bash`, `sh`, or a script that daemonises | Run the server in the foreground (`nginx -g 'daemon off;'`, `exec gunicorn …`) |
| Interactive image with no TTY | Image default is `bash` | `docker run -it` for a shell; otherwise give it a real command |
| Crash on startup | `docker logs CONTAINER` | Read the stack trace; usually config or env |
| Missing env / secret | Log says `KeyError`, `required`, `not set` | Pass `-e`, `--env-file`, or the secret mount |
| Wrong architecture | `exec format error` in the logs | `--platform linux/amd64`, or build multi-arch |
| Entrypoint script with CRLF line endings | `exec ./entrypoint.sh: no such file or directory` though the file exists | `dos2unix`; `.gitattributes` with `*.sh text eol=lf` |

**Get a shell in the same image with the entrypoint bypassed:**

```bash
docker run --rm -it --entrypoint sh IMAGE
docker run --rm -it --entrypoint sh IMAGE -c 'ls -l /app; env | sort'
```

Verified example of the architecture failure:

```bash
docker run --rm --platform linux/arm64 alpine:3 true
# exec /bin/true: exec format error
```

> **Gotcha.** Pulling another platform of a tag with the containerd image store can **replace what the local tag points to**. After the command above, a plain `docker run alpine:3` on this host ran the arm64 image and failed with `exec format error` until `docker pull --platform linux/amd64 alpine:3` restored it. When testing other platforms, tag them separately or use `docker buildx imagetools inspect` instead of pulling.

### OOMKilled

**Symptom:** exit 137, restarts, `OOMKilled: true`, or a process inside dies with no log.

```bash
docker inspect CONTAINER --format 'oom={{.State.OOMKilled}} limit={{.HostConfig.Memory}}'
ID=$(docker inspect CONTAINER --format '{{.Id}}')
cat /sys/fs/cgroup/system.slice/docker-$ID.scope/memory.events     # oom / oom_kill counters
cat /sys/fs/cgroup/system.slice/docker-$ID.scope/memory.peak       # high-water mark (kernel 5.19+)
journalctl -k --since -1h | grep -iE 'oom|killed process'
docker stats --no-stream CONTAINER
```

Decision:

| Finding | Meaning | Fix |
|---|---|---|
| `OOMKilled=true`, usage climbs steadily to the limit | Leak or unbounded cache | Profile the app; cap caches |
| `OOMKilled=true`, spikes at startup | Limit below real working set | Raise `--memory` to peak × 1.25 |
| `OOMKilled=false` but `oom_kill` > 0 | A child process was killed, PID 1 survived | Same fixes; check worker processes |
| No container limit, host `dmesg` shows OOM | Host-level OOM; the kernel chose a victim anywhere | **Set limits on every container** |
| JVM / Node dies with heap errors, not OOM kill | Runtime heap ceiling below container limit, or above it | JVM: `-XX:MaxRAMPercentage=75`; Node: `--max-old-space-size` |

> **Gotcha.** Page cache counts toward `memory.max` on cgroup v2 until the kernel reclaims it. Apps that write large files (log shippers, databases doing bulk loads) can hit the limit on cache, not heap. `memory.stat` shows `file` vs `anon`.

### Permission denied on bind mounts

**Symptom:** `Permission denied` reading or writing a bind-mounted path, even though `ls -l` on the host looks fine. On Fedora there are **two different causes** and they need different fixes. Tell them apart first.

```text
             Permission denied on a bind mount
                         │
       ausearch -m avc -ts recent  shows a denial?
                ┌────────┴────────┐
               yes                no
                │                 │
           SELinux label      UID/GID mismatch
        (:Z / :z / chcon)   (ownership / userns)
```

#### Cause 1: SELinux

```bash
sudo ausearch -m avc -ts recent | grep -E 'container_t|comm='
ls -Z /host/path                      # user_home_t / default_t = not labelled for containers
```

Verified with rootless Podman on this host: without a label suffix, `cat /data/f` → `Permission denied`; with `:Z` → success and the file relabelled to `container_file_t:s0:c145,c537`.

Fix:

```bash
podman run -v /host/path:/data:Z IMAGE          # private to this container
podman run -v /host/path:/data:z IMAGE          # shared between containers
```

> **One-way door.** `:Z`/`:z` relabel the host path permanently. Never on `/home`, `/etc`, `/usr` or your whole home directory. Recover with `restorecon -Rv PATH`.

**Docker on this host does not hit this**, because dockerd runs without `selinux-enabled` and containers are `spc_t` (unconfined; see chapter 07). After enabling it, the same fix applies.

#### Cause 2: UID mismatch

```bash
docker run --rm -v /host/path:/data IMAGE id                 # who the container runs as
ls -ln /host/path                                            # numeric owner on the host
podman unshare ls -ln /host/path                             # owner as seen from inside rootless userns
```

| Situation | Fix |
|---|---|
| Rootful: container runs as UID 10001, dir owned by 1000 | `sudo chown -R 10001:10001 /host/path`, or run with `--user 1000:1000` |
| Rootless Podman: container UID 10001 maps to host `589824+10000` | `podman unshare chown -R 10001:10001 /host/path` |
| Rootless Podman: want host files owned by you | `--userns keep-id` |
| Docker with userns-remap | Owner must be the *remapped* UID (`/etc/subuid` base + container UID) |
| Root in rootless container writes files you can't delete | `podman unshare rm -rf PATH` |

> **Gotcha.** Adding `:U` to a Podman volume (`-v ./data:/data:U`) chowns the host path to the container user automatically. Convenient, and just as permanent as `:Z`. Same rule: narrow paths only.

### DNS not resolving inside containers

**Symptom:** `Could not resolve host`, `Temporary failure in name resolution`, or service names not found between containers.

```bash
docker exec CONTAINER cat /etc/resolv.conf
docker run --rm --network NETWORK alpine:3 nslookup SERVICE_NAME
docker run --rm alpine:3 nslookup example.com
```

What you should see (verified on this Fedora host, where the host uses systemd-resolved at `127.0.0.53`):

| Network | Container `resolv.conf` | Means |
|---|---|---|
| Default bridge | `nameserver 192.168.0.1` (the real upstream) | Docker skips `127.0.0.53` and reads `/run/systemd/resolve/resolv.conf` |
| User-defined network (Compose) | `nameserver 127.0.0.11` | Docker's embedded DNS: container and service names resolve here |

Decision:

| Symptom | Cause | Fix |
|---|---|---|
| Service names don't resolve, external names do | Containers are on the **default bridge**, which has no name resolution between containers | Put them on a user-defined network (Compose does this automatically) |
| Nothing resolves; `resolv.conf` shows `127.0.0.53` | Host's resolver is loopback-only and Docker could not find the upstream file | `--dns 1.1.1.1` for a test; set `"dns": ["UPSTREAM"]` in `daemon.json` |
| Nothing resolves on VPN | VPN pushes DNS to systemd-resolved per-link; containers get the non-VPN upstream | `"dns"` in `daemon.json` pointing at the VPN resolver, or `--dns` per container |
| Resolves, but connections time out | Not DNS — outbound NAT broken (`iptables: false`, firewall reload flushed Docker's rules) | `sudo systemctl restart docker`; never set `iptables: false` |
| Intermittent failures on alpine | musl resolver differences (parallel A/AAAA, TCP fallback) | Test with a glibc image; set `ndots` sensibly |
| Rootless Podman can't resolve | pasta / aardvark-dns issue | `podman info --format '{{.Host.NetworkBackend}}'`; `podman network inspect` |

> **Version-sensitive.** On Fedora with firewalld, a `firewall-cmd --reload` has historically removed Docker's rules until dockerd restarted. Current Docker integrates with firewalld through a `docker` zone and re-applies rules, but if outbound traffic from containers dies right after a firewall reload, restart Docker before debugging anything else.

### Port published but unreachable

**Symptom:** `docker ps` shows `0.0.0.0:8080->80/tcp` but `curl` from another machine (or even locally) hangs or is refused.

Work from the inside out:

```bash
# 1. Is the app listening, and on which address?
docker exec CONTAINER ss -tlnp 2>/dev/null || docker exec CONTAINER netstat -tlnp
# 2. Can the host reach the container IP directly?
docker inspect CONTAINER --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
curl -sS -m 3 http://CONTAINER_IP:80/
# 3. Is the port actually bound on the host, and where?
docker port CONTAINER
ss -tlnp | grep 8080
# 4. From the host, via the published port
curl -sS -m 3 http://127.0.0.1:8080/
```

| Finding | Cause | Fix |
|---|---|---|
| App listens on `127.0.0.1:80` inside the container | App bound to container loopback; nothing outside the container can reach it | Bind the app to `0.0.0.0` (`--host 0.0.0.0`, `HOST=0.0.0.0`) |
| `docker port` shows `127.0.0.1:8080` | Published on loopback only (deliberately, or daemon `"ip": "127.0.0.1"`) | Reach it via the reverse proxy, or publish on a specific interface IP |
| Works locally, not from LAN, firewalld running | Docker's rules normally bypass firewalld; if not, the `docker` zone or `DOCKER-USER` rules block it | `sudo iptables -L DOCKER-USER -n -v`; `firewall-cmd --info-zone=docker` |
| Works from LAN, not from the host itself on its LAN IP | Hairpin NAT with `userland-proxy: false` | Use `127.0.0.1`, or keep the userland proxy |
| Rootless Docker/Podman, port < 1024 | Unprivileged ports only | Publish on ≥1024 or set `net.ipv4.ip_unprivileged_port_start` |
| Rootless, client source IP is wrong | Port driver hides it | pasta (Podman 5 default) preserves it; rootless Docker needs `userland-proxy: false` or a different port driver |
| Container on a network marked `internal: true` | No external connectivity by design | Attach a second, non-internal network for ingress |

> **Gotcha.** The reverse is the more dangerous surprise: a port you **thought** firewalld blocked is reachable, because Docker's DNAT happens before the INPUT chain. Chapter 08 covers binding to loopback and `DOCKER-USER`.

### Build cache not being used

**Symptom:** every build reinstalls dependencies; `--progress=plain` shows no `CACHED` lines.

```bash
docker buildx build --progress=plain . 2>&1 | grep -E 'CACHED|^#[0-9]+ \['
docker buildx du --verbose | head -40
docker buildx ls           # which builder is active?
```

| Cause | Tell-tale | Fix |
|---|---|---|
| `COPY . .` before dependency install | Any source change invalidates the install layer | Copy lockfiles first, install, then copy source |
| No `.dockerignore` | `.git`, `node_modules`, build output change the context hash | Add `.dockerignore` with `.git`, `node_modules`, `dist`, `*.log` |
| Different builder | Cache lives per builder; `docker-container` driver doesn't share the `default` builder's cache (this host has both `mybuilder` and `default`) | Build with the same builder, or export cache |
| CI runner is fresh every time | Local cache is empty by definition | `--cache-to type=registry,ref=REGISTRY/APP:buildcache,mode=max --cache-from type=registry,ref=REGISTRY/APP:buildcache` |
| `ARG` value changes (build number, timestamp, git SHA) | Every step after the `ARG` is invalidated | Declare volatile `ARG`s as late as possible, ideally only in the final stage |
| `--no-cache` or `--pull` in the script | Always rebuilds / always re-resolves base | Remove, or use `--no-cache-filter STAGE` for one stage |
| `RUN apt-get update` split from install | Stale cached `update` layer, not a cache miss — but causes broken installs | Combine them in one `RUN` |
| Base image digest moved | Everything rebuilds after a Renovate bump | Expected |

Use cache mounts for package managers so even a cache miss is fast:

```dockerfile
RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked apt-get update && apt-get install -y --no-install-recommends PKG
```

### No space left on device

**Symptom:** builds or containers fail with `no space left on device`, but `df -h /` may not even look full.

```bash
df -h /var/lib/docker /var/lib/containerd ~/.local/share/containers 2>/dev/null
df -i /var/lib/docker                                  # inodes, not bytes
docker system df
docker buildx du | tail -3
sudo du -sh /var/lib/docker/containers/*/*-json.log 2>/dev/null | sort -h | tail -5
```

This host, verified: 268 GB of reclaimable images and 116 GB of reclaimable build cache. That is the usual answer.

| Where it went | Fix |
|---|---|
| Build cache | `docker builder prune -f --max-used-space 50GB`; set a GC policy (chapter 10) |
| Unused images | `docker image prune -a -f --filter until=168h` |
| Container logs (json-file, no rotation) | Recreate with rotation; daemon default `local` (chapter 08) |
| Stopped containers' writable layers | `docker container prune -f` |
| Anonymous volumes from old `docker run -v /path` | `docker volume prune -f` (anonymous only — **not** `-a`) |
| Inodes exhausted (`df -i` at 100%) | Many small layers or files; prune images and cache |
| `tmpfs` inside the container is full | `--tmpfs /tmp:size=…` too small; the error is from inside the container, not the host |
| `/dev/shm` full (Chrome, PostgreSQL, PyTorch) | Default is 64 MB: `--shm-size 1g` |
| Rootless Podman | Storage lives in `~/.local/share/containers`, in your home filesystem |

> **One-way door.** `docker system prune -a --volumes` on a workstation also removes anonymous volumes, and `docker volume prune -a` removes named ones. Check `docker volume ls` for data you care about first.

### Slow builds

```bash
docker buildx build --progress=plain . 2>&1 | grep -E '^#[0-9]+ DONE [0-9.]+s' | sort -k3 -n -t' ' | tail
docker buildx history ls
docker buildx history inspect
```

| Cause | Fix |
|---|---|
| Huge build context (`transferring context: 2.1GB`) | `.dockerignore` |
| Dependencies re-downloaded every build | Cache mounts (`--mount=type=cache`) |
| Sequential stages that could run in parallel | Split into independent stages; BuildKit runs them concurrently |
| Cross-arch builds under QEMU | Native builders per arch (`docker buildx create --append` a remote arm64 node) or cross-compile in a `--platform=$BUILDPLATFORM` stage |
| Compiling on alpine (musl wheels) | Use a glibc `-slim` base |
| Pulling large bases every time | Stop using `--pull` on every local build; pin digests so pulls are cache hits |
| CI with no cache | Registry cache export/import |

### Debugging distroless containers

**Symptom:** `docker exec -it APP sh` → `exec: "sh": executable file not found`. That's working as intended. Four ways in, in order of preference:

#### 1. A sidecar sharing the namespaces

**Default: attach a tools container to the target's network and PID namespaces.** Nothing is changed in the target.

```bash
docker run --rm -it --network container:APP --pid container:APP nicolaka/netshoot
# inside: ss -tlnp, curl localhost:8080, tcpdump -i eth0, dig, ps aux, ls /proc/1/root/
```

Verified: with `--network container:X --pid container:X`, `ps` in the sidecar shows the target's `sleep` as PID 1. `/proc/1/root` gives you the target's filesystem (read access subject to UID and capabilities — add `--cap-add SYS_PTRACE` for other-UID processes).

Podman is the same: `podman run --rm -it --network container:APP --pid container:APP nicolaka/netshoot`.

> **Gotcha.** You cannot join the namespaces of a **stopped** container (`cannot join network namespace of a non running container`). For a dead container, go to [inspecting a dead container](#inspecting-a-dead-container).

#### 2. nsenter from the host

When you want host tools against the container's namespaces:

```bash
PID=$(docker inspect APP --format '{{.State.Pid}}')
sudo nsenter -t "$PID" -n ss -tlnp          # network namespace only: host's ss, container's sockets
sudo nsenter -t "$PID" -n tcpdump -i eth0 -nn port 8080
sudo nsenter -t "$PID" -m -p ls /           # mount + pid namespace
```

`-n` alone is the useful one: host binaries, container network view. For rootless Podman, `podman unshare nsenter …` or `podman exec` into a sidecar.

#### 3. docker debug

`docker debug APP` attaches a toolbox shell (with `install` for extra packages) to a running container or even an image, without modifying it.

> **Version-sensitive.** `docker debug` ships only with **Docker Desktop** (4.33 and later) as a proprietary CLI plugin that needs a paid Docker subscription. It is **not** part of docker-ce on Fedora (verified: not in `/usr/libexec/docker/cli-plugins`), and there is no standalone Engine build as of September 2026 (`docker/roadmap#893` is open). On a Linux engine, use the sidecar or nsenter.

#### 4. A debug image variant

Distroless publishes `:debug` tags with a busybox shell (`gcr.io/distroless/static-debian12:debug`); Chainguard has `-dev` variants. Run the same app from the debug variant **in a scratch environment** to reproduce. Never ship the debug variant.

#### Copy files in or out

```bash
docker cp APP:/app/config.yaml ./config.yaml
docker cp ./busybox APP:/tmp/busybox      # works on running containers, but read-only rootfs blocks it
```

### Inspecting a dead container

A container that exited is not gone until removed; its writable layer and logs are still there. **Don't `docker rm` or re-run with `--rm` while investigating.**

```bash
docker ps -a --filter status=exited
docker logs CONTAINER                                 # logs survive exit
docker diff CONTAINER                                 # what it changed vs the image
docker cp CONTAINER:/var/log/app ./app-logs           # cp works on stopped containers
docker export CONTAINER -o dead.tar                   # full flattened filesystem
tar -tf dead.tar | grep -E 'core|\.log$'
```

Start a new container from the dead one's filesystem, with a shell, to look around:

```bash
docker commit CONTAINER debug/dead:1
docker run --rm -it --entrypoint sh debug/dead:1     # only if the image has a shell
```

For distroless, export and inspect on the host instead:

```bash
mkdir dead && tar -xf dead.tar -C dead
ls -la dead/tmp dead/app
```

> **Note.** `docker export` flattens the filesystem and drops image metadata (CMD, ENV, history); `docker commit` keeps metadata and adds a layer. Export for forensics, commit for "run it again with a shell". Clean up both images afterwards.

Core dumps: containers inherit the host's `kernel.core_pattern`. On Fedora that pipes to `systemd-coredump`, so `coredumpctl list` on the host shows crashes from containers too.

### Other shapes worth recognising

| Symptom | Cause | Fix |
|---|---|---|
| `Conflict. The container name "/X" is already in use` | Old stopped container with that name | `docker rm X`, or `--replace` in Podman |
| `pull access denied … repository does not exist or may require 'docker login'` | Wrong name, private repo, or expired credentials | `docker login REGISTRY`; check the exact image path |
| `toomanyrequests` from Docker Hub | Anonymous pull rate limit | Log in; use a pull-through cache (Harbor/Zot) |
| `x509: certificate signed by unknown authority` pulling | Internal CA not trusted by the daemon | `/etc/docker/certs.d/REGISTRY/ca.crt`; Podman: `/etc/containers/certs.d/REGISTRY/` |
| `failed to create shim task: OCI runtime create failed` | Runtime rejected the config: bad mount, seccomp, cgroup, device | Read the rest of the line; it names the failing item |
| `Error response from daemon: … is not running` on exec | Container exited | Check exit code first |
| Healthy locally, `unhealthy` in prod | Healthcheck depends on something prod lacks (curl, network) | Healthcheck binary in the image; check the process only |
| Compose `depends_on` ignored | No `condition: service_healthy` | Add the condition and a healthcheck |
| Time wrong in the container | No tzdata, or `TZ` unset | Mount `/etc/localtime:ro` or set `TZ` with tzdata installed |

### Traps

- **Re-running with `--rm` while debugging.** It deletes the evidence on exit.
- **Treating every 137 as OOM.** Check `OOMKilled` — it is often `docker stop` escalating because PID 1 ignored SIGTERM.
- **Fixing SELinux with `label=disable` or `setenforce 0`.** Use `:Z` on a narrow path, or udica.
- **`chown` in rootless without `podman unshare`.** You chown to the wrong host UID.
- **Looking for DNS problems on the default bridge.** Container names never resolve there; use a user network.
- **Assuming firewalld controls published ports.** Docker's DNAT runs first.
- **Pulling another platform of a shared tag to test it.** It can repoint the local tag; use a separate tag.
- **`docker volume prune -a` to free space.** Deletes named volumes you meant to keep.
- **Adding a shell to the production image to debug it.** Use a namespace-sharing sidecar.


---


<a id="12-one-screen-docker-reference"></a>

## 12 · One-screen Docker reference

*The commands worth keeping in muscle memory, grouped by what you are trying to do, with the Podman spelling beside each and the short list of flags that should never appear in anything you ship.*

### Commands by task

Every command here was checked against `--help` on Docker 29.8 / Compose 5.5 / Podman 5.8. For Podman, replace `docker` with `podman` unless the mapping table says otherwise.

#### Run and inspect

```bash
docker run -d --name APP -p 127.0.0.1:8080:8080 IMAGE      # detached, loopback-only port
docker run --rm -it --entrypoint sh IMAGE                  # shell in an image, entrypoint bypassed
docker ps -a --filter status=exited                        # what died
docker logs --since 10m --tail 200 -f APP
docker exec -it APP sh
docker inspect APP --format '{{.State.ExitCode}} {{.State.OOMKilled}}'
docker top APP                                             # processes, from the host's view
docker port APP
docker diff APP                                            # files changed vs the image
docker stats --no-stream
docker events --since 30m --filter container=APP
```

#### Lifecycle

```bash
docker stop -t 30 APP              # SIGTERM, then SIGKILL after 30 s
docker kill -s HUP APP             # send a specific signal (reload config)
docker restart APP
docker update --memory 1g --memory-swap 1g --restart unless-stopped APP
docker rm -f APP
docker rename OLD NEW
docker wait APP                    # block until it exits, print exit code
```

#### Images

```bash
docker pull IMAGE@sha256:DIGEST
docker images --digests
docker image inspect IMAGE --format '{{.Config.User}} {{.Architecture}} {{json .Config.Cmd}}'
docker history --no-trunc --format '{{.CreatedBy}}' IMAGE     # audit for leaked ARG/ENV
docker tag SRC REGISTRY/APP:TAG
docker push REGISTRY/APP:TAG
docker buildx imagetools inspect IMAGE                         # remote manifest, no pull
skopeo inspect --format '{{.Digest}}' docker://IMAGE           # digest without pulling
skopeo copy --all docker://SRC docker://DST                    # every platform, digests preserved
```

#### Build

```bash
docker buildx build -t REGISTRY/APP:TAG --push .
docker buildx build --check .                                  # lint only, no build
docker buildx build --progress=plain --no-cache-filter STAGE .
docker buildx build --platform linux/amd64,linux/arm64 -t REGISTRY/APP:TAG --push .
docker buildx build --secret id=TOKEN,env=TOKEN --ssh default .
docker buildx build --sbom=true --provenance=mode=max --metadata-file meta.json --push -t REGISTRY/APP:TAG .
docker buildx build --cache-to type=registry,ref=REGISTRY/APP:cache,mode=max \
                    --cache-from type=registry,ref=REGISTRY/APP:cache .
docker buildx du
docker buildx ls
docker buildx history ls
```

#### Networks and volumes

```bash
docker network ls
docker network create --internal backend
docker network inspect NET --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{"\n"}}{{end}}'
docker network connect NET APP
docker volume ls
docker volume inspect VOL --format '{{.Mountpoint}}'
docker run --rm -v VOL:/data:ro -v "$PWD":/backup alpine:3 tar -C /data -czf /backup/VOL.tgz .
```

#### Debug

```bash
docker run --rm -it --network container:APP --pid container:APP nicolaka/netshoot
sudo nsenter -t "$(docker inspect APP --format '{{.State.Pid}}')" -n ss -tlnp
docker cp APP:/path ./path                     # works on stopped containers too
docker export APP -o fs.tar                    # flattened filesystem of a dead container
docker commit APP debug/APP:1                  # snapshot to re-run with a shell
```

#### Disk

```bash
docker system df
docker system df -v
docker container prune -f --filter until=24h
docker image prune -a -f --filter until=168h
docker builder prune -f --max-used-space 50GB
docker network prune -f
docker volume prune -f                         # anonymous volumes only
```

#### Daemon and host

```bash
docker info --format '{{.SecurityOptions}} {{.CgroupVersion}} {{.LoggingDriver}}'
docker version --format '{{.Server.Version}}'
docker context ls
docker context create NAME --docker "host=ssh://USER@HOST"
sudo dockerd --validate --config-file /etc/docker/daemon.json
journalctl -u docker --since -1h
```

### --format templates worth keeping

Go templates; `json` renders a value as JSON, `table` adds headers, `\t` separates columns. Every template here ran on this host.

| Want | Command |
|---|---|
| Running containers with health | `docker ps --format 'table {{.Names}}\t{{.State}}\t{{.HealthStatus}}\t{{.RunningFor}}'` |
| Images with digests and size | `docker images --digests --format 'table {{.Repository}}:{{.Tag}}\t{{.Digest}}\t{{.Size}}'` |
| Container IP per network | `docker inspect APP --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}={{$v.IPAddress}} {{end}}'` |
| Mounts | `docker inspect APP --format '{{range .Mounts}}{{.Type}}:{{.Source}}->{{.Destination}} {{end}}'` |
| Environment | `docker inspect APP --format '{{json .Config.Env}}'` |
| Exit state | `docker inspect APP --format 'exit={{.State.ExitCode}} oom={{.State.OOMKilled}} err={{.State.Error}}'` |
| Health log | `docker inspect APP --format '{{json .State.Health}}'` |
| Security posture | `docker inspect APP --format 'priv={{.HostConfig.Privileged}} ro={{.HostConfig.ReadonlyRootfs}} capdrop={{.HostConfig.CapDrop}} capadd={{.HostConfig.CapAdd}} sec={{.HostConfig.SecurityOpt}}'` |
| Limits | `docker inspect APP --format 'mem={{.HostConfig.Memory}} pids={{.HostConfig.PidsLimit}} cpus={{.HostConfig.NanoCpus}}'` |
| Restart policy | `docker inspect APP --format '{{.HostConfig.RestartPolicy.Name}} restarts={{.RestartCount}}'` |
| Log config | `docker inspect APP --format '{{.HostConfig.LogConfig.Type}} {{.HostConfig.LogConfig.Config}}'` |
| Host PID | `docker inspect APP --format '{{.State.Pid}}'` |
| Image user | `docker image inspect IMAGE --format '{{.Config.User}}'` (empty = root) |
| Repo digest | `docker image inspect IMAGE --format '{{index .RepoDigests 0}}'` |
| Volume path | `docker volume inspect VOL --format '{{.Mountpoint}}'` |
| Stats table | `docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.PIDs}}'` |
| Events stream | `docker events --format '{{.Time}} {{.Type}} {{.Action}} {{.Actor.Attributes.name}}'` |
| Every field available | `docker ps --format '{{json .}}'`, piped to `jq` |

Audit one-liners across all running containers:

```bash
# privileged or SYS_ADMIN
docker ps -q | xargs -r docker inspect --format '{{.Name}} priv={{.HostConfig.Privileged}} add={{.HostConfig.CapAdd}}' | grep -E 'priv=true|SYS_ADMIN'
# docker.sock mounted
docker ps -q | xargs -r docker inspect --format '{{.Name}} {{range .Mounts}}{{.Source}} {{end}}' | grep docker.sock
# running as root (empty User)
docker ps -q | xargs -r docker inspect --format '{{.Name}} user={{.Config.User}}' | grep 'user=$'
# no memory limit
docker ps -q | xargs -r docker inspect --format '{{.Name}} mem={{.HostConfig.Memory}}' | grep 'mem=0$'
# published on all interfaces
docker ps --format '{{.Names}} {{.Ports}}' | grep -E '0\.0\.0\.0|\[::\]'
```

### Docker to Podman mapping

Most commands are identical. These are the ones that are not, or that behave differently.

| Task | Docker | Podman | Note |
|---|---|---|---|
| Run as a service | `--restart unless-stopped` | Quadlet `.container` unit | `podman generate systemd` is deprecated |
| Compose | `docker compose` | `podman compose` (wraps docker-compose or podman-compose) | Or Quadlet units / `podman kube play` |
| Auto-update | none built in | `podman auto-update` + `AutoUpdate=registry` | Rolls back on failed start |
| Pods | n/a | `podman pod create`, `--pod NAME` | Shared network namespace, Kubernetes-style |
| Kubernetes YAML | n/a | `podman kube play FILE` / `podman kube generate APP` | Round-trips a pod |
| Enter user namespace | n/a | `podman unshare CMD` | For `chown` of rootless volumes |
| Keep host UID | n/a | `--userns keep-id` | Rootless bind mounts owned by you |
| SELinux label | only with `selinux-enabled` | on by default; `:Z` / `:z` | |
| Chown volume to container user | n/a | `-v SRC:DST:U` | Permanent, like `:Z` |
| Read-only with tmpfs | `--read-only` + `--tmpfs` | `--read-only` (adds tmpfs automatically) | `--read-only-tmpfs=false` for strict |
| Health action | none (informational) | `--health-on-failure kill` / `restart` / `stop` | |
| Secrets at runtime | Swarm only / bind mount | `podman secret create`, `--secret NAME,type=env` | |
| Export a volume | `docker run … tar` | `podman volume export VOL --output FILE` | |
| Remote engine | `docker context create --docker host=ssh://…` | `podman system connection add NAME ssh://…` | |
| Docker-compatible API | the daemon | `systemctl --user enable --now podman.socket` | Socket is at `$XDG_RUNTIME_DIR/podman/podman.sock` |
| Point Docker tools at Podman | n/a | `export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock` | Testcontainers, Compose, etc. |
| Replace a same-named container | `docker rm -f` first | `--replace` | |
| Machine/VM (macOS/Windows) | Docker Desktop | `podman machine` | |
| Image signature policy | none built in | `/etc/containers/policy.json` (`sigstoreSigned`) | Enforced at pull |
| Debug toolbox | `docker debug` (Desktop only) | sidecar with `--pid container:` | |
| Prune | `docker system prune` | `podman system prune` (`--external` for orphaned storage) | |
| Config | `/etc/docker/daemon.json` | `containers.conf`, `storage.conf`, `registries.conf` | Per-user copies in `~/.config/containers/` |
| Default capabilities | 14 | 11 (no `NET_RAW`, `MKNOD`, `AUDIT_WRITE`) | verified |
| Default pids limit | unlimited | 2048 | verified via `--help` |

### Compose cheat sheet

```bash
docker compose up -d                          # create/start, detached
docker compose up -d --wait                   # and wait for healthchecks
docker compose up -d --build                  # rebuild images first
docker compose up -d --force-recreate         # new containers even if config unchanged
docker compose up -d --remove-orphans         # drop services deleted from the file
docker compose up -d --no-deps SERVICE        # just this one, not its dependencies
docker compose watch                          # sync / rebuild on file change (develop.watch)
docker compose ps
docker compose logs -f --tail 100 SERVICE
docker compose exec SERVICE sh
docker compose run --rm SERVICE CMD           # one-off container with the service's config
docker compose restart SERVICE
docker compose stop
docker compose down                           # stop and remove containers + networks
docker compose down -v                        # ALSO named volumes declared in the file
docker compose pull
docker compose config                         # fully resolved file: the first debugging step
docker compose config --quiet                 # validate only
docker compose config --services
docker compose config --images
docker compose config --resolve-image-digests # print with tags pinned to digests
docker compose --profile debug up -d          # include services with profiles: [debug]
docker compose -f compose.yaml -f compose.prod.yaml up -d   # layered files
docker compose ls                             # all projects on this host
docker compose top
```

> **One-way door.** `docker compose down -v` deletes the named volumes the file declares — usually your database. Plain `down` keeps them.

| Compose key | Does |
|---|---|
| `depends_on: {db: {condition: service_healthy}}` | Wait for `db`'s healthcheck before starting |
| `profiles: [debug]` | Service only starts with `--profile debug` |
| `develop.watch` | File-sync / rebuild rules for `compose watch` |
| `x-common: &common` + `<<: *common` | Reuse blocks (hardening defaults) |
| `networks: {backend: {internal: true}}` | No external route |
| `env_file:` / `environment:` | Runtime env; never secrets in the file itself |
| `secrets:` (file-backed) | Mounted at `/run/secrets/NAME` |
| `pull_policy: always` / `missing` / `build` | When Compose pulls |
| `extends:` / `include:` | Compose from other files |

### Flags to never use

Each of these switches off a protection wholesale. If one appears in a runbook, Compose file or CI job, it needs a written reason and a reviewer.

| Flag / setting | What it turns off | Use instead |
|---|---|---|
| `--privileged` | All caps, seccomp, SELinux, device isolation | `--device`, a single `--cap-add`, CDI for GPUs |
| `-v /var/run/docker.sock:…` | Host root, handed to the container | A read-only socket proxy, or no socket |
| `-v /:/host` or other host system paths | Host filesystem | Mount the one directory needed, `:ro` |
| `--security-opt seccomp=unconfined` | Syscall filtering | A custom profile allowing the one syscall |
| `--security-opt label=disable` | SELinux confinement | `:Z` on a narrow path, or udica |
| `--cap-add SYS_ADMIN` / `ALL` | Most of root | The specific capability, or none |
| `--pid=host` | PID isolation: can see and signal host processes | `--pid container:APP` for debugging |
| `--network=host` | Network isolation; also defeats `-p` binding control | Published ports on a bridge |
| `--ipc=host` / `--uts=host` / `--userns=host` | Namespace isolation | Defaults |
| `--oom-kill-disable` without `--memory` | Container OOM containment | A memory limit |
| `-H tcp://0.0.0.0:2375` / `"hosts": ["tcp://…:2375"]` | API authentication | `ssh://` contexts, or 2376 + `tlsverify` |
| `"tls": true` without `"tlsverify": true` | Client authentication | `tlsverify` |
| `"iptables": false` | Container NAT and outbound networking | Filter in `DOCKER-USER` |
| `SocketMode=0666` on `docker.socket` | Everyone is root | Keep `0660 root:docker`, or go rootless |
| `:Z` / `:z` / `:U` on `/`, `/home`, `/etc`, `/usr` | Correct SELinux labels / ownership on the host | Narrow paths only |
| `--build-arg TOKEN=…` for secrets | Nothing — the value is in the history | `--mount=type=secret` |
| `-p 5432:5432` (no bind address) on a server | Your assumption that firewalld protects it | `-p 127.0.0.1:5432:5432` |
| `image: something:latest` in production | Knowing what you run | `tag@sha256:digest` |
| `docker volume prune -a` / `compose down -v` in automation | Your data | Explicit `docker volume rm` after a backup |

### Exit codes, one line each

| Code | Meaning |
|---|---|
| 0 | Process finished — probably not a foreground server |
| 1–124 | App error — read the logs |
| 125 | Engine couldn't create/run it — bad flag or config |
| 126 | Found but not executable |
| 127 | Not found (or missing dynamic loader) |
| 137 | SIGKILL — OOM (check `OOMKilled`) or stop timeout |
| 139 | SIGSEGV — native crash or wrong arch |
| 143 | SIGTERM — something stopped it |

### Checklist

- [ ] Every production `docker run` or Compose service matches the hardened template in chapter 07.
- [ ] None of the never-use flags appears without a reviewed reason; the audit one-liners above return nothing.
- [ ] Images are referenced by digest; `docker compose config --resolve-image-digests` is how you produce them from tags.
- [ ] Remote engines are `ssh://` contexts; no TCP socket without mTLS.
- [ ] Prune is automated for containers, images and build cache; never for volumes.


---
