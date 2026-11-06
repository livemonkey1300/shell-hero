# ~/.zsh/focus.zsh — external working memory, at the shell.
# Source from ~/.zshrc:   source ~/.zsh/focus.zsh
# Notes go to $NOTES_DIR (default ~/notes): inbox.md for captures.
#
# ── The design rule ────────────────────────────────────────────────────────
# Automate the DOING, not the reminding. Generic self-nudging does not survive
# publication-bias correction (d 0.43 -> 0.04). What survives is lowering the
# cost of the correct action. So: nothing here nags. Everything here removes a
# step, and the cues appear where the work is.
#
# Capture latency is the one metric that matters. If any of these takes more
# than ~5 seconds to invoke, it will decay and stop being used.

# ── Capture ────────────────────────────────────────────────────────────────
# Prospective memory is the thing most likely to fail silently. Sub-second
# capture, with the context you'd otherwise have to reconstruct.
n() {
  [ $# -eq 0 ] && { ${EDITOR:-vi} "${NOTES_DIR:-$HOME/notes}/inbox.md"; return; }
  mkdir -p "${NOTES_DIR:-$HOME/notes}"
  printf '%s | %s | %s | %s\n' \
    "$(date -Is)" "$PWD" "$(git rev-parse --short HEAD 2>/dev/null || echo '-')" "$*" \
    >> "${NOTES_DIR:-$HOME/notes}/inbox.md"
  print -P "%F{blue}⚑%f captured"
}

# Retrieve without having to remember where you filed it. Full-text search
# removes the taxonomy decision entirely — one fewer decision at point of use.
nf() {
  local hit
  hit=$(rg --no-heading --line-number . "${NOTES_DIR:-$HOME/notes}" 2>/dev/null | fzf --exact --delimiter=: --preview 'bat -n --color=always {1} 2>/dev/null || cat {1}') || return
  ${EDITOR:-vi} "${hit%%:*}"
}

# ── The handoff note ───────────────────────────────────────────────────────
# The highest-value 60 seconds of the day. Written during a good hour, read
# during a bad one — the only thing that converts your peak into your floor.
park() {
  local root; root=$(git rev-parse --show-toplevel 2>/dev/null) || { print -u2 "not in a repo"; return 1; }
  local f="$root/.PARKED.md"
  if [ ! -f "$f" ]; then
    cat > "$f" <<EOF
# Handoff — $(git branch --show-current 2>/dev/null)

Doing:
Next command:
Watch out for:
EOF
    grep -qxF '.PARKED.md' "$root/.git/info/exclude" 2>/dev/null || \
      echo '.PARKED.md' >> "$root/.git/info/exclude"
  fi
  ${EDITOR:-vi} "$f"
}

# ── Point of performance ───────────────────────────────────────────────────
# Entering a repo that has a handoff note prints it. You do not have to
# remember to look — which is the entire point, because the feeling that you
# don't need to check is the documented error.
_adhd_chpwd() {
  local root; root=$(git rev-parse --show-toplevel 2>/dev/null) || return
  [ -s "$root/.PARKED.md" ] || return
  [ "$root" = "$_ADHD_LAST_ROOT" ] && return     # once per repo, not per cd
  _ADHD_LAST_ROOT="$root"
  print -P "%F{green}── handoff ──%f"
  sed 's/^/  /' "$root/.PARKED.md"
}
autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook chpwd _adhd_chpwd

# ── Context persistence ────────────────────────────────────────────────────
# One tmux session per CONCERN, never per repo — the concern is what you lose.
# Re-entering restores layout, cwd, scrollback and running processes: the state
# that otherwise costs 10-15 minutes to rebuild.
ctx() {
  [ $# -eq 0 ] && { tmux ls 2>/dev/null || print "no contexts"; return; }
  tmux new -As "$1"
}

# Stash messages are an instruction to your future self, not a label.
wip() {
  git stash push -m "wip $(date +%F) — next: ${*:-unspecified}"
}

# ── Decision hygiene ───────────────────────────────────────────────────────
# Surfaces decisions you logged but never scored. The scoring is the part with
# evidence behind it (6-11% calibration gain); the writing alone is a diary.
unscored() {
  rg -B6 '^\- \*\*scored on\*\*:[[:space:]]*$' ~/.claude/decisions.md 2>/dev/null \
    | rg '^## ' || print "✓ nothing unscored"
}

# ── Pomodoro ───────────────────────────────────────────────────────────────
# Shell shortcuts. The Claude commands (/pomo, /pomo-done, /pomo-review) do the
# judgement parts — picking ONE task, sizing the interval, honest capture.
# These are for when you're already in flow and just need the timer moved on.
p()  { pomo "$@"; }
ps_() { pomo status; }
pd() { pomo done "$*"; }
pb() { pomo break "$@"; }
pl() { pomo log "${1:-today}"; }

# Supersedes the old bare `t` timer — pomo logs, t didn't.
