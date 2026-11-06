# Lint, CI & Branching Manual

> lint · format · hooks · branch · merge · pipeline · deploy · debug
> Generated 2026-09-23.

## Contents

- 00 · [Every recommendation, one page](#00-every-recommendation-one-page)
- 01 · [What linting is for](#01-what-linting-is-for)
- 02 · [Per-language setup](#02-per-language-setup)
- 03 · [Linting infra and config](#03-linting-infra-and-config)
- 04 · [Git hooks and pre-commit](#04-git-hooks-and-pre-commit)
- 05 · [Wiring linters into GitLab CI](#05-wiring-linters-into-gitlab-ci)
- 06 · [Branching strategies](#06-branching-strategies)
- 07 · [Merge policy and releases](#07-merge-policy-and-releases)
- 08 · [Anatomy of .gitlab-ci.yml](#08-anatomy-of-gitlab-ci-yml)
- 09 · [Fast, cheap pipelines](#09-fast-cheap-pipelines)
- 10 · [Reuse at scale](#10-reuse-at-scale)
- 11 · [Environments and delivery](#11-environments-and-delivery)
- 12 · [Debugging pipelines](#12-debugging-pipelines)

---


<a id="00-every-recommendation-one-page"></a>

## 00 · Every recommendation, one page

*Every default this guide makes, in tables, with the reason and the chapter that argues it. Defaults are for when you have no reason to choose otherwise; where a line says "close call", the alternative is genuinely defensible and the tiebreaker is named.*

### How to read this

Each row is a **pick**, a **reason**, and the **chapter** that argues it. If you read nothing else, read this chapter and the chapter for whichever line you're about to disagree with.

- **Close call** means the runner-up is a legitimate choice; the tiebreaker is the one fact that should decide it for you.
- **Premium** / **Ultimate** marks a GitLab tier requirement. Self-hosted Free gets most of this guide; the tier-gated rows say what you lose.
- Versions are those current in September 2026 and are pinned in the chapters where they matter.

### Linters and formatters

#### Per language

| Language | Formatter | Linter | Type / static check | Why | Chapter |
|---|---|---|---|---|---|
| Python | **`ruff format`** | **`ruff check`** with an explicit `select` | **mypy `strict`** — *close call* | One tool replaces flake8, isort, pyupgrade, black and most of bandit; `select` makes the rule set immune to ruff 0.16's much larger default set. mypy wins on plugins (Django, pydantic, SQLAlchemy). **Tiebreaker:** no plugin-dependent library → pyright (faster, same engine as Pylance) | languages |
| JS / TS | **Prettier** | **ESLint 10** flat config + typescript-eslint `strictTypeChecked` | **`tsc --noEmit`** | Type-aware rules (`no-floating-promises`, `no-misused-promises`) catch async bugs nothing else does. ESLint 10 is flat-config only | languages |
| JS / TS (alt) | Biome | Biome | `tsc --noEmit` | *Close call.* **Tiebreaker:** no dependency on type-aware rules or framework plugins → Biome (one binary, 10–30× faster) | languages |
| Go | **gofmt + goimports** via golangci-lint | **golangci-lint v2**, `default: standard` + a curated `enable` list | the compiler + `go vet` | One binary, one config; v2 has a separate `formatters:` block. `max-issues-per-linter: 0` or findings are silently truncated | languages |
| Shell | **shfmt** (config in `.editorconfig`) | **shellcheck** | — | The highest-value linter in a DevOps repo; `shfmt -f .` finds scripts without a `.sh` extension | languages |
| Rust | `cargo fmt --check` | `cargo clippy -- -D warnings` | the compiler | `-D warnings` is what makes clippy a gate | languages |

#### Infrastructure and config

| File type | Pick | Why | Chapter |
|---|---|---|---|
| Dockerfile / Containerfile | **hadolint**, `failure-threshold: warning` | Runs shellcheck on every `RUN`; ignore `DL3008`/`DL3018` and pin the base by digest instead | infra-lint |
| YAML | **yamllint** (`extends: default`, tuned), `--strict` | Catches YAML 1.1 traps (`NO` → `false`, `0644` → 420); `--strict` or `warning` rules never fail | infra-lint |
| Markdown | **markdownlint-cli2** | Config-file driven, native Code Quality formatter. Required on docs repos, optional on service repos — *close call*, tiebreaker: are the docs a product users read? | infra-lint |
| JSON / TOML | Prettier / **taplo**; **check-jsonschema** for known schemas | Schema validation catches the typo'd key that syntax checks pass | infra-lint |
| Helm | `helm lint --strict` + **`helm template \| kubeconform -strict`** for every `ci/*-values.yaml` + **ct lint** | Templates aren't YAML until rendered; `ct` enforces version bumps | infra-lint |
| Kubernetes manifests | **kubeconform `-strict`** + **kube-linter** | Schema (`replica: 3` rejected) then policy (root, limits, probes). Never `-ignore-missing-schemas` | infra-lint |
| Terraform / OpenTofu | `fmt -check`, `validate` (`init -backend=false`), **tflint**, **Trivy config** | Trivy is the same tool you gate images with. **Tiebreaker for checkov:** you need graph-based cross-resource checks or many custom policies | infra-lint |
| `.gitlab-ci.yml` | **`check-gitlab-ci`** in the hook (offline), **`glab ci lint --dry-run --ref main`** before merging CI changes | The schema check can't resolve includes or evaluate rules; the dry run can | infra-lint |
| Everything | **`.editorconfig`** | Prevents the pointless diffs; shfmt reads it | infra-lint |

#### Policy for all of them

| Decision | Pick | Why | Chapter |
|---|---|---|---|
| Warning policy | **Zero warnings.** Every enabled rule is an error | A linter with 40 warnings is a linter nobody reads | philosophy |
| Suppressions | Always rule-specific with a reason; lint the suppressions (`RUF100`, `nolintlint`, `reportUnusedDisableDirectives`) | Blanket `# noqa` silences future real findings | philosophy |
| Legacy codebase | Formatter first (one MR, `.git-blame-ignore-revs`) → small high-value rule set, fixed → wider set with a baseline → scheduled full run | A ratchet that only shrinks | philosophy |
| Changed-files mode | Only for slow per-file linters, always with a scheduled full run; **never for type checkers** | Changes in A create findings in untouched B | philosophy, ci-reporting |
| Version pinning | Exact versions, **one source of truth per tool**; Renovate proposes bumps | Unpinned linters break pipelines for changes nobody made | philosophy, hooks |
| Informational vs required | Gate: formatters, linters, type check, tests, secrets, CI YAML, fixable HIGH/CRITICAL CVEs. Report only: complexity, coverage deltas, SAST below HIGH, unfixable CVEs | A gate that fires on 400 findings gets disabled within a week | philosophy |

### Hooks and commit messages

| Decision | Pick | Why | Chapter |
|---|---|---|---|
| Hook manager | **pre-commit** | Builds an isolated, pinned env per hook, so contributors get shellcheck/hadolint/gitleaks without installing them; the same config runs in CI. **Tiebreaker for lefthook:** tools already provisioned by the project toolchain (npm, uv, mise) and you want parallel jobs with no second package manager | hooks |
| Toolchain tools in hooks | `repo: local` calling `uv run` / `npx --no-install` | One version pin per tool, not two | hooks |
| Standalone tools in hooks | pre-commit repos **pinned by SHA** (`autoupdate --freeze`) | Tags are mutable | hooks |
| Hook budget | Under ~3 s for `pre-commit`; type checks at `pre-push` | Slow hooks teach `--no-verify`, which also skips the secret scan | philosophy, hooks |
| pre-commit in CI | `pre-commit run --all-files --show-diff-on-failure`, `PRE_COMMIT_HOME` inside `CI_PROJECT_DIR`, cache keyed on the config, `SKIP=gitleaks` | Caches outside the project dir are never saved; the gitleaks hook scans the (empty) index in CI | hooks |
| Secret scanning | **gitleaks** in the hook (`--staged`), in CI on the MR range (`--redact`), and a full-history scan once | A pushed secret must be rotated; that's the one irreversible lint failure | hooks, ci-reporting |
| Commit convention | **Conventional Commits** | The release tooling computes semver and the changelog from it | hooks, merge-policy |
| Commit checker | **commitizen** (`cz check`). **Tiebreaker for commitlint:** the repo is already a Node project | Python hook, no Node runtime in hooks or CI | hooks |
| What to lint | **The MR title** (squash lands it on `main`), not every branch commit | The squash commit is the only message that survives | hooks, merge-policy |

### Branching and merging

#### Branching model

**Default: trunk-based development with short-lived MR branches** — hours to two days — and **`release/X.Y` branches only for versions you ship and must patch** (GitLab flow with release branches when you need them). Not gitflow.

**Reason:** every integration problem is the price of code living apart from `main`. Trunk-based keeps that bet small; gitflow's `develop` branch adds a second integration point without adding a capability, and trains long-lived branches and big-batch reviews into the team.

**Tiebreaker:** if an auditor or change board requires **production state to be a git ref**, add GitLab flow **environment branches**. Otherwise promote one immutable artefact through protected environments.

| Decision | Pick | Why | Chapter |
|---|---|---|---|
| Model | **Trunk-based** (+ release branches only when you support several versions) | Short branches, one trunk; flags for unfinished work | branching |
| Branch naming | `TYPE/PROJ-123-slug`, enforced by push rule or CI job | Jira linking and scannable MR lists | branching |
| Unfinished work | Feature flags with an owner and a removal ticket | Lets branches stay short | branching |
| Hotfixes | Land on `main` first, cherry-pick down with `-x` | Fixes never regress in the next release | branching |

#### Merge method and squash

| Decision | Pick | Why | Chapter |
|---|---|---|---|
| Merge method | **Fast-forward merge** — *close call* | Linear history; `main` only contains commits tested in exactly that order. **Tiebreaker for merge commit with semi-linear history:** your MRs regularly contain several commits that each deserve to be individually bisectable and revertable — semi-linear keeps them and still marks the MR boundary | merge-policy |
| Squash | **Require** (with fast-forward) | One MR = one commit = one clean revert; changelog tools parse one message per change | merge-policy |
| Squash commit template | `%{title}` + body | The Conventional Commit MR title becomes the commit subject | merge-policy |
| Merged results pipelines | **On** (Premium) | Test the merge, not the branch | merge-policy |
| Merge trains | **On** once more than a few MRs merge per day (Premium) | Fast-forward without trains on a busy repo means everyone clicks Rebase all day | merge-policy |
| Delete source branch | On by default | Stale branches are noise | merge-policy |

#### Protected branches and approvals

| Control | `main` | `release/*` | Why | Chapter |
|---|---|---|---|---|
| Allowed to merge | Developers + Maintainers | Maintainers | Normal path is an MR | merge-policy |
| Allowed to push and merge | **No one** | **No one** | Every change arrives through an MR with a pipeline | merge-policy |
| Force push | **Off** | **Off** | Rewriting shared history is a one-way door (below) | merge-policy |
| Code owner approval | **On** (Premium) | **On** | CODEOWNERS becomes mandatory; protect `CODEOWNERS` itself | merge-policy |
| Protected tags | `v*`, Maintainers (or the release bot) only | — | Tags trigger releases; protected variables only reach protected refs | merge-policy |
| Approval / merge check | Value | Why | Chapter |
|---|---|---|---|
| Minimum approvals | 1 for services, 2 for infra/platform repos | Two eyes on anything that can take down more than one service | merge-policy |
| Prevent approval by author | **On** | Self-approval defeats the point | merge-policy |
| Prevent approvals by users who add commits | **On** | Pushing a fix makes you an author | merge-policy |
| Prevent editing approval rules in MRs | **On** | Authors can't lower their own bar | merge-policy |
| Remove approvals when commits are added | **On** (or code-owner-scoped) | Approvals cover the code that merges | merge-policy |
| Pipelines must succeed | **On** | "Green" must mean something | merge-policy |
| Skipped pipelines count as successful | **Off** | Otherwise `ci.skip` walks around the gate | merge-policy |
| All threads must be resolved | **On** | Review comments aren't advisory | merge-policy |
| Where to set these | **Group level** where you can (Premium) | Every repo answers the same questions the same way | merge-policy |

### CI structure

| Decision | Pick | Why | Chapter |
|---|---|---|---|
| Job conditions | **`rules:`**, never `only`/`except` | `only`/`except` is legacy, can't express AND/OR cleanly, and can't be mixed with `rules` in one job | ci-anatomy |
| Pipeline creation | **`workflow:rules`** with the `$CI_OPEN_MERGE_REQUESTS` pattern | MR pipelines for MRs, branch pipelines for branches without one, tag pipelines — no duplicates | ci-anatomy |
| Always create an MR pipeline | Yes, even for docs-only changes | "Pipelines must succeed" + no pipeline = unmergeable MR | ci-anatomy |
| Ordering | Declare `stages:` for layout, wire every job with **`needs:`** (the DAG) | Jobs start when their inputs are ready, not when a stage drains | ci-anatomy, ci-speed |
| Lint jobs | **`needs: []`**, one job per ecosystem | The lint stage finishes in the time of the slowest job | ci-reporting |
| Reuse within a file | **`extends`** for job templates, **`!reference`** for shared `rules`/`script`; no YAML anchors | Anchors don't work across `include` | ci-anatomy |
| Reuse across projects | **CI/CD components** with typed `spec:inputs`, consumed at a pinned major (`@1`) internally, exact versions + Renovate for third party. `include: project` only on instances older than 17.0 | Shared CI is a library: version it | ci-reuse |
| Auto-cancel | **`interruptible: true`** on build/test/lint, `false` on deploys; `workflow:auto_cancel:on_new_commit: interruptible` | Stale pipelines cost runner time and nothing else | ci-anatomy, ci-speed |
| `rules:changes` | In **MR pipelines**, or with `compare_to` on branch pipelines; always unconditional on the default branch; include config files in `paths` | Branch pipelines compare push-to-push; new branches, tags and schedules always evaluate true | ci-reporting, ci-speed |
| Dependency caches | Key on the lockfile (`cache:key:files`) with `fallback_keys` to the default branch | Changes exactly when dependencies change | ci-speed |
| Analysis caches (ruff, mypy, ESLint, golangci-lint) | Key on branch with fallback to default; all paths inside `CI_PROJECT_DIR` | Warm first run on a new branch | ci-reporting, ci-speed |
| Cache policy | `pull` in MRs, `pull-push` on the default branch | MRs can't overwrite `main`'s cache; no upload races | ci-reporting, ci-speed |
| Reports | Code Quality or JUnit from every lint job, `artifacts:when: always`, **also on the default branch** | Findings in the MR, not the log; widgets diff against the target branch's report | ci-reporting |
| Lint failure semantics | Tool exit status = job status; capture-convert-exit; never `\|\| true` or `allow_failure: true` on a gate | Most broken lint jobs pass silently | ci-reporting |
| SAST / secret detection | Templates (or components if mirrored) on Ultimate; **your own gitleaks job on Free** | On Free the analysers produce an artefact nobody reads and fail nothing | ci-reporting |
| Image builds | **Rootless BuildKit** (`buildctl-daemonless.sh`) with registry cache | Same engine as `docker buildx`; no privileged runner | ci-speed |
| Deploy controls | Protected environments, `resource_group`, manual jobs with protected-environment approvals — in GitLab primitives, not script logic | Visible and enforced for every pipeline | ci-deploy |
| Credentials | **OIDC first** (`id_tokens:` exchanged for short-lived cloud credentials — GCP Workload Identity Federation, AWS); **then OpenBao/Vault via the `secrets:` keyword** (JWT auth bound to project, protected ref and environment); masked + protected CI/CD variables only for what neither can serve | No long-lived cloud keys in GitLab; every credential is short-lived and scoped to the job's claims | ci-deploy |

### Releases and versioning

| Decision | Pick | Why | Chapter |
|---|---|---|---|
| Versioning | **SemVer** from Conventional Commits; `0.x` bumps minor for breaking changes | Machine-computable, and consumers know what a bump means | merge-policy |
| Release trigger | A job on `main` computes the next version and pushes an **annotated tag `vX.Y.Z`**; the tag pipeline builds, publishes and creates the GitLab release | Tagging is visible in CI; the tag is the release record | merge-policy, ci-deploy |
| Release tool | **git-cliff** | One static binary, reads Conventional Commits, `--bumped-version` without side effects. **Tiebreaker for semantic-release:** you want the whole flow in one opinionated tool and already run Node | merge-policy |
| Changelog | Release notes **in the tag message and the GitLab release**, not a committed `CHANGELOG.md` | Pushing a changelog commit to `main` retriggers the release job | merge-policy |
| Release bot identity | Project access token or deploy key, masked + protected variable | `CI_JOB_TOKEN` can't push by default; a bot keeps pushes attributable and revocable | merge-policy |
| Chart / image versions | Chart `version` bumped on every change (`ct` enforces); images and charts pinned by **digest** downstream | A re-pushed tag is a different artefact with the same name | infra-lint |

### Positions worth arguing about

These are opinions, not consensus. Each has its reason so you can overrule it deliberately.

| Position | Reason |
|---|---|
| **Don't pin apt/apk package versions in Dockerfiles. Pin the base image by digest.** | Pinned distro packages vanish from the mirror within weeks and break the build; a digest-pinned base plus Renovate gives reproducibility *and* security updates |
| **`allow_failure: true` on a lint job is worse than deleting it.** | A yellow job nobody reads, plus a false sense that the check exists |
| **Lint the MR title, not the commits.** | With squash-required, branch commits are thrown away; policing `wip` messages is pure friction |
| **Changed-files linting is a transition tool, not a policy.** | It stops growth but never shrinks the backlog, and misses findings in untouched files |
| **Type checkers never run in changed-files mode, and never in the pre-commit hook on a big repo.** | Whole-program by definition; slow enough to train `--no-verify` |
| **The pre-commit hook is a convenience; CI is the contract.** | Everything the hook checks, CI checks again. A hook-only check is a suggestion |
| **Run lint jobs on the default branch even though the MR already passed.** | The Code Quality and test widgets need a base report to diff against |
| **Fast-forward + squash over semi-linear.** | Straight history makes bisect, revert and changelog generation trivial; the per-commit history it discards is usually noise. Close call — see the tiebreaker above |
| **No `develop` branch.** | It's a second integration point with no capability that trunk + release branches lack |
| **Free-tier SAST isn't a gate.** | It runs and reports to an artefact; nothing fails and nothing shows in the MR. Gate with your own jobs |
| **Warnings are not a severity.** | Either a rule fails the build or it's off. `warn` is only for an active ratchet with `--max-warnings` |
| **Release notes live in the tag, not a committed file.** | Committing from CI to `main` loops the pipeline and races human merges |

### One-way doors

Everything else in this guide is reversible in an afternoon. These aren't — or they are, but only at a cost you'll notice.

| Door | What it costs to walk back through | Chapter |
|---|---|---|
| **Force-pushing / rewriting a protected branch** | Rewrites the SHAs everyone has based work on, orphans MR diffs, breaks `cherry-pick -x` references and deployment records. Nothing in GitLab undoes it. For a leaked secret: **rotate first**; rewriting is optional cleanup | merge-policy |
| **A pushed secret** | Public to everyone with read access from the push onward — forks, clones, job logs, MR diffs. The cost is a rotation and an audit of what the credential reached | hooks |
| **Switching merge methods on a busy repo** | Merge commit → fast-forward makes every open MR "behind" at once and forces a rebase of each, mid-review; stacked MRs have to be restacked. The history already on `main` keeps its old shape forever, so tooling that assumes linear history (`git log` without `--first-parent`, changelog generators) has to handle both. Announce it, drain the MR queue first, and enable merge trains the same day | merge-policy |
| **Making a check required without a bypass path** | The day the check is broken (flaky test, a scanner's upstream down, a new linter version with a false positive), **every merge on the repo stops**, including the fix for the check. Before making anything required, decide who can merge when it's broken, how (a Maintainer temporarily relaxing the setting, which is audit-logged on Premium, or a scoped `allow_failure: exit_codes`), and how the relaxation gets reverted | philosophy, ci-reporting, merge-policy |
| **Releasing a breaking change of a shared component as a minor version** | Every consumer on `@1` picks it up on their next pipeline, without doing anything. Removing or renaming an input is a major bump, always | ci-reuse |
| **Pushing a chart or image version that already exists** | In a registry that refuses overwrites, that version number is burnt; in one that allows them, two artefacts share a name and digests diverge silently. `ct lint --check-version-increment` prevents it | infra-lint |
| **Enabling `CI_DEBUG_TRACE`** | Prints every variable, including masked and protected ones, into the job log. You can't un-leak what a reader already saw | ci-debug |
| **A privileged runner shared across projects** | Root on the node for anyone who can push a branch; you can't un-leak what a malicious job read | ci-speed |
| **Adopting gitflow (or keeping it)** | Switching the branch model takes a day; unlearning long-lived branches and release-day heroics takes quarters | branching |
| **Repo-wide reformat** | Reversible in git, but it touches every line's blame. Do it once, in one MR, and add the SHA to `.git-blame-ignore-revs` | philosophy |

### If you're setting up a repo today, in order

1. **The branching chapter — branch model.** `main` as default branch, trunk-based, branch naming convention. No `develop`.
2. **The merge-policy chapter — merge settings, before the first MR.** Fast-forward + squash required, pipelines must succeed, threads resolved, skipped-pipelines-successful off. Protect `main` (no one pushes, no force push) and `v*` tags. Approval settings. Set these at group level if you can.
3. **The infra-lint chapter — `.editorconfig`**, committed first, so every later file is born consistent.
4. **The languages chapter — per-language config.** `pyproject.toml` ruff + mypy, or `eslint.config.mjs` + Prettier + `tsconfig.json`, or `.golangci.yml` v2, plus `.shellcheckrc`. Pin every tool in the lockfile.
5. **The infra-lint chapter — infra lint config.** `.hadolint.yaml`, `.yamllint.yaml`, `.markdownlint-cli2.jsonc`, `.kube-linter.yaml`, `.tflint.hcl`, `ct.yaml` — whichever apply.
6. **The hooks chapter — `.pre-commit-config.yaml`** with `default_install_hook_types`, revs frozen to SHAs, gitleaks, and the commitizen `commit-msg` hook. `pre-commit run --all-files` until clean.
7. **The ci-anatomy chapter — `.gitlab-ci.yml` skeleton.** `workflow:rules` with the duplicate-pipeline pattern, `stages`, a `default:` block with `interruptible: true`.
8. **The ci-reporting chapter — lint jobs.** A `.lint` template (`needs: []`, `artifacts:when: always`, MR + default-branch rules), one job per ecosystem, Code Quality reports, a gitleaks MR-range job, the MR-title check. Verify with `glab ci lint --dry-run --ref main --include-jobs`.
9. **The ci-speed chapter — make it fast.** Lockfile-keyed caches, analysis caches with fallback keys, `pull` in MRs. Measure the critical path.
10. **The merge-policy chapter — release job.** git-cliff, annotated `vX.Y.Z` tags from `main`, GitLab release from the tag pipeline.
11. **The ci-reuse chapter — only when a second repo needs the same jobs.** Extract them into a CI/CD component with typed inputs; consume `@1`.
12. **The ci-deploy chapter — deploys.** Protected environments, `resource_group`, `id_tokens` + OIDC to the cloud, OpenBao/Vault via `secrets:` for everything else — no static cloud keys.
13. **Renovate** — enable the `pre-commit` manager alongside the language managers, so linter bumps arrive as MRs whose pipelines show exactly what changed.

For a **legacy repo**, insert the philosophy chapter's ratchet between steps 4 and 6: formatter first in its own MR, then a small high-value rule set fixed to zero, then the wider set with a baseline and a scheduled full run.

### Checklist

- [ ] One formatter and one linter per language, each pinned once, invoked identically by editor, hook and CI.
- [ ] Every enabled rule is an error; every suppression names its rule and says why.
- [ ] The hook runs in under ~3 s; type checks are at `pre-push` or CI only.
- [ ] Every hook check is re-run in CI on all files (or with a scheduled full run behind changed-files mode).
- [ ] gitleaks runs in the hook, on the MR range in CI with `--redact`, and once over full history.
- [ ] No lint job has `|| true` or `allow_failure: true`; every lint job uploads a report with `when: always`.
- [ ] Lint jobs run on the default branch too.
- [ ] `workflow:rules` prevents duplicate pipelines; every MR gets a pipeline.
- [ ] `main` and `v*` are protected; nobody can push to `main`; force push is off.
- [ ] Fast-forward + squash required (or semi-linear, deliberately); merge trains once the repo is busy.
- [ ] The MR title is linted as a Conventional Commit.
- [ ] Releases are tags created by CI from `main`, with notes in the tag and the GitLab release.
- [ ] Every required check has a written bypass procedure.


---


<a id="01-what-linting-is-for"></a>

## 01 · What linting is for

*A lint gate is a contract about what can reach main, and its value is its signal-to-noise ratio. Every rule you add either buys a real defect class or teaches people to ignore the gate.*

### Five tools, five jobs

People say "the linter" for five different things. They have different failure modes, different costs, and belong in different places in the loop. Mixing them up is how a repo ends up with a 14-minute "lint" stage that nobody trusts.

| Tool class | Question it answers | Output | Can it auto-fix? | Examples |
|---|---|---|---|---|
| **Formatter** | "Is this laid out the canonical way?" | A rewritten file, or a diff | Always — that's the point | `ruff format`, Prettier, `gofmt`, `shfmt`, `terraform fmt` |
| **Linter** | "Is this a known-bad pattern?" | Findings with rule codes | Some rules | ruff, ESLint, golangci-lint, shellcheck, hadolint, yamllint |
| **Type checker** | "Do the types line up across the whole program?" | Errors, no fixes | No | mypy, pyright, `tsc --noEmit`, the Go compiler |
| **Static analysis (deep)** | "Is there a bug reachable through data flow?" | Findings, often with a trace | Rarely | staticcheck, gosec, Semgrep, CodeQL, GitLab SAST |
| **Security / supply-chain scanning** | "Is there a secret, a vulnerable dependency, a bad config?" | Findings keyed to CVEs / rule IDs | No | gitleaks, Trivy, checkov, GitLab Secret Detection, Dependency Scanning |

The practical consequences:

- **Formatters are not negotiable and not reviewable.** A formatter has no findings to triage — it either ran or it didn't. So it belongs in the pre-commit hook (where it silently fixes) and in CI as a `--check` (where it fails if someone bypassed the hook). Never put formatting in code review. A reviewer commenting on whitespace is a reviewer not reading the logic.
- **Linters produce findings, so they need a policy.** Which rules, which severity fails the build, what to do with the backlog. That policy is most of this chapter.
- **Type checkers are whole-program.** They cannot be meaningfully run on "just the changed files" — a change in `models.py` breaks a caller in `views.py` that you did not touch. Run them on the whole project, always, and make them fast with caching instead.
- **Deep static analysis is slow and noisy.** It belongs in CI only, often only on MR and default-branch pipelines, and its findings need triage rather than a hard fail on day one.
- **Secret scanning is the one check with an irreversible failure.** A leaked credential that reaches a pushed commit must be rotated; there is no "fix it in the next commit". That is why secret scanning runs **before** the push (hook) and **again** in CI (the gate), and why its false-positive handling is designed so carefully (the hooks chapter).

> **Note.** The Go compiler is a type checker you already run. For Go, "type checking" is `go build ./...` and `go vet ./...`; golangci-lint runs both implicitly because its linters load type information.

#### Where each class runs

| Class | Editor | Pre-commit hook | CI on MR | CI on default branch | Nightly / scheduled |
|---|---|---|---|---|---|
| Formatter | on save | fix | `--check` | `--check` | — |
| Linter (fast: ruff, shellcheck, hadolint) | live | yes | yes | yes | — |
| Linter (slow: golangci-lint full set, ESLint typed rules) | live | changed files only, or skip | yes | yes | — |
| Type checker | live (LSP) | optional | yes | yes | — |
| Deep static analysis | — | — | yes | yes | full scan |
| Secret scan | — | staged diff | MR diff | yes | full history |
| Dependency / image CVE scan | — | — | yes | yes | yes — CVEs appear without code changes |

The last row is the one people forget: **a dependency scan's result changes when the world changes, not when your code does.** A pipeline that passed on Monday can have a new critical CVE on Wednesday with no commits in between. Schedule it; do not rely on push-triggered pipelines alone.

### Two loops, one contract

There are two feedback loops and they have different jobs. Confusing them produces either a hook so slow people bypass it or a CI gate so lax it catches nothing.

```text
   FAST LOOP (seconds, advisory, on the developer's machine)
   ┌──────────────────────────────────────────────────────────────┐
   │                                                              │
   │   edit ──▶ editor/LSP ──▶ save ──▶ formatter ──▶ git commit  │
   │    ▲        (live           (fix)       │                    │
   │    │        squiggles)                  ▼                    │
   │    │                           pre-commit hook               │
   │    │                           (staged files only:           │
   │    │                            format, lint, secrets,       │
   │    └────── fix ◀── fail ◀───── commit-msg check)             │
   │                                         │ pass               │
   └─────────────────────────────────────────┼────────────────────┘
                                             ▼
                                         git push     ◀── --no-verify
                                             │            skips the
   AUTHORITATIVE GATE (minutes, required, on a runner)    whole fast
   ┌─────────────────────────────────────────┼────────────loop─────┐
   │                                         ▼                     │
   │   MR pipeline: same tools, same pinned versions, ALL files    │
   │   + type check + tests + SAST + secret detection + CVE scan   │
   │                                         │                     │
   │         fail ──▶ MR blocked ("Pipelines must succeed")        │
   │         pass ──▶ approvals ──▶ merge (semi-linear / FF)       │
   │                                         │                     │
   │   default-branch pipeline: re-run, publish baseline reports   │
   │   (Code Quality base for the next MR's widget diff)           │
   └───────────────────────────────────────────────────────────────┘
```

The rules that fall out of the diagram:

1. **The hook is a convenience, the pipeline is the contract.** Anyone can `git commit --no-verify`, delete `.git/hooks`, or never run `pre-commit install`. So **everything the hook checks, CI checks again**, on all files. If a check exists only in the hook, it is a suggestion.
2. **The hook must be fast enough to never be worth bypassing.** Budget: under ~3 seconds for a typical commit. Anything slower moves to `pre-push` or CI only. Once people learn `--no-verify`, they use it for everything, and your secret scan goes with the formatter.
3. **CI must never be *stricter by surprise*.** If CI fails on something the hook passed, the developer loses trust in both. The cure is identical versions and identical config (next section), not a looser CI.
4. **The default-branch pipeline is not redundant.** It re-validates the merged result (which is not what the MR pipeline tested, unless you use semi-linear/fast-forward merges or merge trains — the merge-policy chapter) and it produces the baseline report that GitLab's MR widgets diff against.

### Same versions everywhere

A linter version bump changes the rule set. Ruff 0.16 changed the default rule set from 59 rules to 413 (read in the ruff changelog). ESLint majors change `recommended`. golangci-lint minors add checks to existing linters. If the developer's hook runs ruff 0.15 and CI runs "latest", a green commit becomes a red pipeline for reasons unrelated to the change.

**Pin every linter to an exact version, in one place per ecosystem, and make both loops read it.**

| Ecosystem | Where the pin lives | Hook reads it via | CI reads it via |
|---|---|---|---|
| Python | `pyproject.toml` dev group + `uv.lock` | `uv run ruff` (or pre-commit `rev:` that matches) | `uv sync --frozen && uv run ruff` |
| JS/TS | `package.json` exact version + lockfile | `npx eslint` from `node_modules` | `npm ci && npx eslint` |
| Go | `go.mod` `tool` directive (Go 1.24+) or a pinned binary | `go tool golangci-lint` | same, or pinned image tag |
| Mixed / binaries | `.pre-commit-config.yaml` `rev:` frozen to a SHA | pre-commit | `pre-commit run --all-files` in CI |
| Container tools | image **digest** in `.gitlab-ci.yml` | `podman run IMAGE@sha256:…` | `image: IMAGE@sha256:…` |

> **Gotcha.** The classic drift: `.pre-commit-config.yaml` pins `ruff-pre-commit` at `v0.15.0` while `pyproject.toml` pins `ruff==0.16.8`, and CI runs `uv run ruff`. Now the hook and CI disagree. **Pick one source of truth per tool.** Either CI runs `pre-commit run --all-files` (so the hook's pin is authoritative) or the hook uses `language: system` / `repo: local` and calls `uv run ruff` (so the lockfile is authoritative). The hooks chapter shows both.

> **Version-sensitive.** `go tool` with the `tool` directive in `go.mod` needs Go 1.24 or later. golangci-lint's own docs discourage `go install`/`go tool` builds (they compile with your Go version and your dependency graph, which can differ from the release binary); the release binary or the official image pinned by digest is the safer default for CI.

Let Renovate (or Dependabot) raise the version bumps as MRs. A linter bump is then a reviewable change whose pipeline shows exactly which new findings it introduces — rather than an ambush on whoever pushes next.

### Zero warnings, not "few warnings"

**The only stable number of warnings is zero.** A linter that reports 40 warnings and exits 0 is a linter nobody reads: warning 41, the one that matters, is invisible in the noise. Every mature setup converges on the same shape:

- Every enabled rule is an **error**. If a rule isn't worth failing the build for, disable it — don't demote it to a warning.
- Exceptions are **explicit, local, and justified**: an inline suppression with the rule code and a reason, never a bare `# noqa` or `// eslint-disable-next-line` without a rule name.
- Suppressions are themselves linted: ruff's `RUF100` flags unused `noqa` comments; ESLint's `linterOptions.reportUnusedDisableDirectives` flags unused disables; golangci-lint's `nolintlint` requires a named linter and an explanation.

```python
# Good: specific rule, reason stated
subprocess.run(cmd, shell=True)  # noqa: S602 -- cmd is a constant from settings, not user input

# Bad: silences everything on the line, forever, with no reason
subprocess.run(cmd, shell=True)  # noqa
```

```go
//nolint:gosec // G204: args are validated against an allowlist in parseArgs
cmd := exec.Command(bin, args...)
```

> **Note.** ESLint's `"warn"` severity has one legitimate use: rules you're *migrating toward* during a ratchet, with `--max-warnings` pinned to the current count so the number can only go down. Outside a ratchet, `"warn"` is where rules go to be ignored.

### Ratcheting a legacy codebase

You inherit a 200k-line repo. Turning on the rule set you want produces 11,000 findings. You cannot fix them in one MR and you cannot leave the gate off. The answer is a **ratchet**: new code meets the full standard today; old code is grandfathered and the grandfathered set can only shrink.

There are four mechanisms, from coarsest to finest. Use them in this order of preference.

#### 1. Per-file ignores (coarse, honest)

Exclude whole rules from whole paths, in config, where everyone can see the debt.

```toml
# pyproject.toml
[tool.ruff.lint.per-file-ignores]
"legacy/billing/**" = ["ANN", "D", "PLR"]   # TODO(PLAT-412): remove as modules are rewritten
"tests/**" = ["S101", "PLR2004"]             # asserts and magic numbers are fine in tests
```

This is the right tool when the debt is **concentrated** (one legacy package) and the rule is **low-risk**. It shows up in code review every time someone touches the list, which is exactly what you want.

#### 2. Baseline files (fine-grained, automatic)

Record every current finding in a file; the tool reports only findings **not in the baseline**. New violations fail; old ones are tolerated until fixed, then drop out.

| Tool | Baseline mechanism |
|---|---|
| ruff | `ruff check --add-noqa` writes `# noqa: CODE` onto every current violation. Crude but effective; `RUF100` later removes the ones that are fixed |
| mypy | No native baseline — use per-module `[[tool.mypy.overrides]]` with relaxed flags, tightening module by module |
| pyright / basedpyright | basedpyright has `--writebaseline` (`.basedpyright/baseline.json`) |
| ESLint | ESLint 9.24+ bulk suppressions: `eslint --suppress-all` writes `eslint-suppressions.json`; `--prune-suppressions` drops fixed entries |
| golangci-lint | `issues.new-from-merge-base: main` — only report issues introduced since the merge base (no file needed) |
| gitleaks | `--baseline-path gitleaks-baseline.json` — a previous JSON report |
| shellcheck | No baseline; use per-directory `.shellcheckrc` `disable=` lists |
| hadolint | No baseline; `ignored:` in `.hadolint.yaml` or inline `# hadolint ignore=DL3008` |

> **Version-sensitive.** ESLint bulk suppressions arrived in ESLint 9.24. golangci-lint's `new-from-merge-base` is a v2 option. Check your versions before designing around either.

> **Gotcha.** Baselines keyed by line number rot on every edit above the finding, so a harmless refactor "introduces" 30 findings. Prefer tools that key by content hash or rule+file (ESLint's suppressions count per rule per file; gitleaks fingerprints include the commit). Inline `noqa` comments move with the code and don't have this problem — that's the argument for ruff's `--add-noqa` over an external file.

#### 3. Only-changed-files / only-new-issues

Lint only what the MR touched, or report only issues on changed lines.

- golangci-lint: `--new-from-merge-base=origin/main` (issues on changed lines) or add `--whole-files` (any issue in a changed file).
- pre-commit: `pre-commit run --from-ref "$CI_MERGE_REQUEST_DIFF_BASE_SHA" --to-ref HEAD`.
- ruff / ESLint: pass the file list from `git diff --name-only --diff-filter=ACMR`.

This is attractive and dangerous. **It never shrinks the backlog, it only stops growth.** And it has a hole: a change in file A can create a finding in unchanged file B (a removed export, a renamed type), and changed-files mode will never report it. So:

- **Never use changed-files mode for type checkers** — they're whole-program by definition.
- Use it for slow linters where whole-repo runs are genuinely too slow, and pair it with a **scheduled full run** on the default branch that fails loudly.
- "Whole files" beats "changed lines": touching a file means you own its findings. That turns every MR into a small cleanup, which is the ratchet actually ratcheting.

#### 4. Warning budget (`--max-warnings`)

```bash
eslint . --max-warnings 212
```

Record today's count in CI config; lower it in every MR that fixes some. It works, but it is the weakest ratchet — **it tolerates swapping an old warning for a new one** — so treat it as a transition tool for a quarter, not a policy.

#### The ratchet playbook, in order

1. Turn on the **formatter** first, repo-wide, in one dedicated MR with nothing else in it. Add the commit SHA to `.git-blame-ignore-revs` so `git blame` skips it:

   ```bash
   git config blame.ignoreRevsFile .git-blame-ignore-revs
   ```

   GitLab's blame view honours `.git-blame-ignore-revs` too (GitLab 17.10, GA in 17.11), but only after each viewer ticks **Blame preferences > Ignore specific revisions**; it is not on by default.
2. Turn on a **small, high-value rule set** (ruff `E`, `F`, `B`, `S`; ESLint `recommended`; golangci-lint `standard`) and fix everything. These rules find real bugs, so the fixes are worth it.
3. Add the **wider rule set** with a baseline (`--add-noqa`, `--suppress-all`, `new-from-merge-base`).
4. Add a **scheduled pipeline** that reports the remaining baseline size as a metric. Debt you don't measure is debt you've accepted.
5. Burn down per-file ignores as modules are touched. Every removed line in the ignore list is visible progress in review.

### The cost of noisy gates

Every false positive has a price, and it compounds.

| Symptom | What it's actually costing you |
|---|---|
| Reviewers approve MRs with a red lint job "because it's just lint" | The gate is advisory in practice; your required-check setting is fiction |
| `# noqa` / `eslint-disable` without rule codes spreading through the code | Each blanket suppression silences future real findings on that line |
| `allow_failure: true` on the lint job | Nobody reads a yellow job. **This is disabling the gate with extra steps** |
| `|| true` at the end of a lint command | The job reports success no matter what the tool found. Worse than no job — it's a lie in the MR widget |
| Developers habitually `git commit --no-verify` | Your pre-commit secret scan is gone too |
| A 10-minute lint stage | Developers context-switch away; feedback that arrives after the switch is feedback that costs a reload |

The discipline that keeps a gate respected:

- **Every rule must be able to name a defect class it prevents.** "Style consistency" is the formatter's job. If a lint rule is purely stylistic and the formatter doesn't cover it, it probably shouldn't fail builds.
- **Fail on severity, report the rest.** SAST and CVE scanners produce findings on a spectrum. Gate on `HIGH,CRITICAL` with a fix available (`trivy --severity HIGH,CRITICAL --ignore-unfixed`); publish everything else to the MR widget as information.
- **Budget the time.** Lint + format + type check for an MR should finish in under ~3 minutes on a warm cache. Parallelise lint jobs with `needs: []` so they start immediately instead of waiting for a stage (the ci-reporting chapter).
- **Make the failure message actionable.** A lint job's last lines should tell the developer the exact command to reproduce locally. `ruff check --fix` in the job log beats a wall of findings.

```yaml
lint:python:
  script:
    - uv run ruff check --output-format=full .
  after_script:
    - |
      if [ "$CI_JOB_STATUS" = "failed" ]; then
        echo "Reproduce locally: uv run ruff check --fix . && uv run ruff format ."
      fi
```

> **Note.** `after_script` runs in a separate shell from `script`, so it can't see variables set in `script`, but it does get `CI_JOB_STATUS`. It runs even when `script` fails, which is exactly why it's the place for the "how to reproduce" hint.

### What belongs in the gate

A rule of thumb for deciding whether a check is required (blocks merge) or informational (reported, not blocking):

| Required | Informational |
|---|---|
| Formatter `--check` | Complexity metrics (cyclomatic, cognitive) |
| Linters at the agreed rule set | Coverage deltas |
| Type checker | SAST findings below HIGH |
| Unit tests | Dependency CVEs with no fix available |
| Secret detection | Licence scan (until policy exists) |
| CI YAML validation | Deprecation warnings from the toolchain |
| CVEs HIGH/CRITICAL with a fix | Documentation lint (markdownlint) — *close call* |

Markdown lint is the close call: on a docs-heavy repo it is required; on a service repo it is noise. The tiebreaker is whether rendered docs are a product your users read.

### Traps

- **Hook-only checks.** Anything not re-run in CI is optional. Especially secret scanning.
- **Unpinned linter versions.** The pipeline breaks on a Tuesday for a change nobody made. Pin, and let Renovate propose bumps.
- **Two sources of truth for one version.** `pre-commit` `rev:` and the lockfile drift. Choose one.
- **Changed-files mode for type checkers.** Type errors land in files you didn't touch.
- **Changed-files mode without a scheduled full run.** Findings in untouched files accumulate unseen.
- **`allow_failure: true` or `|| true` on a gate.** Both mean "never fails". Delete the job instead; at least that's honest.
- **Warnings that don't fail anything.** Zero is the only stable count.
- **Reformatting the repo inside a feature MR.** Unreviewable diff, poisoned blame. Separate MR, add to `.git-blame-ignore-revs`.
- **Bare suppressions.** `# noqa` without a code, `//nolint` without a linter, `eslint-disable` without a rule. Lint them out (`RUF100`, `nolintlint`, `reportUnusedDisableDirectives`).
- **Only push-triggered CVE scans.** New CVEs arrive without commits; schedule a nightly scan.


---


<a id="02-per-language-setup"></a>

## 02 · Per-language setup

*One formatter and one linter per language, configured once in the file the ecosystem already reads, pinned in the lockfile, and invoked identically by the editor, the hook and CI.*

### The picks

| Language | Formatter | Linter | Type check | Config lives in |
|---|---|---|---|---|
| Python | **`ruff format`** | **`ruff check`** | **mypy `strict`** — *close call* vs pyright | `pyproject.toml` |
| JS / TS | **Prettier** | **ESLint 10** flat config + typescript-eslint | **`tsc --noEmit`** | `eslint.config.mjs`, `.prettierrc.json`, `tsconfig.json` |
| JS / TS (alt) | Biome | Biome | `tsc --noEmit` | `biome.json` — *close call* |
| Go | **gofmt + goimports** (via golangci-lint `fmt`) | **golangci-lint v2** | the compiler + `go vet` | `.golangci.yml` |
| Shell | **shfmt** | **shellcheck** | — | `.editorconfig`, `.shellcheckrc` |

Versions current at time of writing (read from the GitHub releases API, September 2026): ruff 0.16.8, mypy 2.3.1, pyright 1.1.414, ESLint 10.11.0, typescript-eslint 8.70.1, Prettier 3.9.9, Biome 2.5.14, golangci-lint 2.13.2, shellcheck 0.11.0 (verified locally), shfmt 3.14.1 (3.13.1 installed locally).

> **Version-sensitive.** Three of these changed shape recently. **Ruff 0.16** expanded the default rule set from 59 to 413 rules. **ESLint 10** removed `.eslintrc` entirely — flat config only. **golangci-lint v2** rewrote the config schema (`version: "2"`, `linters.default`, a separate `formatters:` block). Any blog post older than 2025 is probably showing you the old shape.

### Python

#### ruff: one tool for lint, format, imports

Ruff replaces flake8, isort, pyupgrade, pydocstyle, bandit (partially), and black. One binary, one config block, Rust-fast. There's no longer a serious argument for the old stack in a new repo.

```bash
uv add --dev ruff==0.16.8 mypy==2.3.1
uv run ruff check .                  # lint
uv run ruff check --fix .            # lint + safe autofixes
uv run ruff format .                 # format in place
uv run ruff format --check --diff .  # CI: fail if unformatted, show the diff
uv run ruff rule S602                # explain a rule
uv run ruff check --statistics .     # count findings per rule: triage a backlog
uv run ruff check --add-noqa .       # baseline: stamp noqa on every current finding
```

#### pyproject.toml, complete

This is an opinionated, production-ready rule selection. **Use `select`, not `extend-select`**: with ruff 0.16's much larger default set, `select` makes your rule set explicit and immune to future default changes.

```toml
[project]
name = "service"
requires-python = ">=3.12"

[dependency-groups]
dev = [
  "ruff==0.16.8",
  "mypy==2.3.1",
  "pytest>=8",
]

# ---------------------------------------------------------------- ruff
[tool.ruff]
# target-version is inferred from requires-python; set it only if they differ.
line-length = 100
extend-exclude = ["**/migrations/**", "**/*_pb2.py", "**/*_pb2.pyi"]
# Respect the exclude list even when files are passed explicitly (hooks, CI changed-files mode).
force-exclude = true

[tool.ruff.lint]
select = [
  "F",     # pyflakes: undefined names, unused imports — real bugs
  "E", "W",# pycodestyle errors/warnings not covered by the formatter
  "I",     # isort
  "B",     # flake8-bugbear: mutable defaults, loop-variable capture, etc.
  "UP",    # pyupgrade: modern syntax for the target version
  "S",     # flake8-bandit: security
  "SIM",   # flake8-simplify
  "C4",    # comprehensions
  "PTH",   # use pathlib
  "DTZ",   # naive datetimes
  "T20",   # stray print()
  "PT",    # pytest style
  "RET",   # return consistency
  "ARG",   # unused arguments
  "BLE",   # blind except Exception
  "TC",    # typing-only imports behind TYPE_CHECKING
  "N",     # pep8-naming
  "PL",    # pylint subset
  "PERF",  # performance anti-patterns
  "LOG",   # logging misuse
  "G",     # logging format strings
  "ERA",   # commented-out code
  "RUF",   # ruff-specific, including RUF100 (unused noqa)
]
ignore = [
  "E501",    # line length: the formatter owns this
  "PLR0913", # too many arguments: noisy on constructors and handlers
  "PLR2004", # magic value comparison: noisy outside of tests too
  "S101",    # assert: handled per-file below
  "RET504",  # unnecessary assignment before return: hurts debuggability
]
# Never auto-fix these even with --fix: removing "unused" code is a human decision.
unfixable = ["F401", "F841", "ERA001"]

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["S101", "S105", "S106", "PLR2004", "ARG"]
"**/__init__.py" = ["F401"]
"scripts/**" = ["T20"]

[tool.ruff.lint.flake8-tidy-imports]
ban-relative-imports = "all"

[tool.ruff.lint.flake8-type-checking]
runtime-evaluated-base-classes = ["pydantic.BaseModel"]

[tool.ruff.lint.pylint]
max-args = 8

[tool.ruff.format]
docstring-code-format = true
quote-style = "double"

# ---------------------------------------------------------------- mypy
[tool.mypy]
python_version = "3.12"
strict = true
warn_unreachable = true
enable_error_code = [
  "ignore-without-code",   # bare "# type: ignore" is an error
  "redundant-expr",
  "truthy-bool",
  "possibly-undefined",
]
plugins = ["pydantic.mypy"]
files = ["src", "tests"]

[[tool.mypy.overrides]]
module = "tests.*"
disallow_untyped_defs = false        # fixtures and test functions needn't be annotated

[[tool.mypy.overrides]]
module = ["legacy.*"]
# Ratchet: tighten one flag at a time, delete this block when empty.
disallow_untyped_defs = false
disallow_any_generics = false

[[tool.mypy.overrides]]
module = ["some_untyped_vendor_lib.*"]
ignore_missing_imports = true
```

> **Gotcha.** Some lint rules fight the formatter: `W191`, `E111`, `E114`, `E117`, `D206`, `D300`, `Q000`–`Q003`, `COM812`, `COM819`, `ISC002`. Ruff warns at runtime if you enable one alongside `ruff format`. The selection above avoids them; if you add `COM` or `Q`, add those codes to `ignore`.

> **Gotcha.** The flake8-type-checking prefix was renamed from `TCH` to `TC` in ruff 0.8. Old configs with `TCH` still work via redirect but print a deprecation warning — rename it.

> **Note.** `force-exclude = true` matters the moment a hook or CI job passes explicit filenames: without it, `ruff check path/to/migrations/0001.py` lints the file even though it's excluded. The ruff-pre-commit hooks pass `--force-exclude` for you; your own CI scripts must not forget it.

Inline suppressions — always with a code, and ruff 0.16 adds a `ruff: ignore` spelling alongside `noqa`:

```python
import pickle  # noqa: S403 -- trusted internal cache, never user data

def handler(event, context):  # noqa: ARG001 -- signature fixed by the Lambda runtime
    ...
```

#### mypy vs pyright: close call

**Default: mypy `strict = true`.** Reason: plugins. Django (`django-stubs`), pydantic, and SQLAlchemy ship mypy plugins that understand their metaprogramming; without them you drown in false positives on models.

**Tiebreaker: pick pyright if you use no plugin-dependent library.** It's several times faster, its inference is stronger on unannotated code, and it's the same engine as Pylance in VS Code — so the editor and CI agree exactly.

pyright strict config, if you take that branch:

```toml
[tool.pyright]
include = ["src", "tests"]
exclude = ["**/migrations", "**/__pycache__"]
pythonVersion = "3.12"
typeCheckingMode = "strict"
reportMissingTypeStubs = false            # too noisy with untyped third-party libs
reportUnnecessaryTypeIgnoreComment = "error"
reportImplicitOverride = "error"

[[tool.pyright.executionEnvironments]]
root = "tests"
reportPrivateUsage = false
```

```bash
uv run mypy                      # uses files= from pyproject
uv run mypy --install-types --non-interactive   # fetch missing stub packages (review what it installs)
npx pyright@1.1.414              # or: uv run basedpyright (a pip-installable fork with baseline support)
```

> **Version-sensitive.** mypy 2.0 changed defaults: `--local-partial-types` and `--strict-bytes` are now on, `--allow-redefinition` adopted the old `--allow-redefinition-new` semantics, Python 3.9 targets are dropped, and the cache moved to a binary/SQLite format (so a `.mypy_cache` restored from a 1.x job is useless — key your CI cache on the mypy version). Upgrading from 1.x will surface new errors; do it in its own MR.

> **Note.** Astral's `ty` type checker is the one to watch — same team as ruff and uv. Check its release status before adopting it as a gate; this guide doesn't recommend it yet.

### JavaScript and TypeScript

#### ESLint 10 flat config + Prettier (default)

**Default: ESLint + typescript-eslint for lint, Prettier for format.** Reason: typescript-eslint's type-aware rules (`no-floating-promises`, `no-misused-promises`, `await-thenable`, `no-unnecessary-condition`) catch real async bugs that syntax-only linters can't, and the plugin ecosystem (React, import, Vitest, Playwright) is unmatched.

```bash
npm install --save-dev --save-exact \
  eslint@10 @eslint/js typescript-eslint globals \
  prettier eslint-config-prettier typescript
```

`eslint.config.mjs` — complete, strict, type-aware:

```javascript
// eslint.config.mjs
import js from "@eslint/js";
import { defineConfig, globalIgnores } from "eslint/config";
import tseslint from "typescript-eslint";
import eslintConfigPrettier from "eslint-config-prettier/flat";
import globals from "globals";

export default defineConfig([
  globalIgnores(["dist/", "build/", "coverage/", "**/*.gen.ts", "**/generated/**"]),

  {
    name: "project/linter-options",
    linterOptions: {
      reportUnusedDisableDirectives: "error",
    },
  },

  js.configs.recommended,
  tseslint.configs.strictTypeChecked,
  tseslint.configs.stylisticTypeChecked,

  {
    name: "project/typed",
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
      globals: { ...globals.node },
    },
    rules: {
      "@typescript-eslint/no-floating-promises": "error",
      "@typescript-eslint/no-misused-promises": "error",
      "@typescript-eslint/consistent-type-imports": "error",
      "@typescript-eslint/switch-exhaustiveness-check": "error",
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
      "no-console": ["error", { allow: ["warn", "error"] }],
    },
  },

  {
    name: "project/tests",
    files: ["**/*.test.ts", "**/*.spec.ts"],
    rules: {
      "@typescript-eslint/no-non-null-assertion": "off",
      "@typescript-eslint/no-unsafe-assignment": "off",
    },
  },

  {
    name: "project/plain-js",
    files: ["**/*.{js,mjs,cjs}"],
    extends: [tseslint.configs.disableTypeChecked],
  },

  // Last: turn off every stylistic rule that Prettier owns.
  eslintConfigPrettier,
]);
```

What each piece is for:

| Piece | Why |
|---|---|
| `defineConfig` / `globalIgnores` from `eslint/config` | Official helpers; `defineConfig` flattens nested arrays (the typescript-eslint presets are arrays) and gives editor type hints |
| `globalIgnores([...])` | A config object with *only* `ignores` is global; `globalIgnores` makes that explicit so nobody adds a `rules` key and silently turns it into a local ignore |
| `reportUnusedDisableDirectives: "error"` | Stale `eslint-disable` comments become errors — the ESLint equivalent of `RUF100` |
| `strictTypeChecked` | The strict type-aware preset. Use `recommendedTypeChecked` on a legacy codebase and ratchet up |
| `projectService: true` | The modern way to enable type information — reuses the TS language service, handles multiple tsconfigs, no `project:` globs |
| `disableTypeChecked` for `.js` | Config files and scripts aren't in a tsconfig; without this, typed rules error on them |
| `eslint-config-prettier/flat` last | Disables formatting rules so ESLint and Prettier never fight |
| `name:` on each object | Shows up in `npx eslint --inspect-config` and in error messages — invaluable when debugging which block applies |

> **Version-sensitive.** ESLint 10 dropped `.eslintrc.*` and `ESLINT_USE_FLAT_CONFIG` entirely, and config lookup now starts from each linted file's directory and walks up (so a monorepo can have per-package `eslint.config.mjs`). A TypeScript config file (`eslint.config.ts`) works but needs `jiti` installed on Node versions without native type stripping.

> **Gotcha.** Type-aware linting is slow — it builds a full TypeScript program. On a big repo, `strictTypeChecked` can take minutes. Mitigate with `--cache --cache-strategy content` (the ci-reporting chapter), and never run typed rules in a pre-commit hook on a large monorepo; run syntax-only rules in the hook and the full set in CI.

> **Version-sensitive.** TypeScript 7.0 (the native Go port, 8 July 2026; 7.0.2 current) ships **no programmatic API**; the TS team expects a new one in 7.1. typescript-eslint 8.70.1 still declares `typescript >=4.8.4 <6.1.0`, so type-aware linting cannot use TS 7. The [official workaround](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/) runs both side by side: `"@typescript/native": "npm:typescript@^7.0.2"` for `tsc`, and `"typescript": "npm:@typescript/typescript6@^6.0.2"` so typescript-eslint gets the 6.0 API (its CLI is `tsc6`).

`.prettierrc.json` — keep it short; Prettier's value is in having few options:

```json
{
  "printWidth": 100,
  "singleQuote": false,
  "trailingComma": "all",
  "semi": true
}
```

`.prettierignore` (Prettier also reads `.gitignore` by default in v3):

```text
dist/
coverage/
pnpm-lock.yaml
package-lock.json
*.gen.ts
CHANGELOG.md
```

`tsconfig.json` compiler strictness — the flags beyond `strict` that pay for themselves:

```json
{
  "compilerOptions": {
    "target": "ES2023",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,
    "noPropertyAccessFromIndexSignature": true,
    "verbatimModuleSyntax": true,
    "isolatedModules": true,
    "skipLibCheck": true,
    "noEmit": true
  },
  "include": ["src", "tests"]
}
```

`package.json` scripts, so the hook, the developer and CI all type the same thing:

```json
{
  "scripts": {
    "lint": "eslint . --max-warnings 0",
    "lint:fix": "eslint . --fix",
    "format": "prettier --write .",
    "format:check": "prettier --check .",
    "typecheck": "tsc --noEmit",
    "check": "npm run format:check && npm run lint && npm run typecheck"
  }
}
```

```bash
npx eslint --inspect-config          # browser UI: which config blocks apply to which file
npx eslint --print-config src/a.ts   # resolved config for one file
npx eslint . --max-warnings 0        # any warning fails
npx tsc --noEmit -p tsconfig.json    # type check only
npx tsc --noEmit --incremental --tsBuildInfoFile .cache/tsbuildinfo   # cacheable in CI
```

> **Gotcha.** `noUncheckedIndexedAccess` and `exactOptionalPropertyTypes` generate a lot of errors on an existing codebase. Enable them at project start; on a legacy codebase add them last, per-package.

#### Biome: close call

Biome is one Rust binary that formats and lints JS, TS, JSX, JSON, CSS and GraphQL, with Prettier-compatible output and ~95% of the most-used ESLint rules. It's 10–30× faster and has one config file.

**Tiebreaker: choose Biome when you don't depend on type-aware rules or ESLint plugins.** A Node service or library with no React/Vue plugin needs, where lint speed matters (large monorepo, pre-commit on every file) — take Biome. If you rely on `no-floating-promises`-class rules or framework plugins, stay on ESLint.

```json
{
  "$schema": "https://biomejs.dev/schemas/2.5.14/schema.json",
  "vcs": {
    "enabled": true,
    "clientKind": "git",
    "useIgnoreFile": true,
    "defaultBranch": "main"
  },
  "files": {
    "includes": ["**", "!**/dist", "!**/coverage", "!**/*.gen.ts"]
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100
  },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "suspicious": { "noExplicitAny": "error", "noConsole": "error" },
      "correctness": { "noUnusedImports": "error", "noUnusedVariables": "error" },
      "style": { "useImportType": "error" }
    }
  },
  "assist": {
    "enabled": true,
    "actions": { "source": { "organizeImports": "on" } }
  },
  "javascript": {
    "formatter": { "quoteStyle": "double", "trailingCommas": "all" }
  }
}
```

```bash
npx @biomejs/biome check --write .          # format + lint + organise imports, fix
npx @biomejs/biome ci .                     # CI mode: read-only, fails on any diagnostic
npx @biomejs/biome ci --changed .           # only files changed vs vcs.defaultBranch
npx @biomejs/biome ci --reporter=gitlab --reporter-file=gl-code-quality-report.json .
npx @biomejs/biome migrate eslint --write   # port an existing ESLint config
npx @biomejs/biome migrate prettier --write
```

> **Version-sensitive.** Biome 2 replaced `files.include`/`files.ignore` with a single `files.includes` list using `!` negation, and moved import sorting under `assist.actions.source.organizeImports`. 1.x configs need `biome migrate --write`.

Biome doesn't replace `tsc --noEmit`. Keep the type check job either way.

### Go

#### Formatting: gofmt + goimports, via golangci-lint

Go formatting is settled: `gofmt` is the standard, and `goimports` adds import grouping. golangci-lint v2 runs formatters itself (`golangci-lint fmt`) and reports unformatted files as issues in `run`, so you need one binary, not three.

`gofumpt` (stricter gofmt) is the alternative. **Tiebreaker: only on a greenfield repo where everyone uses an editor that runs it** — otherwise gopls's default gofmt formatting and your CI disagree on save.

#### .golangci.yml, v2 schema, complete

```yaml
version: "2"

run:
  timeout: 5m
  tests: true
  modules-download-mode: readonly
  # Evaluate exclusion paths relative to the git root (default is cfg: relative to this file).
  relative-path-mode: gitroot

linters:
  # standard = errcheck, govet, ineffassign, staticcheck, unused
  default: standard
  enable:
    - bodyclose       # unclosed HTTP response bodies
    - copyloopvar     # redundant loop-var copies (Go 1.22+ semantics)
    - errname         # sentinel errors named ErrX, types XError
    - errorlint       # %w wrapping, errors.Is/As instead of ==
    - exhaustive      # missing cases in switches over enums
    - gocritic
    - gosec
    - misspell
    - noctx           # HTTP requests without context
    - nolintlint      # nolint directives must be specific and justified
    - revive
    - unconvert
    - unparam
    - usestdlibvars
  settings:
    errcheck:
      check-type-assertions: true
    exhaustive:
      default-signifies-exhaustive: true
    gocritic:
      enabled-tags: [diagnostic, performance]
    govet:
      enable-all: true
      disable:
        - fieldalignment   # memory layout micro-optimisation; noisy
    nolintlint:
      require-explanation: true
      require-specific: true
    revive:
      rules:
        - name: exported
          arguments: ["disableStutteringCheck"]
        - name: unused-parameter
          disabled: true   # unparam covers this with fewer false positives
    staticcheck:
      # This is the v2 default, written out so nobody "simplifies" it and re-enables
      # the ST10xx comment-style nags. Add "-SAxxxx" here, never remove "all".
      checks: ["all", "-ST1000", "-ST1003", "-ST1016", "-ST1020", "-ST1021", "-ST1022"]
  exclusions:
    generated: lax
    presets:
      - comments
      - std-error-handling
      - common-false-positives
    rules:
      - path: _test\.go
        linters: [gosec, errcheck, noctx, bodyclose]
      - path: internal/legacy/
        linters: [revive, gocritic]   # ratchet: remove as the package is rewritten
    paths:
      - third_party/

formatters:
  enable:
    - gofmt
    - goimports
  settings:
    gofmt:
      simplify: true
    goimports:
      local-prefixes:
        - gitlab.example.com/GROUP
  exclusions:
    generated: lax
    paths:
      - third_party/

issues:
  max-issues-per-linter: 0   # 0 = unlimited; the default truncates and hides findings
  max-same-issues: 0

output:
  formats:
    text:
      path: stdout
    code-climate:
      path: gl-code-quality-report.json
```

| Key | What changed in v2 |
|---|---|
| `version: "2"` | Required. Without it, v2 refuses the file |
| `linters.default` | Replaces `disable-all`/`enable-all`: `standard`, `all`, `none`, `fast` |
| `linters.settings` | Was `linters-settings` at top level |
| `linters.exclusions` | Was `issues.exclude-rules`, `exclude-dirs`, and the implicit default excludes (now opt-in `presets`) |
| `formatters:` | New block. gofmt/goimports/gofumpt/gci/golines moved out of `linters` |
| `output.formats` | Map keyed by format with a `path`, instead of a list of `format:path` strings |
| staticcheck | Absorbed `gosimple` and `stylecheck`, which no longer exist as separate linters |

```bash
golangci-lint migrate                 # convert a v1 .golangci.yml in place (keeps a backup)
golangci-lint config verify           # validate against the JSON schema
golangci-lint linters                 # what's enabled under this config
golangci-lint formatters
golangci-lint run ./...
golangci-lint run --fix ./...
golangci-lint fmt                     # apply formatters
golangci-lint fmt --diff              # show what would change (in CI, `run` already fails on unformatted files)
golangci-lint run --new-from-merge-base=origin/main --whole-files   # ratchet mode
```

> **Gotcha.** v1's default `max-issues-per-linter: 50` and `max-same-issues: 3` silently truncate output — you fix 3 issues, push, and 3 more "new" ones appear. Set both to `0`.

> **Gotcha.** `exclusions.presets` replaced v1's implicit default excludes. A v1 config migrated without presets will suddenly report "missing doc comment" and unchecked `fmt.Fprintf` errors everywhere. `golangci-lint migrate` adds the equivalent presets; hand-written v2 configs need them explicitly.

> **Version-sensitive.** `run.relative-path-mode` is v2-only. Values: `gomod`, `gitroot`, `cfg` (the default: relative to the config file), `wd` (not recommended). It governs how `exclusions` paths and some linters resolve paths. When the Go module lives in a subdirectory of a monorepo, `gitroot` keeps exclusion paths written from the repo root working; also check that Code Quality report paths come out repo-relative (the ci-reporting chapter), because GitLab can't map a path relative to a subdirectory onto the MR diff.

> **Note.** Run it from the release binary or the official image pinned by digest (`golangci/golangci-lint:v2.13.2-alpine@sha256:…`). The golangci-lint project explicitly advises against `go install` for CI — it builds with your local Go toolchain, which can differ from the one the release was tested with.

### Shell

#### shellcheck + shfmt

**shellcheck is the single highest-value linter in a DevOps repo.** Shell is where the silent data-loss bugs live: unquoted variables expanding to nothing, `cd` failing and the next `rm -rf` running in the wrong directory.

```bash
shfmt -f .                                     # list every shell file (by extension AND shebang)
shfmt -f . | xargs shellcheck -f gcc           # lint them all, one line per finding
shfmt -d .                                     # diff of formatting changes; non-zero if any
shfmt -w .                                     # format in place
shellcheck -S warning script.sh                # only warning and above
shellcheck -x -P SCRIPTDIR script.sh           # follow `source` relative to the script
shellcheck --list-optional                     # optional checks you can enable
shellcheck -f diff script.sh | git apply       # apply shellcheck's autofixes
```

`shfmt -f` is the underrated part — it finds scripts without a `.sh` extension by reading shebangs, which is how you catch `bin/deploy` and `hack/release`.

`.shellcheckrc` at the repo root:

```ini
# Default dialect when there's no shebang (sourced libraries)
shell=bash

# Follow `source` statements, resolved relative to the script being checked
external-sources=true
source-path=SCRIPTDIR

# Optional checks worth having
enable=check-unassigned-uppercase
enable=require-double-brackets
enable=add-default-case
enable=deprecate-which
```

`.editorconfig` — shfmt reads its formatting options from here, so the editor and shfmt agree:

```ini
[*.sh]
indent_style = space
indent_size = 2
# shfmt-specific keys
shell_variant = bash
binary_next_line = true
switch_case_indent = true
space_redirects = false

[*.{bash,bats}]
indent_style = space
indent_size = 2
switch_case_indent = true
```

> **Gotcha.** shfmt's flags and EditorConfig are mutually exclusive: if you pass any printer flag (`-i 2`, `-ci`) on the command line, shfmt ignores `.editorconfig` entirely. Pick EditorConfig and pass no printer flags in hooks or CI.

> **Note.** shfmt supports a `zsh` dialect (`-ln zsh` or `shell_variant = zsh`). shellcheck does not lint zsh at all — for your dotfiles, format with shfmt and skip shellcheck.

#### The SC codes you'll actually see

All verified against shellcheck 0.11.0 locally.

| Code | Message (abridged) | What to do |
|---|---|---|
| **SC2086** | Double quote to prevent globbing and word splitting | Quote it: `"$var"`. The top shell bug. Intentional splitting → use an array |
| **SC2046** | Quote this to prevent word splitting (on `$(…)`) | `"$(cmd)"`, or read into an array with `mapfile -t` |
| **SC2068** | Double quote array expansions | `"${arr[@]}"`, never `${arr[@]}` |
| **SC2128** | Expanding an array without an index gives the first element | You meant `"${arr[@]}"` |
| **SC2164** | Use `cd … \|\| exit` in case cd fails | `cd "$dir" \|\| exit 1`, or `set -e`. The one that runs `rm -rf *` in `$HOME` |
| **SC2155** | Declare and assign separately to avoid masking return values | `local x; x=$(cmd)` — otherwise `local`'s exit 0 hides `cmd`'s failure, even under `set -e` |
| **SC2181** | Check exit code directly, not via `$?` | `if ! make; then …` |
| **SC2064** | Use single quotes, otherwise this expands now | `trap 'rm -f "$tmp"' EXIT` |
| **SC2016** | Expressions don't expand in single quotes | Usually intentional (`awk '{print $1}'`, `jq '.x'`) — disable inline with a reason |
| **SC2029** | Unescaped, this expands on the client side | `ssh host "echo $HOME"` expands locally. Single-quote or escape |
| **SC2034** | Variable appears unused | Delete it, or `export` it, or it's read by a sourcing script (disable inline) |
| **SC2154** | Variable referenced but not assigned | Typo, or set by a sourced file — use `-x` or `# shellcheck source=` |
| **SC1091** | Not following sourced file | Add `-x` / `external-sources=true`, or `# shellcheck source=/dev/null` for truly dynamic paths |
| **SC2162** | `read` without `-r` mangles backslashes | Always `read -r` |
| **SC2045** | Iterating over `ls` output is fragile | `for f in ./*.txt` |
| **SC2006** | Use `$(…)` not backticks | Mechanical fix |
| **SC2329** / **SC2317** | Function never invoked / command unreachable | Often false positives with `trap` handlers and dispatch tables — disable inline with a reason |
| **SC3040** | In POSIX sh, `set -o pipefail` is undefined | Your shebang says `sh`. Change it to `bash`, or accept dash/busybox semantics |
| **SC3014** | In POSIX sh, `==` is undefined | Use `=` in `[ ]`, or switch to bash and `[[ ]]` |

Inline suppression, with a reason:

```bash
# shellcheck disable=SC2016  # literal $1 is for awk, not the shell
awk '{print $1}' "$file"
```

> **Gotcha.** GitLab CI `script:` blocks are shell, but shellcheck never sees them. Long inline scripts in `.gitlab-ci.yml` are unlinted shell. **Move anything over ~5 lines into `ci/*.sh`** where shellcheck, shfmt and your editor can reach it.

#### A robust script header

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
shopt -s inherit_errexit 2>/dev/null || true   # bash 4.4+: $(…) inherits set -e

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
```

The `|| true` on `shopt` is the one legitimate use in this guide — it guards against older bash, not against a lint failure.

### Everything else

| Language | Formatter | Linter | Type / static | Notes |
|---|---|---|---|---|
| Rust | `cargo fmt --check` | `cargo clippy --all-targets --all-features -- -D warnings` | the compiler | `-D warnings` is what makes clippy a gate; `rustfmt.toml` + `clippy.toml` for config; `[lints]` table in `Cargo.toml` for workspace-wide rule levels |
| Terraform / HCL | `terraform fmt -check -recursive` | tflint | `terraform validate` | The infra-lint chapter |
| Java / Kotlin | google-java-format / ktfmt | Checkstyle, detekt, Error Prone | the compiler | Spotless (Gradle/Maven) to run formatters in the build |
| C / C++ | clang-format | clang-tidy | the compiler with `-Wall -Wextra -Werror` | `compile_commands.json` is required for clang-tidy |
| Lua | StyLua | selene or luacheck | — | Neovim configs |
| SQL | sqlfluff format | sqlfluff lint | — | Set `dialect` in `.sqlfluff`; slow on large files |
| Protobuf | `buf format` | `buf lint` | `buf breaking --against '.git#branch=main'` | `buf breaking` is the one that protects clients |
| Nix | nixfmt | statix, deadnix | — | |
| CSS / SCSS | Prettier | Stylelint | — | Stylelint has native Code Quality output |
| Ansible | — | ansible-lint | — | `.ansible-lint` profile `production` |

### Traps

- **Ruff `extend-select` on 0.16+.** You inherit 413 default rules plus yours. Use `select` for an explicit, stable rule set.
- **Linting with the formatter's conflicting rules on.** Ruff warns; heed it.
- **`.eslintrc` in an ESLint 10 repo.** It's ignored, silently in some setups. Flat config only.
- **Type-aware ESLint in the pre-commit hook on a large repo.** Minutes per commit; people bypass it. Syntax-only in the hook, typed in CI.
- **golangci-lint v1 config under v2.** Refused without `version: "2"`; migrated without presets it floods. Use `golangci-lint migrate`.
- **Default issue caps in golangci-lint.** Truncated output hides findings. `max-issues-per-linter: 0`, `max-same-issues: 0`.
- **shfmt flags plus `.editorconfig`.** Flags win and EditorConfig is ignored.
- **Scripts without `.sh`.** Glob-based linting misses them; use `shfmt -f .`.
- **Shell inline in `.gitlab-ci.yml`.** Unlinted. Move it into `ci/*.sh`.
- **mypy cache across a major upgrade.** Format changed in 2.0; key the cache on the version.
- **Bumping TypeScript ahead of typescript-eslint.** Check the supported peer range first.


---


<a id="03-linting-infra-and-config"></a>

## 03 · Linting infra and config

*In a platform repo, the YAML, HCL and Dockerfiles are the code. They fail at deploy time, in front of everyone, unless something parses and validates them first — and "it's valid YAML" is the weakest of the checks you can run.*

### Three levels of "valid"

Every config file can be checked at three increasingly useful levels. Most repos stop at the first.

| Level | Question | Example tools | Catches |
|---|---|---|---|
| **1. Syntax** | Does it parse? | yamllint, `check-json`, `check-toml`, `terraform fmt` | Tabs in YAML, trailing commas, unclosed quotes |
| **2. Schema** | Does it match the shape the consumer expects? | kubeconform, `check-jsonschema`, `terraform validate`, `glab ci lint` | `replica: 3` instead of `replicas`, wrong types, unknown keys |
| **3. Policy** | Is it a good idea? | hadolint, kube-linter, tflint, Trivy config, checkov | `:latest` tags, running as root, no resource limits, public S3 buckets |

**Level 2 is where most of the value is.** A YAML file with `replica: 3` passes yamllint, is applied by `kubectl` without complaint (unknown fields are dropped with a warning at best), and runs one pod in production. `kubeconform -strict` rejects it in 50 ms.

The picks:

| File type | Syntax / format | Schema | Policy |
|---|---|---|---|
| Dockerfile / Containerfile | — | — | **hadolint** |
| YAML (generic) | **yamllint** | `check-jsonschema` where a schema exists | — |
| Markdown | **markdownlint-cli2** | — | — |
| JSON | Prettier or `check-json` | `check-jsonschema` | — |
| TOML | **taplo** (`taplo fmt --check`) | taplo with schema | — |
| Helm chart | `helm lint --strict` | **`helm template \| kubeconform`**, `values.schema.json` | **kube-linter** on rendered output |
| Kubernetes manifests | yamllint | **kubeconform** | **kube-linter** |
| Terraform / OpenTofu | `terraform fmt` | `terraform validate` | **tflint** + **Trivy config** |
| `.gitlab-ci.yml` | yamllint | **`glab ci lint`** (server-side), `check-gitlab-ci` (offline) | — |
| Everything | **.editorconfig** | — | — |

### Dockerfiles: hadolint

hadolint parses the Dockerfile into an AST, applies its own `DL` rules, and runs **shellcheck on every `RUN` instruction**. That second part is most of its value — `RUN` lines are unlinted shell otherwise.

```bash
# No install needed: run the pinned image (works with podman or docker)
podman run --rm -i docker.io/hadolint/hadolint:v2.15.1 < Dockerfile
podman run --rm -i -v "$PWD/.hadolint.yaml:/.config/hadolint.yaml:ro" \
  docker.io/hadolint/hadolint:v2.15.1 < Containerfile

hadolint Dockerfile                                  # if installed (pip: hadolint-py ships the binary)
hadolint --failure-threshold warning Dockerfile      # info/style findings don't fail
hadolint -f gitlab_codeclimate Dockerfile > hadolint-cq.json   # Code Quality report
hadolint -f json Dockerfile | jq '.[] | .code' | sort | uniq -c   # triage by rule
```

`.hadolint.yaml` at the repo root:

```yaml
# Fail on warning and above; info and style are reported only.
failure-threshold: warning

# Only allow base images from these registries (DL3026).
trustedRegistries:
  - registry.example.com
  - docker.io
  - quay.io
  - gcr.io

ignored:
  # Pinning every apt package version fights security updates when the base
  # image is digest-pinned and rebuilt by Renovate. Pin the base instead.
  - DL3008
  - DL3018   # same, for apk

override:
  error:
    - DL3002   # last USER is root
    - DL3007   # using :latest
    - DL3020   # ADD instead of COPY for local files
    - DL4006   # pipe in RUN without pipefail
  warning:
    - DL3059   # multiple consecutive RUN instructions
```

| Rule | What it means | Fix |
|---|---|---|
| **DL3006** | Image not tagged | `FROM python:3.13-slim@sha256:…` |
| **DL3007** | `:latest` tag | Pin a tag *and* a digest |
| **DL3008 / DL3018** | apt / apk package not version-pinned | Ignore it (see above) and pin the base by digest — *position worth arguing* |
| **DL3009** | apt lists not deleted | `rm -rf /var/lib/apt/lists/*` in the same `RUN`, or use a cache mount |
| **DL3013** | pip package not pinned | Install from a lockfile (`uv sync --frozen`, `pip install -r requirements.txt --require-hashes`) |
| **DL3015** | apt without `--no-install-recommends` | Add it; typically halves the layer |
| **DL3020** | `ADD` for local files | `COPY`. `ADD` auto-extracts and fetches URLs |
| **DL3025** | Shell-form `CMD`/`ENTRYPOINT` | JSON form, so signals reach PID 1 |
| **DL3002** | Last `USER` is root | `USER 65532:65532` (or a named nonroot user) |
| **DL4006** | Pipe in `RUN` without pipefail | `SHELL ["/bin/bash", "-o", "pipefail", "-c"]` before it |
| **DL3059** | Consecutive `RUN`s | Merge them, unless deliberately split for caching |
| **SC2086** etc. | shellcheck findings inside `RUN` | As in the languages chapter |

Inline suppression goes on the line immediately above the instruction:

```dockerfile
# hadolint ignore=DL3003
RUN cd /src && make install
```

> **Gotcha.** hadolint has parsed BuildKit heredocs (`RUN <<EOF … EOF`) since 2.7.0, but the support has rough edges that are still open upstream in 2.15.1: heredocs with a shebang get irrelevant warnings (hadolint issue 806), bash heredocs are not always detected (1137), and a comment after the closing delimiter fails to parse (960). Treat a clean result on a heredoc-heavy Dockerfile with some suspicion.

> **Note.** The `DL3008` position is worth arguing about. Pinning `curl=7.88.1-10+deb12u5` makes the build reproducible for the week before Debian drops that version from the mirror, then breaks it. A digest-pinned base plus Renovate bumps gives you reproducibility *and* security updates. Pin apt packages only when you need a specific version for correctness.

### YAML: yamllint

yamllint checks syntax and style. It doesn't know what the YAML is *for* — that's what the schema tools below add.

`.yamllint.yaml`:

```yaml
extends: default

ignore: |
  # Helm templates are Go templates, not YAML — they don't parse until rendered.
  charts/*/templates/
  # Generated or vendored
  vendor/
  node_modules/
  .terraform/

rules:
  line-length:
    max: 160
    level: warning
    allow-non-breakable-words: true
    allow-non-breakable-inline-mappings: true
  document-start: disable            # "---" is optional; enforcing it is noise
  truthy:
    allowed-values: ["true", "false"]
    check-keys: false                # GitHub Actions / some tools use `on:` as a key
  comments:
    min-spaces-from-content: 1       # default 2 fights most formatters
  comments-indentation: disable
  indentation:
    spaces: 2
    indent-sequences: consistent     # accept both styles, but one per file
  braces:
    max-spaces-inside: 1
  octal-values:
    forbid-implicit-octal: true      # `mode: 0644` silently becomes 420 in YAML 1.1
    forbid-explicit-octal: false
  key-duplicates: enable
  new-line-at-end-of-file: enable
```

```bash
yamllint .                            # uses .yamllint.yaml
yamllint -f parsable .                # file:line:col: [level] message (rule) — easy to grep/convert
yamllint -f github .                  # GitHub annotations (not useful on GitLab)
yamllint --strict .                   # warnings also exit non-zero
yamllint --list-files .               # what it would lint after ignores
```

> **Gotcha.** `line-length` at `level: warning` without `--strict` means long lines never fail the build — fine. But **any other rule you set to `warning` is invisible without `--strict`**. Either run `yamllint --strict` or keep every rule you care about at `error` (the default level).

> **Gotcha.** YAML 1.1 (which most tools still implement) reads `yes`, `no`, `on`, `off` as booleans and `0644` as octal. `country: NO` becomes `false`. The `truthy` and `octal-values` rules exist for exactly this; keep them on.

> **Note.** yamllint's exit codes: `0` clean, `1` errors, `2` warnings only when `--strict`. That's the full contract a CI job needs.

### Markdown: markdownlint-cli2

Pick **markdownlint-cli2**, not the older `markdownlint-cli`. It's configuration-file-driven (no long CLI invocations to keep in sync), faster, and has a native GitLab Code Quality formatter.

`.markdownlint-cli2.jsonc`:

```jsonc
{
  "config": {
    "default": true,
    "MD013": false,                               // line length: prose wraps, tables can't
    "MD024": { "siblings_only": true },           // duplicate headings OK under different parents
    "MD033": { "allowed_elements": ["details", "summary", "br"] },
    "MD041": false,                               // first line needn't be a heading (front matter, badges)
    "MD046": { "style": "fenced" },
    "MD040": true                                 // fenced code blocks must have a language
  },
  "globs": ["**/*.md"],
  "ignores": ["node_modules/**", "vendor/**", "CHANGELOG.md", "**/charts/*/README.md"],
  "gitignore": true,
  "outputFormatters": [
    ["markdownlint-cli2-formatter-default"],
    ["markdownlint-cli2-formatter-codequality", { "name": "gl-code-quality-markdown.json" }]
  ]
}
```

```bash
npx markdownlint-cli2                       # uses globs from the config
npx markdownlint-cli2 --fix                 # fix what's fixable
npx markdownlint-cli2 "docs/**/*.md" "#docs/generated"   # '#' negates a glob on the CLI
podman run --rm -v "$PWD:/workdir:Z" docker.io/davidanson/markdownlint-cli2:v0.23.3
```

> **Note.** `CHANGELOG.md` is excluded above because it's generated by release tooling (git-cliff, the merge-policy chapter) if you commit one at all; linting a generated file just creates fights with the generator. `helm-docs`-generated chart READMEs are excluded for the same reason.

> **Gotcha.** The `:Z` on the podman volume relabels for SELinux on Fedora. Without it, the container can't read your files and markdownlint reports "no files found" with exit 0 — a silent pass.

### JSON and TOML

| Need | Pick | Command |
|---|---|---|
| JSON parses | `check-json` (pre-commit-hooks) | `pre-commit run check-json --all-files` |
| JSON formatted | **Prettier** (you already have it for JS) | `prettier --check "**/*.json"` |
| JSON matches a schema | **check-jsonschema** | `check-jsonschema --schemafile schema.json data.json` |
| Well-known config files match their schema | check-jsonschema built-ins | `check-jsonschema --builtin-schema vendor.renovate renovate.json` |
| TOML parses | `check-toml` (pre-commit-hooks) | — |
| TOML formatted / validated | **taplo** | `taplo fmt --check`, `taplo lint` |

check-jsonschema ships schemas for common vendor files, so you get level-2 validation for free on files people hand-edit and break:

```bash
pipx run check-jsonschema --builtin-schema vendor.renovate renovate.json
pipx run check-jsonschema --builtin-schema vendor.gitlab-ci --data-transform gitlab-ci .gitlab-ci.yml
pipx run check-jsonschema --schemafile charts/app/values.schema.json charts/app/values.yaml
pipx run check-jsonschema --schemafile https://json.schemastore.org/pyproject.json pyproject.toml
```

> **Note.** JSON doesn't allow comments or trailing commas, but `tsconfig.json`, `.vscode/*.json` and `devcontainer.json` are actually JSONC. `check-json` rejects them. Exclude those paths from `check-json` (or rename to `.jsonc` where the consumer allows it).

### Helm charts

Helm templates aren't YAML until rendered, so linting a chart means rendering it and linting the output. Three layers:

#### 1. helm lint

```bash
helm lint charts/app --strict                              # warnings (e.g. missing icon) fail too
helm lint charts/app --strict -f charts/app/ci/prod-values.yaml
helm lint charts/app --strict --with-subcharts
helm dependency build charts/app                            # lint needs deps present
```

`helm lint` catches template errors, a malformed `Chart.yaml`, and values that fail `values.schema.json`. It does **not** validate rendered manifests against Kubernetes schemas.

#### 2. helm template | kubeconform

```bash
for values in charts/app/ci/*-values.yaml; do
  echo "--- $values"
  helm template app charts/app -f "$values" --kube-version 1.33.0 \
    | kubeconform -strict -summary \
        -kubernetes-version 1.33.0 \
        -schema-location default \
        -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
        -cache "${XDG_CACHE_HOME:-$HOME/.cache}/kubeconform"
done
```

- Render **every values permutation you ship** (`ci/*-values.yaml` is also the chart-testing convention). A template that only breaks when `ingress.enabled: true` is invisible if you only render defaults.
- Pass the **same Kubernetes version** to `helm template --kube-version` (so `.Capabilities` gates evaluate correctly) and to kubeconform.
- `-strict` rejects unknown fields and duplicate keys. Without it, `replica: 3` passes.
- CRDs: the datree CRDs-catalog covers cert-manager, Argo, Prometheus Operator and most popular operators. For your own CRDs, generate schemas with the `openapi2jsonschema.py` script in the kubeconform repo and add a local `-schema-location`.

> **Gotcha.** `-ignore-missing-schemas` is tempting the first time a CRD fails. It turns every unknown kind — including a typo'd `kind: Deploymnet` — into a silent pass. Prefer `-skip KIND1,KIND2` for the specific kinds you can't get schemas for.

> **Gotcha.** In an air-gapped CI, `-schema-location default` fetches from GitHub. Mirror the schemas (`kubernetes-json-schema` for your version, plus the CRDs you use) into the repo or an internal artefact and point `-schema-location` at the local path template.

#### 3. chart-testing (ct)

`ct lint` wraps `helm lint`, a **version-bump check** against the target branch, a Yamale schema check on `Chart.yaml`, and yamllint on the chart — and only for **charts that changed**.

`ct.yaml`:

```yaml
target-branch: main
remote: origin
chart-dirs:
  - charts
chart-repos:
  - bitnami=https://charts.bitnami.com/bitnami
check-version-increment: true
validate-maintainers: false
validate-chart-schema: true
validate-yaml: true
helm-extra-args: --timeout 600s
```

```bash
ct list-changed --config ct.yaml
ct lint --config ct.yaml
ct lint --config ct.yaml --all              # every chart, not just changed ones
ct install --config ct.yaml                 # install into a live cluster (kind in CI) and run helm test
```

> **Gotcha.** ct diffs against `origin/<target-branch>`. GitLab CI clones shallow (`GIT_DEPTH`, 20 by default on current GitLab) and a merge request pipeline may not have `origin/main` at all. Run `git fetch origin main` before `ct`, or `ct list-changed` reports nothing changed and `ct lint` passes vacuously.

> **Note.** `check-version-increment` is the one that stops "I changed the chart but didn't bump the version, so the registry already has 1.4.2 with different contents." That's a one-way door in an OCI registry that refuses overwrites — and a silent inconsistency in one that allows them.

### Kubernetes manifests

For raw manifests and Kustomize output, the same two tools apply:

```bash
kubeconform -strict -summary -kubernetes-version 1.33.0 manifests/
kustomize build overlays/prod | kubeconform -strict -summary -kubernetes-version 1.33.0 -
kubeconform -output junit -strict manifests/ > kubeconform-junit.xml     # JUnit for the MR widget
```

Output formats: `text` (default), `json`, `junit`, `pretty`, `tap`. `-n` sets concurrency (default 4).

#### kube-linter: policy on top of schema

kubeconform says the manifest is *valid*. kube-linter says whether it's *sensible*: no resource limits, running as root, writable root filesystem, `latest` tags, missing probes, privileged containers, host network.

`.kube-linter.yaml`:

```yaml
checks:
  addAllBuiltIn: true
  exclude:
    # Covered by our Kyverno admission policy; reporting twice is noise.
    - "latest-tag"
    # We deliberately drop CPU limits (see the Kubernetes Field Manual).
    - "unset-cpu-requirements"
    # Single-replica dev components.
    - "minimum-three-replicas"
    - "no-anti-affinity"
    - "non-isolated-pod"          # NetworkPolicy lives in a separate chart
ignorePaths:
  - "**/testdata/**"
```

```bash
kube-linter lint --config .kube-linter.yaml manifests/
kube-linter lint --config .kube-linter.yaml charts/app       # renders the chart itself
helm template app charts/app -f values-prod.yaml | kube-linter lint --config .kube-linter.yaml -
kube-linter lint --format sarif manifests/ > kube-linter.sarif
kube-linter checks list                                        # every built-in check
```

Per-object exception, as an annotation — visible in review next to the thing it excuses:

```yaml
metadata:
  annotations:
    ignore-check.kube-linter.io/run-as-non-root: "init container needs root to chown the volume"
```

> **Note.** kube-linter vs Kyverno/Gatekeeper policy: kube-linter is shift-left (fails the MR), admission policy is the enforcement (fails the apply). You want both, and ideally the same rules. If a rule is enforced at admission, still lint it — a rejected apply at deploy time is a worse developer experience than a red MR.

### Terraform and OpenTofu

Four checks, in increasing cost:

```bash
terraform fmt -check -recursive -diff                     # formatting; no init needed
terraform init -backend=false -input=false                # providers only, no state access
terraform validate -json | jq -e '.valid'                 # schema-level validity
tflint --init && tflint --recursive --format compact      # provider-aware lint
trivy config --severity HIGH,CRITICAL --exit-code 1 .     # security misconfig
```

OpenTofu is a drop-in: replace `terraform` with `tofu` throughout.

> **Gotcha.** `terraform validate` needs `init` first (it must load provider schemas). Use `-backend=false` in CI lint jobs so they don't need state credentials — a lint job with write access to state is a lint job that can destroy infrastructure.

#### tflint

`terraform validate` checks that the config is internally consistent. tflint knows the providers: invalid instance types, deprecated arguments, missing `required_version`, unused declarations.

`.tflint.hcl`:

```hcl
config {
  call_module_type = "local"     # inspect local modules; "all" also fetches remote ones
  force            = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "google" {
  enabled = true
  version = "0.33.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}
```

```bash
tflint --init                                   # download plugins into TFLINT_PLUGIN_DIR
tflint --recursive                              # every module directory
tflint --chdir=modules/network
tflint --format junit > tflint-junit.xml        # formats: default, json, checkstyle, junit, compact, sarif
tflint --minimum-failure-severity=warning
```

> **Version-sensitive.** The ruleset plugin `version` shown above is illustrative; pin to the current release of `tflint-ruleset-google` / `-aws` / `-azurerm`. `tflint --init` downloads from GitHub and is rate-limited without `GITHUB_TOKEN`; in CI, cache `TFLINT_PLUGIN_DIR` keyed on `.tflint.hcl` so you download once.

#### Trivy config vs checkov

**Default: Trivy (`trivy config`).** Reason: one binary scans Terraform, Kubernetes, Helm, Dockerfiles *and* container images, with one ignore file (`.trivyignore`) and one severity model. If you already gate images with Trivy (the Kubernetes Field Manual recommends it), IaC scanning costs you nothing new.

**Tiebreaker: checkov** if you need graph-based cross-resource checks (e.g. "this bucket is public *and* has no logging") or you're writing many custom policies — checkov's custom policy model in Python/YAML is richer.

```bash
trivy config .                                            # all IaC types it detects
trivy config --severity HIGH,CRITICAL --exit-code 1 .
trivy config --tf-vars prod.tfvars terraform/
trivy config --format template --template "@/contrib/gitlab-codequality.tpl" -o trivy-cq.json .
trivy config --skip-dirs .terraform --skip-dirs vendor .

checkov -d terraform/ --framework terraform --compact --quiet
checkov -d . --output junitxml > checkov-junit.xml
```

`.trivyignore` — each line an ID, ideally with an expiry:

```text
# Public bucket is the static site origin; reviewed PLAT-881
AVD-AWS-0086 exp:2027-03-31
```

> **Gotcha.** The official Trivy image copies its templates to **`/contrib/`** (absolute; its `Dockerfile` does `COPY contrib/*.tpl contrib/` with no `WORKDIR`), and [Trivy's own GitLab CI example](https://github.com/aquasecurity/trivy/blob/main/docs/tutorials/integrations/gitlab-ci.md) uses `@/contrib/gitlab-codequality.tpl`. A relative `@contrib/...` fails in CI because the job's working directory is `$CI_PROJECT_DIR`. Outside the image (RPM installs use `/usr/local/share/trivy/templates`), point `--template` at the file from the source repo's `contrib/` directory.

### GitLab CI YAML itself

The pipeline config is code that nobody runs locally, which makes it the most commonly broken file in the repo. Validate it before pushing.

#### glab ci lint (server-side, authoritative)

```bash
glab ci lint                                    # validate .gitlab-ci.yml via the project's CI Lint API
glab ci lint path/to/other.gitlab-ci.yml
glab ci lint --include-jobs                     # also list the jobs that would exist
glab ci lint --dry-run --ref main               # simulate pipeline creation on main
glab ci lint --dry-run --ref main --include-jobs
glab ci config compile                          # print the fully merged config (includes resolved)
```

(Flags verified against glab 1.108.)

What each level catches:

| Check | Catches | Misses |
|---|---|---|
| `glab ci lint` (static) | Syntax, unknown keywords, include resolution, `extends` cycles | Anything depending on rules evaluation for a specific ref |
| `glab ci lint --dry-run --ref BRANCH` | `needs:` pointing at a job that doesn't exist *for that ref* after `rules:` filter, empty pipelines, workflow:rules blocking everything | MR-pipeline-specific rules (dry-run simulates a branch pipeline) |
| `glab ci config compile` | Nothing by itself — but diffing it before/after a change shows exactly what an `include:` bump changed | — |

> **Gotcha.** `glab ci lint` sends your **local** file content to the server, but `include: local:` files are resolved from the **repository on the server** at the default branch (or the ref), not from your working tree. A change split across `.gitlab-ci.yml` and an included `ci/lint.yml` lints against the *old* `ci/lint.yml` until you push. Push the branch, then run `glab ci lint --dry-run --ref BRANCH`.

#### The CI Lint API directly

`glab ci lint` wraps these. Both are read-only (they validate; they don't create pipelines), though the first is a `POST`:

```bash
# Validate arbitrary content in the project's context (resolves includes, project variables)
glab api --method POST "projects/:id/ci/lint" \
  --field content=@.gitlab-ci.yml --field include_jobs=true | jq '{valid, errors, warnings}'

# Validate the config already in the repo at a ref, with a pipeline simulation
glab api "projects/:id/ci/lint?dry_run=true&dry_run_ref=main&include_jobs=true" \
  | jq '{valid, errors, warnings, jobs: [.jobs[].name]}'
```

Response fields: `valid`, `errors`, `warnings`, `merged_yaml`, `includes`, and `jobs` with `include_jobs=true`.

> **Note.** The old instance-level `POST /ci/lint` endpoint was removed in GitLab 16.0; use the project-scoped endpoint. The project endpoints need an authenticated token with project access; `POST /projects/:id/ci/lint` (what `glab ci lint` calls) requires permission to **create a pipeline** in the project (Developer or higher, and the ref's protection rules apply to the simulation), while `GET /projects/:id/ci/lint` only needs read access to the code ([API docs](https://docs.gitlab.com/api/lint/), `lib/api/lint.rb`).

#### Offline schema check (pre-commit)

`glab` needs network and a token, which you don't want in a pre-commit hook. The offline alternative validates against the SchemaStore GitLab CI schema:

```bash
pipx run check-jsonschema --builtin-schema vendor.gitlab-ci --data-transform gitlab-ci .gitlab-ci.yml
```

It catches misspelt keywords and wrong types. It can't resolve includes, evaluate `rules:`, or know about CI/CD components — so it's the hook-level check, and `glab ci lint` in CI (or pre-push) is the real one.

> **Gotcha.** The generic `check-yaml` hook from pre-commit-hooks **fails on `!reference [...]` tags** (unknown tag to a safe loader). Add `args: [--unsafe]` for `.gitlab-ci.yml` and included CI files — with `--unsafe` it checks syntax only, which is all it's for here. The `--data-transform gitlab-ci` in `check-gitlab-ci` handles `!reference` properly.

### .editorconfig

The lowest-tech tool in the chapter and the one that prevents the most pointless diffs. Every editor honours it natively or with a plugin, and shfmt reads it (the languages chapter).

```ini
# .editorconfig — https://editorconfig.org
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 2

[*.py]
indent_size = 4

[*.go]
indent_style = tab

[Makefile]
indent_style = tab

[*.md]
# Two trailing spaces are a hard line break in Markdown.
trim_trailing_whitespace = false

[*.{sh,bash}]
indent_size = 2
shell_variant = bash
binary_next_line = true
switch_case_indent = true

[*.{tf,tfvars,hcl}]
indent_size = 2

[{*.bat,*.cmd,*.ps1}]
end_of_line = crlf
```

Pair it with the pre-commit `end-of-file-fixer`, `trailing-whitespace` and `mixed-line-ending` hooks (the hooks chapter) so a contributor whose editor ignores `.editorconfig` still can't commit the difference.

### Traps

- **Stopping at syntax.** yamllint passes `replica: 3`. Add kubeconform `-strict`.
- **`-ignore-missing-schemas`.** Turns typo'd kinds into passes. Use `-skip` for specific kinds.
- **Linting Helm templates as YAML.** They're Go templates. Exclude `templates/` from yamllint; render and lint the output.
- **Rendering only default values.** Render every `ci/*-values.yaml` permutation.
- **`ct` on a shallow clone.** `git fetch origin main` first, or nothing is "changed".
- **`terraform validate` with a real backend in CI.** Use `init -backend=false`; lint jobs don't need state.
- **yamllint rules at `warning` without `--strict`.** They never fail.
- **Linting generated files** (CHANGELOG, helm-docs READMEs, `*_pb2.py`). Exclude them; the generator owns them.
- **`glab ci lint` on a change split across included files.** Includes resolve from the server; push first.
- **`check-yaml` on `!reference` tags.** Needs `--unsafe`.
- **Podman without `:Z` on Fedora.** SELinux hides the files; some linters then pass on "no files".
- **Inline `RUN` shell nobody lints.** hadolint's embedded shellcheck is the only thing reading it.


---


<a id="04-git-hooks-and-pre-commit"></a>

## 04 · Git hooks and pre-commit

*A hook is the cheapest place to catch a mistake and the easiest place to bypass. Make it fast, make it fix rather than nag, and assume CI will re-run every check it contains.*

### What hooks are for

Git runs executables in `.git/hooks/` at fixed points. Four matter for linting:

| Hook | Fires | Receives | Use for | Budget |
|---|---|---|---|---|
| `pre-commit` | before the commit object is created | nothing (inspect the index) | formatters, fast linters, secret scan of staged changes | ~3 s |
| `commit-msg` | after the message is written | path to the message file (`$1`) | Conventional Commits check | < 1 s |
| `pre-push` | before objects are sent | remote name, URL; refs on stdin | slower checks: type check, `glab ci lint`, tests | ~30 s |
| `prepare-commit-msg` | before the editor opens | message file, source | pre-fill a ticket ID from the branch name | < 1 s |

Two facts shape everything else:

1. **`.git/hooks/` isn't versioned.** A fresh clone has no hooks. Something must install them — a framework, or `git config core.hooksPath`.
2. **`git commit --no-verify` (`-n`) skips `pre-commit` and `commit-msg`; `git push --no-verify` skips `pre-push`.** Hooks are advisory by construction. CI is the gate (the philosophy chapter).

```bash
git config core.hooksPath                 # empty = .git/hooks; set = frameworks may refuse to install
git commit --no-verify -m "wip"           # bypass: pre-commit and commit-msg
SKIP=mypy,hadolint git commit -m "…"      # pre-commit framework: skip specific hooks only
LEFTHOOK=0 git commit -m "…"              # lefthook: skip all
```

> **Gotcha.** If `core.hooksPath` is set (globally, by a corporate dotfile, or by an old husky install), `pre-commit install` refuses with "Cowardly refusing to install hooks with `core.hooksPath` set." Check `git config --show-origin core.hooksPath` and unset it at the level where it was set.

### The pre-commit framework

**Default: pre-commit (the Python framework, `pre-commit.com`).** Reason: each hook declares its own language and pre-commit builds an **isolated, pinned environment per hook** — the hadolint hook brings its own hadolint, the shellcheck hook its own shellcheck — so a new contributor runs `pre-commit install` and has the whole toolchain without installing anything else. The same config then runs unchanged in CI.

Current version: pre-commit 4.6.2 (read from pre-commit.com).

```bash
uv tool install pre-commit                 # or: pipx install pre-commit
pre-commit install                         # installs the hook types in default_install_hook_types
pre-commit install --install-hooks         # also build every hook env now, not on first commit
pre-commit run                             # staged files only (what the hook does)
pre-commit run --all-files                 # every tracked file — the CI invocation
pre-commit run ruff-check --all-files      # one hook
pre-commit run --files src/a.py src/b.py
pre-commit run --from-ref origin/main --to-ref HEAD   # files changed on this branch
pre-commit run --hook-stage manual trivy-config        # hooks gated to the manual stage
pre-commit autoupdate --freeze             # bump every rev and pin to a commit SHA
pre-commit gc                              # remove envs no longer referenced
pre-commit clean                           # nuke the whole cache (~/.cache/pre-commit)
pre-commit validate-config
```

#### A complete .pre-commit-config.yaml

Revs below are the current releases' commit SHAs, resolved with `git ls-remote` at time of writing (September 2026). Regenerate with `pre-commit autoupdate --freeze` rather than copying SHAs by hand.

```yaml
# .pre-commit-config.yaml
minimum_pre_commit_version: "3.2.0"   # stage names pre-commit/commit-msg/pre-push
default_install_hook_types: [pre-commit, commit-msg, pre-push]
default_stages: [pre-commit]
fail_fast: false

exclude: |
  (?x)^(
    vendor/|
    .*/generated/|
    .*\.min\.(js|css)$|
    CHANGELOG\.md$
  )

repos:
  # ------------------------------------------------------------ hygiene
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: 3e8a8703264a2f4a69428a0aa4dcb512790b2c8c  # frozen: v6.0.0
    hooks:
      - id: check-merge-conflict
      - id: end-of-file-fixer
      - id: trailing-whitespace
        args: [--markdown-linebreak-ext=md]
      - id: mixed-line-ending
        args: [--fix=lf]
      - id: check-added-large-files
        args: [--maxkb=500]
      - id: check-case-conflict
      - id: check-executables-have-shebangs
      - id: check-shebang-scripts-are-executable
      - id: check-symlinks
      - id: detect-private-key
      - id: check-json
        exclude: ^(tsconfig.*\.json|\.vscode/.*|\.devcontainer/.*)$   # JSONC files
      - id: check-toml
      - id: check-yaml
        args: [--unsafe]         # syntax only; tolerates !reference and Helm-ish tags
        exclude: ^charts/.*/templates/
      - id: no-commit-to-branch
        args: [--branch, main]

  # ------------------------------------------------------------ python
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: 2eeb5678de71a00c0902cbda7105d328432f72cb  # frozen: v0.16.8
    hooks:
      - id: ruff-check
        args: [--fix, --exit-non-zero-on-fix]
      - id: ruff-format

  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: 7ff8d35ae36a7d2b968f2f90b4c723e292e594ee  # frozen: v2.3.1
    hooks:
      - id: mypy
        stages: [pre-push]       # whole-program and slow: not on every commit
        pass_filenames: false
        args: [--config-file=pyproject.toml]
        additional_dependencies: ["pydantic>=2", "types-requests"]

  # ------------------------------------------------------------ shell
  - repo: https://github.com/shellcheck-py/shellcheck-py
    rev: 745eface02aef23e168a8afb6b5737818efbea95  # frozen: v0.11.0.1
    hooks:
      - id: shellcheck

  - repo: https://github.com/scop/pre-commit-shfmt
    rev: 479be5958357ba5ab65ce47172117348516860e9  # frozen: v3.14.1-1
    hooks:
      - id: shfmt                # reads .editorconfig; pass no printer flags

  # ------------------------------------------------------------ containers / yaml
  - repo: https://github.com/AleksaC/hadolint-py
    rev: 6e7504451511eaeb62a3e7f14d63b0296cbf86eb  # frozen: v2.15.1
    hooks:
      - id: hadolint
        files: (^|/)(Dockerfile|Containerfile)(\..*)?$

  - repo: https://github.com/adrienverge/yamllint
    rev: cba56bcde1fdd01c1deb3f945e69764c291a6530  # frozen: v1.38.0
    hooks:
      - id: yamllint
        args: [--strict]

  - repo: https://github.com/python-jsonschema/check-jsonschema
    rev: 99f2dd369364da7ed3ac536504132b3db2e7a3b1  # frozen: 0.38.1
    hooks:
      - id: check-gitlab-ci
        files: ^(\.gitlab-ci\.yml|\.gitlab/ci/.*\.ya?ml)$
      - id: check-renovate

  # ------------------------------------------------------------ secrets
  - repo: https://github.com/gitleaks/gitleaks
    rev: 83d9cd684c87d95d656c1458ef04895a7f1cbd8e  # frozen: v8.30.1
    hooks:
      - id: gitleaks

  # ------------------------------------------------------------ commit message
  - repo: https://github.com/commitizen-tools/commitizen
    rev: 3f5ccc87b27966d9ed21cf5ea8ec2fba38ca65ce  # frozen: v4.19.0
    hooks:
      - id: commitizen           # stage: commit-msg (set by the hook definition)
```

Why each non-obvious setting:

| Setting | Why |
|---|---|
| `default_install_hook_types` | Without it, `pre-commit install` only installs the `pre-commit` hook, and the `commit-msg` and `pre-push` hooks silently never run |
| `ruff-check --exit-non-zero-on-fix` | Autofixes are applied, but the commit still stops so you see and stage what changed. Without it, fixed-but-unstaged changes are easy to lose track of |
| `mypy` at `pre-push`, `pass_filenames: false` | mypy is whole-program; per-file invocation gives wrong answers and is slow |
| mypy `additional_dependencies` | The mirror runs in an **isolated env** — it can't see your project's packages. Plugins and stubs must be listed here, or mypy reports `import-not-found` everywhere. This is the main argument for running mypy as a `repo: local` hook instead (below) |
| `check-yaml --unsafe` | `!reference` tags in GitLab CI files otherwise fail |
| `no-commit-to-branch` | A local speed bump against committing directly to `main`. The real protection is the protected branch (the merge-policy chapter) |
| `check-json` exclude | tsconfig and VS Code files are JSONC |
| hadolint `files:` | Matches `Dockerfile`, `Containerfile`, `Dockerfile.dev`, `api/Containerfile` |

> **Version-sensitive.** The ruff hook id is `ruff-check` in current `ruff-pre-commit`; the old id `ruff` still works as an alias but new configs should use `ruff-check`. Hook stage names changed in pre-commit 3.2 (`commit` → `pre-commit`, `push` → `pre-push`); old names still work but warn.

#### Local hooks: one source of truth for versions

The config above pins ruff twice if `pyproject.toml` also pins it (the philosophy chapter's drift problem). The alternative is a `repo: local` hook that calls the project's own toolchain:

```yaml
  - repo: local
    hooks:
      - id: ruff-check
        name: ruff check (project version)
        entry: uv run --frozen ruff check --fix --exit-non-zero-on-fix --force-exclude
        language: system
        types_or: [python, pyi]
        require_serial: true
      - id: ruff-format
        name: ruff format (project version)
        entry: uv run --frozen ruff format --force-exclude
        language: system
        types_or: [python, pyi]
        require_serial: true
      - id: mypy
        name: mypy (project env)
        entry: uv run --frozen mypy
        language: system
        types: [python]
        pass_filenames: false
        stages: [pre-push]
      - id: eslint
        name: eslint (project version)
        entry: npx --no-install eslint --max-warnings 0 --fix
        language: system
        files: \.(ts|tsx|js|mjs|cjs)$
```

**Rule of thumb:** tools that are part of the language toolchain (ruff, mypy, ESLint, Prettier, golangci-lint) → `repo: local` calling the lockfile version. Standalone binaries with no project dependency (shellcheck, shfmt, hadolint, gitleaks, yamllint) → pre-commit-managed repos, pinned by SHA. You get one pin per tool, never two.

> **Gotcha.** `language: system` means "whatever is on `PATH`". It works because `uv run` and `npx --no-install` resolve the project's pinned version, but a bare `entry: ruff` would run whatever ruff the developer has globally — the drift you were trying to eliminate.

#### Pinning by SHA and autoupdate

`rev:` is a git ref. Tags are mutable — a compromised upstream can move `v1.2.3` to a malicious commit, and every `pre-commit install` afterwards fetches it. `--freeze` pins to the commit SHA and keeps the tag as a comment:

```bash
pre-commit autoupdate --freeze                               # all repos, latest tag, pinned to SHA
pre-commit autoupdate --freeze --repo https://github.com/astral-sh/ruff-pre-commit
pre-commit autoupdate --bleeding-edge                        # default branch HEAD — don't
```

```yaml
    rev: 2eeb5678de71a00c0902cbda7105d328432f72cb  # frozen: v0.16.8
```

**Automate the bumps so each one is its own MR.** Each update then runs through CI and you see exactly which new findings a linter bump introduces. Renovate's `pre-commit` manager does this for tag revs:

```json
{
  "extends": ["config:recommended"],
  "pre-commit": { "enabled": true }
}
```

> **Note.** Renovate's `pre-commit` manager is opt-in (disabled by default), hence the explicit `"enabled": true`.

> **Version-sensitive.** Renovate updates **SHA revs with `# frozen:` comments** (SHA and comment together) from **Renovate 43.20.0** (February 2026, PR 36693, closing issue 22567). On older self-hosted Renovate it does not; there the fallback is a close call between tag revs bumped by Renovate (convenient, mutable) and frozen SHAs bumped by a monthly `pre-commit autoupdate --freeze` MR (immutable, manual). Tiebreaker: the more of your hooks come from small single-maintainer repos, the more the SHA pin is worth.

#### Running pre-commit in GitLab CI

CI runs the same config with `--all-files`. The cache is what makes it fast: hook environments are built once per config change, not per pipeline.

```yaml
pre-commit:
  stage: lint
  image: python:3.13-slim   # pin by digest in real use: python:3.13-slim@sha256:…
  needs: []
  interruptible: true
  variables:
    PRE_COMMIT_HOME: ${CI_PROJECT_DIR}/.cache/pre-commit
    PIP_CACHE_DIR: ${CI_PROJECT_DIR}/.cache/pip
    # gitleaks' hook scans *staged* changes — nothing is staged in CI, so it's a no-op here.
    # Secret scanning runs as its own job (the ci-reporting chapter). no-commit-to-branch is meaningless in CI.
    SKIP: gitleaks,no-commit-to-branch
  cache:
    - key:
        files: [.pre-commit-config.yaml]
        prefix: pre-commit
      paths: [.cache/pre-commit]
    - key: pip-$CI_JOB_IMAGE
      paths: [.cache/pip]
  before_script:
    - apt-get update -qq && apt-get install -y -qq --no-install-recommends git >/dev/null
    - pip install --quiet pre-commit==4.6.2
  script:
    - pre-commit run --all-files --show-diff-on-failure --color=always
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

| Detail | Why |
|---|---|
| `PRE_COMMIT_HOME` inside `CI_PROJECT_DIR` | GitLab can only cache paths inside the project directory. The default `~/.cache/pre-commit` is outside it and is silently not cached |
| `cache:key:files: [.pre-commit-config.yaml]` | Cache invalidates exactly when a rev changes |
| `--show-diff-on-failure` | When a fixer (end-of-file-fixer, ruff-format) modifies files, the job fails *and* prints the diff, so the developer sees what to fix without re-running locally |
| `needs: []` | Starts immediately, doesn't wait for a previous stage |
| `SKIP: gitleaks,…` | The gitleaks hook runs `gitleaks git --pre-commit --staged` with `pass_filenames: false` — it scans the index, which is empty in CI. Leaving it in gives a green tick that scanned nothing |
| `git` installed | pre-commit clones hook repos with git; `-slim` images don't have it |

> **Gotcha.** On the Kubernetes executor, `CI_PROJECT_DIR` can differ between jobs if `builds_dir` isn't fixed, and pre-commit's cached virtualenvs contain **absolute paths** — so a restored cache has broken envs and every hook fails with "bad interpreter". pre-commit's own docs call this out. Set a fixed `builds_dir` in the runner config (`[runners.kubernetes]` … `builds_dir = "/builds"`) or accept a rebuild per job.

> **Gotcha.** Hooks with `language: node` (commitlint, markdownlint-cli2) make pre-commit download a Node runtime via nodeenv on first run. That works on a connected runner and fails on an air-gapped one. For air-gapped CI, prefer the `language: python`/`golang` variants shown above, or bake the hook envs into a CI image (`pre-commit install-hooks` at image build time with `PRE_COMMIT_HOME` set).

Changed-files mode, for MR pipelines on a large repo (the hygiene hooks are fast enough to always run on all files; this is for when the linters aren't):

```bash
pre-commit run --from-ref "$CI_MERGE_REQUEST_DIFF_BASE_SHA" --to-ref "$CI_COMMIT_SHA" \
  --show-diff-on-failure
```

That needs the base SHA present in the clone; with a shallow clone you may need `git fetch --depth=100 origin "$CI_MERGE_REQUEST_TARGET_BRANCH_NAME"` first. See the philosophy chapter for why changed-files mode needs a scheduled full run behind it.

### lefthook: the alternative

lefthook is a single Go binary. It doesn't manage tool installation — it runs commands you already have — and it runs jobs in parallel.

**Tiebreaker: choose lefthook when the tools are already provisioned by the project's own toolchain** (npm, uv, mise, a devcontainer) and you want parallel execution with no second package manager. That's typical of a JS/TS monorepo where everything is in `node_modules` anyway. Choose pre-commit when you need the framework to install standalone binaries (shellcheck, hadolint, gitleaks) for contributors, or when you want the exact same pinned hook set in CI.

Current version: lefthook 2.1.14 (GitHub releases API).

```yaml
# lefthook.yml
output:
  - summary
  - failure

pre-commit:
  parallel: true
  jobs:
    - name: ruff
      glob: "*.{py,pyi}"
      run: uv run --frozen ruff check --fix --force-exclude {staged_files} && uv run --frozen ruff format --force-exclude {staged_files}
      stage_fixed: true

    - name: eslint
      glob: "*.{ts,tsx,js,mjs,cjs}"
      run: npx --no-install eslint --max-warnings 0 --fix {staged_files}
      stage_fixed: true

    - name: prettier
      glob: "*.{json,md,yaml,yml,css}"
      run: npx --no-install prettier --write --ignore-unknown {staged_files}
      stage_fixed: true

    - name: shellcheck
      glob: "*.{sh,bash}"
      run: shellcheck {staged_files}

    - name: shfmt
      glob: "*.{sh,bash}"
      run: shfmt -w {staged_files}
      stage_fixed: true

    - name: hadolint
      glob: "{Dockerfile,Containerfile,*.Dockerfile}"
      run: hadolint {staged_files}

    - name: gitleaks
      run: gitleaks git --pre-commit --staged --redact --no-banner

commit-msg:
  jobs:
    - name: conventional-commit
      run: uv run --frozen cz check --commit-msg-file {1}

pre-push:
  jobs:
    - name: mypy
      run: uv run --frozen mypy
    - name: typecheck
      run: npx --no-install tsc --noEmit
```

```bash
lefthook install                          # writes .git/hooks/* shims
lefthook run pre-commit                   # run the hook's jobs manually
lefthook run pre-commit --all-files       # against every file matching each glob
lefthook validate                         # check the config
LEFTHOOK_EXCLUDE=eslint git commit …      # skip one job
```

| Feature | What it does |
|---|---|
| `{staged_files}` | Replaced with the staged files matching `glob` |
| `stage_fixed: true` | Re-stages files the job modified (formatters), so the fix lands in the commit |
| `parallel: true` | Runs jobs concurrently — the main speed win over pre-commit's serial default |
| `{1}` in `commit-msg` | The first hook argument: the message file path |
| `lefthook-local.yml` | Per-developer overrides, gitignored |

> **Version-sensitive.** lefthook 2.0 (October 2025) removed `skip_output` in favour of `output`, made `exclude` glob-only (no regex), switched the executor for `only`/`skip` `run:` conditions to `sh`, and renamed some CLI flags. The `jobs:` list syntax used above arrived in 1.10; older configs use a `commands:` map, which still works. Check `lefthook run -h` for your version's flags.

> **Gotcha.** `stage_fixed` on a partially staged file stages the *whole* file, including hunks you deliberately left unstaged. pre-commit handles this more carefully: it stashes unstaged changes before running hooks and restores them after. If your team does `git add -p` a lot, that's a point for pre-commit.

### Secret scanning with gitleaks

Secret scanning is the one lint check with an **irreversible failure mode**. Once a credential is in a pushed commit — in any branch, in any MR, even one closed a minute later — treat it as compromised and rotate it. Rewriting history doesn't un-leak it: forks, clones, CI job logs and GitLab's own MR diff storage may all have it.

> **One-way door.** A pushed secret is public to everyone with read access from that moment. The cost is a rotation (plus an audit of what the credential could reach), not a force-push. Hooks and CI exist to make this rare; the incident process exists because it won't be never.

So gitleaks runs in three places:

| Where | Command | Scans |
|---|---|---|
| pre-commit hook | `gitleaks git --pre-commit --staged --redact` | the staged diff, before the commit exists |
| CI, every MR | `gitleaks git --log-opts="BASE..HEAD"` or GitLab Secret Detection | every commit in the MR (catches `--no-verify`) |
| Scheduled, once / quarterly | `gitleaks git --log-opts="--all"` | full history, all refs |

```bash
gitleaks git -v                                         # scan the whole history of the current repo
gitleaks git --log-opts="origin/main..HEAD" -v          # just this branch's commits
gitleaks git --pre-commit --staged --redact             # what the hook runs
gitleaks dir .                                          # the working tree as files, ignoring git
gitleaks dir --redact path/to/file.env
gitleaks git --report-format json --report-path gitleaks.json --redact
gitleaks git --report-format sarif --report-path gitleaks.sarif
gitleaks git --baseline-path gitleaks-baseline.json     # ignore findings present in an old report
gitleaks git --max-decode-depth 2                       # also find base64/hex/percent-encoded secrets
```

Exit codes: `0` nothing found, `1` leaks found (or an error), `126` unknown flag. `--exit-code N` changes the "found" code.

Current version: gitleaks 8.30.1. The project states it's feature complete and now takes only security fixes.

#### .gitleaks.toml

Extend the default rules; don't replace them.

```toml
# .gitleaks.toml
title = "project gitleaks config"

[extend]
useDefault = true
# disabledRules = ["generic-api-key"]    # only if it's genuinely unusable for you

# An internal token format the default rules don't know about.
[[rules]]
id = "internal-service-token"
description = "Internal service token"
regex = '''\bsvc_[a-z0-9]{32}\b'''
keywords = ["svc_"]
entropy = 3.5

# Global allowlist: paths that are never real secrets.
[[allowlists]]
description = "Test fixtures and lockfiles"
paths = [
  '''(^|/)testdata/''',
  '''(^|/)tests/fixtures/''',
  '''(^|/)(package-lock\.json|pnpm-lock\.yaml|uv\.lock|go\.sum)$''',
]

# Known dummy values used in docs and examples.
[[allowlists]]
description = "Documented placeholder values"
regexTarget = "match"
regexes = [
  '''EXAMPLE[A-Z0-9]{8,}''',
  '''changeme''',
]

# Scoped allowlist: only applies to these rules (gitleaks 8.25+).
[[allowlists]]
targetRules = ["generic-api-key"]
description = "Helm values placeholders"
paths = ['''charts/.*/values\.yaml$''']
stopwords = ["placeholder", "REPLACE_ME"]
```

> **Version-sensitive.** `[[allowlists]]` (plural, an array of tables) and `targetRules` arrived in gitleaks 8.25.0. Older configs use a single `[allowlist]` table, which still works. Don't mix both styles in one file.

#### Suppressing a single finding

Three mechanisms, from most to least preferred:

1. **Fix it.** If it's a real secret, rotate it and remove it. If it's a test value, make it obviously fake so the default rules don't match (`AKIAEXAMPLE…` in the allowlist regex above).
2. **Inline `gitleaks:allow`** on the line — visible in review, travels with the code:

   ```python
   TEST_TOKEN = "ghp_0000000000000000000000000000000000"  # gitleaks:allow -- fake token for parser tests
   ```

3. **`.gitleaksignore`** with the finding's fingerprint, for findings in history you can't change:

   ```text
   418edf165dbb63d6f46993ae8f8818ffd87ea582:tests/fixtures/jwt.txt:jwt:17
   ```

   The format is `COMMIT:FILE:RULE_ID:LINE` for git scans (`FILE:RULE_ID:LINE` for `dir` scans), and it's copied straight from the `Fingerprint` field of a JSON report.

#### Adopting gitleaks on an old repo: baseline

A 10-year-old repo will have findings in history — mostly revoked keys and test data. Don't block adoption on triaging all of them:

```bash
gitleaks git --report-format json --report-path gitleaks-baseline.json --redact
git add gitleaks-baseline.json
# From now on, only new findings fail:
gitleaks git --baseline-path gitleaks-baseline.json --redact
```

Then triage the baseline once: rotate anything that might still be live, and move the rest into `.gitleaksignore` with a note. A baseline is a debt register, not an amnesty.

> **Gotcha.** Always run with `--redact` in CI. Without it, gitleaks prints the secret it found into the job log — which is retained, readable by every Developer on the project, and often shipped to a log aggregator. The scanner becomes the leak.

> **Note.** GitLab has server-side options too. **Pipeline Secret Detection** (`Jobs/Secret-Detection.gitlab-ci.yml`, gitleaks under the hood, all tiers for the scan; MR widget and vulnerability management on Ultimate) is covered in the ci-reporting chapter. **Secret push protection** (Ultimate) rejects the push itself, which is the only mechanism that stops a secret before it reaches the server even when the developer has no hooks installed.

### Commit messages: Conventional Commits

**Default: Conventional Commits, checked by commitizen (`cz check`).** Reason: structured messages let the release tooling compute the next semver bump and the changelog mechanically (the merge-policy chapter's git-cliff release flow depends on it), and commitizen is a Python tool with a `language: python` hook — no Node runtime needed in your hooks or CI. This chapter uses commitizen only as the **checker**; releasing is git-cliff's job (the merge-policy chapter).

**Tiebreaker: commitlint** if the repo is already a Node project and you'd rather have one ecosystem; it has a larger plugin ecosystem for custom rules.

The format:

```text
<type>(<optional scope>)!: <description>

[optional body]

[optional footer(s)]
BREAKING CHANGE: <what breaks and how to migrate>
Refs: PLAT-123
```

| Type | Semver effect | Use for |
|---|---|---|
| `feat` | minor | user-visible new capability |
| `fix` | patch | user-visible bug fix |
| `perf` | patch | performance improvement |
| `refactor`, `style`, `test`, `docs`, `build`, `ci`, `chore` | none | everything else |
| `!` after type/scope, or `BREAKING CHANGE:` footer | **major** | incompatible change |

#### commitizen config

For checking, commitizen needs almost nothing — the conventional-commits rules are built in:

```toml
# pyproject.toml (or .cz.toml in a non-Python repo)
[tool.commitizen]
name = "cz_conventional_commits"
tag_format = "v$version"
version_provider = "scm"           # version comes from git tags; nothing is written to files
major_version_zero = true          # while < 1.0.0, breaking changes bump minor
```

`tag_format` and `version_provider` only matter for `cz bump`, which this guide doesn't use for releases; they're set so that `cz bump --dry-run` gives the same answer as git-cliff's `--bumped-version` — a useful cross-check in review.

```bash
cz commit                                      # interactive prompt that writes a valid message
cz check --commit-msg-file .git/COMMIT_EDITMSG # what the commit-msg hook runs
cz check --rev-range origin/main..HEAD         # every commit on this branch — CI
cz check --message "feat(api): add pagination" # a single string — for MR titles
cz bump --dry-run                              # preview only: what the next version would be
```

#### commitlint config (the alternative)

```javascript
// commitlint.config.mjs
export default {
  extends: ["@commitlint/config-conventional"],
  rules: {
    "scope-enum": [2, "always", ["api", "ui", "chart", "ci", "deps"]],
    "subject-case": [2, "never", ["start-case", "pascal-case", "upper-case"]],
    "header-max-length": [2, "always", 100],
  },
};
```

```yaml
  - repo: https://github.com/alessandrojcm/commitlint-pre-commit-hook
    rev: 1f1ac45c93d1c2ce36b71330252c489a5f4f2724  # frozen: v9.27.0
    hooks:
      - id: commitlint
        stages: [commit-msg]
        additional_dependencies: ["@commitlint/config-conventional"]
```

#### Which message actually matters: squash vs merge

This depends on your merge method (the merge-policy chapter), and getting it wrong means linting the wrong thing:

| Merge method | What lands on `main` | What to lint in CI |
|---|---|---|
| Squash on merge | **One commit whose message defaults to the MR title** (configurable in the project's squash commit template) | **The MR title** — `cz check --message "$CI_MERGE_REQUEST_TITLE"` |
| Merge commit / semi-linear, no squash | Every branch commit plus a merge commit | Every commit: `cz check --rev-range "$CI_MERGE_REQUEST_DIFF_BASE_SHA..$CI_COMMIT_SHA"` |
| Fast-forward, no squash | Every branch commit | Every commit, as above |

If you squash, the individual `wip`/`fix typo` commits on the branch are thrown away, and forcing Conventional Commits on each of them is pure friction. **Lint the MR title instead** — it's what becomes the changelog entry.

```yaml
lint:mr-title:
  stage: lint
  image: python:3.13-slim
  needs: []
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  script:
    - pip install --quiet commitizen==4.19.0
    - cz check --message "$CI_MERGE_REQUEST_TITLE"
```

> **Gotcha.** Editing the MR title doesn't trigger a new pipeline. A developer who fixes the title after a red `lint:mr-title` job must re-run the job (or push). Put the fix instruction in the job's `after_script` so it's obvious.

> **Note.** GitLab also has a project-level push rule, **"Commit message regex"** (Premium), enforced server-side on every push. It's a blunt regex, not a parser, but it can't be bypassed with `--no-verify`. Use it as a backstop if the commit messages (not MR titles) are what you release from.

#### A branch-name ticket prefix (prepare-commit-msg)

Optional, but popular with Jira: pull `PLAT-123` out of `feat/PLAT-123-pagination` into a `Refs:` footer automatically.

```bash
#!/usr/bin/env bash
# .githooks/prepare-commit-msg — install via pre-commit `repo: local` with stages: [prepare-commit-msg]
set -euo pipefail
msg_file="$1"
source="${2:-}"
[[ "$source" == "merge" || "$source" == "squash" ]] && exit 0
branch="$(git symbolic-ref --short -q HEAD || true)"
if [[ "$branch" =~ ([A-Z][A-Z0-9]+-[0-9]+) ]]; then
  ticket="${BASH_REMATCH[1]}"
  grep -q "Refs: $ticket" "$msg_file" || printf '\nRefs: %s\n' "$ticket" >>"$msg_file"
fi
```

### Traps

- **Missing `default_install_hook_types`.** `commit-msg` and `pre-push` hooks are defined but never installed.
- **Slow hooks.** Over ~3 s and people learn `--no-verify`, which also skips the secret scan. Move type checks to `pre-push`.
- **Two version pins for one tool.** pre-commit `rev:` vs lockfile. Use `repo: local` for toolchain tools.
- **Tag-pinned revs.** Tags move. `autoupdate --freeze`, and let Renovate bump.
- **mypy mirror without `additional_dependencies`.** Isolated env, no imports, wall of errors. Or run it as a local hook.
- **`PRE_COMMIT_HOME` outside `CI_PROJECT_DIR`.** Never cached, every pipeline rebuilds every env.
- **gitleaks hook in CI.** Scans the (empty) index and passes. Run a real range scan as its own job.
- **gitleaks without `--redact` in CI.** The job log becomes the leak.
- **Rewriting history to "remove" a pushed secret.** Rotate first. History rewriting is cleanup, not remediation.
- **Linting branch commits when you squash.** Lint the MR title.
- **`core.hooksPath` set somewhere.** `pre-commit install` refuses; find it with `git config --show-origin`.
- **`stage_fixed` with partial staging (lefthook).** Stages the whole file.
- **Node-language hooks on air-gapped runners.** nodeenv can't download Node. Bake hook envs into the image.


---


<a id="05-wiring-linters-into-gitlab-ci"></a>

## 05 · Wiring linters into GitLab CI

*A lint job has exactly two duties: exit non-zero when the tool found something, and leave behind a report GitLab can put in front of the reviewer. Most broken lint jobs fail the first one silently.*

### Jobs that fail correctly

A lint job is correct when **its exit status is the tool's exit status**. Everything in this section is about the ways that link gets broken.

#### How the runner runs your script

For the bash and sh shells, GitLab Runner concatenates your `before_script` and `script` lines into one generated shell script and runs it with errexit on — the runner's bash writer emits `set -o pipefail` (only if the shell reports supporting it) followed by `set -o errexit` ([`shells/bash.go`](https://gitlab.com/gitlab-org/gitlab-runner/-/blob/main/shells/bash.go)). So by default:

- Any `script:` line that exits non-zero fails the job immediately.
- A failing command in a pipeline (`ruff check | tee out.txt`) fails the job, because of `pipefail`.
- `after_script` runs in a **separate shell**, and its failures never fail the job.

```yaml
# Prove your runner's semantics once, on a throwaway branch.
shell-semantics:
  image: bash:5
  script:
    - 'echo "shell flags: $-"'
    - false | tee /dev/null      # should fail the job if pipefail is on
    - echo "UNREACHABLE if pipefail is on"
```

What errexit does **not** catch — each of these is a lint job that passes when the tool failed:

| Pattern | Why it passes | Fix |
|---|---|---|
| `ruff check . \|\| true` | Explicitly discards the status | Delete `\|\| true`. If you need to run something after, capture `rc` (below) |
| `ruff check . ; echo done` inside a `- \|` block, with errexit off | Only the last command's status counts | Keep errexit on; don't `set +e` without restoring |
| `ruff check . && echo ok` | A failing left side of `&&` doesn't trigger errexit | Separate lines |
| `if ruff check .; then …; fi` | Commands in an `if` condition are exempt from errexit | Handle the `else` branch with `exit 1` |
| `local out=$(ruff check .)` in a script function | `local` returns 0 and masks the substitution (SC2155) | `local out; out=$(…)` |
| `ruff check . > report.json` then `cat report.json` | Fine — but people then add `\|\| true` to "make sure the report is uploaded" | Use `artifacts:when: always` instead |
| `allow_failure: true` | Job fails, pipeline passes, MR merges | Remove it, or scope it: `allow_failure: exit_codes: [N]` |
| Script in a `sh` image where `pipefail` isn't supported | Old busybox/dash: pipeline status is the last command's | Use a bash image, or avoid pipes |

> **Gotcha.** `script: - |` multi-line blocks run in the same shell as the rest, so errexit applies inside them — but anything you write as `cmd1 && cmd2`, `cmd || fallback` or inside `if` is exempt. The fact that the block is YAML doesn't change bash's rules; shellcheck just can't see it to warn you. Put non-trivial logic in `ci/*.sh` with `set -euo pipefail` at the top, where shellcheck can.

#### The capture-convert-exit pattern

Most linters need to do two things with one run: print human-readable output to the job log, and write a machine-readable report. When the tool can't do both at once, capture the exit code, produce the report, then exit with the captured code:

```bash
#!/usr/bin/env bash
# ci/lint-mypy.sh
set -euo pipefail

rc=0
uv run mypy --no-error-summary > mypy-out.txt || rc=$?   # capture, don't discard
cat mypy-out.txt                                          # human output in the log
uv run mypy-gitlab-code-quality < mypy-out.txt > gl-cq-mypy.json
exit "$rc"                                                # the tool's verdict, unchanged
```

`cmd || rc=$?` is the *correct* use of `||` in a lint job: it records the failure instead of swallowing it, and the last line re-raises it.

> **Note.** Some tools use exit codes to mean different things. mypy: `1` type errors, `2` crash/usage error. yamllint: `1` errors, `2` warnings under `--strict`. gitleaks: `1` leaks, `126` bad flag. If you want "warnings don't block", use `allow_failure: exit_codes: [2]` — it's precise, visible in the MR as a warning, and still fails on real errors.

#### Reports must upload on failure

The report matters most when the job fails. By default, artifacts are uploaded only on success.

```yaml
  artifacts:
    when: always          # upload reports from failed jobs too — the default is on_success
    expire_in: 1 week
    reports:
      codequality: gl-cq-*.json
      junit: junit-*.xml
```

Without `when: always`, a failing lint job shows a red X and **no findings in the MR widget** — which is exactly when the reviewer needed them.

#### A lint job template

```yaml
# .gitlab/ci/lint.yml
.lint:
  stage: lint
  needs: []                  # don't wait for earlier stages; start immediately
  interruptible: true        # a newer push cancels this — lint results for old commits are worthless
  timeout: 10m               # a hung linter shouldn't hold a runner for the default hour
  artifacts:
    when: always
    expire_in: 1 week
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_COMMIT_TAG
```

Every lint job `extends: .lint`. The `rules:` above assume the workflow-level rules that prevent duplicate branch + MR pipelines (the ci-anatomy chapter).

### Running only on changed files

Two different things get called "only on changed files", and they have different traps:

1. **Job-level:** don't run the Go lint job at all if no Go file changed — `rules:changes`.
2. **File-level:** run the job, but pass only changed files to the tool — a `git diff` inside the script.

#### rules:changes

```yaml
lint:go:
  extends: .lint
  image: golangci/golangci-lint:v2.13.2-alpine
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes:
        paths:
          - "**/*.go"
          - go.mod
          - go.sum
          - .golangci.yml            # config change must re-lint everything
          - .gitlab/ci/lint.yml      # so must a change to the job itself
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH    # always on main: the baseline for widgets
  script:
    - golangci-lint run ./...
```

What `changes` compares against depends on the pipeline type — this is the part that bites:

| Pipeline type | `changes` compares | Consequence |
|---|---|---|
| **Merge request pipeline** | MR source branch vs **target branch** (the MR diff) | What you want: the job runs if the MR touches those paths at all, across all its commits |
| **Branch pipeline, existing branch** | This push vs the **previous push** to the branch | A push of only a README change skips the job, even though earlier commits on the branch touched Go. Passing only because the relevant job didn't run this time |
| **Branch pipeline, new branch / first push** | Nothing to compare with | **Always true** |
| **Tag, scheduled, web/API-triggered, pipelines without a push event** | Nothing to compare with | **Always true** (documented) |
| With `changes:compare_to: refs/heads/main` | This ref vs `main` | Makes branch pipelines behave like MR pipelines |

The rules that fall out:

- **Use `rules:changes` in MR pipelines**, where the comparison is the MR diff and therefore meaningful.
- **Don't combine `rules:changes` with branch pipelines** unless you add `compare_to`. The push-to-push comparison produces "the job didn't run, so the MR is green" for reasons unrelated to correctness.
- **Always run unconditionally on the default branch.** It's the baseline for the Code Quality widget and the backstop for anything changed-files mode missed.
- **List config files in `changes`**: the linter config, the lockfile, and the CI file that defines the job. A ruff version bump in `uv.lock` changes the findings in files nobody touched.

```yaml
# Branch pipelines that behave like MR pipelines
    - if: $CI_COMMIT_BRANCH && $CI_COMMIT_BRANCH != $CI_DEFAULT_BRANCH
      changes:
        paths: ["**/*.go"]
        compare_to: refs/heads/main
```

> **Gotcha.** A job skipped by `rules:changes` doesn't exist in the pipeline. Any job with `needs: [lint:go]` then fails pipeline creation with "`needs` job not in pipeline" — or, in the worse case, you drop the `needs` and a later job runs without the check. Use `needs: [{job: lint:go, optional: true}]`.

> **Gotcha.** "Pipelines must succeed" is satisfied by a pipeline in which the relevant job never ran. If the only Go lint job is `rules:changes`-gated and the change-detection is wrong (branch pipeline without `compare_to`, a new file type not in `paths`), the MR merges unlinted with a green badge. This is why the default-branch run is unconditional.

> **Version-sensitive.** `rules:changes:paths` and `rules:changes:compare_to` are the current syntax (a bare list under `changes:` still works and means `paths`). `compare_to` appeared in GitLab 15.3; older self-hosted instances ignore it.

#### File-level: pass only changed files

For tools that are per-file (ruff, ESLint, shellcheck, hadolint, yamllint) on a repo large enough that a full run hurts. **Never for type checkers** (the philosophy chapter).

```bash
#!/usr/bin/env bash
# ci/changed-files.sh — print files changed in this MR, NUL-separated, filtered by extension regex
set -euo pipefail
pattern="${1:?usage: changed-files.sh REGEX}"

if [[ -n "${CI_MERGE_REQUEST_DIFF_BASE_SHA:-}" ]]; then
  base="$CI_MERGE_REQUEST_DIFF_BASE_SHA"
  # Shallow clones may not contain the merge base.
  git cat-file -e "$base^{commit}" 2>/dev/null \
    || git fetch --quiet --depth=200 origin "$CI_MERGE_REQUEST_TARGET_BRANCH_NAME"
  git diff --name-only -z --diff-filter=ACMR "$base" "$CI_COMMIT_SHA" \
    | grep -zE "$pattern" || true
else
  # Not an MR pipeline: lint everything.
  git ls-files -z | grep -zE "$pattern" || true
fi
```

```yaml
lint:shell:
  extends: .lint
  image: koalaman/shellcheck-alpine:v0.11.0
  script:
    - apk add --no-cache bash git grep >/dev/null   # GNU grep for -z
    - ci/changed-files.sh '\.(sh|bash)$' | xargs -0 -r shellcheck -f gcc
```

| Detail | Why |
|---|---|
| `CI_MERGE_REQUEST_DIFF_BASE_SHA` | The merge base GitLab computed for the MR diff — the same set of files the reviewer sees |
| `--diff-filter=ACMR` | Added, copied, modified, renamed — excludes deleted files, which would make the linter error on a missing path |
| `-z` / `xargs -0` | Filenames with spaces |
| `-r` (`--no-run-if-empty`) | Otherwise xargs runs `shellcheck` with no args when nothing changed, which errors. Busybox xargs accepts `-r` but not the GNU long option |
| `\|\| true` after `grep` | **The one legitimate use:** `grep` exits 1 when nothing matches, which means "no files changed", not "lint failed". It's on the file-list step, never on the linter |

> **Gotcha.** The merge base is often deeper than `GIT_DEPTH` (20 by default on current GitLab). Without the fetch, `git diff` fails with "bad object", and if someone "fixes" that with `2>/dev/null || true`, the file list is empty and every lint job passes. The `git cat-file -e` check fetches only when needed.

### GitLab Code Quality reports

Code Quality puts linter findings into the MR: a report listing findings **introduced** and **resolved** by the MR (in current GitLab it sits in the MR **Reports** tab), and (on Ultimate) markers in the diff gutter.

| Surface | Tier |
|---|---|
| MR widget (new/resolved findings) | Free |
| Pipeline "Code Quality" tab | Premium |
| Diff annotations in the Changes view | Ultimate |

> **Version-sensitive.** The old CodeClimate-based `Code-Quality.gitlab-ci.yml` template (Docker-in-Docker, runs CodeClimate engines) was deprecated in GitLab 17.3 and is planned for removal in 19.0. **Don't adopt it.** Produce reports from your own linters, which is what everything below does.

#### The report format

A JSON array of findings. Required fields, per the GitLab docs:

```json
[
  {
    "description": "F401 `os` imported but unused",
    "check_name": "F401",
    "fingerprint": "7815696ecbf1c96e6894b779456d330e",
    "severity": "minor",
    "location": {
      "path": "src/app/main.py",
      "lines": { "begin": 3 }
    }
  }
]
```

| Field | Rule |
|---|---|
| `description` | Human-readable message |
| `check_name` | Rule ID |
| `fingerprint` | Unique and **stable** per finding. GitLab diffs the MR's report against the base's by fingerprint — an unstable fingerprint makes every finding look new |
| `severity` | `info`, `minor`, `major`, `critical`, `blocker` |
| `location.path` | **Relative to the repository root.** Absolute paths or paths relative to a subdirectory don't map onto the diff |
| `location.lines.begin` | Line number (or `location.positions.begin.line`) |

**Multiple jobs can each upload a `codequality` report; GitLab merges them.** One job per linter is fine.

> **Gotcha.** The widget compares the MR pipeline's report against the **target branch's latest pipeline** report. If lint jobs run only in MR pipelines, there's no base report and the widget can't show "introduced vs resolved" properly. **Run lint jobs on the default branch too** — this is the non-obvious reason for the `$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH` rule in `.lint`.

#### Tool by tool

| Tool | Native Code Quality output | Command |
|---|---|---|
| ruff | yes | `ruff check --output-format=gitlab --output-file=gl-cq-ruff.json .` |
| ruff format | yes (0.16+) | `ruff format --check --output-format=gitlab` |
| ESLint | via `eslint-formatter-gitlab` | `eslint --format gitlab .` with `ESLINT_CODE_QUALITY_REPORT` |
| Biome | yes | `biome ci --reporter=gitlab --reporter-file=gl-cq-biome.json .` |
| golangci-lint v2 | yes | `--output.code-climate.path=gl-cq-go.json` or `output.formats.code-climate` |
| mypy | via `mypy-gitlab-code-quality` | text output piped through the converter |
| markdownlint-cli2 | via `markdownlint-cli2-formatter-codequality` | `outputFormatters` in `.markdownlint-cli2.jsonc` |
| hadolint | yes | `hadolint -f gitlab_codeclimate Dockerfile` |
| Trivy config | via bundled template | `--format template --template "@/contrib/gitlab-codequality.tpl"` |
| shellcheck | no | `-f json1` + jq (below) |
| yamllint | no | `-f parsable` + a small converter (below) |
| Flake8 / Pylint | via plugins | `flake8-gl-codeclimate`, `pylint-gitlab` (legacy stacks) |

(The native-support list is from the GitLab Code Quality docs; Biome and hadolint from their own docs.)

#### Python reports

```yaml
lint:python:
  extends: .lint
  image: ghcr.io/astral-sh/uv:python3.13-bookworm-slim
  variables:
    UV_CACHE_DIR: ${CI_PROJECT_DIR}/.cache/uv
    RUFF_CACHE_DIR: ${CI_PROJECT_DIR}/.cache/ruff
  cache:
    - key:
        files: [uv.lock]
        prefix: uv
      paths: [.cache/uv]
    - key: ruff-$CI_COMMIT_REF_SLUG
      fallback_keys: [ruff-$CI_DEFAULT_BRANCH]
      paths: [.cache/ruff]
  script:
    - uv sync --frozen --only-group dev
    - rc=0
    - uv run ruff check --output-format=gitlab --output-file=gl-cq-ruff.json . || rc=$?
    - uv run ruff format --check --output-format=gitlab --output-file=gl-cq-ruff-format.json . || rc=$?
    - uv run ruff check --output-format=concise . || true   # human-readable log only; verdict is $rc
    - exit $rc
  artifacts:
    reports:
      codequality: gl-cq-ruff*.json
```

> **Note.** The `|| true` on the third ruff line is display-only — the verdict was already captured in `rc` from the two gating runs, and `exit $rc` raises it. If you find that too subtle for your team, move the script into `ci/lint-python.sh` with a comment. Ruff with a warm cache makes the extra run nearly free.

> **Version-sensitive.** `ruff format --check --output-format` arrived in ruff 0.16. On older versions, `ruff format --check --diff` is the gate and there's no formatter report.

> **Gotcha.** Ruff writes paths relative to the working directory. Run it from the repo root (the default `CI_PROJECT_DIR`) so paths are repo-relative. In a monorepo job that does `cd services/api`, the paths lose their `services/api/` prefix and the widget can't place them.

```yaml
typecheck:python:
  extends: .lint
  image: ghcr.io/astral-sh/uv:python3.13-bookworm-slim
  variables:
    UV_CACHE_DIR: ${CI_PROJECT_DIR}/.cache/uv
  cache:
    - key:
        files: [uv.lock]
        prefix: uv
      paths: [.cache/uv]
    - key:
        files: [uv.lock, pyproject.toml]    # mypy version + config; max 2 files per key
        prefix: mypy
      paths: [.mypy_cache]
  script:
    - uv sync --frozen
    - uv pip install mypy-gitlab-code-quality
    - bash ci/lint-mypy.sh                   # the capture-convert-exit script above
  artifacts:
    reports:
      codequality: gl-cq-mypy.json
```

#### JS and TS reports

```yaml
lint:js:
  extends: .lint
  image: node:22-bookworm-slim
  variables:
    npm_config_cache: ${CI_PROJECT_DIR}/.cache/npm
    ESLINT_CODE_QUALITY_REPORT: gl-cq-eslint.json
  cache:
    - key:
        files: [package-lock.json]
        prefix: npm
      paths: [.cache/npm]
    - key: eslint-$CI_COMMIT_REF_SLUG
      fallback_keys: [eslint-$CI_DEFAULT_BRANCH]
      paths: [.cache/eslint/, .cache/tsbuildinfo]
  script:
    - npm ci --prefer-offline --no-audit
    - rc=0
    - npx prettier --check . || rc=$?
    - >
      npx eslint . --max-warnings 0 --format gitlab
      --cache --cache-location .cache/eslint/ --cache-strategy content
      || rc=$?
    - npx tsc --noEmit --incremental --tsBuildInfoFile .cache/tsbuildinfo || rc=$?
    - exit $rc
  artifacts:
    reports:
      codequality: gl-cq-eslint.json
```

| Detail | Why |
|---|---|
| `eslint-formatter-gitlab` (devDependency) | Provides `--format gitlab`; writes the report to `ESLINT_CODE_QUALITY_REPORT` and still prints findings to the log |
| `--cache-strategy content` | ESLint's default cache strategy is file **mtime**. A fresh CI checkout gives every file a new mtime, so an mtime cache never hits. `content` hashes files instead |
| `--cache-location .cache/eslint/` | Trailing slash = directory; inside `CI_PROJECT_DIR` so GitLab can cache it |
| `rc` accumulation | All three checks run and report even if the first fails — one pipeline tells you everything |

> **Gotcha.** ESLint's cache doesn't track type information changes in *other* files. With typed rules, a change in `types.ts` can create a finding in an unchanged, cached `handler.ts` that the cache hides. The cache is safe for a fast MR loop; the default-branch pipeline should run **without** `--cache` (or with a cache key that changes on every commit) to catch this.

#### Go reports

```yaml
lint:go:
  extends: .lint
  image: golangci/golangci-lint:v2.13.2-alpine   # pin by digest in real use
  variables:
    GOPATH: ${CI_PROJECT_DIR}/.cache/go
    GOCACHE: ${CI_PROJECT_DIR}/.cache/go-build
    GOLANGCI_LINT_CACHE: ${CI_PROJECT_DIR}/.cache/golangci-lint
  cache:
    - key:
        files: [go.sum]
        prefix: gomod
      paths: [.cache/go/pkg/mod]
    - key: golangci-$CI_COMMIT_REF_SLUG
      fallback_keys: [golangci-$CI_DEFAULT_BRANCH]
      paths: [.cache/go-build, .cache/golangci-lint]
  script:
    - golangci-lint run ./...          # formats configured in .golangci.yml: text to stdout + code-climate file
  artifacts:
    reports:
      codequality: gl-code-quality-report.json
```

golangci-lint v2 writes several formats in one run (configured in `output.formats` — the languages chapter), so no capture-convert dance. For a module in a subdirectory, set `output.path-prefix: services/api` in `.golangci.yml` so report paths are repo-relative.

#### Docker and Markdown reports

```yaml
lint:docker:
  extends: .lint
  image: hadolint/hadolint:v2.15.1-alpine      # pin by digest in real use
  script:
    - |
      find . \( -name '*Dockerfile*' -o -name '*Containerfile*' \) \
        -not -path './vendor/*' -not -path './node_modules/*' -type f > dockerfiles.txt
    - rc=0
    - xargs hadolint < dockerfiles.txt || rc=$?
    - xargs hadolint -f gitlab_codeclimate < dockerfiles.txt > gl-cq-hadolint.json || true   # report only
    - exit $rc
  artifacts:
    reports:
      codequality: gl-cq-hadolint.json
```

> **Note.** The alpine variant of the hadolint image is the one with a shell (the default image is a bare binary), but it has no `git` — hence `find` rather than `git ls-files`. The report line ends in `|| true` because the verdict was already captured in `rc` by the line above; the second run exists only to produce the artefact.

```yaml
lint:markdown:
  extends: .lint
  image: node:22-bookworm-slim
  script:
    - npm ci --prefer-offline --no-audit    # markdownlint-cli2 + formatter-codequality as devDependencies
    - npx markdownlint-cli2                 # outputFormatters in .markdownlint-cli2.jsonc write the report
  artifacts:
    reports:
      codequality: gl-code-quality-markdown.json
```

#### Converting other formats

shellcheck — `json1` output through jq (verified locally against shellcheck 0.11.0 and jq 1.8.1):

```bash
#!/usr/bin/env bash
# ci/lint-shell.sh
set -euo pipefail
mapfile -d '' files < <(shfmt -f . | tr '\n' '\0')
[[ ${#files[@]} -eq 0 ]] && { echo "no shell files"; echo '[]' > gl-cq-shellcheck.json; exit 0; }

rc=0
shellcheck -f gcc "${files[@]}" || rc=$?

shellcheck -f json1 "${files[@]}" | jq '[.comments[] | {
    description: "SC\(.code): \(.message)",
    check_name:  "SC\(.code)",
    fingerprint: ("\(.file):\(.line):\(.column):\(.code)" | @base64),
    severity:    ({"error":"critical","warning":"major","info":"minor","style":"info"}[.level]),
    location:    {path: .file, lines: {begin: .line}}
  }]' > gl-cq-shellcheck.json || true      # report only; verdict is $rc

exit "$rc"
```

yamllint — `parsable` output through a few lines of Python:

```python
#!/usr/bin/env python3
# ci/yamllint-to-codequality.py  —  yamllint -f parsable . | ci/yamllint-to-codequality.py > gl-cq-yamllint.json
import hashlib, json, re, sys

pat = re.compile(r"^(?P<path>.+?):(?P<line>\d+):(?P<col>\d+): \[(?P<level>\w+)\] (?P<msg>.*?)(?: \((?P<rule>[\w-]+)\))?$")
out = []
for raw in sys.stdin:
    m = pat.match(raw.rstrip("\n"))
    if not m:
        continue
    rule = m["rule"] or "syntax"
    fp = hashlib.md5(f'{m["path"]}:{rule}:{m["msg"]}'.encode()).hexdigest()
    out.append({
        "description": f'{rule}: {m["msg"]}',
        "check_name": f"yamllint/{rule}",
        "fingerprint": fp,
        "severity": "major" if m["level"] == "error" else "minor",
        "location": {"path": m["path"].removeprefix("./"), "lines": {"begin": int(m["line"])}},
    })
json.dump(out, sys.stdout, indent=2)
```

> **Note.** The yamllint fingerprint deliberately omits the line number: a finding that moves down because someone added lines above it keeps its fingerprint, so the widget doesn't report it as "new". The shellcheck one includes line and column for simplicity — fine for small scripts, noisier on big ones. Pick based on how much churn the files see.

### SAST and secret detection templates

GitLab ships analyser jobs as CI templates (and, increasingly, CI/CD components). They're the "deep static analysis" and "secret scanning" rows from the philosophy chapter.

```yaml
include:
  - template: Jobs/SAST.gitlab-ci.yml
  - template: Jobs/Secret-Detection.gitlab-ci.yml

stages: [lint, test, build, deploy]     # the template jobs use stage: test — it must exist

variables:
  SAST_EXCLUDED_PATHS: "spec, test, tests, tmp, vendor, node_modules, **/testdata/**"
  SECURE_LOG_LEVEL: info
```

| Variable | Does |
|---|---|
| `SAST_EXCLUDED_PATHS` | Comma-separated paths/globs the analysers skip |
| `SAST_DISABLED` / `SECRET_DETECTION_DISABLED` | Turn off a whole template's jobs (any non-empty value) |
| `SECRET_DETECTION_HISTORIC_SCAN: "true"` | Scan full history — run once, in a scheduled or manual pipeline, not every MR |
| `SECURE_ANALYZERS_PREFIX` | Registry to pull analyser images from — **set this for air-gapped instances** to your mirror |
| `SECURE_LOG_LEVEL` | Analyser log verbosity |

Customising a template job — override by redefining the job name (merged with the template's definition):

```yaml
semgrep-sast:
  interruptible: true
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

secret_detection:
  interruptible: true
  needs: []
```

| Capability | Free | Ultimate |
|---|---|---|
| Run SAST / secret detection, JSON report artefact | yes | yes |
| MR security widget, vulnerability report, dismissal workflow | — | yes |
| Custom secret detection rulesets (`.gitlab/secret-detection-ruleset.toml`) | — | yes |
| Secret push protection (server-side reject) | — | yes |

On Free, the analysers run and produce `gl-sast-report.json` / `gl-secret-detection-report.json` as artefacts, but **nothing fails the pipeline and nothing appears in the MR**. The findings exist, and nobody looks at them. If you're on Free and want a gate, run gitleaks yourself:

```yaml
secrets:gitleaks:
  extends: .lint
  image: zricethezav/gitleaks:v8.30.1        # pin by digest in real use
  variables:
    GIT_DEPTH: 0                             # full history of the MR range
  script:
    - |
      if [ -n "${CI_MERGE_REQUEST_DIFF_BASE_SHA:-}" ]; then
        range="${CI_MERGE_REQUEST_DIFF_BASE_SHA}..${CI_COMMIT_SHA}"
      else
        range="${CI_COMMIT_BEFORE_SHA}..${CI_COMMIT_SHA}"
      fi
      case "$range" in 0000000000000000000000000000000000000000..*) range="-1 $CI_COMMIT_SHA" ;; esac
      gitleaks git --redact --no-banner -v \
        --log-opts="$range" \
        --report-format junit --report-path junit-gitleaks.xml
  artifacts:
    reports:
      junit: junit-gitleaks.xml
```

The range logic: MR pipelines scan the MR's commits; branch pipelines scan the pushed range; a new branch (where `CI_COMMIT_BEFORE_SHA` is all zeros) scans just the head commit. JUnit output makes findings appear in the MR test widget on any tier.

> **Version-sensitive.** GitLab is moving security scanning from templates to CI/CD components (`include: component: $CI_SERVER_FQDN/components/sast/sast@VERSION` and similar). On a self-hosted instance, components exist only if someone has mirrored the `components/*` projects into your instance's catalog. Check `Explore → CI/CD Catalog` before switching; the templates remain the portable option.

> **Gotcha.** The template jobs have their own `rules:` — including branch-pipeline rules. Combined with your MR-pipeline workflow, you can get duplicate SAST jobs or none at all. After including a template, run `glab ci lint --dry-run --ref main --include-jobs` and look at the actual job list (the infra-lint chapter).

### JUnit reports for tests

JUnit XML is the lingua franca for "a list of named checks that passed or failed". GitLab shows it in the MR widget (new failures, fixed tests) and in the pipeline's Tests tab, on all tiers.

```yaml
test:python:
  stage: test
  image: ghcr.io/astral-sh/uv:python3.13-bookworm-slim
  needs: []
  interruptible: true
  script:
    - uv sync --frozen
    - uv run pytest --junitxml=junit-pytest.xml -o junit_family=xunit2
        --cov --cov-report=term --cov-report=xml:coverage.xml
  coverage: '/^TOTAL.+?(\d+(?:\.\d+)?)%$/'
  artifacts:
    when: always
    expire_in: 1 week
    reports:
      junit: junit-pytest.xml
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml
```

| Stack | JUnit | Coverage (Cobertura) |
|---|---|---|
| pytest | `--junitxml=FILE` | `pytest-cov`: `--cov-report=xml:coverage.xml` |
| Go | `gotestsum --junitfile junit-go.xml -- ./...` | `go test -coverprofile=c.out` + `gocover-cobertura < c.out > coverage.xml` |
| Vitest | `--reporter=junit --outputFile=junit-vitest.xml` | `--coverage.reporter=cobertura` |
| Jest | `jest-junit` reporter | `--coverageReporters=cobertura` |
| Helm (ct install) | — | — |
| kubeconform | `-output junit` | — |
| tflint | `--format junit` | — |
| gitleaks | `--report-format junit` | — |
| checkov | `--output junitxml` | — |

Non-test tools that emit JUnit (kubeconform, tflint, gitleaks) are useful precisely because JUnit is shown on every tier: it's the Free-tier way to surface "which manifest failed schema validation" in the MR without opening the job log.

> **Gotcha.** `coverage:` (the regex) and `artifacts:reports:coverage_report` are different features. The regex extracts one percentage from the job log for the MR badge and the coverage-change indicator; the Cobertura report drives line-by-line coverage in the MR diff. You want both, and the regex must match your tool's exact summary line.

> **Gotcha.** Large JUnit files (tens of MB) are truncated or rejected by the MR widget parser. Don't include stdout of passing tests (`-o junit_logging=no` for pytest is the default; keep it).

### MR widgets: what shows where

| Widget | Fed by | Tier |
|---|---|---|
| Code Quality | `artifacts:reports:codequality` | Free (diff annotations: Ultimate) |
| Test summary | `artifacts:reports:junit` | Free |
| Coverage % and change | `coverage:` regex | Free |
| Coverage in diff | `artifacts:reports:coverage_report` | Free |
| Security (SAST, secrets, dependencies, containers) | analyser template reports | Ultimate |
| Terraform plan summary | `artifacts:reports:terraform` | Free |
| Metrics | `artifacts:reports:metrics` | Premium |

> **Note.** Every widget that "compares" (Code Quality, tests, coverage change, metrics) compares against the target branch's latest pipeline. The pattern is always the same: **produce the report on the default branch as well as in MRs**, or the comparison has nothing to compare against.

### Caching linter caches

Linter caches turn a 90-second lint job into a 10-second one. The rules for GitLab caching:

1. **Paths must be inside `CI_PROJECT_DIR`.** Redirect every tool's cache there with its environment variable.
2. **Key on what invalidates the cache.** Dependency caches key on the lockfile (`cache:key:files`, up to two files). Analysis caches key on the branch with a fallback to the default branch.
3. **Separate caches for separate things.** One cache per concern (deps vs lint results), so a lint cache miss doesn't re-download every dependency.

| Tool | Cache location variable / flag | Key on | Notes |
|---|---|---|---|
| ruff | `RUFF_CACHE_DIR` (default `.ruff_cache`) | branch + fallback | Keyed internally by ruff version and settings; stale entries are harmless |
| mypy | `--cache-dir` / `MYPY_CACHE_DIR` (default `.mypy_cache`) | `uv.lock` + `pyproject.toml` | Format changed in 2.0 (SQLite); version-keyed cache avoids loading an incompatible one |
| ESLint | `--cache --cache-location .cache/eslint/ --cache-strategy content` | branch + fallback | `content` strategy is mandatory in CI (mtime never matches) |
| tsc | `--incremental --tsBuildInfoFile .cache/tsbuildinfo` | branch + fallback | |
| golangci-lint | `GOLANGCI_LINT_CACHE` + `GOCACHE` | branch + fallback; `go.sum` for modules | Needs the Go build cache too, or type loading dominates |
| pre-commit | `PRE_COMMIT_HOME` | `.pre-commit-config.yaml` | Absolute paths inside; fixed `builds_dir` on k8s runners (the hooks chapter) |
| uv / pip / npm | `UV_CACHE_DIR`, `PIP_CACHE_DIR`, `npm_config_cache` | the lockfile | |
| tflint | `TFLINT_PLUGIN_DIR` | `.tflint.hcl` | Avoids GitHub rate limits |
| kubeconform | `-cache DIR` | Kubernetes version | Schemas are immutable per version |
| Trivy | `TRIVY_CACHE_DIR` | date (daily) | The vulnerability DB; for IaC, the checks bundle |

The branch-with-fallback pattern, in full:

```yaml
  cache:
    - key: eslint-$CI_COMMIT_REF_SLUG
      fallback_keys:
        - eslint-$CI_DEFAULT_BRANCH
      paths: [.cache/eslint/]
      policy: pull-push
```

A new branch's first pipeline has no cache under its own key, so it pulls `main`'s — warm on the first run.

> **Gotcha.** GitLab keeps separate caches for protected and unprotected branches by default (the `-protected` / `-non_protected` suffix, controlled by the project setting "Use separate caches for protected branches"). So an MR branch can't poison `main`'s cache — but it also means the `fallback_keys` to `main` from an unprotected branch **won't find main's protected cache**. If fallback never hits, this is why. Either accept a cold first run per branch, or have a non-protected job on `main` populate a shared key.

> **Gotcha.** `policy: pull-push` on every MR job means every MR uploads its cache — slow on big caches, and on a busy repo the uploads race. Pull in MR pipelines, pull-push on the default branch, driven by a variable (`cache:policy` accepts a variable from GitLab 16.1):

```yaml
variables:
  CACHE_POLICY: pull

.lint:
  cache:
    - key: eslint-$CI_COMMIT_REF_SLUG
      fallback_keys: [eslint-$CI_DEFAULT_BRANCH]
      paths: [.cache/eslint/]
      policy: $CACHE_POLICY
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      variables:
        CACHE_POLICY: pull-push
```

> **Note.** A cache is an optimisation, never a correctness mechanism. Every job must pass from a cold cache. Test it occasionally with the "Clear runner caches" button on the Pipelines page — a job that only passes warm is a job that fails the day the runner is replaced.

### Putting it together

```text
# .gitlab/ci/lint.yml — included from .gitlab-ci.yml (shape only, not pasteable)
.lint:
  stage: lint
  needs: []
  interruptible: true
  timeout: 10m
  artifacts:
    when: always
    expire_in: 1 week
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_COMMIT_TAG

lint:pre-commit:      { extends: .lint, … }   # hygiene + standalone binaries (the hooks chapter)
lint:python:          { extends: .lint, … }   # ruff check + format, Code Quality
typecheck:python:     { extends: .lint, … }   # mypy, whole program, Code Quality
lint:js:              { extends: .lint, … }   # prettier + eslint + tsc, Code Quality
lint:go:              { extends: .lint, … }   # golangci-lint v2, Code Quality
lint:docker:          { extends: .lint, … }   # hadolint, Code Quality
lint:helm:            { extends: .lint, … }   # helm lint + kubeconform (JUnit) + kube-linter
lint:terraform:       { extends: .lint, … }   # fmt + validate + tflint (JUnit) + trivy config
lint:ci:              { extends: .lint, … }   # check-jsonschema offline; glab ci lint needs a token
lint:mr-title:        { extends: .lint, … }   # cz check on CI_MERGE_REQUEST_TITLE (the hooks chapter)
secrets:gitleaks:     { extends: .lint, … }   # MR range scan, JUnit
```

(Each `…` is that job's body from the sections above.)

Shape decisions embedded in that list:

- **One job per ecosystem, not one "lint" job.** Parallel, independently cacheable, and a red job's name tells you which toolchain failed.
- **All `needs: []`.** The lint stage finishes in the time of the slowest job, not the sum.
- **All `interruptible: true`.** A new push cancels stale lint runs (with `workflow:auto_cancel:on_new_commit: interruptible` — the ci-anatomy chapter).
- **Every job reports.** Code Quality or JUnit, so findings land in the MR, not just the log.

### Traps

- **`|| true` or `allow_failure: true` on a gate.** The job can never fail. Capture `rc` and `exit "$rc"` instead.
- **Reports without `artifacts:when: always`.** Findings vanish exactly when the job fails.
- **Lint jobs only in MR pipelines.** No base report; Code Quality can't diff. Run on the default branch too.
- **`rules:changes` on branch pipelines without `compare_to`.** Compares push-to-push; relevant jobs silently skip.
- **Config files missing from `rules:changes:paths`.** A linter bump or config change doesn't re-lint.
- **`needs:` on a job that `rules:changes` can remove.** Pipeline creation fails. Use `optional: true`.
- **Changed-files mode on a shallow clone.** Merge base missing, empty diff, everything passes. Fetch it.
- **Repo-relative paths.** Reports from a `cd subdir` job don't map onto the diff. Use path prefixes.
- **Unstable fingerprints.** Every finding looks "new" every MR.
- **ESLint cache with mtime strategy.** Never hits in CI. `--cache-strategy content`.
- **Caches outside `CI_PROJECT_DIR`.** Silently not cached. Redirect with the tool's env var.
- **Assuming Free-tier SAST gates anything.** It produces an artefact nobody reads. Gate with your own jobs.
- **Template jobs needing a `test` stage.** Include SAST without `test` in `stages:` and pipeline creation fails.
- **A cache that makes jobs pass.** Clear runner caches occasionally and make sure everything still passes cold.


---


<a id="06-branching-strategies"></a>

## 06 · Branching strategies

*A branching model is a bet on how long code is allowed to live apart from main. Every integration problem you have is the price of that bet, so the winning move is to keep the bet small: short branches, one long-lived trunk, and release branches only when you actually support more than one version.*

### The one number that matters

Every branching strategy is an answer to one question: **how long can a change live away from the trunk before it is integrated?** Merge conflicts, "works on my branch", long code-review queues, big-bang releases and painful hotfixes all scale with that number. Strategies differ mainly in how many long-lived branches they keep and how often they reconcile them.

| Strategy | Long-lived branches | Typical branch life | Release unit | Fits |
|---|---|---|---|---|
| **Trunk-based** | `main` only | hours to 2 days | any green commit on `main` | services you deploy continuously |
| **GitHub flow** | `main` only | days | MR merge = deploy | web apps, single deployed version |
| **GitLab flow (environment)** | `main` + `staging`, `production` | days | promotion by merge | when promotion must be a git event |
| **GitLab flow (release)** | `main` + `release/X.Y` | days | tag on release branch | shipped software, several supported versions |
| **gitflow** | `main` + `develop` + `release/*` + `hotfix/*` | weeks | scheduled release | boxed software with long QA cycles, and not much else |

**Default: trunk-based development with short-lived MR branches, plus `release/X.Y` branches only for versions you ship to customers and must patch.** That is GitLab flow with release branches when you need it, and plain trunk-based when you don't. The tiebreaker against GitLab flow's environment branches is below.

### Trunk-based development

One shared branch, `main`. Everyone integrates into it at least daily. Work happens on branches that live for hours, not weeks, and every merge goes through an MR with a green pipeline. Unfinished features ship dark behind flags.

```text
main  ──●────●────●────●────●────●────●────●──▶   every commit deployable
         \  /      \  /      \      /    \  /
          ●         ●●        ●────●      ●
        PROJ-101  PROJ-102   PROJ-103   PROJ-104
        (4 h)     (1 day)    (2 days)   (2 h)

deploy:  ▲         ▲         ▲          ▲         from main, automatically
```

#### Why it wins for services

- **Conflicts stay small** because nobody's branch diverges far. A two-hour branch rarely conflicts; a three-week branch always does.
- **CI measures reality.** The pipeline on `main` tests the thing you will actually deploy, not an intermediate integration branch.
- **Review stays cheap.** A 150-line MR gets a real review. A 3,000-line MR gets "LGTM".
- **Rollback is a revert of one small commit**, not an archaeology exercise.

#### What it demands

Trunk-based development is not "no process". It moves the process into three places:

1. **A fast, trustworthy pipeline.** If `main` goes red and stays red, everyone is blocked. Target under 10 minutes for the MR pipeline (chapter 09) and merge trains or merged-results pipelines so `main` does not break from two individually-green MRs (chapter 07).
2. **Feature flags.** Code that is not ready still merges; it just does not run.
3. **Small-batch habits.** Break work into slices that each leave `main` releasable: schema first, then code that writes both shapes, then code that reads the new shape, then cleanup.

> **Note.** "Trunk-based" in the DORA research sense means fewer than three active branches, each living under a day, and no code freezes. Most teams that say they do trunk-based actually do GitHub flow with short branches. That is fine. The property that matters is branch age, not the label.

### GitHub flow

Like trunk-based, but with branches that are allowed to live a few days and the explicit rule that **merging to `main` deploys**. There is still exactly one long-lived branch.

```text
main  ──●──────────●───────────●──────────●──▶
         \        /  \        /            ▲
          ●──●──●     ●──●──●              │
         feature/a    feature/b         merge = deploy
         (MR, review,  (MR, review,
          CI, merge)    CI, merge)
```

It fits a single deployed version: web apps, internal services, anything where "the current version" is the only version. It does not answer "how do I patch v2.3 while main is on v3.1" because it assumes that question never comes up.

**Where it differs from trunk-based in practice:** GitHub flow tolerates longer branches and relies less on flags. The failure mode is branches drifting to a week or two, at which point you have the gitflow integration problem without the gitflow ceremony.

### GitLab flow

GitLab flow is GitHub flow plus **one of two** additions. They solve different problems; do not adopt both by reflex.

#### With environment branches

Promotion between environments is a merge between branches. `main` deploys to staging; merging `main` into `pre-production` deploys there; merging into `production` deploys production.

```text
main            ──●──●──●──●──●──●──●──●──▶   deploys to: staging
                        │           │
                        ▼ merge     ▼ merge
pre-production  ────────●───────────●─────▶   deploys to: pre-prod
                        │           │
                        ▼ merge     ▼ merge (later)
production      ────────●───────────────●─▶   deploys to: production

rule: changes flow downstream only. Fixes land in main first, then cherry-pick
      or merge down. Never commit directly to production.
```

**When it fits:** regulated environments where auditors want "what is in production" to be answerable by `git log production`, or where production deploys happen on a schedule controlled by someone who is not the developer.

**Why it is usually not the default:** environment branches duplicate state that GitLab already tracks. The Environments page records which commit is deployed where, protected environments give you the approval gate, and deployment history is an audit log. Environment branches add merge commits that carry no code, invite drift ("someone hotfixed production directly"), and make a rollback a merge instead of a redeploy.

> **Note.** Tiebreaker for environment branches vs trunk + protected environments: **if your auditor or change board requires the production state to be a git ref**, use environment branches. Otherwise, promote one immutable artefact (an image digest) through environments with `environment:` jobs and approvals (chapter 11). Promoting the build, not re-merging the source, is also the only way to guarantee production runs the exact bytes staging tested.

#### With release branches

For software you **ship** rather than deploy: libraries, on-prem products, Helm charts customers install, anything where customers run v2.3 while you develop v3.0.

```text
main         ──●──●──●──●──●──●──●──●──●──●──●──●──▶  next release
                     │              │     ▲
                     │ branch       │     │ fix lands on main first
                     ▼              │     │
release/2.3  ────────●──●───────────┼─────●──────────▶ v2.3.0, v2.3.1
                       tag          │    cherry-pick -x
                     v2.3.0         ▼
release/2.4  ───────────────────────●──●──────●─────▶ v2.4.0, v2.4.1
                                      tag     cherry-pick
                                    v2.4.0
```

Rules that make it work:

- **Branch as late as possible**, at the point you stabilise for release. Until then, everything is on `main`.
- **Fixes go upstream first.** Fix on `main`, then cherry-pick down to each supported release branch. Fixing on the release branch first means you will eventually forget to bring it forward, and the bug reappears in the next release.
- **Tags are cut from release branches**, never from `main` (unless `main` is the only thing you ship).
- **Delete nothing; protect everything.** `release/*` is a protected branch pattern; `v*` is a protected tag pattern (chapter 07).

This is the variant most teams actually need once they ship to customers. It is still trunk-based on `main`.

### gitflow

Vincent Driessen's 2010 model: `main` holds only released code, `develop` is the integration branch, `feature/*` branches off `develop`, `release/*` branches off `develop` for stabilisation and merges into both `main` and `develop`, `hotfix/*` branches off `main` and merges into both.

```text
main      ──●──────────────────────────●───────────●──────▶  tags only
             \                        / \         /
hotfix/1.0.1  \                      /   ●───────●           merge to main AND develop
               \                    /     \       \
release/1.1     \           ●──●──●        \       \
                 \         /       \        \       \
develop   ────────●──●──●──●────●───●───●────●───────●────▶  integration
                   \      /    /        \
feature/x           ●──●──●   /          ●──●──●──●──●──●    weeks-long feature
feature/y              ●──●──●
```

#### Why gitflow hurts continuous delivery

1. **Two sources of truth.** `develop` and `main` diverge by design. The pipeline that tested `develop` did not test what lands on `main`; the release merge creates a new, untested combination.
2. **Integration is deferred to the worst moment.** Feature branches off `develop` live for weeks; the release branch is where everything meets for the first time, under deadline.
3. **Double merges breed drift.** Every hotfix and release must be merged into two branches. Forget the `develop` half once and the next release resurrects the bug.
4. **It encodes a release cadence.** The whole shape exists to batch changes into scheduled releases. Continuous delivery is the opposite: ship each change when it is ready. Adopting gitflow commits you to batch size, and batch size is what the DORA metrics punish.
5. **Its author walked it back.** Driessen's 2020 note on the original post says that for continuously delivered software (web apps), a simpler workflow like GitHub flow is the better fit, and gitflow is for explicitly versioned software supporting multiple versions in the wild.

**When gitflow is still defensible:** almost never for a service. For shipped software with several supported versions, GitLab flow with release branches gives you the same capability without `develop`.

> **One-way door.** Not the choice itself, but the habits it trains. Teams that ran gitflow for years have long-lived branches, big-batch reviews and release-day heroics built into their muscle memory. Switching the branch model takes a day; unwinding the habits takes a quarter. Budget for the habits.

#### Migrating off gitflow

```bash
# 1. Freeze: finish or park open release/* and hotfix/* branches.
# 2. Make main == develop (after the last release is out)
git switch main
git pull --ff-only
git merge --no-ff origin/develop -m "chore: fold develop into main for trunk-based workflow"
git push origin main

# 3. Retarget open MRs from develop to main (per MR)
glab mr update MR_IID --target-branch main

# 4. Change the default branch in the UI (Settings > Repository > Branch defaults),
#    then unprotect and delete develop once nothing targets it.
git push origin --delete develop
```

> **Gotcha.** Changing the default branch does not retarget existing MRs, does not move scheduled pipelines, and does not rewrite `rules: - if: $CI_COMMIT_BRANCH == "develop"` in your CI config. Grep for `develop` in `.gitlab-ci.yml`, included templates, Renovate config (`baseBranches`) and any deploy tooling before you delete the branch.

### Branch naming

Names are not cosmetic: they drive Jira linking, CI rules, protected-branch patterns and push rules.

#### The convention

```text
TYPE/JIRAKEY-NUMBER-short-slug

feat/PROJ-1234-oidc-login
fix/PROJ-1250-null-tenant-crash
chore/PROJ-1301-bump-helm-3-16
release/2.4
```

| Part | Why |
|---|---|
| `TYPE/` | Matches Conventional Commit types (chapter 07), groups branches in UIs, lets CI rules key on prefix |
| `PROJ-1234` | **Uppercase** Jira key: the Jira development panel links branches, commits and MRs that contain the key |
| `short-slug` | Humans need to tell branches apart in `git branch` output. Three to five words |

Keep the Jira key uppercase. Jira's smart linking matches `PROJ-1234`; some integrations are case-sensitive, and `$CI_COMMIT_REF_SLUG` lowercases it anyway for anything that needs DNS-safe names (review apps, namespaces).

#### Enforcing it

Push rules (Premium) can reject branch names that do not match a regex. A pattern that allows the convention plus the release and default branches:

```text
^(main|release/[0-9]+\.[0-9]+|(feat|fix|chore|docs|refactor|perf|test|build|ci|revert)/[A-Z][A-Z0-9]+-[0-9]+-[a-z0-9-]+)$
```

On Free tier, enforce in CI instead. This job fails MR pipelines whose source branch does not match:

```yaml
branch-name:
  stage: .pre
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  script:
    - |
      if ! printf '%s' "$CI_MERGE_REQUEST_SOURCE_BRANCH_NAME" \
        | grep -Eq '^(feat|fix|chore|docs|refactor|perf|test|build|ci|revert)/[A-Z][A-Z0-9]+-[0-9]+-[a-z0-9-]+$'; then
        echo "Branch name must be TYPE/PROJ-123-slug, got: $CI_MERGE_REQUEST_SOURCE_BRANCH_NAME"
        exit 1
      fi
```

#### Creating branches from Jira keys

```bash
# Create the branch, push it, open a draft MR in one go
git switch -c feat/PROJ-1234-oidc-login origin/main
git push -u origin HEAD \
  -o merge_request.create \
  -o merge_request.target=main \
  -o merge_request.draft \
  -o merge_request.title="feat(auth): OIDC login [PROJ-1234]"

# Or with glab after the first push
glab mr create --draft --fill --target-branch main
```

A zsh helper that turns a key and a title into a branch name:

```bash
jbranch() {
  # usage: jbranch feat PROJ-1234 "OIDC login for the API"
  local type=$1 key=$2; shift 2
  local slug=$(print -r -- "$*" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//' | cut -c1-40)
  git switch -c "${type}/${key}-${slug}" origin/main
}
```

> **Gotcha.** Branch names become `$CI_COMMIT_REF_SLUG` (lowercased, non-alphanumerics replaced with `-`, truncated to 63 bytes). Two branches that differ only in case or punctuation get the **same slug**, so their review apps and cache keys collide. Another reason to keep slugs short and distinct.

### Short-lived branches

The rule: **a branch older than two working days is a problem to discuss at stand-up**, not a normal state.

#### Techniques that keep branches short

| Technique | What it does | Use when |
|---|---|---|
| **Feature flags** | Merge incomplete code, disabled | Any user-visible feature taking more than a day |
| **Branch by abstraction** | Introduce an interface, swap implementations behind it over several MRs | Replacing a library, datastore or subsystem |
| **Expand/contract** | Add new schema, dual-write, migrate readers, remove old | Database and API changes |
| **Stacked MRs** | Chain of small dependent MRs, each reviewable alone | A feature that is naturally several layers |
| **Dark launch** | Deploy code paths that run but whose output is discarded or compared | Risky rewrites where you want production traffic as a test |

#### Feature flags

The cheapest flag is an environment variable read at startup. The next step is a flag service. GitLab ships an Unleash-compatible feature-flag API per project (Deploy > Feature flags) so any Unleash client SDK can read flags from GitLab without running a separate service; self-hosted Unleash, Flagsmith or OpenFeature with any provider are the alternatives.

```python
# OpenFeature Python SDK, provider-agnostic
from openfeature import api

client = api.get_client()
if client.get_boolean_value("new-billing-engine", False, evaluation_context):
    return new_billing(order)
return legacy_billing(order)
```

Flag hygiene rules that keep flags from becoming permanent config:

- **Every flag has an owner and a removal ticket** created at the same time as the flag. Put the Jira key in the flag description.
- **Release flags live weeks, not months.** Ops flags (kill switches) may live forever; label them differently.
- **Test both paths in CI** while the flag exists. A flag with an untested "off" path is a latent outage.

> **Note.** Feature flags are the mechanism that separates **deploy** (code is in production) from **release** (users see it). Once you have that separation, most arguments for long-lived branches disappear.

### Stacked MRs

A stack is a chain of branches where each one builds on the previous: `api-schema` ← `api-handlers` ← `ui`. Each MR targets the branch below it, so reviewers see only that layer's diff.

```text
main ──●─────────────────────────────▶
        \
         ●──●  PROJ-10-schema          MR !101 → main
             \
              ●──●  PROJ-10-handlers   MR !102 → PROJ-10-schema
                  \
                   ●  PROJ-10-ui       MR !103 → PROJ-10-handlers
```

#### Stacks with plain git

`git rebase --update-refs` (git 2.38+) rewrites every branch pointer in the stack when you rebase the top, which removes most of the pain.

```bash
# Build the stack
git switch -c feat/PROJ-10-schema origin/main
# ...commit...
git switch -c feat/PROJ-10-handlers
# ...commit...
git switch -c feat/PROJ-10-ui
# ...commit...

# Main moved on: rebase the whole stack from the top, updating all three branches
git fetch origin
git rebase --update-refs origin/main
git push --force-with-lease origin feat/PROJ-10-schema feat/PROJ-10-handlers feat/PROJ-10-ui

# Make it the default
git config --global rebase.updateRefs true
```

Open the MRs with the right targets:

```bash
glab mr create -s feat/PROJ-10-schema   -b main                 --fill --draft
glab mr create -s feat/PROJ-10-handlers -b feat/PROJ-10-schema   --fill --draft
glab mr create -s feat/PROJ-10-ui       -b feat/PROJ-10-handlers --fill --draft
```

When the bottom MR merges, GitLab automatically retargets MRs whose target branch was deleted on merge to that branch's own target (so !102 retargets to `main`), provided "Delete source branch" is set on !101.

#### Stacks with glab

glab 1.108 ships an experimental `glab stack` command family that manages the branches and MRs for you:

```bash
glab stack create PROJ-10-oidc     # start a named stack
# edit, then save each layer as a commit + branch
glab stack save -m "feat(auth): add token schema"
glab stack save -m "feat(auth): handlers"
glab stack list                    # show layers
glab stack prev                    # navigate: also next, first, last, move
glab stack amend -a -m "fix typo"  # fold changes into the current layer
glab stack sync --update-base      # rebase onto latest main, push, create/update MRs
glab stack infer --name PROJ-10-oidc main..HEAD   # turn an existing commit range into a stack
                                   # (range start must be a branch name, not HEAD~5)
```

> **Version-sensitive.** `glab stack` is marked EXPERIMENTAL in glab 1.108 (verified with `glab stack --help`). Flags and behaviour may change between glab releases; pin the glab version in any script that depends on it.

#### Merge method matters for stacks

With **squash on merge**, the bottom MR lands as one new commit whose SHA does not appear in the upper branches. Git sees the upper branches as still containing the old commits, and the next rebase replays them, producing conflicts against themselves. Fix: after the bottom merges, rebase the next layer with `--onto`, skipping the squashed commits:

```bash
# !101 (schema) was squash-merged. handlers still contains the old schema commits.
git fetch origin
git rebase --update-refs --onto origin/main feat/PROJ-10-schema feat/PROJ-10-ui
```

That replays only the commits after `feat/PROJ-10-schema` onto the new `main`, and updates the handlers pointer on the way.

### Release branches and hotfixes

#### Cutting a release branch

```bash
git fetch origin
git switch -c release/2.4 origin/main
git push -u origin release/2.4

# Tag the first release candidate or final release from the branch
git tag -a v2.4.0 -m "v2.4.0"
git push origin v2.4.0
```

Protect `release/*` (Maintainers merge, nobody pushes, force-push off) and `v*` tags (Maintainers create) before the first release branch exists. See chapter 07.

#### Hotfix: upstream first, then cherry-pick down

```bash
# 1. Fix on main via a normal MR: fix/PROJ-1400-token-refresh-race
#    It merges as commit ABC1234 (the squash commit, if you squash).

# 2. Cherry-pick onto each supported release branch, via an MR
git fetch origin
git switch -c fix/PROJ-1400-token-refresh-race-2.4 origin/release/2.4
git cherry-pick -x ABC1234
git push -u origin HEAD \
  -o merge_request.create \
  -o merge_request.target=release/2.4 \
  -o merge_request.title="fix(auth): token refresh race [PROJ-1400] (backport 2.4)"

# 3. After it merges, tag the patch release from the release branch
git switch release/2.4 && git pull --ff-only
git tag -a v2.4.1 -m "v2.4.1" && git push origin v2.4.1
```

`-x` appends `(cherry picked from commit ABC1234)` to the message, which is how you later answer "is PROJ-1400 in 2.3?" with `git log --grep`:

```bash
# Which release branches contain the fix, by original SHA or by Jira key?
git branch -r --contains ABC1234
git log origin/release/2.3 --oneline --grep 'cherry picked from commit ABC1234'
git log origin/release/2.3 --oneline --grep 'PROJ-1400'
```

GitLab's MR page also has a **Cherry-pick** button (and the commit page has one) that opens a new MR against a chosen target branch. It is fine for one-off backports; for three release branches the loop above is faster.

#### Cherry-picking a merge commit

If your merge method creates merge commits and you cherry-pick the merge rather than the individual commits, tell git which parent is the mainline:

```bash
git cherry-pick -x -m 1 MERGE_SHA   # -m 1 = diff against the first parent (the target branch)
```

> **Gotcha.** Cherry-picking a merge commit brings over the net change but loses the individual commit history, and a later cherry-pick of one of the original commits will conflict or apply twice. Squash-merge on `main` avoids this entirely: one MR, one commit, one clean cherry-pick. This is one of the strongest arguments for squash in chapter 07.

#### When the fix cannot go upstream first

Sometimes the code on `main` has been rewritten and the fix does not apply. Then fix on the release branch, and **open a Jira ticket for the forward-port the same minute**, linked to the original. The failure mode is not doing it on the release branch; it is forgetting that `main` still has the bug.

#### How many release branches?

Support the fewest versions your contracts allow. Each supported branch multiplies every security fix. A common shape: current minor plus the previous minor, and the last minor of the previous major for a fixed window. Write the policy down (a `SECURITY.md` or support matrix) so "do we patch 2.1?" has an answer before the CVE arrives.

### Choosing, concretely

```text
Do customers run versions you must patch independently?
├── yes → trunk-based on main + release/X.Y branches        (GitLab flow, release)
└── no  → Must production state be a git ref for audit/change control?
          ├── yes → trunk-based + environment branches      (GitLab flow, environment)
          └── no  → trunk-based, promote one artefact
                    through protected environments          (the default)
```

| If you are... | Pick | Tiebreaker against the runner-up |
|---|---|---|
| Running a service you deploy yourself | **Trunk-based**, short MR branches, flags | GitHub flow only if the team cannot yet keep branches under two days; it is a stepping stone, not a destination |
| Shipping a product customers install | **Trunk + release branches** | gitflow adds `develop` without adding a capability |
| Under a change board that wants prod as a branch | **GitLab flow with environment branches** | Promotion by artefact + protected environment approvals, if the board accepts GitLab's deployment log as evidence |
| Building a library | **Trunk + tags**, release branches only for LTS lines | Release branches from day one only if you already promise LTS |

### Checklist

- [ ] `main` is the default branch, protected, no direct pushes, force-push off.
- [ ] Branch names follow `TYPE/PROJ-123-slug`, enforced by push rule or a CI job.
- [ ] Median MR age under two days; anything older is raised at stand-up.
- [ ] Feature flags exist, each with an owner and a removal ticket.
- [ ] `release/*` and `v*` are protected patterns **before** the first release branch is cut.
- [ ] Hotfixes land on `main` first and are cherry-picked with `-x`.
- [ ] A written support policy says which release branches receive fixes.
- [ ] `git config --global rebase.updateRefs true` if you stack.
- [ ] No `develop`. If you have one, you have a migration plan.


---


<a id="07-merge-policy-and-releases"></a>

## 07 · Merge policy and releases

*The merge settings decide what main's history looks like and what "green" means at the moment of merge. Set them once, per group where you can, so every repository answers the same three questions the same way: what shape does history take, who can change main, and what must be true before a merge.*

### The settings that matter

Everything in this chapter lives in three places in the GitLab UI. Knowing which is which saves a lot of clicking.

| Location | Controls |
|---|---|
| **Settings > Merge requests** | Merge method, squash option, merge checks (pipelines must succeed, threads resolved), merged results pipelines, merge trains, commit templates |
| **Settings > Repository** | Protected branches, protected tags, push rules, default branch, branch rules |
| **Settings > Merge requests > Approvals** (Premium) | Approval rules, approval settings (prevent author approval, reset on push) |

**Default for a service repository:**

| Setting | Value | Why |
|---|---|---|
| Merge method | **Fast-forward merge** | Linear history; `main` only ever contains commits that were tested in exactly that order |
| Squash | **Require** | One MR = one commit = one clean revert or cherry-pick; changelog tooling parses one message per change |
| Squash commit template | `%{title}` + body | The MR title (Conventional Commit format) becomes the commit subject |
| Pipelines must succeed | **On** | "Green MR" must mean something |
| Skipped pipelines are successful | **Off** | Otherwise `[ci skip]` is a way around the gate |
| All threads must be resolved | **On** | Review comments are not advisory |
| Merged results pipelines | **On** (Premium) | Test the merge, not the branch |
| Merge trains | **On** once more than a few MRs merge per day (Premium) | Stops two green MRs making a red `main` |
| Delete source branch | **On by default** | Stale branches are noise and slug collisions |

The tiebreakers for each choice are in the sections below.

### Merge methods

GitLab offers three merge methods. Squash is a separate, orthogonal setting.

```text
Starting point:   main   A───B───C
                               \
                  feature       D───E

1. Merge commit
   main   A───B───C───────M        M has parents C and E
                   \     /         MR can merge even if behind main
                    D───E

2. Merge commit with semi-linear history
   main   A───B───C───────M        same shape as (1), but merge is only
                   \     /         allowed if feature is rebased on C,
                    D'──E'         so the branch "bubble" is always clean

3. Fast-forward merge
   main   A───B───C───D'──E'       no merge commit; main just moves forward
                                   requires feature rebased on C
```

| Method | History | Needs rebase | MR boundaries visible | Revert an MR |
|---|---|---|---|---|
| Merge commit | Graph, can be tangled | No | Yes (merge commit) | `git revert -m 1 M` |
| Semi-linear | Graph of clean bubbles | Yes | Yes | `git revert -m 1 M` |
| Fast-forward | Straight line | Yes | Only with squash | `git revert SHA` (with squash) |

#### What each one guarantees

- **Merge commit** is the only method where the code on `main` after the merge may never have been tested in that exact combination. The branch pipeline tested `D─E` on top of `A`, not on top of `C`. Merged results pipelines (below) close that gap.
- **Semi-linear** guarantees the branch was rebased on the current `main`, so the branch pipeline tested the actual result. It keeps a merge commit per MR, which is useful for `git log --first-parent` to list MRs.
- **Fast-forward** gives the same testing guarantee and a straight-line history. `git log`, `git bisect`, and changelog generators all behave best on it.

**Default: fast-forward with squash required.** Close call against **semi-linear with squash off** for teams who value per-commit history inside an MR. The tiebreaker: if your MRs regularly contain several commits that each deserve to be individually bisectable and revertable (a refactor commit, then a behaviour change commit), semi-linear keeps them and still marks the MR boundary. If your MR commits are mostly "wip" and "address review", squash throws away noise and fast-forward is strictly better.

> **Gotcha.** Fast-forward and semi-linear both require the source branch to be rebased on the target. On a busy repository every merge makes every other open MR "behind", and developers spend their day clicking **Rebase**. Merge trains fix this: they rebase and test each queued MR automatically. Without trains, fast-forward on a repository with more than about ten merges a day becomes friction.

#### Rebasing from the command line or glab

```bash
# Server-side rebase of the MR's source branch onto its target
glab mr rebase MR_IID

# Or locally
git fetch origin
git rebase origin/main
git push --force-with-lease --force-if-includes
```

`--force-if-includes` (git 2.30+) refuses the push if the remote ref has commits you have not integrated locally, which closes the gap where `--force-with-lease` passes because a background `git fetch` updated your remote-tracking ref.

### Squash options

The **Squash commits when merging** setting has four values:

| Value | Behaviour |
|---|---|
| Do not allow | Never squash; checkbox hidden |
| Allow | Checkbox shown, off by default |
| Encourage | Checkbox shown, on by default |
| Require | Always squash; checkbox hidden |

Per-MR override from the command line, when the project allows it:

```bash
glab mr create --fill --squash-before-merge=true
glab mr merge MR_IID --squash --squash-message "fix(api): handle null tenant [PROJ-1250]"
```

#### Commit message templates

Settings > Merge requests has a **Merge commit message template** and a **Squash commit message template**. With squash required and fast-forward, only the squash template matters. A template that produces Conventional Commit subjects from MR titles and keeps traceability:

```text
%{title}

%{description}

MR: %{reference}
%{co_authored_by}
```

Useful placeholders: `%{title}`, `%{description}`, `%{reference}` (the `group/project!123` MR reference), `%{source_branch}`, `%{target_branch}`, `%{first_multiline_commit}`, `%{all_commits}`, `%{co_authored_by}`, `%{approved_by}`, `%{merged_by}`, `%{issues}`.

> **Gotcha.** With squash on, **the MR title becomes the commit subject**. Linting individual commit messages in a pre-commit hook is then pointless for changelog purposes; lint the **MR title** instead (a CI job on `$CI_MERGE_REQUEST_TITLE`, shown later in this chapter). Many teams lint commits and then wonder why the changelog is full of "Draft: wip".

#### What squash costs

- **Individual commits are gone from `main`.** They still exist in the MR's commit tab while the MR exists, and in the source branch until it is deleted.
- **Stacked MRs need `--onto` rebases** after a lower layer merges (chapter 06).
- **Attribution collapses to one author**, with others as `Co-authored-by` trailers if you use `%{co_authored_by}`.

### Protected branches

A protected branch has four independent controls. Configure them per branch or per wildcard pattern in Settings > Repository > Protected branches.

| Control | `main` | `release/*` | Why |
|---|---|---|---|
| Allowed to merge | Developers + Maintainers | Maintainers | Merging via MR is the normal path; release branches are stricter |
| Allowed to push and merge | **No one** | **No one** | Every change arrives through an MR with a pipeline |
| Allowed to force push | **Off** | **Off** | Rewriting shared history destroys other people's work and audit trails |
| Require approval from code owners | **On** (Premium) | **On** (Premium) | CODEOWNERS approvals become mandatory, not advisory |

"Allowed to push" can also list specific users, groups or deploy keys (Premium). A deploy key with push access is how you let a release bot push version bumps and tags without granting a human that right.

```bash
# Read-only: inspect current protection via the API
glab api projects/:id/protected_branches | jq '.[] | {name, push_access_levels, merge_access_levels, allow_force_push, code_owner_approval_required}'
glab api projects/:id/protected_tags | jq '.[] | {name, create_access_levels}'
```

> **One-way door.** Force-pushing a protected branch (even once, by briefly unprotecting it) rewrites the SHAs everyone else has based work on, orphans MR diffs, and breaks any `git cherry-pick -x` references and deployment records that point at old SHAs. Nothing in GitLab undoes it. If a secret leaked into `main`, **rotate the secret**; history rewriting is a second, optional step, and the push rule "Prevent pushing secret files" plus secret detection are the controls that stop it next time.

#### Protected tags

Protect `v*` so only Maintainers (or the release bot's deploy key) can create release tags. Tags trigger release pipelines and, with protected variables and environments, production deploys; an unprotected tag is a way to run the production deploy job from any commit.

```text
Protected tag:     v*
Allowed to create: Maintainers
```

> **Gotcha.** Protected **variables** are exposed to pipelines on protected branches **and protected tags**. If you protect `main` but not `v*`, tag pipelines will not see the deploy credentials, and the release job fails with an empty variable rather than a clear error. Protect both patterns before the first release.

#### Group-level protection

On Premium, protected branches can be defined at the **group** level and apply to every project in it. Define `main` protection once per group rather than per repository; project settings can add stricter rules but not weaker ones.

### CODEOWNERS

A `CODEOWNERS` file maps paths to people or groups. With "Require approval from code owners" on the protected branch, a change to a path needs approval from one of its owners.

#### Location

GitLab looks in this order and uses the **first** found: `CODEOWNERS` at the repository root, then `docs/CODEOWNERS`, then `.gitlab/CODEOWNERS`. Put it in `.gitlab/` next to your templates.

The file used is the one **on the target branch** of the MR. Changing `CODEOWNERS` in an MR does not change who must approve that MR.

#### Syntax

```text
# Default owners for everything not matched later
* @platform-team

# Later rules win. Leading / anchors to the repo root; no leading / matches at any depth.
/charts/                @platform-team @sre
/src/billing/           @alice @billing-devs
*.tf                    @infra
/docs/**/*.md           @docs

# Sections: each section is evaluated independently, and each needs its own approval
[Security][2] @security-team
/src/auth/
/src/crypto/
.gitlab-ci.yml          @security-team @platform-team

# Optional section: owners are suggested but approval is not required
^[Docs]
/docs/                  @docs

# Role-based owners (GitLab 17.9+): any member with that role
[CI]
/.gitlab/ci/            @@maintainer

# Exclusion (GitLab 17.10+): no owner required for lockfile-only changes
[Dependencies]
!package-lock.json
!uv.lock
```

| Syntax | Meaning |
|---|---|
| `/path/file` | Root-anchored path |
| `file` or `dir/file` | Matches at any depth |
| `/dir/` | Everything under the directory, recursively |
| `*`, `**` | Glob within one level, across levels |
| `[Name]` | Start a section; approvals required from each matching section |
| `[Name][N]` | Section requiring N approvals |
| `^[Name]` | Optional section: owners shown, approval not required |
| `[Name] @owner` | Default owners for paths in that section with no owner listed |
| `@user`, `@group`, `@group/sub` | Owners |
| `@@developer`, `@@maintainer`, `@@owner` | Role owners |
| `!pattern` | Exclude matching files from ownership in that section |

> **Version-sensitive.** Role owners (`@@maintainer`) need GitLab 17.9+; `!` exclusions need 17.10+. On older instances those lines are silently ignored or show as syntax errors in the file viewer.

> **Gotcha.** Group owners must have **at least Developer access to the project** (directly or through an invited group) for their approval to count. A group listed in `CODEOWNERS` that was never invited to the project shows as an owner in the file view but cannot satisfy the approval rule, and MRs block forever. Open the `CODEOWNERS` file in the GitLab UI: it flags syntax errors and unresolvable owners.

#### Protect CODEOWNERS itself

Without this, anyone who can merge can remove themselves from the approval path:

```text
[Code owners] @platform-leads
/.gitlab/CODEOWNERS
```

### Approval rules

Approvals are a Premium feature. Free tier can still request reviewers, but cannot make approval a merge requirement.

#### Project approval rules

Settings > Merge requests > Approvals. A sensible baseline:

| Rule | Approvers | Required | Target branch |
|---|---|---|---|
| Any reviewer | Eligible project members | 1 | All protected branches |
| Code owners | From `CODEOWNERS` | per section | All protected branches (via protected-branch toggle) |
| Release branches | `@release-managers` | 1 | `release/*` |

#### Approval settings

| Setting | Value | Why |
|---|---|---|
| Prevent approval by author | **On** | Self-approval defeats the point |
| Prevent approvals by users who add commits | **On** | Someone who pushed a fix to the MR is now an author |
| Prevent editing approval rules in MRs | **On** | Otherwise authors can lower the bar on their own MR |
| Remove all approvals when commits are added | **On**, or "remove approvals by Code Owners if their files changed" | Approvals should cover the code that merges |
| Require user re-authentication to approve | Off unless compliance requires it | Friction without much benefit on most teams |

```bash
# Who needs to approve this MR, and who has?
glab mr approvers MR_IID
glab mr view MR_IID
```

### Merge checks

In Settings > Merge requests > Merge checks.

#### Pipelines must succeed

Blocks the merge button until the latest pipeline for the MR is successful. Combine with:

- **Skipped pipelines are considered successful: off.** Otherwise `git push -o ci.skip` or `[skip ci]` in a commit message produces a mergeable MR with no pipeline.
- **Auto-merge** (the "Set to auto-merge" button, or `glab mr merge --auto-merge`) to merge as soon as the pipeline passes.

> **Gotcha.** "Pipelines must succeed" checks **the latest pipeline** for the MR's head. If your `workflow:rules` produce no pipeline at all for some MRs (for example, docs-only changes skipped by `rules:changes`), the MR can never merge. Either always create a pipeline with at least one cheap job, or enable "Skipped pipelines are considered successful" knowingly. The first is safer; chapter 08 shows the pattern.

#### All threads must be resolved

Blocks merge while any discussion thread is unresolved. Reviewers use threads for blocking comments and non-thread comments (or suggestions marked non-blocking) for nits.

#### Other checks worth knowing

| Check | Use |
|---|---|
| Status checks must succeed (Premium) | External systems (a security scanner, a deployment gate) post pass/fail via the API |
| Prevent merge while Jira issue is not linked / has no key (Ultimate, Jira integration) | Enforce traceability from Jira |
| Draft MRs cannot merge | Always on |

### Merged results pipelines

A normal MR pipeline tests the **source branch**. A merged results pipeline tests the **result of merging the source into the target** as it exists right now: GitLab creates a temporary merge ref (`refs/merge-requests/IID/merge`) and runs the pipeline on it.

```text
branch pipeline:          tests  feature HEAD            (A─D─E)
merged results pipeline:  tests  merge(main HEAD, feature) (A─B─C─M)
                                 ↑ catches conflicts with B and C that
                                   are textually clean but semantically broken
```

- Requires `rules` that create **merge request pipelines** (`$CI_PIPELINE_SOURCE == "merge_request_event"`). Branch pipelines are never merged results.
- In the pipeline, `$CI_MERGE_REQUEST_EVENT_TYPE` is `merged_result`; for a plain MR pipeline it is `detached`.
- Premium tier. Enable in Settings > Merge requests > Merge options.
- Falls back to a regular MR pipeline if the branch has conflicts.

> **Note.** With fast-forward or semi-linear merges, the branch is already rebased on `main`, so merged results adds nothing until `main` moves again. It matters most with the merge-commit method, and it is the foundation merge trains build on.

### Merge trains

Merged results tests your branch against `main` as of when the pipeline started. If two MRs are each green against the same `main` and merge one after the other, the combination was never tested. Merge trains queue MRs and test each one against **main plus everything ahead of it in the queue**.

```text
main: ──●  C

train:   [!101]           [!102]                [!103]
pipeline: C + !101        C + !101 + !102       C + !101 + !102 + !103
          ✔ merges        ✔ merges              ✘ fails → !103 dropped,
                                                   author notified,
                                                   nothing behind it restarts
                                                   unless it was stacked on !103
```

Key facts:

- Requires merged results pipelines and "Pipelines must succeed". Premium.
- Up to **20** pipelines run in parallel by default (configurable per project).
- `$CI_MERGE_REQUEST_EVENT_TYPE` is `merge_train` in train pipelines, which lets you run a lighter or heavier job set:

```yaml
e2e:
  rules:
    - if: $CI_MERGE_REQUEST_EVENT_TYPE == "merge_train"   # full suite only on the train
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      when: manual
      allow_failure: true
```

- A failed MR is removed from the train; MRs behind it are re-queued with pipelines recomputed without it.
- "Merge immediately" bypasses the train but restarts the pipelines of every MR behind it. GitLab 16.5 added (behind a disabled flag) and 16.10 enabled, still as an **experiment**, an option to skip the train **without** restarting it; it is not available with fast-forward or semi-linear merge methods.

> **Version-sensitive.** Merge trains with the **fast-forward and semi-linear** merge methods arrived in GitLab 16.5 (flag `fast_forward_merge_trains_support`, enabled by default). On older instances trains work only with the merge-commit method. Check your instance's merge options page: the train toggle is disabled with an explanatory message if the combination is unsupported.

> **Gotcha.** A merge train multiplies pipeline load by up to the train length, and a flaky test ejects innocent MRs. Fix flakes and cut MR pipeline time (chapter 09) **before** turning trains on, or developers will learn to "merge immediately" and the train becomes theatre.

### Push rules

Premium. Settings > Repository > Push rules; can be set at group level so every new project inherits them. They are checked **server-side on push**, so they apply to every client.

| Rule | Recommended | Notes |
|---|---|---|
| Reject unsigned commits | Your call | Only if you run signing everywhere; otherwise it blocks web edits and bots unless they sign |
| Reject unverified users | On | Committer email must be a verified email of the pushing user |
| Check whether the commit author is a GitLab user | On for internal repos | Stops commits authored as `root@localhost` |
| Prevent pushing secret files | **On** | Blocks common key and credential filenames (`id_rsa`, `.pem`, `credentials.json` and similar) |
| Require expression in commit messages | Usually off with squash | Commit lint belongs on MR titles when squashing |
| Branch name regex | **On** | The chapter 06 pattern |
| Maximum file size (MB) | 10 to 50 | Stops binaries and dumps; use Git LFS or the package registry |
| Prohibited file names | `.*\.(tfstate|pfx|p12|jks)$` | Things that should never be in git |
| Do not allow users to remove Git tags with `git push` | **On** | Release tags are immutable |

> **Note.** Push rules check **every commit in the push**, including old commits on a newly pushed branch. Turning on "Reject unsigned commits" for an existing repository means any branch containing historic unsigned commits cannot be pushed as a new branch. Roll it out at the start of a new repository, or accept that old branches must be recreated.

### Conventional Commits and SemVer

Conventional Commits is a commit-message grammar that machines can parse into a version bump and a changelog:

```text
type(scope)!: subject

body

BREAKING CHANGE: description
Refs: PROJ-1234
```

| Type | Bump | Changelog section |
|---|---|---|
| `feat` | minor | Features |
| `fix` | patch | Bug fixes |
| `perf` | patch | Performance |
| `refactor`, `docs`, `test`, `build`, `ci`, `chore`, `style` | none | usually hidden |
| any type with `!` or a `BREAKING CHANGE:` footer | **major** | Breaking changes |
| `revert` | patch (tool-dependent) | Reverts |

SemVer rules applied: `MAJOR.MINOR.PATCH`; while `MAJOR` is `0`, most tools bump **minor** for breaking changes instead of major, which is configurable.

#### Lint the MR title, not every commit

With squash required, the MR title is the only message that reaches `main`:

```yaml
mr-title:
  stage: .pre
  image: docker.io/library/alpine:3.22
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  script:
    - |
      title="$CI_MERGE_REQUEST_TITLE"
      re='^(feat|fix|perf|refactor|docs|test|build|ci|chore|style|revert)(\([a-z0-9-]+\))?!?: .+'
      if ! printf '%s' "$title" | grep -Eq "$re"; then
        echo "MR title is not a Conventional Commit: $title"
        echo "Example: feat(auth): add OIDC login [PROJ-1234]"
        exit 1
      fi
```

> **Gotcha.** Renaming the MR does **not** start a new pipeline, so a failed title check stays red after the fix until the pipeline is re-run. Tell people to hit **Run pipeline** on the MR (or `glab ci run --mr`) after retitling.

#### Where to put the Jira key

The subject line is precious; put the key either at the end in brackets (`[PROJ-1234]`) or as a `Refs: PROJ-1234` trailer. Jira's development panel matches the key anywhere in the message. Branch names already carry the key (chapter 06), and MR titles should too, because the MR title is what lands on `main`.

### Automated releases

The flow: Conventional Commits on `main` → a job computes the next version → creates a tag and a changelog entry → the tag pipeline builds and publishes artefacts and a GitLab release.

```text
main commit ─▶ pipeline on main ─▶ release job: next version? ─▶ tag vX.Y.Z
                                                                    │
                                   tag pipeline ◀───────────────────┘
                                   build image, push chart, create GitLab release
```

#### The tool options

| Tool | Runtime | GitLab support | Changelog file | Pick when |
|---|---|---|---|---|
| **git-cliff** | single Rust binary | `[remote.gitlab]` enriches with MR and author data | Yes, templated | **Default**: polyglot repos, no Node dependency, you want to control tagging yourself |
| **semantic-release** | Node | `@semantic-release/gitlab` plugin creates releases and comments on MRs | Via `@semantic-release/changelog` | Full "merge = release" automation and you already run Node |
| **GitLab changelog API** / `glab changelog generate` | built in | Native | Output to paste or commit | You want zero extra tooling and will add `Changelog:` trailers |
| **release-please** | Node | **GitHub only** (its README and action target GitHub; no GitLab support) | Yes, via a release PR | Not an option on GitLab; the release-MR pattern it popularised can be reproduced with git-cliff |

**Default: git-cliff.** It is one static binary you can pin in a CI image, it reads Conventional Commits out of the box, `--bumped-version` gives you the next version without side effects, and it leaves tagging and publishing to your pipeline where they are visible. **semantic-release** is the tiebreaker pick if you want the whole flow (analyse, tag, release notes, MR comments) to be one opinionated tool and are comfortable with a Node toolchain in a Python shop.

#### git-cliff in a pipeline

`cliff.toml` at the repository root (generate a starting point with `git cliff --init`). The relevant bump config:

```toml
[bump]
features_always_bump_minor = true
breaking_always_bump_major = true
initial_tag = "0.1.0"
```

Release job on `main` that tags when there is something to release. It pushes with a project access token (role Maintainer, scope `write_repository`) stored as a masked, protected variable, because `CI_JOB_TOKEN` cannot push to the repository by default:

```yaml
release:tag:
  stage: release
  image: docker.io/library/python:3.13   # full image: ships git; pin by digest in real use
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH && $CI_PIPELINE_SOURCE == "push"
  variables:
    GIT_DEPTH: 0            # git-cliff needs full history and tags
  before_script:
    - pip install --quiet "git-cliff==GIT_CLIFF_VERSION"   # PyPI wheel of the same binary
  script:
    - NEXT="$(git cliff --bumped-version)"
    - CURRENT="$(git describe --tags --abbrev=0 2>/dev/null || echo none)"
    - |
      if [ "$NEXT" = "$CURRENT" ]; then
        echo "No releasable commits since $CURRENT"; exit 0
      fi
    - git cliff --unreleased --tag "$NEXT" --strip header > RELEASE_NOTES.md
    - git tag -a "$NEXT" -F RELEASE_NOTES.md
    - git push "https://release-bot:${RELEASE_TOKEN}@${CI_SERVER_HOST}/${CI_PROJECT_PATH}.git" "$NEXT"
```

Then the tag pipeline creates the GitLab release with the `release:` keyword (chapter 11 has the full job):

```yaml
release:publish:
  stage: release
  image: registry.gitlab.com/gitlab-org/cli:latest   # glab image; pin a version
  rules:
    - if: $CI_COMMIT_TAG =~ /^v?\d+\.\d+\.\d+$/
  script:
    - echo "Releasing $CI_COMMIT_TAG"
  release:
    tag_name: $CI_COMMIT_TAG
    name: $CI_COMMIT_TAG
    description: $CI_COMMIT_TAG_MESSAGE
```

> **Gotcha.** Tag pushes made with a token **do** trigger pipelines, which is what you want here. Pushes of **commits** back to `main` from CI (for example, committing an updated `CHANGELOG.md`) also trigger a pipeline on `main`, which runs the release job again. Either keep the changelog in release notes only (recommended), or guard the job with `$CI_COMMIT_AUTHOR !~ /release-bot/` and push with `-o ci.skip`.

> **Version-sensitive.** `$CI_COMMIT_TAG_MESSAGE` needs GitLab 15.5+. GitLab 17.2 added (behind a flag, GA in 18.4) an opt-in project setting that lets `CI_JOB_TOKEN` push to its own repository; it is off by default, and a dedicated bot token keeps release pushes attributable and revocable, so this chapter does not rely on it. The image tags above are examples; check the registry for the current release and pin by digest.

#### GitLab's changelog API and glab

GitLab can generate changelog entries from commits that carry a `Changelog:` trailer, grouped by trailer value:

```text
fix(api): handle null tenant

Changelog: fixed
```

```bash
# Generate the changelog for the version git describe finds
glab changelog generate

# For an explicit version and range, using a different trailer
glab changelog generate --version 2.4.0 --from FROM_SHA --to TO_SHA --trailer Changelog

# Config lives at .gitlab/changelog_config.yml by default (--config-file to override)
```

The companion API endpoint (`POST /projects/:id/repository/changelog`) commits the result to a branch; that is a write call, so run it only from CI with a scoped token.

> **Note.** The trailer requirement is the catch: every change needs `Changelog: added|fixed|changed|...` added by a human. With squash, put it in the MR description and include `%{description}` in the squash template. Conventional-commit-based tools avoid the second convention entirely, which is why git-cliff is the default here.

#### semantic-release, for comparison

```json
{
  "branches": ["main", { "name": "release/*", "range": "${name.replace(/^release\\//, '')}.x" }],
  "plugins": [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    "@semantic-release/gitlab"
  ]
}
```

It needs `GITLAB_TOKEN` (or `GL_TOKEN`) with API and repository write access, `GIT_DEPTH: 0`, and runs `npx semantic-release` in a job on `main`. It creates the tag and the GitLab release in one step.

### Traps

- **Protecting `main` but not `v*` tags.** Protected variables vanish in tag pipelines, and anyone who can push a tag can trigger release jobs.
- **Squash required, commit messages linted, MR titles not linted.** The changelog is built from the one thing you did not check.
- **"Pipelines must succeed" plus rules that create no pipeline.** Docs-only MRs become unmergeable. Always create a pipeline.
- **"Skipped pipelines are considered successful" on.** `-o ci.skip` walks around the gate.
- **CODEOWNERS groups not invited to the project.** Required approvals that nobody can give.
- **Fast-forward without merge trains on a busy repository.** Endless rebase clicking; people lobby to go back to merge commits.
- **Merge trains before fixing flaky tests.** Innocent MRs get ejected; people learn to bypass the train.
- **Release job pushes a commit to `main`.** It retriggers itself. Keep release notes in the tag and release, not a committed file, or guard the job.
- **Force-pushing a protected branch "just once".** Irreversible; rotate secrets instead.


---


<a id="08-anatomy-of-gitlab-ci-yml"></a>

## 08 · Anatomy of .gitlab-ci.yml

*A pipeline is two decisions made in order: first workflow:rules decides whether a pipeline exists at all and what kind it is, then each job's rules decide whether that job is in it. Get those two layers right and the rest of the file is just scripts.*

### How GitLab reads the file

When something happens (a push, an MR update, a schedule, an API call), GitLab builds a pipeline in this order:

```text
event ──▶ resolve includes ──▶ merge extends / !reference ──▶ evaluate workflow:rules
                                                                    │
                                   no match, or when: never ────────┴──▶ no pipeline
                                                                    │ match
                                                                    ▼
                                      for each job: evaluate rules (first match wins)
                                                                    │
                                        when: never / no match ─────┴──▶ job omitted
                                                                    │
                                                                    ▼
                                      build graph from stages + needs ──▶ pipeline
```

Three consequences worth internalising:

1. **Rules are evaluated when the pipeline is created**, against variables available at that moment. Variables set by a job's `script` or `dotenv` report cannot affect whether a later job exists.
2. **`workflow:rules` runs once, before any job rules.** If it produces no pipeline, no job rule is consulted.
3. **Includes and `extends` are resolved first**, so `glab ci config compile` (chapter 12) shows you exactly what the rules engine sees.

### Pipeline types

| Type | Trigger | `$CI_PIPELINE_SOURCE` | Runs on | Notes |
|---|---|---|---|---|
| Branch | push to a branch | `push` | the branch HEAD | Default when no rules exist |
| Tag | push of a tag | `push` (with `$CI_COMMIT_TAG` set) | the tagged commit | `$CI_COMMIT_BRANCH` is **empty** |
| Merge request | MR created/updated | `merge_request_event` | source branch HEAD | `$CI_MERGE_REQUEST_EVENT_TYPE=detached` |
| Merged results | MR, with setting on (Premium) | `merge_request_event` | temporary merge ref | `$CI_MERGE_REQUEST_EVENT_TYPE=merged_result` |
| Merge train | MR added to train (Premium) | `merge_request_event` | train merge ref | `$CI_MERGE_REQUEST_EVENT_TYPE=merge_train` |
| Scheduled | pipeline schedule | `schedule` | branch or tag chosen in schedule | Schedule variables available |
| Manual (web) | Run pipeline button | `web` | chosen ref | Inputs and variables from the form |
| API | `POST /pipeline`, `glab ci run` | `api` | chosen ref | |
| Trigger token | `POST /trigger/pipeline` | `trigger` | chosen ref | `glab ci run-trig` |
| Parent-child | `trigger: include:` in a parent | `parent_pipeline` | same ref as parent | Child sees parent's MR context |
| Multi-project | `trigger: project:` upstream | `pipeline` | downstream project's ref | |

Two predicates cover most rules: "is this an MR pipeline?" (`$CI_PIPELINE_SOURCE == "merge_request_event"`) and "is this the default branch?" (`$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH`). Tags are the third (`$CI_COMMIT_TAG`).

> **Gotcha.** MR-only variables (`$CI_MERGE_REQUEST_IID`, `$CI_MERGE_REQUEST_TARGET_BRANCH_NAME`, `$CI_MERGE_REQUEST_LABELS` and friends) exist **only in MR pipelines**. A branch pipeline for a branch that has an open MR does not have them. Rules that test `$CI_MERGE_REQUEST_LABELS =~ /skip-e2e/` silently never match in branch pipelines.

### workflow:rules

Without `workflow:rules`, GitLab creates a **branch** pipeline for every push, and, if any job has an MR rule, an **MR** pipeline as well. The result is two pipelines per push on every branch with an open MR: double runner cost, and two sets of statuses.

#### The standard snippet

Run MR pipelines for MRs, branch pipelines for branches without an MR, and tag pipelines:

```yaml
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS
      when: never
    - if: $CI_COMMIT_BRANCH
    - if: $CI_COMMIT_TAG
```

Line by line:

1. MR event → MR pipeline.
2. Push to a branch that **has an open MR** → no branch pipeline (the MR pipeline covers it).
3. Push to any other branch (including `main`, which normally has no MR from itself) → branch pipeline.
4. Tag → tag pipeline.

Anything else (schedules, API, web) matches none of these and creates no pipeline. Add them explicitly:

```yaml
workflow:
  name: '$PIPELINE_NAME'
  auto_cancel:
    on_new_commit: interruptible
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      variables:
        PIPELINE_NAME: 'MR !$CI_MERGE_REQUEST_IID: $CI_MERGE_REQUEST_TITLE'
    - if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS && $CI_PIPELINE_SOURCE == "push"
      when: never
    - if: $CI_PIPELINE_SOURCE == "schedule"
      variables:
        PIPELINE_NAME: 'Scheduled: $CI_COMMIT_REF_NAME'
    - if: $CI_COMMIT_TAG
      variables:
        PIPELINE_NAME: 'Release $CI_COMMIT_TAG'
    - if: $CI_COMMIT_BRANCH
      variables:
        PIPELINE_NAME: 'Branch: $CI_COMMIT_BRANCH'
```

The `&& $CI_PIPELINE_SOURCE == "push"` on the second rule keeps web and API pipelines working on branches that happen to have an MR open.

> **Version-sensitive.** `workflow:name` needs GitLab 15.5+. `workflow:auto_cancel:on_new_commit` needs 16.8+ (GA 16.10); `on_job_failure` 16.10+ (GA 16.11). `$CI_OPEN_MERGE_REQUESTS` has existed since 13.8. Check with `glab ci lint` against your instance before relying on the newer keys.

> **Gotcha.** The very first push of a new branch happens **before** the MR exists, so it always gets a branch pipeline. Opening the MR then creates an MR pipeline for the same commit. One duplicate per branch is expected; pushing with `-o merge_request.create` opens the MR in the same push and avoids even that.

#### Always create a pipeline for MRs

If "Pipelines must succeed" is on (chapter 07), an MR with no pipeline can never merge. That happens when every job is filtered out by `rules:changes` (a docs-only change, for example). Keep one cheap job with no `changes` filter:

```yaml
mr-sanity:
  stage: lint                  # not .pre: a pipeline with only .pre/.post jobs does not run
  image: docker.io/library/alpine:3.22
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  script:
    - echo "MR !$CI_MERGE_REQUEST_IID ok"
```

> **Gotcha.** A pipeline whose only jobs are in `.pre` or `.post` is not created. That is why the sanity job sits in a real stage.

### Stages and needs

#### Stages: the coarse graph

`stages:` declares ordered buckets. By default a job starts only when **every** job in the previous stage has finished successfully. Two implicit stages always exist: `.pre` (first) and `.post` (last).

```yaml
stages: [lint, test, build, package, deploy]
```

#### needs: the real graph

`needs:` makes a job start as soon as the listed jobs finish, regardless of stage. This turns the stage waterfall into a DAG:

```text
Stages only:                          With needs:

lint:  ruff ──┐                       ruff ──▶ pytest ──▶ build ──▶ deploy
       mypy ──┤                       mypy ─┘              ▲
              ▼ (waits for all)       helm-lint ──────────┘ (chart only)
test:  pytest ┐
       e2e ───┤  (e2e is slow: build   e2e runs in parallel with build,
              ▼   waits for it)        it does not block the image
build: image
```

```yaml
build:image:
  stage: build
  needs: [ruff, pytest]          # starts when these two pass, ignores e2e
deploy:staging:
  stage: deploy
  needs: [build:image, helm:package]
```

Rules of `needs`:

| Form | Effect |
|---|---|
| `needs: []` | Start immediately when the pipeline starts, ignoring stages |
| `needs: [a, b]` | Wait for `a` and `b`; download their artefacts |
| `needs: [{job: a, artifacts: false}]` | Wait for `a`, but do not download its artefacts |
| `needs: [{job: a, optional: true}]` | Wait for `a` if it exists in this pipeline; do not fail if rules removed it |
| `needs: [{pipeline: $PARENT_PIPELINE_ID, job: gen}]` | Artefacts from a job in the parent pipeline (child pipelines) |
| `needs: [{project: group/proj, job: build, ref: main, artifacts: true}]` | Artefacts from another project's latest successful pipeline (Premium) |

> **Gotcha.** If job B `needs` job A and A's rules exclude it from this pipeline, **pipeline creation fails** with "'B' job needs 'A' job, but 'A' is not in any previous stage". Use `optional: true` whenever the needed job has its own `rules:changes` or branch conditions.

**Default: declare stages for readability, wire every job with `needs`.** Stages still set the visual layout and give `.pre`/`.post` semantics; `needs` sets actual ordering. Jobs with no `needs` keyword fall back to stage ordering, which is a common source of "why is this waiting?".

#### dependencies vs needs

`dependencies:` only controls which artefacts are downloaded, not ordering. With `needs`, artefacts come from the needed jobs and `dependencies` is redundant. Use `dependencies: []` only on stage-ordered jobs that should download nothing.

### rules

`rules` is an ordered list. **The first matching rule decides**; later rules are not evaluated. If no rule matches, the job is not added.

#### Clauses

| Clause | Matches when | Example |
|---|---|---|
| `if:` | Expression is true | `if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH` |
| `changes:` | Any listed path changed | `changes: ["src/**/*", "pyproject.toml"]` |
| `changes: {paths, compare_to}` | Changed relative to a given ref (15.3+) | `compare_to: refs/heads/main` |
| `exists:` | Any listed file exists in the repo | `exists: [Dockerfile]` |
| (no clause) | Always | A final catch-all rule |

Multiple clauses in one rule are **ANDed**. Separate rules are **ORed** (first match wins).

#### Results

| Key | Values | Default when rule matches |
|---|---|---|
| `when:` | `on_success`, `on_failure`, `always`, `manual`, `delayed`, `never` | `on_success` |
| `allow_failure:` | `true`, `false`, or `exit_codes:` list | `false`, including for `when: manual` (see Gotcha) |
| `start_in:` | duration, with `when: delayed` | |
| `variables:` | map, set only when this rule matches | |
| `needs:` | override the job's needs (16.4+) | |
| `interruptible:` | override the job's interruptible (16.10+) | |

#### Patterns

```yaml
# Run on MRs and main; manual on other branches; never on tags
test:e2e:
  rules:
    - if: $CI_COMMIT_TAG
      when: never
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - when: manual
      allow_failure: true

# Only when chart files change, in MRs; always on main
helm:lint:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes:
        paths: [charts/**/*]
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

# Only if a Dockerfile exists (useful in shared templates)
build:image:
  rules:
    - exists: [Dockerfile]

# Per-rule variables: bigger timeout on the nightly schedule
test:
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
      variables:
        PYTEST_ADDOPTS: "--runslow"
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

> **Gotcha.** `when: manual` inside **rules** defaults to `allow_failure: false`, which makes the pipeline show as **blocked** until someone clicks it, and "Pipelines must succeed" then blocks the MR. Outside rules (legacy job-level `when: manual`) the default is `allow_failure: true`. For optional manual jobs in rules, always write `allow_failure: true` explicitly.

#### Expressions

```yaml
if: $VAR                                  # set and non-empty
if: $VAR == null                          # unset
if: $VAR == "value"
if: $VAR != "value"
if: $VAR =~ /^release\/\d+\.\d+$/         # RE2 regex
if: $VAR !~ /wip/i
if: $A && ($B || $C)                      # parentheses supported
if: $CI_MERGE_REQUEST_LABELS =~ /(^|,)run-e2e(,|$)/
```

The right-hand side of `=~` can be a variable containing a regex, which is useful in templates: `if: $CI_COMMIT_BRANCH =~ $RELEASE_BRANCH_REGEX`.

#### Why only/except is legacy

`only:` and `except:` predate `rules`. They are not removed, but:

- They **cannot be combined with `rules`** in the same job.
- They cannot express "manual on branches, automatic on main" in one job without duplication.
- They have surprising defaults: a job with no `only` runs on branches **and tags**, and `only: changes` behaves differently for pipelines without a push event.
- No new features land for them; `rules:variables`, `rules:needs`, `rules:interruptible` exist only in `rules`.

Convert them as you touch them:

```yaml
# Before
deploy:
  only: [main]
  except: [schedules]

# After
deploy:
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
      when: never
    - if: $CI_COMMIT_BRANCH == "main"
```

### Predefined variables that matter

Out of the few hundred predefined variables, these are the ones you actually branch on and build with.

| Variable | Value | Use |
|---|---|---|
| `CI_PIPELINE_SOURCE` | `push`, `merge_request_event`, `schedule`, `web`, `api`, `trigger`, `pipeline`, `parent_pipeline` | Which kind of pipeline |
| `CI_COMMIT_BRANCH` | branch name; **empty in MR and tag pipelines** | Branch rules |
| `CI_COMMIT_REF_NAME` | branch or tag name (also set in MR pipelines, as the source branch) | Human-readable ref |
| `CI_COMMIT_REF_SLUG` | lowercased, `[a-z0-9-]`, max 63 bytes | DNS names, namespaces, cache keys |
| `CI_COMMIT_TAG` | tag name; only in tag pipelines | Release rules |
| `CI_COMMIT_SHA` / `CI_COMMIT_SHORT_SHA` | full / 8-char SHA | Image tags |
| `CI_DEFAULT_BRANCH` | usually `main` | Never hardcode `main` |
| `CI_MERGE_REQUEST_IID` | MR number | MR comments, review app names |
| `CI_MERGE_REQUEST_EVENT_TYPE` | `detached`, `merged_result`, `merge_train` | Different jobs for trains |
| `CI_MERGE_REQUEST_TARGET_BRANCH_NAME` | target branch | Diff base for linters |
| `CI_MERGE_REQUEST_DIFF_BASE_SHA` | merge base SHA | `git diff --name-only $CI_MERGE_REQUEST_DIFF_BASE_SHA` |
| `CI_OPEN_MERGE_REQUESTS` | `group/proj!1,...` if the branch has open MRs | Duplicate-pipeline suppression |
| `CI_REGISTRY`, `CI_REGISTRY_IMAGE` | registry host, `registry/group/project` | Image names |
| `CI_REGISTRY_USER` / `CI_REGISTRY_PASSWORD` | job-scoped registry credentials | `docker login` |
| `CI_JOB_TOKEN` | job-scoped API/registry/package token | Package uploads, API calls (chapter 11) |
| `CI_PROJECT_DIR` | checkout path | Cache/artefact paths are relative to this |
| `CI_PIPELINE_ID`, `CI_JOB_ID` | numeric IDs | Unique names |
| `CI_ENVIRONMENT_NAME`, `CI_ENVIRONMENT_SLUG`, `CI_ENVIRONMENT_URL` | from `environment:` | Deploy scripts |
| `CI_SERVER_HOST`, `CI_SERVER_FQDN`, `CI_SERVER_URL` | instance host, host+port, URL | Portable clone URLs and component includes |

> **Gotcha.** `CI_COMMIT_BRANCH` is **empty** in MR pipelines. Rules like `if: $CI_COMMIT_BRANCH == "main"` never match in an MR pipeline, which is usually what you want, but templates that build image tags from `$CI_COMMIT_BRANCH` produce `registry/app:` in MR pipelines. Use `$CI_COMMIT_REF_SLUG` for tags and names.

### Variables and precedence

Variables come from many places. When two define the same name, the higher one wins:

| Rank | Source |
|---|---|
| 1 (highest) | Pipeline execution and scan execution policies |
| 2 | Manual job variables (entered when running a manual job) |
| 3 | Pipeline variables: Run pipeline form, schedules, API, trigger, push options, upstream `trigger:` forwarding |
| 4 | Project CI/CD variables |
| 5 | Group CI/CD variables (closest subgroup wins) |
| 6 | Instance CI/CD variables |
| 7 | `dotenv` report variables from needed/dependent jobs |
| 8 | `.gitlab-ci.yml` variables: `rules:variables` > job `variables` > `workflow:rules:variables` > top-level `variables` |
| 9 | Deployment variables |
| 10 (lowest) | Predefined variables |

What this means in practice:

- **A project variable silently overrides the same name in `.gitlab-ci.yml`.** When a job ignores your YAML change, check Settings > CI/CD > Variables.
- **Pipeline variables override almost everything**, which is why the project setting "Minimum role to use pipeline variables" should be set to Maintainer (or "No one allowed") on sensitive projects. Otherwise any Developer can run a pipeline with `DEPLOY_ENV=production` or override a script path.
- **`dotenv` artefacts beat YAML variables**, so a build job can publish `IMAGE_DIGEST=sha256:...` and every downstream job sees it.

```yaml
build:
  script:
    - echo "IMAGE_DIGEST=$(cat digest.txt)" >> build.env
  artifacts:
    reports:
      dotenv: build.env

deploy:
  needs: [build]
  script:
    - helm upgrade --install app ./chart --set image.digest="$IMAGE_DIGEST"
```

> **Version-sensitive.** Newer GitLab versions restrict pipeline variables by default on new projects ("Minimum role to use pipeline variables" defaulting to Developer or higher, and more recently "No one allowed" for new projects in the 17.x/18.x series). Check the setting on your instance rather than assuming either behaviour.

#### Expansion

- YAML variables are expanded, including references to other variables: `IMAGE: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA`.
- UI variables can be marked **Expand variable reference** or not; with it off, a `$` in the value is literal (important for passwords).
- In YAML, `variables: {PASS: {value: "a$b", expand: false}}` prevents expansion.
- Expansion in `rules:if` happens once; nested references (`$A` where `A=$B`) are expanded, but not command substitution.

### default:

Keywords under `default:` apply to every job that does not set them. Supported: `image`, `services`, `before_script`, `after_script`, `cache`, `artifacts`, `retry`, `timeout`, `interruptible`, `tags`, `hooks`, `id_tokens`.

```yaml
default:
  image: docker.io/library/python:3.13-slim
  interruptible: true
  retry:
    max: 2
    when: [runner_system_failure, stuck_or_timeout_failure, scheduler_failure, api_failure]
  timeout: 20m
  tags: [k8s, amd64]
```

> **Gotcha.** Top-level `image:`, `services:`, `cache:`, `before_script:` and `after_script:` (outside `default:`) still work but are deprecated. Use `default:`.

> **Note.** `retry` on `script_failure` hides flaky tests. Retry only infrastructure failure reasons by default, and fix the flake.

### extends, anchors and !reference

Three ways to reuse YAML inside a pipeline. They are not interchangeable.

| Mechanism | Works across `include` files | Merges maps | Merges arrays | Best for |
|---|---|---|---|---|
| YAML anchors (`&`, `<<: *`) | **No** (same file only) | Shallow | No | Nothing new; legacy |
| `extends:` | Yes | **Deep** | No (arrays replaced) | Job templates |
| `!reference [job, key]` | Yes | No (inserts value) | Yes (can splice into a list) | Reusing a `script` or `rules` list |

#### extends

```yaml
.python:
  image: docker.io/library/python:3.13-slim
  variables:
    UV_CACHE_DIR: $CI_PROJECT_DIR/.cache/uv
  before_script:
    - pip install --quiet uv
    - uv sync --frozen

ruff:
  extends: .python
  script:
    - uv run ruff check .
```

Hidden jobs start with `.` and never run. `extends` merges deeply: the job's `variables` are merged key by key with the template's. **Arrays are replaced, not merged**: if `ruff` defined `before_script`, the template's `before_script` would be gone entirely. `extends` can take a list; later entries win.

#### !reference

`!reference` inserts a specific key from another job, so you can compose lists:

```yaml
.rules:mr-and-main:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

.setup:
  script:
    - pip install --quiet uv
    - uv sync --frozen

pytest:
  rules:
    - if: $CI_COMMIT_TAG
      when: never
    - !reference [.rules:mr-and-main, rules]      # splices both rules in
  script:
    - !reference [.setup, script]
    - uv run pytest
```

Nesting is allowed up to 10 levels.

#### Anchors

```yaml
.defaults: &defaults
  image: docker.io/library/python:3.13-slim
job:
  <<: *defaults
  script: [echo hi]
```

**Avoid in new code.** Anchors are resolved by the YAML parser before GitLab sees the file, so they cannot reach into included files, and `<<:` merges only one level deep.

**Default: `extends` for job templates, `!reference` for sharing `rules` and `script` lists, no anchors.**

### A complete pipeline

A Python service with a Dockerfile and a Helm chart in `charts/app/`. It lints, tests, builds one image per commit, packages the chart as OCI, deploys MRs to review environments and `main` to staging, and promotes tags to production. Speed techniques are in chapter 09, reuse in chapter 10, deploy details in chapter 11.

```yaml
# .gitlab-ci.yml
# Layout: pyproject.toml + uv.lock, src/, tests/, Dockerfile, charts/app/

workflow:
  name: '$PIPELINE_NAME'
  auto_cancel:
    on_new_commit: interruptible          # 16.8+: newer commit cancels interruptible jobs
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      variables: { PIPELINE_NAME: 'MR !$CI_MERGE_REQUEST_IID: $CI_MERGE_REQUEST_TITLE' }
    - if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS && $CI_PIPELINE_SOURCE == "push"
      when: never                         # the MR pipeline covers this push
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
      variables: { PIPELINE_NAME: 'Release $CI_COMMIT_TAG' }
    - if: $CI_COMMIT_BRANCH
      variables: { PIPELINE_NAME: 'Branch: $CI_COMMIT_BRANCH' }

stages: [lint, test, build, package, deploy]

variables:
  # One image per commit; tags are aliases pushed on release.
  IMAGE: $CI_REGISTRY_IMAGE/app:$CI_COMMIT_SHORT_SHA
  CHART_REPO: oci://$CI_REGISTRY/$CI_PROJECT_PATH/charts
  UV_CACHE_DIR: $CI_PROJECT_DIR/.cache/uv
  PIP_DISABLE_PIP_VERSION_CHECK: "1"
  GIT_DEPTH: "20"                         # enough for most tools; release jobs override

default:
  image: docker.io/library/python:3.13-slim   # pin by digest in real use
  interruptible: true                     # safe default; deploy jobs opt out
  tags: [k8s, amd64]
  retry:
    max: 2
    when: [runner_system_failure, stuck_or_timeout_failure, scheduler_failure]

# ---------- reusable fragments ----------

.rules:mr-main-tag:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_COMMIT_TAG

.python:
  cache:
    key:
      files: [uv.lock]                    # new key only when dependencies change
      prefix: uv
    paths: [.cache/uv]
    policy: pull-push
  before_script:
    - pip install --quiet "uv==UV_VERSION"
    - uv sync --frozen --all-groups

.helm:
  image: docker.io/alpine/helm:HELM_VERSION   # pick a pinned 3.x or 4.x tag
  before_script:
    - echo "$CI_REGISTRY_PASSWORD" | helm registry login "$CI_REGISTRY" -u "$CI_REGISTRY_USER" --password-stdin

# ---------- lint ----------

ruff:
  stage: lint
  extends: .python
  needs: []                               # start at t=0
  rules: !reference [.rules:mr-main-tag, rules]
  script:
    - uv run ruff check --output-format=gitlab --output-file=gl-code-quality.json . || RC=$?
    - uv run ruff format --check .
    - exit ${RC:-0}
  artifacts:
    when: always
    reports:
      codequality: gl-code-quality.json   # findings inline in the MR diff

mypy:
  stage: lint
  extends: .python
  needs: []
  rules: !reference [.rules:mr-main-tag, rules]
  script:
    - uv run mypy src

helm:lint:
  stage: lint
  extends: .helm
  needs: []
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes: { paths: [charts/**/*] }
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_COMMIT_TAG
  before_script: []                       # no registry login needed to lint
  script:
    - helm lint charts/app --strict
    - helm template app charts/app -f charts/app/values-ci.yaml > /dev/null

# ---------- test ----------

pytest:
  stage: test
  extends: .python
  needs: []                               # tests do not depend on lint passing
  rules: !reference [.rules:mr-main-tag, rules]
  services:
    - name: docker.io/library/postgres:17
      alias: db
  variables:
    POSTGRES_PASSWORD: ci                 # throwaway, service-local only
    DATABASE_URL: postgresql://postgres:ci@db:5432/postgres
  script:
    - uv run pytest -n auto --junitxml=report.xml --cov=src --cov-report=term --cov-report=xml:coverage.xml
  coverage: '/TOTAL.*\s+(\d+%)$/'         # parses the term report for the MR badge
  artifacts:
    when: always
    expire_in: 1 week
    reports:
      junit: report.xml                   # test results tab + MR widget
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml                # line coverage in the MR diff

# ---------- build ----------

build:image:
  stage: build
  image:
    name: docker.io/moby/buildkit:BUILDKIT_VERSION-rootless
    entrypoint: [""]
  needs: [ruff, pytest]                   # mypy and helm:lint do not gate the image
  rules: !reference [.rules:mr-main-tag, rules]
  variables:
    BUILDKITD_FLAGS: --oci-worker-no-process-sandbox
  before_script:
    - mkdir -p ~/.docker
    - printf '{"auths":{"%s":{"username":"%s","password":"%s"}}}' "$CI_REGISTRY" "$CI_REGISTRY_USER" "$CI_REGISTRY_PASSWORD" > ~/.docker/config.json
  script:
    - |
      buildctl-daemonless.sh build \
        --frontend dockerfile.v0 \
        --local context=. --local dockerfile=. \
        --opt build-arg:VERSION="${CI_COMMIT_TAG:-$CI_COMMIT_SHORT_SHA}" \
        --output type=image,name="$IMAGE",push=true \
        --export-cache type=registry,ref="$CI_REGISTRY_IMAGE/cache:buildkit",mode=max \
        --import-cache type=registry,ref="$CI_REGISTRY_IMAGE/cache:buildkit" \
        --metadata-file metadata.json
    - |
      # block scalar: the '": ' inside this line would otherwise be parsed as a YAML key
      DIGEST=$(sed -n 's/.*"containerimage.digest": *"\([^"]*\)".*/\1/p' metadata.json)
      echo "IMAGE_DIGEST=$DIGEST" > build.env
  artifacts:
    reports:
      dotenv: build.env                   # IMAGE_DIGEST for every job that needs this one

# ---------- package ----------

helm:package:
  stage: package
  extends: .helm
  needs: [helm:lint]
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_COMMIT_TAG
  script:
    - VERSION="${CI_COMMIT_TAG#v}"
    - VERSION="${VERSION:-0.0.0-$CI_PIPELINE_IID.$CI_COMMIT_SHORT_SHA}"   # SemVer prerelease for main
    - helm package charts/app --version "$VERSION" --app-version "${CI_COMMIT_TAG:-$CI_COMMIT_SHORT_SHA}"
    - helm push app-"$VERSION".tgz "$CHART_REPO"
    - echo "CHART_VERSION=$VERSION" > chart.env
  artifacts:
    reports:
      dotenv: chart.env

# ---------- deploy ----------

.deploy:
  extends: .helm
  interruptible: false                    # never cancel a half-applied release
  variables:
    KUBE_CONTEXT: group/infra/agents:k8s-agent   # GitLab agent for Kubernetes
  script:
    - |
      helm upgrade --install "$RELEASE" charts/app \
        --kube-context "$KUBE_CONTEXT" \
        --namespace "$NAMESPACE" --create-namespace \
        -f "charts/app/values-${VALUES}.yaml" \
        --set image.repository="$CI_REGISTRY_IMAGE/app" \
        --set image.digest="$IMAGE_DIGEST" \
        --wait --timeout 10m

deploy:review:
  extends: .deploy
  stage: deploy
  needs:
    - build:image
    - job: helm:lint
      optional: true                      # helm:lint only runs when charts/ changed
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  variables:
    RELEASE: app-mr-$CI_MERGE_REQUEST_IID
    NAMESPACE: review-$CI_MERGE_REQUEST_IID
    VALUES: review
  environment:
    name: review/$CI_COMMIT_REF_SLUG
    url: https://mr-$CI_MERGE_REQUEST_IID.review.example.internal
    on_stop: stop:review
    auto_stop_in: 3 days
    deployment_tier: development
  resource_group: review/$CI_COMMIT_REF_SLUG

stop:review:
  extends: .helm
  stage: deploy
  needs: [deploy:review]
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      when: manual
      allow_failure: true
  variables:
    GIT_STRATEGY: none                    # branch may be deleted by the time this runs
    KUBE_CONTEXT: group/infra/agents:k8s-agent
  before_script: []
  script:
    - helm uninstall "app-mr-$CI_MERGE_REQUEST_IID" --kube-context "$KUBE_CONTEXT" --namespace "review-$CI_MERGE_REQUEST_IID" --wait || true
  environment:
    name: review/$CI_COMMIT_REF_SLUG
    action: stop

deploy:staging:
  extends: .deploy
  stage: deploy
  needs: [build:image, helm:package, mypy]
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  variables: { RELEASE: app, NAMESPACE: app-staging, VALUES: staging }
  environment:
    name: staging
    url: https://app.staging.example.internal
    deployment_tier: staging
  resource_group: staging

deploy:production:
  extends: .deploy
  stage: deploy
  needs: [build:image, helm:package]
  rules:
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
      when: manual                        # plus protected-environment approval
      allow_failure: false                # pipeline shows "blocked" until deployed
  variables: { RELEASE: app, NAMESPACE: app-production, VALUES: production }
  environment:
    name: production
    url: https://app.example.internal
    deployment_tier: production
  resource_group: production
```

#### What to notice

- **`workflow:rules` first**, with names, so the pipeline list reads as a log.
- **Every job has `needs`**, so lint, tests and chart lint all start at t=0, and the image build waits only for what gates it.
- **The image is built once per commit** and addressed by **digest** in every deploy. Tags are cosmetic; the digest in `IMAGE_DIGEST` travels by `dotenv`.
- **Deploy jobs are `interruptible: false`** and serialised with `resource_group`; everything else is interruptible so a new push cancels stale work.
- **`.rules:mr-main-tag` is defined once** and spliced with `!reference`; the only jobs with custom rules are the ones that genuinely differ.
- **Reports** (`codequality`, `junit`, `coverage_report`) put results in the MR widget instead of in logs nobody opens. The partner chapter on CI reporting covers the formats.
- **Deploys use the chart from the checkout** for simplicity. For stricter promotion, deploy the pushed OCI chart instead: `helm upgrade --install app "$CHART_REPO/app" --version "$CHART_VERSION"`, so production runs the exact chart artefact staging ran.
- **Placeholders** (`UV_VERSION`, `HELM_VERSION`, `BUILDKIT_VERSION`) are deliberate: pin real versions, and digests for images.

> **Note.** Using the GitLab agent for Kubernetes, the `KUBE_CONTEXT` is `path/to/agent-config-project:agent-name` and the agent must authorise this project in its `ci_access` config. Jobs then get a kubeconfig automatically; no cluster credentials live in CI variables. Chapter 11 covers the alternatives.

### Traps

- **No `workflow:rules`.** Duplicate branch and MR pipelines on every push to a branch with an MR.
- **`when: manual` in rules without `allow_failure: true`.** Pipeline blocked, MR unmergeable.
- **`needs` on a job whose rules may exclude it.** Pipeline creation error; add `optional: true`.
- **`$CI_COMMIT_BRANCH` in MR pipelines.** Empty. Use `$CI_COMMIT_REF_NAME` or `$CI_MERGE_REQUEST_SOURCE_BRANCH_NAME`.
- **Anchors across includes.** They do not work; use `extends` or `!reference`.
- **`extends` expecting arrays to merge.** They are replaced; splice with `!reference`.
- **Project variables overriding YAML.** Check Settings > CI/CD > Variables when a YAML change "does nothing".
- **Mixing `only/except` with `rules`.** Invalid in one job; convert the job fully.
- **Building a new image per environment.** Build once, promote the digest.


---


<a id="09-fast-cheap-pipelines"></a>

## 09 · Fast, cheap pipelines

*Pipeline time is dominated by waiting, not working: waiting for a stage to drain, for a cache to download, for a runner to schedule, for a clone to finish. Measure the critical path first, then remove waits in order of size. Most pipelines halve with needs, a correct cache key and interruptible alone.*

### Measure before you tune

Before changing anything, find the **critical path**: the longest chain of dependent jobs from pipeline start to finish. Only jobs on that path affect wall-clock time; speeding up anything else just saves runner minutes.

```bash
# Duration and queue time for every job in the latest pipeline on the current branch
glab ci get -F json | jq -r '
  .jobs[] | [.name, .stage, .status, (.queued_duration // 0 | floor), (.duration // 0 | floor)]
  | @tsv' | sort -t$'\t' -k5 -n -r | column -t

# Same for a specific pipeline
glab ci get -p PIPELINE_ID -F json | jq '.duration, .queued_duration'

# Last 20 pipelines on main: duration trend
glab ci list -r main -P 20 -F json | jq -r '.[] | [.id, .status, .created_at] | @tsv'
glab api "projects/:id/pipelines/PIPELINE_ID" | jq '{duration, queued_duration}'
```

Numbers to look at:

| Metric | Where | Healthy | Smell |
|---|---|---|---|
| Pipeline duration | pipeline JSON `duration` | MR pipeline under 10 min | Over 20 min: people stop waiting and context-switch |
| Queued duration | job JSON `queued_duration` | under 30 s | Minutes: too few runners, or tags nobody serves |
| Job setup time | job log: time before your first `script` line | under 30 s | Image pull, clone and cache download dominate |
| Critical path | the pipeline graph with "job dependencies" view | 3 to 5 jobs | Stage waterfall; everything waits for the slowest job in each stage |

Build > Pipelines > **CI/CD analytics** (Analyze > CI/CD analytics on newer versions) shows success rate and duration percentiles over time. Look at p50 and p95, not the mean: the p95 is what developers remember.

#### Timestamps and sections in job logs

Collapsible sections with their own duration make the slow step visible in the log itself:

```yaml
test:
  script:
    - echo -e "\e[0Ksection_start:$(date +%s):deps[collapsed=true]\r\e[0KInstalling dependencies"
    - uv sync --frozen
    - echo -e "\e[0Ksection_end:$(date +%s):deps\r\e[0K"
    - uv run pytest
```

Runner feature flags help without editing scripts:

```yaml
variables:
  FF_SCRIPT_SECTIONS: "true"   # each script line becomes a timed, collapsible section
  FF_TIMESTAMPS: "true"        # per-line timestamps in the job log
```

> **Version-sensitive.** `FF_TIMESTAMPS` needs GitLab Runner 17.0+ with a matching GitLab version; `FF_SCRIPT_SECTIONS` has been available longer. Runner feature flags can be set as CI variables or in the runner's `config.toml` `[runners.feature_flags]`.

### The order of work

Ranked by typical payoff per hour of effort:

| # | Change | Typical saving | Section |
|---|---|---|---|
| 1 | Wire jobs with `needs` instead of stage waterfalls | 20 to 50% wall time | chapter 08 |
| 2 | `interruptible` + auto-cancel | Runner cost on busy branches | below |
| 3 | Correct cache key and policy | 30 s to several minutes per job | below |
| 4 | Registry layer cache for image builds | Minutes per build | below |
| 5 | `rules:changes` to skip irrelevant jobs | Whole jobs | below |
| 6 | `parallel` test sharding | Test time divided by N | below |
| 7 | Right-size runners | Variable | below |
| 8 | Shallow clone | Seconds to minutes on big repos | below |

### Cache vs artifacts

They look similar (both are "files saved from a job") and are used for opposite things.

| | Cache | Artifacts |
|---|---|---|
| Purpose | Speed up **repeat** work: downloaded dependencies | Pass **results** between jobs and keep them |
| Stored | On the runner or in the runner's distributed cache (S3/GCS/Azure) | In GitLab |
| Guaranteed present | **No**: best effort, may be missing | **Yes**, for jobs that `needs`/`dependencies` on the producer, until expiry |
| Scope | Any pipeline using the same key (across branches) | This pipeline (and downloadable later) |
| Default expiry | Until evicted or cleared | 30 days (instance-configurable); latest artifacts kept by default |
| Visible in UI | No | Yes, browsable and downloadable |

#### When each is wrong

- **Using cache to pass build output to the next job.** Cache is best-effort; on a different runner, or after eviction, the next job gets nothing and fails intermittently. Use artifacts.
- **Using artifacts for `node_modules` or a virtualenv.** Every downstream job downloads hundreds of MB from GitLab, and they are kept for 30 days per pipeline. Use cache.
- **Caching the virtualenv instead of the download cache.** Virtualenvs embed absolute paths and interpreter versions; a Python image bump silently breaks them. Cache `UV_CACHE_DIR` or `PIP_CACHE_DIR` and rebuild the venv, which is fast from a warm cache.
- **Caching on the Kubernetes executor without a distributed cache.** Each job is a fresh pod; local cache lives in a volume that is gone after the job. Without `[runners.cache]` pointed at S3-compatible storage (MinIO, GCS, S3), `cache:` does nothing except cost upload time.

```bash
# In a job log, a cache that is working looks like:
#   Checking cache for uv-3f2a...-protected...
#   Downloading cache from https://minio.internal/runner/project/123/uv-3f2a...
#   Successfully extracted cache
# A cache that never works on k8s without distributed cache:
#   No URL provided, cache will not be downloaded from shared cache server.
```

### Cache keys

The key decides **who shares** a cache. Too broad and jobs fight over it; too narrow and it is always cold.

#### key:files

The best default for dependency caches: the key is a hash of the lockfile, so it changes exactly when dependencies change.

```yaml
.uv-cache:
  cache:
    key:
      files: [uv.lock]         # up to 2 files
      prefix: uv-py313          # separate caches per Python version; keys cannot contain /
    paths: [.cache/uv]
  variables:
    UV_CACHE_DIR: $CI_PROJECT_DIR/.cache/uv
  after_script:
    - uv cache prune --ci      # drop pre-built wheels that are cheap to re-download; shrinks the upload
```

`prefix` is prepended to the hash. If none of the listed files exist, the key falls back to `default`.

> **Gotcha.** Cache `paths` must be inside `$CI_PROJECT_DIR`. `~/.cache/pip` or `/root/.cache/uv` are silently not cached. Point the tool's cache directory into the project with its environment variable (`UV_CACHE_DIR`, `PIP_CACHE_DIR`, `npm_config_cache`, `GOMODCACHE`, `GOCACHE`).

#### fallback_keys

When the primary key misses (lockfile just changed), start from an older cache instead of empty:

```yaml
cache:
  key:
    files: [uv.lock]
    prefix: uv
  fallback_keys:
    - uv-$CI_DEFAULT_BRANCH    # a cache main keeps warm
    - uv-default
  paths: [.cache/uv]
```

Up to five fallback keys, tried in order. A `CACHE_FALLBACK_KEY` CI/CD variable, if set, is tried last.

> **Version-sensitive.** `cache:fallback_keys` needs GitLab 16.0+.

A pattern that makes fallbacks useful: a job on `main` also pushes to a stable key.

```yaml
warm-cache:
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  cache:
    - key: uv-$CI_DEFAULT_BRANCH
      paths: [.cache/uv]
      policy: push
  script:
    - uv sync --frozen
```

#### key:files_commits

A newer variant keys on the **latest commit that touched** the listed files rather than their content hash. Content hashing (`files`) is the better default because a revert produces the same key as before; use `files_commits` only if the files are large and hashing them is itself slow.

> **Version-sensitive.** `cache:key:files_commits` arrived in GitLab 18.4, in the same release that changed `cache:key:files` from commit-based to **content-based** keys. Before 18.4, `key:files` itself keyed on the last commit that touched the files, so on older instances you already have `files_commits` behaviour under the `files` name. The two cannot be combined in one cache.

#### policy: pull, push, pull-push

| Policy | Downloads | Uploads | Use for |
|---|---|---|---|
| `pull-push` (default) | yes | yes | A single job that both uses and refreshes the cache |
| `pull` | yes | no | Many parallel jobs that only consume the cache |
| `push` | no | yes | One job whose purpose is to (re)build the cache |

Uploading is often slower than downloading. If eight test shards all `pull-push` the same key, you pay eight uploads of an identical archive and race on who wins. Make one job populate the cache and the rest `pull`:

```yaml
deps:
  stage: .pre
  cache: { key: { files: [uv.lock] }, paths: [.cache/uv], policy: pull-push }
  script: [uv sync --frozen]

pytest:
  parallel: 8
  needs: [deps]
  cache: { key: { files: [uv.lock] }, paths: [.cache/uv], policy: pull }
  script: [uv sync --frozen, uv run pytest ...]
```

Make the policy conditional so MR branches never overwrite the cache that `main` relies on (variables in `cache:policy` need GitLab 16.1+):

```yaml
cache:
  key: { files: [uv.lock] }
  paths: [.cache/uv]
  policy: $CACHE_POLICY
variables:
  CACHE_POLICY: pull
rules:
  - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    variables: { CACHE_POLICY: pull-push }
  - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

#### Protected and unprotected caches

GitLab separates caches by protection: pipelines on protected refs use keys suffixed `-protected`, others `-non_protected`. An MR branch cannot poison the cache a protected `main` pipeline restores. This is a security feature, but it also means **MR pipelines do not see main's cache** by default. `cache:unprotect: true` shares them, at the cost of that isolation.

> **Gotcha.** "Clear runner caches" (Build > Pipelines) does not delete anything. It increments an index in the key (`cache-1`, `cache-2`), so every job misses once and old archives age out of the bucket via its lifecycle rules. Put a lifecycle expiry (for example 14 days) on the distributed-cache bucket or it grows forever.

#### Multiple caches per job

A job can have up to four caches, each with its own key and policy:

```yaml
cache:
  - key: { files: [uv.lock], prefix: uv }
    paths: [.cache/uv]
  - key: pre-commit-v1
    paths: [.cache/pre-commit]
    policy: pull
```

### interruptible and auto-cancel

When you push twice in a row, the first pipeline is redundant. Auto-cancel stops it, but only jobs marked `interruptible: true`.

```yaml
default:
  interruptible: true          # safe default for build/test

workflow:
  auto_cancel:
    on_new_commit: interruptible   # cancel only interruptible jobs, even if others started
    on_job_failure: all            # optional: first failure cancels the rest of the pipeline

deploy:production:
  interruptible: false         # never cancel a half-applied deploy
```

| `on_new_commit` | Behaviour |
|---|---|
| `conservative` (default) | Cancel the old pipeline only if **no** `interruptible: false` job has started yet |
| `interruptible` | Cancel every interruptible job, leave non-interruptible ones running |
| `none` | Never auto-cancel |

| `on_job_failure` | Behaviour |
|---|---|
| `none` (default) | Keep running other jobs after a failure |
| `all` | Cancel all running and pending jobs as soon as one fails |

> **Version-sensitive.** `workflow:auto_cancel:on_new_commit` arrived in GitLab 16.8 behind a disabled flag, on by default in 16.9 and GA in 16.10; `on_job_failure` arrived in 16.10 behind a flag and went GA in 16.11; `rules:interruptible` (overriding per rule) needs 16.10+. Before that, only the project setting "Auto-cancel redundant pipelines" plus job-level `interruptible` exist, with `conservative` behaviour.

The project setting **Settings > CI/CD > General pipelines > Auto-cancel redundant pipelines** must also be on (it is by default for new projects).

> **Gotcha.** With `conservative`, a single early non-interruptible job (a `.pre` job that notifies Jira, for example) makes the whole pipeline uncancellable. Either mark it interruptible or switch to `on_new_commit: interruptible`.

> **Note.** `on_job_failure: all` gives fast failure feedback and saves minutes, but it hides the **second** failure: developers fix lint, push, and only then learn tests also fail. Use it on expensive pipelines (e2e, big matrices), not as a blanket default.

### needs with artifacts: false

Every job in `needs` downloads that job's artefacts by default. Large artefacts (test reports, coverage HTML, wheel directories) add time to every consumer that does not use them.

```yaml
deploy:staging:
  needs:
    - job: build:image             # needs its dotenv (IMAGE_DIGEST)
    - job: pytest                  # gate only; do not download its 200 MB coverage HTML
      artifacts: false
```

Also set `expire_in` on large, short-lived artefacts and keep reports small:

```yaml
artifacts:
  expire_in: 3 days
  paths: [dist/]
  exclude: [dist/**/*.map]
```

> **Gotcha.** `dotenv` report variables travel with the artefacts. With `artifacts: false` on a `needs` entry, the consumer does **not** get that job's dotenv variables. Keep `artifacts: true` on the job that publishes the dotenv, and keep that job's other artefacts small.

### Parallel jobs

#### parallel: N (test sharding)

`parallel: N` runs N copies of the job; each sees `CI_NODE_INDEX` (1..N) and `CI_NODE_TOTAL`. Your test runner splits the work.

```yaml
pytest:
  parallel: 6
  script:
    # pytest-split balances by recorded durations (.test_durations committed to the repo)
    - uv run pytest --splits "$CI_NODE_TOTAL" --group "$CI_NODE_INDEX" --junitxml=report-$CI_NODE_INDEX.xml
  artifacts:
    when: always
    reports:
      junit: report-*.xml          # GitLab merges all shards in the MR widget
```

Refresh durations occasionally (`uv run pytest --store-durations` on a scheduled pipeline, committing the result via an MR), or shards drift out of balance and the slowest one dominates.

Sharding pays off when per-job setup is small compared to test time. With 60 s of setup and 90 s of tests, six shards cost 6 × 60 s of setup to save 75 s of wall time. **Try `pytest -n auto` (pytest-xdist) on one bigger runner first**; it parallelises with no setup duplication.

#### parallel: matrix

Runs one job per combination of variable values:

```yaml
test:
  image: docker.io/library/python:$PY-slim
  parallel:
    matrix:
      - PY: ["3.12", "3.13", "3.14"]
        DB: [postgres, sqlite]
      - PY: ["3.13"]
        DB: [mysql]
  script:
    - uv run pytest --db "$DB"
```

That is 3 × 2 + 1 = 7 jobs, named like `test: [3.12, postgres]`. Limit: 200 jobs per `parallel:matrix`.

Depend on one combination with `needs:parallel:matrix`:

```yaml
publish:
  needs:
    - job: test
      parallel:
        matrix:
          - PY: "3.13"
            DB: postgres
```

> **Version-sensitive.** `needs:parallel:matrix` needs GitLab 16.3+. Matrix variables work in `script`, `image`, `services` and `tags`. [Current docs](https://docs.gitlab.com/ci/jobs/job_control/#use-matrix-variables-in-rules) say rules are evaluated per matrix job, so `rules:if`, `rules:changes` and `rules:exists` see that job's values (no nested expansion: `FILE: $OTHER` stays literal). That section was only added to the docs in May 2026, and a regression where `rules:if` stopped seeing matrix variables was reported in late 2025 (issue 581340), so confirm the job list with `glab ci lint --dry-run --include-jobs` on your instance.

A common use is building multi-architecture images on native runners instead of QEMU emulation:

```yaml
build:image:
  parallel:
    matrix:
      - ARCH: [amd64, arm64]
  tags: [k8s, $ARCH]           # route each copy to a native runner
  script:
    - buildctl-daemonless.sh build ... --output type=image,name=$IMAGE-$ARCH,push=true

build:manifest:
  needs: [build:image]
  script:
    - docker buildx imagetools create -t "$IMAGE" "$IMAGE-amd64" "$IMAGE-arm64"
```

### Skip work with rules:changes

Do not run the chart linter when nobody touched the chart.

```yaml
helm:lint:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes:
        paths: [charts/**/*]
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH   # always on main
```

What `changes` compares against:

| Pipeline | Compared against |
|---|---|
| MR pipeline | The MR's diff (target branch merge base to source HEAD) |
| Branch pipeline, existing branch | The commits in **this push** only |
| Branch pipeline, new branch | Nothing to compare: `changes` is **true** |
| Tag, schedule, web, API, trigger | No push diff: `changes` is **true** |
| Any, with `compare_to: refs/heads/main` | Diff against that ref |

> **Gotcha.** On branch pipelines, `changes` sees only the **last push**, not the branch as a whole. Push a chart change, then push a README fix: the second pipeline skips `helm:lint`, and if that pipeline is the one "Pipelines must succeed" checks, a chart change merges without its lint. Use `changes` in **MR pipelines** (where it covers the whole MR diff) and run everything on `main`. Chapter 12 has more traps.

`compare_to` makes branch pipelines behave like MR pipelines:

```yaml
rules:
  - changes:
      paths: [charts/**/*]
      compare_to: refs/heads/main
```

> **Version-sensitive.** `rules:changes:compare_to` needs GitLab 15.3+.

#### Monorepo: one job template, many paths

```yaml
.service:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes:
        paths: ["services/$SERVICE/**/*", "libs/**/*", "uv.lock"]
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  script:
    - uv run --package "$SERVICE" pytest "services/$SERVICE"

test:billing:
  extends: .service
  variables: { SERVICE: billing }
test:auth:
  extends: .service
  variables: { SERVICE: auth }
```

Variables in `changes:paths` are expanded from job and pipeline variables. For a large monorepo, generate the job list dynamically instead (chapter 10, dynamic child pipelines).

### Clone less

#### GIT_DEPTH

New projects default to a shallow clone depth of **20**. For most jobs that is right; for some it is wrong.

| Job | Setting | Why |
|---|---|---|
| Lint, test, build | `GIT_DEPTH: "20"` or even `"1"` | Only need the tree |
| Changelog, `git describe`, version bump | `GIT_DEPTH: "0"` (full clone) | Need tags and history |
| Diff-based linters (`--since $CI_MERGE_REQUEST_DIFF_BASE_SHA`) | Deep enough to include the merge base, or `0` | Shallow clone may not contain the base commit |
| Deploy with `GIT_STRATEGY: none` | n/a | No checkout at all |

```yaml
variables:
  GIT_DEPTH: "20"
release:
  variables:
    GIT_DEPTH: "0"
```

#### Other git knobs

| Variable | Values | Use |
|---|---|---|
| `GIT_STRATEGY` | `clone`, `fetch` (default), `none`, `empty` | `fetch` reuses the runner's working copy; `none` for jobs that only use artefacts |
| `GIT_SUBMODULE_STRATEGY` | `none`, `normal`, `recursive` | Only fetch submodules for jobs that need them |
| `GIT_SUBMODULE_DEPTH` | number | Shallow submodules |
| `GIT_FETCH_EXTRA_FLAGS` | e.g. `--no-tags` | Skip fetching every tag on big repos |
| `GIT_LFS_SKIP_SMUDGE` | `1` | Do not download LFS objects unless the job needs them |
| `GIT_CLEAN_FLAGS` | e.g. `-ffdx -e .cache/` | Keep caches between fetches on persistent runners |

> **Gotcha.** `GIT_STRATEGY: fetch` has no benefit on Kubernetes or autoscaled Docker Machine / fleeting runners, where every job starts in a new, empty build directory. It helps on long-lived shell or Docker runners with persistent build volumes.

### Runners: tags and sizing

#### Route by tag

Runners advertise tags; jobs request them. A job runs only on a runner that has **all** of the job's tags.

```yaml
default:
  tags: [k8s, amd64]            # everyday jobs
pytest:
  tags: [k8s, amd64, large]     # a runner with bigger pod limits
build:arm:
  tags: [k8s, arm64]
```

Keep tags about **capability** (`arm64`, `gpu`, `large`, `privileged`), not about teams or projects.

> **Gotcha.** A job whose tag combination no runner offers sits in **pending** forever ("This job is stuck because you don't have any active runners online or available with any of these tags assigned to them"). Check with `glab runner list` (if you can see the runners) and compare tags. Chapter 12 covers diagnosis.

#### Size per job on Kubernetes

The Kubernetes executor lets jobs request resources through variables, within limits the runner admin allows (`cpu_request_overwrite_max_allowed`, `memory_limit_overwrite_max_allowed` and friends in `config.toml`):

```yaml
pytest:
  variables:
    KUBERNETES_CPU_REQUEST: "4"
    KUBERNETES_CPU_LIMIT: "4"
    KUBERNETES_MEMORY_REQUEST: 6Gi
    KUBERNETES_MEMORY_LIMIT: 6Gi
  script:
    - uv run pytest -n 4
```

Rules of thumb:

- **Match `-n` / worker counts to the CPU request**, not the node's CPU count. `nproc` inside a pod reports the node's cores, and `pytest -n auto` will oversubscribe a 2-CPU pod on a 32-core node.
- **Set memory request = limit** for CI pods; OOM kills mid-test are worse than a slightly lower bin-packing density.
- **Image pull time is setup time.** Use `pull_policy: if-not-present` on the runner for pinned-digest images, a registry mirror close to the runners, and slim images.

#### Cost levers

| Lever | Effect |
|---|---|
| Spot/preemptible node pool for CI | 60 to 80% cheaper; add `retry: when: [runner_system_failure]` for evictions |
| Scale-to-zero node pool | Pay nothing idle; costs cold-start latency on the first job |
| One large runner vs many shards | Fewer setups; cheaper if setup dominates |
| `rules:changes` in MRs | Jobs that do not run cost nothing |
| `interruptible` + auto-cancel | Redundant pipelines stop billing |

### Building images

This is where the most time and most security risk hide.

| Builder | Privileged | Layer cache | Speed | Status | Verdict |
|---|---|---|---|---|---|
| **Docker-in-Docker** (`docker:dind` service) | **Yes** | Registry `--cache-from`; local cache lost per job | Good | Maintained | Only on dedicated, isolated privileged runners |
| **Docker socket bind** (`/var/run/docker.sock`) | Effectively root on the host | Host cache, shared | Fastest | n/a | **Never on shared runners**: any job controls the host |
| **BuildKit rootless** (`moby/buildkit:*-rootless`, `buildctl-daemonless.sh`) | No (needs unconfined seccomp/AppArmor, or user namespaces) | Registry cache, `mode=max` | Best | Maintained, same engine as `docker buildx` | **Default** |
| **Buildah / Podman** rootless | No (needs `fuse-overlayfs` or `vfs`) | Registry cache via `--layers --cache-to/--cache-from` | Good with overlay, slow with vfs | Maintained | Pick if you standardise on Podman; RHEL/Fedora-native |
| **kaniko** | No | Registry cache (`--cache=true`) | Slower on large images | **Google archived it (June 2025)**; community forks (Chainguard and others) | Migrate away; do not start new pipelines on it |

**Default: rootless BuildKit** via `buildctl-daemonless.sh`. It is the same engine as `docker buildx`, so Dockerfile features (`RUN --mount=type=cache`, `--mount=type=secret`, heredocs, multi-platform) behave identically locally and in CI; it needs no privileged pod; and registry cache export with `mode=max` caches intermediate stages, not just the final one. The tiebreaker for **Buildah** is organisational: if your platform is Podman-first and you want one toolchain on laptops and CI, Buildah is fine, but budget for storage-driver tuning.

#### Rootless BuildKit with registry cache

```yaml
build:image:
  image:
    name: docker.io/moby/buildkit:BUILDKIT_VERSION-rootless
    entrypoint: [""]
  variables:
    BUILDKITD_FLAGS: --oci-worker-no-process-sandbox
  before_script:
    - mkdir -p ~/.docker
    - printf '{"auths":{"%s":{"username":"%s","password":"%s"}}}' "$CI_REGISTRY" "$CI_REGISTRY_USER" "$CI_REGISTRY_PASSWORD" > ~/.docker/config.json
  script:
    - |
      buildctl-daemonless.sh build \
        --frontend dockerfile.v0 \
        --local context=. --local dockerfile=. \
        --output type=image,name="$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA",push=true \
        --import-cache type=registry,ref="$CI_REGISTRY_IMAGE/cache:main" \
        --import-cache type=registry,ref="$CI_REGISTRY_IMAGE/cache:$CI_COMMIT_REF_SLUG" \
        --export-cache type=registry,ref="$CI_REGISTRY_IMAGE/cache:$CI_COMMIT_REF_SLUG",mode=max
```

Importing both the branch cache and `main`'s cache means a new branch starts warm. On the Kubernetes executor, rootless BuildKit needs the build pod to run with seccomp and AppArmor `Unconfined` (set by the runner admin via pod annotations or `pod_security_context`), because it creates user namespaces and mounts.

#### Docker-in-Docker, if you must

```yaml
build:image:
  image: docker.io/library/docker:DOCKER_VERSION
  services:
    - name: docker.io/library/docker:DOCKER_VERSION-dind
      alias: docker
  variables:
    DOCKER_HOST: tcp://docker:2376
    DOCKER_TLS_CERTDIR: /certs
    DOCKER_TLS_VERIFY: "1"
    DOCKER_CERT_PATH: /certs/client
  tags: [privileged]           # only runners dedicated to this
  script:
    - echo "$CI_REGISTRY_PASSWORD" | docker login -u "$CI_REGISTRY_USER" --password-stdin "$CI_REGISTRY"
    - docker buildx create --use --driver docker-container
    - |
      docker buildx build \
        --cache-from type=registry,ref=$CI_REGISTRY_IMAGE/cache:main \
        --cache-to type=registry,ref=$CI_REGISTRY_IMAGE/cache:$CI_COMMIT_REF_SLUG,mode=max \
        -t "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA" --push .
```

> **One-way door.** A privileged runner that accepts jobs from any project hands root on the node to anyone who can push a branch. You cannot un-leak what a malicious job read from the node. If you run DinD, give it a dedicated node pool, a `privileged` tag, and restrict the runner to specific projects (or protected branches only).

#### Dockerfile habits that matter more than the builder

```dockerfile
# syntax=docker/dockerfile:1
FROM docker.io/library/python:3.13-slim AS build
COPY --from=ghcr.io/astral-sh/uv:UV_VERSION /uv /usr/local/bin/uv
WORKDIR /app
# Dependencies first: this layer only rebuilds when the lockfile changes
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-install-project --no-dev
# Then source: changes here do not invalidate the dependency layer
COPY src/ src/
RUN --mount=type=cache,target=/root/.cache/uv uv sync --frozen --no-dev
```

`RUN --mount=type=cache` helps locally but does **not** persist between CI jobs (the BuildKit daemon is per-job). In CI, layer ordering plus registry cache with `mode=max` is what gives you hits.

### Checklist

- [ ] Critical path measured; you know which 3 to 5 jobs determine wall time.
- [ ] Every job wired with `needs`; independent jobs start at t=0 with `needs: []`.
- [ ] `default: interruptible: true`; deploy jobs `interruptible: false`; `workflow:auto_cancel:on_new_commit: interruptible`.
- [ ] Dependency caches keyed on lockfiles with `key:files`, fallback to a key `main` keeps warm.
- [ ] Parallel consumers use `policy: pull`; one job pushes.
- [ ] Distributed cache configured if runners are on Kubernetes or autoscaled, with a bucket lifecycle rule.
- [ ] Artefacts have `expire_in`; gate-only `needs` use `artifacts: false`.
- [ ] `rules:changes` used in MR pipelines, everything runs on `main`.
- [ ] `GIT_DEPTH` shallow by default, `0` for release jobs.
- [ ] Rootless BuildKit with registry cache; no socket mounts; DinD only on isolated runners.
- [ ] kaniko pipelines have a migration ticket.
- [ ] Worker counts match CPU requests, not node cores.


---


<a id="10-reuse-at-scale"></a>

## 10 · Reuse at scale

*Shared CI config is a library, and every library problem applies: versioning, interfaces, breaking changes and discoverability. Treat shared jobs as components with typed inputs and semantic versions, pin them like dependencies, and the forty repositories that use them stop breaking together.*

### The reuse ladder

From least to most structure. Move up a rung when the one you are on starts hurting.

| Rung | Mechanism | Interface | Versioning | Use for |
|---|---|---|---|---|
| 1 | `extends` / `!reference` in one file | none | the file | Deduplicating inside one project (chapter 08) |
| 2 | `include: local` | none | the repo | Splitting one big `.gitlab-ci.yml` into files |
| 3 | `include: project` from a central repo | **implicit**: variables the template happens to read | `ref:` (branch, tag, SHA) | Legacy shared templates |
| 4 | **CI/CD components** with `spec:inputs` | **explicit**, typed, validated | **semantic version** tags, catalog | **Default** for anything shared across projects |
| 5 | Parent-child and multi-project pipelines | `trigger:` + inputs/variables | per pipeline | Structuring big or cross-repo pipelines |

**Default: CI/CD components in a central group, consumed at a pinned major version (`@1`), with typed `spec:inputs`.** Plain `include: project` templates are the tiebreaker only when your instance predates GitLab 17.0, where components became generally available.

### include

Every include is fetched and **deep-merged** into one configuration before any rule is evaluated.

#### The five sources

```yaml
include:
  # 1. Same repository. Wildcards allowed: * one level, ** recursive
  - local: .gitlab/ci/*.yml

  # 2. Another project on this instance, at a ref
  - project: platform/ci-templates
    ref: v3.2.0                   # tag or SHA; a branch means "whatever is there now"
    file:
      - templates/python.yml
      - templates/docker.yml

  # 3. Any HTTPS URL (public, no auth)
  - remote: https://example.com/ci/common.yml
    integrity: sha256-BASE64_HASH    # GitLab 17.9+: refuse the file if the hash differs

  # 4. A template shipped with GitLab
  - template: Jobs/SAST.gitlab-ci.yml

  # 5. A CI/CD component
  - component: $CI_SERVER_FQDN/platform/components/python@1.4.0
    inputs:
      python-version: "3.13"
```

#### Merge rules

- **Maps merge recursively**; for the same key, the including file wins over the included one, and later includes win over earlier ones.
- **Arrays are replaced wholesale.** You cannot append one script line to an included job's `script`; you redefine the whole array, or use `!reference` to splice.
- **Jobs with the same name merge**, which is how you override a template job locally:

```yaml
include:
  - template: Jobs/SAST.gitlab-ci.yml

semgrep-sast:            # a job defined in the template
  tags: [k8s, amd64]     # merged in: only this key changes
  rules:                 # replaces the template's rules entirely
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
```

#### include:rules

Includes can be conditional:

```yaml
include:
  - local: .gitlab/ci/release.yml
    rules:
      - if: $CI_COMMIT_TAG
  - local: .gitlab/ci/helm.yml
    rules:
      - exists: [charts/*/Chart.yaml]
```

Only variables known **before** the config is parsed can be used: project, group and instance variables, pipeline variables (web, API, schedule, trigger) and predefined variables like `CI_COMMIT_REF_NAME`, `CI_PIPELINE_SOURCE` and `CI_PROJECT_*`. **Not** variables defined in the YAML itself (top-level or job `variables:`).

> **Gotcha.** `include:project` fetches the file with the permissions of **the user who triggered the pipeline**. A developer without access to `platform/ci-templates` gets "Project not found or access denied" and no pipeline. Make central template projects internal (or grant the consuming groups Reporter), and remember that scheduled pipelines run as the schedule owner.

#### Limits

A pipeline may include at most **150** files by default (self-managed admins can change it), counting nested includes and duplicates. The same file included twice counts twice. Remote includes have a fetch timeout; a flaky remote host means flaky pipeline creation.

### CI/CD components

A component is a reusable unit of pipeline config with a declared input interface, living in a **component project** and released with semantic version tags. Components can be published to the **CI/CD Catalog** so people can find them.

> **Version-sensitive.** Components and the CI/CD Catalog became generally available in GitLab 17.0 (experimental from 16.0, beta in 16.x). `$[[ component.* ]]` context interpolation arrived in 18.6 (beta) and 18.7 (GA). The per-project component limit was raised from 30 to 100 in 18.5.

#### Component project layout

```text
platform/components/            # the component project
├── README.md                   # required for the catalog
├── templates/
│   ├── python-test.yml         # single-file component: "python-test"
│   ├── docker-build/
│   │   ├── template.yml        # directory component: "docker-build" (only template.yml is released)
│   │   └── README.md           # extra files for docs/tests, not part of the component
│   └── helm-publish.yml
├── tests/                      # optional fixtures used by the project's own pipeline
└── .gitlab-ci.yml              # tests every component, then releases on tag
```

Component names come from the file or directory name under `templates/`: letters, digits, `_`, `-` and `.`.

#### Writing a component

A component file has a **header** with `spec:inputs`, then `---`, then ordinary pipeline YAML that references inputs with `$[[ inputs.NAME ]]`.

```yaml
# templates/python-test.yml
spec:
  inputs:
    stage:
      default: test
    python-version:
      type: string
      default: "3.13"
      options: ["3.12", "3.13", "3.14"]
      description: Python image tag to test with.
    test-path:
      default: tests
    workers:
      type: number
      default: 2
      description: pytest-xdist workers; match the runner's CPU request.
    coverage:
      type: boolean
      default: true
    job-prefix:
      default: python
      regex: ^[a-z][a-z0-9-]*$
      description: Prefix for job names, so a project can include this twice.
---
"$[[ inputs.job-prefix ]]:test":
  stage: $[[ inputs.stage ]]
  image: docker.io/library/python:$[[ inputs.python-version ]]-slim
  interruptible: true
  variables:
    UV_CACHE_DIR: $CI_PROJECT_DIR/.cache/uv
    COVERAGE: "$[[ inputs.coverage ]]"
  cache:
    key:
      files: [uv.lock]
      prefix: uv-$[[ inputs.job-prefix ]]
    paths: [.cache/uv]
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_COMMIT_TAG
  script:
    - pip install --quiet uv
    - uv sync --frozen
    - |
      ARGS="--junitxml=report.xml -n $[[ inputs.workers ]]"
      if [ "$COVERAGE" = "true" ]; then
        ARGS="$ARGS --cov=src --cov-report=xml:coverage.xml"
      fi
      uv run pytest $ARGS "$[[ inputs.test-path ]]"
  artifacts:
    when: always
    reports:
      junit: report.xml
```

#### Input types and validation

| Key | Meaning |
|---|---|
| `type` | `string` (default), `number`, `boolean`, `array` |
| `default` | Makes the input optional. **No default = mandatory**; pipeline creation fails if it is not supplied. Use `''` for an optional empty string |
| `options` | Allowed values (max 50) |
| `regex` | RE2 pattern the value must match (strings only) |
| `description` | Shown in the catalog and the Run pipeline form |
| `rules` | Conditional `options`/`default` based on other inputs (GitLab 18.7+) |

Interpolation functions, chained with `|`:

| Function | Does |
|---|---|
| `expand_vars` | Expands CI/CD variable references inside the input value |
| `truncate(offset, length)` | Substring |
| `posix_escape` | Escapes for safe use in a shell word (not a security boundary) |

> **Gotcha.** Inputs are interpolated **when the config is fetched**, as text substitution, before YAML-level merging and long before any job runs. An input can therefore change job names, stages, `needs`, `rules`, anything. It cannot read runtime state. If you need a value computed during the pipeline, it has to be a CI variable, not an input.

#### Inputs vs variables

| | Inputs | Variables |
|---|---|---|
| Resolved | At pipeline creation | At job runtime |
| Typed and validated | Yes | No |
| Can change structure (job names, `needs`, `stage`) | Yes | No |
| Visible to scripts | Only where interpolated | As environment variables |
| Overridable by a project variable of the same name | No | **Yes** (precedence, chapter 08) |

**Use inputs for a component's interface.** A template that reads `$PYTHON_VERSION` from the environment has an invisible interface that any project, group or instance variable of that name silently overrides.

#### Consuming a component

```yaml
include:
  - component: $CI_SERVER_FQDN/platform/components/python-test@1
    inputs:
      python-version: "3.13"
      workers: 4
  - component: $CI_SERVER_FQDN/platform/components/docker-build@1
    inputs:
      image-name: $CI_REGISTRY_IMAGE/app

# Override one key on the generated job, as with any include
python:test:
  tags: [k8s, amd64, large]
```

Always use `$CI_SERVER_FQDN`, not a hardcoded hostname, so the same config works on a staging instance and after a hostname migration.

#### Versions

| Reference | Resolves to | Use |
|---|---|---|
| `@1.4.2` | That tag | Maximum reproducibility; needs Renovate to bump |
| `@1.4` | Latest `1.4.*` release | Patch updates only |
| `@1` | Latest `1.*.*` release | **Default**: features and fixes, no breaking changes |
| `@~latest` | Latest release, excluding pre-releases | Only in the component project's own tests |
| `@SHA` | That commit | Pinning an unreleased fix |
| `@main` | Branch head | Never in consuming projects |

Partial versions (`@1`, `@1.4`) resolve only against **released** semantic-version tags (published to the catalog). If a SHA, tag and branch share a name, SHA wins, then tag, then branch.

**Default: `@1` (major pin) for internal components, exact versions plus Renovate for third-party components.** The tiebreaker: an internal platform team you can talk to is trusted to honour SemVer; a third party is not, and exact pins make every change reviewable.

> **One-way door.** Once projects consume `@1`, every `1.x` release lands in all of them on their next pipeline. A breaking change released as `1.5.0` breaks every consumer at once, and they did nothing. Treat input removals, renames, changed defaults and changed job names as **major** bumps. Job names count: consumers override jobs by name.

#### Testing and releasing a component

The component project's own pipeline includes its components **by SHA** and exercises them, then creates a release on a tag:

```yaml
# .gitlab-ci.yml in platform/components
include:
  - component: $CI_SERVER_FQDN/$CI_PROJECT_PATH/python-test@$CI_COMMIT_SHA
    inputs:
      test-path: tests/fixtures/python-app/tests
      job-prefix: selftest

stages: [test, release]

check-generated-jobs:
  stage: test
  image: docker.io/library/alpine:3.22
  script:
    - echo "selftest:test ran in this pipeline; add assertions on its artefacts here"
  needs: [selftest:test]

create-release:
  stage: release
  image: registry.gitlab.com/gitlab-org/cli:latest   # pin a version
  rules:
    - if: $CI_COMMIT_TAG =~ /^\d+\.\d+\.\d+$/
  script:
    - echo "Releasing components $CI_COMMIT_TAG"
  release:
    tag_name: $CI_COMMIT_TAG
    description: "Release $CI_COMMIT_TAG of components in $CI_PROJECT_PATH"
```

Catalog requirements: the project is marked as a **CI/CD Catalog project** (Settings > General > Visibility), has a description and `README.md`, components live in `templates/`, and releases use **SemVer tags** (`1.2.3`, not `v1.2.3`) created through the `release` keyword or the Releases API.

```bash
# Inspect what the catalog would see, read-only
glab release list -R platform/components
glab api "projects/$(printf %s platform/components | jq -sRr @uri)/releases" | jq '.[0] | {tag_name, released_at}'
```

> **Note.** glab 1.108 has `glab release create --publish-to-catalog` and `glab repo publish catalog TAG`, both marked experimental; `glab repo publish catalog --help` says it needs the `ci_release_cli_catalog_publish_option` feature flag enabled on the instance and must run as the release author. In CI, the `release:` keyword is the documented path and needs no flag.

#### Structure components for override

- **Prefix job names with an input** (`job-prefix`) so a project can include the same component twice (two Python packages, two images).
- **Expose `stage` as an input** with a sensible default; consumers' stage lists differ.
- **Do not set `tags:`** in a component unless the job genuinely needs special hardware. Let consumers route.
- **Provide `rules` that match the standard `workflow:rules`**, and document them. Consumers can override the whole `rules` array by job name.
- **Keep one concern per component.** "python-test" and "python-lint" as two components compose better than "python-everything" with twelve boolean inputs.

### Parent-child pipelines

A parent pipeline triggers child pipelines from YAML in the **same project**. Each child is a full pipeline with its own stages, `needs` graph and status, shown nested under the parent.

```text
parent pipeline
├── prepare
├── trigger:frontend  ──▶  child pipeline (frontend/.gitlab-ci.yml)
│                           lint ─ test ─ build
├── trigger:backend   ──▶  child pipeline (backend/.gitlab-ci.yml)
│                           lint ─ test ─ build ─ image
└── deploy (needs both triggers, with strategy: depend)
```

```yaml
trigger:backend:
  stage: build
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes: { paths: [backend/**/*] }
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  trigger:
    include: backend/.gitlab-ci.yml
    strategy: depend          # parent job mirrors the child's status
  variables:
    SERVICE: backend          # passed to the child as pipeline variables

trigger:frontend:
  stage: build
  trigger:
    include:
      - local: frontend/.gitlab-ci.yml
    strategy: depend
    forward:
      pipeline_variables: true   # also forward variables the parent was started with
```

Why use them:

- **Monorepos**: each component's pipeline is independent and only triggered when its paths change.
- **Readability**: a 2,000-line YAML becomes several 200-line ones with their own graphs.
- **Isolation**: a child's `workflow:rules`, stages and `default:` do not leak into siblings.

Things to know:

- Children run on the **same commit and ref** as the parent. MR pipelines' children see MR variables.
- A child's own `workflow:rules` must allow `$CI_PIPELINE_SOURCE == "parent_pipeline"`, or the child is empty and fails to be created.
- **Without `strategy: depend`**, the trigger job succeeds as soon as the child is **created**. The parent can go green while the child fails. Always set `strategy: depend` unless you really mean fire-and-forget.
- Maximum nesting depth is two levels of children below the parent.

```yaml
# backend/.gitlab-ci.yml
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "parent_pipeline"

stages: [lint, test, build]
# ... jobs ...
```

> **Gotcha.** Child pipelines do **not** appear in the MR's pipeline widget as their own entries; the parent's trigger job carries the status. With `strategy: depend` that is accurate. Without it, reviewers see a green MR over a failed child.

### Dynamic child pipelines

A job **generates** YAML at runtime, saves it as an artefact, and a trigger job runs it as a child. This is the escape hatch from static YAML: loops, file discovery, generated matrices.

```yaml
generate:
  stage: .pre
  image: docker.io/library/python:3.13-slim
  script:
    - python .gitlab/ci/generate.py > child.yml
  artifacts:
    paths: [child.yml]

run-generated:
  stage: build
  needs: [generate]
  trigger:
    include:
      - artifact: child.yml
        job: generate
    strategy: depend
```

A generator that emits one test job per changed service in a monorepo:

```python
# .gitlab/ci/generate.py
import os
import subprocess
import sys

import yaml  # PyYAML; or build the YAML as text if you want zero dependencies

base = os.environ.get("CI_MERGE_REQUEST_DIFF_BASE_SHA") or "HEAD~1"
changed = subprocess.run(
    ["git", "diff", "--name-only", base, "HEAD"],
    check=True, capture_output=True, text=True,
).stdout.splitlines()

services = sorted({p.split("/")[1] for p in changed if p.startswith("services/") and p.count("/") >= 2})

pipeline = {"workflow": {"rules": [{"if": '$CI_PIPELINE_SOURCE == "parent_pipeline"'}]}, "stages": ["test"]}
if not services:
    pipeline["noop"] = {"stage": "test", "image": "docker.io/library/alpine:3.22", "script": ["echo nothing changed"]}
for svc in services:
    pipeline[f"test:{svc}"] = {
        "stage": "test",
        "image": "docker.io/library/python:3.13-slim",
        "script": ["pip install --quiet uv", f"uv run --package {svc} pytest services/{svc}"],
    }
yaml.safe_dump(pipeline, sys.stdout, sort_keys=False)
```

Rules for generators:

- **Always emit at least one job.** An empty child pipeline fails to be created, which fails the trigger job.
- **Make the generator deterministic** and testable locally: write its output to a file and run `glab ci lint` on it.
- **Generated YAML can `include:` components**, so the generator decides *which* jobs, and the components decide *how*.
- **Diff base needs history**: set `GIT_DEPTH: 0` or deep enough on the generator job.

```bash
# Validate generated output locally before pushing
python .gitlab/ci/generate.py > /tmp/child.yml && glab ci lint /tmp/child.yml
```

### Multi-project pipelines

A trigger job in project A starts a pipeline in project B. Use it when a change in one repository must be validated or deployed by another: a library triggering its consumers' tests, an app triggering a deployment repository.

```yaml
# in the app repository
deploy:trigger:
  stage: deploy
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
  trigger:
    project: platform/deployments
    branch: main
    strategy: depend           # wait for and mirror the downstream result
  variables:
    APP: billing
    IMAGE_DIGEST: $IMAGE_DIGEST   # from a dotenv in an earlier job
```

Downstream, the pipeline source is `pipeline`:

```yaml
# platform/deployments/.gitlab-ci.yml
workflow:
  rules:
    - if: $CI_PIPELINE_SOURCE == "pipeline"
    - if: $CI_COMMIT_BRANCH
```

What to know:

- The user who triggered the upstream pipeline must have permission to run pipelines in the downstream project on that branch (Developer, and protected-branch rules apply).
- Variables in the trigger job's `variables:` are passed as **pipeline variables**, which rank high in precedence downstream. If the downstream project restricts pipeline variables ("Minimum role to use pipeline variables"), the trigger fails. Prefer **`trigger:inputs`** where your version supports it: typed, validated, and not subject to the variable restrictions.
- Artefacts from upstream can be fetched downstream with `needs:project` (Premium) or passed as variables.
- `strategy: depend` makes the upstream job wait and reflect the downstream status. Without it, upstream goes green immediately.

> **Version-sensitive.** Pipeline-level `spec:inputs` in `.gitlab-ci.yml` (for Run pipeline, API, schedules and `trigger:inputs`) arrived in GitLab 17.11. On earlier versions, downstream parameters are variables only. `glab ci run --input key:value` (verified in glab 1.108) passes pipeline inputs from the command line.

#### Multi-project vs parent-child

| Need | Pick |
|---|---|
| Split one repository's pipeline | Parent-child |
| Monorepo, per-directory pipelines | Parent-child (static or dynamic) |
| Cross-repository dependency or deployment | Multi-project |
| Shared job definitions | Neither: components |

### A central templates repository

If you are not yet on components, or you need non-component shared files (scripts, config), the shape that scales:

```text
platform/ci/
├── templates/                 # CI/CD components (the catalog project)
├── scripts/                   # shell/Python helpers, versioned with the components
├── images/                    # Dockerfiles for CI tool images (uv, helm, kubectl, lint tools)
├── examples/                  # a minimal consuming .gitlab-ci.yml per stack
└── CHANGELOG.md               # generated; consumers read this before bumping a major
```

Principles:

- **One owner team**, with CODEOWNERS on `templates/`, and MR review from at least one consuming team for breaking changes.
- **Ship CI tool images from the same repository** and reference them by digest from the components, so a component version fully determines the toolchain.
- **Publish a migration note with every major**: which inputs changed, which job names changed, a before/after YAML snippet.
- **Renovate** in consuming repositories bumps component versions like any dependency, one MR per repository, so each team sees the change and its pipeline result.

### Avoiding include sprawl

Sprawl looks like this: a project includes six files, three of which include four more each, two templates define jobs with the same name, and nobody can say where `before_script` comes from.

#### Symptoms and fixes

| Symptom | Fix |
|---|---|
| "Where does this job come from?" | `glab ci config compile` shows the fully merged config; search it |
| Nested includes more than two levels deep | Flatten: consumers include components directly, components do not include other components unless unavoidable |
| Templates reading unexplained variables | Convert to components with `spec:inputs` |
| Same job name defined in two includes | Prefix job names with an input; the later include silently wins otherwise |
| `include: project` without `ref` | Always pin `ref:` to a tag or SHA; unpinned means every template edit is a production change for every consumer |
| Global `default:` or `variables:` in shared templates | Remove: an included file's `default:` changes every job in the consuming project |
| Hitting the 150-include limit | You are including per-job files; merge them into components |

#### See the merged result

```bash
# Fully resolved config, with every include merged, as GitLab sees it
glab ci config compile > /tmp/merged.yml
grep -n '^[a-z].*:$' /tmp/merged.yml | head -50    # top-level job names

# Validate, and simulate a pipeline on a ref (shows which jobs would be created)
glab ci lint --dry-run --ref main --include-jobs
```

> **Gotcha.** A shared template that sets top-level `default:` (say, `default: image: python`) overrides nothing if the consumer also sets `default:`, but silently changes every job in consumers that don't. The same goes for top-level `variables:` and `workflow:`. Components should define **jobs** only, never global keywords.

### Checklist

- [ ] Shared CI lives in one component project with a README, SemVer tags and a self-test pipeline.
- [ ] Components have typed `spec:inputs` with descriptions; mandatory inputs are intentional.
- [ ] Consumers include with `$CI_SERVER_FQDN` and pin `@MAJOR` (internal) or exact versions (third party).
- [ ] Breaking changes, including job renames, bump the major and ship a migration note.
- [ ] No `include: project` without a pinned `ref:`.
- [ ] Components do not set `default:`, top-level `variables:` or `workflow:`.
- [ ] Every trigger job has `strategy: depend` unless fire-and-forget is intended.
- [ ] Child pipeline configs allow `parent_pipeline` in `workflow:rules`.
- [ ] Dynamic generators always emit at least one job and are tested with `glab ci lint`.
- [ ] Remote includes use `integrity:` (17.9+) or are replaced by project includes.


---


<a id="11-environments-and-delivery"></a>

## 11 · Environments and delivery

*A deploy job is the one place where CI touches production, so it carries the controls: who may run it, what credentials it can reach, whether it may run concurrently, and whether anyone must approve it. Put each control in GitLab's primitives (protected environments, resource groups, ID tokens) rather than in script logic, so they are visible and enforced for every pipeline.*

### The deploy model

```text
            build once                           promote the same digest
MR  ──▶ image@sha256:ab12 ──▶ review/feat-x      (review app, auto-stops)
main ─▶ image@sha256:cd34 ──▶ staging            (automatic, resource_group)
tag  ─▶ image@sha256:cd34 ──▶ production         (manual + approval, protected env,
                                                  OIDC credentials, deploy freeze aware)
```

Five GitLab primitives carry the controls:

| Control | Primitive | Tier |
|---|---|---|
| Track what is deployed where | `environment:` | Free |
| One deploy at a time per target | `resource_group:` | Free |
| Who may deploy, and approvals | Protected environments | Premium |
| Credentials that exist only for that job | `id_tokens:` + OIDC / `secrets:` | Free (`secrets:` with Vault: Premium) |
| Stop deploys during a freeze | Deploy freezes + `$CI_DEPLOY_FREEZE` | Free |

### Environments

An `environment:` on a job turns it into a **deployment**: GitLab records which commit went to which environment, when, by whom, and shows it on Operate > Environments and in the MR widget.

```yaml
deploy:staging:
  environment:
    name: staging
    url: https://app.staging.example.internal
    deployment_tier: staging
    kubernetes:
      agent: group/infra/agents:k8s-agent   # links the environment to the cluster dashboard
```

#### Keys

| Key | Values | Notes |
|---|---|---|
| `name` | string, may contain variables | `review/$CI_COMMIT_REF_SLUG` groups dynamic environments into a folder |
| `url` | URL | "View deployment" button in MR and environment page |
| `deployment_tier` | `production`, `staging`, `testing`, `development`, `other` | Inferred from the name if omitted; set it explicitly |
| `action` | `start` (default), `prepare`, `stop`, `verify`, `access` | `prepare`/`verify`/`access` use the environment without creating a deployment |
| `on_stop` | job name | Job run when the environment is stopped |
| `auto_stop_in` | duration (`3 days`, `1 week`) | Stops the environment (runs `on_stop`) after inactivity |
| `kubernetes:agent` | `path:agent-name` | Enables the environment's Kubernetes dashboard |

**Set `deployment_tier` explicitly.** Tier drives DORA metrics (only `production` counts for deployment frequency and lead time), and inference from names like `prod-eu` or `live` is unreliable.

#### Actions that do not deploy

A job that only reads from an environment (smoke tests, a DB migration dry run, fetching credentials) should not appear as a deployment:

```yaml
smoke:staging:
  needs: [deploy:staging]
  environment:
    name: staging
    action: verify           # uses staging's protected variables; no deployment record
  script:
    - ./scripts/smoke.sh "$CI_ENVIRONMENT_URL"
```

Environment-scoped variables (a CI/CD variable with "Environment scope: production") are only injected into jobs whose `environment:name` matches, including `prepare`/`verify`/`access` jobs.

> **Gotcha.** Environment-scoped variables are matched by `environment:name` **pattern**, not tier. A variable scoped to `production` is not visible in a job whose environment is `production-eu`. Use wildcard scopes (`production*`) deliberately, and never scope secrets to `*`.

### resource_group

Two pipelines deploying to the same environment at the same time interleave `helm upgrade` or `terraform apply` and leave it half one version, half the other. `resource_group` makes jobs with the same group name run one at a time across all pipelines in the project.

```yaml
deploy:staging:
  resource_group: staging
deploy:production:
  resource_group: production
deploy:review:
  resource_group: review/$CI_COMMIT_REF_SLUG   # one at a time per review app
```

#### Process mode

Set per resource group through the API (not in YAML):

| Mode | Picks next | Use |
|---|---|---|
| `unordered` (default) | Whichever job is ready | Fine when order does not matter |
| `oldest_first` | Lowest pipeline ID | Every change deployed in order (audit trails, migrations) |
| `newest_first` | Highest pipeline ID | Skip stale deploys; latest wins |
| `newest_ready_first` | Newest job that is ready to run | Same intent as `newest_first`, faster when older jobs are still waiting on needs |

```bash
# Read the current mode (read-only)
glab api "projects/:id/resource_groups/production" | jq '{key, process_mode}'
# Changing it is a write: PUT projects/:id/resource_groups/production with process_mode=newest_first
```

**Default: `newest_first` for staging, `oldest_first` for production** when production runs database migrations in order; `newest_first` for production otherwise. Combine with **Settings > CI/CD > General pipelines > Prevent outdated deployment jobs**, which fails deploy jobs that are older than the environment's latest deployment, so a retried old pipeline cannot roll production backwards by accident.

> **Gotcha.** `resource_group` serialises within **one project**. Two projects deploying to the same cluster namespace do not see each other's locks. Use a single deployment project (multi-project trigger, chapter 10) or a lock in the target system.

### Manual jobs and approvals

#### Manual deploy jobs

```yaml
deploy:production:
  rules:
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
      when: manual
      allow_failure: false        # pipeline status "blocked" until deployed
  manual_confirmation: "Deploy $CI_COMMIT_TAG to production?"   # 17.1+
  environment:
    name: production
    deployment_tier: production
  resource_group: production
```

`allow_failure: false` on a manual job makes the pipeline **blocked** (not passed) until someone runs it. That is correct for a tag pipeline whose whole purpose is the deploy. For an optional manual job on MR pipelines, use `allow_failure: true` or the MR cannot merge (chapter 08).

> **Version-sensitive.** `manual_confirmation` needs GitLab 17.1+. It is a UI prompt, not a control: anyone allowed to run the job can click through.

#### Protected environments

The actual control. Settings > CI/CD > Protected environments (Premium):

| Setting | Production | Staging |
|---|---|---|
| Allowed to deploy | `@release-managers` group or Maintainers | Developers + Maintainers |
| Required approvals | 1 or 2 from `@prod-approvers` | 0 |
| Approvers can self-approve their own pipeline | Off | n/a |

What protection enforces:

- Only "allowed to deploy" users can run, retry or cancel jobs targeting the environment. A Developer who can push a tag still cannot run the production job.
- **Because only deployers can run jobs for the environment, its environment-scoped variables only reach jobs a deployer started.** Production credentials scoped to `production` cannot be read by a job someone else ran.
- With required approvals, the job waits in "waiting for approval" until approved on the environment's page or the pipeline, then runs.

Group-level protected environments (by tier) let you protect `production` for every project in a group at once.

> **Note.** Protected environments protect **jobs that declare the environment**. A job without `environment:` that runs `helm upgrade` against production with credentials from an unscoped variable bypasses all of it. The credential design below (OIDC, environment-scoped, protected) is what closes that hole: without the environment declaration, the job cannot get credentials.

#### Deploy freezes

Settings > CI/CD > Deploy freezes: cron-style windows (for example, Friday 17:00 to Monday 07:00, in a time zone). During a freeze, GitLab sets `$CI_DEPLOY_FREEZE`. Nothing is blocked automatically; your rules decide:

```yaml
deploy:production:
  rules:
    - if: $CI_DEPLOY_FREEZE
      when: never                 # or: when: manual + a louder confirmation for emergencies
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
      when: manual
      allow_failure: false
```

```bash
# List freeze periods (read-only)
glab api "projects/:id/freeze_periods" | jq '.[] | {freeze_start, freeze_end, cron_timezone}'
```

> **Gotcha.** `$CI_DEPLOY_FREEZE` is evaluated when the **pipeline is created**. A tag pipeline created on Friday at 16:59 has a manual deploy job that can still be run at 18:00, inside the freeze. For hard freezes, also check the freeze in the job's script via the API, or rely on protected-environment approvals during freeze windows.

### Review apps

A review app is a per-MR environment, created by the MR pipeline and destroyed when the MR merges or closes.

```yaml
deploy:review:
  stage: deploy
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
  resource_group: review/$CI_COMMIT_REF_SLUG
  interruptible: false
  variables:
    NS: review-$CI_MERGE_REQUEST_IID
  script:
    - |
      helm upgrade --install "app-$CI_MERGE_REQUEST_IID" charts/app \
        --kube-context "$KUBE_CONTEXT" -n "$NS" --create-namespace \
        -f charts/app/values-review.yaml \
        --set image.digest="$IMAGE_DIGEST" \
        --set ingress.host="mr-$CI_MERGE_REQUEST_IID.review.example.internal" \
        --wait --timeout 5m
  environment:
    name: review/$CI_COMMIT_REF_SLUG
    url: https://mr-$CI_MERGE_REQUEST_IID.review.example.internal
    on_stop: stop:review
    auto_stop_in: 3 days
    deployment_tier: development

stop:review:
  stage: deploy
  needs: [deploy:review]
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      when: manual
      allow_failure: true
  variables:
    GIT_STRATEGY: none            # the branch may already be deleted
    NS: review-$CI_MERGE_REQUEST_IID
  script:
    - helm uninstall "app-$CI_MERGE_REQUEST_IID" --kube-context "$KUBE_CONTEXT" -n "$NS" --wait || true
    - kubectl --context "$KUBE_CONTEXT" delete namespace "$NS" --ignore-not-found --wait=false
  environment:
    name: review/$CI_COMMIT_REF_SLUG
    action: stop
```

How the stop job gets triggered:

| Event | Result |
|---|---|
| MR merged or closed, and the branch is deleted | GitLab runs `on_stop` automatically |
| `auto_stop_in` elapses with no new deployment | GitLab runs `on_stop` |
| Someone clicks Stop on the environment | GitLab runs `on_stop` |
| `glab api -X POST projects/:id/environments/ENV_ID/stop` | Same as clicking Stop (write call) |

Requirements that are easy to miss:

- The stop job must have the **same `environment:name`** and `action: stop`, and be in the **same pipeline stage or later** with rules that include it in the pipeline (as manual).
- `GIT_STRATEGY: none`: when the branch has been deleted, a checkout would fail and the environment would never stop.
- The stop job must be able to run without artefacts from jobs that may have expired; do not `needs` artefacts, only the deploy job for ordering.
- Resource limits: put a `ResourceQuota` in each review namespace and cap review apps with `auto_stop_in`, or a busy repository will fill the cluster.

> **Gotcha.** If the stop job's rules exclude it from the pipeline (for example, a `changes:` filter), the environment has no stop action and review apps pile up forever. Keep the stop job's rules identical to the deploy job's, plus `when: manual`.

### Secrets

The order of preference, from best to worst:

| Rank | Mechanism | Secret lives | Rotation |
|---|---|---|---|
| 1 | **OIDC to the target** (`id_tokens`, no stored secret) | Nowhere; short-lived token minted per job | Nothing to rotate |
| 2 | **External secrets manager** via `secrets:` (OpenBao/Vault, GCP, Azure, GitLab Secrets Manager) | In the manager | In the manager, no CI change |
| 3 | **CI/CD variable**: masked + hidden + protected + environment-scoped | In GitLab | Manual update per project/group |
| 4 | Anything in the repository | Git history, forever | Impossible; rotate the secret |

#### CI/CD variables done properly

When a secret must be a CI variable, set all four flags:

| Flag | Effect | Limits |
|---|---|---|
| **Protected** | Only exposed to pipelines on protected branches and tags | Needs `main` and `v*` protected (chapter 07) |
| **Masked** | Replaced with `[MASKED]` in job logs | Value: single line, no spaces, 8+ characters, from the Base64 alphabet plus `@ : . ~ -` and a few others |
| **Masked and hidden** | Masked, and the value can never be viewed in the UI after saving | GitLab 17.4+ (GA 17.6); only when creating the variable |
| **Environment scope** | Only injected into jobs with a matching `environment:name` | Use exact names for production |

Also untick **Expand variable reference** for secrets that may contain `$`, otherwise `pa$word` becomes `pa`.

> **Version-sensitive.** "Masked and hidden" arrived in GitLab 17.4 behind a default-on flag and became generally available in 17.6. You cannot convert an existing variable to hidden; delete and recreate it.

> **Gotcha.** Masking is a **log filter**, not access control. Any job that receives the variable can `echo "$SECRET" | base64` or send it anywhere. The protections that matter are protected + environment scope + protected environments, which decide **which jobs receive it at all**.

#### File variables

A variable of type **File** is written to a temporary file; the variable holds the **path**. Use them for kubeconfigs, service-account JSON, certificates: tools that want a file, and values that are multi-line (and so cannot be masked).

```yaml
deploy:
  script:
    - export KUBECONFIG="$KUBECONFIG_PROD"     # a File variable: this is a path
    - kubectl get ns
    # Read the content only where a tool insists on a string:
    - gcloud auth activate-service-account --key-file "$GCP_SA_KEY"
```

> **Gotcha.** Referencing a File variable in the variables section of another variable (`variables: { KUBECONFIG: $KUBECONFIG_PROD }`) passes the **path**, which is what you want. Wrapping it as `"$(cat $VAR)"` into a regular variable puts the unmasked content in the environment of every subprocess.

#### External secrets: OpenBao / Vault with id_tokens and secrets:

The flow: GitLab mints a JWT for the job (`id_tokens:`), the runner exchanges it with Vault/OpenBao's JWT auth method for a short-lived Vault token, reads the secret, and exposes it to the job.

```text
job starts ──▶ GitLab mints ID token (aud=https://bao.example.internal)
                │   claims: project_path, ref, ref_protected, environment, ...
                ▼
runner ──▶ OpenBao auth/jwt/login (role=app-prod, jwt=ID token)
                │   role bound_claims: project_id=42, ref_protected=true, environment=production
                ▼
           OpenBao token (TTL minutes) ──▶ read kv/data/app/prod ──▶ secret as file/env var
```

Server side, once (OpenBao CLI is `bao`; Vault's is `vault`, same syntax):

```bash
bao auth enable jwt
bao write auth/jwt/config \
  oidc_discovery_url="https://gitlab.example.internal" \
  bound_issuer="https://gitlab.example.internal"

bao policy write app-prod - <<'EOF'
path "kv/data/app/prod" { capabilities = ["read"] }
EOF

bao write auth/jwt/role/app-prod - <<'EOF'
{
  "role_type": "jwt",
  "policies": ["app-prod"],
  "token_explicit_max_ttl": 600,
  "user_claim": "user_login",
  "bound_audiences": ["https://bao.example.internal"],
  "bound_claims_type": "glob",
  "bound_claims": {
    "project_id": "42",
    "ref_protected": "true",
    "ref_type": "tag",
    "environment": "production"
  }
}
EOF
```

CI side, with the `secrets:` keyword (Premium):

```yaml
variables:
  VAULT_SERVER_URL: https://bao.example.internal   # or set as a project/group variable
  VAULT_AUTH_PATH: jwt                              # default: jwt
  VAULT_AUTH_ROLE: app-prod

deploy:production:
  environment: { name: production, deployment_tier: production }
  id_tokens:
    VAULT_ID_TOKEN:
      aud: https://bao.example.internal
  secrets:
    DB_PASSWORD:
      vault: app/prod/db_password@kv        # path/field@engine-mount (kv-v2 by default)
      token: $VAULT_ID_TOKEN
      file: false                           # value in the variable, not a file path
    TLS_KEY:
      vault:
        engine: { name: kv-v2, path: kv }
        path: app/prod
        field: tls_key
      token: $VAULT_ID_TOKEN                # default file: true → $TLS_KEY is a path
  script:
    - ./deploy.sh
```

On Free tier, do the same exchange yourself in the script:

```yaml
deploy:production:
  id_tokens:
    BAO_ID_TOKEN:
      aud: https://bao.example.internal
  image: quay.io/openbao/openbao:BAO_VERSION
  script:
    - export BAO_ADDR=https://bao.example.internal
    - export BAO_TOKEN="$(bao write -field=token auth/jwt/login role=app-prod jwt="$BAO_ID_TOKEN")"
    - export DB_PASSWORD="$(bao kv get -field=db_password kv/app/prod)"
    - ./deploy.sh
```

Bind roles on the **claims that express intent**: `project_id` (not `project_path`, which changes on rename or transfer), `ref_protected: true`, `ref_type`, and `environment` for production roles. The `environment` claim only appears for jobs with `environment:`, which ties the credential to the protected-environment controls above.

> **Version-sensitive.** `id_tokens` needs GitLab 15.7+. The legacy `CI_JOB_JWT`, `CI_JOB_JWT_V1` and `CI_JOB_JWT_V2` variables were removed in GitLab 17.0; any Vault integration still using them is broken on current versions. `secrets:gcp_secret_manager` needs 16.8+, `secrets:azure_key_vault` 16.3+, and `secrets:akeyless` is newer still.

> **Version-sensitive.** **GitLab Secrets Manager** is a native secrets store built on OpenBao, used as `secrets: NAME: gitlab_secrets_manager: { name: ... }` (keyword added in GitLab 19.0, needs Runner 19.0+). It was a flagged/closed beta in 18.3 to 18.10, a public beta in 19.0, and reached **limited availability on GitLab.com in 19.3** for Premium and Ultimate, billed in GitLab Credits after a 30-day trial. On self-managed it is still **beta** as of 19.4 ([docs](https://docs.gitlab.com/ci/secrets/secrets_manager/)). If you already run OpenBao, the `vault:` integration above is the production-ready path today.

> **Gotcha.** Secrets fetched with `secrets:` default to **file** variables: `$DB_PASSWORD` holds a path like `/builds/.../DB_PASSWORD.tmp`. Scripts that expect the value get a filename and fail authentication in confusing ways. Set `file: false` for values, or read the file.

### OIDC to cloud providers

Same ID-token mechanism, no secrets manager in between: the cloud provider trusts GitLab's issuer and exchanges the job's token for short-lived cloud credentials.

#### GCP (Workload Identity Federation)

One-time setup: a workload identity pool with a provider for issuer `https://gitlab.example.internal`, an attribute mapping such as `google.subject=assertion.sub,attribute.project_id=assertion.project_id,attribute.ref_protected=assertion.ref_protected`, an attribute condition like `assertion.project_id == "42" && assertion.ref_protected == "true"`, and `roles/iam.workloadIdentityUser` on a service account for that principal set.

```yaml
deploy:gke:
  image: gcr.io/google.com/cloudsdktool/google-cloud-cli:GCLOUD_VERSION-slim
  id_tokens:
    GCP_ID_TOKEN:
      aud: https://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID
  script:
    - echo "$GCP_ID_TOKEN" > "$CI_BUILDS_DIR/.gcp_token"
    - |
      gcloud iam workload-identity-pools create-cred-config \
        "projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID" \
        --service-account="deployer@PROJECT_ID.iam.gserviceaccount.com" \
        --credential-source-file="$CI_BUILDS_DIR/.gcp_token" \
        --output-file="$CI_BUILDS_DIR/.gcp_creds.json"
    - gcloud auth login --cred-file="$CI_BUILDS_DIR/.gcp_creds.json"
    - gcloud container clusters get-credentials CLUSTER --region REGION --project PROJECT_ID
```

#### AWS

An IAM OIDC identity provider for the GitLab host, and a role whose trust policy conditions on `aud` and `sub`:

```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/gitlab.example.internal" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": { "gitlab.example.internal:aud": "https://gitlab.example.internal" },
    "StringLike":   { "gitlab.example.internal:sub": "project_path:group/app:ref_type:tag:ref:v*" }
  }
}
```

```yaml
deploy:aws:
  id_tokens:
    AWS_ID_TOKEN:
      aud: https://gitlab.example.internal
  variables:
    AWS_ROLE_ARN: arn:aws:iam::ACCOUNT_ID:role/gitlab-deployer
    AWS_WEB_IDENTITY_TOKEN_FILE: $CI_BUILDS_DIR/.aws_token
  script:
    - echo "$AWS_ID_TOKEN" > "$AWS_WEB_IDENTITY_TOKEN_FILE"
    - aws sts get-caller-identity     # SDKs pick up the role + token file automatically
```

> **Note.** On self-managed GitLab, AWS can only condition on the `sub` claim (plus `aud`), so encode what matters in `sub`: GitLab lets you customise the `sub` claim per project through the API to include, for example, `environment`. On GitLab.com more claims are usable as condition keys.

> **Gotcha.** The cloud provider must reach your GitLab's OIDC discovery document (`https://GITLAB_HOST/.well-known/openid-configuration`) and JWKS. For a GitLab behind a VPN, AWS and GCP cannot fetch them; you need either a public reverse proxy for exactly those two paths, or (GCP) upload the JWKS to the provider manually and update it when GitLab rotates keys.

### CI_JOB_TOKEN

Every job gets `CI_JOB_TOKEN`, valid only while the job runs, with the permissions of the user who started the job, **restricted to the projects that allow it**.

What it is good for:

| Use | Example |
|---|---|
| Container registry of this or allowed projects | `docker login -u gitlab-ci-token -p "$CI_JOB_TOKEN" "$CI_REGISTRY"` (prefer `CI_REGISTRY_USER`/`CI_REGISTRY_PASSWORD`) |
| Package registry (PyPI, npm, generic, Helm) | `uv publish --publish-url "$CI_API_V4_URL/projects/$CI_PROJECT_ID/packages/pypi" -u gitlab-ci-token -p "$CI_JOB_TOKEN"` |
| Clone another allowed project | `git clone "https://gitlab-ci-token:${CI_JOB_TOKEN}@${CI_SERVER_HOST}/group/lib.git"` |
| Selected API endpoints | Releases, deployments, environments, pipelines trigger, packages |

#### The allowlist

Settings > CI/CD > Job token permissions: **"Limit access to this project"** / the **CI/CD job token allowlist**. When on, only jobs from projects or groups on **this** project's allowlist can use their job token against this project. It is the target project that decides who may come in.

```bash
# Read the allowlist of a project (read-only)
glab api "projects/:id/job_token_scope" | jq
glab api "projects/:id/job_token_scope/allowlist" | jq '.[].path_with_namespace'
glab api "projects/:id/job_token_scope/groups_allowlist" | jq '.[].full_path'
```

- New projects have the allowlist enabled, containing only themselves.
- The old **outbound** scope ("limit what this project's token can reach") is gone; only the inbound allowlist remains.
- Add **groups** rather than long lists of projects where a whole group of consumers needs access (package registries, shared images).

> **Version-sensitive.** The feature was renamed to "CI/CD job token allowlist" in GitLab 17.3. Since 17.6, self-managed admins can turn on **Enable and enforce job token allowlist for all projects**, which removes the per-project opt-out. **Fine-grained job token permissions**, which limit which REST endpoints a token can call, arrived as an experiment in 17.10, went beta in 18.0 and GA in 18.3; endpoints are still being added (19.1 added Badges, 19.4 commit refs). From 19.0, job tokens are JWTs by default ([docs](https://docs.gitlab.com/ci/jobs/ci_job_token/)).

> **Gotcha.** "404 Project Not Found" when a job pulls an image, package or repository from another project almost always means **the target project's allowlist does not include the source project**. The error is a 404 by design, not a 403.

### Releases from tags

A tag pipeline builds artefacts and creates a GitLab Release with notes and links.

```yaml
release:
  stage: release
  image: registry.gitlab.com/gitlab-org/cli:GLAB_VERSION
  rules:
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
  needs:
    - job: build:image
    - job: helm:package
  script:
    - echo "Creating release $CI_COMMIT_TAG for $CI_REGISTRY_IMAGE@$IMAGE_DIGEST"
  release:
    tag_name: $CI_COMMIT_TAG
    name: $CI_COMMIT_TAG
    description: $CI_COMMIT_TAG_MESSAGE          # annotated tag message, e.g. from git-cliff
    assets:
      links:
        - name: Container image
          url: https://$CI_REGISTRY_IMAGE@$IMAGE_DIGEST
          link_type: image
        - name: Helm chart ($CHART_VERSION)
          url: $CI_PROJECT_URL/container_registry
          link_type: package
```

- The `release:` keyword runs a CLI inside the job image. Since GitLab 18.4 the docs require **`glab` 1.58.0+** on `$PATH` (image `registry.gitlab.com/gitlab-org/cli`); older instances used `release-cli` (image `registry.gitlab.com/gitlab-org/release-cli`). The runner falls back to `release-cli` with a warning that it will not be supported after GitLab 20.0 ([migration doc](https://docs.gitlab.com/user/project/releases/release_cli/)). Pin the image.
- `description` can be a file path (`description: ./RELEASE_NOTES.md`) produced by an earlier job's artefact.
- Tag pipelines need protected tags (`v*`) to see protected variables (chapter 07).

From the command line, when you release by hand:

```bash
glab release create v2.4.1 --notes-file RELEASE_NOTES.md --ref release/2.4 \
  --assets-links '[{"name":"Image","url":"https://registry.example.internal/group/app@sha256:DIGEST","link_type":"image"}]'
glab release view v2.4.1
glab release list
```

### Traps

- **Deploy job without `environment:`.** No deployment record, no protected-environment control, no environment-scoped credentials. Every deploy declares its environment.
- **Secrets scoped to `*` or unprotected.** Any branch pipeline can read production credentials.
- **Protecting `main` but not `v*`.** Tag pipelines lose protected variables; production deploys fail oddly.
- **Masking treated as security.** It is a log filter; restrict who receives the value.
- **`CI_JOB_JWT` still in use.** Removed in 17.0; switch to `id_tokens`.
- **Vault roles bound on `project_path`.** A project rename or transfer changes it; bind on `project_id`.
- **`secrets:` values used as values when they are file paths.** Set `file: false` or read the file.
- **Review stop job with different rules or a git checkout.** Environments never stop; namespaces pile up.
- **No `resource_group` on deploys.** Concurrent `helm upgrade`s on the same release.
- **Relying on `$CI_DEPLOY_FREEZE` alone for hard freezes.** It is evaluated at pipeline creation.
- **Rebuilding the image per environment.** Promote one digest.


---


<a id="12-debugging-pipelines"></a>

## 12 · Debugging pipelines

*Most "CI is broken" reports are one of three things: a rule that did not match the way you read it, a runner that cannot pick the job up, or state (cache, artefact, variable) that was not where the job expected it. Ask which of the three it is before reading a single log line.*

### Triage in one minute

```text
Did a pipeline get created at all?
├── no  → workflow:rules filtered it, YAML is invalid, or the include failed
│         → glab ci lint --dry-run --ref BRANCH ; check the pipeline list for "yaml invalid"
└── yes → Is the job in the pipeline?
          ├── no  → job rules did not match (see "Why didn't my job run")
          │         → glab ci lint --dry-run --ref BRANCH --include-jobs
          └── yes → What state is it in?
                    ├── pending / stuck     → no runner with matching tags, or runner capacity
                    ├── created / waiting   → needs not satisfied, resource_group lock, approval
                    ├── manual / blocked    → waiting for someone to click (allow_failure: false)
                    ├── skipped             → an earlier stage failed, or needs failed
                    └── failed              → read the log from the bottom; check the error table below
```

```bash
# Current branch: pipeline status and every job's state
glab ci status
glab ci get -d                     # extended job details
glab ci view                       # interactive: run, retry, cancel, jump to logs

# Follow a job's log live, by name or ID
glab ci trace pytest
glab ci trace -p PIPELINE_ID build:image

# Retry one job, or trigger a manual one
glab ci retry pytest
glab ci trigger deploy:review

# Pipelines that failed to be created because the YAML was invalid
glab ci list --yaml-errors
```

### Why didn't my job run

The rules engine is literal. These are the traps, in order of how often they bite.

#### 1. workflow:rules filtered the whole pipeline

If `workflow:rules` has no matching rule, **no pipeline is created and nothing is shown** in the pipeline list for a push. Running a pipeline manually gives the only visible message: "Pipeline filtered out by workflow rules".

```bash
# Simulate pipeline creation on a ref; the output says whether a pipeline would be created
glab ci lint --dry-run --ref BRANCH --include-jobs
```

Common cause: the standard snippet (chapter 08) has no rule for `schedule`, `web` or `api`, so schedules silently do nothing.

#### 2. $CI_PIPELINE_SOURCE is not what you think

| You did | `$CI_PIPELINE_SOURCE` |
|---|---|
| Pushed a branch | `push` |
| Pushed a **tag** | `push` (not `tag`; test `$CI_COMMIT_TAG`) |
| Opened or updated an MR | `merge_request_event` |
| Clicked Run pipeline | `web` |
| `glab ci run` / API | `api` |
| Pipeline schedule | `schedule` |
| Trigger token (`glab ci run-trig`) | `trigger` |
| Parent's `trigger: include:` | `parent_pipeline` |
| Upstream project's `trigger: project:` | `pipeline` |

`glab ci run --mr` creates an MR pipeline (`merge_request_event`); without `--mr` it is `api`. Jobs that only allow `merge_request_event` do not appear in a pipeline you started from the CLI without `--mr`.

#### 3. First match wins, so when: never must come first

```yaml
# WRONG: the first rule matches on main, so the job runs even on schedules
job:
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_PIPELINE_SOURCE == "schedule"
      when: never

# RIGHT: exclusions first, inclusions after
job:
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
      when: never
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

And the mirror image: **no matching rule means the job is excluded**. A job with rules for MRs and `main` does not exist in tag pipelines, which breaks any tag-pipeline job that `needs` it.

#### 4. changes is true when there is nothing to compare

| Pipeline | `rules:changes` evaluates |
|---|---|
| MR pipeline | Against the MR diff |
| Push to an existing branch | Against the commits in that push |
| **First push of a new branch** | **Always true** |
| **Tag, schedule, web, API, trigger** | **Always true** |
| Any, with `compare_to:` | Against that ref |

So a job guarded only by `changes: [docs/**]` runs on **every** tag and scheduled pipeline, and on every new branch. The opposite surprise: on a branch pipeline, `changes` sees only the last push, so a second push that does not touch `charts/` skips the chart lint even though the branch changed the chart.

Fixes: combine `changes` with an `if` on pipeline source, and use `compare_to: refs/heads/main` for branch pipelines.

```yaml
helm:lint:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes: { paths: [charts/**/*] }
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_COMMIT_TAG
```

#### 5. Variables that are empty in this pipeline

| Variable | Empty in |
|---|---|
| `CI_COMMIT_BRANCH` | MR pipelines, tag pipelines |
| `CI_COMMIT_TAG` | Everything except tag pipelines |
| `CI_MERGE_REQUEST_*` | Everything except MR pipelines (including branch pipelines of a branch with an MR) |
| Protected variables | Pipelines on **unprotected** branches and tags |
| Environment-scoped variables | Jobs whose `environment:name` does not match the scope |
| Variables set in `script` or `dotenv` | Always, at rule-evaluation time: rules run at pipeline creation |

An unset variable in `if: $VAR == "x"` is simply false; no error is raised. That is why a typo in a variable name makes a job silently disappear.

#### 6. Strings, not booleans

All variables are strings. `if: $DEPLOY == true` compares to the string `true`. `if: $DEPLOY` is true for any non-empty value, **including `"false"`**. Write `if: $DEPLOY == "true"`.

#### 7. Regex quoting

A regex literal is written unquoted, between slashes: `if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/`. RE2 syntax, so no look-ahead or back-references. To keep a regex in a variable, put the slashes inside the value (`RELEASE_RE: '/^release\/\d+$/'`) and compare with `=~ $RELEASE_RE`.

#### 8. needs pointing at a job that is not there

```text
'deploy' job needs 'helm:lint' job, but 'helm:lint' is not in any previous stage
```

This is a **pipeline creation** error: the whole pipeline fails, not just the job. The needed job was excluded by its own rules in this pipeline. Add `optional: true` to the `needs` entry, or align the rules.

#### 9. The job is hidden or not a job

A job name starting with `.` is a template and never runs. Top-level keys that happen to be reserved words (`image`, `services`, `cache`, `variables`, `stages`, `include`, `workflow`, `default`, `before_script`, `after_script`, `spec`) are not jobs. A key with no `script`, `trigger` or `run` is an error ("jobs config should contain at least one visible job", or "job X config should implement a script: or a trigger: keyword").

### Validate before you push

#### glab ci lint

```bash
glab ci lint                          # static check of .gitlab-ci.yml via the instance's CI Lint API
glab ci lint path/to/file.yml         # another file (a generated child config, a component test)
glab ci lint --include-jobs           # also list the jobs the static check sees
glab ci lint --dry-run --ref main     # simulate pipeline creation on main: rules evaluated for that ref
glab ci lint --dry-run --ref v2.4.1 --include-jobs   # which jobs would a tag pipeline contain?
```

Static linting validates syntax and includes. **Only `--dry-run` evaluates rules**, and it does so for a branch or tag pipeline on the given ref; it cannot simulate an MR pipeline or a schedule. For those, reason from the tables above or test on a throwaway branch.

> **Note.** Both commands use the GitLab API of the project's instance, with your token. They send the YAML to the server but create nothing. They need a project context (run inside a clone, or pass `-R GROUP/PROJECT`), because includes are resolved relative to the project.

#### glab ci config compile

```bash
glab ci config compile                  # fully merged config: every include, extends and !reference resolved
glab ci config compile > /tmp/merged.yml
yq '.pytest' /tmp/merged.yml            # what does the pytest job look like after all merges?
yq '.pytest.rules' /tmp/merged.yml
```

This answers "where did this `before_script` come from" and "which rules does this job really have" without reading five included files.

#### Pipeline editor

Build > Pipeline editor in the UI: live validation, the **Visualize** tab (the stages/needs graph), the **Full configuration** tab (the same merged view as `config compile`) and **Validate** with a simulated pipeline for a chosen branch. Useful when you are editing on a branch that has not been pushed yet (the editor commits for you) or reviewing someone else's change.

#### Run jobs locally with gitlab-ci-local

`gitlab-ci-local` (a community tool, not GitLab's) parses `.gitlab-ci.yml` and runs jobs in local Docker containers or in a shell. It is the fastest loop for script bugs.

```bash
npm install -g gitlab-ci-local        # also packaged for Homebrew, AUR and a Debian PPA

gitlab-ci-local --list                # jobs that would run (excludes when: never)
gitlab-ci-local --list-all            # including when: never
gitlab-ci-local --preview             # print the merged config
gitlab-ci-local pytest                # run one job
gitlab-ci-local --needs build:image   # run a job and everything it needs
gitlab-ci-local --variable CI_PIPELINE_SOURCE=merge_request_event --list   # simulate rule inputs
```

Local variables live in `.gitlab-ci-local-variables.yml` (per project) or `~/.gitlab-ci-local/variables.yml` (per user, by project/group). Add both to your global gitignore; they are where people put tokens.

What it does not reproduce: your runner's executor configuration, distributed cache, protected-variable logic, real `CI_JOB_TOKEN` permissions, `id_tokens`, `secrets:` and GitLab-side features (environments, resource groups, approvals); its source has no handling for `id_tokens`, `secrets` or `resource_group`. It also warns and skips multi-project `trigger:project` jobs, ignores `needs:project` and `needs:pipeline`, and treats `$[[ ]]` input interpolation functions as no-ops. Use it for script and rule debugging, not for deploy jobs.

> **Note.** On Fedora with Podman instead of Docker, point it at the Podman socket (`systemctl --user enable --now podman.socket`, then `DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock`). Services and some networking features behave differently under rootless Podman; if a job with `services:` misbehaves locally, check it on a real runner before debugging further.

### CI_DEBUG_TRACE

Setting `CI_DEBUG_TRACE: "true"` makes the runner print every shell command with `set -x` and **dump all variables** at the start of the job.

```yaml
pytest:
  variables:
    CI_DEBUG_TRACE: "true"       # remove before merging
```

Or for a single run without a commit:

```bash
glab ci run -b BRANCH --variables CI_DEBUG_TRACE:true
```

> **One-way door.** Debug trace prints **every variable's value, including masked and protected ones**, into the job log. Masking does not apply to the variable dump. Anyone who can read the job log (Developers, and on public projects possibly everyone) can read your deploy credentials, and job logs persist until the job is erased. Never enable it on a job that receives production secrets. If it happened: erase the job log (job page > Erase, or the API), then **rotate every secret the job could see**. Erasing alone is not enough; you do not know who read it.

Safer alternatives, in order:

1. `set -x` in the specific script block you are debugging, which traces commands without the variable dump.
2. `CI_DEBUG_SERVICES: "true"` to see service container logs (a Postgres that will not start), without the trace.
3. `env | cut -d= -f1 | sort` to see **which** variables exist, without values.
4. `FF_SCRIPT_SECTIONS: "true"` for per-line timing.

> **Note.** GitLab restricts who can view debug-trace logs (at least Developer role, and project settings can restrict further). That limits exposure; it does not make the practice safe.

### Common errors

| Symptom (log or UI) | Cause | Fix |
|---|---|---|
| **yaml invalid** / "did not find expected key" / "mapping values are not allowed here" | YAML syntax: bad indentation, an unquoted `:` in a script line, tabs | `glab ci lint`; quote script lines containing `: ` (`- 'echo "a: b"'`) or use a `|` block |
| "jobs config should contain at least one visible job" | Every job is hidden (`.` prefix) or excluded, or only `.pre`/`.post` jobs remain | Add a visible job in a real stage |
| "'X' job needs 'Y' job, but 'Y' is not in any previous stage" | `needs` target excluded by its rules | `needs: [{job: Y, optional: true}]` or align rules |
| "Pipeline filtered out by workflow rules" | No `workflow:rules` rule matched | Add a rule for that pipeline source |
| **Job stuck in pending**: "no active runners online ... with any of these tags" | No runner has **all** the job's tags, runner paused, or runner locked to other projects | Compare job `tags` with `glab runner list` output; remove over-specific tags |
| Pending for minutes, runners online | Runner concurrency full, or Kubernetes cannot schedule the pod | Check runner `concurrent`/`limit`, cluster capacity, pod events |
| "prepare environment: waiting for pod running: timed out" | Pod unschedulable: resource requests too big, image pull failing, node selector | `kubectl describe pod` in the runner namespace; lower `KUBERNETES_*_REQUEST` |
| "exit code 137" / "OOMKilled" | Out of memory | Raise `KUBERNETES_MEMORY_LIMIT`; reduce test workers |
| **"no space left on device"** | Docker images and volumes filling the runner host, or pod ephemeral storage limit | Prune on the runner host (`docker system prune` via a cron or the runner's cleanup), raise ephemeral storage, smaller images |
| **Cache miss every time** ("No URL provided, cache will not be downloaded from shared cache server") | No distributed cache on autoscaled/Kubernetes runners | Configure `[runners.cache]` S3/GCS on the runner |
| Cache miss on MR, hit on main | Protected vs non-protected cache keys (`-protected` / `-non_protected`) | Expected; `cache:unprotect: true` to share, knowing the risk |
| Cache "created" but next job finds nothing | Paths outside `$CI_PROJECT_DIR`, or keys differ (variable not expanded as expected) | Move caches into the project dir; print the key in the log |
| **Artifact expired**: "This job depends on other jobs with expired/erased artifacts" | Retrying an old job whose `needs` artefacts passed `expire_in` | Re-run the whole pipeline, or lengthen `expire_in` for artefacts that retries need |
| "404 Not Found" pulling image, package or repo from another project | Target project's CI/CD job token allowlist does not include this project | Add this project (or group) to the target's allowlist |
| "HTTP Basic: Access denied" on git push from CI | `CI_JOB_TOKEN` cannot push by default | Use a project access token or deploy key with write access |
| "x509: certificate signed by unknown authority" | Self-hosted CA not trusted by the runner or job image | Runner `tls-ca-file`; `CI_SERVER_TLS_CA_FILE`; add the CA to the job image |
| "Cannot connect to the Docker daemon at tcp://docker:2375" | DinD service TLS mismatch or not privileged | Set `DOCKER_HOST=tcp://docker:2376` + `DOCKER_TLS_CERTDIR=/certs`, or move to rootless BuildKit (chapter 09) |
| "Job's log exceeded limit" | Log over the runner `output_limit` (default 4 MB) | Quieter output; raise `output_limit` in runner config |
| "413 Request Entity Too Large" uploading artefacts | Over the instance max artefact size | Smaller artefacts, `exclude:`, or raise the limit (admin) |
| Protected variable is empty | Branch or tag not protected | Protect the ref pattern (chapter 07) |
| `secrets:` value looks like a file path | `secrets:` defaults to file variables | `file: false` |
| Manual job makes pipeline "blocked" | `when: manual` in rules defaults to `allow_failure: false` | Add `allow_failure: true` for optional manual jobs |
| Job cancelled for no visible reason | Auto-cancel: a newer pipeline on the same ref made it redundant | Expected for `interruptible: true`; mark deploys `interruptible: false` |

#### Reading a failed log efficiently

```bash
# Last 80 lines of a job log, without the TUI
glab ci trace JOB_ID 2>&1 | tail -80

# Find the first error line in a long log
glab api "projects/:id/jobs/JOB_ID/trace" | grep -n -m1 -iE 'error|fatal|exception|failed'

# Download a job's artefacts from the last pipeline on a ref
glab ci artifact main pytest
```

The actual error is usually **above** the last lines, which are the runner's cleanup and "ERROR: Job failed: exit code 1". Search upwards for the first failing command.

### A one-screen keyword reference

#### Global keywords

| Keyword | Does |
|---|---|
| `default` | Defaults for all jobs: `image`, `services`, `before_script`, `after_script`, `cache`, `artifacts`, `retry`, `timeout`, `interruptible`, `tags`, `hooks`, `id_tokens` |
| `include` | Pull in YAML: `local`, `project` (+`ref`, `file`), `remote` (+`integrity` 17.9+), `template`, `component` (+`inputs`); `rules` for conditional includes |
| `spec` | Header before `---`: `spec:inputs` for components and pipelines |
| `stages` | Ordered stage names; `.pre` and `.post` implicit |
| `variables` | Pipeline-wide variables (lowest YAML precedence) |
| `workflow` | `rules` (create a pipeline?), `name` (15.5+), `auto_cancel` (16.8+/16.10+) |

#### Job keywords

| Keyword | Does |
|---|---|
| `script` / `before_script` / `after_script` | Commands; `after_script` runs even on failure, in a separate shell |
| `run` | Newer step-based alternative to `script` (experimental; check your version) |
| `image` / `services` | Job container and sidecar containers (`name`, `alias`, `entrypoint`, `pull_policy`) |
| `stage` | Which stage; default `test` |
| `needs` | DAG dependencies: `job`, `artifacts`, `optional`, `pipeline`, `project`, `parallel:matrix` |
| `dependencies` | Which jobs' artefacts to download (stage-ordered jobs only) |
| `rules` | `if`, `changes` (`paths`, `compare_to`), `exists`, then `when`, `allow_failure`, `variables`, `needs`, `interruptible` |
| `when` | `on_success`, `on_failure`, `always`, `manual`, `delayed` (+`start_in`), `never` |
| `allow_failure` | `true`/`false` or `exit_codes: [..]` |
| `manual_confirmation` | Prompt text for manual jobs (17.1+) |
| `variables` | Job variables; `{value, description, options, expand}` |
| `cache` | `key` (`files`, `files_commits`, `prefix`), `fallback_keys` (16.0+), `paths`, `policy`, `when`, `unprotect`, `untracked` |
| `artifacts` | `paths`, `exclude`, `expire_in`, `when`, `name`, `reports` (`junit`, `coverage_report`, `codequality`, `dotenv`, `sast`, ...), `access`, `expose_as` |
| `coverage` | Regex to extract a coverage percentage from the log |
| `parallel` | `N` (2 to 200) or `matrix` |
| `interruptible` | Can auto-cancel stop this job? |
| `resource_group` | Serialise jobs with the same key |
| `environment` | `name`, `url`, `deployment_tier`, `action`, `on_stop`, `auto_stop_in`, `kubernetes` |
| `release` | Create a GitLab Release: `tag_name`, `name`, `description`, `ref`, `assets:links`, `milestones` |
| `trigger` | Downstream pipeline: `include` (child), `project`+`branch` (multi-project), `strategy: depend`, `forward`, `inputs` |
| `id_tokens` | OIDC JWTs for the job, each with `aud` (15.7+) |
| `secrets` | External secrets: `vault`, `gcp_secret_manager`, `azure_key_vault`, `akeyless`, `gitlab_secrets_manager`; `token`, `file` |
| `tags` | Runner selection; job runs on a runner having all tags |
| `timeout` | Per-job timeout (cannot exceed the runner's) |
| `retry` | `max` (0 to 2), `when` (failure reasons), `exit_codes` |
| `extends` | Inherit from hidden jobs / templates (deep merge, arrays replaced) |
| `hooks` | `pre_get_sources_script`: commands before the git clone |
| `inherit` | `default: false` / `variables: false` (or lists) to opt out of globals |
| `pages` | GitLab Pages deploy job settings (`publish`, `expire_in`) |
| `only` / `except` | **Legacy**; use `rules` |

#### Most-used variables

| Variable | Meaning |
|---|---|
| `CI_PIPELINE_SOURCE` | What created the pipeline |
| `CI_COMMIT_BRANCH` / `CI_COMMIT_TAG` / `CI_COMMIT_REF_SLUG` | Branch (not in MR/tag), tag, DNS-safe ref |
| `CI_DEFAULT_BRANCH` | The default branch |
| `CI_MERGE_REQUEST_IID` / `_EVENT_TYPE` / `_TARGET_BRANCH_NAME` / `_DIFF_BASE_SHA` | MR pipelines only |
| `CI_OPEN_MERGE_REQUESTS` | Branch has open MRs (duplicate suppression) |
| `CI_REGISTRY_IMAGE` / `CI_REGISTRY_USER` / `CI_REGISTRY_PASSWORD` | Registry path and job credentials |
| `CI_JOB_TOKEN` | Job-scoped token (allowlist-limited) |
| `CI_ENVIRONMENT_NAME` / `_URL` / `_TIER` | From `environment:` |
| `CI_DEPLOY_FREEZE` | Set during a deploy freeze |
| `CI_NODE_INDEX` / `CI_NODE_TOTAL` | `parallel` shard number and count |
| `CI_SERVER_FQDN` | Instance host for component includes |
| `GIT_DEPTH` / `GIT_STRATEGY` / `GIT_SUBMODULE_STRATEGY` | Clone behaviour |
| `CI_DEBUG_TRACE` / `CI_DEBUG_SERVICES` | Debug output (trace leaks secrets) |

### Checklist

- [ ] Before asking "why", run `glab ci lint --dry-run --ref BRANCH --include-jobs`.
- [ ] Before reading included files, run `glab ci config compile`.
- [ ] Exclusion rules (`when: never`) come first in every `rules` list.
- [ ] `changes` is always paired with an `if` on the pipeline source.
- [ ] Optional manual jobs have `allow_failure: true`.
- [ ] `needs` on conditionally-included jobs use `optional: true`.
- [ ] `workflow:rules` explicitly lists every pipeline source you use, including schedules.
- [ ] `CI_DEBUG_TRACE` never enabled on jobs that receive secrets; if it was, erase the log and rotate.
- [ ] `gitlab-ci-local` variable files are gitignored.
- [ ] Stuck jobs: compare tags before blaming the runner.


---
