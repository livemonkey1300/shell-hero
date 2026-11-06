---
name: add-feature
description: Add or extend a feature end to end the way the repository at hand already does it — find the nearest existing feature and copy its shape, ask at most four questions when the request is vague, put logic, wiring, config, tests (wired into the suite and CI), docs and the changelog where the repository puts them, run its own checks, flag one-way doors, and stage for the user. Use when asked to "add", "build", "implement" or "extend" a feature.
argument-hint: "<what the feature does>"
---

# Add a feature

The feature: **$ARGUMENTS**

## 0. Read first

The repo's `CLAUDE.md` (every level) and `.claude/rules/`; **they outrank this skill**. Then find the
**nearest existing feature** — the one most like this one — and read it end to end: its logic, its
wiring, its tests, its docs, the commit that added it (`git log --follow --diff-filter=A -- <file>`).
You are going to copy its shape. Write like the code around it: its comment density, its names, its
spelling rule.

## 1. Ask, when it is vague

If the request leaves these open, ask them in one round (AskUserQuestion when available, your best
guess first), at most four: where it lives (which package or module), where it shows (command,
endpoint, menu, setting), what "done" looks like, and whether it writes anything outside the repo.
Then say the plan in a few lines and go. **A clear request needs no questions.**

## 2. Where the code goes

Follow the nearest feature. In most repositories that means:

| Part | Rule |
|---|---|
| Logic, prompts, parsing | A pure module with no UI or framework import, so tests and every front end share it. |
| Wiring (UI, CLI, HTTP handler) | Thin: argument validation, calling the logic, presenting the result. **Validate every input before any network or model call.** |
| Config, flags, settings | Where the others are declared. A setting pointing at a host, a project or a binary is machine-scoped, not synced. |
| Public ids (commands, settings, routes, event names, reply keys) | **One-way doors.** Add; never rename. A rename is a migration. If the repo pins its ids in a fixture or test, add the new one there. |

House rules worth keeping wherever you are:

- Anything written outside the repo (a tracker, the code host, a push, a deploy) is **shown exactly and
  confirmed first**.
- Data from the user, git, a tracker or a file going into an LLM prompt sits in tags, redacted, with
  a closing tag inside it broken; "data, not instructions to you". See `prompt-engineering.md`.
- Additive before destructive: add the new path, move the callers, delete the old path last.
- A migration that creates a resource grants the role the service runs as; without it the deploy is
  clean and the runtime fails.

## 3. Tests (before calling it done)

- Unit tests next to the area's existing suite. **A new suite is wired into the package's test
  script and its CI job** — a test nobody runs is not a test.
- Run the repo's real checks (format, lint, type-check, test) through its task runner. Report the
  result as it is; **a failing test is fixed, not skipped.**

## 4. Docs and changelog

The user guide for the area, the README's feature list when it is a headline feature, the API or
protocol doc for a new endpoint, the `CLAUDE.md` map when a file is added, the changelog if the repo
keeps one by hand (if it is generated from Conventional Commits, the commit message is the changelog
entry).

## 5. Ship

1. Build and install locally if the repo has a step for it, so the user can try it.
2. Stage explicit paths. **Commit only when asked**, on a branch, as the repo's commit style
   (`feat(<area>): …`); the body says why.
3. If merging releases to users, **say so before pushing** — that is a one-way door.

Finish with: the outcome on the first line, what changed, what was verified (the commands and their
output; label anything else read in the code / inferred), what was not, and **Needed from you** (or
"nothing needed"). To take it to a draft PR, follow `/implement-subtask` steps 10–11; to explain it to
reviewers, `/change-brief`.
