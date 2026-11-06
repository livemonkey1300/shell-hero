---
name: what-now
description: You don't know what to work on — asks a few sharp questions and converges on one thing, sized to the state you're actually in. Use when asked "what should I work on", "what now", "I can't decide what to do next", or /what-now.
argument-hint: (optional) anything on your mind, or blank
---

The user doesn't know what to do next, or has too much in their head to choose. Your job
is to **converge to one action**, sized to the capacity they actually have right now.

<context>
$ARGUMENTS
</context>

## The shape of this command

Unlike `/reload` and `/loose-ends`, which deliberately never ask — **this one asks.** But
it asks **few, late, and well-informed**. Every question you ask costs something, and a
question you could have answered yourself by running a command is a question you must not
ask.

So: **gather first, ask second, commit third.**

---

## Step 1 — Gather silently. Do not ask anything yet.

Run these before you open your mouth. You need real options to offer, not blanks.

- `~/.claude/parked.md` — open loops, with their `next` fields
- `~/.claude/decisions.md` — anything `deferred until` whose trigger may have fired
- `~/.claude/weekly.md` — if it exists and is recent
- Dirty trees and unpushed commits across `<CHECKOUT_ROOTS>` (e.g. `~/src/*`)
- `.PARKED.md` in the current repo, if there is one
- `gh pr list --search 'review-requested:@me'` / `glab mr list --reviewer=@me` — anyone
  blocked on them
- Current branch and recent commits

Do not print this. It's your input, not their reading.

---

## Step 2 — Ask at most three questions. Use `AskUserQuestion`.

**Ask them one at a time where the answer changes the next question.** Offer concrete
options drawn from what you gathered — never generic ones.

### Question 1 — the time box (always ask)

How long have they actually got? The options should be real shapes, not durations in the
abstract:

- **Under 30 min** — only closable things
- **An hour or two** — one real piece of work
- **A long stretch** — something that needs the model loaded
- **Unknown / keeps getting interrupted** — treat as the first case

### Question 2 — capacity, not mood (always ask, and phrase it carefully)

This is the load-bearing question and the one nobody thinks to ask themselves.

Ask **what kind of work will actually land right now**, with options like:

- **Sharp** — can hold a system in my head
- **Functional but scattered** — can execute, can't architect
- **Low** — mechanical work only
- **Wired but unfocused** — energy without direction

**Frame it as a fact about this hour, never as a judgement.** The deficit is *consistency,
not capability* — same peak as anyone, unpredictable floor. Asking this is how you match
the task to the hour instead of matching it to a plan made on a different day. There is no
wrong answer and you should say nothing evaluative about whichever they pick.

### Question 3 — only if still ambiguous

Offer the two or three genuine candidates you found, as concrete options:
*"Finish the half-done X"*, *"Decide the deferred Y"*, *"Unblock Z's MR"*.

**Never more than four options.** More alternatives increase the felt difficulty rather
than reducing it — and if you can already tell, skip this question entirely and go to
step 3.

---

## Step 3 — Commit to one thing

### ▸ Do this
**One action.** The first literal command. Not a plan, not a list — the thing they type.

### ▸ Why this one
Two lines. Why it fits the time and capacity they named.

Match the work to the state they declared:
- **Sharp + long** → the architectural thing, or a one-way door that's been waiting
- **Functional but scattered** → execute something already decided. Not design work.
- **Low** → mechanical and closable. Rebases, cleanup, review comments, a stale worktree.
- **Wired but unfocused** → something physical and bounded with a visible end.
  ★ Motor activity rises *with* working-memory load and plausibly supports it — walking
  through a hard problem out loud is legitimate work, not avoidance.
- **Short box** → something that can be genuinely *finished*, never something started.

★ **If they said low capacity, do not offer the important-but-hard thing.** The whole
point of asking was to avoid that. Offering it anyway makes the question theatre and
teaches them the command doesn't listen.

### ▸ Parked the rest
List the other candidates in one line each, then offer to `/park` any that aren't already
captured. **Getting them out of their head is half the value of running this** — the
overwhelm is usually about holding the alternatives, not about the chosen task.

---

## Rules

- **Never end with a list of options.** The ranking *is* the work; doing it for them is the
  entire point of this command.
- **Never ask a question you could have answered with a command.** Check the tree, don't
  ask what they were working on.
- **Never ask more than three.** If you still can't tell after three, pick the smallest
  closable thing and say you're picking it.
- **No pep talk, no commentary on how much is open, no observation about how long since
  something was touched.** Just the pick and the reason.
- If they say a low-capacity day, that's information, not a confession. Respond to it the
  same way you'd respond to "I have 20 minutes."
