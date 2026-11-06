#!/usr/bin/env bash
# shell-hero installer — Fedora/RHEL, Debian/Ubuntu/Mint/Pop (and WSL), Arch,
# openSUSE, macOS. Safe to re-run: skips what's there, backs up what it replaces.
#
#   ./install.sh                 packages + oh-my-zsh + plugins + link configs
#   ./install.sh --no-packages   only oh-my-zsh, plugins and configs (no sudo)
#   ./install.sh --copy          copy configs instead of symlinking to this repo
#   ./install.sh --no-chsh       don't make zsh your login shell
#
# Symlinks (default) mean `git pull` in this repo updates your shell. --copy
# gives you files you can edit freely without touching the repo.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DO_PKGS=1 MODE=link DO_CHSH=1
for a in "$@"; do
  case $a in
    --no-packages) DO_PKGS=0 ;;
    --copy)        MODE=copy ;;
    --no-chsh)     DO_CHSH=0 ;;
    -h|--help)     sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

info() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
STAMP=$(date +%Y%m%d-%H%M%S)
MISSING=()

# ---------------------------------------------------------------- OS detection
OS=unknown
if [[ $(uname -s) == Darwin ]]; then OS=macos
elif [[ -r /etc/os-release ]]; then
  . /etc/os-release
  case " ${ID:-} ${ID_LIKE:-} " in
    *" fedora "*|*" rhel "*|*" centos "*) OS=fedora ;;
    *" debian "*|*" ubuntu "*)           OS=debian ;;
    *" arch "*)                          OS=arch ;;
    *" suse "*|*" opensuse "*)           OS=suse ;;
  esac
fi
grep -qi microsoft /proc/version 2>/dev/null && WSL=1 || WSL=0
info "Detected: $OS$( ((WSL)) && echo ' (WSL)')"

# ---------------------------------------------------------------- packages
# One logical tool per line: "tool-we-check  fedora  debian  arch  suse  brew"
# '-' = not packaged there (a fallback below handles some of these).
PKGS=$(cat <<'EOF'
zsh       zsh            zsh             zsh            zsh            zsh
git       git            git             git            git            git
curl      curl           curl            curl           curl           curl
fzf       fzf            fzf             fzf            fzf            fzf
rg        ripgrep        ripgrep         ripgrep        ripgrep        ripgrep
fd        fd-find        fd-find         fd             fd             fd
bat       bat            bat             bat            bat            bat
eza       eza            eza             eza            eza            eza
zoxide    zoxide         zoxide          zoxide         zoxide         zoxide
nvim      neovim         neovim          neovim         neovim         neovim
jq        jq             jq              jq             jq             jq
btop      btop           btop            btop           btop           btop
lazygit   lazygit        -               lazygit        lazygit        lazygit
yazi      -              -               yazi           yazi           yazi
tldr      tldr           tldr            tldr           tealdeer       tlrc
chafa     chafa          chafa           chafa          chafa          chafa
pdftotext poppler-utils  poppler-utils   poppler        poppler-tools  poppler
rich      python3-rich   python3-rich    python-rich    python3-rich   -
pillow    python3-pillow python3-pil     python-pillow  python3-Pillow -
EOF
)
case $OS in fedora) COL=2 ;; debian) COL=3 ;; arch) COL=4 ;; suse) COL=5 ;; macos) COL=6 ;; *) COL=0 ;; esac

pkg_install() {
  case $OS in
    fedora) sudo dnf install -y "$@" ;;
    debian) sudo apt-get install -y "$@" ;;
    arch)   sudo pacman -S --needed --noconfirm "$@" ;;
    suse)   sudo zypper --non-interactive install "$@" ;;
    macos)  brew install "$@" ;;
  esac
}

python_has() { python3 -c "import $1" 2>/dev/null; }

if (( DO_PKGS )); then
  if (( COL == 0 )); then
    warn "Unknown OS — skipping packages. Install by hand: see docs/INSTALL.md"
  else
    if [[ $OS == macos ]] && ! have brew; then
      info "Installing Homebrew"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
    fi
    [[ $OS == debian ]] && sudo apt-get update -qq
    [[ $OS == fedora ]] && ! rpm -q dnf-plugins-core >/dev/null 2>&1 && sudo dnf install -y dnf-plugins-core || true

    # Clipboard + trash, per platform
    if [[ $OS != macos ]] && (( ! WSL )); then
      if [[ -n ${WAYLAND_DISPLAY:-} ]]; then extra=(wl-clipboard); else extra=(xclip); fi
      extra+=(trash-cli)
    else extra=(); fi

    todo=()
    while read -r tool fe de ar su br; do
      [[ -z $tool ]] && continue
      cols=("$tool" "$fe" "$de" "$ar" "$su" "$br"); pkg=${cols[$((COL-1))]}
      case $tool in
        rich|pillow) python_has "$( [[ $tool == pillow ]] && echo PIL || echo rich)" && continue ;;
        fd)  { have fd || have fdfind; } && continue ;;
        bat) { have bat || have batcat; } && continue ;;
        *)   have "$tool" && continue ;;
      esac
      [[ $pkg == - ]] && { MISSING+=("$tool"); continue; }
      todo+=("$pkg")
    done <<<"$PKGS"
    todo+=(${extra[@]+"${extra[@]}"})

    if (( ${#todo[@]} )); then
      info "Installing: ${todo[*]}"
      # all at once is fast; if one name is unknown on this release, fall back to one by one
      pkg_install "${todo[@]}" 2>/dev/null || for p in "${todo[@]}"; do
        pkg_install "$p" >/dev/null 2>&1 && echo "   ok   $p" || { echo "   miss $p"; MISSING+=("$p"); }
      done
    else
      info "All packages already present"
    fi

    # Debian/Ubuntu name clashes: expose fd and bat under their real names
    mkdir -p "$HOME/.local/bin"
    have fdfind && ! have fd  && ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    have batcat && ! have bat && ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"

    # lazygit has no Debian/Ubuntu package on older releases: official binary
    if ! have lazygit && [[ $OS != macos ]]; then
      arch=$(uname -m); case $arch in x86_64) arch=x86_64 ;; aarch64|arm64) arch=arm64 ;; esac
      v=$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p')
      if [[ -n $v ]]; then
        info "Installing lazygit $v from GitHub"
        tmp=$(mktemp -d)
        curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v$v/lazygit_${v}_Linux_${arch}.tar.gz" | tar -xz -C "$tmp" lazygit
        install -m 755 "$tmp/lazygit" "$HOME/.local/bin/lazygit"; rm -rf "$tmp"
        MISSING=(${MISSING[@]+"${MISSING[@]/lazygit}"})
      fi
    fi

    # fzf: the config needs >= 0.48 (fzf --zsh, inline-right). Old distro builds → upstream.
    fzf_ok() {
      have fzf || return 1
      local v; v=$(fzf --version | cut -d' ' -f1); local maj=${v%%.*} rest=${v#*.}; local min=${rest%%.*}
      (( maj > 0 || min >= 48 ))
    }
    if ! fzf_ok; then
      info "fzf missing or older than 0.48 — installing upstream into ~/.fzf"
      [[ -d ~/.fzf ]] || git clone -q --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
      ~/.fzf/install --bin >/dev/null
      ln -sf ~/.fzf/bin/fzf "$HOME/.local/bin/fzf"
    fi

    # Python libs for mdview/imgview when the distro doesn't package them (and macOS)
    for m in rich:rich PIL:pillow; do
      python_has "${m%%:*}" || pip3 install --user --quiet "${m##*:}" 2>/dev/null \
        || pip3 install --user --quiet --break-system-packages "${m##*:}" 2>/dev/null \
        || MISSING+=("python:${m##*:}")
    done
  fi
fi

have zsh || { warn "zsh is not installed — install it and re-run"; exit 1; }
have git || { warn "git is not installed — install it and re-run"; exit 1; }

# ---------------------------------------------------------------- oh-my-zsh + plugins
if [[ ! -d $HOME/.oh-my-zsh ]]; then
  info "Installing oh-my-zsh"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi
ZC=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
clone() { [[ -d $2 ]] || { info "  + ${2##*/}"; git clone -q --depth 1 "$1" "$2"; }; }
info "oh-my-zsh plugins and theme"
clone https://github.com/romkatv/powerlevel10k.git                   "$ZC/themes/powerlevel10k"
clone https://github.com/zsh-users/zsh-autosuggestions               "$ZC/plugins/zsh-autosuggestions"
clone https://github.com/zsh-users/zsh-syntax-highlighting           "$ZC/plugins/zsh-syntax-highlighting"
clone https://github.com/zsh-users/zsh-history-substring-search      "$ZC/plugins/zsh-history-substring-search"
clone https://github.com/zsh-users/zsh-completions                   "$ZC/plugins/zsh-completions"
clone https://github.com/Aloxaf/fzf-tab                              "$ZC/plugins/fzf-tab"
clone https://github.com/MichaelAquilina/zsh-you-should-use          "$ZC/plugins/you-should-use"

# ---------------------------------------------------------------- link configs
place() {  # place SRC DEST — symlink (or copy), backing up a real file in the way
  local src=$1 dst=$2
  mkdir -p "$(dirname "$dst")"
  if [[ -L $dst && $(readlink "$dst") == "$src" ]]; then return; fi
  if [[ -e $dst || -L $dst ]]; then mv "$dst" "$dst.bak-$STAMP"; echo "   backup $dst → $dst.bak-$STAMP"; fi
  if [[ $MODE == link ]]; then ln -s "$src" "$dst"; else cp -R "$src" "$dst"; fi
  echo "   $MODE  $dst"
}
info "Placing configs ($MODE)"
place "$REPO/zsh/zshrc"    "$HOME/.zshrc"
place "$REPO/zsh/p10k.zsh" "$HOME/.p10k.zsh"
for f in "$REPO"/zsh/*.zsh; do
  [[ ${f##*/} == p10k.zsh ]] && continue
  place "$f" "$HOME/.zsh/${f##*/}"
done
for f in "$REPO"/zsh/completions/*; do place "$f" "$HOME/.zsh/completions/${f##*/}"; done
for f in "$REPO"/bin/*; do chmod +x "$f"; place "$f" "$HOME/.local/bin/${f##*/}"; done
[[ -d $REPO/guides ]] && place "$REPO/guides" "$HOME/.local/share/shell-hero/guides"

# ---------------------------------------------------------------- login shell
if (( DO_CHSH )) && [[ ${SHELL##*/} != zsh ]]; then
  info "Making zsh your login shell"
  chsh -s "$(command -v zsh)" || warn "chsh failed — run: chsh -s $(command -v zsh)"
fi

# ---------------------------------------------------------------- report
# shellcheck disable=SC2207  # entries are single words
MISSING=($(printf '%s\n' ${MISSING[@]+"${MISSING[@]}"} | grep -v '^$' | sort -u || true))
echo
info "Done. Start it with: exec zsh   — then press F1 for every shortcut."
(( ${#MISSING[@]} )) && warn "Not installed (optional, see docs/INSTALL.md): ${MISSING[*]}"
echo "   Secrets and machine-only settings go in ~/.zshrc.local (never in the repo)."
echo "   First run of Powerlevel10k: the bundled ~/.p10k.zsh is used; 'p10k configure' to redo it."
