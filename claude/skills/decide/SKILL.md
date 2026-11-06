---
name: decide
description: Force a stuck decision to a close — classify it reversible or not, size the ceremony to match, log it
argument-hint: <the decision you're stuck on>
---

The user is stuck on a decision, or about to make one fast that deserves more care. Both
are failure modes and **the same person does both** — often on the same day. The job of
this command is to work out which one is happening and correct for it.

<decision>
$ARGUMENTS
</decision>

If `<decision>` is empty, ask what the decision is — once — then stop.

## Step 1 — Classify it. Before anything else.

Ask yourself, not them:

**Is this a one-way door?** If it's wrong, what does it cost to undo — an hour, a day, a
data migration, a customer conversation?

- **Two-way door** (cheap to reverse): say so **in the first line**, recommend the option
  you'd pick, and — this is the part that matters — **make them close it.** Do not analyse
  it further.

  ★ The usual advice ("reversible decisions can be made quickly, mistakes are cheap") is
  only half right and the missing half is the expensive one. **Leaving a door ajar is not
  free.** Bullens et al. 2011: people in a *reversible* decision condition scored measurably
  **lower on a working-memory task**, and that reduced capacity mediated increased regret.
  Gilbert & Ebert 2002: the post-decision rationalisation that makes you content with a
  choice **only engages once the decision is closed** — people who could change their minds
  liked their outcome *less*, while 84% predicted the opposite.

  So an undecided decision is a background process eating capacity. The rule is not "decide
  fast" but **"decide, then write the trigger that would reopen it, then treat it as
  closed."** The trigger is what lets the mind stop holding the option.
- **One-way door** (expensive or impossible to reverse): say so, and then it earns the
  full treatment below. This is where the care belongs — and where it usually isn't spent,
  because these are the ones that feel scary and get deferred instead.

Say which it is, in the first line, before any other output. Getting this backwards —
agonising over the cheap one, rushing the expensive one — is the actual thing this command
exists to prevent.

## Step 2 — For a one-way door only

### The decision
Restate it in one sentence. If you can't, it isn't one decision — split it and say so.

### Options
At most **three**. For each: one line for it, one line against it. **No tables, no scoring
matrices.** Scoring matrices feel rigorous and mostly launder a preference into arithmetic.

### What would change my mind
The single most important section. For your recommendation, name the **specific, checkable
fact** that would flip it. If no such fact exists, the decision isn't evidence-bound and
you should say that plainly — it's a values call, and values calls don't get better with
more analysis.

### The recommendation
One option. A reason. A confidence level you actually mean.

### The cost of waiting
What does another week of not deciding cost? Sometimes genuinely nothing — say so, it's a
legitimate answer and it takes the pressure off. Often it's compounding, and naming that is
what unsticks it.

## Step 3 — Log it

Append to `~/.claude/decisions.md`:

```markdown
## <decision, one line>
- **date**: <ISO date>
- **door**: one-way | two-way
- **chose**: <what, or `deferred until <trigger>` — a trigger, never a date>
- **because**: <one line>
- **would change my mind**: <the checkable fact>
- **reopen trigger**: <REQUIRED on a two-way door. A condition, not a calendar date —
  "when the hosting platform is confirmed", not "in 2 weeks". Calendar dates get missed;
  conditions get noticed. This field is what closes the door.>
- **prediction**: <something falsifiable, with a date>
- **scored on**: <blank. Fill in later — see below.>
```

Then confirm in one line.

## ★ The `scored on` field is the active ingredient

Writing a decision down does nothing on its own — there is **no research** showing decision
journals improve decisions. What *is* evidenced is outcome-scored calibration practice:
Chang et al. 2016 found under an hour of structured training plus repeated **scored**
feedback improved Brier scores **6–11%** across four years of forecasting tournaments.

So an unscored log is a diary. Periodically surface the unscored ones:

```sh
rg -B2 'scored on:\s*$' ~/.claude/decisions.md
```

## Why the log matters more than it looks

It defeats hindsight bias. In six weeks the reasoning is gone and only the outcome remains,
which makes good decisions with bad outcomes feel like mistakes and teaches exactly the
wrong lesson. **The log preserves what you knew at the time** — that's the only thing that
makes a past decision reviewable at all.

It also means a decision genuinely gets made *once*. Re-litigating settled decisions is a
large and invisible tax, and "it's in the log, with the reason" ends it.
