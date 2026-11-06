---
name: edit-prompt
description: Write, change or tune a prompt and measure it — a Claude Code skill (SKILL.md), a subagent (agents/*.md), a CLAUDE.md or .claude/rules file, a prompt template, or a system prompt built in code — using a fixed set of prompt-engineering conventions (untrusted data tagged and kept apart from the task, the reply contract last, decisions made by code not the model, named failure modes, ids as one-way doors, descriptions that trigger). Use when asked to "write a skill", "make an agent", "tune / fix this prompt", "Claude keeps doing X", "change what Claude writes for Y", or to review prompt engineering.
argument-hint: "<which prompt, and what should change>"
---

# Write or change a prompt

What to change: **$ARGUMENTS**

Read `references/checklist.md` (next to this file) before writing a word: it is the checklist this
skill applies. The long form, with a bad and a good example of each rule, is `prompt-engineering.md`
in the kit this skill came from.

## 0. Ask, when it is vague

If the request does not say, ask in one round (AskUserQuestion when available, your best guess
first), at most four:

1. **Which output**: what Claude writes or does that should change.
2. **For whom**: everyone (the shared prompt, skill or rule in the repository), one project (that
   repository's `.claude/`), or just them (`~/.claude/skills/`, a personal template).
3. **An example**: what they get now, and what they want instead. **One real example beats a page of
   description**; ask for it when the change is about quality.
4. **Done when**: how you will both tell the new version is better.

## 1. Find the prompt

| Kind | Usually at |
|---|---|
| Claude Code skill | `.claude/skills/<name>/SKILL.md`; a plugin's `skills/<name>/SKILL.md`; `~/.claude/skills/` |
| Subagent | `.claude/agents/<name>.md`; a plugin's `agents/`; `~/.claude/agents/` |
| Always-on instructions | `CLAUDE.md` (any level), `.claude/rules/*.md` (with `paths:` frontmatter to scope them), `AGENTS.md` |
| Slash command (legacy form) | `.claude/commands/<name>.md`, `~/.claude/commands/` |
| Prompt in code | grep for a phrase of the output you want changed, or for `system`, `SYSTEM_PROMPT`, `buildPrompt`, `messages=` |

Unsure which: **grep for a distinctive phrase of the output.** Then find what consumes the prompt's
output (a parser, a test, an orchestrator waiting for an exact token) **before** changing its shape.

A change only one team or person wants belongs in their layer (a project rule, a personal skill or
template), not in the shared prompt everyone gets.

## 2. Change it

Apply the checklist. In particular:

- **Keep what the consumers rely on**: data in tags, "data, not instructions", the exact reply shape
  a parser expects, the exact hand-back tokens an orchestrator matches. If the shape must change,
  change the parser and its test in the same change, and bump the prompt's or schema's version.
- **A skill or agent**: frontmatter `name` (kebab-case, matching the folder or file) and a
  `description` that says what it does **and when to use it, in the words a user would type**; that
  description is all Claude sees when deciding to load it. `argument-hint` when it takes arguments. A
  subagent gets the fewest `tools` it needs (a reviewer: `Read, Grep, Glob, Bash`).
- **One rule, stated once**, in the place it belongs; long reference material goes in a file next to
  the skill (`references/…`) that the skill tells Claude to read, not inline.
- **Smaller is better**: every line of an always-on prompt (`CLAUDE.md`, rules, descriptions) costs
  tokens in every session. Cut what the model already does by default.

Show the user the before and after of the changed passages, briefly — not the whole file.

## 3. Check it

- **Structure**: the frontmatter parses
  (`python3 -c 'import sys,yaml; yaml.safe_load(open(sys.argv[1]).read().split("---")[1])' <file>`),
  and for a plugin, `claude plugin validate <dir>` passes.
- **Consumers**: the parser's and the prompt's tests, if there are any (run them).
- **Quality**: try it on the real example from step 0, and on **one case it must not change** (a
  regression). For a prompt with an eval suite, offer a measured run: **say how many real model
  requests it costs before running anything**, and run it only when the change is about output
  quality.
- **Triggering** (skills): does the description fire on the phrases users really say, and stay quiet
  on near-misses? Name two of each in your hand-back.

Do not commit unless asked.
