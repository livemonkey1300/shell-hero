---
name: pomo
description: Start a focused interval — picks ONE task, chooses the right interval length for the work, starts the timer
argument-hint: <the one task> [deep|classic|short|grind]
---

Start a Pomodoro interval. The timer engine is `~/.claude/bin/pomo` — **drive it, don't
reimplement it.** Your job is the three things a shell script can't do: enforce that it's
one task, pick the right interval length, and write down what "done" will look like.

<task>
$ARGUMENTS
</task>

## Step 1 — One task. Enforce this.

If `<task>` is empty, read `~/.claude/parked.md` and the current repo's `.PARKED.md` and
offer **at most three** candidates. Don't offer more — the point is to reduce the choice,
not stage it.

★ **If they've given you something that is actually two or more tasks, say so and make them
pick one.** "Fix the export script and update the dependency-bot config" is two. This is the one
rule worth being firm about — the single-task constraint is most of what the technique
actually provides, and a Pomodoro spent switching between three things is just 25 minutes.

## Step 2 — Pick the interval, don't default to 25

The preset should match **the reload cost of the work**, not habit:

| Preset | Interval | Use when |
|---|---|---|
| `deep` | 50/10 | Architecture, debugging a distributed system, anything where you hold a model in your head |
| `classic` | 25/5 | Bounded, well-defined work — a review, a known fix, config changes |
| `short` | 15/5 | **Starting** is the hard part. Lower the bar below the resistance. |
| `grind` | 90/20 | Long-form writing or review that's already loaded |

★ **Default to `deep` for anything architectural, not `classic`.** Resuming code costs
10–15 minutes of context rebuild for anyone — so a 25-minute block can spend half of itself
reloading. That ratio is bad for exactly the work most engineers do most. Say which you picked and
why, in one line.

If they named a preset, use it without comment.

## Step 3 — Name the finish line

Before starting the timer, get **one line on what "done" looks like** for this interval.
Not the whole task — what will be true in 50 minutes.

"MR !949 reviewed and comment posted" — good. "Work on !949" — not good, push back once.

This matters because an interval with no finish line ends in a judgement call about whether
to continue, and that judgement is exactly what's hard to make at minute 50.

## Step 4 — Start it

```sh
~/.claude/bin/pomo start "<task> → <finish line>" <preset>
```

Then confirm in **two lines maximum**: the task, and the wall-clock time it ends.
Nothing else. They're about to start; don't fill the screen.

## Step 5 — Get out of the way

Do not offer to help with the task. Do not summarise the plan. Do not wish them luck.

If they asked you to work on the task *with* them, then work on it — but say nothing
further about the timer until they run `/pomo-done`.

## Notes

- If a pomodoro is already running, say so with `pomo status` and ask whether to abort the
  current one (`pomo abort`) or leave it. Don't silently clobber it.
- If they get interrupted mid-interval, the right move is `pomo abort "<why>"` and then
  `/park` — an interrupted interval logged as *interrupted* is data; one logged as *done*
  is a lie to your future self, and the log is only worth having if it's honest.
