# Claude Code kit

A reusable, employer-neutral set of Claude Code instructions, skills, agents and prompt-engineering
patterns. You can drop it into any machine or project.

**Start with `prompt-engineering.md`.** It is the tutorial, and everything else in this kit applies
it.

## What's here

```
claude/
├── README.md                    this file
├── CLAUDE.md.global             personal working-style instructions → ~/.claude/CLAUDE.md
├── prompt-engineering.md        the guide: 40 techniques, each with why / bad / good / what it prevents
├── templates/                   project CLAUDE.md starting points (with "why:" comments per section)
│   ├── generic-repo.CLAUDE.md
│   ├── typescript-extension.CLAUDE.md   monorepo: base + extensions, editor front ends, prompts in code
│   ├── infra-devops.CLAUDE.md           Helm / Terraform / Docker / CI
│   └── rules/llm-prompts.md             a path-scoped .claude/rules file
├── patterns/                    copy-paste prompt snippets (see patterns/README.md)
├── skills/<name>/SKILL.md       → ~/.claude/skills/<name>/SKILL.md
├── agents/<name>.md             → ~/.claude/agents/<name>.md
└── bin/                         helper scripts some skills drive → ~/.claude/bin/
```

### Skills

| Skill | What it does | Needs |
|---|---|---|
| **Focus and context** | | |
| `park` | Capture an open loop in one line without breaking flow | writes `~/.claude/parked.md` |
| `reload` | Rebuild the mental model after a context switch: where you are, what changed, the one next action | git; reads `parked.md`, `decisions.md` |
| `loose-ends` | Everything open (parked, dirty trees, unpushed, PRs), then exactly one thing to do | git, `gh` or `glab`; set `<CHECKOUT_ROOTS>` |
| `what-now` | Asks up to three sharp questions (time, capacity) and converges on one task | as above |
| `decide` | Classify a decision as a one-way or two-way door, size the ceremony, log it with a reopen trigger | writes `~/.claude/decisions.md` |
| `pomo`, `pomo-done`, `pomo-review` | Pomodoro intervals sized to the work's reload cost; honest log; weekly pattern | `bin/pomo` at `~/.claude/bin/pomo`, `notify-send` optional |
| **Writing** | | |
| `fix` | Grammar fix, then five tones | |
| `fix-org` | Grammar fix, then organize into point → message → rapid version → gaps | |
| `fix-org-src` | `fix-org` plus parallel research agents that source each claim | web tools |
| `fix-org-ask` | `fix-org-src`, but interviews you about angle and audience first | web tools |
| `help-me` | Look up a command in your cheatsheet library, then offer to save what was learned | set the docs path (default `~/docs`) |
| **Engineering** | | |
| `start-work` | From a rough request or ticket key: gather, ask ≤4 questions once, branch, plan, hand over | |
| `add-feature` | Add a feature the way the repo already does it: nearest feature's shape, tests wired into CI, docs | |
| `edit-prompt` | Write or tune a prompt/skill/agent/CLAUDE.md using the guide's checklist, then measure it | `references/checklist.md` (included) |
| `technical-plan` | Decompose a change into PR-sized subtasks with a dependency graph and waves | |
| `pr-review` | Review a PR/MR against its ticket; verdict computed by rule; post only on confirmation | `gh` or `glab`; tracker optional |
| `rebase` | Rebase co-pilot: preview conflicts, resolve the mechanical ones, ask on judgement calls, verify | git ≥ 2.44 |
| `fast-commit` | Generate a commit message and commit; hardware-key signing aware; never bypasses hooks | |
| **Delivery workflow** (ticket → merged) | | |
| `ticket-writer` | Write a ticket (Context / Problem / checkable acceptance criteria) or a 30-second catch-up comment; created only after you say so | any `<TRACKER>` |
| `plan-to-tickets` | Turn a `technical-plan` into a story + subtasks with Gherkin ACs and Blocked by / Blocks links | any `<TRACKER>` |
| `implement-subtask` | One ticket → worktree → plan → implement → project checks → staged → draft PR | `gh` or `glab` |
| `story-orchestrator` | Whole story: dependency waves, parallel worktrees, developer → reviewer → fix loop, integration branch a human merges | caps on rounds and parallel agents |
| `pr-feedback` | Act on review comments: sort must-fix / should-fix / question / disagree, fix, check, one reply covering every thread | `gh` or `glab` |
| `change-brief` | A markdown brief of a change: what and why, risk and rollback, how to test, the code a reviewer must read | |
| `expert-panel` | Convene ≤5 role agents on a design question in parallel, then synthesise one answer with disagreements and one-way doors | the role agents below |
| `project-setup` | Make a repo agent-ready: CLAUDE.md from its real commands, rules, specialists picked by its stack, permission allow-list, the delivery loop wired | the kit's `install.sh` |
| `adr` | Architecture decision records: triage whether one is needed, draft, supersede with links both ways | |
| `spec-miner` | Reverse-engineer what the code does today into `SPEC.md`, every claim with `file:line` | |
| `cli-tool` | Robust POSIX/bash scripts and small CLIs: quoting, exit codes, dry-run, portable flags, shellcheck, a test | |
| `open-pr` | Open a draft PR/MR from committed work: stops when nothing is ahead, guards against duplicates, looks up tracker transitions, shows the description first | `gh` or `glab` |
| `handoff` | Stop a long session before context fills; a ≤40-line note a fresh session continues from | |
| `memory-sleep` | Keep a memory file small: add only durable lessons, consolidate ("sleep") past its cap, with a backup | |
| **Ops** | | |
| `k8s-debug` | Diagnose a failing pod by symptom, read-only; mutations shown and run only on a yes (prod-like contexts need the name typed back) | `kubectl` |
| `slo-runbook` | SLIs/SLOs with error-budget and burn-rate maths, one-page runbooks, blameless postmortems | |
| `cloud-cost` | Find waste in a billing export, computed by script; ranked savings, never deletes or buys | billing export |
| **Business** (Canada) | see [`business/README.md`](business/README.md) | set `<PROVINCE>` |
| `finance-ops` | chart of accounts, monthly close, runway, invoices with the right GST/HST/QST lines, filing calendar; never moves money or files | xlsx skill optional |
| `sales-outreach` | ideal customer, prospects, sequences, objections, CRM. **CASL gate per recipient**; refuses harvesting and scraping | |
| `brand-voice` | voice, pillars, style sheet, AI-slop review, bilingual EN/FR for Quebec | |
| `support-triage` | redact personal info, then themes by cost, canned replies, escalation and privacy-incident path | |
| `legal-drafts` | privacy policy (PIPEDA / Law 25), terms, contractor and NDA checklists, CASL policy; **drafts for a lawyer, never advice** | |
| `launch-kit` | Launch copy and timeline (Product Hunt, itch, Show HN, newsletter); drafts only, CASL gate, no vote manipulation | |
| `blog-post` | Research and write a post or case study with cited claims; never publishes | |
| `store-review` | Order/sales CSVs → business review with KPIs and 3 actions; personal info redacted first | |
| **Games** | | |
| `game-start` | Idea → one-page design → playable grey-box loop with deterministic tests; originality gate (no remakes of existing games) | |
| `game-art` | Art, animation and sound **as code**: palette pixel art, vector sprites, particles, Web Audio effects; flashing/colour-blind/motion checks | |
| `game-ship` | Release checklist, itch.io / Pages build, store page from real screenshots, Canadian sales-tax / French / privacy questions | |

### Agents

| Agent | Role | Tools |
|---|---|---|
| `developer` | Red/green TDD implementer; verifies with the repo's own checks; stages, never commits | read + write |
| `reviewer` | Independent reviewer; **no write tools**; runs the checks itself; zero-tolerance list | read-only |
| `technical-writer` | Docs for a named audience, from the real code; never touches source | read + write docs |
| `product-owner` | Runs the TDD ticket loop: developer → reviewer → developer → reviewer → writer | dispatches the three above |
| `docker-build-expert` | How each Dockerfile is really built (bake, compose, CLIs, CI, Bazel) | read-only |
| `vscode-extension-ux-reviewer` | UX review of a VS Code extension's flow in terms of the VS Code API | read-only |
| `go-reviewer` | Go idiom review grounded in Effective Go and the style guides; names where a house rule departs from idiom | read-only |
| `business-advisor` | Founder decisions: pricing, unit economics, runway, incorporation; routes to the business skills | read-only + web |
| `game-designer` | Playtest review: is the loop fun, game feel, difficulty, friction, what to cut; the one change most likely to make it more fun | read-only, runs tests |

**Specialist role agents.** These are advisers, all read-only. Each grounds itself in your repo first (README, CLAUDE.md, ADRs, `git log`, the actual files). It answers verdict-first with `file:line` evidence, labels every claim verified / read in code / inferred / couldn't determine, gives one recommendation, and flags one-way doors. Specialist knowledge such as air-gapped delivery, defence and regulated standards, or geospatial work sits in optional sections; nothing is assumed.

| Ask about… | Agent |
|---|---|
| charts, probes, install/upgrade ordering, CRDs, NetworkPolicy, operators | `kubernetes-helm-engineer` |
| pipelines, runners, build graphs, bake/cache, Terraform/Ansible, immutable images, POSIX shell | `devops-ci-engineer` |
| Renovate, pinning and digests, SBOM, signing, provenance | `supply-chain-engineer` |
| cloud topology, managed vs self-hosted, cost, GCP ↔ AWS translation | `cloud-architect` |
| SLOs, alerts, probes as signals, degraded states, telemetry and RUM, dashboards | `sre-observability-engineer` |
| Dockerfiles and images against CIS / NIST 800-190 / hardening baselines | `container-security-reviewer` |
| threat models, trust boundaries, secrets, vulnerability policy, compliance evidence | `security-architect` |
| "should this land", ADRs, C4, module boundaries, technology adoption, NFRs | `principal-architect` |
| build-vs-buy, replacing a dependency, upstream health, reference architectures (web access) | `tech-researcher` |
| a question spanning several of the above, in one voice | `generalist-oracle` |
| models, migrations, indexes, APIs, workers, audit trails | `backend-engineer` |
| React/TS architecture, auth and cross-tab sessions, client sync, API-client codegen, maps | `frontend-engineer` |
| event contracts, keys and idempotency, dedupe, status machines, binary feeds | `integration-engineer` |
| test strategy, integration harnesses, e2e, flaky tests, "does CI really fail" | `test-quality-engineer` |
| LLM features: grounding, hallucination guards, offset validation, prompt injection | `llm-feature-engineer` |
| shared libraries, devcontainers, onboarding friction, build/runtime plumbing | `platform-library-engineer` |

The **reviewer** can pull in up to two of these for domain checks, and **expert-panel** convenes several at once. They come from real senior engineers' review habits, anonymized and stripped of any employer-specific context.

### Also in here

- [`evals/`](evals/README.md): **behavioural tests for skills**. Each is a prompt plus the observable behaviour it must produce, including a "nothing to do" case. `pr-review`, `implement-subtask` and `open-pr` ship with suites.
- [`lsp/`](lsp/README.md): a repo-local plugin marketplace that gives Claude real language servers (Python, TypeScript). Its README covers the silent `lspServers` trap.
- `templates/rules/`: **`agentic-work.md` (the token-discipline standard for every agent that touches code; reasons in `prompt-engineering.md` Part 10)**, `code-exploration.md` (which search tool first), `shell-scripts.md` (POSIX by default), `llm-prompts.md`.

### bin

- `pomo`: the Pomodoro timer engine (state, notifications, log) that the `pomo*` skills drive. A
  25-minute timer cannot live inside a Claude turn, so it runs as a real background job.
- `kit-lint`: enforces the kit's budgets by script: descriptions ≤ 500 chars (they load into every session), body caps, required sections. `--report` prints the per-session token estimate.
- `statusline.sh`: status line showing model · repo · @branch · dirty count · parked count.

## Install

**Global working style.** Loaded in every session, everywhere:
```sh
cp claude/CLAUDE.md.global ~/.claude/CLAUDE.md      # or merge it into the one you have
```
Fill in or delete the `<YOUR_DOCS_DIR>` line, and delete the comment block at the top.

**Per project.** Copy the closest template to the repo root, fill the `<PLACEHOLDERS>`, then delete
the `why:` comments (they cost tokens every session):
```sh
cp claude/templates/generic-repo.CLAUDE.md ./CLAUDE.md
mkdir -p .claude/rules && cp claude/templates/rules/llm-prompts.md .claude/rules/
```

**Skills.** Personal (`~/.claude/skills/`, every project) or project (`.claude/skills/`, shared with
the repo):
```sh
mkdir -p ~/.claude/skills && cp -r claude/skills/park ~/.claude/skills/
```

**Agents**:
```sh
mkdir -p ~/.claude/agents && cp claude/agents/reviewer.md ~/.claude/agents/
```

**Easiest: ask Claude.** Open Claude Code in this repo and say *"set me up"*. It follows
[`BOOTSTRAP.md`](BOOTSTRAP.md): one round of questions, a dry run, then the install, plus
[`/project-setup`](skills/project-setup/SKILL.md) for a project of yours.

**By hand, with the installer.** Packs are `focus`, `writing`, `engineering`, `workflow`, `ops`, `roles`, `business` and `games`:
```sh
claude/install.sh --list                          # what's in each pack, and what you already have
claude/install.sh --all --dry-run                 # show, change nothing
claude/install.sh --pack focus,engineering        # into ~/.claude
claude/install.sh --pack workflow,roles --project ~/code/my-app   # into that repo's .claude/
claude/install.sh --all --update                  # also replace items you edited (yours → ~/.claude/.kit-backups/)
```
It never overwrites silently: an item that differs from the kit is skipped and named, unless you pass
`--update`. The global `CLAUDE.md` is never touched by the script; copy it yourself, or let Claude merge it.

**Status line**: add to `~/.claude/settings.json`:
```json
"statusLine": { "type": "command", "command": "~/.claude/bin/statusline.sh", "padding": 0 }
```

**Check it took.** In a new `claude` session, type `/` and look for `park`, `reload`, `pr-review`.
Run `/agents` to see `reviewer` and the others.

## Placeholders to fill

| Placeholder | Where | What |
|---|---|---|
| `<CHECKOUT_ROOTS>` | `loose-ends`, `what-now` | Where your clones live, e.g. `~/src/*` |
| `~/docs` | `help-me`, `CLAUDE.md.global` | Your cheatsheet library, if you keep one |
| `origin/main` | `rebase` | Your integration branch, if it isn't `main` |
| `<TRACKER>` | `product-owner`, `pr-review` | How to reach your backlog (MCP connector, `gh issue`, a file) |
| `<PROJECT_NAME>`, `<SPELLING>`… | `templates/*` | Per project |
| Project-specific blocking items | `agents/reviewer.md` | Your stack's recurring defect classes |

## Conventions this kit follows

Canadian spelling. `file:line` for every code reference. Never commit or push unless asked. Writes
outside the session (PR comments, tickets, pushes) are shown exactly and confirmed first.
