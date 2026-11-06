---
name: loose-ends
description: Everything currently open across parked items, dirty repos, unpushed commits and MRs — then exactly one thing to do next
argument-hint: (optional) "close" to also help clear the easy ones
---

Show the user everything that is currently open, in one place, and then **narrow it to one
action**. Both halves matter. A list of twenty open things without a pick at the end makes
the situation worse, not better — it's the same overwhelm with better formatting.

<mode>
$ARGUMENTS
</mode>

## Gather

Run these yourself. Don't ask the user what's open — the entire point is that they can't
hold it.

- `~/.claude/parked.md` — all entries
- Dirty working trees: check `<CHECKOUT_ROOTS>` (e.g. `~/src/*`, `~/work/*`) and any other
  checkouts you can find, with `git status --short` in each
- Unpushed commits per repo: `git log --oneline @{u}.. 2>/dev/null`
- Stashes: `git stash list`
- Open PRs/MRs authored by them: `gh pr list --author @me` or `glab mr list --author=@me`
- PRs/MRs awaiting **their** review: `gh pr list --search 'review-requested:@me'` or
  `glab mr list --reviewer=@me`
- Worktrees that still exist: `git worktree list` per repo
- `~/.claude/decisions.md` entries with `chose: deferred` whose revisit condition may now
  be met

## Present

### ▸ Needs a decision, not work
Deferred decisions whose trigger condition has now been met. **Put this first** — these are
the cheapest items to clear and the most likely to be silently blocking something else. A
decision that could have been made three weeks ago is holding up whatever depends on it,
invisibly.

### ▸ Blocking someone else
MRs awaiting their review, and anything parked with a non-empty `blocks:`. **Second,
because other people's time is involved and this is the category most likely to be
invisible from the inside.**

### ▸ Interrupted work
Dirty trees and unpushed commits. For each, one line on what the change appears to be.
Flag anything untouched for **more than a week** — that's usually either done-and-forgotten
or abandoned, and both want a decision rather than continued existence.

### ▸ Parked
Grouped by repo. Summary + `next` only. Not the full context field.

### ▸ Stale
Anything parked more than 30 days with no movement. Say it plainly:
**"these have been open a month — delete or do?"** Offer to delete them in one batch.
Deleting a parked item is a legitimate, healthy outcome and should feel like one, not like
failure.

### ▸ ★ Do this one
**One item.** With the first concrete command or action.

Choose by, in order: (1) unblocks another person, (2) a decision that's blocking work,
(3) finishes something already started, (4) smallest thing that can be fully closed.

Never present a ranked list of five. The ranking is the work, and doing it *for* them is
the entire value of this command.

## If `<mode>` is "close"

After the summary, offer to clear the mechanical ones **in a single batch, with one
confirmation** — delete stale parked items, drop dead worktrees, push commits that are
plainly ready.

Batch them into one prompt. Do not walk through them one at a time asking about each;
twelve small confirmations is more depleting than one large one, and it's the reason the
queue got this long.

## Tone

State the numbers, no commentary on them. Don't say "wow, 14 open items". Don't
congratulate. Don't imply anything about discipline. It's a status readout, and the useful
response to it is the one action at the bottom.
