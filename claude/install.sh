#!/usr/bin/env bash
# Install the Claude Code kit (skills, agents, helper scripts) — deterministic and non-destructive.
# Claude runs this during setup (see BOOTSTRAP.md); people can run it by hand too.
#
#   claude/install.sh --list                    packs, items, and what's already installed
#   claude/install.sh --pack focus,engineering  install packs into ~/.claude
#   claude/install.sh --all                     every pack
#   claude/install.sh --all --project ~/code/x  install into ~/code/x/.claude (shared with that repo)
#   claude/install.sh --all --dry-run           show what would happen, change nothing
#   claude/install.sh --all --update            also replace items that differ (old copy → .kit-backups/)
#   claude/install.sh --check                   repo hygiene: every skill/agent belongs to a pack
#
# Never overwrites silently: an item that exists and differs is skipped and reported,
# unless --update, which first moves it to <target>/.kit-backups/<timestamp>/ (outside the folders
# Claude loads, so a backed-up skill never shows up twice).
set -euo pipefail

KIT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STAMP=$(date +%Y%m%d-%H%M%S)

# ---------------------------------------------------------------- packs (the one place to edit)
pack_items() {
  case $1 in
    focus)       echo "skill:park skill:reload skill:loose-ends skill:what-now skill:decide skill:pomo skill:pomo-done skill:pomo-review bin:pomo bin:statusline.sh" ;;
    writing)     echo "skill:fix skill:fix-org skill:fix-org-src skill:fix-org-ask skill:help-me" ;;
    engineering) echo "skill:start-work skill:add-feature skill:technical-plan skill:rebase skill:fast-commit skill:pr-review skill:pr-feedback skill:change-brief skill:edit-prompt skill:project-setup" ;;
    workflow)    echo "skill:ticket-writer skill:plan-to-tickets skill:implement-subtask skill:story-orchestrator skill:open-pr skill:expert-panel agent:developer agent:reviewer agent:technical-writer agent:product-owner" ;;
    roles)       echo "agent:principal-architect agent:security-architect agent:tech-researcher agent:generalist-oracle agent:kubernetes-helm-engineer agent:devops-ci-engineer agent:supply-chain-engineer agent:cloud-architect agent:sre-observability-engineer agent:container-security-reviewer agent:backend-engineer agent:frontend-engineer agent:integration-engineer agent:test-quality-engineer agent:llm-feature-engineer agent:platform-library-engineer agent:docker-build-expert agent:vscode-extension-ux-reviewer agent:go-reviewer" ;;
    business)    echo "skill:finance-ops skill:sales-outreach skill:brand-voice skill:support-triage skill:legal-drafts agent:business-advisor" ;;
    *) return 1 ;;
  esac
}
PACKS="focus writing engineering workflow roles business"
pack_blurb() {
  case $1 in
    focus)       echo "working memory: park, reload, decide, pomodoro, status line" ;;
    writing)     echo "grammar fix and message structuring, cheatsheet lookup" ;;
    engineering) echo "start work, add a feature, plan, rebase, commit, review, change brief, set up a project" ;;
    workflow)    echo "the agentic loop: ticket → plan → implement → review → PR, panel of experts" ;;
    business)    echo "run a small company in Canada: finance and GST/HST/QST, CASL-safe sales, brand voice, support, legal drafts" ;;
    roles)       echo "19 read-only specialist advisers (architecture, security, k8s, CI, backend, frontend…)" ;;
  esac
}

# ---------------------------------------------------------------- args
MODE="" SEL="" TARGET="$HOME/.claude" DRY=0 UPDATE=0 PROJECT=0
while (( $# )); do
  case $1 in
    --list)    MODE=list ;;
    --check)   MODE=check ;;
    --all)     MODE=install; SEL=$PACKS ;;
    --pack)    MODE=install; SEL=$(echo "$2" | tr ',' ' '); shift ;;
    --project) TARGET="$(cd "$2" && pwd)/.claude"; PROJECT=1; shift ;;
    --dry-run) DRY=1 ;;
    --update)  UPDATE=1 ;;
    -h|--help|"") sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
[[ -z $MODE ]] && { sed -n '2,15p' "$0"; exit 0; }

src_of() { local k=${1%%:*} n=${1#*:}
  case $k in skill) echo "$KIT/skills/$n" ;; agent) echo "$KIT/agents/$n.md" ;; bin) echo "$KIT/bin/$n" ;; esac; }
dst_of() { local k=${1%%:*} n=${1#*:}
  case $k in skill) echo "$TARGET/skills/$n" ;; agent) echo "$TARGET/agents/$n.md" ;; bin) echo "$TARGET/bin/$n" ;; esac; }
status_of() {  # new | same | differs | missing-source
  local s d; s=$(src_of "$1"); d=$(dst_of "$1")
  [[ -e $s ]] || { echo missing-source; return; }
  [[ -e $d ]] || { echo new; return; }
  diff -rq "$s" "$d" >/dev/null 2>&1 && echo same || echo differs
}

# ---------------------------------------------------------------- check
if [[ $MODE == check ]]; then
  all=" "; for p in $PACKS; do all+="$(pack_items "$p") "; done
  rc=0
  for d in "$KIT"/skills/*/; do n=$(basename "$d"); [[ $all == *" skill:$n "* ]] || { echo "not in any pack: skill:$n"; rc=1; }; done
  for f in "$KIT"/agents/*.md; do n=$(basename "$f" .md); [[ $all == *" agent:$n "* ]] || { echo "not in any pack: agent:$n"; rc=1; }; done
  for i in $all; do [[ $(status_of "$i") == missing-source ]] && { echo "pack lists a missing item: $i"; rc=1; }; done
  (( rc )) || echo "ok: every skill and agent is in exactly the packs listed, and every listed item exists"
  exit $rc
fi

# ---------------------------------------------------------------- list
if [[ $MODE == list ]]; then
  echo "target: $TARGET"
  for p in $PACKS; do
    printf '\n\033[1m%s\033[0m — %s\n' "$p" "$(pack_blurb "$p")"
    for i in $(pack_items "$p"); do printf '  %-8s %-34s %s\n' "$(status_of "$i")" "${i#*:}" "(${i%%:*})"; done
  done
  exit 0
fi

# ---------------------------------------------------------------- install
for p in $SEL; do pack_items "$p" >/dev/null || { echo "unknown pack: $p (have: $PACKS)" >&2; exit 2; }; done
echo "target: $TARGET$( ((DRY)) && echo '  (dry run — nothing changes)')"
added=0 same=0 updated=0 skipped=()
for p in $SEL; do
  for i in $(pack_items "$p"); do
    [[ $PROJECT == 1 && ${i%%:*} == bin ]] && continue      # helper scripts are per-user, not per-repo
    s=$(src_of "$i"); d=$(dst_of "$i"); st=$(status_of "$i")
    case $st in
      same) same=$((same+1)) ;;
      new)
        echo "  + ${i#*:}"; added=$((added+1))
        (( DRY )) || { mkdir -p "$(dirname "$d")"; cp -R "$s" "$d"; } ;;
      differs)
        if (( UPDATE )); then
          bk="$TARGET/.kit-backups/$STAMP/${i%%:*}s"
          echo "  ~ ${i#*:}  (old copy → ${bk/#$HOME/\~}/)"; updated=$((updated+1))
          (( DRY )) || { mkdir -p "$bk"; mv "$d" "$bk/"; cp -R "$s" "$d"; }
        else skipped+=("${i#*:}"); fi ;;
      missing-source) echo "  ! ${i#*:} is listed but missing from the kit" >&2 ;;
    esac
  done
done
(( DRY )) || chmod +x "$TARGET"/bin/* 2>/dev/null || true
echo "added $added · unchanged $same · updated $updated · skipped (yours differs) ${#skipped[@]}"
(( ${#skipped[@]} )) && echo "  differs, kept yours: ${skipped[*]}  — rerun with --update to replace (backed up first)"
exit 0
