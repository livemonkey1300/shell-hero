---
name: fast-commit
description: Fast commit — auto-generate a commit message and commit, FIDO-key aware
---

Create a git commit quickly, writing the commit message yourself. Follow these steps:

1. Run `git status` and `git diff` (staged and unstaged) in parallel, plus `git log --oneline -10` to
   match this repo's commit message style.
2. Stage the relevant changed files (prefer explicit paths over `git add -A`/`git add .`; never stage
   files that look like secrets or credentials).
3. Draft a concise commit message (1-2 sentences, focused on *why*) that matches the repo's existing
   style and follows any spelling rule the repo's `CLAUDE.md` or `.claude/rules/` sets.
4. Run `git commit -m "<message>"`.
   - If the user signs commits with a hardware security key (SSH-format signing, `commit.gpgsign=true`,
     `user.signingkey` pointing at an `_sk` key): the commit command will likely hang briefly waiting
     for a physical touch/tap on the key — this is expected, not an error. Let it run; do not
     interrupt, retry, or treat a pause as a failure.
   - Never pass `--no-verify`, `--no-gpg-sign`, `-c commit.gpgsign=false`, or otherwise bypass signing
     or hooks to work around a pending touch — wait for it instead.
5. Do NOT modify any git configuration as part of this command — no changes to `git config`
   (global, local, or `.gitlab` config), signing settings, remotes, or hooks. If a commit fails for a
   config-related reason, report it and ask the user rather than changing config yourself.
6. Do not push and do not amend an existing commit — always create a new commit.
7. After the commit succeeds, run `git status` to confirm, and report the commit hash and message.

If there is nothing staged or changed, say so and stop — do not create an empty commit.
