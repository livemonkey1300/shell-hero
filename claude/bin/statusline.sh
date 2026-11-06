#!/bin/sh
# Statusline: model · repo@branch · dirty · parked count
# Exists because time-blindness and context-switching are cheaper to fix with a
# persistent ambient readout than with a command you have to remember to run.
input=$(cat)
model=$(printf '%s' "$input" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("model",{}).get("display_name","?"))' 2>/dev/null)
dir=$(printf '%s' "$input" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("workspace",{}).get("current_dir",""))' 2>/dev/null)
cd "$dir" 2>/dev/null || cd "$HOME"

repo=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
branch=$(git branch --show-current 2>/dev/null)
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
parked=$(grep -c '^## ' "$HOME/.claude/parked.md" 2>/dev/null || echo 0)

out="\033[2m$model\033[0m"
[ -n "$repo" ] && out="$out \033[36m$repo\033[0m"
[ -n "$branch" ] && out="$out \033[35m@$branch\033[0m"
[ "$dirty" -gt 0 ] 2>/dev/null && out="$out \033[33m●$dirty\033[0m"
[ "$parked" -gt 0 ] 2>/dev/null && out="$out \033[2m│\033[0m \033[34m⚑$parked\033[0m"
printf "$out"
