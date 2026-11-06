# Install — any OS

**One command on Linux, macOS and WSL:**

```sh
git clone <this-repo> ~/perso/shell-hero && cd ~/perso/shell-hero && ./install.sh
exec zsh        # then press F1
```

The installer is safe to re-run. It skips anything already installed, and **backs up any file it replaces** as `file.bak-YYYYMMDD-HHMMSS`.

| Flag | Effect |
|---|---|
| *(none)* | packages + oh-my-zsh + plugins + configs symlinked to the repo + zsh as login shell |
| `--no-packages` | skip the package manager (no sudo); for locked-down machines |
| `--copy` | copy configs instead of symlinking (edit freely, repo untouched) |
| `--no-chsh` | don't change your login shell |

**Symlink vs copy:** with symlinks (the default), `git pull` in the repo updates your shell, and `zshrc`/`zgod` edits land in the repo, ready to commit. Use `--copy` on a machine where you don't want the repo to be the source of truth.

---

## What gets installed

| Piece | Where it goes | Why |
|---|---|---|
| `zsh/zshrc` | `~/.zshrc` | load order, plugins, history, keys |
| `zsh/*.zsh` | `~/.zsh/` | one module per topic; each skips itself if its tool is missing |
| `zsh/p10k.zsh` | `~/.p10k.zsh` | Powerlevel10k prompt (`p10k configure` to redo) |
| `zsh/completions/*` | `~/.zsh/completions/` | `make` target and `moon` completion |
| `bin/*` | `~/.local/bin/` | `mdview`, `imgview`, `docview`, `vpreview`, `pomo` |
| `guides/` | `~/.local/share/shell-hero/guides` | so `mdd` can browse them |
| oh-my-zsh | `~/.oh-my-zsh` | plugin framework |
| plugins | `~/.oh-my-zsh/custom/` | powerlevel10k, autosuggestions, syntax-highlighting, history-substring-search, zsh-completions, fzf-tab, you-should-use |

**Packages** (by command name): `zsh git curl fzf rg fd bat eza zoxide nvim jq btop lazygit yazi tldr chafa pdftotext`, plus Python `rich` and `pillow` for the terminal viewers, plus a clipboard tool (`wl-clipboard` or `xclip`) and `trash-cli` on Linux desktops.

---

## Per-OS notes

### Fedora / RHEL / CentOS Stream — `dnf`
Everything comes from the official repos except `yazi`, which is optional. If you want it: `sudo dnf copr enable lihaohong/yazi && sudo dnf install yazi`.

### Debian / Ubuntu / Mint / Pop!_OS / Zorin — `apt`
- `fd` and `bat` install as **`fdfind` and `batcat`**. The installer symlinks them to `fd` and `bat` in `~/.local/bin`, and the config handles both names.
- `eza` is packaged from Debian 13 and Ubuntu 24.04 onward. On older releases it ends up in the "not installed" list, and `ls` falls back to plain `ls --color`.
- `lazygit` is installed from its GitHub release when apt doesn't have it.
- **Ubuntu 22.04 ships fzf 0.29**, which is too old for this config. The installer detects that and installs upstream fzf into `~/.fzf`.
- Neovim from apt can be old. For a current one: `sudo add-apt-repository ppa:neovim-ppa/unstable && sudo apt install neovim`, or use the AppImage.

### Arch / Manjaro / EndeavourOS — `pacman`
Everything is in the official repos.

### openSUSE — `zypper`
Everything except `yazi` (optional).

### macOS — Homebrew
- The installer installs Homebrew first if it's missing.
- macOS has used zsh by default since Catalina, so `chsh` is usually a no-op.
- The config picks the macOS tools by itself: `open` instead of `xdg-open`, `pbcopy`/`pbpaste` for the clipboard, `lsof` for `ports`, `brew` for `upd`.
- Linux-only shortcuts (`ip`, `free`, `dfh` filters, `gio trash`) are skipped or fall back to an equivalent.
- For `del` (move to trash), macOS 14+ has `trash` built in; on older versions, `brew install trash`.
- Python libraries go in with `pip3 install --user rich pillow`.

### Windows — WSL2
1. In PowerShell (admin): `wsl --install -d Ubuntu`, then reboot.
2. Open Ubuntu and follow the Debian/Ubuntu notes: `./install.sh`.
3. Install a **Nerd Font** in Windows (for example *JetBrainsMono Nerd Font*) and select it in Windows Terminal → Settings → Ubuntu → Appearance. Without it, icons show as boxes.
4. Clipboard: `clip.exe` and PowerShell `Get-Clipboard` are used automatically. `o` uses `wslview` if you install `wslu`: `sudo apt install wslu`.

Plain Windows without WSL isn't supported, because zsh needs a POSIX environment.

---

## After installing

1. **Font:** install any [Nerd Font](https://www.nerdfonts.com/) and select it in your terminal. Powerlevel10k and `eza --icons` need it.
2. **Terminal:** any terminal works. **Ghostty, kitty or WezTerm** also show real images inline (`img`, `pdfv`, mermaid diagrams in `mdv`).
3. **Secrets go in `~/.zshrc.local`**, which is sourced if present and never committed. API tokens, work-only aliases and machine paths all belong there:
   ```sh
   # ~/.zshrc.local  (chmod 600)
   export SOME_API_TOKEN='…'
   alias work-repo='cd ~/work/big-repo'
   ```
4. **Optional DevOps tools:** the matching modules switch on as soon as these tools are on `PATH`:

   | Tool | Install |
   |---|---|
   | Docker | <https://docs.docker.com/engine/install/> (or Podman: `dnf/apt install podman`) |
   | kubectl | <https://kubernetes.io/docs/tasks/tools/> |
   | helm | `curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \| bash` |
   | krew + `ctx`/`ns`/`tree` plugins | <https://krew.sigs.k8s.io/docs/user-guide/setup/install/> then `kubectl krew install ctx ns tree` |
   | kubecolor | `brew install kubecolor` / GitHub release |
   | gcloud | <https://cloud.google.com/sdk/docs/install> |
   | terraform | <https://developer.hashicorp.com/terraform/install> |
   | bazelisk (as `bazel`) | <https://github.com/bazelbuild/bazelisk/releases> → `~/.local/bin/bazel` |
   | moon | `curl -fsSL https://moonrepo.dev/install/moon.sh \| bash` |
   | mise | `curl https://mise.run \| sh` |
   | grype / syft / hadolint / shellcheck | `sbom`, `vulns`, `dlint`, `shlint` use these. Packaged on most distros or via brew |

## Uninstall

```sh
rm ~/.zshrc ~/.p10k.zsh ~/.zsh/*.zsh            # the symlinks
mv ~/.zshrc.bak-<stamp> ~/.zshrc                # restore your old one
rm ~/.local/bin/{mdview,imgview,docview,vpreview,pomo}
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| Icons are boxes or `?` | Install a Nerd Font and select it in the terminal |
| `zsh: command not found: fd` (Debian) | `ln -s $(which fdfind) ~/.local/bin/fd` (the installer does this) |
| fzf errors on `--info=inline-right` | fzf is older than 0.48: rerun `./install.sh` (it upgrades) |
| A `compdef` alias lost its completion | something ran `compinit` a second time after it; see the tutorial, *Load order* |
| Slow startup | `zmodload zsh/zprof` at the top of `~/.zshrc`, `zprof` at the bottom, open a new shell |
| Prompt asks the p10k wizard | `p10k configure`, or check `~/.p10k.zsh` is linked |
