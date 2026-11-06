<!--
  Project CLAUDE.md — infrastructure / DevOps repository (Helm charts, Terraform, Ansible,
  Dockerfiles, CI pipelines, cluster config).
  Copy to ./CLAUDE.md and fill in the <PLACEHOLDERS>. Delete the `why:` comments once
  filled in: every line here costs tokens every session.
-->

# <REPO_NAME>: context for Claude Code

<!-- why: in infra, "where does this run" is the first question and the model cannot infer it.
     Name the environments and which of them are real. -->
<One paragraph: what this repo deploys, to where (cloud, on-prem, air-gapped?), and who operates it.>

Environments: `<dev>` (safe to break), `<staging>`, `<prod>` (**never touched from a session**).

## The map

<!-- why: infra repos have many parallel trees (charts, modules, inventories, pipelines). A table
     stops the model editing the generated copy instead of the source. -->
| What | Source | Generated / vendored (do not edit) | Checked by |
|---|---|---|---|
| Helm charts | `charts/<name>/` | `charts/*/charts/*.tgz` | `helm lint`, `helm template … \| kubeconform` |
| Terraform | `terraform/modules/`, `terraform/envs/<env>/` | `.terraform/`, `*.tfstate` | `terraform fmt -check`, `terraform validate`, `tflint` |
| Images | `images/<name>/Dockerfile` | | `hadolint`, `<scanner>` |
| CI | `.gitlab-ci.yml` / `.github/workflows/` | | `<ci lint command>` |

## Safety rules

<!-- why: these are the one-way doors of infrastructure. Stated as hard rules, with the reason,
     because the cost of the model "just trying" an apply is an outage. -->
- **Never run `apply`, `destroy`, `helm upgrade/install/uninstall`, `kubectl apply/delete`, or any
  write against a shared environment.** Produce the plan (`terraform plan`, `helm diff`,
  `kubectl diff`) and hand the exact command to the user.
- **Never print, log or commit a secret.** Secrets come from `<secret manager>`; never inline them in
  values files, tfvars, build ARGs or CI variables in the repo.
- State, CRDs, storage classes, PVCs, DNS records, IAM bindings and anything with data behind it
  are **one-way doors**: say so before proposing a change to one.

## House rules

<!-- why: the conventions that keep environments reproducible. Each carries its reason so the
     model can tell when it applies. -->
- **Pin exactly**: images by digest, charts and providers by exact version. A floor-only pin
  (`>=`, `^`, `latest`) makes local and CI resolve differently.
- A base-image tag must be a literal the dependency bot can see, not assembled from build ARGs.
- **Wait on a condition, never a duration** (`kubectl wait --for=condition=…`, `rollout status`);
  a `sleep` is a bet on machine speed.
- Liveness probes check the process, never an external dependency; readiness may.
- A migration that creates a resource grants the runtime role in the same change.
- Bound every retry and log why it waits.
- Additive before destructive: add the new resource, move traffic, remove the old one last.
- Follow the repo's spelling and naming rules: <SPELLING>, <resource naming convention>.

## Build, test, validate

| Command | When |
|---|---|
| `<make lint>` | before staging |
| `<make template ENV=dev>` | to see what a chart renders |
| `<make plan ENV=dev>` | to see a Terraform change (read-only) |
| `<local cluster up: kind / k3d / tilt up>` | to try a chart end to end, locally |

## Gotchas

<!-- why: the specific traps of this estate, e.g. "the staging cluster has a webhook that rejects
     unpinned images", "module X is shared by three environments". -->
- <...>

## Co-change rules

<!-- why: "when you change A, also change B" is the rule the model breaks most, because B is not in
     the diff it is looking at. Don't put these here: put each in a path-scoped .claude/rules/ file
     so it loads exactly when A is touched. Example, as .claude/rules/compose-profiles.md: -->
<!--
---
paths:
  - "compose.yml"
  - "compose.*.yml"
---
# Compose profiles
Adding a profile to a compose file means documenting it in the `COMPOSE_PROFILES` block of
`.env.example`, one line: `#   <profile>: <what it starts>`. Why: `.env.example` is the only place a
newcomer discovers profiles exist. Profiles set automatically by tooling are not documented there.
-->
- Path-scoped co-change rules live in `.claude/rules/`: <list them, one line each>.

## Working agreement (agents)
<!-- why: the delivery skills (implement-subtask, story-orchestrator, pr-review) read this to know how far they may go. /project-setup fills it in. -->
- **Autonomy:** <advise | implement + stage | implement + commit + draft PR>. Humans merge, always.
- **Parallel agents:** at most <2>. Each one draws on the same Claude subscription limits.
- **Base branch:** `<main>`. Branches: `<type>/<ticket>-<short-title>`.
- **Tracker:** <GitHub Issues | GitLab Issues | Jira PROJ | Linear | none>.
- **Checks that must pass before "done":** `<lint cmd>`, `<test cmd>`.
- **Never without asking:** push, deploy, migrate a shared database, change CI, touch secrets.
