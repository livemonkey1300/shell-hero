# ~/.zsh/dev.zsh — dev-tool shortcuts: moon task runner, Graphviz, fuzzy edit.

# === Moon ===
# moon (moonrepo.dev) monorepo task runner; completion in ~/.zsh/completions/moon-completion.zsh
if (( $+commands[moon] )) || [[ -r $HOME/.moon/bin/env ]]; then
  [[ -r $HOME/.moon/bin/env ]] && . "$HOME/.moon/bin/env"
  # mr <target>... [flags]: `moon run`, scoped to the current project, or
  # workspace-wide from the workspace root. Bare targets get `~:` (current
  # project) or `:` (workspace root, where .moon/ lives); qualified ones (with a
  # `:`) pass through. After the first flag, every arg passes through unchanged.
  mr() {
      local prefix='~:' passthrough=0 count=$# i=0 arg
      [[ -d "$PWD/.moon" ]] && prefix=':'
      while (( i < count )); do
          arg=$1
          shift
          if (( passthrough )); then
              set -- "$@" "$arg"
          else
              case "$arg" in
              --|-*) passthrough=1; set -- "$@" "$arg" ;;
              *:*) set -- "$@" "$arg" ;;
              *) set -- "$@" "${prefix}${arg}" ;;
              esac
          fi
          (( i++ ))
      done
      moon run "$@"
  }
  # mrq: mr --quiet, with the flag placed before any `--` so moon keeps it.
  mrq() {
      local split=${@[(ie)--]}
      if (( split > $# )); then
          mr "$@" --quiet
      else
          mr "${@[1,split-1]}" --quiet "${@[split,-1]}"
      fi
  }
  mt() { moon tasks "$@" }
  [[ -r ~/.zsh/completions/moon-completion.zsh ]] && source ~/.zsh/completions/moon-completion.zsh
fi

# === Misc ===
# Render a Graphviz .dot file to PNG and open it, e.g. `dotr diagram.dot`
dotr() {
  if [[ -z "$1" ]]; then
    echo "Usage: dotr <file.dot> [output.png]"
    return 1
  fi
  local out="${2:-${1:r}.png}"
  dot -Tpng "$1" -o "$out" && ${_god_opener:-xdg-open} "$out"
}

# fuzzy-pick a file and open it in nvim: fe [query]
fe() {
  local file
  file=$(fzf --query="$1" --select-1 --exit-0)
  [ -n "$file" ] && ${EDITOR:-nvim} "$file"
}
