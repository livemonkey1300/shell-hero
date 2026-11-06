# Tutorial — how this shell works, and how to make it yours

Read this once, top to bottom, in about 45 minutes. After that you'll be able to read any line of the config and write your own shortcuts the same way.

Each section has **the idea**, **the real code**, and a **trap** we actually hit while building this.

---

## 1. How zsh starts

zsh reads several files at startup. You only need two:

| File | When | Put here |
|---|---|---|
| `~/.zshenv` | **every** zsh, even scripts | almost nothing (it slows every script) |
| `~/.zshrc` | interactive shells | everything in this repo |

`~/.zshrc` is plain zsh, run top to bottom, so **order is the whole game.** That's why `zsh/zshrc` is short and numbered:

```
1. SSH key unlock        – may ask for a PIN/touch, so it must come before…
2. instant prompt         – …which draws the prompt immediately and buffers output
3. fpath, then oh-my-zsh  – oh-my-zsh runs compinit (completion) exactly once
4. history, keys, editor
5. topic modules          – docker, k8s, cloud, bazel, dev, focus
6. god.zsh LAST           – zoxide must init after compinit
```

> **Trap — the double `compinit`.** Your old `.zshrc` called `compinit` three times. Each call **wipes every `compdef` made before it**, which is why the old comments said things like "h/fx completion must stay after the last compinit". The fix: put the completion directories on `fpath` **before** oh-my-zsh loads, and never call `compinit` again. One call, nothing lost, faster startup (about 0.33 s here).

## 2. oh-my-zsh and plugins

oh-my-zsh is a loader. You list plugins, and it sources them in order:

```zsh
plugins=( git sudo extract fzf zsh-completions fzf-tab you-should-use
          zsh-autosuggestions zsh-syntax-highlighting zsh-history-substring-search )
```

| Plugin | What you get |
|---|---|
| `git` | about 200 `g*` aliases (`gst`, `gco`, `gp`…). F1 lists them |
| `sudo` | <kbd>Esc Esc</kbd> prefixes `sudo` |
| `fzf` | <kbd>Ctrl-R</kbd> history, <kbd>Ctrl-T</kbd> files, <kbd>Alt-C</kbd> cd |
| `fzf-tab` | <kbd>Tab</kbd> opens fzf with previews instead of a list |
| `you-should-use` | tells you when you typed something an alias already covers. This is how aliases get learned |
| `zsh-autosuggestions` | grey suggestion from history; <kbd>→</kbd> or <kbd>Ctrl-Space</kbd> accepts it |
| `zsh-syntax-highlighting` | red while you type means the command doesn't exist |
| `zsh-history-substring-search` | type part of a command, then <kbd>↑</kbd> |

> **Trap — plugin aliases collide with yours.** The `git` plugin defines `gcm` as "checkout main". If you expect `gcm` to be "commit -m", redefine it **after** `source $ZSH/oh-my-zsh.sh`. The same thing is why the Google Cloud shortcuts are `gx`, `gvms`, `gkec`: `gcl`, `gcs`, `gst`, `gcp` and `gke` were already taken by oh-my-zsh.

> **Trap — fzf-tab needs the menu off.** oh-my-zsh sets `menu select` on a *more specific* zstyle pattern, which outranks a generic `menu no`. You need both lines:
> ```zsh
> zstyle ':completion:*' menu no
> zstyle ':completion:*:*:*:*:*' menu no
> ```

## 3. Alias or function?

**Alias:** text substitution, good for a fixed command with a few flags.
```zsh
alias dps='docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"'
```

**Function:** anything with arguments in the middle, logic, or more than one step.
```zsh
# shell into the first pod whose name matches: kbash api -n my-ns
kbash() {
  local pod
  pod=$(command kubectl get pod -o name "${@:2}" | grep -m1 -- "$1") || { echo "no pod matching '$1'" >&2; return 1; }
  command kubectl exec -it "$pod" "${@:2}" -- sh -c 'command -v bash >/dev/null && exec bash || exec sh'
}
```

The habits in that function:
- `local` for every variable, so nothing leaks into your shell.
- `"${@:2}"` passes the remaining arguments through, so `-n ns` just works.
- `command kubectl` skips the `kubectl→kubecolor` alias, keeping piped output free of colour codes.
- `|| { …; return 1; }` gives a clear error and a non-zero exit.

> **Trap — Fedora pre-defines some aliases.** `l.` already exists as an alias on Fedora, and `l.() { … }` then fails to parse, because the alias expands first. Use `function l. { … }`, which isn't subject to alias expansion.

> **Trap — optional flag values eat arguments.** `eza --icons lib` treats `lib` as the *value* of `--icons`. Always write `--icons=auto`.

## 4. The zsh-isms you'll see everywhere

| Code | Meaning |
|---|---|
| `(( $+commands[eza] ))` | is `eza` on PATH? Faster than `command -v`, no subprocess |
| `(( $+aliases[x] ))` / `$+functions[x]` | is `x` an alias or function? |
| `${(f)"$(cmd)"}` | split output into an array **by line** |
| `${(s.:.)var}` | split on `:` |
| `*(N)` | glob qualifier: N = no error if nothing matches |
| `*(DN[1,41])` | include dotfiles, nullglob, first 41 matches (used by auto-ls to count cheaply) |
| `${f:e}` `${f:r}` `${f:t}` | extension, path without extension, basename |
| `cmd &!` | start in the background **and** disown (no "job finished" noise) |
| `print -z -- "text"` | put text **on your next prompt** for you to edit, instead of running it |
| `${1:-default}` | first argument, or a default |

`print -z` is the secret behind `zhelp` and the Jira-style pickers: they *put the command on your prompt* instead of running it, so you can check it first.

## 5. fzf pickers: the pattern behind half the shortcuts

Almost every `f*` command has the same shape: **list → fzf with preview → act on the pick**.

```zsh
# fuzzy-switch branch, preview shows recent commits
fgb() {
  local b; b=$(git branch --all --sort=-committerdate --format='%(refname:short)' | grep -v HEAD |
    fzf --prompt='branch> ' --preview 'git log --oneline --graph --color=always -20 {}') || return
  git switch "${b#origin/}"
}
```

- `|| return`: <kbd>Esc</kbd> in fzf exits non-zero, so the function quietly stops.
- `{}` in `--preview` is the highlighted line. `{1}` is its first field.
- `--expect=ctrl-e` makes fzf print which key you pressed first, so one picker can do two things (Enter = read, Ctrl-E = edit). See `_md_pick` in `god.zsh`.
- `--bind 'ctrl-r:execute-silent(...)+refresh-preview'` toggles a mode without leaving fzf. `mdf` uses this to flip rendered ⇄ raw.

Try writing one yourself: a picker over `docker ps` that runs `docker logs -f` on the chosen container.

## 6. Key bindings and widgets (ZLE)

The line editor is called ZLE. A *widget* is a function bound to a key:

```zsh
# Ctrl-Z on an empty prompt brings the suspended job back
_god_fg_toggle() { if (( $#BUFFER == 0 )); then BUFFER=fg; zle accept-line; else zle push-input; fi }
zle -N _god_fg_toggle && bindkey '^Z' _god_fg_toggle
```

- `$BUFFER` is the text on the prompt; `$LBUFFER` is the text left of the cursor.
- `zle -I` and `zle reset-prompt` are needed around anything that draws (fzf), or the prompt gets corrupted.
- To find a key's code: run `cat`, press the key, and read what's printed (`^[OP` is F1).

## 7. Hooks: run code when something happens

```zsh
autoload -Uz add-zsh-hook && add-zsh-hook chpwd _god_autols
```

`chpwd` runs after every `cd`. Two shortcuts use it: auto-`ls` in small directories, and printing a repo's `.PARKED.md` handoff note when you enter it (`focus.zsh`).

> **Trap — hooks run inside `$(…)` too.** `x=$(cd foo && pwd)` triggers `chpwd`, so auto-ls output would land *inside `x`*. The guard:
> ```zsh
> (( ZSH_SUBSHELL == 0 )) && [[ -t 1 && -o interactive ]] || return
> ```
> Only act when you're at a real prompt.

## 8. zhelp: self-documenting config

`zhelp` (or <kbd>F1</kbd>) **reads the source files** on every run, so it can't go stale. The conventions:

```zsh
# === Section Name ===                       starts a section
alias x='…'   # what it does                  trailing comment = description
# what it does: usage example                comment right above a function = description
myfunc() { … }
# key: Ctrl-X :: what it does                documents a key binding
```

A function with no comment above it shows up with a broken description, so **always write the comment**. That comment also becomes your cheatsheet: `docs/gen-cheatsheet.sh` builds [CHEATSHEET.md](CHEATSHEET.md) from the same index.

## 9. Cross-platform without a mess

Detect once, at load time, then use the result everywhere:

```zsh
if [[ $OSTYPE == darwin* ]];    then _god_opener=open
elif (( $+commands[wslview] )); then _god_opener=wslview
else                                 _god_opener=xdg-open; fi
alias o='$_god_opener'
```

The clipboard (`_god_copy`: pbcopy / wl-copy / xclip / clip.exe), trash, `upd` and `ports` work the same way. **Underscore-prefixed names** are internal; zhelp hides them.

## 10. Modules that switch themselves off

Every topic file starts with a guard:

```zsh
(( $+commands[kubectl] )) || return 0
```

`return` at the top level of a *sourced* file stops sourcing just that file. Install kubectl later and the shortcuts appear in the next shell; no config edit is needed.

**Add your own module:** create `zsh/mytool.zsh` with a guard and a `# === Section ===`, add `mytool` to the `for __m in …` loop in `zshrc`, and add it to `ZHELP_SOURCES` in `zhelp.zsh`.

## 11. Secrets never go in the repo

`zshrc` ends with:

```zsh
[[ -r ~/.zshrc.local ]] && source ~/.zshrc.local
```

Tokens, work hostnames and internal tool paths go **there**, with `chmod 600 ~/.zshrc.local`. Two more habits:
- Start a command with a **space** to keep it out of history (`HIST_IGNORE_SPACE`), for example ` export TOKEN=…`.
- Before committing dotfiles, scan them: `rg -i 'token|secret|password|api_key|ATATT|glpat-' zsh/`.

## 12. Debugging your shell

| Problem | Tool |
|---|---|
| What is `x`, really? | `whence -v x` (alias? function? which file?) or `type x` |
| Where was a function defined? | `whence -v myfunc` |
| Trace every line | `zsh -x -i -c exit 2>&1 \| less` |
| Startup is slow | `zmodload zsh/zprof` first line, `zprof` last line, new shell |
| Test a config without touching yours | `HOME=$(mktemp -d) ./install.sh --no-packages --no-chsh`, then `HOME=… zsh -i` |
| Syntax check | `zsh -n file.zsh` |

## 13. Exercises

1. Add `alias please-ls='…'` with a trailing description, then find it with <kbd>F1</kbd>.
2. Write `dlf`: fzf over running containers → `docker logs -f`.
3. Make `mkcd dir` (mkdir + cd) as a function, and explain why it can't be an alias.
4. Add a `chpwd` hook that prints the Node version when a directory has `package.json`, guarded so it never fires inside `$(…)`.
5. Run `docs/gen-cheatsheet.sh` and check your additions appear.

---

**Next:** [CHEATSHEET.md](CHEATSHEET.md) for everything available, and the [guides](../guides/README.md) for the tools themselves.
