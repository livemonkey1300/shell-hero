---
name: pomo-done
description: Close out an interval — capture what actually happened, then break or continue
argument-hint: (optional) what you got done
---

The interval is over. Close it out honestly and get them into the break.

<what-happened>
$ARGUMENTS
</what-happened>

## Step 1 — Check the state first

```sh
~/.claude/bin/pomo status
```

Three cases, and they're handled differently:

**Still running with time left** — they're finishing early. Fine, that's a completed
interval, not a failure. Log it and move on.

**Overrun** — the timer fired and they kept going. Note the overrun in **one short line**
(`ran 22m over`) and nothing more. No comment on discipline, no advice about respecting the
timer. Just log it and get them into the break, which is now more needed, not less.

**Nothing running** — they may have already closed it. Show today's log and stop.

## Step 2 — Capture what actually happened

If `<what-happened>` is empty, ask **one** question: what actually got done?

Take their answer as given. **Do not evaluate it, reframe it as progress, or find a silver
lining in a bad interval.** "Got nowhere, wrong approach" is a legitimate and useful log
entry — arguably more useful than a good one, because it's the entry that tells them
something next week.

```sh
~/.claude/bin/pomo done "<what actually happened>"
```

## Step 3 — Did it hit the finish line?

The task string carries the finish line after `→`. Ask, in one line, whether it was met.

- **Met** → the task is done. Offer to `/park` the *next* piece if there is one, so it's
  captured rather than held.
- **Not met** → ★ **make the next interval's finish line smaller.** A finish line missed
  twice was the wrong size, not the wrong effort. Say that once, plainly, and adjust it —
  don't ask them to try harder.

## Step 4 — Push them into the break

The engine already says whether a long break is due. Relay it and stop.

```sh
~/.claude/bin/pomo break        # or: pomo break long
```

★ **The break is the part of this technique that earns its place here**, so don't let it
become optional. Not because rest improves the next interval — the evidence for that is
weaker than people think — but because it's a **forced boundary against a four-hour
disappearance**. Absorption doesn't choose what it attaches to; the timer is the only thing
in the loop that does.

Say it as one line, not a lecture: *"Long break — away from the screen."*

## Step 5 — After four intervals, one question

When the engine reports the cycle is complete, ask once:
**"Keep going, or is that the session?"**

Take the answer at face value. If they stop, suggest `park` for the handoff note while the
context is still loaded — that's the highest-value minute available and it's about to be
lost.

## Rules

- **No praise, no streak-counting, no "great work".** The log is an instrument; keep it
  clean. Gamification turns an honest record into one that flatters, and an inaccurate
  record is worse than none.
- Never suggest skipping the break to maintain momentum.
- Never suggest a fifth interval before asking.
