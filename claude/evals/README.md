# Skill evals

A skill is a prompt, and a prompt change that fixes one complaint usually breaks something else
(`prompt-engineering.md` §38). These evals measure a skill by **what it does**, not what it says:
which commands fire, which gates stop it, what it refuses to create. Each skill that has them keeps
them next to itself, in `skills/<name>/evals/evals.json`.

| Skill | Cases |
|---|---|
| `open-pr` | `skills/open-pr/evals/evals.json` |
| `pr-review` | `skills/pr-review/evals/evals.json` |
| `implement-subtask` | `skills/implement-subtask/evals/evals.json` |
| `game-start` | `skills/game-start/evals/evals.json` |

## The format

```json
{
  "skill": "open-pr",
  "version": 1,
  "notes": "How to run these, and anything a runner must know.",
  "evals": [
    {
      "name": "nothing-to-open",
      "kind": "negative",
      "setup": "Scratch repo; branch feat/x is even with origin/main (0 commits ahead).",
      "prompt": "Open a PR for this branch.",
      "expected": [
        "Runs git log/rev-list against the base and finds 0 commits ahead.",
        "Stops with a message that there is nothing to open a PR for."
      ],
      "must_not": [
        "Runs git push, gh pr create or glab mr create.",
        "Creates a ticket."
      ]
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `name` | Stable kebab-case id. **Ids are one-way doors** (§19): reword the case, never rename it, or you lose its history. |
| `kind` | `positive` (the skill should act) or `negative` (the right outcome is doing nothing, or stopping). |
| `setup` | The repo / remote / tracker state the case needs, in words a person can build in a few commands. |
| `prompt` | What the user types first. |
| `followups` | Optional. The user's later turns, in order (typically "yes" at a gate), for cases that must get past a human gate. Absent → one turn. |
| `expected` | Observable behaviours that must happen, each checkable from the transcript alone. |
| `must_not` | Observable behaviours that must not happen. One hit fails the case. |

### Rules for writing a case

- **Observable, never wording.** "Runs `gh pr list --head <branch>` before `gh pr create`" is
  gradeable. "Explains clearly that a PR exists" is not, and "says 'A PR already exists'" breaks on
  the first rephrasing. Assert on tool calls, their arguments, their order, and where the run stops.
- **One behaviour per line.** A line with "and" in it is two expectations; when it half-passes you
  cannot score it.
- **Every suite has a negative case.** "Nothing to do → create nothing" (§16) is the case that
  catches a skill that always produces something. At least one per suite; two is better.
- **Every gate has a case that stops at it.** A gate that is never exercised is a gate you will
  delete by accident in the next edit.
- **4–6 cases per skill.** Enough to cover the main path, each gate, and the negative case; few
  enough that running the suite is something you actually do.
- **Name the case after the behaviour**, not the bug that prompted it (`duplicate-pr-guard`, not
  `fix-for-tuesday`).

## How to run one, by hand, with Claude Code

There is no runner in this kit for `evals.json`; you run each case as a one-shot `claude -p` session
against a throwaway repo and grade the transcript. That is deliberately low-tech: it works on any
machine with Claude Code and `jq`.

**Say the cost first** (§39). Each case is one full agent session, several model requests. A
six-case suite run against the new and the old version is twelve sessions.

### 1. Build the scratch repo

```sh
EVAL=$(mktemp -d)                         # never inside a real checkout
cd "$EVAL" && git init -q -b main && git commit -q --allow-empty -m init
git init -q --bare "$EVAL.remote.git" && git remote add origin "$EVAL.remote.git" && git push -q -u origin main
# then build the case's `setup`: branches, commits, a dirty tree…
```

A local bare remote is enough for every case that should **stop before the network** (nothing to
open, dirty tree, a gate). Cases that must reach `gh`/`glab` need a throwaway repository on the code
host; delete it after.

### 2. Put the version under test where Claude Code finds it

```sh
mkdir -p .claude/skills/open-pr
cp ~/path/to/kit/claude/skills/open-pr/SKILL.md .claude/skills/open-pr/
```

A project-level `.claude/skills/` copy is picked up in that directory. If you also have the skill
installed in `~/.claude/skills/`, **check which copy loads** (a different name for the copy under
test avoids the question).

**Baseline**: the previous version, from git, in a second scratch repo built the same way:

```sh
git -C ~/path/to/kit show HEAD~1:claude/skills/open-pr/SKILL.md > .claude/skills/open-pr/SKILL.md
```

### 3. Run the case

```sh
claude -p "Open a PR for this branch." \
  --output-format stream-json --verbose \
  --no-session-persistence \
  > run.jsonl                             # single-turn case
```

- `--output-format stream-json` needs `--verbose` in print mode; without it the CLI refuses to start
  (**verified**, Claude Code 2.1.319).
- **Cases with `followups`**: run without `--no-session-persistence`, then answer each follow-up with
  `claude -p --continue "<followup>" --output-format stream-json --verbose >> run.jsonl` from the
  same directory (`-c/--continue` resumes the most recent conversation there). **Not verified**
  end to end here; if a resumed run loses the skill's context, run that case interactively and grade
  from the session instead.
- In `-p` mode nobody answers a question or a permission prompt. **A skill that stops at a human
  gate ends the run with the question as its last message** — which is exactly what a gate case
  checks.
- Narrow what may run with `--allowedTools` (e.g. `--allowedTools "Bash(git *)"`) so a case that
  should stop at a gate cannot push even if the skill regresses. A denied call still shows up in the
  transcript, which is what you grade.
- `--max-budget-usd <n>` stops a runaway case, but it is **checked after a request, not before**: a
  0.05 budget ended at 0.12 on a single-turn run (**verified**, 2.1.319). Treat it as a tripwire, not
  a ceiling.
- `--permission-mode`, `--model` and the rest: `claude --help` on your version is the reference.
  Flags change between releases; anything above not marked verified, check before you rely on it.

### 4. Grade it

List the tool calls, in order:

```sh
jq -r 'select(.type=="assistant") | .message.content[]?
       | select(.type=="tool_use")
       | "\(.name)\t\(.input.command // .input.file_path // (.input|tostring))"' run.jsonl
```

and the final message and cost:

```sh
jq -r 'select(.type=="result") | "\(.subtype) cost=\(.total_cost_usd) turns=\(.num_turns)\n\(.result // "")"' run.jsonl
```

(Both **verified** against a 2.1.319 transcript. The stream format is not a stable API; if a field
is missing on your version, look at one line of `run.jsonl` and adjust.)

Tick each `expected` line pass/fail and each `must_not` line hit/miss, by reading. A case passes when
every `expected` passes and no `must_not` hits. Write the result down per case, with the version
(git sha of the skill) it was run against.

Grading with a model is fine for the lines that need judgement ("the ticket draft is derived from the
diff"): give a second `claude -p` the transcript **as tagged data, not instructions** (§1–§3) and one
expectation at a time, and ask for pass/fail with the line of the transcript that proves it. Tool-call
lines are graded by `jq` and eye, not by a model.

### 5. Compare against the baseline

| Case | Old | New |
|---|---|---|
| nothing-to-open | pass | pass |
| duplicate-pr-guard | **fail** | pass |

**A change ships when it fixes the case it was made for and regresses none.** A case that fails on
both versions is a known gap; note it, don't hide it.

### 6. Clean up

Close any PR/MR, delete the remote branches, delete any ticket the run created, `rm -rf "$EVAL"
"$EVAL.remote.git"`. A case that touched a real tracker leaves residue other people see.

## Claude Code's built-in plugin evals

Recent Claude Code versions ship `claude plugin eval` (present in 2.1.319's `--help`): it runs a
plugin's eval suite in its own case format (`case.yaml`, or `prompt.md` plus `graders/*.md`), adds a
no-plugin baseline arm, and reports scores. **Not used or verified here**: this kit's `evals.json`
files are the hand-run format above. If you package the kit as a plugin, the cases translate
one-to-one — `prompt` → the case prompt, each `expected`/`must_not` line → a grader.
