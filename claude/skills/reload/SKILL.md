---
name: reload
description: Rebuild the mental model after a context switch — where am I, what changed, what was I about to do
argument-hint: (optional) a repo path, or blank for the current directory
---

The user has context-switched back into this work and needs the mental model rebuilt for
them rather than reconstructed by them. That reconstruction is the expensive part and it
is pure overhead — do it *for* them, fast, and in a fixed shape they can skim.

<target>
$ARGUMENTS
</target>

If `<target>` is empty use the current directory.

## The rule

**Everything below is gathered, never asked.** If you end this command by asking them a
question about what they were doing, the command has failed at its one job. Run the
commands, read the state, present it.

Keep the whole thing under ~40 lines. This is a reload, not a report — if it's long enough
to need its own reload, it's too long.

## Gather

Run these yourself, quietly, in parallel where possible:

- `git branch --show-current`, `git log --oneline -8`, `git status --short`
- `git diff --stat` and `git diff --cached --stat`
- `git log --oneline origin/$(git branch --show-current)..HEAD 2>/dev/null` — unpushed
- Recently modified files: `find . -type f -newermt '2 days ago' -not -path './.git/*' -not -path '*/node_modules/*' | head -20`
- `~/.claude/parked.md` — entries whose `where` matches this repo/branch
- `~/.claude/decisions.md` — the most recent entries touching this work
- If there's a PR/MR for this branch: `gh pr view --json number,title,state` (GitHub) or
  `glab mr list --source-branch=<branch>` (GitLab)

## Present, in exactly this order

### ▸ Where you are
One line: repo, branch, and what that branch is *for* — infer it from the branch name and
recent commit messages. If the branch name carries a ticket ID, say the ticket ID.

### ▸ What you last did
The last 3–5 commits as a short narrative, not a raw log dump. "You moved the shared
templates into core, then fixed the config ref parsing" beats three SHAs. They wrote these
commits and still won't remember them.

### ▸ What's uncommitted
Staged vs unstaged vs untracked, grouped, with a one-line read on what the change *is*.
**If the working tree is dirty in a way that looks like an interrupted edit, say so
directly** — that's usually the actual thread they dropped, and it's the highest-value line
in this whole output.

### ▸ Parked items for this work
From `parked.md`, matching this repo/branch. Show the summary and the `next` field only.
If none, say "none" and move on.

### ▸ ★ The single next action
**One** action. Not a list. Pick the one that best continues what they were doing — bias
hard toward finishing the interrupted thing over starting the next thing.

If you genuinely cannot tell, say so and give **at most two** options with the one line
that distinguishes them. Never more than two.

---

Do not editorialise about how long it's been, how much is open, or what they should have
done. Just the state and the next action.
