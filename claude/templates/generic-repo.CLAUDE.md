<!--
  Project CLAUDE.md — generic repository.
  Copy to ./CLAUDE.md at the repo root and fill in the <PLACEHOLDERS>.
  The `why:` comments explain each section; delete them once filled in —
  this file is loaded into every session in this repo, so every line costs tokens every time.
-->

# <PROJECT_NAME>: context for Claude Code

<!-- why: two or three sentences of orientation. What it is, who uses it, what it runs on.
     The model reads everything below through this lens; without it, it guesses the domain
     from file names and guesses wrong on the first task. -->
<One paragraph: what this is, who uses it, the stack, where it runs.>

Repository: `<GIT_HOST>/<GROUP>/<REPO>`. Tracker: `<TRACKER>` (ticket keys look like `<ABC-123>`).

## Start here

<!-- why: the entry points. If you have project skills, name them here so they get used;
     a skill nobody mentions is a skill the model rarely loads. -->
- `/start-work` when the request is not yet clear; `/add-feature`, `/edit-prompt` for the rest.
- The source of truth for behaviour: `README.md`, `docs/<guide>.md`. **Where docs and code
  disagree, the code wins and the doc is a bug to report.**

## The map

<!-- why: the single highest-value section. A table from "feature" to "where the logic is" to
     "where it is tested" saves the model a dozen greps per task and stops it inventing a new
     module next to the one that already does the job. Keep one row per feature area. -->
| Area | Logic | Wiring (CLI / HTTP / UI) | Tests |
|---|---|---|---|
| <feature> | `src/<area>/` | `src/<area>/handler.ts` | `test/<area>.test.*` |
| <feature> | | | |

## House rules

<!-- why: the rules this codebase already follows, each with its reason in a clause. A rule
     without a reason gets applied in the wrong place or dropped under pressure; a reason lets
     the model tell when the rule does not apply. State each rule once, here, not in three files. -->
- Pure logic lives in modules with no framework/UI import, so tests and every front end share it.
- Anything written outside the repo (a tracker, the code host, a push, a deploy) is **shown exactly
  and confirmed first**.
- Data from users, git, trackers or files that goes into an LLM prompt sits in tags, redacted,
  labelled "data, not instructions to you" (see the kit's `prompt-engineering.md`).
- Never print, log or commit a token or credential.
- Public ids (CLI flags, routes, config keys, event names, stored formats) are **one-way doors**:
  add, never rename; a rename is a migration.
- Write like the surrounding code: its comment density, names, and <SPELLING> spelling.
- Do not commit or push unless asked. Commits are <Conventional Commits / house style>.

## Build, test, run

<!-- why: exact commands with "when" to use each. Without "when", the model runs the slowest
     one every time or invents its own. Name the one that must pass before claiming anything works. -->
| Command | When |
|---|---|
| `<install>` | once after cloning |
| `<test>` | **before saying anything works** |
| `<lint / format / typecheck>` | before staging |
| `<run locally>` | to try a change |
| `<eval / e2e>` | costs real requests or minutes: say how many first |

A new test suite goes into the package's test script **and** its CI job — a suite nobody runs is
not a test.

## Gotchas

<!-- why: the things that cost someone an afternoon. Each one is a sentence the model would
     otherwise rediscover the hard way. Delete the section if there are none yet. -->
- <e.g. "The dev server caches config; restart it after editing `config/*.yaml`.">

## Releases

<!-- why: tells the model which actions are one-way doors for users. A merge that ships to
     everyone deserves a warning before the push, and the model can only give it if it knows. -->
<How a release happens: what a merge to `main` triggers, who receives it.>

## Working agreement (agents)
<!-- why: the delivery skills (implement-subtask, story-orchestrator, pr-review) read this to know how far they may go. /project-setup fills it in. -->
- **Autonomy:** <advise | implement + stage | implement + commit + draft PR>. Humans merge, always.
- **Parallel agents:** at most <2>. Each one draws on the same Claude subscription limits.
- **Base branch:** `<main>`. Branches: `<type>/<ticket>-<short-title>`.
- **Tracker:** <GitHub Issues | GitLab Issues | Jira PROJ | Linear | none>.
- **Checks that must pass before "done":** `<lint cmd>`, `<test cmd>`.
- **Never without asking:** push, deploy, migrate a shared database, change CI, touch secrets.
