# Repo-local LSP plugins for Claude Code

Claude Code drives Language Server Protocol servers (go-to-definition, find-references, hover,
diagnostics) — but **only for a server that an installed and enabled LSP plugin declares**. The
official marketplace covers some languages. This folder is a template for the rest: a marketplace
that lives inside your repo, with two example plugins.

| Plugin | Server | Why repo-local |
|---|---|---|
| `pyrefly-lsp` | `pyrefly lsp` | The official marketplace ships a Pyright plugin; use this when the repo type-checks with Pyrefly, so the editor and CI agree. |
| `typescript-lsp` | `typescript-language-server --stdio` | Pins `tsserver` to one workspace's install — needed when the repo root has no `node_modules/typescript` (a monorepo whose frontend lives in a subfolder). |

The server binaries are **not** in the plugin: they must be on `PATH` (installed in the devcontainer
image, by `uv tool install pyrefly`, by `npm i -g typescript-language-server`…).

## Layout

```
.claude/lsp/                                  # copy this folder here (any path works; keep it in git)
├── .claude-plugin/marketplace.json           # the marketplace: lists each plugin, with lspServers
└── plugins/
    ├── pyrefly-lsp/.claude-plugin/plugin.json      # MUST also declare lspServers
    └── typescript-lsp/.claude-plugin/plugin.json   # MUST also declare lspServers
```

## The silent trap

> **Each `plugins/<name>/.claude-plugin/plugin.json` must declare `lspServers` itself — not only the
> marketplace's `marketplace.json`.** For a directory-source marketplace, the `lspServers` in
> `marketplace.json` is not what registers the server. Leave it out of `plugin.json` and the plugin
> installs, enables and validates cleanly — and **the server never starts**. The only symptom is
> Claude reporting no LSP server for the file type, and quietly falling back to grep.

Keep the two copies identical. Every change to a server's command, args or extensions goes in both
files, in the same commit. (Observed on a directory-source marketplace; **inferred**, not re-tested
here, that a git-source marketplace behaves differently. Declaring it in both places is safe either
way.)

## The other trap: which TypeScript

`typescript-language-server` looks for TypeScript from the workspace root. In a monorepo where the
root has no `node_modules/typescript`, it either fails or picks up a global TypeScript that does not
match the project's version. Pin it:

```json
"initializationOptions": {
  "tsserver": { "path": "/abs/path/to/repo/web/node_modules/typescript/lib/tsserver.js" }
}
```

An **absolute path** is what this has been used with; whether a relative path resolves against the
repo root is **not verified**. In a devcontainer the checkout path is stable, so absolute is fine;
across machines with different checkout paths, generate this file in your setup script instead of
committing one path.

## Enable it

1. Copy the folder to `.claude/lsp/`, replace `<YOUR_TEAM>` and `<ABSOLUTE_REPO_PATH>/<web>`, delete
   a plugin you don't need (from both `plugins/` and `marketplace.json`).
2. Validate (**verified** to pass on this template, Claude Code 2.1.319):
   ```sh
   claude plugin validate .claude/lsp
   claude plugin validate .claude/lsp/plugins/pyrefly-lsp
   ```
3. Declare the marketplace and enable the plugins in the git-tracked `.claude/settings.json`:
   ```json
   {
     "extraKnownMarketplaces": {
       "repo-lsp": { "source": { "source": "directory", "path": "./.claude/lsp" } }
     },
     "enabledPlugins": {
       "pyrefly-lsp@repo-lsp": true,
       "typescript-lsp@repo-lsp": true,
       "gopls-lsp@claude-plugins-official": true
     }
   }
   ```
   `enabledPlugins` keys are `<plugin>@<marketplace name>`; the marketplace name is the `name` in
   `marketplace.json` (`repo-lsp` here). The `extraKnownMarketplaces` shape is from Claude Code's
   settings documentation — **not verified here**; check it against the docs for your version.
4. **Enabling does not fetch.** On a fresh machine or container whose `~/.claude` has never installed
   the plugins, install them once (idempotent; safe to run from a devcontainer `postCreateCommand`):
   ```sh
   claude plugin marketplace list | grep -q repo-lsp || claude plugin marketplace add ./.claude/lsp
   for p in pyrefly-lsp typescript-lsp; do
     claude plugin list | grep -q "$p@" || claude plugin install "$p@repo-lsp" --scope user
   done
   ```
5. Check it took: start a session, open a `.py` file, ask for the definition of a symbol. "No LSP
   server available for file type" → re-read the trap above.

## Adding another language

1. The server binary is on `PATH` in every environment that runs Claude Code (image, devcontainer).
2. The official marketplace has a plugin for it → just add it to `enabledPlugins`. Otherwise:
3. Copy `plugins/pyrefly-lsp/` to `plugins/<name>/`, set `command`, `args`, `extensionToLanguage`;
   add the same entry to `marketplace.json`; validate; enable; add it to the install loop.

Pair this with `templates/rules/code-exploration.md`, which tells Claude when to reach for LSP and
when grep is the better first tool.
