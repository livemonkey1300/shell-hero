# Linux Command Helper

A speed cheatsheet for everyday Linux investigation (processes, files, network,
logs), shell aliases, git speed commands and **docker compose** debugging. For `kubectl`/Helm, see the
existing [Kubernetes Cheatsheet](./kubernetes-cheatsheet.md) and
[Helm Cheatsheet](./helm-cheatsheet.md) — this doc doesn't repeat those.

> Convention used below: `<...>` is a placeholder you fill in.

---

## 0. Aliases & Shell Helpers

Drop into `~/.bashrc` / `~/.zshrc`:

```bash
# --- navigation ---
alias ..='cd ..'
alias ...='cd ../..'
alias proj='cd ~/my-project'
alias ll='ls -lah'
alias lt='ls -lahtr'                      # sorted by mtime, oldest last
alias po='cd ~/my-project && cd -'        # jump to project, then back

# --- grep / find speedups (install ripgrep + fd) ---
alias rg='rg --smart-case'
alias f='fd'

# --- git ---
alias gs='git status -sb'
alias gd='git diff'
alias gl='git log --oneline --graph --decorate -20'
alias gco='git checkout'
alias gb='git branch --sort=-committerdate'   # most-recently-used branches first

# --- docker compose (projects often pick files like `compose.dev.yml` via .env COMPOSE_FILE) ---
alias dc='docker compose'
alias dcl='docker compose logs -f --tail=200'
alias dcp='docker compose ps'
alias dcx='docker compose exec'

# --- functions ---
# follow logs for one or more compose services: dclogs backend frontend
dclogs() { docker compose logs -f --tail=200 "$@"; }

# jump into a shell inside a running compose service
dcsh() { docker compose exec "${1:?service name}" sh -c '[ -x /bin/bash ] && exec bash || exec sh'; }

# what process owns this port?
whoport() { lsof -iTCP:"$1" -sTCP:LISTEN -n -P; }

# quick disk hog finder in current dir, top 15
dux() { du -ah . 2>/dev/null | sort -rh | head -15; }
```

Reload with `source ~/.zshrc` (or open a new shell).

---

## 1. Fast Navigation & File Search

| Goal | Command | Example |
| --- | --- | --- |
| Jump to frequently-used dirs | `zoxide` (`z`) | `z my-project/backend` |
| Fuzzy find files/history | `fzf` | `vim $(fzf)`, `Ctrl-R` for fuzzy shell history |
| Find files by name | `fd` (or `find`) | `fd docker-compose`, `find . -iname "*.yaml"` |
| Find files modified recently | `find -mmin` | `find . -mmin -30 -type f` (edited in last 30 min) |
| Find files by size | `find -size` | `find . -size +50M` |
| Content search (fast) | `rg` (ripgrep) | `rg -n "APP_REGISTRY" --type env` |
| Content search w/ context | `rg -C` | `rg -C 3 "def migrate" backend/src` |
| List dir sizes | `du -sh */` | `du -sh */ \| sort -rh` |
| Disk usage overview | `ncdu` | `ncdu ~/my-project` (interactive) |
| Free space | `df -h` | `df -h /` |

```bash
# recursively find + act
fd -e py -x wc -l {}                       # count lines in every .py file
find . -name "*.log" -mtime +7 -delete     # delete logs older than 7 days

# ripgrep across the monorepo, respecting .gitignore automatically
rg "TODO|FIXME" --stats
rg -l "postgres" --type-add 'compose:*.yml' -t compose   # files only, custom type
```

---

## 2. Process & System Investigation

| Goal | Command | Example |
| --- | --- | --- |
| Interactive process viewer | `htop` (or `top`) | `htop` |
| Tree view of processes | `pstree` | `pstree -p <pid>` |
| Find process by name | `pgrep` / `ps` | `pgrep -fl uvicorn`, `ps aux \| grep node` |
| Kill by name | `pkill` | `pkill -f vite` |
| What's listening on a port | `ss` / `lsof` | `ss -tulpn \| grep 5173`, `lsof -iTCP:5432 -sTCP:LISTEN` |
| Trace syscalls (why is X hanging) | `strace` | `strace -f -p <pid>` |
| Trace shared libs / opens | `strace -e trace=open,openat` | `strace -e trace=openat -p <pid>` |
| Open files by a process | `lsof -p` | `lsof -p <pid>` |
| CPU/mem live per-process | `top -p` | `top -p <pid>` |
| System journal (systemd) | `journalctl` | `journalctl -u docker -f`, `journalctl --since "10 min ago"` |
| Kernel ring buffer | `dmesg` | `dmesg -T \| tail -50` |
| Env of a running process | `/proc` | `cat /proc/<pid>/environ \| tr '\0' '\n'` |
| Resource limits | `ulimit` | `ulimit -a` |

```bash
# who's eating memory right now
ps aux --sort=-%mem | head -10

# who's eating CPU
ps aux --sort=-%cpu | head -10

# watch a command repeatedly (great for polling a service coming up)
watch -n 2 'docker compose ps'

# free memory / swap
free -h
```

---

## 3. Network Investigation

| Goal | Command | Example |
| --- | --- | --- |
| Test HTTP endpoint | `curl` | `curl -sv https://app.local/api/health` |
| Test HTTP, pretty JSON | `curl \| jq` | `curl -s localhost:8000/health \| jq .` |
| DNS lookup | `dig` / `getent` | `dig app.local`, `getent hosts app.local` |
| Check TCP connectivity | `nc -zv` | `nc -zv localhost 5432` |
| List open sockets | `ss -tulpn` | `ss -tulpn` (all listening TCP/UDP + owning PID) |
| Trace route | `traceroute`/`mtr` | `mtr app.local` |
| Capture packets (need sudo) | `tcpdump` | `sudo tcpdump -i any port 443 -n` |
| Show routing table | `ip route` | `ip route get 8.8.8.8` |

```bash
# is the backend actually listening?
whoport 8000   # (alias defined above)

# repeated health check until it passes
until curl -sf localhost:8000/health; do sleep 1; done && echo UP
```

---

## 4. Log & Text Investigation

| Goal | Command | Example |
| --- | --- | --- |
| Follow a log file | `tail -f` | `tail -f -n 100 backend/.logs/app.log` |
| Follow, filtered | `tail -f \| grep` | `tail -f app.log \| grep --line-buffered ERROR` |
| Search + context | `grep -C` | `grep -C 5 "Traceback" app.log` |
| Count matches | `grep -c` | `grep -c "ERROR" app.log` |
| Multi-file recursive search | `grep -rn` / `rg` | `rg -n "raise Exception" backend/src` |
| Structured JSON logs | `jq` | `docker compose logs backend --no-log-prefix \| jq -R 'fromjson? // .'` |
| YAML inspect | `yq` | `yq '.services \| keys' compose.dev.yml` |
| Diff two files/outputs | `diff` / `delta` | `diff -u old.yaml new.yaml` |
| Pretty-print large JSON | `jq .` | `curl -s api/thing \| jq .` |
| Column-align/parse output | `awk` / `column` | `docker compose ps \| awk '{print $1,$NF}'` |

```bash
# last 200 lines of every compose service log, since 10 min ago
docker compose logs --since 10m --tail=200

# grep across the whole repo excluding node_modules/venvs
rg -n "DATABASE_URL" --glob '!node_modules' --glob '!.venv'
```

---

## 5. Git Speed Commands

| Goal | Command |
| --- | --- |
| Short status | `git status -sb` |
| One-line graph log | `git log --oneline --graph --decorate -20` |
| What changed in this branch vs main | `git diff main...HEAD` |
| List files changed vs main | `git diff --name-only main...HEAD` |
| Who last touched a line | `git blame -L <start>,<end> <file>` |
| Find when a string was introduced | `git log -S "<string>" --oneline` |
| Stash WIP | `git stash -u` / `git stash pop` |
| Interactive add | `git add -p` |
| Clean untracked (dry run first!) | `git clean -ndx` then `-fdx` |
| Current branch's upstream tracking | `git status -sb` (top line) |

```bash
# ticket-prefixed branch names, e.g. <TICKET>-<slug>:
git checkout -b PROJ-123-fix-helm-chart

# see all branches sorted by recent activity
git branch --sort=-committerdate --format='%(committerdate:relative)%09%(refname:short)'
```

---

## 6. Docker Compose Investigation Cheat-Sheet

A stack's compose file(s) can be selected via `.env`'s `COMPOSE_FILE`
(colon-separated list, e.g. `compose.yml:compose.dev.yml`). The examples below
assume a typical stack with `backend`, `frontend`, `nginx`, `postgres`,
`clickhouse` and `redpanda` services, plus a one-shot `backend-init` migration job.

```bash
docker compose ps                          # status + health of every service
docker compose ps --format '{{.Name}}\t{{.Health}}'
docker compose config --services           # list resolved service names
docker compose logs -f backend             # follow one service
docker compose logs -f backend frontend    # follow several
docker compose logs --since 15m nginx      # recent window only
docker compose exec backend bash           # shell into a running container
docker compose exec postgres psql -U postgres
docker compose exec clickhouse clickhouse-client
docker compose exec redpanda rpk topic list
docker compose top backend                 # processes inside that container
docker compose restart backend             # restart just one service
docker stats                               # live CPU/mem for all containers
```

```bash
# "why is backend-init stuck / did migrations run?"
docker compose logs backend-init

# "is a dependency healthy yet?" — poll until it reports healthy
until [ "$(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q postgres)")" = healthy ]; do sleep 2; done

# free up disk from stopped stuff (careful — check first)
docker system df           # see what's using space
docker system prune        # remove unused (safe-ish, prompts first)
```

---

## 7. Quick Reference: "I want to..."

| I want to... | Run |
| --- | --- |
| See what's running locally | `docker compose ps` |
| Tail backend errors only | `docker compose logs -f backend \| grep -i error` |
| Find what's using port 5432 | `whoport 5432` (alias) or `lsof -iTCP:5432 -sTCP:LISTEN` |
| Rebuild everything from scratch | `docker compose down -v && docker compose up -d --build` (⚠ destroys volumes) |
| Reset a broken local kind cluster | `kind delete cluster && kind create cluster` (⚠ destructive) |
| Run one backend test fast | `cd backend && uv run pytest -k <name> -x` |
| Debug a hanging process | `strace -f -p <pid>` or `htop` → select → `l` (lsof) |
| Check disk space before it bites you | `df -h` then `dux` (alias) or `ncdu` |
