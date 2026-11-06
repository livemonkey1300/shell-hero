---
name: pomo-review
description: What the intervals actually bought you — reads the log and finds the pattern, over a day or a week
argument-hint: (optional) today | week | YYYY-MM-DD
---

Read the Pomodoro log and say something true about it.

<period>
$ARGUMENTS
</period>

```sh
~/.claude/bin/pomo log "${period:-today}"
```

For a week, read `~/.claude/pomo.log` directly and aggregate.

## What to report

### ▸ What landed
The completed intervals and what each produced. Group by task where several intervals went
to one thing — **"4 intervals on the export fix" is the useful unit**, not four separate rows.

### ▸ What got interrupted, and by what
The `abort` entries with their reasons. If a reason repeats across days, **name the
pattern** — recurring interruptions are usually structural (a standing meeting, a
notification channel, one person), and structural problems have structural fixes.

### ▸ Where the estimate was wrong
Compare actual minutes against the preset length. Two signals worth surfacing, and only if
they're actually present:

- **Consistent overrun on `classic`** → the work needed `deep`. The interval was too short
  for the reload cost, and switching preset is the fix.
- **Consistent abandonment in the first few minutes** → the task was too big to start.
  `short` exists for this, and so does making the finish line smaller.

### ▸ One thing to change
**One.** Not a list. The highest-signal adjustment for next week.

## Rules

- **This is not a productivity score.** Don't total up "focused hours" as an achievement,
  don't compare to previous periods, don't call anything good or bad. Report what happened.
- **A day with two completed intervals and six hours of incident response is a normal day**,
  not a failure. If the log looks thin, check whether that's what happened before implying
  anything about it.
- If the log is empty, say so in one line and stop. Don't fill the space.
- ★ Be careful with the conclusion "this is working." Across this whole field, apparent
  effects shrink by half or more once the assessment is blinded — and a self-assessed
  productivity method is the least blinded measurement there is. **What the log can honestly
  tell you is what you worked on and what interrupted you.** That's genuinely valuable and
  it's a different claim from "the technique helped."
