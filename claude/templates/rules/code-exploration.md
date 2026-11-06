---
paths:
  - "<src>/**"
  - "<services>/**"
  - "<libs>/**"
---

<!--
  A rule for repos with a code-graph MCP server and/or LSP plugins wired into Claude Code.
  Copy to .claude/rules/code-exploration.md and fill the <PLACEHOLDERS>. Scope `paths:` to the
  source trees the tools cover (the rule loads when the session touches them); delete the `paths:`
  block to load it in every session instead. Delete the tiers you don't have (no code-graph server →
  drop tier 1; no LSP plugins → drop tier 2; neither → delete the rule: grep-first is the default).
  LSP plugins: see claude/lsp/ in this kit.
-->

# Code exploration: which tool, in which order

For code-shaped questions ("where is X defined", "who calls X", "what breaks if I change Y", "how is
this package structured"), use the tools in this order — **but only inside each tool's coverage**.
Outside it, grep/Read is the right first tool, not a last resort.

## 1. Code-graph MCP — first, inside its indexed scope

Indexed: `<src/>`, `<services/>`, `<libs/>`. **Not indexed** (skip straight to grep): `<infra/>`,
`<migrations/>`, `<charts/>`, docs, compose files, CI config.

**Never hardcode the project name.** List the indexed projects first (`<list_projects>`) and pick
from the result: the name is usually derived from the checkout path, which differs between clones,
worktrees and containers. A guessed name returns nothing, silently, and sends you to grep thinking
the graph is empty.

| Question shape | Tool |
|---|---|
| Which project, and is the index fresh | `<list_projects>`, then `<index_status>` |
| Where is X defined / used; find implementations | `<search_graph>` / `<search_code>` |
| Who calls X; call chains across packages or services | `<trace_path>` |
| Package structure, dependency graph, module boundaries | `<get_architecture>` |
| Blast radius of the current diff | `<detect_changes>` |
| Read one symbol once you have its qualified name | `<get_code_snippet>` |

## 2. LSP — for exact, single-symbol answers on the live file

Covers `<Go, Python, TypeScript>` only — no SQL, YAML, shell, Terraform, Helm, Markdown, JSON.
Once you have a file, line and column (from a grep or graph hit): `goToDefinition`,
`findReferences`, `goToImplementation`, `hover`, `incomingCalls`/`outgoingCalls`,
`documentSymbol`, `workspaceSymbol`.

**Prefer LSP over the graph for any file edited in this session** (by you or a subagent): LSP reads
the file on disk; the graph is keyed on the last indexed commit and may not have seen the edit.

## 3. grep / Read / Glob — first choice outside 1 and 2

Use them first when: the path is outside both tools' coverage (infra, config, SQL, YAML, shell,
docs); the check is a one-off string search; you need a whole file, not a symbol; or tiers 1–2
returned nothing or errored (say so — an empty graph answer is not evidence of absence).

## Why this order

The graph follows call and import edges grep cannot see and answers architecture questions grep
cannot answer at all; LSP is type-aware ground truth on the live file; grep is exact, current and
covers everything, and is the right tool wherever the other two have no data.
