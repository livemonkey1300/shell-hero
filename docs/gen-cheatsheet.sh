#!/usr/bin/env bash
# Regenerate docs/CHEATSHEET.md from the live config (the same index zhelp uses).
# Run from anywhere after the config is installed: docs/gen-cheatsheet.sh
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
zsh -i -c '_zhelp_rows' 2>/dev/null | python3 -I -c '
import sys, collections, re
order = ["god.zsh","zshrc","docker.zsh","k8s.zsh","cloud.zsh","bazel.zsh","dev.zsh","focus.zsh"]
titles = {"god.zsh":"Daily driver — `zsh/god.zsh`","zshrc":"Core — `zsh/zshrc`","docker.zsh":"Docker — `zsh/docker.zsh`",
  "k8s.zsh":"Kubernetes — `zsh/k8s.zsh`","cloud.zsh":"Google Cloud & Terraform — `zsh/cloud.zsh`",
  "bazel.zsh":"Bazel — `zsh/bazel.zsh`","dev.zsh":"Dev tools — `zsh/dev.zsh`","focus.zsh":"Focus & working memory — `zsh/focus.zsh`"}
g = collections.OrderedDict((k, collections.OrderedDict()) for k in order)
for line in sys.stdin:
    p = line.rstrip("\n").split("\t")
    if len(p) != 5 or p[2] == "oh-my-zsh": continue
    kind, name, sec, desc, loc = p
    f = loc.rsplit(":", 1)[0].split("/")[-1].lstrip(".")
    if f not in g: continue
    sec = re.sub(r"^\d+\.\s*", "", sec)
    if sec == "focus.zsh": sec = "Capture, handoff, timers"
    g[f].setdefault(sec, []).append((kind, name, desc))
esc = lambda s: s.replace("|", "\\|")
anchor = lambda t: re.sub(r"[^a-z0-9 -]", "", t.lower()).replace(" ", "-")
out = ["# Cheatsheet", "",
  "Every alias, function and key binding in this config, grouped by file. **Generated from the config itself** (the same index `zhelp` uses), so it matches what you have.", "",
  "> In the shell, press **F1** or run `zhelp` for a fuzzy-searchable version of this page. `zhelp -l docker` prints a filtered list. Oh-my-zsh plugin aliases (the ~240 `g*` git aliases and so on) are in `zhelp` too, but not on this page.", "",
  "Regenerate after changing the config: `docs/gen-cheatsheet.sh`.", ""]
out += ["- [%s](#%s)" % (titles[f].split(" — ")[0], anchor(titles[f])) for f in g if g[f]] + [""]
for f, secs in g.items():
    if not secs: continue
    out += ["## " + titles[f], ""]
    for sec, items in secs.items():
        out += ["### " + sec, "", "| | What it does |", "|---|---|"]
        for kind, name, desc in items:
            n = "<kbd>%s</kbd>" % esc(name) if kind == "key" else "`%s`" % esc(name)
            out.append("| %s | %s |" % (n, esc(desc)))
        out.append("")
print("\n".join(out))
' > "$here/CHEATSHEET.md"
echo "wrote $here/CHEATSHEET.md ($(grep -c '^| ' "$here/CHEATSHEET.md") rows)"
