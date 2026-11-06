<!--
  The efficient agentic coding standard. Copy to .claude/rules/agentic-work.md (no `paths:`, so it
  loads in every session) in any repo where Claude, its subagents, or an agent company (Paperclip
  and the like) touch code. Reasons and examples: claude/prompt-engineering.md Part 10 (§41–§50).
  Keep it short: this file is paid for in every session.
-->

# Agentic work: spend tokens on the change, not around it

Every agent that touches code here follows these rules. Each one exists because the opposite
burns usage limits without improving the result.

**Scope**
- One task per run, with an owner. Don't widen it; name anything else under "parked".
- Never two agents on the same files at once. Parallel only when the work truly splits.

**Reading**
- Search before reading: `rg -n`, `git grep`, `git log -S`, LSP or a code-graph tool. Then read the
  lines that matter (offset/limit), not the whole file.
- Never re-read a file that is already in your context and hasn't changed.
- Skip generated, vendored, minified and lock files, `node_modules/`, `dist/`, build output.

**Tool output**
- Cap it at the source: `| head -50`, `| tail -30`, `--quiet`, `git diff --stat` before
  `git diff -- <path>`, `grep -m`. Logs: filter for the error, then widen.
- Tests: the narrowest check first (one file or one test, quiet reporter, stop at first failure),
  the full suite **once**, at the end.

**Fixing**
- Two attempts at the same failure, each with a different hypothesis written down first. Then stop
  and report what you learned (blocked or handoff). Flailing is the most expensive thing an agent does.
- Edit the lines that change; never rewrite a whole file to change a few.
- Independent tool calls go out together, in one message.

**Subagents and model choice**
- Spawn one only for independent work or a wide read-only search whose conclusion is all you need.
- Brief: goal, files in scope, what's already ruled out, and the hand-back shape (≤ 300 words,
  verdict first, `file:line`, verified vs inferred, no file dumps).
- Cheapest model and effort that can do the job: search and mechanical edits → lower effort or a
  smaller model; implementation → the default; architecture, security and final review → the
  strongest. Higher effort only for a well-specified hard problem.

**Verifying**
- Verify once, at the right level, and paste the command and its result. Reviewers run the checks
  themselves once; nobody re-runs what was already verified on the same commit.

**Context**
- Long session (auto-compaction fired, ~40 tool calls, or a phase change): write a `/handoff` and
  stop. A fresh session with a good note beats a full one.
- Don't edit `CLAUDE.md`, rules or skills mid-session: always-loaded text that stays stable is
  cached; text that changes is paid in full again.
