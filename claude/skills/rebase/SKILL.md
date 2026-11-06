---
name: rebase
description: Rebase the current branch with a co-pilot — previews conflicts before starting, resolves the mechanical ones itself, asks you about every judgement call, and verifies the result. FIDO-signing aware, never pushes. Use when asked to "rebase this branch", "rebase onto main", "help with these rebase conflicts", "squash my fixups", or /rebase.
argument-hint: "[onto-ref, default origin/main] [--continue] [--preview] [--fixups]"
---

Drive a `git rebase` of the current branch for the user. **Mechanical work is yours;
judgement calls are theirs.** The command fails if it asks about something it could
have settled from the code, and it fails worse if it silently picks a side in a
conflict where the two sides meant different things.

<args>
$ARGUMENTS
</args>

- First non-flag word in `<args>` = the ref to rebase onto. Default `origin/main` (change to your integration branch, e.g. `origin/develop`).
- `--continue` — a rebase is already in progress (yours or one the user started by
  hand). Skip to **Step 3**.
- `--preview` — run Steps 0–1 only, report, stop. Change nothing.
- `--fixups` — `git rebase --autosquash` so `fixup!`/`squash!` commits fold in.

## Hard rules

- **Never push.** Not even with a lease. At the end, print the push command for them.
- **Signing.** Check `git config --get commit.gpgsign`. If the user signs with a hardware
  (FIDO `-sk`) key: **a rebase re-signs every replayed commit, so each one waits for
  a physical touch.** A pause is expected, not a hang. Never pass `--no-gpg-sign`,
  `-c commit.gpgsign=false` or `--no-verify` to get round it, and never edit git config.
  Say in Step 1 how many touches to expect.
- **No interactive flags** (`-i` is unsupported here). Use `GIT_EDITOR=true` for
  `--continue`, and `--autosquash` without `-i` for fixups (git ≥ 2.44 allows it).
- **Never `git rebase --abort`, `--skip`, or `reset --hard` without asking.** `--skip`
  drops a commit — that is a one-way door within the rebase.
- **Ours/theirs are inverted during a rebase.** `--ours` = the base you're rebasing
  onto, `--theirs` = the user's commit being replayed. **Never use the words "ours" or
  "theirs" to the user.** Say "main's version" (or the onto-ref's name) and "your
  commit's version".
- **No cross-branch cherry-picks** as a way to "fix" a conflict. Other branches are
  evidence only.
- Untracked files are not your business. Leave them alone, don't stash them.

## Step 0 — Preflight (gathered, never asked)

Run in parallel:

- `git rev-parse --git-path rebase-merge` / `rebase-apply` — is a rebase in progress? If
  so and `--continue` wasn't passed, say so and go to Step 3.
- `git branch --show-current`, `git status --short`
- `git config --get rerere.enabled` — if on, recorded resolutions will replay. They land
  unstaged; you still review each before `git add`.

**Dirty tracked files** (staged or unstaged) → this is the one preflight question. Ask
with `AskUserQuestion`: *stash them for the rebase (recommended, `git stash push -m
"rebase-autostash <branch>"`, popped at the end)* / *stop so I can commit them first*.

**Shared branch check:** `git log --format='%an' <onto>..HEAD | sort -u` — if anyone
other than the user authored commits on this branch, **flag it as a one-way door**
(rewriting a branch someone else has) and ask before continuing.

## Step 1 — Preview (nothing changes yet)

```bash
git fetch --prune origin
BASE=$(git merge-base HEAD <onto>)
git log --oneline --reverse <onto>..HEAD          # your commits to replay
git log --oneline <onto> ^HEAD | wc -l            # how far behind
git merge-tree --write-tree --name-only --messages <onto> HEAD   # predicted conflicts
```

`merge-tree` predicts the **end-state** conflicts of the whole branch. Per-commit
replays can conflict in more places (an early commit fights a file a later commit
fixes) — say so if the series is long, don't claim the prediction is exact.

For each predicted conflict file, one line on **why**: `git log --oneline $BASE..<onto>
-- <file>` (what upstream did to it) against `git log --oneline <onto>..HEAD -- <file>`
(what the user did). Modify/delete conflicts get called out by name — they always need
a decision.

**Create the safety ref before touching anything:**
`git branch -f backup/<branch>-pre-rebase HEAD` — and tell the user its name. Undo is
`git reset --keep backup/<branch>-pre-rebase`.

Report as:

```
▸ Rebasing <branch> (N commits) onto <onto> (M commits behind) — expect N key touches
▸ Predicted conflicts: <count>
    <file> — upstream: <what>; yours: <what>
▸ Backup: backup/<branch>-pre-rebase
```

If `--preview`, stop here. Otherwise, if zero predicted conflicts, **proceed without
asking**. If there are predicted conflicts, proceed too — the questions come when each
one actually arises, with the real hunks in front of you.

## Step 2 — Start

```bash
git rebase [--autosquash] <onto>
```

Clean finish → Step 4. Stops on conflict → Step 3.

## Step 3 — Each stop

Identify the commit being replayed: `git show --stat REBASE_HEAD` and its message. Then
`git diff --name-only --diff-filter=U` for the conflicted files.

For **each** conflicted file, read the conflict hunks, read what upstream intended
(`git log -p $BASE..<onto> -- <file>`, scoped to the hunk) and what the user's commit
intended (`git show REBASE_HEAD -- <file>`). Then classify:

### Resolve yourself — say what you did, one line each

- **Both sides made independent, non-overlapping edits** that git couldn't line up
  (adjacent lines, reordered imports, both appended to a list). Keep both.
- **Identical intent** — both sides made the same change, differently formatted.
- **Lockfiles and generated files** (`uv.lock`, `package-lock.json`, `pnpm-lock.yaml`,
  `go.sum`, generated OpenAPI clients). Never hand-merge. Take the base's version, then
  regenerate with the project's own task runner (`make`, `npm run`, `just`…) so
  the user's dependency change is re-applied on top.
- **Upstream renamed/moved something the user's commit also touched** and the move is
  unambiguous — apply the user's edit at the new location.
- **rerere replayed a resolution** — check it still makes sense against the new base,
  then accept.

### Ask the user — `AskUserQuestion`

Anything where picking a side changes behaviour:

- Both sides changed the **same logic** with different intent (a value, a condition, a
  config key, a version pin).
- **Modify/delete**: one side deleted a file the other edited. Common on a branch that
  removes a layout — ask whether the edit needs porting somewhere else or dies with the
  file.
- A resolution that would need **new code** neither side wrote.
- Upstream changed something the user's commit **depends on** without textually
  conflicting (a renamed function the commit calls, a changed signature) — this one
  you catch by reading, not from markers. Flag it even though git didn't.

Question shape — **one decision per question**, up to 4 per `AskUserQuestion` call,
batched per stop:

- `question`: `<file>:<line> — <one-line description of what the two sides disagree on>`
- Options, recommended first with "(Recommended)" and the reason in `description`:
  - **Keep main's version** — what that means behaviourally
  - **Keep your commit's version** — what that means behaviourally
  - **Combine** — only if a sensible merge exists; put the exact resolved code in
    `preview`
- Use `preview` on every option to show the resulting code, so they compare outcomes,
  not markers.

Give the recommendation from evidence (the upstream commit message, the ticket in the
branch name, what other code now expects) — and say which category it is:
**read it in the code** (`file:line`) vs **inferred**.

### After each stop

1. Apply the resolutions. `grep -n '^<<<<<<<\|^=======$\|^>>>>>>>' <files>` must be
   empty.
2. Cheap sanity check on touched files only: `python -m py_compile`, `gofmt -l`,
   `tsc --noEmit` on the project, `yq` on YAML — whichever applies. Not the full suite.
3. `git add <files>` (explicit paths, never `-A`).
4. `GIT_EDITOR=true git rebase --continue`. Expect a key touch.
5. If the commit is now empty (upstream already contains it), **ask** before `--skip`.

Loop until done.

## Step 4 — Verify and report

```bash
git range-diff <onto> backup/<branch>-pre-rebase HEAD
git log --format='%h %G? %s' <onto>..HEAD        # G/U = signed, N = unsigned
```

`range-diff` shows which of the user's commits changed **in content** during the
rebase, not just in base. Any commit marked `!` that you didn't resolve a conflict in
is suspicious — look at it.

Then run lint for the projects the branch touches (through the repo's own task runner,
derived from the changed paths). Run tests only if a resolution changed logic and the suite is
fast; otherwise list the command under the ask.

Pop the stash if Step 0 made one. If the pop conflicts, stop and say so.

Report, in this order:

```
▸ Rebased <branch> onto <onto> — N commits, all signed ✔ / ✘
▸ Resolved by me: <file> — <one line>        (repeat)
▸ Decided by you: <file> — <choice>          (repeat)
▸ Changed in content (range-diff): <commits> — expected / ⚠ look at <sha>
▸ Lint: <verified result per project>
▸ Backup: backup/<branch>-pre-rebase  (git branch -D it once you're happy)

Needed from you:
  - push when ready: git push --force-with-lease --force-if-includes
  - <anything else, or "nothing needed">

Parked:
  - <anything noticed that isn't this rebase>
```

Distinguish **verified** (ran it) from **inferred** in every line that makes a claim.
