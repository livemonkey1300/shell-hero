# Cheatsheet

Every alias, function and key binding in this config, grouped by file. **Generated from the config itself** (the same index `zhelp` uses), so it matches what you have.

> In the shell, press **F1** or run `zhelp` for a fuzzy-searchable version of this page. `zhelp -l docker` prints a filtered list. Oh-my-zsh plugin aliases (the ~240 `g*` git aliases and so on) are in `zhelp` too, but not on this page.

Regenerate after changing the config: `docs/gen-cheatsheet.sh`.

- [Daily driver](#daily-driver--zshgodzsh)
- [Core](#core--zshzshrc)
- [Docker](#docker--zshdockerzsh)
- [Kubernetes](#kubernetes--zshk8szsh)
- [Google Cloud & Terraform](#google-cloud--terraform--zshcloudzsh)
- [Bazel](#bazel--zshbazelzsh)
- [Dev tools](#dev-tools--zshdevzsh)
- [Focus & working memory](#focus--working-memory--zshfocuszsh)

## Daily driver — `zsh/god.zsh`

### Listing

| | What it does |
|---|---|
| `ls` | list, dirs first, icons |
| `l` | EVERYTHING: long, hidden, git status, "2 hours ago" |
| `ll` | long list with git status |
| `la` | long list incl. hidden files |
| `lt` | tree, 2 levels, skips .gitignored |
| `lS` | by size, biggest LAST (next to prompt); dirs show real size |
| `lm` | by modified time, newest LAST |
| `lx` | grouped by file extension |
| `ldir` | directories only (ld is the linker) |
| `lf` | files only |
| `l.` | hidden (dot) files only |
| `ltree` | tree to any depth: ltree [depth=3] [dir] |

### Navigation

| | What it does |
|---|---|
| `up` | up N directories: up 3 |
| `cdg` | jump to the root of the current git repo |
| `cdf` | fuzzy-pick any directory below here and cd into it |
| `cl` | cd into a dir and list it |
| `mkt` | cd into a fresh throwaway temp directory |
| `autols` | → [[ $1 == off ]] && _GOD_AUTOLS=0 \|\| _GOD_AUTOLS=1; echo "autols: ${${_GOD_AUTOLS/1/on}/0/off}" |
| <kbd>z <part></kbd> | jump to your most-used dir matching <part> (zoxide; learns as you cd) |
| <kbd>zi</kbd> | fuzzy-pick from every dir you've visited |

### Find & search

| | What it does |
|---|---|
| `ff` | find files by name (fd, includes hidden, skips .git): ff pattern [dir] |
| `ffd` | find directories by name: ffd pattern [dir] |
| `fif` | find text in files, pick a hit with preview, open nvim at that line: fif text [dir] |
| `fkill` | fuzzy-pick processes (Tab = multi) and kill them: fkill [signal] |
| `hs` | search your command history: hs docker |

### Git

| | What it does |
|---|---|
| `fgb` | fuzzy-switch branch (local + remote), preview shows recent commits |
| `fgl` | browse git log with diff preview; Enter = full commit in a pager |

### Files

| | What it does |
|---|---|
| `cp` | ask before overwriting (\cp to skip) |
| `mv` | ask before overwriting (\mv to skip) |
| `rm` | ask once before deleting >3 files or recursing (rm -rf still silent) |
| `del` | move to the trash instead of deleting |
| `trashls` | what's in the trash |
| `trashempty` | empty the trash |
| `cpv` | copy with a progress bar: cpv src dst |
| `bak` | timestamped backup copy: bak file → file.bak-20261103-0930 |
| `sizes` | size of everything here, sorted, biggest last: sizes [dir] |
| `dfh` | disk usage per mount, without the tmpfs/overlay noise |
| `e` | open in your editor: e file |
| `o` | open with the default app: o . / o file.pdf |
| `json` | pretty-print JSON from a pipe: curl … \| json |

### Clipboard

| | What it does |
|---|---|
| `clip` | copy a file's contents (or stdin) to the clipboard: clip file / cmd \| clip |
| `clipp` | print the clipboard |
| `cpwd` | copy the current directory path |

### System

| | What it does |
|---|---|
| `ports` | every listening port + process (macOS) |
| `port` | who is using a port: port 8080 |
| `psg` | find a process: psg node |
| `topmem` | top memory users |
| `topcpu` | top CPU users |
| `meminfo` | RAM / swap |
| `localip` | your IPs, one line per interface |
| `myip` | public IP |
| `path` | PATH, one entry per line |
| `now` | date/time/week |
| `please` | rerun the last command with sudo (or Esc Esc) |
| `upd` | update the whole system, whatever the package manager |
| `serve` | serve this directory over http: serve [port=8000] |
| `cheat` | cheatsheet for any command, from cheat.sh (uses tldr if installed): cheat tar |

### Markdown

| | What it does |
|---|---|
| `mdv` | read markdown RENDERED in a pager (q quits): mdv file.md  (no file = pick one) |
| `mdr` | read markdown RAW, syntax-highlighted: mdr file.md |
| `mdf` | pick a .md with live preview; Ctrl-R flips rendered⇄raw, Enter reads, Ctrl-E edits: mdf [dir] [query] |
| `mdd` | browse your cheatsheets the same way (SHELL_HERO_DOCS, default: the guides in this repo): mdd [query] |

### Images

| | What it does |
|---|---|
| `img` | show images IN the terminal (Ghostty/kitty/WezTerm): img a.png b.jpg  (--width 60) |
| `imgo` | open images in the GUI viewer (Loupe), detached from the shell: imgo pic.png |
| `imgf` | pick an image below here and show it in the terminal: imgf [dir] |

### Documents

| | What it does |
|---|---|
| `pdfv` | flip through a PDF IN the terminal as page images; n/p or →/← to turn, q quits: pdfv file.pdf [page] |
| `pdft` | read a PDF as text (keeps the layout) in a pager: pdft file.pdf |
| `pdfo` | open a PDF in the PDF app (Papers): pdfo file.pdf |
| `docv` | read a Word doc (.docx/.doc/.odt) rendered IN the terminal: docv file.docx  (--raw = markdown source) |
| `doco` | open a document in LibreOffice: doco file.docx |
| `v` | view ANY file in the terminal, picking the viewer by type (md, image, pdf, docx, json, code…): v file  (no file = fuzzy pick with preview) |

### Lint & security

| | What it does |
|---|---|
| `sbom` | SBOM (CycloneDX via syft) + package table; saved as ./sbom.cdx.json: sbom [dir\|image] |
| `vulns` | known vulnerabilities (grype), worst first, in a dir, image or SBOM: vulns [dir\|image\|sbom:file] [--only-fixed] |
| `dlint` | lint every Dockerfile/Containerfile in the repo (hadolint): dlint [files…] |
| `shlint` | lint every shell script (shellcheck; .sh/.bash plus sh/bash shebangs): shlint [files…] |
| `cilint` | validate .gitlab-ci.yml against GitLab (glab, needs login): cilint [file] |
| `lintall` | every linter that applies here: Dockerfiles, shell scripts, GitLab CI |

### Shell

| | What it does |
|---|---|
| `reload` | restart the shell, picking up config changes |
| `zshrc` | edit .zshrc, then reload |
| `zgod` | edit these shortcuts, then reload |
| `ahelp` | old name for zhelp |

### Keys

| | What it does |
|---|---|
| <kbd>F1</kbd> | open zhelp (this list); Enter puts the pick on your prompt |
| <kbd>Ctrl-R</kbd> | fuzzy search history |
| <kbd>Ctrl-T</kbd> | fuzzy pick a file, insert its path |
| <kbd>Alt-C</kbd> | fuzzy cd into a subdirectory |
| <kbd>Alt-Z</kbd> | fuzzy jump to any dir you've visited (zoxide) |
| <kbd>Tab</kbd> | completion menu with fzf + preview (, and . switch groups) |
| <kbd>Ctrl-Space</kbd> | accept the grey autosuggestion |
| <kbd>→ / End</kbd> | accept the grey autosuggestion |
| <kbd>Up / Down</kbd> | history search on what you've typed so far |
| <kbd>Esc Esc</kbd> | put sudo in front of the current/last command |
| <kbd>Ctrl-X Ctrl-E</kbd> | edit the command line in nvim |
| <kbd>Ctrl-Z</kbd> | on an empty prompt: bring the suspended job back (fg) |
| <kbd>Alt-.</kbd> | insert the last argument of the previous command |
| <kbd>Ctrl-U / Ctrl-K</kbd> | delete to start / end of line |
| <kbd>Ctrl-W / Alt-D</kbd> | delete word back / forward |
| <kbd>Ctrl-A / Ctrl-E</kbd> | jump to start / end of line |

## Core — `zsh/zshrc`

### oh-my-zsh

| | What it does |
|---|---|
| `gcm` | oh-my-zsh's git plugin makes gcm "checkout main"; keep it "commit -m". |

### Core behaviour

| | What it does |
|---|---|
| `vim` | → nvim |
| `vi` | → nvim |

### Terminal tools

| | What it does |
|---|---|
| `lg` | git TUI |
| `rr` | file manager TUI |
| `claudeteam` | Claude Code with agent teammates in tmux panes |
| `grep` | → grep --color=auto |
| `diff` | → diff --color=auto |

## Docker — `zsh/docker.zsh`

### Docker Compose

| | What it does |
|---|---|
| `dc` | → docker compose |
| `dcu` | → docker compose up -d |
| `dcd` | → docker compose down |
| `dcr` | → docker compose restart |
| `dcl` | → docker compose logs -f |
| `dcp` | → docker compose pull |
| `dcps` | → docker compose ps |
| `dcb` | → docker compose build |
| `dcex` | → docker compose exec |

### Docker

| | What it does |
|---|---|
| `dps` | → docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}" |
| `dpsa` | → docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}" |
| `dlogs` | → docker logs -f |
| `dstats` | → docker stats --no-stream |
| `dprune` | → docker system prune -f |
| `dinspect` | → docker inspect |
| `dexec` | → docker exec -it |
| `dimages` | → docker images |
| `d` | → docker |
| `di` | → docker images |
| `dex` | → docker exec -it |
| `dcud` | → docker compose up -d |
| `dnet` | → docker network ls |
| `dvol` | → docker volume ls |
| `dhung` | Docker cleanup — hung containers and stale networks |
| `dhungrm` | Force-remove those wedged containers (needs `drestart` if one is truly stuck in the daemon) |
| `dstopall` | → docker stop -t 3 $(docker ps -q) 2>/dev/null \|\| echo "nothing running" |
| `drmall` | → docker rm -f $(docker ps -aq) 2>/dev/null \|\| echo "no containers" |
| `dnetflush` | Networks: prune unused, then the sledgehammer for "network has active endpoints" |
| `drestart` | → sudo systemctl restart docker.service |
| `dflush` | Everything at once: kill wedged containers, drop stale networks, prune the rest |
| `dnetforce` | Force-flush a docker network that refuses to go away because endpoints are |

## Kubernetes — `zsh/k8s.zsh`

### Kubernetes

| | What it does |
|---|---|
| `kubectl` | → kubecolor |
| `k` | → kubectl |
| `kgs` | → kubectl get svc |
| `kp` | → k get po,svc,endpoints,endpointslices.discovery.k8s.io -o wide -A |
| `kpn` | → k get po,svc,endpoints,endpointslices.discovery.k8s.io -o wide |
| `kev` | → k get events -A \| grep Warning |
| `keva` | → k get events -A |
| `kevn` | → k get events \| grep Warning |
| `kevan` | → k get events |
| `ko` | Full-namespace overview: workloads + ingress + config + storage + autoscaling |
| `koa` | → k get all,ingress,cm,secret,pvc,hpa -o wide -A |
| `kpw` | Pod watch (live, current namespace / all namespaces) |
| `kpwa` | → k get po -o wide -w -A |
| `kd` | General-purpose shortcuts |
| `kl` | → k logs -f |
| `klp` | previous container instance, useful after a crash/restart |
| `kaf` | → k apply -f |
| `kdf` | → k delete -f |
| `kgn` | → k get nodes -o wide |
| `ktop` | → kubectl top pods --containers --sort-by=memory |
| `ktopn` | → k top nodes |
| `kgns` | show namespace set by kcontext |
| `kcrd` | CRD inspection — fast reads without leaving the terminal |
| `kcrdw` | → k get crd -o wide |
| `kcrdy` | → k get crd "$1" -o yaml \| less |
| `kexp` | → k explain "$1" --recursive |
| `knewpod` | wizard: create a pod (prompts for name/image/ns/port; run, edit YAML, or cancel) |
| `knewdeploy` | wizard: create a deployment (prompts; run, edit YAML, or cancel) |
| `knewjob` | wizard: create a job (prompts; run, edit YAML, or cancel) |
| `knew` | wizard: pick pod / deployment / job, then prompts for the rest |

### k8s core shortcuts

| | What it does |
|---|---|
| `kg` | → kubectl get |
| `kgp` | → kubectl get pods |
| `kgpa` | → kubectl get pods -A |
| `kgpw` | → kubectl get pods -o wide -w |
| `kgno` | → kubectl get nodes -o wide |
| `kx` | → kubectl exec -it |
| `ke` | → kubectl edit |
| `kevf` | kev is taken (warnings, all ns); kevf pod/foo |
| `ka` | → kubectl apply -f |
| `kk` | → kubectl apply -k |
| `kdiff` | → kubectl diff -f |
| `kdel` | → kubectl delete |
| `kdry` | → kubectl create --dry-run=client -o yaml |
| `kctx` | krew ctx/ns plugins, no kubectx binary installed |
| `kns` | → kubectl ns |
| `h` | → helm |
| `hls` | → helm list -A |
| `fx` | → flux |
| `kbash` | shell into the first pod whose name matches; extra args pass through: kbash api -n my-ns |
| `klf` | fuzzy-pick a pod and tail it: klf [-n ns] |
| `ksec` | decode every key of a secret: ksec my-secret [-n ns] |
| `kgall` | the real "get all": every namespaced kind, including custom resources: kgall [ns] |
| `kwho` | who owns this? ownership tree via krew tree plugin: kwho deploy web |
| `kpf` | port-forward in the background and print the URL: kpf svc/grafana 3000:80 [-n ns] |
| `knet` | throwaway debug pod with network tools |
| `kcontext` | → k config set-context --current --namespace "$@" |

## Google Cloud & Terraform — `zsh/cloud.zsh`

### Google Cloud

| | What it does |
|---|---|
| `gx` | → gcloud |
| `gcfg` | → gcloud config configurations list |
| `gauth` | google login: regular + application (ADC), one browser trip |
| `gadc` | google login: application only (ADC: Terraform, SDKs) |
| `glogin` | google login: regular only (gcloud/kubectl CLI) |
| `gvms` | → gcloud compute instances list --format='table(name,zone.basename(),status,machineType.basename(),networkInterfaces[0].networkIP:label=INTERNAL_IP,scheduling.provisioningModel:label=MODEL)' |
| `gkel` | → gcloud container clusters list --format='table(name,location,currentMasterVersion,currentNodeCount,status)' |
| `garl` | → gcloud artifacts repositories list --format='table(name.basename(),format,name.segment(3):label=LOCATION,sizeBytes.size(units_out=G):label=GB)' |
| `gsl` | → gcloud storage ls |
| `gsm` | → gcloud secrets list |
| `gimpoff` | stop impersonating, whether gimp (env) or `gcloud config set` started it |
| `gwho` | who am I, where am I: account, project, region, impersonation, kube context |
| `gpj` | switch project; no argument = fuzzy-pick from the projects you can see |
| `gcon` | switch named configuration (account + project + region bundle); no arg = pick |

### cross-project inventory

| | What it does |
|---|---|
| `gxr` | → rm -f $_GX_CACHE/*(N); _gx_inv vms >/dev/null; _gx_inv clusters >/dev/null; echo "cached: $(wc -l < $_GX_CACHE/vms.tsv) VMs, $(wc -l < $_GX_CACHE/clusters.tsv) clusters" |
| `gssh` | ssh through IAP, any project: gssh [vm] [-- remote cmd] |
| `gscp` | copy through IAP: gscp ./file vm:/tmp/   (or vm:/path ./); VM looked up in any project |
| `gtun` | forward a VM port to localhost through IAP: gtun vm 8080 [local-port] |
| `gvmon` | → local vm; vm=($(_gx_pick vms "$1")) \|\| return; gcloud compute instances start "${vm[1]}" --zone "${vm[2]}" --project "${vm[3]}" |
| `gvmoff` | → local vm; vm=($(_gx_pick vms "$1")) \|\| return; gcloud compute instances stop  "${vm[1]}" --zone "${vm[2]}" --project "${vm[3]}" |
| `gvmsa` | every VM / cluster you can see, across projects (cached; gxr refreshes) |
| `gkela` | → _gx_inv clusters \| column -t -s $'\t' -N PROJECT,NAME,LOCATION,STATUS |
| `gkec` | GKE credentials, any project; no arg = pick. Extra flags pass through (--dns-endpoint) |
| `gkestale` | kube contexts whose GKE cluster no longer exists; --delete removes them |
| `gkeops` | GKE operations still running (upgrades, resizes); cancel with gcloud container operations cancel ID |
| `gin` | run any command against another project, by unique prefix: gin my-proj gvms |
| `gbind` | grant a role without the interactive condition prompt: gbind PROJECT MEMBER ROLE |
| `garauth` | docker login for Artifact Registry in a region (default: your compute/region) |
| `gart` | images (with tags) in a repo: gart REGION-docker.pkg.dev/PROJECT/REPO |
| `gsmget` | read a secret's latest version: gsmget NAME [version] |
| `glogs` | readable logs: glogs 'resource.type="k8s_container" severity>=ERROR' [1h] |
| `giam` | my roles on the current project (or a given one): giam [project] [member] |
| `gimp` | run gcloud as a service account for this shell only: gimp SA_EMAIL |

### Terraform

| | What it does |
|---|---|
| `tf` | → terraform |
| `tfi` | → terraform init |
| `tfp` | → terraform plan |
| `tfa` | → terraform apply |
| `tfo` | → terraform output |
| `tfv` | → terraform validate |
| `tff` | → terraform fmt -recursive |
| `tfs` | → terraform state list |

## Bazel — `zsh/bazel.zsh`

### bazel

| | What it does |
|---|---|
| `b` | binaries in ~/.local/bin: bazel (bazelisk), buildifier, buildozer, ibazel, target-determinator |
| `bb` | → bazel build |
| `bt` | → bazel test |
| `br` | → bazel run |
| `bzq` | not bq: /usr/bin/bq already exists |
| `bcq` | → bazel cquery |
| `baq` | → bazel aquery |
| `bi` | → bazel info |
| `bmod` | → bazel mod |
| `ib` | → ibazel |
| `bwho` | which targets use this file directly: bwho //lib/auth:token.go |
| `bwhy` | why does A depend on B: bwhy //app:server @pypi//requests |
| `bout` | where did the outputs land: bout //app:server |
| `btlog` | open a test's log: btlog //lib/auth:auth_test |
| `btidy` | tidy everything generated: BUILD files, use_repo lists, formatting |
| `bkinds` | every rule kind in the repo, counted |

## Dev tools — `zsh/dev.zsh`

### Moon

| | What it does |
|---|---|
| `mr` | mr <target>... [flags]: `moon run`, scoped to the current project, or |
| `mrq` | mrq: mr --quiet, with the flag placed before any `--` so moon keeps it. |
| `mt` | → moon tasks "$@" |

### Misc

| | What it does |
|---|---|
| `dotr` | Render a Graphviz .dot file to PNG and open it, e.g. `dotr diagram.dot` |
| `fe` | fuzzy-pick a file and open it in nvim: fe [query] |

## Focus & working memory — `zsh/focus.zsh`

### Capture, handoff, timers

| | What it does |
|---|---|
| `n` | ── Capture ──────────────────────────────────────────────────────────────── |
| `nf` | Retrieve without having to remember where you filed it. Full-text search |
| `park` | ── The handoff note ─────────────────────────────────────────────────────── |
| `ctx` | ── Context persistence ──────────────────────────────────────────────────── |
| `wip` | Stash messages are an instruction to your future self, not a label. |
| `unscored` | ── Decision hygiene ─────────────────────────────────────────────────────── |
| `p` | ── Pomodoro ─────────────────────────────────────────────────────────────── |
| `ps_` | → pomo status; |
| `pd` | → pomo done "$*"; |
| `pb` | → pomo break "$@"; |
| `pl` | → pomo log "${1:-today}"; |

