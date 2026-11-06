# ~/.zsh/zhelp.zsh — searchable help for every alias, function and key you have.
#
#   zhelp            fuzzy search; Enter puts the pick on your prompt, Ctrl-O opens its source
#   zhelp docker     same, pre-filtered
#   zhelp -l [word]  plain grouped list (no fzf), e.g. zhelp -l k8s | less
#   F1               same as zhelp, from anywhere on the prompt
#
# Built from the source files on every run, so it can't go stale: add an alias with a
# trailing "# description" (or a "# description" line above a function) and it's in.

# in load order: a later definition of the same name replaces an earlier one
typeset -ga ZHELP_SOURCES=( ~/.zshrc ~/.zsh/{docker,k8s,cloud,bazel,dev,focus,god}.zsh )

# One line per entry: kind \t name \t section \t description \t file:line
_zhelp_index() {
  local f
  for f in $ZHELP_SOURCES; do
    [[ -r $f ]] || continue
    awk -v file="$f" '
      function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
      function emit(kind, name, desc) {
        if (name ~ /^_/) return
        gsub(/\t/, " ", desc)
        printf "%s\t%s\t%s\t%s\t%s:%d\n", kind, name, section, trim(desc), file, NR
      }
      BEGIN { section = file; sub(/.*\//, "", section); nb = 0 }
      # section markers: # === X ===   # --- X ---   # >>> X >>>
      /^[ \t]*#[ \t]*(===|---|>>>)[ \t]/ {
        s = $0
        sub(/^[ \t]*#[ \t]*(===|---|>>>)[ \t]*/, "", s); sub(/[ \t]*(===|---|>>>|<<<)[ \t]*$/, "", s)
        sub(/[ \t]+(—|-|\().*$/, "", s); sub(/:.*$/, "", s)
        if (s != "") section = trim(s)
        nb = 0; next
      }
      /^[ \t]*# key:/ {
        s = $0; sub(/^[ \t]*# key:[ \t]*/, "", s)
        i = index(s, " :: "); if (i) emit("key", trim(substr(s, 1, i - 1)), substr(s, i + 4))
        next
      }
      /^[ \t]*#/ { s = $0; sub(/^[ \t]*#+[ \t]?/, "", s); blk[++nb] = s; next }
      /^[ \t]*alias[ \t]+[A-Za-z0-9_.:+-]+=/ {
        s = $0; sub(/^[ \t]*alias[ \t]+/, "", s)
        name = s; sub(/=.*/, "", name)
        val = substr(s, length(name) + 2); desc = ""
        if (match(val, /[\x27"][ \t]+#[ \t]/)) { desc = substr(val, RSTART + RLENGTH); val = substr(val, 1, RSTART) }
        else if (match(val, /[ \t]+#[ \t]/)) { desc = substr(val, RSTART + RLENGTH); val = substr(val, 1, RSTART - 1) }
        if (desc == "" && nb) desc = blk[1]
        if (desc == "") { desc = val; gsub(/^[\x27"]|[\x27"]$/, "", desc); desc = "→ " desc }
        emit("alias", name, desc); nb = 0; next
      }
      /^[ \t]*(function[ \t]+[A-Za-z0-9_.:+-]+[ \t]*(\(\))?[ \t]*\{|[A-Za-z0-9_.:+-]+[ \t]*\(\))/ {
        s = $0; sub(/^[ \t]*(function[ \t]+)?/, "", s)
        name = s; sub(/[ \t]*(\(\)|\{).*/, "", name)
        desc = ""
        # prefer the comment line that starts with the name (usage line), else the first
        for (i = 1; i <= nb; i++) if (index(blk[i], name " ") == 1 || index(blk[i], name ":") == 1) { desc = blk[i]; break }
        if (desc == "" && nb) desc = blk[1]
        if (desc == "" && match(s, /\{.*\}/)) desc = "→ " trim(substr(s, RSTART + 1, RLENGTH - 2))
        emit("func", name, desc); nb = 0; next
      }
      { nb = 0 }
    ' "$f"
  done
}

# Index + any oh-my-zsh/plugin alias not defined in the files. Last definition
# wins (matches what the shell does); god.zsh entries listed first, omz last.
_zhelp_rows() {
  local -A row; local -a order; local kind name sec desc loc a k v
  while IFS=$'\t' read -r kind name sec desc loc; do
    [[ $kind == key ]] || (( $+aliases[$name] || $+functions[$name] )) || continue
    k="$kind:$name"; [[ $kind == func ]] && k="alias:$name"
    order=(${order:#$k} $k)
    row[$k]="$kind"$'\t'"$name"$'\t'"$sec"$'\t'"$desc"$'\t'"$loc"
  done < <(_zhelp_index)
  local -a first rest
  for k in $order; do [[ $row[$k] == *$'\t'${HOME}/.zsh/god.zsh:* ]] && first+=($k) || rest+=($k); done
  for k in $first $rest; do print -r -- "$row[$k]"; done
  for a in ${(ko)aliases}; do
    (( $+row[alias:$a] )) && continue
    v=${${aliases[$a]//$'\t'/ }//$'\n'/; }
    print -r -- "alias"$'\t'"$a"$'\t'"oh-my-zsh"$'\t'"→ $v"$'\t'"alias $a='$v'"
  done
}

# Picker: prints the chosen name (empty for keys / Ctrl-O / Esc)
_zhelp_pick() {
  local out key sel
  out=$(_zhelp_rows | awk -F'\t' '{
      tag = ($1 == "key") ? "\033[35m" : "\033[1;32m"
      printf "%s%-16.16s\033[0m \033[2m%-16.16s\033[0m %s\t%s\t%s\t%s\n", tag, $2, $3, $4, $1, $2, $5 }' |
    fzf --ansi --delimiter=$'\t' --with-nth=1 --query="$*" --expect=ctrl-o \
        --prompt='zhelp> ' --height=80% --layout=reverse --border=rounded \
        --header='Enter: put on prompt · Ctrl-O: open source · Ctrl-/: toggle preview' \
        --preview='loc={4}; f=${loc%:*}; n=${loc##*:}
                   if [[ -f $f ]]; then
                     bat --color=always --style=numbers,grid --highlight-line $n --line-range $(( n > 4 ? n - 4 : 1 )):$(( n + 30 )) "$f"
                   else print -r -- {4}; fi' \
        --preview-window='down,45%,border-top' --bind='ctrl-/:toggle-preview') || return
  # --expect prints the key line first, empty for Enter; "(@f)" in quotes keeps it
  local -a lines=("${(@f)out}"); key=$lines[1]; sel=$lines[2]
  local -a f=("${(@ps:\t:)sel}")
  if [[ $key == ctrl-o ]]; then
    [[ -f ${f[4]%:*} ]] && ${EDITOR:-nvim} "+${f[4]##*:}" "${f[4]%:*}" </dev/tty
  elif [[ ${f[2]} != key ]]; then
    print -r -- "${f[3]}"
  fi
}

zhelp() {
  if [[ $1 == (-l|--list) || ! -t 1 ]]; then
    [[ $1 == (-l|--list) ]] && shift
    local last= kind name sec desc loc
    _zhelp_rows | { [[ -n $1 ]] && grep -i -- "$*" || cat } |
      while IFS=$'\t' read -r kind name sec desc loc; do
        [[ $sec != $last ]] && { print -P "\n%B%F{cyan}── $sec ──%f%b"; last=$sec }
        printf '  \e[1;32m%-16s\e[0m %s\n' "$name" "$desc"
      done
    return
  fi
  local pick; pick=$(_zhelp_pick "$@")
  [[ -n $pick ]] && print -z -- "$pick "
}

_zhelp_widget() {
  local pick; zle -I
  pick=$(_zhelp_pick </dev/tty)
  [[ -n $pick ]] && LBUFFER+="$pick "
  zle reset-prompt
}
zle -N _zhelp_widget
bindkey '^[OP' _zhelp_widget     # F1 (xterm code)
bindkey '^[[11~' _zhelp_widget   # F1 (vt220 code)
