---
paths:
  - "**/*.sh"
---

<!--
  A scoped rule: copy to .claude/rules/shell-scripts.md. It loads only when the session touches a
  .sh file. Add your repo's other script globs (bin/*, hooks without an extension) to `paths:`.
  Fill the <PLACEHOLDERS>.
-->

# Shell scripts

**POSIX `#!/bin/sh` by default.** Bash (`#!/usr/bin/env bash`) only when the script genuinely needs
a bash feature, **and the reason is a comment in the first lines** (`# bash: needs arrays for the
target list`). Why: a script that runs in an image, CI, or on a minimal host gets `dash`, `ash` or
BusyBox as `sh`, and a bashism there fails at run time, not at review.

`set -eu` at the top. `pipefail` is not POSIX: under `#!/bin/sh`, don't use it — split the pipeline,
or check each stage's status.

## Not in a `#!/bin/sh` script → the POSIX way

| Bashism | Instead |
|---|---|
| `[[ $a == b* ]]` | `[ "$a" = "b" ]`; patterns with `case "$a" in b*) … ;; esac` |
| Arrays: `arr=(a b)`, `"${arr[@]}"` | `set -- a b` and `"$@"`; or a newline-separated string read with `while IFS= read -r x` |
| `local -a`, `local -i`, `declare`, `typeset` | plain variables; scope with a subshell `( … )` where needed |
| `<(cmd)`, `>(cmd)` | a temp file from `mktemp`, removed in a `trap … EXIT` |
| `cmd <<< "$s"` | `printf '%s\n' "$s" \| cmd` |
| `${v^^}`, `${v,,}` | `printf '%s' "$v" \| tr '[:lower:]' '[:upper:]'` |
| `${v/pat/rep}`, `${v:1:3}` | `sed`, `cut`, `awk`; `${v#pre}` / `${v%suf}` are POSIX and fine |
| `function f { … }` | `f() { … }` |
| `echo -e`, `echo -n` | `printf` |
| `source file` | `. file` |
| `$RANDOM`, `$EPOCHSECONDS` | `awk 'BEGIN{srand(); print int(rand()*32768)}'`, `date +%s` |
| `which x` | `command -v x` |
| `&>file` | `>file 2>&1` |

## Before calling a script done

```sh
shfmt -w -i 2 -ci <script>      # take the formatter's output; formatting is never a judgement call
shellcheck <script>             # zero errors and warnings
```

Match the flags CI uses (`<ci format-check command>`). A suppressed check carries its reason inline:
`# shellcheck disable=SC2086  # word-splitting $FLAGS is intended`.

## Structure

- Executed scripts: shebang on line 1, committed executable (`git update-index --chmod=+x`).
- Sourced libraries: `.sh`, no shebang needed, a header comment saying what they provide and how to
  source them; shared helpers live in `<lib/>`.
- Errors to stderr through a `die()`; configuration by environment variable with a default
  (`"${TARGET:-dev}"`). If it needs real argument parsing or data structures, it should not be shell.
