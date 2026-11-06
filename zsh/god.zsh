# ~/.zsh/god.zsh — daily-driver shortcuts, sourced at the end of ~/.zshrc.
#
# zhelp reads this file (and ~/.zshrc, adhd.zsh) to build its index, so:
#   "# === Name ==="        starts a section
#   alias x='…'   # text    trailing comment = description
#   # text                  comment line right above a function = description
#   # key: Ctrl-X :: text   documents a key binding
#
# Works on Linux (Wayland or X11), macOS and WSL: the few OS-specific bits
# (open, clipboard, trash, system update) pick the right tool at load time.

# --- cross-platform plumbing (underscore names stay out of zhelp) ---
if [[ $OSTYPE == darwin* ]];            then _god_opener=open
elif (( $+commands[wslview] ));         then _god_opener=wslview
else                                         _god_opener=xdg-open; fi
_god_copy() {
  if   (( $+commands[pbcopy] ));   then pbcopy
  elif [[ -n $WAYLAND_DISPLAY ]] && (( $+commands[wl-copy] )); then wl-copy
  elif (( $+commands[xclip] ));    then xclip -selection clipboard
  elif (( $+commands[clip.exe] )); then clip.exe
  else echo "no clipboard tool: install wl-clipboard (Wayland) or xclip (X11)" >&2; return 1; fi
}
_god_paste() {
  if   (( $+commands[pbpaste] ));  then pbpaste
  elif [[ -n $WAYLAND_DISPLAY ]] && (( $+commands[wl-paste] )); then wl-paste
  elif (( $+commands[xclip] ));    then xclip -selection clipboard -o
  else powershell.exe -noprofile -command Get-Clipboard 2>/dev/null; fi
}
_god_trash() {
  if   (( $+commands[gio] ));   then gio trash "$@"
  elif (( $+commands[trash] )); then trash "$@"          # macOS 14+ / trash-cli
  else echo "no trash tool: install trash-cli" >&2; return 1; fi
}

# === Listing ===
if (( $+commands[eza] )); then
  _eza='eza --icons=auto --group-directories-first'
  alias ls="$_eza"                                                      # list, dirs first, icons
  alias l="$_eza --long --all --git --time-style=relative --no-user"    # EVERYTHING: long, hidden, git status, "2 hours ago"
  alias ll="$_eza --long --git --time-style=relative --no-user"         # long list with git status
  alias la="$_eza --long --all --git"                                   # long list incl. hidden files
  alias lt="$_eza --tree --level=2 --git-ignore"                        # tree, 2 levels, skips .gitignored
  alias lS="$_eza --long --sort=size --total-size --no-user"            # by size, biggest LAST (next to prompt); dirs show real size
  alias lm="$_eza --long --sort=modified --time-style=relative --no-user" # by modified time, newest LAST
  alias lx="$_eza --long --sort=extension --no-user"                    # grouped by file extension
  alias ldir="$_eza --long --only-dirs --no-user"                       # directories only (ld is the linker)
  alias lf="$_eza --long --only-files --no-user"                        # files only
  # hidden (dot) files only
  function l. { ${=_eza} --long --all --no-user -d .*(N) }   # "function" form: Fedora aliases l., which would break "l.()"
  # tree to any depth: ltree [depth=3] [dir]
  ltree() { ${=_eza} --tree --git-ignore --level=${1:-3} "${2:-.}" }
fi

# === Navigation ===
# up N directories: up 3
up() { local n=${1:-1} p=; while (( n-- > 0 )); do p+=../; done; cd "${p:-..}" }
# jump to the root of the current git repo
cdg() { cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" }
# fuzzy-pick any directory below here and cd into it
cdf() { local d; d=$(fd --type d --hidden --exclude .git . "${1:-.}" | fzf --prompt='cd> ' --preview 'eza --tree --level=2 --icons=always --color=always {}') && cd "$d" }
# cd into a dir and list it
cl() { cd "${1:-$HOME}" && ls }
# cd into a fresh throwaway temp directory
mkt() { cd "$(mktemp -d)" && pwd }

# auto-list after every cd (only small dirs, ≤40 entries). `autols off` / `autols on`
_GOD_AUTOLS=1
autols() { [[ $1 == off ]] && _GOD_AUTOLS=0 || _GOD_AUTOLS=1; echo "autols: ${${_GOD_AUTOLS/1/on}/0/off}" }
# only at the prompt: never inside $(cd … && pwd), scripts or pipes, where it would corrupt output
_god_autols() { (( _GOD_AUTOLS && ZSH_SUBSHELL == 0 )) && [[ -t 1 && -o interactive ]] || return; local -a e=( *(DN[1,41]) ); (( $#e && $#e <= 40 )) && ls }
autoload -Uz add-zsh-hook && add-zsh-hook chpwd _god_autols

# zoxide: `z foo` jumps to the most-used dir matching foo, `zi` picks with fzf
# key: z <part> :: jump to your most-used dir matching <part> (zoxide; learns as you cd)
# key: zi :: fuzzy-pick from every dir you've visited
(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"

# === Find & search ===
# find files by name (fd, includes hidden, skips .git): ff pattern [dir]
ff() { fd --type f --hidden --exclude .git "$@" }
# find directories by name: ffd pattern [dir]
ffd() { fd --type d --hidden --exclude .git "$@" }
# find text in files, pick a hit with preview, open nvim at that line: fif text [dir]
fif() {
  [[ -z $1 ]] && { echo "usage: fif <text> [dir]" >&2; return 1 }
  local sel; sel=$(rg --line-number --no-heading --color=always --smart-case -- "$1" "${2:-.}" |
    fzf --ansi --delimiter : --prompt="$1> " \
        --preview 'bat --color=always --style=numbers --highlight-line {2} {1}' \
        --preview-window 'right,60%,+{2}/2') || return
  ${EDITOR:-nvim} "+${${(s.:.)sel}[2]}" "${${(s.:.)sel}[1]}"
}
# fuzzy-pick processes (Tab = multi) and kill them: fkill [signal]
fkill() {
  local pids; pids=$(ps -u $USER -o pid,%cpu,%mem,etime,cmd --sort=-%cpu |
    fzf -m --header-lines=1 --prompt='kill> ' | awk '{print $1}')
  [[ -n $pids ]] && kill -${1:-15} ${(f)pids} && echo "sent SIG${1:-TERM} to ${(f)pids}"
}
# search your command history: hs docker
hs() { fc -lim "*${*}*" 1 | tail -n 40 }

# === Git (fuzzy) ===
# fuzzy-switch branch (local + remote), preview shows recent commits
fgb() {
  local b; b=$(git branch --all --sort=-committerdate --format='%(refname:short)' | grep -v HEAD |
    fzf --prompt='branch> ' --preview 'git log --oneline --graph --color=always -20 {}') || return
  git switch "${b#origin/}"
}
# browse git log with diff preview; Enter = full commit in a pager
fgl() {
  git log --oneline --color=always --decorate "$@" |
    fzf --ansi --no-sort --prompt='commit> ' \
        --preview 'git show --color=always --stat --patch {1} | head -300' \
        --bind 'enter:execute(git show --color=always {1} | less -R)'
}

# === Files ===
alias cp='cp -i'                     # ask before overwriting (\cp to skip)
alias mv='mv -i'                     # ask before overwriting (\mv to skip)
alias rm='rm -I'                     # ask once before deleting >3 files or recursing (rm -rf still silent)
alias del='_god_trash'               # move to the trash instead of deleting
if (( $+commands[gio] )); then
  alias trashls='gio trash --list'     # what's in the trash
  alias trashempty='gio trash --empty' # empty the trash
fi
alias cpv='rsync -ah --info=progress2' # copy with a progress bar: cpv src dst
# timestamped backup copy: bak file → file.bak-20261103-0930
bak() { local f; for f in "$@"; do command cp -a -- "$f" "$f.bak-$(date +%Y%m%d-%H%M)" && echo "→ $f.bak-$(date +%Y%m%d-%H%M)"; done }
# size of everything here, sorted, biggest last: sizes [dir]
sizes() { (cd "${1:-.}" && du -sh -- *(DN) 2>/dev/null | sort -h) }
# disk usage per mount, without the tmpfs/overlay noise
dfh() { df -h -x tmpfs -x devtmpfs -x overlay -x squashfs -x efivarfs }
alias e='${EDITOR:-nvim}'             # open in your editor: e file
alias o='$_god_opener'                # open with the default app: o . / o file.pdf
alias json='jq -C . | less -R'        # pretty-print JSON from a pipe: curl … | json

# === Clipboard ===
# copy a file's contents (or stdin) to the clipboard: clip file / cmd | clip
clip() { if [[ -n $1 ]]; then _god_copy < "$1"; else _god_copy; fi }
alias clipp='_god_paste'              # print the clipboard
# copy the current directory path
cpwd() { print -rn -- $PWD | _god_copy && echo "copied $PWD" }

# === System ===
if (( $+commands[ss] )); then
  alias ports='ss -tulpn'               # every listening port + process
else
  alias ports='lsof -nP -iTCP -sTCP:LISTEN' # every listening port + process (macOS)
fi
# who is using a port: port 8080
port() { (( $+commands[ss] )) && ss -tulpnH "sport = :$1"; (( $+commands[lsof] )) && lsof -nP -i :"$1" 2>/dev/null }
alias psg='ps aux | grep -v grep | grep -i'   # find a process: psg node
alias topmem='ps -eo pid,%mem,rss,cmd --sort=-%mem | head -15' # top memory users
alias topcpu='ps -eo pid,%cpu,cmd --sort=-%cpu | head -15'     # top CPU users
alias meminfo='free -h'               # RAM / swap
alias localip='ip -br -c a'           # your IPs, one line per interface
alias myip='curl -fsS https://ifconfig.me; echo' # public IP
alias path='print -l $path'           # PATH, one entry per line
alias now='date "+%Y-%m-%d %H:%M:%S (%a, week %V)"' # date/time/week
alias please='sudo $(fc -ln -1)'      # rerun the last command with sudo (or Esc Esc)
# update the whole system, whatever the package manager
upd() {
  if   (( $+commands[dnf] ));    then sudo dnf upgrade --refresh
  elif (( $+commands[apt] ));    then sudo apt update && sudo apt full-upgrade
  elif (( $+commands[pacman] )); then sudo pacman -Syu
  elif (( $+commands[zypper] )); then sudo zypper dup
  elif (( $+commands[brew] ));   then brew update && brew upgrade
  fi
  (( $+commands[flatpak] )) && flatpak update
  return 0
}
# serve this directory over http: serve [port=8000]
serve() { python3 -m http.server "${1:-8000}" }
# cheatsheet for any command, from cheat.sh (uses tldr if installed): cheat tar
cheat() { if (( $+commands[tldr] )); then tldr "$@"; else curl -fsS "https://cheat.sh/${(j:+:)@}"; fi }

# === Markdown ===
# read markdown RENDERED in a pager (q quits): mdv file.md  (no file = pick one)
#   files with ```mermaid diagrams print without the pager, so the diagrams can be drawn as pictures
mdv() {
  local f=${1:-$(_md_pick .)}; [[ -n $f ]] || return
  if [[ -z $TMUX && $TERM == *(ghostty|kitty)* ]] && grep -qE '^\s*(```|~~~)\s*mermaid' -- "$f" 2>/dev/null; then
    mdview --images -- "$f"
  else
    mdview -- "$f" | less -RF
  fi
}
# read markdown RAW, syntax-highlighted: mdr file.md
mdr() { bat --language=markdown --style=numbers,grid -- "$@" }
# pick a .md with live preview; Ctrl-R flips rendered⇄raw, Enter reads, Ctrl-E edits: mdf [dir] [query]
mdf() { local f; f=$(_md_pick "${1:-.}" "$2") && [[ -n $f ]] && mdv "$f" }
# browse your cheatsheets the same way (SHELL_HERO_DOCS, default: the guides in this repo): mdd [query]
mdd() { mdf "${SHELL_HERO_DOCS:-$HOME/.local/share/shell-hero/guides}" "$1" }
_md_pick() {
  local flag=${XDG_RUNTIME_DIR:-/tmp}/mdview-raw.$$ out
  command rm -f $flag
  out=$(fd -e md -e markdown --hidden --exclude .git . "$1" |
    fzf --query="$2" --prompt='md> ' --expect=ctrl-e \
        --header='Ctrl-R: rendered ⇄ raw · Enter: read · Ctrl-E: edit in nvim' \
        --preview="mdview \$([[ -e $flag ]] && echo --raw) --width \$FZF_PREVIEW_COLUMNS -- {}" \
        --preview-window='right,65%' \
        --bind="ctrl-r:execute-silent([[ -e $flag ]] && command rm -f $flag || touch $flag)+refresh-preview")
  local rc=$?; command rm -f $flag; (( rc )) && return rc
  local -a l=("${(@f)out}")
  if [[ $l[1] == ctrl-e ]]; then ${EDITOR:-nvim} "$l[2]" </dev/tty; else print -r -- "$l[2]"; fi
}

# === Images ===
alias img='imgview'                    # show images IN the terminal (Ghostty/kitty/WezTerm): img a.png b.jpg  (--width 60)
# open images in the GUI viewer (Loupe), detached from the shell: imgo pic.png
imgo() { local f; for f in "$@"; do $_god_opener "$f" &>/dev/null &! done }
# pick an image below here and show it in the terminal: imgf [dir]
imgf() {
  local prev='file -b {}'
  (( $+commands[chafa] )) && prev='chafa --size=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES} {}'
  local f; f=$(fd -e png -e jpg -e jpeg -e gif -e webp -e bmp -e tif -e tiff . "${1:-.}" |
    fzf --prompt='img> ' --preview="$prev" --preview-window='right,60%') && imgview "$f"
}

# === Documents ===
# flip through a PDF IN the terminal as page images; n/p or →/← to turn, q quits: pdfv file.pdf [page]
pdfv() {
  local f=$1 p=${2:-1} n tmp k
  n=$(pdfinfo -- "$f" 2>/dev/null | awk '/^Pages:/{print $2}')
  [[ -z $n ]] && { echo "pdfv: can't read '$f'" >&2; return 1 }
  tmp=$(mktemp -d)
  while true; do
    (( p < 1 )) && p=1; (( p > n )) && p=$n
    print -n '\e[2J\e[3J\e[H'                                 # clear screen + scrollback (drops old images)
    pdftoppm -png -r 110 -f $p -l $p -singlefile -- "$f" $tmp/page && imgview --no-caption $tmp/page.png
    print -P "%F{8}${f:t}  ·  page %B$p/$n%b  ·  n/→ next  p/← prev  g first  G last  t text  o open in app  q quit%f"
    read -sk1 k
    [[ $k == $'\e' ]] && { read -sk2 k; [[ $k == '[C' ]] && k=n; [[ $k == '[D' ]] && k=p }
    case $k in
      n|' '|j) (( p++ )) ;;  p|b|k) (( p-- )) ;;  g) p=1 ;;  G) p=$n ;;
      t) pdft "$f"; ;;  o) pdfo "$f" ;;  *) break ;;
    esac
  done
  command rm -rf $tmp
}
# read a PDF as text (keeps the layout) in a pager: pdft file.pdf
pdft() { pdftotext -layout -- "$1" - | less -RF }
# open a PDF in the PDF app (Papers): pdfo file.pdf
pdfo() { $_god_opener "$1" &>/dev/null &! }
# read a Word doc (.docx/.doc/.odt) rendered IN the terminal: docv file.docx  (--raw = markdown source)
docv() {
  [[ $1 == --raw ]] && { docview "$2" | mdview --raw - | less -RF; return }
  docview "$1" | mdview - | less -RF
}
# open a document in LibreOffice: doco file.docx
doco() { if (( $+commands[libreoffice] )); then libreoffice "$@" &>/dev/null &! else $_god_opener "$1" &>/dev/null &! fi }
# view ANY file in the terminal, picking the viewer by type (md, image, pdf, docx, json, code…): v file  (no file = fuzzy pick with preview)
v() {
  local f=$1
  if [[ -z $f ]]; then
    f=$(fd --type f --hidden --exclude .git . | fzf --prompt='view> ' \
          --preview='vpreview {} $FZF_PREVIEW_COLUMNS' --preview-window='right,60%') || return
  fi
  [[ -d $f ]] && { l "$f"; return }
  case ${f:e:l} in
    md|markdown)                      mdv "$f" ;;
    png|jpg|jpeg|gif|webp|bmp|tif|tiff) imgview "$f" ;;
    pdf)                              pdfv "$f" ;;
    docx|doc|odt|rtf)                 docv "$f" ;;
    json)                             jq -C . "$f" | less -RF ;;
    *)                                bat -- "$f" ;;
  esac
}

# === Lint & security ===
# SBOM (CycloneDX via syft) + package table; saved as ./sbom.cdx.json: sbom [dir|image]
sbom() {
  local t=${1:-.}
  syft -q "$t" -o table -o cyclonedx-json=sbom.cdx.json | less -FS
  echo "saved: ./sbom.cdx.json  ·  vulns in it: vulns sbom:./sbom.cdx.json"
}
# known vulnerabilities (grype), worst first, in a dir, image or SBOM: vulns [dir|image|sbom:file] [--only-fixed]
vulns() { local t=${1:-.}; [[ -d $t ]] && t="dir:$t"; grype -q "$t" --sort-by severity "${@:2}" | less -FS }
# lint every Dockerfile/Containerfile in the repo (hadolint): dlint [files…]
dlint() {
  local -a f=("$@"); (( $#f )) || f=(${(f)"$(fd -t f -H -E .git -g '{Dockerfile,Containerfile,*.Dockerfile,*.dockerfile,Dockerfile.*,Containerfile.*}')"})
  (( $#f )) || { echo "no Dockerfiles here"; return }
  hadolint "${f[@]}" && print -P "%F{green}✓ ${#f} Dockerfile(s) clean%f"
}
# lint every shell script (shellcheck; .sh/.bash plus sh/bash shebangs): shlint [files…]
shlint() {
  local -a f=("$@")
  (( $#f )) || f=(${(fu)"$(fd -t f -H -E .git -E node_modules -e sh -e bash; rg -l -m1 --hidden -g '!.git' -g '!node_modules' '\A#!\S*\b(env\s+)?(ba|da)?sh\b' 2>/dev/null)"})
  (( $#f )) || { echo "no shell scripts here"; return }
  shellcheck -x "${f[@]}" && print -P "%F{green}✓ ${#f} script(s) clean%f"
}
# validate .gitlab-ci.yml against GitLab (glab, needs login): cilint [file]
cilint() { glab ci lint "${1:-.gitlab-ci.yml}" }
# every linter that applies here: Dockerfiles, shell scripts, GitLab CI
lintall() {
  local rc=0
  print -P "%B── Dockerfiles%b"; dlint || rc=1
  print -P "%B── Shell scripts%b"; shlint || rc=1
  [[ -f .gitlab-ci.yml ]] && { print -P "%B── GitLab CI%b"; cilint || rc=1 }
  return rc
}

# === Shell ===
alias reload='exec zsh'               # restart the shell, picking up config changes
alias zshrc='${EDITOR:-nvim} ~/.zshrc && exec zsh'     # edit .zshrc, then reload
alias zgod='${EDITOR:-nvim} ~/.zsh/god.zsh && exec zsh' # edit these shortcuts, then reload
alias ahelp='zhelp'                   # old name for zhelp

# === Keys ===
# key: F1 :: open zhelp (this list); Enter puts the pick on your prompt
# key: Ctrl-R :: fuzzy search history
# key: Ctrl-T :: fuzzy pick a file, insert its path
# key: Alt-C :: fuzzy cd into a subdirectory
# key: Alt-Z :: fuzzy jump to any dir you've visited (zoxide)
# key: Tab :: completion menu with fzf + preview (, and . switch groups)
# key: Ctrl-Space :: accept the grey autosuggestion
# key: → / End :: accept the grey autosuggestion
# key: Up / Down :: history search on what you've typed so far
# key: Esc Esc :: put sudo in front of the current/last command
# key: Ctrl-X Ctrl-E :: edit the command line in nvim
# key: Ctrl-Z :: on an empty prompt: bring the suspended job back (fg)
# key: Alt-. :: insert the last argument of the previous command
# key: Ctrl-U / Ctrl-K :: delete to start / end of line
# key: Ctrl-W / Alt-D :: delete word back / forward
# key: Ctrl-A / Ctrl-E :: jump to start / end of line

_god_fg_toggle() { if (( $#BUFFER == 0 )); then BUFFER=fg; zle accept-line; else zle push-input; fi }
zle -N _god_fg_toggle && bindkey '^Z' _god_fg_toggle

_god_zi_widget() { zle -I; zi </dev/tty; zle reset-prompt }
zle -N _god_zi_widget && bindkey '^[z' _god_zi_widget

# FZF everywhere: fd for listing, bat/eza previews, nicer layout
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
export FZF_DEFAULT_OPTS='--height=60% --layout=reverse --border=rounded --info=inline-right --bind=ctrl-/:toggle-preview'
export FZF_CTRL_T_COMMAND=$FZF_DEFAULT_COMMAND
export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:300 {} 2>/dev/null || eza --tree --level=2 --icons=always --color=always {}'"
export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'
export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --icons=always --color=always {}'"
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --icons=always --color=always $realpath'

source ~/.zsh/zhelp.zsh
