# shell-hero: instructions for Claude

This repo is a personal toolkit: a zsh config (`zsh/`, `install.sh`), DevOps guides (`guides/`),
and a Claude Code kit (`claude/`: skills, agents, templates, prompt-engineering guide).

## If the user asks to be set up

Phrases like "set me up", "install this", "install the skills", "read this project and install
everything", or "spawn an agentic workflow for my project" mean: **follow
[`claude/BOOTSTRAP.md`](claude/BOOTSTRAP.md) step by step.** Don't improvise an install, and don't
copy files by hand. The scripts do the copying and never overwrite without a backup.

## If the user is changing this repo

- **No secrets, employer names or internal URLs, ever.** This repo is public. Before any commit:
  `rg -i 'token|secret|password|ATATT|glpat-' zsh/ bin/ claude/`
- **New or changed skill or agent →** add it to a pack in `claude/install.sh` (`pack_items`), then
  run `claude/install.sh --check && claude/bin/kit-lint`. Descriptions ≤ 500 characters: they load
  into every session (`prompt-engineering.md` Part 10).
- **New shell alias or function →** give it a description comment (that's what feeds F1 and the
  cheatsheet), then run `docs/gen-cheatsheet.sh`.
- **Test shell changes in a throwaway home:**
  `HOME=$(mktemp -d) ./install.sh --no-packages --no-chsh`
- **Prompts follow [`claude/prompt-engineering.md`](claude/prompt-engineering.md):** a description
  that triggers, untrusted data kept apart from the task, the reply contract last.
- Canadian spelling. Don't commit or push unless asked.
