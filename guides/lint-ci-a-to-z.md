# Lint & CI, A→Z

> One route that follows a change: the formatter and linter in your editor, the pre-commit hook that catches the rest, a short-lived branch, the merge request, a GitLab pipeline that is fast and fails for the right reasons, the merge, the deploy, and how to debug the job that never ran.
> Full version: [Lint, CI & Branching Field Manual](./lint-ci-branching-field-manual.md)

## Contents

- 01 · [The feedback loop](#ch01)
- 02 · [Configure the linters](#ch02)
- 03 · [Hooks and secrets](#ch03)
- 04 · [Branch off the trunk](#ch04)
- 05 · [The merge request](#ch05)
- 06 · [Anatomy of a pipeline](#ch06)
- 07 · [Lint jobs that fail correctly](#ch07)
- 08 · [Fast and shared pipelines](#ch08)
- 09 · [Release and deploy](#ch09)
- 10 · [When the pipeline breaks](#ch10)
- Z · [One-screen reference](#appendix)

---


<a id="ch01"></a>

## 01 · The feedback loop

*Your editor, your pre-commit hook and CI run the same pinned tools at three speeds, and only CI is the contract. Every enabled rule is an error, because a linter with 40 warnings is a linter nobody reads.*

A change meets its first check as you type and its last on a runner, minutes later. Here's the map of everything in between.

### Five tools, five jobs

"The linter" means five different things, and each belongs somewhere different.

- **Formatter** (`ruff format`, Prettier, `gofmt`): rewrites layout. It fixes in the hook and runs as `--check` in CI. Never put formatting in code review.
- **Linter** (ruff, ESLint, shellcheck): reports known-bad patterns by rule code, so it needs a policy.
- **Type checker** (mypy, `tsc --noEmit`): whole-program. A change in `models.py` breaks a caller you never touched, so it always runs on the whole project.
- **Deep static analysis** (Semgrep, GitLab SAST): slow and noisy. CI only.
- **Secret scanning** (gitleaks): the one class with an irreversible failure. A pushed secret must be rotated.

### Two loops, one contract

The fast loop advises in seconds on your machine; the gate on a runner decides what reaches `main`.

```mermaid
%% caption: Everything the hook checks, CI checks again, because --no-verify skips the whole fast loop.
flowchart LR
  A["edit"] --> B["editor and LSP"]
  B --> C["git commit"]
  C --> D["pre-commit hook: staged files"]
  D -->|"fail"| A
  D -->|"pass"| E["git push"]
  C -.->|"--no-verify"| E
  E --> F["MR pipeline: all files"]
  F -->|"fail"| A
  F -->|"pass"| G["merge to main"]
  G --> H["default-branch pipeline: baseline reports"]
```

The rules that fall out of it:

1. **The hook is a convenience, the pipeline is the contract.** A check that exists only in the hook is a suggestion.
2. **The hook must be fast enough never to be worth bypassing.** Budget about 3 seconds; people who learn `--no-verify` skip the secret scan along with the formatter.
3. **CI must never be stricter by surprise.** The cure is identical versions and config.
4. **The default-branch pipeline is not redundant.** It produces the baseline report the MR widgets diff against.

### Where each check runs

| Class | Editor | Pre-commit hook | CI on MR | CI on default branch | Scheduled |
|---|---|---|---|---|---|
| Formatter | on save | fix | `--check` | `--check` | — |
| Fast linter (ruff, shellcheck, hadolint) | live | yes | yes | yes | — |
| Slow linter (typed ESLint, full golangci-lint) | live | changed files or skip | yes | yes | — |
| Type checker | live | `pre-push` at most | yes | yes | — |
| Deep static analysis | — | — | yes | yes | full scan |
| Secret scan | — | staged diff | MR commits | yes | full history |
| Dependency / image CVEs | — | — | yes | yes | yes, nightly |

The last row is the one people forget: **a CVE scan's result changes when the world changes, not when your code does.** Schedule it.

### Pin once, run everywhere

A linter bump changes the rule set: ruff 0.16 grew its defaults from 59 rules to 413. If the hook runs one version and CI runs "latest", a green commit turns red for no reason. Pin every linter to an exact version **in one place per tool** (the lockfile, a SHA-frozen pre-commit `rev:`, or an image digest), and let Renovate raise bumps as MRs so each shows exactly which findings it adds.

> **Gotcha.** The classic drift: `.pre-commit-config.yaml` pins ruff at one version, `pyproject.toml` at another, and CI runs `uv run ruff`. Two pins for one tool always drift. The hooks chapter shows the one-pin layout.

### Zero warnings

**The only stable number of warnings is zero.** If a rule isn't worth failing the build for, turn it off instead of demoting it. Exceptions are local, name their rule and give a reason:

```python
# Good: specific rule, reason stated
subprocess.run(cmd, shell=True)  # noqa: S602 -- cmd is a constant from settings, not user input

# Bad: silences everything on the line, forever
subprocess.run(cmd, shell=True)  # noqa
```

Lint the suppressions too (ruff `RUF100`, golangci-lint `nolintlint`).

### Inheriting a legacy repo

Ratchet, so new code meets the standard today and old debt can only shrink: the formatter first, in its own MR, with its SHA in `.git-blame-ignore-revs`; then a small high-value rule set fixed to zero; then the wider set with a baseline (`ruff check --add-noqa`, `eslint --suppress-all`). Changed-files linting stops growth but never shrinks the backlog, and **never works for type checkers**.

> **One-way door.** Making a check required without a bypass path. The day it breaks (a flaky test, a scanner outage, a linter false positive), every merge stops, including the fix. Before you make anything required, write down who can merge when it's broken, how, and how the relaxation gets reverted.

---


<a id="ch02"></a>

## 02 · Configure the linters

*One formatter and one linter per language, configured in the file the ecosystem already reads and pinned in the lockfile. Config files are code too: check them for syntax, then schema, then policy.*

The keystroke end of the route: the tools your editor, hook and CI will all call. Configure each once; the rest of the guide runs it in more places.

### The picks

| File | Pick | Why |
|---|---|---|
| Python | `ruff format` + `ruff check` with explicit `select`; **mypy `strict`** | One tool replaces flake8, isort and black. Close call: pyright if no plugin-dependent library |
| JS / TS | Prettier + **ESLint 10** flat config + typescript-eslint `strictTypeChecked`; `tsc --noEmit` | Type-aware rules (`no-floating-promises`) catch async bugs. Biome if you need neither typed rules nor plugins |
| Go | **golangci-lint v2** (`default: standard` + a curated list), gofmt + goimports via its `formatters:` block | One binary, one config |
| Shell | **shellcheck** + **shfmt** | The highest-value linter in a DevOps repo |
| Dockerfile | **hadolint**, `failure-threshold: warning` | Runs shellcheck on every `RUN` |
| YAML | **yamllint** `--strict` | Catches YAML 1.1 traps: `NO` becomes `false`, `0644` becomes 420 |
| Helm / Kubernetes | `helm lint --strict`, **`helm template` piped to `kubeconform -strict`**, kube-linter | Templates aren't YAML until rendered |
| Terraform | `fmt -check`, `validate`, **tflint**, **Trivy config** | Trivy is the same tool you gate images with |
| `.gitlab-ci.yml` | `check-gitlab-ci` in the hook, `glab ci lint` before merging | The schema check can't resolve includes or evaluate rules |
| Everything | **`.editorconfig`** | Stops pointless whitespace diffs; shfmt reads it |

> **Version-sensitive.** Three of these changed shape recently. **Ruff 0.16** expanded the default rule set from 59 to 413 rules. **ESLint 10** removed `.eslintrc` entirely. **golangci-lint v2** rewrote the config schema. A blog post older than 2025 is probably showing you the old shape.

### Python

Install with `uv add --dev ruff==0.16.8 mypy==2.3.1` so the hook and CI use the lockfile version. Use `select`, not `extend-select`, so ruff's big new default set can't change your rules under you. This is a trimmed version of the full manual's selection.

```toml
# file: pyproject.toml
[tool.ruff]
line-length = 100
force-exclude = true   # respect excludes even when a hook passes filenames

[tool.ruff.lint]
select = ["F", "E", "W", "I", "B", "UP", "S", "SIM", "C4", "PTH", "DTZ", "T20", "PT", "RUF"]
ignore = ["E501"]      # the formatter owns line length
unfixable = ["F401", "F841"]

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["S101"]   # asserts are fine in tests

[tool.mypy]
strict = true
enable_error_code = ["ignore-without-code"]
files = ["src", "tests"]
```

### JavaScript and TypeScript

The typed block is what earns ESLint its place. `projectService` gives it type information, and `eslint-config-prettier` goes last so the two never fight.

```javascript
// file: eslint.config.mjs
import js from "@eslint/js";
import { defineConfig, globalIgnores } from "eslint/config";
import tseslint from "typescript-eslint";
import eslintConfigPrettier from "eslint-config-prettier/flat";

export default defineConfig([
  globalIgnores(["dist/", "coverage/"]),
  { linterOptions: { reportUnusedDisableDirectives: "error" } },
  js.configs.recommended,
  tseslint.configs.strictTypeChecked,
  {
    languageOptions: {
      parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
    },
  },
  eslintConfigPrettier,
]);
```

### Go and shell

golangci-lint v2 needs `version: "2"`, and the issue caps must be zero or findings are silently truncated.

```yaml
# file: .golangci.yml
version: "2"
linters:
  default: standard
  enable: [bodyclose, errorlint, gosec, nolintlint, revive]
  exclusions:
    presets: [comments, std-error-handling, common-false-positives]
formatters:
  enable: [gofmt, goimports]
issues:
  max-issues-per-linter: 0
  max-same-issues: 0
output:
  formats:
    text: { path: stdout }
    code-climate: { path: gl-code-quality-report.json }   # the CI report
```

`shfmt -f .` finds shell scripts by shebang as well as extension, which is how you catch `bin/deploy`.

```bash
shfmt -f . | xargs shellcheck -f gcc
shfmt -d .
```

### Config files: three levels of valid

Check config for **syntax** (does it parse), **schema** (does it match what the consumer expects) and **policy** (is it a good idea). Schema is where the value is: `replica: 3` passes yamllint, is dropped by `kubectl`, and runs one pod in production. `kubeconform -strict` rejects it in 50 ms.

Render a chart with every values file you ship, at the same Kubernetes version you pass to kubeconform.

```bash
for values in charts/app/ci/*-values.yaml; do
  helm template app charts/app -f "$values" --kube-version 1.33.0 \
    | kubeconform -strict -summary -kubernetes-version 1.33.0
done
```

Pin the base image by digest instead of pinning every apt package, which breaks the build when Debian drops the version.

```yaml
# file: .hadolint.yaml
failure-threshold: warning
ignored: [DL3008, DL3018]
override:
  error: [DL3002, DL3007, DL3020, DL4006]
```

For yamllint, `extends: default`, ignore `charts/*/templates/` (Go templates, not YAML), and keep the `truthy` and `octal-values` rules on.

> **Gotcha.** Two silent passes to avoid. yamllint rules set to `warning` never fail without `--strict`. And `kubeconform -ignore-missing-schemas` turns a typo'd `kind: Deploymnet` into a pass; use `-skip KIND` for the specific kinds you can't get schemas for.

---


<a id="ch03"></a>

## 03 · Hooks and secrets

*pre-commit gives every contributor the same pinned hooks in under three seconds, and CI runs the same config on all files. gitleaks runs before the push because a pushed secret has to be rotated, not deleted.*

You've saved the file. Now `git commit` fires the hooks. They are the cheapest place to catch a mistake and the easiest place to skip, so make them fast, make them fix rather than nag, and assume CI re-runs every one.

### The hooks that matter

| Hook | Fires | Use for | Budget |
|---|---|---|---|
| `pre-commit` | before the commit is created | formatters, fast linters, secret scan of staged changes | ~3 s |
| `commit-msg` | after the message is written | Conventional Commits check | under 1 s |
| `pre-push` | before objects are sent | type check, `glab ci lint`, tests | ~30 s |

`.git/hooks/` isn't versioned, so something must install the hooks, and `--no-verify` skips them.

### Install pre-commit

pre-commit builds an isolated, pinned environment per hook, so a new contributor gets shellcheck, hadolint and gitleaks without installing any of them.

```bash
uv tool install pre-commit
pre-commit install --install-hooks
pre-commit run --all-files
```

`SKIP=mypy git commit …` skips one hook without skipping the rest.

### A lean config

`default_install_hook_types` is the line people forget: without it, only the `pre-commit` hook is installed and the others silently never run. Revs are frozen to SHAs because tags can move; regenerate them with `pre-commit autoupdate --freeze`.

```yaml
# file: .pre-commit-config.yaml
default_install_hook_types: [pre-commit, commit-msg, pre-push]
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: 3e8a8703264a2f4a69428a0aa4dcb512790b2c8c  # frozen: v6.0.0
    hooks:
      - id: end-of-file-fixer
      - id: trailing-whitespace
      - id: check-yaml
        args: [--unsafe]          # tolerates GitLab's !reference tags
      - id: no-commit-to-branch
        args: [--branch, main]
  - repo: https://github.com/shellcheck-py/shellcheck-py
    rev: 745eface02aef23e168a8afb6b5737818efbea95  # frozen: v0.11.0.1
    hooks:
      - id: shellcheck
  - repo: https://github.com/gitleaks/gitleaks
    rev: 83d9cd684c87d95d656c1458ef04895a7f1cbd8e  # frozen: v8.30.1
    hooks:
      - id: gitleaks
  - repo: https://github.com/commitizen-tools/commitizen
    rev: 3f5ccc87b27966d9ed21cf5ea8ec2fba38ca65ce  # frozen: v4.19.0
    hooks:
      - id: commitizen            # runs at commit-msg
  - repo: local
    hooks:
      - id: ruff-check
        name: ruff check (project version)
        entry: uv run --frozen ruff check --fix --exit-non-zero-on-fix --force-exclude
        language: system
        types_or: [python, pyi]
      - id: mypy
        name: mypy (project env)
        entry: uv run --frozen mypy
        language: system
        types: [python]
        pass_filenames: false
        stages: [pre-push]        # whole-program and slow
```

**The rule of thumb:** toolchain tools (ruff, mypy, ESLint) go in `repo: local` and call the lockfile version with `uv run` or `npx --no-install`. Standalone binaries (shellcheck, hadolint, gitleaks) come from pre-commit repos pinned by SHA. One pin per tool, never two.

### The same hooks in CI

CI runs the same config on every file. The cache is what makes it fast.

```yaml
# file: .gitlab-ci.yml
pre-commit:
  stage: lint
  image: python:3.13-slim
  needs: []
  variables:
    PRE_COMMIT_HOME: ${CI_PROJECT_DIR}/.cache/pre-commit
    SKIP: gitleaks,no-commit-to-branch
  cache:
    key:
      files: [.pre-commit-config.yaml]
      prefix: pre-commit
    paths: [.cache/pre-commit]
  before_script:
    - apt-get update -qq && apt-get install -y -qq --no-install-recommends git >/dev/null
    - pip install --quiet pre-commit==4.6.2
  script:
    - pre-commit run --all-files --show-diff-on-failure
```

> **Gotcha.** Two settings that fail silently. `PRE_COMMIT_HOME` must sit inside `CI_PROJECT_DIR`, because GitLab only caches paths there. And `SKIP: gitleaks` is deliberate: the hook scans staged changes, nothing is staged in CI, so it would give a green tick that scanned nothing. Secret scanning gets its own CI job (the lint jobs chapter).

### Secrets: gitleaks in three places

Once a credential is in a pushed commit, in any branch, treat it as compromised. So gitleaks runs:

- **in the hook**, on the staged diff, before the commit exists;
- **in CI on every MR**, over the MR's commits, which catches `--no-verify`;
- **once over full history**, when you adopt it.

```bash
gitleaks git --pre-commit --staged --redact
gitleaks git --log-opts="origin/main..HEAD" -v
gitleaks git --log-opts="--all" --redact
```

A fake value in a test gets an inline allow with a reason, so it's visible in review:

```python
TEST_TOKEN = "ghp_0000000000000000000000000000000000"  # gitleaks:allow -- fake token for parser tests
```

Always pass `--redact` in CI, or the job log prints the secret and the scanner becomes the leak.

> **One-way door.** A pushed secret is readable by everyone with access from that moment: forks, clones, job logs, MR diffs. **Rotate first.** Rewriting history is optional cleanup, not remediation.

### Commit messages

Conventional Commits let the release tooling compute the version and changelog mechanically.

```text
type(scope)!: description

optional body

BREAKING CHANGE: what breaks and how to migrate
Refs: PROJ-123
```

`feat` bumps minor, `fix` and `perf` bump patch, `!` or `BREAKING CHANGE:` bumps major. commitizen checks it with no Node runtime:

```bash
cz check --commit-msg-file .git/COMMIT_EDITMSG
cz check --message "feat(api): add pagination"
```

If you squash on merge, and the merge chapter says you should, only the MR title reaches `main`. That's the message to lint in CI.

---


<a id="ch04"></a>

## 04 · Branch off the trunk

*Keep one long-lived branch, main, and work branches that live hours to two days; add release/X.Y only for versions you ship and must patch. Unfinished work merges dark behind a feature flag instead of waiting on a branch.*

The commit is clean and needs a branch. The branching model decides how long that branch lives away from `main`, and every conflict, stale review and painful hotfix scales with that number.

### Trunk-based, with release branches when you need them

**Default: trunk-based development.** One shared branch, `main`. Work happens on MR branches that live for hours, not weeks. Every merge goes through an MR with a green pipeline, and `main` is always deployable.

```mermaid
%% caption: Branches leave main and come back within a day or two; release branches exist only for versions customers run.
flowchart LR
  M1["main"] --> M2["main"] --> M3["main"] --> M4["main"]
  M1 --> F1["feat/PROJ-101, 4 hours"]
  F1 -->|"MR, squash"| M2
  M2 --> F2["fix/PROJ-102, 1 day"]
  F2 -->|"MR, squash"| M3
  M3 --> R["release/2.4"]
  R --> T["tag v2.4.0"]
  M4 -->|"cherry-pick -x"| R
```

| Strategy | Long-lived branches | Branch life | Fits |
|---|---|---|---|
| **Trunk-based** | `main` | hours to 2 days | services you deploy yourself |
| GitLab flow, release branches | `main` + `release/X.Y` | days | software customers install and you patch |
| GitLab flow, environment branches | `main` + `staging`, `production` | days | when an auditor requires production state to be a git ref |
| gitflow | `main` + `develop` + `release/*` + `hotfix/*` | weeks | boxed software with long QA, and not much else |

**Why not gitflow:** `develop` is a second integration point that adds no capability. The pipeline that tested `develop` didn't test what lands on `main`, and every hotfix must be merged twice. Even its author now points continuously delivered software at a simpler flow.

**Why not environment branches, usually:** GitLab already records what's deployed where. Promote one immutable image digest through protected environments instead (the deploy chapter). The tiebreaker: use environment branches only if your change board requires production state to be a git ref.

> **One-way door.** Not the model itself, but the habits it trains. Switching off gitflow takes a day. Unlearning long-lived branches, big-batch reviews and release-day heroics takes a quarter. Budget for the habits.

### What trunk-based demands

It isn't "no process". It moves the process into three places:

1. **A fast, trustworthy pipeline**, under 10 minutes for an MR, so a red `main` is rare and short.
2. **Feature flags**, so code that isn't ready still merges; it just doesn't run. Each flag gets an owner and a removal ticket the day it's created.
3. **Small slices**: schema first, then code that writes both shapes, then code that reads the new one, then cleanup.

A branch older than two working days is a problem to raise at stand-up, not a normal state.

### Name the branch

The convention is `TYPE/JIRAKEY-NUMBER-short-slug`, with the Jira key in uppercase so Jira's development panel picks it up.

```text
feat/PROJ-1234-oidc-login
fix/PROJ-1250-null-tenant-crash
release/2.4
```

Create the branch, push it and open a draft MR in one go. Opening the MR in the same push also saves you a duplicate branch pipeline.

```bash
git switch -c feat/PROJ-1234-oidc-login origin/main
git push -u origin HEAD \
  -o merge_request.create \
  -o merge_request.target=main \
  -o merge_request.draft \
  -o merge_request.title="feat(auth): OIDC login [PROJ-1234]"
```

On Premium, a push rule rejects bad names. On Free, an MR job that greps `$CI_MERGE_REQUEST_SOURCE_BRANCH_NAME` against this pattern does the same:

```text
^(feat|fix|chore|docs|refactor|perf|test|build|ci|revert)/[A-Z][A-Z0-9]+-[0-9]+-[a-z0-9-]+$
```

### Stack dependent work

When a feature is naturally several layers, open a chain of small MRs, each targeting the branch below. `--update-refs` moves every branch pointer in the stack when you rebase the top.

```bash
git config --global rebase.updateRefs true
git fetch origin
git rebase --update-refs origin/main
git push --force-with-lease origin feat/PROJ-10-schema feat/PROJ-10-handlers feat/PROJ-10-ui
```

With squash on merge, the bottom layer lands as a new commit the upper branches don't contain, so rebase the rest with `git rebase --update-refs --onto origin/main LOWER_BRANCH TOP_BRANCH`.

### Hotfix: upstream first, then down

Fix on `main` through a normal MR, then cherry-pick onto each supported release branch. Fixing the release branch first means you'll eventually forget to bring the fix forward, and the bug comes back in the next release.

```bash
git fetch origin
git switch -c fix/PROJ-1400-token-refresh-race-2.4 origin/release/2.4
git cherry-pick -x COMMIT_SHA
git push -u origin HEAD \
  -o merge_request.create \
  -o merge_request.target=release/2.4
```

`-x` records the original SHA in the message, so "is the fix in 2.3?" becomes a search:

```bash
git log origin/release/2.3 --oneline --grep 'cherry picked from commit COMMIT_SHA'
```

> **Note.** Protect `release/*` and `v*` tags **before** you cut the first release branch. Support the fewest release lines your contracts allow, and write the policy down before the CVE arrives: each supported branch multiplies every security fix.

---


<a id="ch05"></a>

## 05 · The merge request

*Fast-forward with squash required turns one MR into one commit on a straight main, so the MR title is the message that matters. Protect main and v* tags, require a green pipeline, and let merge trains stop two green MRs from making a red main.*

The MR is open. The merge settings decide what `main`'s history looks like and what "green" means at merge time. Set them once, before the first MR, at group level where you can.

### The settings

| Setting | Value | Why |
|---|---|---|
| Merge method | **Fast-forward merge** | Straight history; `main` only holds commits tested in exactly that order |
| Squash commits when merging | **Require** | One MR, one commit, one clean revert or cherry-pick |
| Squash commit template | `%{title}` + body | The Conventional Commit MR title becomes the commit subject |
| Pipelines must succeed | **On** | "Green" has to mean something |
| Skipped pipelines are successful | **Off** | Otherwise `ci.skip` walks around the gate |
| All threads must be resolved | **On** | Review comments aren't advisory |
| Merged results pipelines | **On** (Premium) | Test the merge, not the branch |
| Merge trains | **On** once more than a few MRs merge a day (Premium) | Stops two green MRs making a red `main` |

**Close call: fast-forward versus semi-linear.** Semi-linear keeps a merge commit per MR and gives the same testing guarantee. The tiebreaker: if your MRs regularly hold several commits that each deserve to be bisectable and revertable on their own, take semi-linear with squash off. If they're mostly "wip" and "address review", squash throws away noise and fast-forward wins.

### Protect main and the release tags

In **Settings > Repository > Protected branches**, for `main` and `release/*`:

- **Allowed to push and merge: no one.** Every change arrives through an MR with a pipeline.
- **Allowed to merge:** Developers and Maintainers on `main`, Maintainers on `release/*`.
- **Force push: off.**
- **Code owner approval: on** (Premium), and protect the `CODEOWNERS` file itself.

Protect the `v*` tag pattern so only Maintainers or the release bot can create tags. Tags trigger releases, and **protected variables only reach protected refs**: protect `main` but not `v*`, and the release job fails with an empty variable rather than a clear error.

> **One-way door.** Force-pushing a protected branch, even once, rewrites the SHAs everyone has based work on, orphans MR diffs and breaks `cherry-pick -x` references. Nothing in GitLab undoes it. If a secret leaked into `main`, rotate the secret.

### Approvals

On Premium, require one approval for services and two for infra or platform repos. Then prevent approval by the author and by anyone who added commits, prevent editing approval rules in MRs, and remove approvals when commits are added, so approvals cover the code that actually merges.

### Lint the MR title

With squash required, the MR title is the only message that reaches `main`, and it's what the changelog is built from. Lint it, not the branch commits.

```yaml
# file: .gitlab-ci.yml
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

> **Gotcha.** Renaming an MR doesn't start a pipeline, so a failed title check stays red after the fix. Re-run the pipeline after retitling, with **Run pipeline** on the MR or `glab ci run --mr`.

### Merged results and merge trains

A **merged results** pipeline tests your branch merged into today's `main`. A **merge train** queues MRs and tests each against `main` plus everything ahead of it.

```mermaid
%% caption: Each train pipeline includes every MR ahead of it, so the combination that lands on main is the one that was tested.
flowchart LR
  M["main at C"] --> A["C + MR 101"]
  A --> B["C + 101 + 102"]
  B --> X["C + 101 + 102 + 103"]
  A -->|"green"| L1["101 merges"]
  B -->|"green"| L2["102 merges"]
  X -->|"red"| D["103 dropped, author told"]
```

In train pipelines `$CI_MERGE_REQUEST_EVENT_TYPE` is `merge_train`, so you can save the full e2e suite for the train:

```yaml
# file: .gitlab-ci.yml
e2e:
  rules:
    - if: $CI_MERGE_REQUEST_EVENT_TYPE == "merge_train"
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      when: manual
      allow_failure: true
```

Without trains, fast-forward on a busy repo means everyone rebases all day (`glab mr rebase MR_IID`, or `git push --force-with-lease --force-if-includes` after a local rebase); trains with fast-forward need GitLab 16.5 or later. But a train multiplies pipeline load and ejects innocent MRs on a flaky test, so **fix flakes and cut pipeline time first**, or people learn "merge immediately" and the train becomes theatre.

---


<a id="ch06"></a>

## 06 · Anatomy of a pipeline

*workflow:rules decides whether a pipeline exists and what kind it is; each job's rules then decide whether that job is in it. Wire every job with needs, so it starts when its inputs are ready instead of when a stage drains.*

The MR is open and a pipeline starts. What GitLab builds is two decisions made in order; get them right and the rest is just scripts.

### How GitLab reads the file

GitLab resolves includes, merges `extends` and `!reference`, evaluates `workflow:rules` once, then each job's `rules`. **All of it happens at pipeline creation**, so a variable set in a job's `script` or `dotenv` can't decide whether a later job exists.

Three predicates cover most rules:

```yaml
if: $CI_PIPELINE_SOURCE == "merge_request_event"   # an MR pipeline
if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH         # the default branch
if: $CI_COMMIT_TAG                                  # a tag pipeline
```

### MR pipeline or branch pipeline

Without `workflow:rules`, every push to a branch with an open MR gets **two** pipelines: a branch pipeline and an MR pipeline. Double the runner cost, two sets of statuses. The standard fix:

```mermaid
%% caption: Rules are tried top to bottom and the first match decides; a push to a branch with an open MR is dropped because the MR pipeline covers it.
flowchart TD
  E["event"] --> Q1{"merge_request_event?"}
  Q1 -->|"yes"| MR["MR pipeline"]
  Q1 -->|"no"| Q2{"branch push with an open MR?"}
  Q2 -->|"yes"| N["no pipeline"]
  Q2 -->|"no"| Q3{"branch or tag?"}
  Q3 -->|"branch"| BR["branch pipeline"]
  Q3 -->|"tag"| TG["tag pipeline"]
  Q3 -->|"neither"| N
```

```yaml
# file: .gitlab-ci.yml
workflow:
  auto_cancel:
    on_new_commit: interruptible
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS && $CI_PIPELINE_SOURCE == "push"
      when: never
    - if: $CI_PIPELINE_SOURCE == "schedule"
    - if: $CI_COMMIT_TAG
    - if: $CI_COMMIT_BRANCH
```

Without the `schedule` line, schedules silently create nothing.

**Always create a pipeline for MRs.** With "Pipelines must succeed" on, an MR whose jobs are all filtered out by `rules:changes` can never merge. Keep one cheap MR job with no `changes` filter, in a real stage: a pipeline with only `.pre` or `.post` jobs isn't created.

### Job rules

`rules` is an ordered list. **The first matching rule decides**, and if none matches the job isn't added. Clauses in one rule are ANDed; separate rules are ORed. So exclusions go first:

```yaml
test:e2e:
  rules:
    - if: $CI_COMMIT_TAG
      when: never
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - when: manual
      allow_failure: true
```

Use `rules`, never the legacy `only`/`except`.

> **Gotcha.** `when: manual` inside `rules` defaults to `allow_failure: false`. The pipeline shows as **blocked** until someone clicks, and "Pipelines must succeed" then blocks the MR. For optional manual jobs, always write `allow_failure: true`.

### Stages for layout, needs for order

By default a job waits until **every** job in the previous stage has finished. `needs` lets it start as soon as the jobs it actually depends on are done, which turns the waterfall into a graph.

```mermaid
%% caption: With needs, lint and tests start at once and the image waits only for what gates it; the slow e2e suite never blocks the build.
flowchart LR
  R["ruff"] --> B["build:image"]
  P["pytest"] --> B
  MY["mypy"] --> S["deploy:staging"]
  B --> S
  H["helm:lint"] --> HP["helm:package"]
  HP --> S
  E["e2e"]
```

```yaml
ruff:
  stage: lint
  needs: []              # start at t=0
build:image:
  stage: build
  needs: [ruff, pytest]  # ignores mypy and e2e
```

| Form | Effect |
|---|---|
| `needs: []` | Start immediately, ignoring stages |
| `needs: [a, b]` | Wait for `a` and `b`, download their artefacts |
| `needs: [{job: a, artifacts: false}]` | Wait for `a`, skip its artefacts |
| `needs: [{job: a, optional: true}]` | Wait for `a` if it exists in this pipeline |

**Default: declare `stages:` for readability, wire every job with `needs`.** A job without `needs` falls back to stage order, which is a common answer to "why is this waiting?".

> **Gotcha.** If job B needs job A and A's rules left it out of this pipeline, **pipeline creation fails**: "'B' job needs 'A' job, but 'A' is not in any previous stage". Add `optional: true` whenever the needed job has its own `rules:changes` or branch conditions.

### Reuse inside the file

Use `extends` for job templates and `!reference` to splice shared `rules` or `script` lists. Skip YAML anchors: they can't reach across `include` files. `extends` merges maps deeply but **replaces arrays**, so splice lists with `!reference`.

```yaml
.rules:mr-main-tag:
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_COMMIT_TAG

.python:
  image: docker.io/library/python:3.13-slim
  before_script: [pip install --quiet uv, uv sync --frozen]

mypy:
  extends: .python
  stage: lint
  needs: []
  rules: !reference [.rules:mr-main-tag, rules]
  script:
    - uv run mypy src
```

When a job ignores your YAML change, check **Settings > CI/CD > Variables**: a project variable silently beats the same name in the file.

---


<a id="ch07"></a>

## 07 · Lint jobs that fail correctly

*A lint job has two duties: exit non-zero when the tool found something, and upload a report GitLab can show the reviewer, even when it fails. Run every lint job on the default branch too, so the MR widget has something to diff against.*

The pipeline exists. **A lint job is correct when its exit status is the tool's exit status**, and most broken lint jobs pass silently.

### How the runner runs your script

The runner joins `before_script` and `script` into one shell script with `errexit` and `pipefail` on, so any failing line fails the job. `after_script` runs in a separate shell and never fails the job.

What errexit doesn't catch, and what to do instead:

| Pattern | Why it passes | Fix |
|---|---|---|
| `ruff check . \|\| true` | Throws the status away | Delete it; capture `rc` if something must run after |
| `ruff check . && echo ok` | A failing left side of `&&` is exempt from errexit | Separate lines |
| `if ruff check .; then …; fi` | `if` conditions are exempt | Handle `else` with `exit 1` |
| `allow_failure: true` | Job fails, pipeline passes, MR merges | Remove it, or scope it with `exit_codes` |

> **Gotcha.** `allow_failure: true` on a lint job is worse than deleting it: a yellow job nobody reads, plus a false sense that the check exists. `|| true` is the same lie in a different place. Both mean "never fails".

### Capture, convert, exit

When a tool can't print for humans and write a report in one run, capture its exit code, build the report, then exit with that code. Keep such scripts in `ci/*.sh`, where shellcheck sees them.

```bash
# file: ci/lint-mypy.sh
#!/usr/bin/env bash
set -euo pipefail

rc=0
uv run mypy --no-error-summary > mypy-out.txt || rc=$?
cat mypy-out.txt
uv run mypy-gitlab-code-quality < mypy-out.txt > gl-cq-mypy.json
exit "$rc"
```

`cmd || rc=$?` records the failure and the last line re-raises it. If warnings shouldn't block, use `allow_failure: exit_codes: [2]`, which still fails on real errors.

### A lint job template

Every lint job extends one hidden template. `artifacts:when: always` matters most: by default artefacts upload only on success, so a failing job shows a red X and **no findings in the MR**, exactly when the reviewer needed them.

```yaml
# file: .gitlab/ci/lint.yml
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
```

A Python job that gates on both ruff runs and reports both to Code Quality:

```yaml
lint:python:
  extends: .lint
  image: ghcr.io/astral-sh/uv:python3.13-bookworm-slim
  variables:
    UV_CACHE_DIR: ${CI_PROJECT_DIR}/.cache/uv
  script:
    - uv sync --frozen --only-group dev
    - rc=0
    - uv run ruff check --output-format=gitlab --output-file=gl-cq-ruff.json . || rc=$?
    - uv run ruff format --check --output-format=gitlab --output-file=gl-cq-ruff-format.json . || rc=$?
    - exit $rc
  artifacts:
    reports:
      codequality: gl-cq-ruff*.json
```

Keep **one job per ecosystem**: parallel, separately cached, and a red job's name tells you which toolchain failed.

### Reports in the MR

Code Quality shows the findings an MR **introduces** and **resolves**; JUnit feeds the test widget on every tier, which is how kubeconform, tflint and gitleaks reach the MR on Free. Report paths must be repo-relative and fingerprints stable, or every finding looks new.

**Run lint jobs on the default branch as well.** Every comparing widget diffs against the target branch's latest pipeline. No report on `main` means nothing to compare against.

> **Version-sensitive.** The old CodeClimate-based `Code-Quality.gitlab-ci.yml` template was deprecated in GitLab 17.3 and is planned for removal in 19.0. Don't adopt it; produce reports from your own linters.

### Skip jobs with rules:changes, carefully

`rules:changes` skips a job when its files didn't change. What it compares against depends on the pipeline type, which is the part that bites:

- **MR pipeline:** the whole MR diff against the target branch. What you want.
- **Branch pipeline:** only this push against the previous push. A README-only push skips the Go lint even if earlier commits touched Go.
- **New branch, tag, schedule, web, API:** nothing to compare, so always true.

So use `changes` in MR pipelines, run unconditionally on the default branch, and list the config files that change findings:

```yaml
lint:go:
  extends: .lint
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes:
        paths: ["**/*.go", go.mod, go.sum, .golangci.yml, .gitlab/ci/lint.yml]
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

On branch pipelines, add `compare_to: refs/heads/main` to make `changes` behave like an MR diff.

### Secrets on the MR range

On Free, the Secret Detection template fails nothing and shows nothing in the MR. Gate with your own gitleaks job over the MR's commits:

```yaml
secrets:gitleaks:
  extends: .lint
  image: zricethezav/gitleaks:v8.30.1
  variables:
    GIT_DEPTH: 0
  script:
    - |
      if [ -n "${CI_MERGE_REQUEST_DIFF_BASE_SHA:-}" ]; then
        range="${CI_MERGE_REQUEST_DIFF_BASE_SHA}..${CI_COMMIT_SHA}"
      else
        range="${CI_COMMIT_BEFORE_SHA}..${CI_COMMIT_SHA}"
      fi
      case "$range" in 0000000000000000000000000000000000000000..*) range="-1 $CI_COMMIT_SHA" ;; esac
      gitleaks git --redact --no-banner -v --log-opts="$range" \
        --report-format junit --report-path junit-gitleaks.xml
  artifacts:
    reports:
      junit: junit-gitleaks.xml
```

---


<a id="ch08"></a>

## 08 · Fast and shared pipelines

*Pipeline time is mostly waiting, so measure the critical path and remove the waits: needs, a lockfile-keyed cache and interruptible jobs halve most pipelines. When a second repo needs the same jobs, ship them as a versioned CI/CD component instead of a copied file.*

The pipeline works. Now make it fast: under 10 minutes for an MR, because over 20 people stop waiting and context-switch.

### Measure first

Only jobs on the **critical path**, the longest chain of dependent jobs, affect wall-clock time. Sort the latest pipeline's jobs by duration and queue time:

```bash
glab ci get -F json | jq -r '
  .jobs[] | [.name, .stage, .status, (.queued_duration // 0 | floor), (.duration // 0 | floor)]
  | @tsv' | sort -t$'\t' -k5 -n -r | column -t
```

Queued for minutes means too few runners or a tag nobody serves. Then fix, biggest payoff first: `needs` instead of a stage waterfall, `interruptible` plus auto-cancel, a correct cache key, a registry layer cache for images, and `rules:changes` in MR pipelines.

### Cache or artefact

```mermaid
%% caption: Artefacts carry results forward inside one pipeline and are guaranteed; the cache carries downloads across pipelines and may be missing.
flowchart LR
  subgraph P1["pipeline 1"]
    B1["build"] -->|"artefact: dist, dotenv"| D1["deploy"]
  end
  subgraph P2["pipeline 2"]
    B2["build"]
  end
  B1 -->|"cache: uv download dir"| C["runner cache store"]
  C -.->|"best effort"| B2
```

| | Cache | Artefacts |
|---|---|---|
| Purpose | Speed up **repeat** work: downloaded dependencies | Pass **results** between jobs and keep them |
| Stored | Runner or its distributed cache (S3, GCS) | GitLab |
| Guaranteed present | **No**, best effort | **Yes**, for jobs that need the producer, until expiry |
| Scope | Any pipeline with the same key | This pipeline |
| Wrong use | Passing build output to the next job: fails intermittently | `node_modules` or a virtualenv: hundreds of MB per job |

Cache the **download** directory (`UV_CACHE_DIR`, `npm_config_cache`), not the virtualenv, which embeds absolute paths and breaks on an image bump.

### The cache key

Key dependency caches on the lockfile, so the key changes exactly when dependencies do. Fall back to a key `main` keeps warm, so a new lockfile doesn't start cold. Pull in MRs and push only from `main`, so MR branches can't overwrite the cache `main` relies on.

```yaml
# file: .gitlab-ci.yml
variables:
  UV_CACHE_DIR: $CI_PROJECT_DIR/.cache/uv
  CACHE_POLICY: pull

.python:
  cache:
    key:
      files: [uv.lock]
      prefix: uv
    fallback_keys: [uv-$CI_DEFAULT_BRANCH]
    paths: [.cache/uv]
    policy: $CACHE_POLICY
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      variables:
        CACHE_POLICY: pull-push
```

The fallback only helps if something fills it: add a job on `main` that writes the stable key `uv-$CI_DEFAULT_BRANCH` with `policy: push`. Analysis caches (ruff, mypy, ESLint, golangci-lint) key on the branch instead, `eslint-$CI_COMMIT_REF_SLUG` with a fallback to the default branch, so a new branch's first run is warm. ESLint needs `--cache-strategy content` in CI, because a fresh checkout gives every file a new mtime.

> **Gotcha.** Three reasons a cache never hits. **Paths outside `$CI_PROJECT_DIR`** (`~/.cache/pip`) are silently not cached. **Kubernetes runners without a distributed cache** lose it with every pod; the log says "No URL provided". And **protected and unprotected refs get separate caches** by default, so an MR branch's fallback won't find `main`'s protected cache.

### Cancel stale work

When you push twice, the first pipeline is waste. Auto-cancel stops it, but only for jobs marked interruptible:

```yaml
workflow:
  auto_cancel:
    on_new_commit: interruptible

deploy:production:
  interruptible: false   # never cancel a half-applied deploy
```

Gate-only needs can skip artefacts with `needs: [{job: pytest, artifacts: false}]`, except on a job that publishes a `dotenv`, whose variables travel with its artefacts.

### Build images rootless

**Default: rootless BuildKit** (`buildctl-daemonless.sh`): the `docker buildx` engine with no privileged pod, plus a registry cache with `mode=max`. Import `main`'s cache as well as the branch's. Kaniko is archived; don't start new pipelines on it.

### Share it: CI/CD components

When a second repo needs the same jobs, ship a **component**: pipeline YAML with typed inputs, released with SemVer tags.

```yaml
# file: templates/python-test.yml
spec:
  inputs:
    python-version:
      default: "3.13"
      options: ["3.12", "3.13", "3.14"]
    job-prefix:
      default: python
      regex: ^[a-z][a-z0-9-]*$
---
"$[[ inputs.job-prefix ]]:test":
  image: docker.io/library/python:$[[ inputs.python-version ]]-slim
  interruptible: true
  script:
    - pip install --quiet uv && uv sync --frozen && uv run pytest
```

Consumers pin the major version and use `$CI_SERVER_FQDN`, so the config survives a hostname change:

```yaml
include:
  - component: $CI_SERVER_FQDN/platform/components/python-test@1
    inputs:
      python-version: "3.13"
```

**Default: `@1` for internal components, exact versions plus Renovate for third-party ones.** Components define jobs only, never `default:`, top-level `variables:` or `workflow:`, which would silently change every consumer's pipeline.

> **One-way door.** Once projects consume `@1`, every `1.x` release reaches all of them on their next pipeline. A breaking change released as a minor breaks every consumer at once. Removing or renaming an input, changing a default, or renaming a job is always a major bump.

---


<a id="ch09"></a>

## 09 · Release and deploy

*A job on main computes the next version from Conventional Commits and pushes a vX.Y.Z tag, and the tag pipeline promotes the image digest main already built. Deploy controls live in GitLab primitives, environments, resource_group, protected environments and short-lived OIDC credentials, not in script logic.*

The MR merged. A deploy job is the one place CI touches production, so it carries the controls.

### The release flow

Build the image once per commit and promote that digest, so production runs the bytes staging tested.

```mermaid
%% caption: The tag pipeline deploys the digest that main already built and staging already ran; nothing is rebuilt for production.
flowchart LR
  MR["MR pipeline"] --> RV["review app"]
  M["main pipeline"] --> IMG["image at digest"]
  IMG --> ST["staging, automatic"]
  M --> REL["release job: next version"]
  REL --> TAG["tag vX.Y.Z"]
  TAG --> TP["tag pipeline"]
  TP --> PR["production: manual, approved"]
  IMG -.->|"same digest"| PR
```

### Tag from main

A release job on `main` asks git-cliff for the next version and tags only when there's something to release. The release notes go into the annotated tag, not a committed `CHANGELOG.md`: a commit pushed back to `main` would trigger the release job again.

```yaml
# file: .gitlab-ci.yml
release:tag:
  stage: release
  image: docker.io/library/python:3.13
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH && $CI_PIPELINE_SOURCE == "push"
  variables:
    GIT_DEPTH: 0            # git-cliff needs full history and tags
  before_script:
    - pip install --quiet "git-cliff==GIT_CLIFF_VERSION"
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

`RELEASE_TOKEN` is a project access token in a masked, protected variable: `CI_JOB_TOKEN` can't push by default, and a bot token stays attributable and revocable.

### Deploy to an environment

`environment:` makes the job a recorded deployment and `resource_group` runs deploys to one target one at a time. The job also takes the digest from the build job's `dotenv` and fetches credentials for itself alone.

```yaml
# file: .gitlab-ci.yml
deploy:production:
  stage: deploy
  needs: [build:image, helm:package]
  interruptible: false
  rules:
    - if: $CI_DEPLOY_FREEZE
      when: never
    - if: $CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/
      when: manual
      allow_failure: false     # pipeline shows "blocked" until deployed
  environment:
    name: production
    url: https://app.example.internal
    deployment_tier: production
  resource_group: production
  variables:
    VAULT_SERVER_URL: https://bao.example.internal
    VAULT_AUTH_ROLE: app-prod
    KUBE_CONTEXT: group/infra/agents:k8s-agent   # GitLab agent for Kubernetes
  id_tokens:
    VAULT_ID_TOKEN:
      aud: https://bao.example.internal
  secrets:
    DB_PASSWORD:
      vault: app/prod/db_password@kv
      token: $VAULT_ID_TOKEN
      file: false              # the value, not a file path
  script:
    - |
      helm upgrade --install app charts/app \
        --kube-context "$KUBE_CONTEXT" --namespace app-production \
        -f charts/app/values-production.yaml \
        --set image.digest="$IMAGE_DIGEST" \
        --wait --timeout 10m
```

What each control does:

- **Protected environments** (Premium) decide who may run the job and require approvals. A Developer who can push a tag still can't deploy.
- **`resource_group`** serialises across pipelines. Turn on **Prevent outdated deployment jobs** too, so a retried old pipeline can't roll production back.
- **`$CI_DEPLOY_FREEZE`** is set during deploy freezes, but only your rules act on it, and only at pipeline creation: a manual job from a pipeline created before the freeze can still run inside it.
- **Review apps** use `environment: { name: review/$CI_COMMIT_REF_SLUG, on_stop: stop:review, auto_stop_in: 3 days }`, with a stop job that sets `GIT_STRATEGY: none`, because the branch may already be gone.

### Credentials, best first

| Rank | Mechanism | Where the secret lives | Rotation |
|---|---|---|---|
| 1 | **OIDC to the target**: `id_tokens` exchanged with GCP Workload Identity Federation or AWS | Nowhere; a short-lived token per job | Nothing to rotate |
| 2 | **OpenBao or Vault** via `secrets:` (Premium) or a `bao` login in the script (Free) | In the manager | In the manager, no CI change |
| 3 | **CI/CD variable**: masked, hidden, protected and environment-scoped | In GitLab | By hand, per project or group |
| 4 | Anything in the repository | Git history, forever | Impossible; rotate the secret |

Bind OpenBao roles on `project_id` (not `project_path`, which changes on rename), `ref_protected`, `ref_type`, and `environment` for production. The `environment` claim only exists for jobs that declare `environment:`, tying the credential to the protected environment.

On Free, the job does the same exchange in its script with `bao write auth/jwt/login`, passing the `id_tokens` JWT. The legacy `CI_JOB_JWT` variables were removed in GitLab 17.0, so any integration still using them is broken.

> **Gotcha.** Masking is a log filter, not access control. Any job that receives a variable can send it anywhere. What protects a secret is **which jobs receive it at all**: protected refs, environment scope and protected environments. A deploy job without `environment:` bypasses every one of those.

### Publish the release

The tag pipeline creates the GitLab release with the `release:` keyword, using `description: $CI_COMMIT_TAG_MESSAGE` so the notes git-cliff wrote become the release notes. Since GitLab 18.4 that keyword needs `glab` 1.58.0 or newer in the job image (`registry.gitlab.com/gitlab-org/cli`); pin it.

---


<a id="ch10"></a>

## 10 · When the pipeline breaks

*Most "CI is broken" reports are a rule that didn't match the way you read it, a runner that can't pick the job up, or a cache, artefact or variable that wasn't where the job expected. Ask which of the three it is, and run glab ci lint --dry-run, before reading a single log line.*

No pipeline, a missing job, a stuck job, or a red one: the fix is almost always in one of three places.

### Triage

```mermaid
%% caption: Work down from "was a pipeline created" to "what state is the job in"; each branch points at a different cause.
flowchart TD
  A{"pipeline created?"} -->|"no"| W["workflow:rules, invalid YAML, or a failed include"]
  A -->|"yes"| B{"job in the pipeline?"}
  B -->|"no"| R["job rules did not match"]
  B -->|"yes"| C{"job state?"}
  C -->|"pending"| T["no runner with all its tags"]
  C -->|"waiting"| N["needs, resource_group or approval"]
  C -->|"blocked"| M["manual job with allow_failure false"]
  C -->|"failed"| L["read the log upward from the end"]
```

Before guessing, ask GitLab what it would build for this ref:

```bash
glab ci lint --dry-run --ref BRANCH --include-jobs
glab ci config compile > /tmp/merged.yml
glab ci list --yaml-errors
```

`--dry-run` is the only lint mode that evaluates rules, and it simulates a branch or tag pipeline, never an MR pipeline or a schedule. `config compile` shows every include merged, so you can see where a `before_script` came from.

### Why didn't my job run

1. **`workflow:rules` filtered the whole pipeline.** No rule matched, so nothing appears in the list at all. The usual cause: no rule for `schedule`, `web` or `api`.
2. **`$CI_PIPELINE_SOURCE` isn't what you think.** A tag push is `push` (test `$CI_COMMIT_TAG`). `glab ci run` is `api`; add `--mr` for `merge_request_event`.
3. **First match wins.** A `when: never` placed after an inclusive rule never gets a chance. Exclusions go first.
4. **No matching rule means the job is excluded**, which breaks any job that `needs` it.
5. **`changes` is true when there's nothing to compare**: on every tag, schedule and new branch. On a branch pipeline it sees only the last push.
6. **The variable is empty in this pipeline.** An unset variable just makes `if:` false, with no error, so a typo makes a job silently vanish.
7. **Variables are strings.** `if: $DEPLOY` is true for `"false"`. Write `if: $DEPLOY == "true"`.

Which variables are empty where:

| Variable | Empty in |
|---|---|
| `CI_COMMIT_BRANCH` | MR pipelines and tag pipelines |
| `CI_COMMIT_TAG` | Everything except tag pipelines |
| `CI_MERGE_REQUEST_*` | Everything except MR pipelines, including branch pipelines of a branch with an MR |
| Protected variables | Pipelines on unprotected branches and tags |
| Environment-scoped variables | Jobs whose `environment:name` doesn't match the scope |
| Anything set in `script` or `dotenv` | Rule evaluation, always: rules run at pipeline creation |

Build image tags and names from `$CI_COMMIT_REF_SLUG`, never `$CI_COMMIT_BRANCH`, which is empty in MR pipelines.

### Common errors

In a failed log, the last lines are the runner's cleanup; search upward for the first failing command.

- **"'X' job needs 'Y' job, but 'Y' is not in any previous stage"**: Y's rules excluded it. `needs: [{job: Y, optional: true}]`.
- **Stuck pending, "no active runners ... with any of these tags"**: no runner has **all** the job's tags. Compare with `glab runner list` before blaming the runner.
- **"404 Not Found" pulling from another project**: the target project's CI/CD job token allowlist doesn't include this one.
- **"HTTP Basic: Access denied" on `git push`**: `CI_JOB_TOKEN` can't push by default; use a project access token.
- **Job cancelled for no visible reason**: auto-cancel; a newer pipeline made it redundant.

### Debug without leaking

1. `set -x` in the one script block you're debugging.
2. `env | cut -d= -f1 | sort` to see **which** variables exist, without their values.
3. `CI_DEBUG_SERVICES: "true"` to see why a service container won't start.
4. `gitlab-ci-local JOB_NAME` to run a job locally for script and rule bugs. It doesn't reproduce protected variables, `id_tokens`, `secrets:` or environments, so not for deploy jobs.

> **One-way door.** `CI_DEBUG_TRACE: "true"` dumps **every variable, masked and protected included**, into the job log, and masking doesn't apply to that dump. Never set it on a job that receives secrets. If it happened, erase the job log, then **rotate every secret the job could see**; you don't know who read it.

### The daily loop

- [ ] Commit through the hooks; never `--no-verify` past a real finding.
- [ ] Branch as `TYPE/PROJ-123-slug` and open the MR in the same push.
- [ ] Title the MR as a Conventional Commit; re-run the pipeline after renaming.
- [ ] Missing job: `glab ci lint --dry-run --ref BRANCH --include-jobs` first.
- [ ] Stuck job: compare its tags with the runners first.

---


<a id="appendix"></a>

## Z · One-screen reference

*Every default from the route in tables you can print: the picks, the merge settings, the rules predicates and the commands. Where a line says close call, the runner-up is defensible and the tiebreaker is named.*

### Tool picks

| Area | Pick | Runner-up and tiebreaker |
|---|---|---|
| Python | `ruff format`, `ruff check` (`select`), mypy `strict` | pyright if no plugin-dependent library |
| JS / TS | Prettier, ESLint 10 + typescript-eslint `strictTypeChecked`, `tsc --noEmit` | Biome if no typed rules or plugins |
| Go | golangci-lint v2, gofmt + goimports | — |
| Shell | shellcheck + shfmt (`.editorconfig`) | — |
| Dockerfile | hadolint, `failure-threshold: warning`, base pinned by digest | — |
| Kubernetes / Helm | `helm lint --strict`, `helm template` into `kubeconform -strict`, kube-linter | — |
| Terraform | `fmt -check`, `validate` (`init -backend=false`), tflint, Trivy config | checkov for graph-based checks |
| Hooks | pre-commit, revs frozen to SHAs | lefthook if the toolchain already provides every tool |
| Commit check | commitizen `cz check` on the MR title | commitlint in a Node repo |
| Secrets | gitleaks: hook, MR range with `--redact`, full history once | — |
| Releases | git-cliff, annotated `vX.Y.Z` tags from `main` | semantic-release if you want one tool and run Node |

### Merge and branch settings

| Setting | Value |
|---|---|
| Branch model | Trunk-based; `release/X.Y` only for versions you patch; no `develop` |
| Branch name | `TYPE/PROJ-123-slug` |
| Merge method | Fast-forward (close call: semi-linear if MR commits deserve individual bisect) |
| Squash | Require; template `%{title}` + body |
| Pipelines must succeed / skipped count as success | On / Off |
| All threads resolved | On |
| Merged results; merge trains | On (Premium); trains once more than a few MRs a day |
| Protected `main`, `release/*` | Push: no one; force push: off; code owner approval: on |
| Protected tags | `v*`, Maintainers or release bot |
| Approvals | 1 for services, 2 for infra; author and committers can't approve; reset on push |

### What rules:changes compares

| Pipeline | Compared against |
|---|---|
| MR pipeline | The whole MR diff |
| Branch pipeline, existing branch | This push only |
| New branch, tag, schedule, web, API, trigger | Nothing: always true |
| Any, with `compare_to: refs/heads/main` | That ref |

### needs, rules and when

| Write | Means |
|---|---|
| `needs: []` | Start at pipeline start |
| `needs: [{job: a, optional: true}]` | Wait for `a` only if its rules kept it |
| `needs: [{job: a, artifacts: false}]` | Gate on `a`, skip its files (and its dotenv) |
| `when: never` first | Exclusions before inclusions; first match wins |
| `when: manual` + `allow_failure: true` | Optional manual job that doesn't block the MR |
| `when: manual` + `allow_failure: false` | Deliberate gate; pipeline shows blocked |
| `if: $VAR == "true"` | Variables are strings; `if: $VAR` is true for `"false"` |

### Commands

```bash
pre-commit install --install-hooks
pre-commit run --all-files
pre-commit autoupdate --freeze
gitleaks git --log-opts="origin/main..HEAD" --redact
cz check --message "feat(api): add pagination"
glab ci lint --dry-run --ref BRANCH --include-jobs
glab ci config compile
glab ci trace JOB_NAME
glab ci run --mr
git push --force-with-lease --force-if-includes
git cherry-pick -x COMMIT_SHA
```

### Predefined variables

| Variable | Use |
|---|---|
| `CI_PIPELINE_SOURCE` | `push`, `merge_request_event`, `schedule`, `web`, `api`, `trigger`, `pipeline`, `parent_pipeline` |
| `CI_COMMIT_BRANCH` / `CI_COMMIT_TAG` | Branch (empty in MR and tag pipelines) / tag |
| `CI_COMMIT_REF_SLUG` | DNS-safe ref for image tags, namespaces, cache keys |
| `CI_DEFAULT_BRANCH` | Never hardcode `main` |
| `CI_MERGE_REQUEST_DIFF_BASE_SHA` | Merge base for changed-files diffs (MR only) |
| `CI_MERGE_REQUEST_EVENT_TYPE` | `detached`, `merged_result`, `merge_train` |
| `CI_DEPLOY_FREEZE` | Set during a deploy freeze, at pipeline creation |

### One-way doors

| Door | Why it doesn't close |
|---|---|
| A pushed secret | Readable from the push onward; rotate, then clean up |
| Force-pushing a protected branch | Rewrites everyone's SHAs; nothing in GitLab undoes it |
| `CI_DEBUG_TRACE` on a job with secrets | Dumps masked values into the log; erase and rotate |
| A required check with no bypass | The day it breaks, every merge stops, including the fix |
| A breaking component change as a minor | Every `@1` consumer breaks on its next pipeline |
| A privileged runner shared across projects | Root on the node for anyone who can push a branch |

---
