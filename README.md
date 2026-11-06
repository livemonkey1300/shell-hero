# shell-hero

My terminal setup and everything I learned building it, in one repo:

- **a zsh config** with about 290 documented shortcuts. Press <kbd>F1</kbd> to search them.
- **a one-command installer** for Linux, macOS and WSL.
- **a tutorial** on how the config works, so you can change it.
- **16 DevOps guides**: Git, Docker, Kubernetes, Helm, CI, Linux security, Bazel, Google Cloud.
- **a reusable Claude Code kit**: CLAUDE.md templates, prompt-engineering guide, skills and agents.

Everything is generic. No employer code, names or secrets; machine-specific things go in `~/.zshrc.local`.

## Quick start

```sh
git clone <this-repo> ~/perso/shell-hero
cd ~/perso/shell-hero && ./install.sh
exec zsh
```

Then press <kbd>F1</kbd>. Per-OS details, flags and troubleshooting: **[docs/INSTALL.md](docs/INSTALL.md)**.

## What's where

| Path | What | Read when |
|---|---|---|
| [`docs/INSTALL.md`](docs/INSTALL.md) | install on Fedora, Debian/Ubuntu, Arch, openSUSE, macOS, WSL | setting up a machine |
| [`docs/TUTORIAL.md`](docs/TUTORIAL.md) | how the config works: load order, plugins, aliases vs functions, fzf pickers, widgets, hooks, traps we hit | **first, once** (about 45 min) |
| [`docs/CHEATSHEET.md`](docs/CHEATSHEET.md) | every shortcut, by file (generated from the config) | looking something up away from a shell |
| [`zsh/`](zsh/) | the config itself | customising |
| [`bin/`](bin/) | terminal viewers: `mdview` (markdown), `imgview` (images), `docview` (Word), `vpreview`, `pomo` (timer) | — |
| [`guides/`](guides/README.md) | the learning library, with a suggested reading order | learning a tool |
| [`claude/`](claude/README.md) | Claude Code kit: CLAUDE.md templates, prompt engineering, skills, agents | starting a project with Claude |
| [`install.sh`](install.sh) | the installer | — |

### The zsh config

| File | Contains |
|---|---|
| `zsh/zshrc` | load order, oh-my-zsh and plugins, history, keys, editor; sources everything else |
| `zsh/god.zsh` | daily driver: `ls` family (eza), navigation (`up`, `cdg`, `cdf`, `z`), find (`ff`, `fif`, `fkill`), fuzzy git (`fgb`, `fgl`), safe file ops (`del`, `bak`), clipboard, system (`ports`, `port`, `upd`), viewers (`v`, `mdv`, `img`, `pdfv`, `docv`), lint and security (`shlint`, `dlint`, `vulns`, `sbom`), keys |
| `zsh/zhelp.zsh` | <kbd>F1</kbd> / `zhelp`: searchable index built live from the files above |
| `zsh/docker.zsh` | `d*` Docker and Compose shortcuts, cleanup for wedged containers and networks |
| `zsh/k8s.zsh` | `k*` kubectl shortcuts, `kbash`, `klf`, `ksec`, `kgall`, `kpf`, `knet`, creation wizards (`knew`) |
| `zsh/cloud.zsh` | `g*` Google Cloud across every project (`gssh`, `gkec`, `gtun`, `gin`…) and `tf*` Terraform |
| `zsh/bazel.zsh` | `b*` Bazel shortcuts and query helpers (`bwho`, `bwhy`, `bout`) |
| `zsh/dev.zsh` | `mr`/`mt` for moon, `dotr` (Graphviz), `fe` |
| `zsh/focus.zsh` | working memory: `n` (capture a note), `nf` (find notes), `park` (handoff note per repo), `ctx` (tmux per concern), `wip`, `p`/`pd` (pomodoro) |

Each topic module **turns itself off** when its tool isn't installed, so the same config works on a laptop with only git and on a full DevOps workstation.

## The ten shortcuts to learn first

| Type | Get |
|---|---|
| <kbd>F1</kbd> | search every shortcut; Enter puts it on your prompt |
| <kbd>Ctrl-R</kbd> | fuzzy history |
| `z part-of-dir` | jump to a directory you've visited |
| `fif text` | search inside files, open the hit in nvim at that line |
| `ff name` | find files by name |
| `l` | everything in this dir, with git status and "2 hours ago" times |
| `v file` | view any file (markdown, image, pdf, docx, json, code) in the terminal |
| `fgb` | switch git branch with a preview |
| <kbd>Esc Esc</kbd> | put `sudo` in front |
| `n some thought` | capture a note without leaving what you're doing |

## Learning path

1. **Shell**: [TUTORIAL](docs/TUTORIAL.md), then live with <kbd>F1</kbd> for a week. `you-should-use` will nag you into the aliases.
2. **Tools**: the [guides](guides/README.md) in order: Linux command helper → Git → Docker → Kubernetes → Helm/Tilt → CI → Linux security → (Bazel, Google Cloud as needed). Start each with its **A→Z**, and keep the **field manual** for reference.
3. **Working with Claude**: [claude/prompt-engineering.md](claude/prompt-engineering.md), then copy a [template](claude/README.md) into your next project.

## Rules this repo keeps

- **No secrets in git.** Tokens go in `~/.zshrc.local` (sourced if present, `chmod 600`). Before committing: `rg -i 'token|secret|password|ATATT|glpat-' zsh/ bin/`.
- **Every alias or function gets a description comment.** That's what feeds <kbd>F1</kbd> and the cheatsheet.
- **After changing shortcuts**, run `docs/gen-cheatsheet.sh`.
- Test config changes without risking your shell: `HOME=$(mktemp -d) ./install.sh --no-packages --no-chsh` then `HOME=<that dir> zsh -i`.
