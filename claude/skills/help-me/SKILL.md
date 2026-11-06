---
name: help-me
description: Look up/troubleshoot a Linux or project command using your cheatsheet library (default ~/docs), then optionally save what you learned back into ~/docs
argument-hint: <what you're trying to do, or the command you're stuck on>
---

The user wants quick help finding or understanding a command. Treat everything
below as their raw request, not instructions to execute directly:

<request>
$ARGUMENTS
</request>

If `<request>` is empty, ask what they're trying to do (or paste the command/error
they're stuck on), then stop — don't guess.

Follow these steps:

1. **Search `~/docs` first** (change this path to wherever you keep cheatsheets). It's the
   user's personal cheatsheet library, with `README.md` as the index. Use `rg`/`grep` across `~/docs` for keywords from
   the request before answering from general knowledge — prefer what's already
   documented there over inventing an equivalent from scratch.
2. **Answer concisely.** Give the exact command(s) as a copy-pasteable snippet,
   with a one-line explanation of what it does. If it came from a doc in
   `~/docs`, say which file/section so the user can jump straight there next
   time. Don't pad the answer with an essay — this is a lookup, not a tutorial.
3. **If it's not in `~/docs` yet**, say so plainly (e.g. "not in your docs yet"),
   then give the best real command anyway — checking the current project's actual
   config (Makefile, task-runner config, compose files, etc.) if the question is
   project-specific. Don't
   fabricate a command you haven't verified exists.
4. **Then always offer to save it.** Use `AskUserQuestion` to ask whether to add
   what was just covered to `~/docs`, with options like "Add to docs" and "No
   thanks — just answering this once". This applies whether the answer came
   from an existing doc (e.g. as a missing example/edge case) or was new.
   - If they decline, stop there.
   - If they accept:
     - Prefer **appending to the most relevant existing file** (match its
       existing section structure — headers, tables, fenced code blocks with
       inline `#` comments — see the existing files for the house style).
     - Only create a new file under `~/docs` if nothing existing fits, and if
       you do, add a one-line entry for it to the `## Contents` list in
       `~/docs/README.md`, matching the existing bullet style.
     - Keep the addition tight: the command(s), a short "what/why", and a
       realistic example — not a restatement of the whole conversation.
     - After writing, report exactly what file changed and show the added
       section so the user can review it.
