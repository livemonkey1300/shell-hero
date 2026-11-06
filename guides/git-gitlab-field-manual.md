# Git & GitLab Field Manual

> objects · history · rewrite · recover · glab · REST · GraphQL
> Generated 2026-09-23.

## Contents

- 00 · [Every recommendation, one page](#00-every-recommendation-one-page)
- 01 · [The model underneath](#01-the-model-underneath)
- 02 · [Setup: config, identity, signing](#02-setup-config-identity-signing)
- 03 · [Daily driving](#03-daily-driving)
- 04 · [Rewrite: rebase, pick, revert](#04-rewrite-rebase-pick-revert)
- 05 · [Recover and undo](#05-recover-and-undo)
- 06 · [At scale: worktrees to monorepos](#06-at-scale-worktrees-to-monorepos)
- 07 · [One-screen Git reference](#07-one-screen-git-reference)
- 08 · [glab: install, auth and config](#08-glab-install-auth-and-config)
- 09 · [glab by intent](#09-glab-by-intent)
- 10 · [glab api in depth](#10-glab-api-in-depth)
- 11 · [The REST API with curl](#11-the-rest-api-with-curl)
- 12 · [Scripting and troubleshooting](#12-scripting-and-troubleshooting)

---


<a id="00-every-recommendation-one-page"></a>

## 00 · Every recommendation, one page

*Every default this guide recommends, Git and GitLab alike, with the reason for each. Read this, then read the chapter for whichever line you're about to disagree with.*

### How to read this

**Defaults are for when you have no reason to choose otherwise.** Each line gives one pick and why. Where a line says "close call", the alternative is genuinely defensible and the tiebreaker is named. Chapters 01–07 are Git; chapters 08–12 are glab and the GitLab API.

Everything was checked against **git 2.55** and **glab 1.108** on Fedora 43; glab-specific changes up to **1.119** (latest, 2026-09-22) are noted where they matter. Anything newer, experimental or server-dependent is flagged in its chapter.

### The Git stack

| Decision | Pick | Why | Ch |
|---|---|---|---|
| Conflict markers | **`merge.conflictStyle = zdiff3`** | Shows the base alongside ours and theirs, so you resolve *changes*, not *results*. The highest-value line of config there is | 02, 04 |
| Diff algorithm | **`diff.algorithm = histogram`** | Aligns on unique lines, so you get far fewer "moved the brace" diffs | 02 |
| Repeated conflicts | **`rerere.enabled = true`**, `autoUpdate` off | Replays recorded resolutions but leaves them unstaged, so you review before `git add` | 02, 04 |
| Pull behaviour | **`pull.rebase = true`**. *Close call* | No "Merge branch 'feat' of…" noise on shared feature branches. Tiebreaker: if you often pull on main or release branches, `pull.ff = only` makes accidental local commits an error instead | 02 |
| First push | **`push.autoSetupRemote = true`** | No more `-u origin HEAD` ritual | 02 |
| Force-push | **`--force-with-lease --force-if-includes`**, with `push.useForceIfIncludes = true` | A lease alone is satisfied by an IDE's background fetch and silently clobbers a colleague's commit. Reproduced on 2.55 | 03 |
| Stale remote branches | **`fetch.prune = true`**; leave `fetch.pruneTags` unset | Dead `origin/*` refs disappear. `pruneTags` would also delete your local-only tags | 02 |
| Rebase defaults | **`rebase.autoSquash`, `autoStash`, `updateRefs` = true; `missingCommitsCheck = error`** | Fixups arrange themselves, dirty trees don't block, stacks stay together, and deleting a todo line by accident becomes an error | 02, 04 |
| Branch listing | **`branch.sort = -committerdate`**, `column.ui = auto` | `git branch` shows what you're working on, not an alphabetical wall | 02 |
| Identity | **`user.useConfigOnly = true`** + `includeIf "hasconfig:remote.*.url:…"` | The wrong-email commit becomes impossible, wherever the clone lives | 02 |
| Signing | **SSH signing** (`gpg.format = ssh`) with a FIDO2 `-sk` key | One key type for transport and signing, and no gpg-agent. GitLab verifies SSH signatures (15.7+). GPG only where policy demands OpenPGP | 02 |
| HTTPS credentials | **SSH for Git transport**. For HTTPS: `glab auth git-credential` for GitLab hosts, `libsecret` for the rest | One login covers glab and Git. Never `credential.helper = store` | 02, 08 |
| Pager | **delta**. *Close call* with difftastic | Tiebreaker: delta for anything you page every day; `difft` on demand for refactor and reformat reviews | 02 |
| Switching and restoring | **`switch` / `restore`**, never `checkout` | `checkout` does two unrelated things depending on whether an argument happens to be a path | 03 |
| MR review diff | **`git diff main...HEAD`** (three dots) | Diffs from the merge base, which is what the MR shows. Two dots diffs tip to tip | 03, 07 |
| Cleaning up a branch | **`commit --fixup` + `rebase -i --autosquash`**, `--keep-base` mid-review | Fixes land in the right commit without moving your base or re-running unrelated CI | 04 |
| Stacked MRs | **`rebase --update-refs`**, and `rebase --onto` after a squash-merged parent | Every branch in the stack moves together (verified) | 04 |
| Backports | **fix on main, `cherry-pick -x` to release** | You move exactly one change, and it's traceable. Merging release into main drags in bumps and hacks | 04 |
| Undoing on shared branches | **`git revert`** (`-m 1` for merges) | History only grows, so nobody's clone breaks | 04, 05 |
| Moving a branch | **`reset --keep`** over `reset --hard` | Refuses to run instead of destroying uncommitted edits | 05 |
| Finding a regression | **`bisect run`** with exit 125 on build failure; `--first-parent` on merge-based repos | Unattended, and it finds the MR first and the commit second | 05 |
| History surgery on pushed repos | **`git filter-repo`** on a fresh mirror clone | `git filter-branch`'s own man page warns against using it; BFG is unmaintained | 05 |
| Second checkout | **worktrees**, not stash-and-switch | Separate tree and build cache, same object store | 06 |
| Big-repo clone | **`--filter=blob:none`** (+ `--sparse` for monorepos), or `scalar clone` | Full history for a fraction of the download. Shallow clones cripple `merge-base` and `log` | 06 |
| CI clone depth | **shallow by default; `GIT_DEPTH: 0` only for jobs that need history** (describe, changelog) | Fast builds, and the jobs that need tags still get them | 06 |
| Large binaries | **Git LFS, decided at repo creation** | Migrating later rewrites all history | 06 |
| Vendoring another repo | **neither submodule nor subtree**; use a package, image or Helm dependency | Both have sharp edges. If forced: submodule for large or shared, subtree `--squash` for small and static | 06 |
| Hooks | **config-based hooks (2.55) for personal all-repo checks; `core.hooksPath` for team hooks; CI for anything mandatory** | Hooks are skippable and not cloned. They give fast feedback; they don't enforce anything | 06 |
| Big-repo speed | **per-repo `core.fsmonitor` + `untrackedCache` + `git maintenance start`** | fsmonitor works on Linux in 2.55 (verified). Keep it per-repo: one daemon per repo, and inotify watches are finite | 02, 06 |

### The glab and API stack

The detail, flags and version caveats are in chapters 08–12. At the level of the decision:

| Decision | Pick | Why | Ch |
|---|---|---|---|
| Interactive GitLab work | **glab** | It infers host, project and the current branch's MR or pipeline, so most commands need no arguments | 08, 09 |
| Scripting against GitLab | **`glab api`** | curl that already knows your host and token, and paginates for you. Raw curl only where glab isn't installed or in tools others run | 10, 11 |
| Your own token | **fine-grained PAT with an expiry**, `read_api` for read-only scripts | Least privilege: a read-only token can't delete a branch by mistake. Fine-grained PATs need a recent GitLab (see ch 08) | 08 |
| Automation tokens | **group or project access token** at the lowest role, 90-day expiry, rotated | Survives staff leaving, scoped to the group, and shows in audit logs as a bot | 08 |
| Tokens in pipelines | **`CI_JOB_TOKEN`**, with the target project's allowlist | No stored secret, and it dies with the job | 08, 11 |
| Paginating big lists | **keyset pagination; follow the `Link: rel="next"` header** | Constant cost per page, and it survives the offset cutoff on deep lists | 10, 11 |
| Project references in scripts | **numeric project IDs** | Paths change on rename or transfer; IDs never do | 11 |

### The positions worth arguing about

These are opinions, not consensus. Each comes with its reason so you can overrule it deliberately.

| Position | Reason |
|---|---|
| **Rebase your own branch; never rebase a branch someone else pushes to.** | Rewriting makes new commit IDs. Anyone who has the old ones gets duplicates on their next pull |
| **Curate commits before review rather than squash-merging everything.** | A clean series bisects and blames well, and a squash of 30 WIP commits doesn't. Squash-merge is fine when the MR's commits really are noise |
| **`pull.rebase = true` over merge-pulls.** | "Merge branch 'feat' of gitlab…" commits carry no information and clutter `--first-parent` |
| **Signed commits by default, with a hardware key.** | Signing is only worth anything if the key can't be copied off the laptop. The cost is one touch per commit, and per rewritten commit during a rebase |
| **Stash is for minutes; branches are for days.** | Stashes aren't pushed, are easy to drop, and are anonymous without `-m` |
| **`--force-with-lease` alone is not safe.** | Background fetches satisfy the lease. `--force-if-includes` is the actual safety check |
| **Hooks are convenience, not policy.** | `--no-verify` exists and hooks aren't cloned. Put enforcement in CI and server push rules |
| **Blob-less clones over shallow ones for humans.** | Shallow breaks `merge-base`, `describe`, rebase and `log`. Blob-less keeps all history and fetches contents lazily |
| **Don't set fsmonitor globally.** | One daemon per repo you ever touch. Turn it on where `git status` is actually slow |
| **Use experimental commands (`git history`, `git replay`) for quick surgery, not in shared scripts.** | Both are marked EXPERIMENTAL in 2.55; their behaviour may change under you |

### One-way doors

Almost everything in Git is reversible, because committed objects survive about 30 days in the reflog. These are the exceptions: decide them slowly.

| Door | What it costs |
|---|---|
| **Force-pushing a shared branch** | Drops commits from everyone else's view and breaks their next pull. Recovery needs whoever still has the old tip. Protect main and release branches so the server refuses it |
| **History rewrite with filter-repo (or `lfs migrate --everything`)** | Every commit ID from the first affected commit on changes. Open MRs, pinned SHAs, forks and every clone point at history that's gone; everyone re-clones |
| **Rewriting instead of rotating a leaked secret** | A rewrite doesn't un-leak anything: clones, forks, CI logs, MR refs and caches have it. **Rotate first**, rewrite second, then clean the server |
| **Deleting or moving a tag others have pulled** | Their clones keep the old tag indefinitely, because fetch won't overwrite it. Cut a new version instead |
| **`reset --hard`, `restore .`, `clean -fdx`** on uncommitted work | It was never an object, so no reflog or fsck can bring it back. The exception: anything you staged survives as a dangling blob |
| **`reflog expire --expire=now` + `gc --prune=now`** | Deletes every recovery path. Right as the last step of a secret purge; wrong anywhere else |
| **`glab token rotate` / `revoke`** | The old secret dies immediately. Have the consumer's update path ready first (ch 08) |
| **Adopting LFS or submodules after the fact** | LFS migration rewrites history; submodule removal leaves `.git/modules` debris and breaks old checkouts |
| **Repository hash or ref format** (`--object-format`, `--ref-format`) | Chosen at `git init`. Converting later means migrating the repository |

### If you're starting today, in order

1. **Chapter 02.** Install the `~/.gitconfig`, the includeIf identity split, SSH signing with a FIDO key, and the zsh functions. Check with `git config list --show-origin`.
2. **Chapter 08.** Install glab, `glab auth login` against your GitLab host, and set `glab auth git-credential` as the HTTPS helper for it.
3. **Chapter 01.** Read it once. The three trees and reachability explain every command after this.
4. **Chapter 03.** Make `git lg`, `add -p`, `diff main...HEAD` and `gpf` reflexes.
5. **Chapter 09.** Drive MRs, pipelines and reviews from the terminal with glab.
6. **Chapter 04.** Fixup and autosquash on your next branch; `--update-refs` the first time you stack.
7. **Chapter 05.** Read the undo table *before* you need it. Try the stash-drop recovery once in a scratch repo.
8. **Chapter 10.** Put your first `glab api` recipe in a file instead of your shell history.
9. **Chapter 06.** When a repo gets big: worktrees, blob-less clones, sparse-checkout, maintenance.
10. **Chapter 07.** Keep it open until revision syntax and pathspec magic are automatic.


---


<a id="01-the-model-underneath"></a>

## 01 · The model underneath

*Git is a content-addressed object store with a handful of movable pointers on top. Every command either writes objects, moves a pointer, or copies between the three trees, and once you can say which, nothing Git does is surprising.*

### Four ideas, then vocabulary

Everything in the rest of this guide is downstream of four ideas:

1. **Objects are immutable and named by their content.** A commit ID is a hash of the commit's bytes, which include its parent IDs and its tree ID. Change anything and you have a different object with a different name.
2. **Refs are cheap, mutable pointers to objects.** A branch is a 41-byte file (or a reftable row) holding a commit ID. Creating, moving and deleting branches never touches history.
3. **There are three trees**: `HEAD` (last commit), the index (next commit), and the working tree (your files). Almost every porcelain command is a copy between two of them.
4. **Reachability decides what survives.** An object is kept if some ref, reflog entry, or the index can reach it. Everything else is garbage on a timer.

Hold those four and "rebase rewrites history", "reset is dangerous" and "you can't lose a commit" all become statements you can reason about rather than folklore.

### The object store

There are four object types. You will touch three of them daily.

| Type | Holds | Named by | You see it via |
|---|---|---|---|
| **blob** | file content, nothing else (no name, no mode) | hash of the content | `git cat-file -p BLOB` |
| **tree** | a directory listing: mode, type, hash, name per entry | hash of the listing | `git ls-tree HEAD` |
| **commit** | one tree ID, zero or more parent IDs, author, committer, message, optional signature | hash of all that | `git cat-file -p HEAD` |
| **tag** (annotated) | a pointer to another object, plus tagger, message, optional signature | hash of all that | `git cat-file -p v1.2.0` |

Look at a real one. In a fresh repo with `README` and `src/app.py`:

```bash
git cat-file -p HEAD
# tree d81d207a394c3398e980bc981047a7272e324864
# author t <t@x> 1790171279 -0400
# committer t <t@x> 1790171279 -0400
#
# init

git cat-file -p 'HEAD^{tree}'
# 100644 blob ce013625030ba8dba906f756967f9e9ca394464a	README
# 040000 tree bfb9f117f528d7d4fe915b4da8a6834a734ebc81	src

echo hello | git hash-object --stdin
# ce013625030ba8dba906f756967f9e9ca394464a    <- same as README: content-addressed
```

That last line is the whole trick. The blob ID depends only on the bytes, so two identical files anywhere in history are stored once, and "has this content changed?" is a string comparison.

```text
  commit 67d7307 ──────────────▶ tree d81d207 (root)
    parent: (none)                  ├── README  ──▶ blob ce01362  "hello\n"
    author / committer              └── src/    ──▶ tree bfb9f11
    message: "init"                                  └── app.py ──▶ blob 587be6b

  commit a1b2c3d ──────────────▶ tree 9f8e7d6 (root)
    parent: 67d7307                 ├── README  ──▶ blob ce01362  (reused, unchanged)
    message: "edit app"             └── src/    ──▶ tree 44aa0b1  (new: a child changed)
                                                     └── app.py ──▶ blob 7c1e2f0 (new)
```

A commit is a **snapshot**, not a diff. Diffs are computed on demand by comparing two trees. Unchanged subtrees are shared by hash, which is why snapshots are cheap and why `git diff` between two distant commits is fast: it skips every subtree whose hash matches.

> **Note.** Because a commit hashes its parent's ID, a commit ID pins its entire ancestry. That is what makes a signed tag or a pinned SHA in CI meaningful: nobody can alter anything upstream of it without changing the ID.

#### Loose objects and packs

New objects are written **loose**: one zlib-compressed file per object under `.git/objects/ab/cdef…`. Periodically (on `gc`, `maintenance`, or push/fetch) they are gathered into **packfiles**, which delta-compress similar objects against each other. Packs are a storage detail; the object model does not change. Chapter 05 covers packs and `gc`, chapter 06 covers keeping them healthy in big repos.

```bash
git count-objects -vH           # loose vs packed, sizes
git repo structure              # counts of refs/commits/trees/blobs and inflated size (2.55)
git repo info --all             # bare? shallow? object format, ref format
```

> **Version-sensitive.** `git repo info` and `git repo structure` are recent additions (present in 2.55, verified). On older Git, use `git rev-parse --is-shallow-repository`, `git count-objects -v` and `git-sizer`.

### Refs and HEAD

A **ref** is a name that points to an object ID. They live in namespaces:

| Ref | Example | Moved by |
|---|---|---|
| `refs/heads/*` | `refs/heads/main` — local branches | `commit`, `merge`, `rebase`, `reset`, `branch -f` |
| `refs/remotes/*` | `refs/remotes/origin/main` — remote-tracking | **only** `fetch` (and `push` on success) |
| `refs/tags/*` | `refs/tags/v1.2.0` | `tag`; should never move |
| `refs/stash` | the stash stack's top; older entries are its reflog | `stash` |
| `refs/notes/*`, `refs/merge-requests/*`, `refs/prefetch/*` | tool- and server-specific | notes, GitLab, `maintenance` |

`HEAD` is special: normally it is a **symbolic ref** that names a branch, not a commit.

```bash
cat .git/HEAD
# ref: refs/heads/main
git symbolic-ref HEAD           # refs/heads/main
git rev-parse HEAD              # the commit ID it resolves to
```

When you commit, Git writes the new commit and then moves **the branch HEAD names**. HEAD itself does not change; it still says "main".

```text
  before commit                        after commit
  HEAD ─▶ main ─▶ C2                   HEAD ─▶ main ─▶ C3
                  │                                    │
                  C1                                   C2
                                                       │
                                                       C1
```

**Detached HEAD** is when HEAD holds a commit ID directly instead of a branch name: `git switch --detach v1.2.0`, a checkout of a SHA, or mid-rebase. Commits made here move only HEAD. Switch away and nothing references them except the reflog. That is the entire "I lost my work in detached HEAD" story, and chapter 05 is the recovery.

#### Refs on disk: files and reftable

By default refs are loose files under `.git/refs/` plus a `.git/packed-refs` file. Git 2.45+ can instead store them in **reftable**, a binary format with atomic multi-ref updates and no case-folding collisions on macOS/Windows.

```bash
git init --ref-format=reftable NEWREPO     # verified on 2.55
git repo info references.format            # files | reftable
```

> **Note.** Never read or write `.git/refs` by hand in scripts. Use `git rev-parse`, `git for-each-ref` and `git update-ref`, which work regardless of the backend.

### The three trees

```text
   working tree            index (staging)            HEAD
   (files on disk)         (.git/index)               (last commit)
  ┌──────────────┐        ┌──────────────┐        ┌──────────────┐
  │ edit here    │─ add ─▶│ next commit  │─commit▶│ C3           │
  │              │        │              │        │              │
  │              │◀restore│              │◀restore│              │
  │              │        │              │ --staged              │
  │              │◀────── restore --source=HEAD --staged --worktree│
  └──────────────┘        └──────────────┘        └──────────────┘
       git diff                git diff --staged
   (worktree vs index)         (index vs HEAD)
                  git diff HEAD (worktree vs HEAD)
```

The **index** is a real file: a sorted list of `(mode, blob ID, stage, path)` plus stat data for speed. It is literally the tree of your next commit, already hashed.

```bash
git ls-files -s
# 100644 ce013625030ba8dba906f756967f9e9ca394464a 0	README
# 100644 587be6b4c3f93f93c489c0111bba5596147a26cb 0	src/app.py
```

The `0` is the **stage number**. During a conflict, a path has stages 1 (base), 2 (ours) and 3 (theirs) instead of 0, and "resolving" means collapsing those back to a single stage-0 entry, which is exactly what `git add` does.

This is why `git add` is not "track this file". It is **"hash this content into the object store and put its ID in the index now"**. Edit the file again after `git add` and the index still holds the old version; `git status` shows the file as both staged and modified.

#### What each command copies

| Command | From | To | Moves a branch? |
|---|---|---|---|
| `git add PATH` | worktree | index | no |
| `git restore PATH` | index | worktree | no |
| `git restore --staged PATH` | HEAD | index | no |
| `git restore --source=REV -SW PATH` | REV | index and worktree | no |
| `git commit` | index | new commit | **yes**, the current branch |
| `git reset --soft REV` | — | — | **yes**, to REV; index and worktree untouched |
| `git reset [--mixed] REV` | REV | index | **yes** |
| `git reset --hard REV` | REV | index and worktree | **yes** |
| `git switch BRANCH` | BRANCH | index and worktree (carrying local changes if they don't conflict) | moves **HEAD**, not a branch |

The critical distinction: **`reset` with a commit moves the branch HEAD points at; `switch` moves HEAD itself.** `reset --hard origin/main` on `feature` makes `feature` point at `origin/main`. `switch main` leaves `feature` exactly where it was.

### Reachability and garbage

An object is **reachable** if you can get to it by walking from any root:

- every ref (`refs/heads`, `refs/tags`, `refs/remotes`, `refs/stash`, notes…)
- every **reflog** entry (for as long as the reflog keeps it)
- the index, `HEAD`, and in-progress operation state (`ORIG_HEAD`, `MERGE_HEAD`, rebase todo)
- other worktrees' HEADs and indexes

```text
   refs/heads/main ──▶ E ──▶ D ──▶ C ──▶ B ──▶ A
                                   ▲
   refs/heads/feat ──▶ G ──▶ F ────┘

   After `git branch -D feat`:  F and G are unreachable from any ref…
   …but HEAD's reflog still lists G, so they survive until the reflog entry expires.
```

Unreachable objects are **not deleted immediately**. `gc` prunes loose unreachable objects older than 2 weeks (`gc.pruneExpire`), and reflog entries for commits no longer on the tip expire after 30 days (`gc.reflogExpireUnreachable`); reachable reflog entries after 90 days (`gc.reflogExpire`). Defaults read from `git help config` on 2.55.

The practical rule: **anything you committed, even once, even on a branch you deleted, is recoverable for about 30 days** on the machine where you did it. Anything you never committed or stashed (untracked files wiped by `reset --hard` or `clean -fd`) was never an object and is gone.

> **Gotcha.** Reflogs are **local**. A commit you pushed and someone else force-overwrote on the server lives in *your* reflog (if you had it) and in the server's own housekeeping, not in any reflog your colleague can see. Recovery happens on the machine that had the commit.

### Why rebase makes new commits

A commit's ID covers its parent's ID. So "moving" commit `F` to sit on top of `E` instead of `C` necessarily makes **a new commit `F'`** with the same diff intent, a new parent, a new tree (because the base changed), and therefore a new ID.

```text
  before:                         after `git rebase main` on feat:

        F───G   feat                              F'──G'  feat
       /                                         /
  A──B──C──D──E   main              A──B──C──D──E   main
                                          \
                                           F───G   (orphaned: only reflog + ORIG_HEAD reach them)
```

Consequences that follow directly:

- **Anyone who had `F` and `G` now has commits your branch no longer contains.** If they merge their copy, both `F`/`G` and `F'`/`G'` land in history. This is the whole reason for "don't rebase shared branches".
- **Pushing a rebased branch requires a force**, because the remote's `feat` (`G`) is not an ancestor of your `feat` (`G'`). Chapter 03 covers doing that safely.
- **Signatures and CI results attach to IDs.** A rebased commit is unsigned until re-signed (with `commit.gpgSign`, rebase re-signs each one), and GitLab treats it as a new pipeline SHA.
- **The originals are still there.** `ORIG_HEAD` and `feat@{1}` point at `G` right after the rebase. Undo is `git reset --hard ORIG_HEAD`.

Cherry-pick, `commit --amend`, `rebase -i`, `filter-repo`, `git history reword` and squash-merge all make new commits for exactly the same reason. **Nothing in Git edits a commit. It writes a new one and moves a ref.**

### Merges and merge bases

A merge commit is simply a commit with two (or more) parents. Its tree is the result of a three-way merge using the **merge base**: the best common ancestor.

```text
            F───G   feat
           /     \
  A──B──C──D──E───M   main      M has parents E (first) and G (second)
           ▲
       merge base of E and G = D
```

```bash
git merge-base main feat                 # D
git merge-base --fork-point origin/main  # smarter base using origin/main's reflog
```

**First parent matters.** `M^1` is the branch you were on (`E`), `M^2` is what you merged in (`G`). `git log --first-parent main` walks only the mainline, which on a repo that merges MRs gives you one line per merged MR. `git revert -m 1 M` means "undo what the merge brought in relative to parent 1". Chapter 04 goes deep on that trap.

### Remote-tracking refs

A remote is a name plus a URL plus a **refspec** that says how to map the remote's refs into yours:

```bash
git config --get-regexp '^remote\.origin\.'
# remote.origin.url git@gitlab.example.com:group/project.git
# remote.origin.fetch +refs/heads/*:refs/remotes/origin/*
```

Read that refspec as: "take every `refs/heads/X` on the server and write it to my `refs/remotes/origin/X`; the `+` means allow non-fast-forward updates". So:

```text
      server (origin)                         your clone
  refs/heads/main    ── fetch ──▶  refs/remotes/origin/main     (read-only mirror, moved by fetch)
  refs/heads/feat    ── fetch ──▶  refs/remotes/origin/feat
                                     ▲
                                     │ upstream (branch.feat.merge / .remote)
                                   refs/heads/feat               (yours, moved by you)
```

- **`origin/main` is a snapshot of the server as of your last fetch.** It is not live. `git status` saying "up to date with origin/main" means "as of whenever you last fetched", which may be days ago.
- **Only `fetch` moves remote-tracking refs** (and a successful `push` updates the one it pushed). `pull` is `fetch` followed by `merge` or `rebase` against the upstream.
- **Upstream** is per-branch config: `branch.feat.remote = origin`, `branch.feat.merge = refs/heads/feat`. It's what `@{u}`, `git status` ahead/behind, bare `git pull` and bare `git push` use. `push.autoSetupRemote` sets it on first push (chapter 02).
- A branch deleted on the server leaves your `origin/feat` behind until you fetch with `--prune` (or set `fetch.prune`).

```bash
git fetch origin                          # update refs/remotes/origin/*
git rev-list --left-right --count @{u}...HEAD   # "behind ahead"
git branch -vv                            # every branch, its upstream, ahead/behind
git ls-remote origin 'refs/heads/*'       # what the server has right now, no fetch
```

#### GitLab's extra refs

GitLab publishes each MR's head as `refs/merge-requests/IID/head` (and, when merge-ref pipelines are on, `refs/merge-requests/IID/merge`). They are not fetched by default refspecs. Fetching one gives you an MR's exact code without adding the author's fork as a remote:

```bash
git fetch origin refs/merge-requests/IID/head:mr-IID
git switch mr-IID
```

`glab mr checkout IID` does the same with nicer ergonomics; see the glab chapters.

### Plumbing worth knowing

You rarely need plumbing, but these five answer "what is Git actually doing" faster than any porcelain:

| Command | Answers |
|---|---|
| `git cat-file -p OBJ` / `-t OBJ` | what is this object, what's in it |
| `git rev-parse REV` | what commit does this expression resolve to |
| `git ls-files -s` | what exactly is staged, including conflict stages |
| `git for-each-ref --format='%(refname) %(objectname:short)'` | every ref and where it points |
| `git reflog show REF` | where has this ref been |

### Checklist

- Can you say, for any command you're about to run, **which of the three trees it writes** and **whether it moves a branch or HEAD**? If not, check the table above first.
- **Committed means recoverable** (locally, ~30 days). Uncommitted, unstashed changes are one `reset --hard` away from gone. Commit or stash before anything destructive.
- **Rebase, amend, cherry-pick and squash all make new IDs.** Anything already shared needs coordination before you rewrite it.
- **`origin/*` is a cache.** Fetch before you trust ahead/behind, and before any force-push.
- **First parent is the mainline.** Use `--first-parent` for history and `-m 1` for merge reverts.


---


<a id="02-setup-config-identity-signing"></a>

## 02 · Setup: config, identity, signing

*Git's defaults are tuned for backward compatibility with 2008, not for you. About thirty lines of config fix conflict markers, diffs, pushes and rebases for good, and two includeIf lines make the wrong-email commit impossible.*

### Where config lives

Git reads config in this order; **later wins**, key by key:

| Level | File | Flag | Use it for |
|---|---|---|---|
| system | `/etc/gitconfig` | `--system` | distro or fleet defaults; leave alone on a workstation |
| global (XDG) | `~/.config/git/config` | `--global` (if `~/.gitconfig` is absent) | your defaults |
| global | `~/.gitconfig` | `--global` | your defaults (read after the XDG file) |
| local | `REPO/.git/config` | `--local` | remotes, per-repo overrides |
| worktree | `REPO/.git/worktrees/NAME/config.worktree` | `--worktree` | per-worktree overrides (needs `extensions.worktreeConfig`) |
| command | `git -c key=value …`, `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n` | — | one-off overrides and scripts |

**Pick one global file.** If both `~/.config/git/config` and `~/.gitconfig` exist, both are read and `~/.gitconfig` wins on conflicts, which is a fine way to spend an afternoon confused. Keep `~/.gitconfig` (it's where `git config --global` writes when it exists) and put the satellite files (`ignore`, `allowed_signers`, identity includes) under `~/.config/git/`.

```bash
git config list --show-origin --show-scope        # every value and the file it came from
git config get --show-origin user.email           # which file set this one
git config get --type=bool push.autoSetupRemote   # typed read (true/false normalized)
git config edit --global                          # opens the file in $EDITOR
```

> **Version-sensitive.** The `git config list|get|set|unset|edit` subcommands arrived in Git 2.46. The old `git config --get`, `--list`, `--unset` forms still work, and you'll see them in older docs and scripts.

For scripts that must ignore the user's config (CI, reproducible tests), isolate completely:

```bash
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git …
```

### The opinionated ~/.gitconfig

This is the whole file. Every line is here for a reason given in the table after it; nothing is decorative. It has been parsed by `git config --list` on 2.55.

```ini
# ~/.gitconfig
[user]
	name = YOUR NAME
	email = YOU@personal.example
	useConfigOnly = true            # never guess an email from hostname
	signingKey = ~/.ssh/id_ed25519_sk.pub

[init]
	defaultBranch = main

[core]
	excludesFile = ~/.config/git/ignore
	untrackedCache = true
	pager = delta
	# fsmonitor is per-repo, not global: see "Speed" below

[interactive]
	diffFilter = delta --color-only

[delta]
	navigate = true                 # n / N jump between files
	line-numbers = true
	# side-by-side = true           # nice on a wide monitor, awful in a split pane

[gpg]
	format = ssh
[gpg "ssh"]
	allowedSignersFile = ~/.config/git/allowed_signers

[commit]
	gpgSign = true
	verbose = true                  # show the diff in the commit message editor

[tag]
	gpgSign = true
	sort = version:refname          # v1.10 after v1.9

[status]
	showUntrackedFiles = all        # show files inside new dirs, not just the dir

[diff]
	algorithm = histogram
	colorMoved = plain
	colorMovedWS = allow-indentation-change
	mnemonicPrefix = true           # i/ w/ c/ instead of a/ b/
	renames = copies

[merge]
	conflictStyle = zdiff3

[rerere]
	enabled = true

[fetch]
	prune = true
	writeCommitGraph = true

[pull]
	rebase = true

[push]
	default = simple
	autoSetupRemote = true
	followTags = true
	useForceIfIncludes = true

[rebase]
	autoSquash = true
	autoStash = true
	updateRefs = true
	missingCommitsCheck = error

[branch]
	sort = -committerdate

[column]
	ui = auto

[log]
	date = iso-local

[help]
	autocorrect = prompt

[transfer]
	fsckObjects = true

[maintenance]
	strategy = incremental

# Identity switching (see next section)
[includeIf "gitdir:~/work/"]
	path = ~/.config/git/work.inc
[includeIf "hasconfig:remote.*.url:git@gitlab.example.com:*/**"]
	path = ~/.config/git/work.inc
[includeIf "hasconfig:remote.*.url:https://gitlab.example.com/**"]
	path = ~/.config/git/work.inc

[alias]
	st    = status -sb
	lg    = log --graph --format='%C(auto)%h%d %s %C(dim)%an, %ar%C(reset)'
	lga   = lg --all
	last  = log -1 --stat
	pushf = push --force-with-lease --force-if-includes
	fixup = commit --fixup
	amend = commit --amend --no-edit
	unstage = restore --staged
	wip   = !git add -A && git commit --no-verify --no-gpg-sign -m 'wip'
	undo  = reset --soft HEAD~1
	gone  = !git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads | awk '$2==\"[gone]\"{print $1}'
	who   = shortlog -sne --no-merges
	root  = rev-parse --show-toplevel
```

#### Why each line

| Key | Default | Why change it |
|---|---|---|
| `user.useConfigOnly = true` | false | Without it, a repo outside your includeIf paths commits as `you@fedora.localdomain`. With it, Git refuses to commit until an email is configured |
| `init.defaultBranch = main` | `master` (changes to `main` in Git 3.0, per the 2.55 init hint) | Matches GitLab's default; silences the hint |
| `core.untrackedCache = true` | false | Caches untracked-file scans; noticeable `git status` speedup on any repo with many directories |
| `commit.verbose = true` | false | You write better messages when the diff is in front of you |
| `status.showUntrackedFiles = all` | `normal` | `normal` shows `newdir/` and hides that it contains `secrets.env` |
| `diff.algorithm = histogram` | `myers` | Aligns diffs on unique lines; far fewer "moved the closing brace" diffs. Also used by merges for hunk alignment |
| `diff.colorMoved = plain` | off | Moved blocks show in a different colour, so a refactor that moves 200 lines reads as a move, not as 200 deletions and 200 additions |
| `diff.renames = copies` | `true` | Also detects copies; cheap on modern machines |
| `merge.conflictStyle = zdiff3` | `merge` | Adds the **base** section between ours and theirs, so you can see what each side *changed*, not just what each side *has*. The single highest-value line in this file |
| `rerere.enabled = true` | false | Records conflict resolutions and replays them. Repeated rebases of a long-lived branch stop re-asking the same question |
| `fetch.prune = true` | false | Deletes `origin/foo` when `foo` is deleted on the server; otherwise dead remote branches accumulate forever |
| `fetch.writeCommitGraph = true` | false | Keeps the commit-graph file current on each fetch; speeds `log --graph`, `merge-base` and ahead/behind |
| `pull.rebase = true` | unset (and divergent pulls then error) | See the "close call" below |
| `push.autoSetupRemote = true` | false | First `git push` on a new branch creates `origin/BRANCH` and sets upstream, no `-u origin HEAD` ritual |
| `push.followTags = true` | false | Pushes annotated tags that point at commits you're pushing. Lightweight tags stay local |
| `push.useForceIfIncludes = true` | false | Makes every `--force-with-lease` also check you have *seen* the remote tip. Chapter 03 shows the failure it prevents |
| `rebase.autoSquash = true` | false | `rebase -i` pre-arranges `fixup!`/`squash!`/`amend!` commits. Applies to interactive rebases only (verified: a plain `git rebase` with this config ignores fixups; pass `--autosquash` explicitly) |
| `rebase.autoStash = true` | false | Rebase stashes and re-applies your dirty tree instead of refusing to start |
| `rebase.updateRefs = true` | false | Rebasing the top of a stack moves every branch in the stack with it (chapter 04) |
| `rebase.missingCommitsCheck = error` | `ignore` | Deleting a line in the `rebase -i` todo drops that commit. This makes accidental deletions an error; use `drop` to mean it |
| `branch.sort = -committerdate` | `refname` | `git branch` shows what you were working on, not an alphabetical wall |
| `column.ui = auto` | never | `git branch`, `git tag`, `git status` list in columns when the terminal is wide |
| `tag.sort = version:refname` | `refname` | Semver-aware ordering |
| `help.autocorrect = prompt` | show suggestion only | `git stauts` asks "did you mean status?" instead of just failing. Never set a number here; it auto-runs the guess |
| `transfer.fsckObjects = true` | false | Validates every object received on fetch/clone/push. Catches corruption and malformed objects at the door. Rare legacy repos with old broken objects need a per-repo `fetch.fsck.skipList` |
| `maintenance.strategy = incremental` | `none` for scheduled | Only matters for repos you `git maintenance register`; it makes the scheduled jobs prefetch and repack incrementally without ever deleting data |

#### The close call: pull.rebase

`pull.rebase = true` versus `pull.ff = only` is a **close call**.

- **Pick `pull.rebase = true`** (this guide's default). When two people push to the same feature branch, `git pull` replays your unpushed commits on top of theirs and you never get a "Merge branch 'feat' of gitlab…" commit. With `rebase.autoStash` it even works on a dirty tree.
- **Tiebreaker:** if you regularly pull on `main` or release branches where you should never have local commits, `pull.ff = only` makes an accidental local commit an error instead of quietly rebasing it into your next push.

Whichever you pick, set one. With neither set, current Git (verified on 2.55) refuses to pull divergent branches and prints a hint telling you to choose.

### Identity per context: includeIf

Two identities (work and personal) on one machine is the normal case. **Make the wrong identity impossible, not unlikely.**

```ini
# ~/.config/git/work.inc
[user]
	email = YOU@corp.example
	signingKey = ~/.ssh/id_ed25519_sk_work.pub
[core]
	sshCommand = ssh -i ~/.ssh/id_ed25519_sk_work -o IdentitiesOnly=yes
```

Three conditions are worth knowing:

| Condition | Matches when | Use for |
|---|---|---|
| `gitdir:~/work/` | the repo's `.git` is under `~/work/` (trailing `/` means "and everything below") | directory-based separation; the simplest |
| `gitdir/i:…` | same, case-insensitive | macOS/Windows paths |
| `onbranch:release/**` | current branch matches | branch-specific hooks or signing policy |
| `hasconfig:remote.*.url:PATTERN` | any remote URL matches | "any repo cloned from the work GitLab", wherever it lives on disk |

`hasconfig` is the stronger guarantee: a work repo cloned into `~/tmp` still gets the work identity. Pattern rules I verified on 2.55:

```ini
# scp-style SSH remotes (git@host:group/project.git)
[includeIf "hasconfig:remote.*.url:git@gitlab.example.com:*/**"]    # matches
# [includeIf "hasconfig:remote.*.url:git@gitlab.example.com:**"]    # does NOT match
# ssh:// remotes
[includeIf "hasconfig:remote.*.url:ssh://git@gitlab.example.com/**"]
# https remotes
[includeIf "hasconfig:remote.*.url:https://gitlab.example.com/**"]
```

Each URL form needs its own line: an `https://` pattern does not match an `ssh://` remote and vice versa (verified).

> **Gotcha.** Files included through `hasconfig:remote.*.url` may not themselves define remote URLs, so keep `url.*.insteadOf` rewrites in the main file, not in `work.inc`.

Verify before your first commit in a new clone:

```bash
git config get --show-origin user.email
git config get --show-origin user.signingKey
```

### SSH keys for transport

Use a **hardware-backed SSH key** (`-sk` types) for GitLab if you have a FIDO2 key; otherwise ed25519.

```bash
# FIDO2 resident key, one touch per use; label it so ssh-add -L is readable
ssh-keygen -t ed25519-sk -O resident -O application=ssh:gitlab-work \
  -C "YOU@corp.example gitlab" -f ~/.ssh/id_ed25519_sk_work

# no hardware key
ssh-keygen -t ed25519 -C "YOU@corp.example gitlab" -f ~/.ssh/id_ed25519_work
```

```text
# ~/.ssh/config
Host gitlab.example.com
    User git
    IdentityFile ~/.ssh/id_ed25519_sk_work
    IdentitiesOnly yes
    ControlMaster auto
    ControlPath ~/.ssh/cm-%C
    ControlPersist 10m
```

`ControlMaster` reuses one authenticated connection for ten minutes, so a `fetch --all` across remotes or a submodule update is one touch, not twelve.

```bash
ssh -T git@gitlab.example.com          # "Welcome to GitLab, @you!"
GIT_SSH_COMMAND='ssh -v' git fetch     # debug which key is being offered
```

If your GitLab listens on a non-standard SSH port, put `Port` in `~/.ssh/config` rather than into every remote URL.

To force SSH even when someone pastes an HTTPS URL:

```ini
[url "git@gitlab.example.com:"]
	insteadOf = https://gitlab.example.com/
```

### Signing commits and tags

**Pick SSH signing** over GPG. One key type for transport and signing, no `gpg-agent` pinentry weather, and GitLab verifies SSH signatures against the SSH keys on your profile (key usage "Authentication & Signing").

> **Version-sensitive.** GitLab verifies SSH-signed **commits** from **15.7** (flag on by default; GA in 15.8). Verification status for SSH-signed **tags** came much later: 18.3 behind `render_ssh_signed_tags_verification_status`, GA in **19.1** (docs.gitlab.com/user/project/repository/signed_commits/ssh). On older instances `tag.gpgSign` still signs locally; GitLab just won't show a badge.

#### SSH signing

```bash
git config set --global gpg.format ssh
git config set --global user.signingKey ~/.ssh/id_ed25519_sk.pub
git config set --global commit.gpgSign true
git config set --global tag.gpgSign true

# allowed_signers lets *you* verify signatures locally (git log --show-signature)
mkdir -p ~/.config/git
printf '%s namespaces="git" %s\n' "YOU@personal.example" "$(cat ~/.ssh/id_ed25519_sk.pub)" \
  >> ~/.config/git/allowed_signers
git config set --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers
```

```bash
git log --show-signature -1
git log --format='%h %G? %GS %s' -10     # G good, B bad, U untrusted, N none, E can't check
git verify-commit HEAD
git verify-tag v1.2.0
```

> **Gotcha.** With `commit.gpgSign = true` and a FIDO key that requires touch, **every rewritten commit asks for a touch**: a 25-commit interactive rebase is 25 taps, and an unattended script that rebases just hangs. For scripted rewrites, pass `--no-gpg-sign` or `-c commit.gpgSign=false`, and re-sign at the end with `git rebase --exec 'git commit --amend --no-edit -S' BASE` when you are at the keyboard.

> **Gotcha.** If the agent refuses the operation ("agent refused operation", "Couldn't sign message"), the key is not in the agent, or the FIDO key was not touched in time. `ssh-add -L` shows what the agent holds; `ssh-add -K` loads resident keys from the token.

#### GPG, if you must

```bash
gpg --full-generate-key                      # ed25519 / cv25519
gpg --list-secret-keys --keyid-format=long   # take the long ID
git config set --global gpg.format openpgp
git config set --global user.signingKey LONG_KEY_ID
gpg --armor --export LONG_KEY_ID             # paste into GitLab > GPG keys
```

GPG remains the right answer only when a policy demands OpenPGP, or your GitLab predates SSH signing.

### Credentials over HTTPS

**Use SSH for Git transport.** HTTPS credentials matter anyway for three cases: networks that block port 22, CI-like scripts on your laptop, and Git LFS (which talks HTTPS even when the remote is SSH, unless your admin enabled pure-SSH LFS; see chapter 06).

On Fedora 43, pick by case:

| Helper | Package | Stores | Use when |
|---|---|---|---|
| `glab auth git-credential` | glab (installed) | the token `glab auth login` saved | you already use glab against that host; one login covers both |
| `libsecret` | `git-credential-libsecret` | GNOME Keyring / KWallet via Secret Service | a desktop session, any host |
| `cache --timeout=3600` | built in | memory, for an hour | headless boxes, short sessions |
| `store` | built in | **plaintext** `~/.git-credentials` | never on a laptop |
| `git-credential-oauth` | `git-credential-oauth` | OAuth tokens via browser flow | GitLab instances with OAuth app configured and no PAT policy |

Package names verified against the Fedora 43 repos (`dnf list --available 'git-credential*'`).

```bash
sudo dnf install git-credential-libsecret
git config set --global credential.helper libsecret
```

Per-host helpers keep the glab token for GitLab and the keyring for everything else. **The empty `helper =` line resets the inherited list**, so only glab is consulted for that host:

```ini
[credential]
	helper = libsecret
[credential "https://gitlab.example.com"]
	helper =
	helper = !glab auth git-credential
```

```bash
# what would Git send for this URL? (prints the password; don't paste output anywhere)
printf 'protocol=https\nhost=gitlab.example.com\n\n' | git credential fill

# forget a cached/stored credential
printf 'protocol=https\nhost=gitlab.example.com\n\n' | git credential reject
```

> **Gotcha.** Tokens embedded in remote URLs (`https://oauth2:TOKEN@gitlab…`) end up in `.git/config`, in shell history and in every `git remote -v` screenshot. Use a helper, or in CI use `CI_JOB_TOKEN` via the URL GitLab provides for that job.

### Global ignore and attributes

```bash
mkdir -p ~/.config/git
cat >> ~/.config/git/ignore <<'EOF'
.DS_Store
*.swp
*~
.idea/
.vscode/
.direnv/
.envrc.local
*.local.yaml
__pycache__/
.pytest_cache/
node_modules/.cache/
EOF
```

Put **editor and OS noise** in the global ignore. Put **project build artefacts** in the project's `.gitignore`, where teammates benefit. Precedence rules are in chapter 06.

### Diff and pager tools

#### delta as the pager

**Pick delta** for everyday paging: syntax highlighting, line numbers, `n`/`N` navigation between files, and it respects `diff.colorMoved`. It's a pager, so it works with every command that pages: `diff`, `show`, `log -p`, `blame`, `add -p` (via `interactive.diffFilter`).

```bash
sudo dnf install git-delta     # the binary is `delta`
```

The config is in the main file above. `merge.conflictStyle = zdiff3` makes delta render conflicts with the base section, which it handles well.

> **Note.** delta and difftastic are not installed on the machine this guide was verified on, so nothing here was executed. The config keys (`navigate`, `line-numbers`, `side-by-side`, `interactive.diffFilter = delta --color-only`, `zdiff3`) match delta's own manual (dandavison.github.io/delta), and the `difftool`/`diff.external` setup matches difftastic's Git chapter (difftastic.wilfred.me.uk/git.html), which prefers `diff.external` because Git then passes mode changes and renames. Latest upstream: delta 0.19.2, difftastic 0.71.0.

#### difftastic for structural diffs

difftastic (`difft`) diffs by syntax tree, so reindenting a block, rewrapping arguments or moving a function shows as what it is. It is slower and its output can't be applied as a patch, so use it **on demand**, not as the default pager.

```bash
sudo dnf install difftastic
```

```ini
[difftool "difftastic"]
	# upstream's form: passes the real path so headers and language detection use it
	cmd = difft "$MERGED" "$LOCAL" "abcdef1" "100644" "$REMOTE" "abcdef2" "100644"
[difftool]
	prompt = false
[pager]
	difftool = true
[alias]
	dft  = difftool --tool=difftastic
	dlog = -c diff.external=difft log -p --ext-diff
	dshow = -c diff.external=difft show --ext-diff
```

```bash
git dft                  # structural diff of the working tree
git dft main...HEAD      # structural diff of this branch's changes
git dlog -3              # last 3 commits, structurally
```

**Tiebreaker between them:** delta for everything you pipe to a pager; difftastic when reviewing a refactor or a reformat, where a line diff is noise.

### Speed: fsmonitor, untracked cache, maintenance

For most repos Git is fast enough without tuning. For large ones (tens of thousands of files, or a monorepo):

```bash
# per repo: filesystem monitor daemon + untracked cache
git config set core.fsmonitor true
git config set core.untrackedCache true
git fsmonitor--daemon status

# or let scalar apply a full set of large-repo settings and schedule maintenance
scalar register
```

I verified on this Fedora 43 box that Git 2.55's build includes `fsmonitor--daemon` (`git version --build-options` lists `feature: fsmonitor--daemon`) and that the daemon runs and watches a repo on Linux. The `git help config` text still says Windows and macOS only, which is out of date for this build.

**Keep fsmonitor per-repo, not global.** Each repo you touch starts its own daemon holding inotify watches. On a machine with hundreds of clones, a global setting means hundreds of daemons, each holding **one inotify watch per directory** in its worktree, all counted against the per-user `fs.inotify.max_user_watches` (see `man 7 inotify`). Check your ceiling with `sysctl fs.inotify.max_user_watches`. Git's docs don't quantify this for Linux; the risk is inferred from how the daemon and inotify work, not measured.

Background maintenance keeps packs, the commit-graph and prefetched refs fresh on a timer:

```bash
git maintenance start          # registers this repo + creates systemd --user timers
systemctl --user list-timers 'git-maintenance@*'
git maintenance unregister     # stop maintaining this repo
```

`git maintenance start` on Linux writes `~/.config/systemd/user/git-maintenance@.{timer,service}` (from `man git-maintenance`). It is harmless and reversible with `git maintenance stop`. Chapter 06 covers what the tasks do.

### zsh aliases and functions

Aliases for the reflexes, functions for anything with logic. These pass `zsh -n`. Paste into `~/.zshrc` or a sourced `~/.config/zsh/git.zsh`. They assume fzf (installed on Fedora 43 here) and set nothing global.

```bash
# ---- git: aliases -------------------------------------------------------
alias g='git'
alias gs='git status -sb'
alias gd='git diff'
alias gds='git diff --staged'
alias ga='git add'
alias gap='git add -p'
alias gc='git commit'
alias gca='git commit --amend --no-edit'
alias gsw='git switch'
alias gswc='git switch -c'
alias gf='git fetch --all --prune'
alias gpl='git pull'
alias gp='git push'
alias gpf='git push --force-with-lease --force-if-includes'
alias grb='git rebase'
alias grbi='git rebase -i'
alias grbc='git rebase --continue'
alias grba='git rebase --abort'
alias gl='git log --graph --format="%C(auto)%h%d %s %C(dim)%an, %ar%C(reset)"'
alias gla='gl --all'
alias gwt='git worktree'

# default branch of origin (main/master/trunk), from origin/HEAD
# populate once per clone with: git remote set-head origin --auto
gdefault() {
  local ref
  ref=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) \
    || { echo main; return; }
  echo "${ref#origin/}"
}

# gsync: fetch, then rebase the current branch (and its stack) onto the fresh default branch
gsync() {
  local base; base=$(gdefault)
  git fetch --prune origin && git rebase --update-refs "origin/$base"
}

# gco: fuzzy-switch to a local or remote branch, most recent first
gco() {
  local ref
  ref=$(git for-each-ref --sort=-committerdate \
          --format='%(refname:short)%09%(committerdate:relative)%09%(subject)' \
          refs/heads refs/remotes \
        | grep -v -e '/HEAD' \
        | fzf --height=40% --reverse --delimiter='\t' --nth=1 \
              --preview 'git log --oneline --graph --color=always -20 {1}') || return
  ref=${ref%%$'\t'*}
  if git show-ref --verify --quiet "refs/heads/$ref"; then
    git switch "$ref"
  else
    git switch --track "$ref"          # origin/foo -> local foo tracking origin/foo
  fi
}

# gfix: pick a commit on this branch, commit the staged changes as its fixup, autosquash
gfix() {
  local base sha
  base=$(git merge-base HEAD "origin/$(gdefault)") || return
  sha=$(git log --format='%h %s' "$base"..HEAD \
        | fzf --height=40% --reverse --preview 'git show --stat --color=always {1}') || return
  sha=${sha%% *}
  git commit --fixup="$sha" && git rebase --autosquash "$base"
}

# gpick: browse history with a preview, print the chosen SHA (compose: git show $(gpick))
gpick() {
  git log --color=always --format='%C(auto)%h%d %s %C(dim)%ar' "$@" \
    | fzf --ansi --no-sort --reverse --preview 'git show --color=always {1}' \
    | awk '{print $1}'
}

# gclean: delete local branches whose upstream was deleted on the server
gclean() {
  git fetch --prune --quiet
  git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads \
    | awk '$2 == "[gone]" {print $1}' \
    | while read -r b; do git branch -D "$b"; done
}

# groot: cd to the top of the current repo (or worktree)
groot() { cd "$(git rev-parse --show-toplevel)" || return; }
```

> **Gotcha.** `gclean` uses `branch -D`, which deletes even unmerged branches. That's deliberate: a squash-merged MR leaves a branch that Git considers unmerged forever. The commits remain in the reflog for 30 days (chapter 05) if you delete one you still needed. The `[gone]` value was verified with `%(upstream:track)` on 2.55.

> **Note.** If you use oh-my-zsh's `git` plugin, it defines many of these names already, with different meanings (`gco` is `git checkout` there). Pick one set; don't load both.

#### Prompt

A prompt that shows branch, dirty state and ahead/behind prevents half the mistakes in chapter 05. Starship's `git_branch` and `git_status` modules, or zsh's built-in `vcs_info`, both work. Whatever you pick, **make it show detached HEAD and in-progress rebase/merge states** loudly; that's the state where people lose work.

### Checklist

- `git config list --show-origin --show-scope` shows one global file, not two.
- `user.useConfigOnly = true`, and `git config get --show-origin user.email` in a work clone resolves to `work.inc`.
- `merge.conflictStyle = zdiff3`, `rerere.enabled = true`, `diff.algorithm = histogram`.
- `push.autoSetupRemote`, `push.useForceIfIncludes`, `fetch.prune` are all `true`.
- One of `pull.rebase = true` or `pull.ff = only` is set.
- Commits show `G` in `git log --format='%G?'`, and GitLab shows them as Verified.
- No `helper = store` and no tokens in any `remote.*.url`.
- `fsmonitor` and `maintenance` are on only for the big repos that need them.


---


<a id="03-daily-driving"></a>

## 03 · Daily driving

*Most daily Git is asking a question (what changed, who, why, where does this branch stand) and then moving exactly the right thing between the three trees. Learn the question-shaped commands and the safe push, and the rest is muscle memory.*

### What state am I in

```bash
git status -sb                   # short: branch, ahead/behind, XY codes
git status                       # long: includes "rebase in progress", hints
git branch -vv                   # every local branch, its upstream, ahead/behind, last subject
git rev-list --left-right --count @{u}...HEAD    # "BEHIND AHEAD" for scripts
git stash list
git worktree list
```

The short-status `XY` columns are **index then worktree**:

| Code | Means |
|---|---|
| `M ` | modified, staged |
| ` M` | modified, not staged |
| `MM` | staged, then modified again (the index holds the older version) |
| `A ` | new file, staged |
| `??` | untracked |
| `D ` / ` D` | deleted, staged / deleted, not staged |
| `R ` | renamed (staged) |
| `UU`, `AA`, `DU`… | unmerged: conflict in progress |

> **Gotcha.** `git status` ahead/behind is relative to **your last fetch**. "Your branch is up to date with 'origin/main'" after a week without fetching means nothing. `git fetch` first when it matters.

### What changed

#### Diff shapes

| Want | Command |
|---|---|
| unstaged changes | `git diff` |
| what will be committed | `git diff --staged` |
| everything vs last commit | `git diff HEAD` |
| what this branch changed since it forked | `git diff main...HEAD` (three dots: from merge base) |
| literal difference between two tips | `git diff main..HEAD` or `git diff main HEAD` |
| just filenames | `git diff --name-status main...HEAD` |
| size of the change | `git diff --stat main...HEAD`, `--shortstat`, `--dirstat` |
| word-level for prose/YAML | `git diff --word-diff` or `--color-words` |
| one file at another revision | `git show REV:path/to/file` |
| a file between two revisions | `git diff REV1 REV2 -- path` |
| whitespace problems before committing | `git diff --check` |
| ignore whitespace noise | `git diff -w` (all), `-b` (amount), `--ignore-blank-lines` |

**`A...B` in `git diff` means "from the merge base of A and B to B"**, which is what an MR shows. `A..B` in `diff` is the same as `A B`: tip to tip, including everything main gained that you don't have, which is almost never what you want to review. The dots mean something different in `git log`; chapter 07 has the table.

```bash
git diff --stat origin/main...HEAD          # my MR, summarized
git diff origin/main...HEAD -- '*.yaml'     # my MR, YAML only
git diff HEAD~3 -- charts/ ':!charts/*/tests'   # pathspec exclusion
```

#### Log shapes

The one you'll type most is an alias (`git lg` from chapter 02). The shapes worth knowing:

```bash
git log --oneline -20
git log --graph --oneline --decorate --all         # topology of everything
git log --graph --format='%C(auto)%h%d %s %C(dim)%an, %ar%C(reset)' main..HEAD
git log --first-parent --oneline main              # one line per merged MR
git log --stat -5                                  # which files each commit touched
git log -p -3 -- path/to/file                      # patches for one file
git log --follow -p -- path/to/renamed/file        # across renames (single file only)
git log --since='2 weeks ago' --author='Alice' --no-merges
git log --grep='JIRA-123' --oneline                # search messages
git log --format='%h %G? %an %s' -10               # signature status per commit
git log origin/main..HEAD                          # what I'm about to push
git log HEAD..origin/main                          # what I'm about to pull
git log --left-right --oneline main...feature      # < only-on-main, > only-on-feature
git log --cherry-pick --right-only --oneline main...feature   # feature commits not already on main (patch-id match)
```

The format placeholders you'll reach for: `%h` short hash, `%H` full, `%s` subject, `%b` body, `%an`/`%ae` author name/email, `%ar` relative date, `%ad` date (honours `--date=`), `%cn`/`%cr` committer, `%d` decorations, `%G?` signature status, `%(trailers:key=Signed-off-by)`, `%C(auto)` colour. The full table is in chapter 07.

```bash
git log --date=format:'%Y-%m-%d %H:%M' --format='%ad %h %s'
git log --format='%(trailers:key=Co-authored-by,valueonly)' | sort | uniq -c
```

#### Find the commit that…

**Pickaxe** searches diffs, not messages. It's the fastest way to answer "when did this string appear or vanish".

| Flag | Finds commits where | Use for |
|---|---|---|
| `-S'STRING'` | the **count** of STRING changed (added or removed, not moved) | "when was `featureFlagX` introduced / deleted" |
| `-S'REGEX' --pickaxe-regex` | same, regex | |
| `-G'REGEX'` | any added or removed **line** matches | "when did anything touching `timeout:` change", including edits in place |

```bash
git log -S'max_connections' --oneline                     # added or removed
git log -S'max_connections' -p -- config/                 # with the patches
git log -G'timeoutSeconds:\s*[0-9]+' --oneline -- charts/ # any edit to that line shape
git log -S'API_KEY' --all --oneline                       # across every branch; secret hunting
```

> **Gotcha.** `-S` ignores a commit that only **moves** a line (count unchanged) or edits it in place without changing the count of the string. If `-S` finds nothing and you're sure it changed, use `-G`.

**Line history** follows a range or a function through every commit that changed it, including moves between line numbers:

```bash
git log -L 40,60:src/server.py              # lines 40-60
git log -L '/def reconcile/,+30:ctrl.py'    # regex start, 30 lines
git log -L :reconcile:ctrl.py               # a whole function (uses funcname rules)
```

`-L :func:` relies on the file's diff driver to find function boundaries. It works out of the box for C-like syntax; for Python, Go and others, set a driver in `.gitattributes` (`*.py diff=python`, `*.go diff=golang`) and it becomes precise. Chapter 06 covers attributes.

#### Who and why: blame

```bash
git blame -w -C -C -M path/to/file                # ignore whitespace, follow moves and copies
git blame -L 100,140 path/to/file                 # a range
git blame -L :reconcile ctrl.py                   # a function
git blame REV^ -- path/to/file                    # blame as of before REV (peel back a reformat)
git blame --ignore-rev SHA path                   # pretend SHA didn't happen
git blame --color-by-age --color-lines path
```

| Flag | Effect |
|---|---|
| `-w` | ignore whitespace changes: a reindent doesn't steal authorship |
| `-M` | detect lines moved **within** the file |
| `-C` | detect lines moved or copied from other files **changed in the same commit** |
| `-C -C` | also from files in the commit that **created** the file |
| `-C -C -C` | from **any** file in any commit (slow on big repos) |

**Pin reformat commits once so everyone's blame skips them:**

```bash
echo 'FULL_SHA_OF_BLACK_REFORMAT  # black reformat, 2026-03' >> .git-blame-ignore-revs
git config set blame.ignoreRevsFile .git-blame-ignore-revs    # per clone
git config set blame.markIgnoredLines true
```

Commit `.git-blame-ignore-revs` to the repo; trailing `# comments` on a SHA line are allowed (verified). Each clone still has to set `blame.ignoreRevsFile` itself. GitLab's web blame honours a `.git-blame-ignore-revs` at the repo root from **17.10** (behind `blame_ignore_revs`, enabled by default) and GA in **17.11** (docs.gitlab.com/user/project/repository/files/git_blame).

#### Search the tree

```bash
git grep -n 'imagePullPolicy'                      # tracked files only, fast
git grep -n -e 'TODO' --and -e 'security' -- '*.py'
git grep 'replicas:' $(git rev-list -n1 --before='2026-06-01' main) -- charts/   # as of a date
git grep -c 'import requests' -- '*.py' | sort -t: -k2 -n
git ls-files | grep -i dockerfile
```

`git grep` beats `rg` for one thing: searching **another revision** without checking it out.

### Staging exactly what you mean

#### Hunks: add -p

```bash
git add -p                     # walk every hunk
git add -p path/to/file
git restore -p path/to/file    # interactively DISCARD worktree hunks
git restore --staged -p        # interactively unstage hunks
git reset -p                   # same as above, older spelling
git stash push -p              # stash only some hunks
```

| Key | Does |
|---|---|
| `y` / `n` | stage / skip this hunk |
| `s` | **split** into smaller hunks (if there's unchanged context between changes) |
| `e` | **edit** the hunk in `$EDITOR`: delete `+` lines you don't want, turn `-` lines to context with a space |
| `a` / `d` | stage / skip this and all later hunks in the file |
| `/REGEX` | jump to a hunk matching REGEX |
| `j` `k` / `J` `K` | next/previous undecided / any hunk |
| `g` | go to hunk by number |
| `q` | quit, keep what you've decided |

The loop that produces clean commits from a messy session:

```bash
git add -p                    # stage one logical change
git diff --staged             # read exactly what you're committing
git commit                    # commit.verbose shows the diff again in the editor
# repeat until git status is clean
```

For new files, `add -p` doesn't see them until they're tracked:

```bash
git add -N newfile.py         # intent-to-add: tracked, empty in the index
git add -p newfile.py         # now hunks are selectable
```

#### restore and switch, not checkout

`git checkout` does two unrelated things (switch branches, overwrite files) and its behaviour depends on whether an argument happens to be a branch or a path. **Use `switch` and `restore`.**

| Intent | Command |
|---|---|
| go to a branch | `git switch BRANCH` |
| create and go | `git switch -c BRANCH [START]` |
| back to previous branch | `git switch -` |
| check out a tag or SHA to look around | `git switch --detach v1.2.0` |
| local branch from a remote one | `git switch BRANCH` (guesses `origin/BRANCH`) or `git switch --track origin/BRANCH` |
| switch, carrying conflicting local edits via 3-way merge | `git switch -m BRANCH` |
| discard worktree changes to a file | `git restore FILE` |
| unstage a file (keep edits) | `git restore --staged FILE` |
| file back to how it was in REV, staged and on disk | `git restore --source=REV --staged --worktree FILE` |
| a deleted file back | `git restore --source=REV^ FILE` (REV = the commit that deleted it) |

> **Gotcha.** `git restore FILE` and `git restore .` discard uncommitted changes with **no undo**: they were never objects (chapter 01). Stash first if there's any doubt: `git stash push FILE`.

### Commit hygiene

**One logical change per commit, a subject that says what and why, and a body when the why isn't obvious.** Reviewers read commits; future-you reads `git log -S` hits.

```text
charts/api: raise readiness timeout to 10s

The /healthz handler now checks the Redis connection, which takes up to
6s on a cold pool. With the 3s timeout, rollouts flapped under load.

Refs: OPS-412
```

- Subject: imperative, about 50 characters, no trailing period, scope prefix if the repo uses one.
- Blank line, then body wrapped at 72.
- Trailers last: `Refs:`, `Co-authored-by:`, `Signed-off-by:`. Add them without editing text by hand:

```bash
git commit --trailer 'Refs: OPS-412'
git commit -s                                    # Signed-off-by (DCO)
git commit --trailer 'Co-authored-by: Name <email>'
git interpret-trailers --parse < .git/COMMIT_EDITMSG
```

Fixing the last commit:

```bash
git commit --amend                     # message and/or staged content
git commit --amend --no-edit           # just fold in what's staged
git commit --amend --reset-author --no-edit   # after fixing user.email
```

Fixing an older commit is a **fixup** (full treatment in chapter 04):

```bash
git add -p
git commit --fixup=SHA                 # content into SHA
git commit --fixup=reword:SHA          # only a new message for SHA
git commit --fixup=amend:SHA           # content and a new message
git rebase -i --autosquash main        # or: git rebase --autosquash main
```

> **Note.** Commit early and often **locally**, then curate before you push. Small local commits are free undo points; the MR reviewer should see the curated story, not the keystrokes.

### Stash

Stash is a stack of commits under `refs/stash`. Each entry is a merge-shaped commit holding the worktree state, with the index state (and optionally untracked files) as extra parents.

```bash
git stash push -m 'wip: auth refactor'      # tracked changes, index + worktree
git stash push -u -m 'with untracked'       # include untracked files
git stash push -S -m 'only staged'          # only what's staged (-S / --staged)
git stash push -p                           # choose hunks
git stash push -- path/to/dir               # only these paths
git stash list
git stash show -p stash@{1}                 # the diff of an entry
git stash apply stash@{1}                   # apply, keep the entry
git stash apply --index                     # also restore what was staged vs not
git stash pop                               # apply + drop (drops only on clean apply)
git stash drop stash@{2}
git stash branch NEWBRANCH stash@{0}        # new branch at the stash's base, apply, drop
```

**Rules of thumb:**

- **Always `-m`.** `stash@{3}: WIP on main: 4f2a…` tells you nothing in a week.
- **Stash is for minutes, branches are for days.** Anything you'd be upset to lose goes on a branch as a `wip` commit; stashes are easy to drop and are never pushed.
- **`git stash branch`** is the answer when a stash won't apply cleanly because the branch has moved: it goes back to the commit you stashed from.
- A dropped or cleared stash is recoverable for a while; chapter 05 has the `fsck` recipe (verified).

> **Version-sensitive.** `git stash export --to-ref REF` and `git stash import COMMIT` (present in 2.55, verified in `git stash -h`) turn the stash stack into an ordinary ref chain you can push, and back. Useful for moving stashes between machines; older Git can't read the exported form with `stash` commands.

### Fetch, pull, push: what each moves

```text
  server                 fetch                     your clone
  refs/heads/main  ─────────────────▶  refs/remotes/origin/main
                                              │
                                   pull = fetch + (rebase | merge) into
                                              ▼
                                        refs/heads/main  (yours)
                                              │
                          push: server's refs/heads/main := yours,
                                only if fast-forward (unless forced)
```

| Command | Moves your branches? | Moves remote-tracking refs? | Changes the server? |
|---|---|---|---|
| `git fetch` | no | yes | no |
| `git pull` | **yes** (current branch) | yes | no |
| `git push` | no | yes (the pushed one) | **yes** |

**Default to `fetch` then decide.** `pull` is fine on your own feature branch with `pull.rebase = true`; on anything else, fetch, look, then merge or rebase deliberately.

```bash
git fetch --all --prune                 # every remote, drop deleted branches
git fetch origin main                   # just one branch
git log --oneline HEAD..origin/main     # what arrived
git rebase origin/main                  # replay mine on top
git merge --ff-only origin/main         # or: fast-forward only, fail if diverged
```

#### Push semantics

With `push.default = simple` and `push.autoSetupRemote = true`, bare `git push` pushes the current branch to the same-named branch on its remote and sets upstream the first time.

```bash
git push                                # current branch
git push origin HEAD:refs/heads/other   # push current commit to a differently named branch
git push origin --delete old-branch
git push origin v1.4.0                  # one tag
git push --follow-tags                  # annotated tags reachable from pushed commits
git push --atomic origin main v1.4.0    # both refs or neither
git push --dry-run                      # what would happen
```

GitLab push options create MRs and skip CI from the command line (`git push -o merge_request.create -o merge_request.target=main`, `-o ci.skip`); the glab chapters cover them and when `glab mr create` is the better tool.

#### Force-push safely

After a rebase or amend, your branch no longer contains the server's tip, so a plain push is rejected. The three ways to force, from worst to best:

| Command | Overwrites the server if… | Verdict |
|---|---|---|
| `git push --force` | always | **never on a branch anyone else touches** |
| `git push --force-with-lease` | the server's tip equals **your `origin/BRANCH`** | unsafe with background fetch |
| `git push --force-with-lease --force-if-includes` | the above, **and** your branch's history contains your `origin/BRANCH` tip | **the default** |

The failure `--force-if-includes` fixes, reproduced on 2.55:

```bash
# colleague pushes a commit to feat
# your editor/IDE runs a background `git fetch`  -> origin/feat now includes their commit
git commit --amend -m 'reword'                   # you never looked at their commit
git push --force-with-lease                      # SUCCEEDS: lease matched the fresh origin/feat
                                                 # -> their commit is silently gone
git push --force-with-lease --force-if-includes  # REJECTED: "updated since the last checkout"
```

The lease only checks that the server hasn't moved since **your last fetch**. A background fetch updates `origin/feat` without you ever integrating it, so the lease is satisfied and you clobber the commit. `--force-if-includes` additionally checks that your local branch has, at some point (via its reflog), contained the remote tip you're overwriting.

```bash
git config set --global push.useForceIfIncludes true   # applies to every --force-with-lease
git pushf                                              # alias from chapter 02
```

For scripts, pin the lease explicitly so it doesn't depend on remote-tracking state at all:

```bash
EXPECTED=$(git rev-parse origin/feat)
git push --force-with-lease=feat:"$EXPECTED" origin feat
```

> **One-way door.** Force-pushing a **shared** branch (main, release branches, a branch two people push to) drops commits from everyone else's view, breaks their next pull, and orphans review comments tied to SHAs. Recovering needs whoever still has the old tip. Protect main and release branches in GitLab so the server refuses it, and treat any force-push to a shared branch as a coordinated event.

### Upstreams, remotes and forks

#### Upstream tracking

```bash
git branch -vv                                     # see every branch's upstream
git branch --set-upstream-to=origin/feat           # set for current branch
git branch --unset-upstream
git switch -c feat --track origin/feat             # create with upstream
git rev-parse --abbrev-ref --symbolic-full-name @{u}   # name of the upstream
git remote set-head origin --auto                  # (re)learn the server's default branch
```

#### Working with a fork

The fork workflow (you push to your fork, MRs target the canonical project) has one config trick that removes all the friction: **pull from upstream, push to your fork, automatically**.

```bash
git clone git@gitlab.example.com:YOU/project.git
cd project
git remote add upstream git@gitlab.example.com:group/project.git
git fetch upstream

git config set remote.pushDefault origin            # pushes go to your fork
git config set push.default current                 # per-repo; see gotcha below
git switch -c feat upstream/main                    # branch from canonical main
git branch --set-upstream-to=upstream/main          # pulls/rebases come from canonical
git push                                            # goes to origin/feat (your fork)
git rev-parse --abbrev-ref @{u} @{push}             # upstream/main   origin/feat
```

This is the **triangular workflow**: `@{u}` (what you rebase onto) and `@{push}` (where you push) are different refs. `git status` reports ahead/behind against `@{u}`; `git log @{push}..` shows what you haven't pushed yet.

> **Gotcha.** With the global `push.default = simple`, the push itself goes to the right place in a triangular setup, but `@{push}` fails with "cannot resolve 'simple' push to a single destination" (verified on 2.55), which breaks `git log @{push}..` and any prompt that shows unpushed commits. Setting `push.default = current` in the fork clone makes `@{push}` resolve to `origin/BRANCH` (verified).

Keep your fork's main in sync without a local checkout of it:

```bash
git fetch upstream
git push origin upstream/main:main                  # fast-forward your fork's main
```

#### Checking out someone's MR

```bash
git fetch origin refs/merge-requests/IID/head:mr-IID && git switch mr-IID
# or, if you have glab: glab mr checkout IID
```

#### Multiple remotes at once

```bash
git remote -v
git remote add mirror git@backup.example.com:group/project.git
git remote set-url --add --push origin git@gitlab.example.com:group/project.git
git remote set-url --add --push origin git@backup.example.com:group/project.git
git push                                            # now pushes to both
git remote rename origin gitlab
git remote prune origin                             # drop stale remote-tracking refs once
```

### Tags

```bash
git tag -a v1.4.0 -m 'v1.4.0'            # annotated (and signed, with tag.gpgSign)
git tag -s v1.4.0 -m 'v1.4.0'            # explicitly signed
git tag v1.4.0-local                     # lightweight: just a ref, no metadata
git tag -l 'v1.*' --sort=-version:refname | head
git describe --tags --always --dirty     # v1.4.0-3-g4f2a1c9-dirty
git push origin v1.4.0
git ls-remote --tags origin
```

**Use annotated tags for anything you release.** They carry tagger, date, message and signature; `describe` and `push --follow-tags` only consider annotated tags by default.

> **One-way door.** Moving or deleting a tag that others have fetched does not propagate: their clones keep the old tag forever (fetch won't overwrite an existing tag without `--force` or `--prune-tags`). Release a new version number instead of re-pointing `v1.4.0`.

### Traps

- **`git diff A..B` is not the MR diff.** Use `A...B`.
- **Stale `origin/*`.** Ahead/behind, `@{u}` and `--force-with-lease` all trust your last fetch. Fetch first.
- **`--force-with-lease` alone is not safe** with IDEs that fetch in the background. Set `push.useForceIfIncludes`.
- **`git restore .` and `git checkout -- .` have no undo.** Stash first.
- **`add -p` skips untracked files.** `git add -N` them first.
- **`-S` misses in-place edits.** Use `-G`.
- **Pulling on main with local commits** rebases them into your next push. Fetch, look, then decide; or set `pull.ff = only` if that's your habit.
- **Re-pointing a released tag** splits the world into people with the old one and people with the new one.


---


<a id="04-rewrite-rebase-pick-revert"></a>

## 04 · Rewrite: rebase, pick, revert

*Every rewrite makes new commits and moves a ref, so the old ones are always one reflog lookup away. That makes rewriting your own unpushed branch cheap and safe, and rewriting a shared one a coordination problem, not a technical one.*

### The rule

**Rewrite freely what only you have. Revert what others have.** Everything in this chapter up to "Revert" is for your own branch before, or during, review. Rewrites create new commit IDs (chapter 01), so anyone who fetched the old IDs now has divergent history.

A feature branch in an open MR is a middle case: you own it, but reviewers have looked at specific SHAs. Rewriting it is normal on GitLab (the MR shows "compare with previous version"), as long as **nobody else pushes to it** and you push with `--force-with-lease --force-if-includes` (chapter 03).

Before any big rewrite, drop a marker. It costs nothing and turns "undo" into one command:

```bash
git branch -f backup/feat HEAD        # or: git tag -f pre-rebase
# … rewrite …
git reset --hard backup/feat          # if it went wrong
git range-diff backup/feat...HEAD     # or: compare old vs new series, commit by commit
```

### Interactive rebase

```bash
git rebase -i main                    # everything on this branch since main
git rebase -i HEAD~5                  # last five
git rebase -i --root                  # all the way to the first commit
git rebase -i --keep-base main        # edit commits without moving to main's new tip
```

**`--keep-base`** is underused: it keeps your branch on the same fork point, so you can squash and reorder mid-review without also pulling in 40 new commits from main (and a fresh CI run's worth of unrelated failures).

The todo list, as Git 2.55 prints it:

| Command | Does |
|---|---|
| `p`, `pick` | keep the commit as is |
| `r`, `reword` | keep, edit the message |
| `e`, `edit` | stop after applying, so you can amend or split |
| `s`, `squash` | meld into the previous commit, combine messages |
| `f`, `fixup` | meld into previous, **keep previous message** |
| `fixup -C` | meld into previous, **keep this commit's message** |
| `fixup -c` | same as `-C` but open the editor |
| `x`, `exec CMD` | run a shell command; a non-zero exit stops the rebase |
| `b`, `break` | stop here; `git rebase --continue` resumes |
| `d`, `drop` | remove the commit |
| `l`, `label` / `t`, `reset` / `m`, `merge` | rebuild merge topology (with `--rebase-merges`) |
| `u`, `update-ref REF` | move REF to this point at the end (added by `--update-refs`) |

With `rebase.missingCommitsCheck = error` (chapter 02), deleting a line is an error; write `drop` when you mean it.

During a stopped rebase:

```bash
git status                            # what's happening and what's next
git rebase --continue                 # after resolving/amending
git rebase --skip                     # drop the commit that's being applied
git rebase --abort                    # put everything back as it was before
git rebase --edit-todo                # change the remaining plan
git rebase --show-current-patch       # the commit currently being applied
```

#### Run tests on every commit

A series where each commit builds is a series you can bisect (chapter 05). Prove it before you push:

```bash
git rebase -x 'make test' main                    # exec after every pick
git rebase -x 'make lint' -x 'make test' main
git rebase --reschedule-failed-exec -x 'make test' main   # retry exec after you fix it
```

When an exec fails, the rebase stops **after** that commit is applied: fix, `git commit --amend`, then `git rebase --continue`.

### Fixup and autosquash

The fastest way to keep a branch clean while working: commit fixes as fixups aimed at the commit they belong to, and let rebase fold them in.

```bash
git add -p
git commit --fixup=SHA                # "fixup! <subject of SHA>"
git commit --fixup=amend:SHA          # "amend! …": content plus a replacement message (opens editor)
git commit --fixup=reword:SHA         # message only, no content
git commit --squash=SHA               # "squash! …": combine messages at rebase time

git rebase -i --autosquash main       # todo is pre-arranged; just save
git rebase --autosquash main          # non-interactive: applies them directly
```

Verified on 2.55: `rebase.autoSquash = true` only affects **interactive** rebases. A plain `git rebase main` leaves `fixup!` commits in place; pass `--autosquash` when you want it without `-i`.

Aim a fixup by message instead of SHA:

```bash
git commit --fixup=':/add readiness probe'     # newest commit whose message matches
git commit --fixup="$(git log --format=%h -1 --grep='readiness' main..)"
```

`gfix` in chapter 02 wraps the fzf-pick, fixup and autosquash into one command.

#### git history: the no-rebase shortcut

Git 2.55 ships an experimental `git history` command for the three most common edits. It rewrites **without touching the worktree or index** (except `fixup`, which reads the index), runs no hooks, and moves **every descendant branch** automatically.

```bash
git add -p && git history fixup SHA          # fold staged changes into SHA
git history reword SHA                       # edit SHA's message in $EDITOR
git history split SHA -- path/one path/two   # interactively split hunks out into a new parent commit
git history fixup SHA --dry-run              # print the ref updates instead of doing them
```

Verified on 2.55: `fixup` and `reword` rewrote an older commit and moved a second branch based on it, with no rebase state.

> **Version-sensitive.** `git history` is marked EXPERIMENTAL in 2.55: behaviour may change. It refuses histories containing merges and refuses any operation that would conflict. Use it for quick surgery on a linear branch; use `rebase -i` for anything else.

### Stacked branches: --update-refs

A stack is several branches, each building on the previous, each its own MR:

```text
  main ──●──●
            \
             A1──A2          feat/api       (MR 1: target main)
                   \
                    B1──B2   feat/client    (MR 2: target feat/api)
```

Without help, rebasing `feat/client` onto new main rewrites `A1` and `A2` into `A1'` `A2'` under `feat/client`, but `feat/api` still points at the old `A2`. The stack comes apart.

**`--update-refs` moves every branch that points into the rebased range.** Verified on 2.55:

```bash
git switch feat/client
git rebase --update-refs origin/main
# Successfully rebased and updated refs/heads/feat/client.
# Updated the following refs with --update-refs:
#	refs/heads/feat/api
```

With `rebase.updateRefs = true` (chapter 02) it's automatic. In `rebase -i`, each branch shows up as an `update-ref refs/heads/…` line; you can move commits across those lines to shift a commit from one MR to another.

Push the whole stack in one go:

```bash
git push --force-with-lease --force-if-includes origin feat/api feat/client
```

> **Note.** `glab stack` offers a stacked-diff workflow with one MR per layer; see the glab chapters. Underneath, it is still branches and rebases, and `--update-refs` is what keeps a hand-built stack together.

#### When the bottom of the stack gets squash-merged

A squash merge puts one new commit `S` on main containing A1+A2's changes. Your `feat/client` still contains `A1` and `A2`, which Git does not recognise as already merged. Rebasing onto main replays them and conflicts with `S`.

**Cut the old base off with `--onto`:**

```bash
git fetch origin
git rebase --onto origin/main feat/api feat/client
#                 new base    old base (exclude up to here)  branch to move
```

```text
  before:  main ──●──S                      after:  main ──●──S
                 \                                            \
                  A1──A2 (feat/api)                            B1'──B2' (feat/client)
                        \
                         B1──B2 (feat/client)
```

### rebase --onto, in general

`git rebase --onto NEWBASE UPSTREAM BRANCH` means: **take the commits in `UPSTREAM..BRANCH` and replay them on `NEWBASE`.**

| Situation | Command |
|---|---|
| branched from the wrong branch (from `develop`, should be `main`) | `git rebase --onto main develop feat` |
| drop commits 2 and 3 of 5 (C1..C5 on top of X) | `git rebase --onto C1 C3 feat` |
| copy the last 3 commits onto a new branch off main | `git switch -c new && git rebase --onto main HEAD~3` (then reset the old branch if they shouldn't stay there) |
| parent branch was squash-merged | `git rebase --onto origin/main OLD_PARENT child` |
| parent branch was rebased (and you have its old tip in reflog) | `git rebase --onto parent parent@{1} child` |

`--fork-point` (the default when you rebase against the configured upstream with no argument) uses the upstream's reflog to guess the old base automatically. That's why a bare `git rebase` after someone rewrote `main` often does the right thing and an explicit `git rebase origin/main` sometimes doesn't.

#### git replay (experimental)

`git replay` does a rebase **without a worktree**: it computes the new commits in memory and atomically updates refs. It exists for servers and scripts.

```bash
git replay --onto origin/main origin/main..feat --ref-action=print   # print update-ref commands
git replay --onto origin/main origin/main..feat                     # update refs atomically
git replay --contained --onto origin/main origin/main..feat/client  # also move branches inside the range
```

> **Version-sensitive.** `git replay` is EXPERIMENTAL in 2.55 (flags verified via `git replay -h`). It stops on the first conflict rather than letting you resolve it. Useful in CI bots; `rebase` remains the interactive tool.

### Cherry-pick

```bash
git cherry-pick SHA                  # one commit
git cherry-pick -x SHA               # adds "(cherry picked from commit …)": use on release branches
git cherry-pick A^..B                # A through B inclusive
git cherry-pick A..B                 # AFTER A through B: A itself is excluded
git cherry-pick -n SHA               # apply to index/worktree, don't commit
git cherry-pick -m 1 MERGE_SHA       # a merge's changes relative to its first parent
git cherry-pick --continue | --skip | --abort
```

> **Gotcha.** `A..B` excludes `A`. Verified on 2.55: `git cherry-pick cp~2..cp` picked `cp2` and `cp3`, not `cp1`. For "these three commits", write `FIRST^..LAST` or `LAST~3..LAST`.

**Use `-x` for backports.** The trailer records the source SHA, so `git log --grep='cherry picked from commit SHA'` finds every backport of a fix, and anyone reading the release branch can trace it to main.

**Prefer fix-on-main-then-pick-to-release** over fix-on-release-then-merge-back. Merging a release branch into main drags in version bumps and release-only hacks; cherry-picks move exactly one change.

Find which commits are already on the other side (by patch content, not SHA):

```bash
git cherry -v release/1.4 main       # "+" = not yet on release/1.4, "-" = equivalent patch present
git log --cherry-pick --right-only --oneline release/1.4...main
```

### Revert

Revert makes a **new commit** that undoes an old one. History only grows, so it's safe on shared branches.

```bash
git revert SHA                       # opens editor for the message
git revert --no-edit SHA
git revert A^..B                     # a range, one revert commit per commit (newest first)
git revert -n A^..B && git commit -m 'Revert feature X (A..B)'   # a range as one commit
git revert --continue | --abort
```

#### Reverting a merge: -m

A merge commit has two parents, so "undo this commit" is ambiguous. `-m 1` means "undo what this merge brought in, relative to parent 1 (the branch it was merged into)". That's almost always what you want for a merged MR.

```bash
git revert -m 1 MERGE_SHA
```

Without `-m`, Git refuses (verified on 2.55: "commit … is a merge but no -m option was given").

> **Gotcha.** **Reverting a merge doesn't unmerge the branch.** Git still considers the branch's commits merged, because they are ancestors of main. If the branch is later fixed and merged again, **only commits made after the first merge come in**, and the original changes stay reverted. Verified on 2.55: re-merging the topic after reverting its merge brought only the new commit, and conflicted with the revert's deletion. The fix is to **revert the revert first**, then merge the new work:

```bash
git revert REVERT_SHA                # re-apply the original changes
git merge topic                      # now the follow-up commits apply cleanly
```

> **Note.** The same applies to GitLab's "Revert" button on a merged MR: it creates a revert of the merge commit (or of the squash commit). Re-landing the feature needs a revert of that revert, not a fresh MR of the same branch.

### Conflicts

#### Read the conflict before touching it

With `merge.conflictStyle = zdiff3` (chapter 02) every conflict shows three versions, verified on 2.55:

```text
a
<<<<<<< HEAD
B2
||||||| 08c561c
b
=======
B1
>>>>>>> x
c
```

Read it as: **the base had `b`; our side changed it to `B2`; their side changed it to `B1`.** The resolution must reflect both *changes*, not pick one *result*. Without the base section you can't tell whether a side added, removed or modified a line, which is how conflict resolutions silently lose one side's fix.

```bash
git status                           # which files are unmerged
git diff                             # combined diff of all conflicts
git diff --name-only --diff-filter=U # just the conflicted paths
git log --merge -p -- FILE           # commits on either side that touched FILE
git show :1:FILE                     # base version
git show :2:FILE                     # ours
git show :3:FILE                     # theirs
```

#### Ours and theirs flip during rebase

| Operation | `--ours` / `HEAD` / stage 2 | `--theirs` / stage 3 |
|---|---|---|
| `merge feat` (on main) | main (where you are) | feat (being merged in) |
| `rebase main` (on feat) | **main**, plus your already-replayed commits | **your commit** being replayed |
| `cherry-pick X` | where you are | X |
| `revert X` | where you are | the inverse of X |

During a rebase you're standing on the new base, replaying your commits onto it, so **"ours" is upstream and "theirs" is you**. Everybody gets this wrong at least once.

#### Resolution strategies, by case

| Case | Do |
|---|---|
| Take one side for a whole file | `git restore --ours FILE` or `--theirs FILE`, then `git add FILE` |
| Lockfiles (`package-lock.json`, `poetry.lock`, `go.sum`) | take either side, then **regenerate** with the package manager, then `git add` |
| Generated files (CRDs, mocks, compiled assets) | take either side, regenerate, `git add` |
| Both sides reformatted the same file | abort; land the reformat alone first; redo |
| Renamed on one side, edited on other | Git usually follows it; if not, apply the edit to the new path by hand, `git rm` the old |
| Deleted on one side, modified on other | decide: `git rm FILE` (keep the deletion) or `git add FILE` (keep the edit) |
| Many trivial conflicts in a long rebase | `git rebase --abort`, then `git merge` instead: one conflict resolution rather than one per commit |
| Want a visual tool | `git mergetool` (set `merge.tool`, e.g. `vimdiff`, `meld`) |

Merge-level options for when you know the answer in advance:

```bash
git merge -X theirs feat              # resolve *conflicting hunks* in favour of feat; clean hunks merge normally
git merge -X ours feat                # same, favour current branch
git merge -s ours old-branch          # record a merge but keep our tree entirely (discard theirs); rare
git merge -X ignore-space-change feat
git rebase -X theirs main             # during rebase "theirs" = your commits (see table)
```

> **Gotcha.** `-X ours` (strategy **option**) and `-s ours` (strategy) are completely different. `-X ours` merges normally and only picks our side where hunks conflict. `-s ours` throws away every change from the other branch and just records the merge. Confusing them silently drops work.

#### Preview a merge without doing it

```bash
git merge-tree --write-tree --name-only main feat
echo $?                              # 0 = clean, 1 = conflicts (verified)
```

`merge-tree --write-tree` performs a real merge entirely in the object store: no worktree, no index, no state to clean up. Use it in scripts to ask "would this MR merge cleanly onto main?".

#### After you resolve

```bash
git add FILE                          # marks resolved: collapses stages 1-3 to stage 0
git diff --staged                     # what the resolution actually changed
git merge --continue                  # or: git rebase --continue / cherry-pick --continue
```

`git log --remerge-diff` on a merge commit later shows exactly how its conflicts were resolved (the difference between an automatic merge and what was committed). It's the right tool to review someone else's conflict resolution.

```bash
git show --remerge-diff MERGE_SHA
git log --remerge-diff --merges -5
```

### rerere

**rerere** (reuse recorded resolution) remembers how you resolved each conflict hunk and replays it when the same conflict appears again. It pays for itself on long-lived branches you rebase repeatedly, and on "test merge into main, abort, merge again later" workflows.

```bash
git config set --global rerere.enabled true
```

Verified on 2.55: after resolving a conflict once, resetting and repeating the merge printed `Resolved 'z' using previous resolution.` and the file already held the resolution. Without `rerere.autoUpdate`, the file stays marked unmerged so you still have to `git add` it; **keep it that way**, so a replayed resolution gets a look before it's committed.

```bash
git rerere status                    # paths rerere is tracking right now
git rerere diff                      # what rerere applied vs the conflict
git rerere forget FILE               # the recorded resolution was wrong; forget it
ls .git/rr-cache/                    # the recorded pre/post images
```

> **Gotcha.** rerere replays a **wrong** resolution as faithfully as a right one, across every future rebase. If you resolved something badly, `git rerere forget FILE` before redoing it, or it comes back.

Train rerere from history (e.g. before a big rebase of a branch that already has merges from main): the `rerere-train.sh` script replays past merges to populate the cache. On Fedora 43 it ships in the `git` package at `/usr/share/doc/git/contrib/rerere-train.sh` (verified present):

```bash
sh /usr/share/doc/git/contrib/rerere-train.sh origin/main~500..origin/main   # learn from merges in that range
```

### Splitting a commit

#### With rebase -i

```bash
git rebase -i SHA^                   # mark SHA as "edit"
# rebase stops after applying SHA
git reset HEAD^                      # un-commit it; changes are now unstaged
git add -p                           # stage the first logical piece
git commit -m 'first piece'
git add -p
git commit -m 'second piece'
git rebase --continue
```

`git reset HEAD^` (mixed) keeps the changes in the worktree and clears the index, which is exactly the state you want for re-staging in pieces. The original message is gone at this point; retrieve it with `git log -1 --format=%B ORIG_HEAD` if you want to reuse it.

#### With git history split

```bash
git history split SHA                 # choose hunks to move into a new parent commit
git history split SHA -- path/a       # only consider changes under path/a
```

One command, no rebase state, descendant branches moved automatically. Same experimental caveats as above.

#### Split one file out of the last commit

```bash
git reset HEAD^ -- path/to/file      # index: file as it was before the commit
git commit --amend --no-edit         # last commit now excludes that file
git add path/to/file
git commit -m 'separate change to file'
```

### Squash everything into one commit

```bash
git reset --soft $(git merge-base HEAD origin/main)
git commit                           # one commit with all the changes; write a real message
```

`reset --soft` moves the branch back to the fork point and leaves the index holding the final state, so the next commit contains everything. Faster than `rebase -i` with 30 `s` lines.

### Traps

- **Rebasing a branch someone else pushes to.** Their next pull duplicates every commit. Agree first, or merge instead.
- **`A..B` in cherry-pick excludes `A`.** Use `A^..B`.
- **"ours" and "theirs" swap during rebase.** Upstream is ours; your commit is theirs.
- **`-X ours` versus `-s ours`.** One resolves conflicts; the other discards the other branch entirely.
- **Reverting a merge then re-merging the branch.** Only new commits land. Revert the revert.
- **rerere replays bad resolutions.** `git rerere forget FILE`.
- **FIDO-signed rebases need a touch per commit.** Script with `--no-gpg-sign`, re-sign at the keyboard.
- **Stacks come apart without `--update-refs`.** Set `rebase.updateRefs = true`.
- **Squash-merged parent in a stack.** `rebase --onto origin/main OLD_PARENT child`, not a plain rebase.
- **Long rebase, same conflict per commit.** Abort and merge, or enable rerere and grind through once.


---


<a id="05-recover-and-undo"></a>

## 05 · Recover and undo

*If it was ever committed or stashed, it's still in the object store, and the reflog knows where. Recovery is almost always "find the SHA, point a branch at it". The only truly lost work is work that never became an object.*

### First: stop and mark

Before you try to fix anything, do two things that can't make it worse:

```bash
git status                                   # is an operation in progress? (rebase, merge, cherry-pick, bisect)
git branch rescue/$(date +%H%M) HEAD         # pin where you are now
```

Then **don't run `git gc`, `git prune`, `git reflog expire` or `git stash clear`** until you've found what you're after. Everything below relies on objects that those commands delete.

If an operation is in progress, the cleanest undo is usually its own abort:

```bash
git rebase --abort
git merge --abort
git cherry-pick --abort
git revert --abort
git am --abort
git bisect reset
```

### The reflog

Every time a ref moves (commit, reset, rebase, checkout, merge, pull, amend), Git appends a line to that ref's reflog: old value, new value, what did it. **HEAD has its own reflog** that records every checkout too.

```bash
git reflog                                   # HEAD's reflog, newest first
git reflog show feat                         # one branch's reflog
git reflog --date=iso                        # with timestamps
git log -g --format='%h %gd %gs %s' -20      # reflog as a log, with commit subjects
```

A real one (from a lab repo on 2.55):

```text
d3e44d9 HEAD@{0}: reset: moving to HEAD~1
6f4f8e4 HEAD@{1}: commit: lost
d3e44d9 HEAD@{2}: checkout: moving from a8f833f… to main
```

The commit `6f4f8e4` is no longer on any branch, but the reflog still points at it. Recovery:

```bash
git branch recovered 6f4f8e4                 # or: git reset --hard HEAD@{1}
```

Reflog syntax is also revision syntax:

| Expression | Means |
|---|---|
| `HEAD@{1}` | where HEAD was one move ago |
| `feat@{1}` | where `feat` was before its last move (e.g. before the rebase) |
| `feat@{2.hours.ago}` | where `feat` was two hours ago |
| `main@{yesterday}` | where your local `main` was yesterday |
| `@{-1}` | the branch you were on before the last checkout |

> **Gotcha.** Reflogs are **local, per clone, and per ref**. A fresh clone has an empty reflog. Deleting a branch with `git branch -D` deletes its own reflog too, but HEAD's reflog still has the commits if you ever had that branch checked out.

Expiry defaults (from `git help config`, 2.55): entries for commits still reachable from the ref's tip live 90 days (`gc.reflogExpire`); entries for commits no longer reachable (amended, rebased away, reset away) live **30 days** (`gc.reflogExpireUnreachable`).

### ORIG_HEAD

Operations that move HEAD a long way (`reset`, `rebase`, `merge`, `pull`, `am`) save the previous HEAD in `ORIG_HEAD` first. It's the one-step undo for the last big move:

```bash
git reset --hard ORIG_HEAD                   # undo the last rebase / merge / reset
git range-diff ORIG_HEAD...HEAD              # what did that rebase change, commit by commit
git diff ORIG_HEAD HEAD                      # what did that pull bring in
```

`ORIG_HEAD` is overwritten by the next such operation, so it's only good for "the thing I just did". For anything further back, use the reflog.

### Reset: the three modes and a fourth

`git reset REV` moves **the current branch** to REV. The mode says what happens to the index and worktree.

```text
                 branch ref   index        worktree     untracked
  --soft         moved        unchanged    unchanged    unchanged
  --mixed (def)  moved        = REV        unchanged    unchanged
  --hard         moved        = REV        = REV        unchanged (but see clean)
  --keep         moved        = REV        = REV, refuses if it would lose local edits
```

| Mode | Use for |
|---|---|
| `--soft` | uncommit, keep everything staged: squash the last N commits, redo a commit message and content |
| `--mixed` | uncommit and unstage, keep the edits: re-split changes into different commits |
| `--hard` | throw away commits **and uncommitted edits**: back to a known state |
| `--keep` | move the branch like `--hard`, but abort if any file you've locally modified would be overwritten |

**Pick `--keep` over `--hard`** when you mean "move this branch, and I think my tree is clean". If you're wrong about the tree, `--keep` refuses; `--hard` destroys the edits with no reflog to save them.

```bash
git reset --soft HEAD~3 && git commit        # squash last 3 into one
git reset HEAD~1                             # uncommit, keep edits unstaged
git reset --keep origin/main                 # move branch to server state, refuse if dirty
git reset --hard origin/main                 # same, and discard any edits
git reset -- FILE                            # path form: unstage FILE (= restore --staged)
```

> **One-way door.** `git reset --hard` and `git clean -fdx` destroy **uncommitted** work permanently; it was never an object, so no reflog or `fsck` can bring it back. `git stash -u` first if there's any doubt, or use `--keep`. For `clean`, always run `git clean -nd` (dry run) before `-fd`.

### The undo table

"I did X. How do I undo it?"

| I did | Undo | Notes |
|---|---|---|
| committed to the wrong branch (not pushed) | `git branch right-branch && git reset --keep HEAD~1 && git switch right-branch` | the commit stays on the new branch |
| committed with the wrong message | `git commit --amend` | last commit only; older: `--fixup=reword:SHA` |
| committed with the wrong author email | `git commit --amend --reset-author --no-edit` | fix `user.email` first |
| forgot a file in the last commit | `git add FILE && git commit --amend --no-edit` | |
| committed something that should be two commits | `git reset HEAD~1`, then `add -p` twice | chapter 04 for older commits |
| staged something by mistake | `git restore --staged FILE` | edits stay |
| edited a file and want the committed version back | `git restore FILE` | **edits are gone** |
| deleted a file (uncommitted) | `git restore FILE` | |
| deleted a file in a commit | `git restore --source=SHA^ FILE` | SHA = the deleting commit |
| amended and want the pre-amend commit | `git reset --soft HEAD@{1}` | reflog |
| rebased and it went wrong | `git reset --hard ORIG_HEAD` (or `feat@{1}`) | |
| merged and shouldn't have (not pushed) | `git reset --hard ORIG_HEAD` | |
| merged and pushed | `git revert -m 1 MERGE_SHA` | chapter 04: re-merging needs a revert of the revert |
| pushed a bad commit to a shared branch | `git revert SHA && git push` | never rewrite shared history to undo |
| `reset --hard` to the wrong place | `git reset --hard HEAD@{1}` | committed work only |
| deleted a branch | `git reflog`, find its tip, `git branch NAME SHA` | also printed by `branch -D` itself |
| dropped or cleared a stash | fsck recipe below | |
| force-pushed over someone's commits | their clone or your reflog has the old tip: `git push --force-with-lease origin OLD_SHA:BRANCH` | coordinate first |
| pulled and got a surprise merge commit | `git reset --hard ORIG_HEAD`, then `git pull --rebase` | |
| `git checkout -- .` / `git restore .` | **nothing** | uncommitted edits were never objects; check your editor's local history |
| committed a secret | see "A leaked secret" below | **rotate first** |
| deleted a tag locally | `git fetch origin tag NAME` | if it exists on the server |
| deleted a tag on the server | `git push origin NAME` from any clone that still has it | |

When `git branch -D` runs, it prints the SHA it deleted (`Deleted branch feat (was 4f2a1c9).`). **That line is your undo**: `git branch feat 4f2a1c9`.

### Lost commits: fsck

When the reflog doesn't have it (you deleted the branch's reflog, the commit was made in detached HEAD long ago, or it's a stash), search the object store for **dangling** objects: objects nothing references.

```bash
git fsck --unreachable --no-reflogs | grep commit          # commits not reachable from refs (ignoring reflogs)
git fsck --lost-found                                      # also writes them to .git/lost-found/{commit,other}/
```

Turn the list into something readable:

```bash
git fsck --unreachable --no-reflogs 2>/dev/null \
  | awk '/commit/ {print $3}' \
  | xargs git log --no-walk --format='%h %ci %s' \
  | sort -k2 -r | head -30
```

`--no-reflogs` treats reflog-only commits as unreachable too, so you see everything that isn't on a branch or tag, which is usually what you want when hunting.

For blobs (a file you `git add`ed but never committed, then lost with `reset --hard`):

```bash
git fsck --lost-found
ls .git/lost-found/other/                   # each file is a blob named by SHA
git show SHA_OF_BLOB > recovered.txt
grep -l 'distinctive string' .git/lost-found/other/*
```

That last case is the one exception to "uncommitted work is gone": **anything you staged was hashed into a blob**, so it's recoverable by content even if you never committed it.

#### Dropped stashes

A stash entry is a commit. When you `drop` or `clear`, the commit becomes dangling. Its subject gives it away: `On BRANCH: MESSAGE` or `WIP on BRANCH: …`. The index commit that belongs to it reads `index on BRANCH: …`, so filter that out.

```bash
git fsck --unreachable --no-reflogs 2>/dev/null \
  | awk '/commit/ {print $3}' \
  | xargs git log --no-walk --format='%h %s' \
  | grep -E '^[0-9a-f]+ (On|WIP on) '
# 07bfc1b On main: important wip       <- verified on 2.55 after `stash drop`

git stash apply 07bfc1b                      # apply it directly by SHA
git stash store -m 'recovered' 07bfc1b       # or put it back on the stack
```

This is one more reason to **always use `stash push -m`**: a message makes the dangling commit findable by grep.

### Detached HEAD work

You checked out a tag or SHA, committed, then switched away. Git warns you on the switch, and prints the SHA:

```text
Warning: you are leaving 2 commits behind, not connected to any of your branches:
  9c1e2f0 fix probe
  ...
If you want to keep them by creating a new branch, this may be a good time to do so with:
 git branch <new-branch-name> 9c1e2f0
```

If you missed it: `git reflog | grep 'moving from'` shows each checkout; the SHA just before you left detached HEAD is the tip of the lost work.

### Bisect

Bisect binary-searches history for the commit that introduced a change. With 1,000 commits between good and bad, it takes about 10 steps.

```bash
git bisect start BAD GOOD                    # e.g. git bisect start HEAD v1.4.0
# Git checks out the midpoint. Test it, then:
git bisect good                              # or: git bisect bad
# repeat until it prints "<SHA> is the first bad commit"
git bisect reset                             # back to where you started
```

#### bisect run

Make the test a script and let Git drive. Exit codes decide each step:

| Exit code | Means |
|---|---|
| `0` | good |
| `1`–`127` except `125` | bad |
| `125` | **skip**: can't test this commit (doesn't build) |
| `128`+ or killed by signal | abort the bisect |

```bash
git bisect start HEAD v1.4.0
git bisect run make test
git bisect run ./scripts/check-regression.sh
git bisect run sh -c 'make build || exit 125; ./bin/app --selftest'
git bisect reset
```

Verified on 2.55: with 20 commits and `git bisect run sh -c '[ "$(cat n)" -lt 13 ]'`, it identified `c13` as the first bad commit unattended.

A good bisect script:

- **Builds first, and exits `125` if the build fails**, so unrelated breakage is skipped instead of blamed.
- **Tests only the one behaviour**, not the whole suite, so an unrelated flaky test doesn't mislead the search.
- **Lives outside the repo** (or is copied to `/tmp`), because checking out old commits may delete or change it.

#### Bisect options worth knowing

```bash
git bisect start --first-parent HEAD v1.4.0  # only walk mainline merges: "which MR broke it"
git bisect start HEAD v1.4.0 -- charts/      # only commits touching charts/
git bisect start --term-old=fast --term-new=slow HEAD v1.4.0   # not a bug: a behaviour change
git bisect skip                              # this one can't be tested
git bisect log > bisect.log                  # save the session
git bisect replay bisect.log                 # replay it (after fixing a wrong good/bad)
git bisect visualize --oneline               # remaining candidates
```

**`--first-parent`** is the right default on a repo that merges MRs with merge commits: it finds the merge that broke things (one step per MR) instead of dropping you into the middle of someone's half-finished WIP commits. Once you have the MR, bisect inside it if you need to.

> **Gotcha.** Bisect assumes the property flips once: good, good, good, bad, bad. If the bug came and went (fixed then reintroduced), bisect finds *a* transition, not necessarily the one you care about. Narrow `GOOD` to after the earlier fix.

### A leaked secret

A token, password or key was committed. The order matters:

1. **Rotate the credential. Now.** Revoke the leaked one at its source (GitLab PAT, cloud key, database password), issue a new one, deploy it. Do this before touching history.
2. **Assume it's compromised.** Check the credential's audit logs for use since the commit time.
3. **Then decide whether to rewrite history.** Rewriting is cleanup, not remediation.

> **One-way door.** **Rewriting history does not un-leak a secret.** Anyone who cloned, forked or fetched since the commit has it; CI job logs, caches, MR diffs, container image layers and backups may too. On GitLab, MR diffs and refs under `refs/merge-requests/*` and `refs/pipelines/*` keep the old commits reachable on the server even after a force-push. Rotation is the fix; rewriting only stops the secret spreading further.

#### If it was never pushed

It only exists locally. Remove it from the commit and move on:

```bash
git rm --cached secrets.env && echo 'secrets.env' >> .gitignore
git commit --amend --no-edit                 # if it's in the last commit
# older commit: git rebase -i, mark it edit, remove, amend, continue
git reflog expire --expire=now --all && git gc --prune=now   # purge the old objects locally
```

Still rotate if the value was ever real and anything else (a shell history, a CI variable dump, a screen share) could have seen it.

#### If it was pushed: filter-repo

**Use `git filter-repo`**, not `git filter-branch` (which Git's own docs warn against) and not BFG (unmaintained, and filter-repo covers its use cases).

```bash
sudo dnf install git-filter-repo              # 2.47.0 in Fedora 43 (verified in repo metadata)
```

> **Note.** git-filter-repo isn't installed on the machine this guide was verified on, so nothing below was executed. The options were checked against the upstream manual and the v2.47.0 source (github.com/newren/git-filter-repo); 2.47.0 is still the latest release.

Work on a **fresh mirror clone**. filter-repo refuses to run on a repo that isn't a fresh clone unless you pass `--force`, precisely so it can't destroy local-only work.

```bash
git clone --mirror git@gitlab.example.com:group/project.git project-clean.git
cd project-clean.git
git filter-repo --analyze                    # reports in filter-repo/analysis/: biggest blobs, paths, renames

# Option A: remove a file from all history
git filter-repo --sensitive-data-removal --invert-paths --path config/secrets.env

# Option B: replace the secret string wherever it appears, keep the files
cat > /tmp/replacements.txt <<'EOF'
glpat-XXXXXXXXXXXXXXXXXXXX==>REDACTED
regex:AKIA[0-9A-Z]{16}==>REDACTED_AWS_KEY
EOF
git filter-repo --sensitive-data-removal --replace-text /tmp/replacements.txt
shred -u /tmp/replacements.txt               # it contains the secret
```

| Option | Does |
|---|---|
| `--sensitive-data-removal` (`--sdr`) | fetches all refs first, records the first changed commits, reports orphaned LFS objects, and prints cleanup steps for the server and other clones |
| `--invert-paths --path P` | remove P (file or directory) everywhere in history |
| `--replace-text FILE` | `literal==>replacement`, `regex:…==>…`, `glob:…==>…`; default replacement `***REMOVED***` |
| `--strip-blobs-bigger-than 10M` | drop large blobs (the "someone committed a 2 GB dump" case) |
| `--analyze` | report only, no rewrite |
| `--force` | skip the fresh-clone check; **the rewrite ends by expiring reflogs and pruning**, so the old history is gone locally |

> **Version-sensitive.** `--sensitive-data-removal` arrived in filter-repo **2.47.0** (absent from 2.45.0); Fedora 43 ships 2.47.0. On an older build, run the same filters without it and follow the cleanup steps below by hand.

Then:

```bash
# verify the secret is gone from every ref
git log --all -S'glpat-XXXXXXXXXXXXXXXXXXXX' --oneline     # should print nothing
git grep 'glpat-' $(git rev-list --all) | head             # slow on big repos; should print nothing

# push the rewritten history over the server's (branches and tags)
git push --force --mirror origin
```

> **Gotcha.** A normal filter-repo run removes the `origin` remote afterwards as a safety measure; **with `--sensitive-data-removal` it keeps `origin`** (the push-back is the point) and prints the exact push command. Without `--sdr`, re-add it with `git remote add origin URL` before pushing. On GitLab, protected branches reject the force-push until you temporarily allow it, and the read-only `refs/merge-requests/*` refs make `--mirror` report errors for those refs; that's expected.

**Server side**: a force-push alone leaves the old objects on the GitLab server, reachable from MR refs and kept until housekeeping. GitLab (17.9+ GA, Owner role) has **Settings > Repository > Repository maintenance > Remove blobs** (by blob ID) and **Redact text**; afterwards run **Settings > General > Advanced > Run housekeeping**, then **Prune unreachable objects** (docs.gitlab.com/user/project/repository/repository_size). The blob IDs from `--analyze` are what you feed Remove blobs. Open MRs may need a manual rebase afterwards.

**Everyone else's clones** still contain the secret and, worse, the old history. If one colleague pushes their stale branch, the secret is back. Tell them to:

```bash
# simplest and safest: delete the clone and re-clone
# or, if they have local work to keep:
git fetch --prune --prune-tags origin
git rebase --onto origin/main OLD_MAIN_SHA my-branch        # replay their own commits only
git reflog expire --expire=now --all && git gc --prune=now
```

> **One-way door.** A history rewrite changes every commit ID from the first affected commit onward. Every open MR, every pinned SHA in CI or Helm values, every `Refs: SHA` in a ticket, and every fork is now pointing at history that no longer exists on the server. Announce it, freeze pushes, rewrite, then unfreeze.

#### Prevent the next one

- GitLab's secret push protection and secret detection in CI (see the GitLab chapters) stop it at the server.
- A client-side `pre-commit` hook running `gitleaks git --pre-commit --staged` (or similar) stops it on your machine; chapter 06 covers hooks.
- `.gitignore` the usual suspects (`*.env`, `*.pem`, `*.key`, `kubeconfig*`, `*.tfstate`) at the project level, not just globally.

### gc, packs and repository health

`git gc` packs loose objects, removes unreachable objects past their grace period, expires reflogs and packs refs. Git runs it automatically (`gc.auto`, by default after about 6,700 loose objects) and you rarely need to run it by hand.

```bash
git count-objects -vH                        # loose objects, pack count, sizes
git gc                                       # normal housekeeping
git gc --aggressive                          # much slower, somewhat smaller; rarely worth it
git maintenance run --task=gc                # same, via maintenance
git fsck --full                              # verify object integrity
git verify-pack -v .git/objects/pack/pack-*.idx | sort -k3 -n | tail -5    # biggest objects in a pack
```

**What gc will delete**, and the timers that protect you (defaults from `git help config` on 2.55):

| Thing | Deleted after |
|---|---|
| reflog entries for commits still on the tip | 90 days (`gc.reflogExpire`) |
| reflog entries for rewritten-away commits | 30 days (`gc.reflogExpireUnreachable`) |
| unreachable loose objects (and cruft pack contents) | 2 weeks (`gc.pruneExpire`) |

So: an amended-away commit stays in the reflog 30 days; once its reflog entry expires, it becomes unreachable and survives another two weeks before prune. Recovery windows are generous, **as long as nobody runs `gc --prune=now`**.

> **One-way door.** `git reflog expire --expire=now --all && git gc --prune=now` is the purge. It's the right final step after removing a secret, and the wrong command to run "to clean up" in any other situation, because it deletes every recovery path this chapter describes.

#### Packs

Objects are stored in packfiles (`.git/objects/pack/pack-*.pack` plus `.idx`), delta-compressed against similar objects. Many small packs slow lookups; `gc` or maintenance consolidates them. Cruft packs (`gc.cruftPacks`, default true in 2.55) hold unreachable objects with their mtimes, so pruning doesn't have to explode them into millions of loose files.

For big repos, prefer scheduled incremental maintenance over periodic full `gc` (chapter 06):

```bash
git maintenance start                         # hourly prefetch + commit-graph, daily incremental repack
```

### Traps

- **`reset --hard` and `restore .` have no undo for uncommitted edits.** Stash, or use `reset --keep`.
- **`git clean -fdx` deletes ignored files too** (your `.env`, local config, build caches). Run `-n` first.
- **Reflogs are local.** Recovery happens on a machine that had the commit.
- **`gc --prune=now` and `reflog expire --expire=now` delete the safety net.** Only as the last step of a deliberate purge.
- **Rewriting history doesn't revoke a leaked secret.** Rotate first; rewrite second; clean the server; re-clone everywhere.
- **Stash without `-m`** is hard to find again after a drop.
- **Bisect without exit 125 for build failures** blames the wrong commit.
- **`ORIG_HEAD` only remembers the last big move.** Use the reflog for anything older.


---


<a id="06-at-scale-worktrees-to-monorepos"></a>

## 06 · At scale: worktrees to monorepos

*Big-repo pain comes from three separate things: too many files on disk, too much history in the object store, and too many objects to scan. Each has its own fix (sparse-checkout, partial clone, maintenance), and they combine cleanly once you stop treating them as one problem.*

### Worktrees

A worktree is an extra checkout attached to the same repository: **one object store, many working directories, each on its own branch.** It replaces "stash, switch, wait for the rebuild, switch back, pop".

```bash
git worktree add ../proj-hotfix -b hotfix/1.4.1 origin/release/1.4   # new branch in a new dir
git worktree add ../proj-review origin/feat/other                   # detached, for reviewing
git worktree add ../proj-main main                                  # existing branch
git worktree list
git worktree remove ../proj-hotfix           # refuses if dirty; -f to force
git worktree prune                           # forget worktrees whose directories you rm'd
git worktree lock ../proj-usb --reason 'on removable disk'
git worktree move ../proj-review ../review
git worktree repair                          # after moving the main repo or a worktree by hand
```

Use them for:

- **Hotfix while mid-feature**, without touching your feature tree or its build cache.
- **Reviewing an MR** with the code running beside yours.
- **Long test runs** on one branch while you keep editing another.
- **Agents or scripts** that need an isolated checkout of the same repo.

Layout that stays tidy: a bare-ish "hub" with worktrees as siblings.

```bash
git clone --bare git@gitlab.example.com:group/proj.git proj/.bare
echo 'gitdir: ./.bare' > proj/.git
git -C proj config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
git -C proj fetch
git -C proj worktree add main main
git -C proj worktree add feat-x -b feat-x origin/main
# proj/main, proj/feat-x, ... all share proj/.bare
```

> **Gotcha.** **A branch can be checked out in only one worktree at a time.** `git switch main` in a second worktree fails with "already used by worktree at …". Use `git switch --detach main` there, or a different branch.

> **Gotcha.** Each worktree has its own index, HEAD and untracked files, but **shares config, hooks, stash, refs and reflogs**. A `git stash` in one worktree shows up in `git stash list` in all of them. Per-worktree config needs `git config set extensions.worktreeConfig true` and then `git config set --worktree KEY VALUE`.

Build tools that key caches on absolute path (some Node and Python setups) rebuild from scratch in each worktree. That's the one real cost.

### Sparse-checkout

Sparse-checkout limits **which files are written to disk**. History and objects are unaffected; `git log` still sees everything.

**Use cone mode** (the default): you list directories, Git includes them recursively plus every file at each parent level. It's fast because matching is by directory prefix, and it's what `index.sparse` optimises for.

```bash
git sparse-checkout set services/api libs/common     # only these dirs (plus root files)
git sparse-checkout add charts/api                   # add one more
git sparse-checkout list
git sparse-checkout reapply                          # re-apply after a merge brought in new paths
git sparse-checkout disable                          # full checkout again
git config set index.sparse true                     # sparse index: index only holds what's checked out
```

Verified on 2.55: after `clone --sparse`, only root files were on disk; `sparse-checkout add svc/a` materialised `svc/a` and nothing else under `svc/`.

Non-cone mode (`--no-cone`, gitignore-style patterns) exists for "every `*.proto` everywhere" cases. It's slower on large trees and incompatible with sparse index; avoid unless you need patterns.

> **Gotcha.** `git grep`, `git diff` and most commands only look at the checked-out paths by default, but history commands (`log`, `blame` on a path) work on everything. A search that returns nothing may just mean the file is outside your cone: `git grep PATTERN HEAD -- path` searches the tree object regardless.

### Partial clone

Partial clone limits **which objects are downloaded**. Missing objects are fetched lazily from the promisor remote when something needs them.

| Filter | Downloads up front | Fetches on demand | Use for |
|---|---|---|---|
| `--filter=blob:none` | all commits and trees | file contents as checked out or diffed | **developer clones of big repos: the default pick** |
| `--filter=blob:limit=1m` | small blobs too | large blobs | repos with a few huge assets |
| `--filter=tree:0` | commits only | trees and blobs | throwaway CI jobs that only need the tip; **terrible for humans** (every `log -- path` fetches trees) |

```bash
git clone --filter=blob:none git@gitlab.example.com:group/big.git
git config list --local | grep -E '^remote\.origin\.(promisor|partialclonefilter)'
# remote.origin.promisor true
# remote.origin.partialclonefilter blob:none
```

Verified on 2.55 against a `file://` remote with `uploadpack.allowFilter`: a blob-less clone with `--no-checkout` had 12 objects missing; checkout fetched the ones needed for the tip; `git backfill` fetched most of the rest in batches.

**Blob-less plus sparse** is the monorepo combination: all history, only your directories' contents.

```bash
git clone --filter=blob:none --sparse git@gitlab.example.com:group/mono.git
cd mono
git sparse-checkout set services/api libs/common
```

`git backfill` (new in recent Git, present in 2.55) pre-downloads missing blobs in batches, so you can go offline or stop paying per-command latency:

```bash
git backfill                         # blobs reachable from HEAD's history
git backfill --sparse                # only blobs inside your sparse-checkout
git backfill origin/main~500..origin/main
```

> **Gotcha.** Commands that need old file contents (`log -p`, `blame`, `log -S`, `diff` against old revisions) fetch blobs on demand, one round trip per batch. On a slow VPN that feels like a hang. `git backfill` first, or scope the command to a path.

> **Note.** Partial clone needs server support, and GitLab has it: Gitaly passes `uploadpack.allowFilter=true` on every `upload-pack` (read in `internal/git/gitcmd/command_description.go` in the Gitaly source; GitLab's clone docs only state the client needs Git 2.22+). `sparse:oid` filters are experimental and heavy on Gitaly; stick to `blob:none` or `blob:limit`. Against a server without filter support, Git prints `filtering not recognized by server, ignoring` and does a full clone.

### Shallow clones in CI

A shallow clone truncates **history**: `--depth N` fetches only the last N commits. Fast for CI, and it breaks every command that needs history beyond the cut.

GitLab CI runners do shallow fetches by default. The depth comes from the project's **Settings > CI/CD > General pipelines > Git shallow clone** (default **20** for new projects, maximum 1000, empty or `0` = full clone) or `GIT_DEPTH` in `.gitlab-ci.yml`, which overrides it (docs.gitlab.com/ci/pipelines/settings). Older projects keep whatever value they were created with, so check the setting:

```yaml
variables:
  GIT_DEPTH: "20"          # default-ish; enough for most build jobs

release:
  variables:
    GIT_DEPTH: "0"         # full history: needed for git describe, changelogs, semantic-release
  script:
    - git describe --tags --always
```

What breaks at shallow depth, and the fix:

| Needs | Why shallow breaks it | Fix |
|---|---|---|
| `git describe` | the tag is beyond the cut | `GIT_DEPTH: 0`, or `git fetch --tags --unshallow` in that job |
| `git merge-base origin/main HEAD` (changed-files detection) | the fork point is beyond the cut | `git fetch --deepen=200 origin main`, or use `CI_MERGE_REQUEST_DIFF_BASE_SHA` |
| changelog / semantic-release | needs commits since last tag | `GIT_DEPTH: 0` |
| `git log -S`, `blame` in CI | history is missing | full depth for that job only |
| pushing back from CI | shallow pushes can be rejected | full depth, or push from a dedicated job |

```bash
git rev-parse --is-shallow-repository       # true / false
git fetch --deepen=100                      # 100 more commits
git fetch --shallow-since='2026-06-01'
git fetch --unshallow                       # all of it
```

**For humans, prefer blob-less over shallow.** `--filter=blob:none` gives you full history for a small fraction of the download; `--depth` gives you a crippled repo that confuses `merge-base`, `log` and rebase.

For CI jobs that only need the tip and never look at history, `git clone --revision=SHA` (Git 2.49+) fetches exactly one commit without creating any branch:

```bash
git clone --depth=1 --revision=REF_OR_SHA URL dir
```

### Git LFS

LFS stores large files outside Git: the repo holds a small pointer file, and the content lives in the LFS store (GitLab's object storage). Clones download only the versions checked out.

```bash
sudo dnf install git-lfs                     # 3.7.1 in Fedora 43 (verified in repo metadata)
git lfs install                              # once per user: installs filter config + hooks
git lfs track '*.psd' 'datasets/**'          # writes .gitattributes
git add .gitattributes
git lfs ls-files                             # which files are LFS pointers
git lfs status
git lfs fetch --all && git lfs pull
GIT_LFS_SKIP_SMUDGE=1 git clone URL          # clone with pointers only; pull content later
git lfs migrate import --include='*.bin' --everything   # rewrite history to move files into LFS
```

> **Note.** git-lfs isn't installed on the machine this guide was verified on; commands are from its documentation, not executed. Upstream latest is 3.8.0.

When to use it: **large binaries that change** (design files, datasets, test fixtures, firmware). When not to: build artefacts (use a package or container registry), and anything you can generate.

> **One-way door.** `git lfs migrate import --everything` rewrites every commit in history, with all the consequences of chapter 05's filter-repo section: new SHAs, force-push, everyone re-clones. Decide on LFS at repo creation when you can.

> **Gotcha.** By default LFS talks HTTPS even when the Git remote is SSH (it gets a token via `git-lfs-authenticate` over SSH). GitLab **17.2+** (17.3 for the Helm chart) can serve pure-SSH LFS if an admin enables it; git-lfs 3.x tries SSH first and falls back to HTTPS, and GitLab asks for git-lfs **3.5.1+**, preferably 3.6.0+ to avoid a known clone crash (docs.gitlab.com/administration/lfs). Unless you know it's on, assume HTTPS. Proxies, air-gapped mirrors and CI runners need the LFS endpoint reachable too. A mirror that copies Git refs but not LFS objects produces a repo full of pointer files.

### Submodules and subtree

Both embed one repository in another. **Default pick: neither.** Use your package manager, a container image, or a Helm dependency. When you genuinely need source from another repo in-tree:

| | Submodule | Subtree |
|---|---|---|
| What's stored | a commit SHA (gitlink) pointing into another repo | the other repo's files, copied into yours |
| Clone experience | needs `--recurse-submodules` or an extra `submodule update` | nothing special: files are just there |
| Updating | bump the SHA in a commit | `git subtree pull` (a merge) |
| Contributing back | commit inside the submodule, push it, then bump | `git subtree push` (splits history, slow on big repos) |
| Access | every consumer needs read access to the sub-repo | only the maintainer does |
| Pick when | the sub-repo is large, versioned independently, or shared by many | the sub-repo is small, rarely changes, and consumers shouldn't care |

#### Submodules

```bash
git submodule add git@gitlab.example.com:group/lib.git vendor/lib
git clone --recurse-submodules URL
git submodule update --init --recursive       # after a plain clone, or after switching branches
git submodule update --remote vendor/lib      # move to the tip of the tracked branch
git submodule status
git submodule foreach 'git status -s'
git -C vendor/lib log --oneline -3
```

Config that removes most submodule pain:

```bash
git config set --global submodule.recurse true          # checkout, pull, switch recurse automatically
git config set --global status.submoduleSummary true    # show submodule commits in git status
git config set --global diff.submodule log              # show submodule commit list in diffs
git config set --global push.recurseSubmodules check    # refuse to push a bump whose SHA isn't pushed
```

Submodule traps:

- **Detached HEAD inside the submodule** is normal: the superproject pins a SHA, not a branch. Commit there without `git switch BRANCH` first and your work is in detached HEAD (chapter 05).
- **The bump that points at an unpushed commit.** You commit in the submodule, bump the superproject, push only the superproject. CI and colleagues get "reference is not a tree". `push.recurseSubmodules check` prevents it.
- **Relative URLs** (`../lib.git`) in `.gitmodules` resolve against the superproject's remote, which is what you want for forks and mirrors. Absolute URLs break when a mirror or air-gapped copy is used.
- **GitLab CI** needs `GIT_SUBMODULE_STRATEGY: recursive` (or `normal`), and the job token needs access to the sub-project.
- **Removing** one properly: `git rm vendor/lib`, then `rm -rf .git/modules/vendor/lib`.

#### Subtree

`git subtree` is a separate Fedora package, `git-subtree` (verified in repo metadata).

```bash
sudo dnf install git-subtree
git subtree add --prefix=vendor/lib git@gitlab.example.com:group/lib.git main --squash
git subtree pull --prefix=vendor/lib git@gitlab.example.com:group/lib.git main --squash
git subtree push --prefix=vendor/lib git@gitlab.example.com:group/lib.git my-branch
```

**Always `--squash`** on add and pull, or the sub-repo's entire history gets merged into yours. Keep the prefix consistent forever; subtree finds its previous merges by it.

> **Gotcha.** Dependency bots (Renovate) and code scanners treat subtree-vendored code as yours: they'll open MRs against it and report its CVEs as your findings. Exclude the prefix in their config.

### Scalar and maintenance

`scalar` (installed with Git on Fedora 43) is a front end that applies Git's large-repo settings in one go: partial clone, sparse-checkout in cone mode, fsmonitor, commit-graph, multi-pack-index, and scheduled maintenance.

```bash
scalar clone git@gitlab.example.com:group/mono.git     # creates mono/src as the worktree, sparse by default
scalar clone --full-clone URL                          # same settings, no sparse-checkout
scalar register                                        # apply settings + maintenance to an existing clone
scalar list
scalar run all                                         # run all maintenance tasks now
scalar unregister
```

`scalar clone` puts the worktree in `REPO/src/`, leaving `REPO/` for build output outside the checkout. That layout surprises people once.

#### git maintenance

```bash
git maintenance start                         # register + systemd --user timers (hourly/daily/weekly)
git maintenance run --task=commit-graph --task=prefetch
git maintenance run --auto                    # run only what's needed
git maintenance is-needed                     # exit status: does auto-maintenance want to run? (2.55)
git maintenance stop                          # remove timers
```

What the scheduled tasks do with `maintenance.strategy = incremental` (from `git help config`, 2.55): **prefetch** and **commit-graph** hourly, **loose-objects** and **incremental-repack** daily, **pack-refs** weekly. None of them delete data. Prefetch writes to `refs/prefetch/`, not `refs/remotes/`, so your `origin/*` refs only move when you fetch; the next real fetch is just fast.

The `geometric` strategy (the default for manual `git maintenance run` in 2.55) repacks geometrically and generates cruft packs for unreachable objects: the modern replacement for full `gc` on big repos.

### Monorepo tips

- **Clone:** `--filter=blob:none --sparse`, or `scalar clone`. Never full on a laptop over VPN.
- **Status speed:** `core.fsmonitor = true`, `core.untrackedCache = true`, `index.sparse = true` per repo. Verified that the fsmonitor daemon runs on Linux in Git 2.55 (chapter 02).
- **Commit-graph:** `fetch.writeCommitGraph = true` plus maintenance. `log --graph`, `merge-base` and ahead/behind are dramatically faster with it.
- **CODEOWNERS** plus path-scoped CI rules (`rules: changes:`) keep a monorepo MR from triggering 40 pipelines. See the GitLab chapters.
- **Scoped history:** `git log -- services/api`, `git log --first-parent -- services/api`.
- **Find what changed for CI:** `git diff --name-only "$CI_MERGE_REQUEST_DIFF_BASE_SHA"...HEAD`.
- **Measure before tuning:** `git repo structure` (2.55) or `git-sizer` shows whether the problem is file count, blob size, history depth or ref count. Each has a different fix.
- **Refs:** thousands of branches and tags slow `fetch` negotiation. `git config set remote.origin.fetch '+refs/heads/main:refs/remotes/origin/main'` plus explicit fetches for what you need; or reftable (`git init --ref-format=reftable`, chapter 01) for new repos.

```bash
GIT_TRACE2_PERF=1 git status 2>&1 | tail -20   # where the time goes
git status --untracked-files=no                # quick check without the untracked scan
```

### Client-side hooks

Hooks are scripts Git runs at points in its workflow. They're local: **not cloned, not enforced**. Anything that must hold for everyone belongs in CI or server-side push rules; hooks are for fast feedback.

| Hook | Runs | Good for | Skip with |
|---|---|---|---|
| `pre-commit` | before the commit is created | lint, format check, secret scan on staged files | `--no-verify` |
| `prepare-commit-msg` | before the editor opens | insert branch's ticket ID into the template | — |
| `commit-msg` | after the message is written | enforce message format, ticket reference | `--no-verify` |
| `post-checkout` / `post-merge` | after switch / merge | regenerate, `npm ci` when lockfile changed | — |
| `pre-push` | before objects are sent | run fast tests; block pushing to `main` | `--no-verify` |
| `pre-rebase` | before rebase starts | refuse to rebase published branches | — |

#### Share hooks: core.hooksPath

Hooks in `.git/hooks/` aren't versioned. Commit them to the repo and point Git at the directory:

```bash
mkdir -p .githooks && cp my-pre-commit .githooks/pre-commit && chmod +x .githooks/pre-commit
git config set core.hooksPath .githooks        # each clone opts in
```

#### Config-based hooks (Git 2.55)

Git 2.55 can define hooks in config, several per event, with scopes. Verified on 2.55:

```ini
# ~/.gitconfig: runs in every repo
[hook "gitleaks"]
	event = pre-commit
	command = gitleaks git --pre-commit --staged --redact   # `protect` is deprecated since gitleaks 8.19
[hook "msgcheck"]
	event = commit-msg
	command = ~/.local/bin/check-commit-msg
```

```bash
git hook list pre-commit --show-scope      # which hooks fire, and from which config level
git config set hook.gitleaks.enabled false  # disable a global hook in one repo
git hook run pre-commit                    # run it by hand
```

In the lab, a config hook with `exit 1` blocked the commit, `git hook list --show-scope` showed it as `local lint`, and `hook.lint.enabled=false` let the commit through.

> **Version-sensitive.** Config-based hooks (`hook.<name>.command` / `.event` / `.enabled`, `git hook list`) are present in 2.55 (verified). Older Git ignores the config silently, so a global secret-scanning hook defined this way does nothing on an older machine.

**Pick config-based hooks for personal, all-repo checks** (secret scanning), **`core.hooksPath` for repo-specific, team-shared hooks**, and the `pre-commit` framework when the team already uses it.

Hook rules that keep them tolerable:

- **Fast.** A `pre-commit` hook over one second gets `--no-verify`'d by habit. Check staged files only (`git diff --cached --name-only --diff-filter=ACM`).
- **Check the index, not the worktree.** Linting the worktree passes code that isn't what you're committing.
- **Never mutate in `pre-commit`** without re-staging; auto-formatting then committing the unformatted index is a classic.

### Attributes

`.gitattributes` assigns behaviour to paths: line endings, diff and merge drivers, LFS, export rules. Committed to the repo, so it applies to everyone.

```text
# .gitattributes
* text=auto eol=lf

*.sh      text eol=lf
*.bat     text eol=crlf
*.png     binary
*.pdf     binary

*.py      diff=python
*.go      diff=golang
*.md      diff=markdown
*.sh      diff=bash

package-lock.json   -diff linguist-generated=true
charts/*/crds/*     linguist-generated=true
CHANGELOG.md        merge=union

*.psd     filter=lfs diff=lfs merge=lfs -text

/tests/fixtures/**  export-ignore
.gitlab-ci.yml      export-ignore
```

| Attribute | Does |
|---|---|
| `text=auto` | normalise line endings to LF in the repo for files Git detects as text |
| `eol=lf` / `eol=crlf` | force the line ending in the working tree |
| `binary` | shorthand for `-diff -merge -text`: never diff, merge or convert |
| `diff=DRIVER` | use a built-in funcname/word-diff driver (`python`, `golang`, `rust`, `java`, `kotlin`, `markdown`, `bash`…; full list in `man gitattributes`, and there is none for HCL or YAML): better hunk headers and `log -L :func:` |
| `-diff` | show "Binary files differ" instead of a diff (huge lockfiles) |
| `merge=union` | on conflict, keep both sides' lines; OK for changelogs, dangerous for code |
| `linguist-generated` | GitLab collapses these files in MR diffs |
| `filter=lfs` | route through Git LFS (written by `git lfs track`) |
| `export-ignore` | exclude from `git archive` (release tarballs) |

```bash
git check-attr -a path/to/file              # every attribute that applies, and its value
git add --renormalize .                     # after changing text/eol rules: re-normalise the index
```

> **Gotcha.** Changing `text`/`eol` attributes doesn't touch existing files until you `git add --renormalize .` and commit. Do it in a commit on its own so the diff is reviewable, and add it to `.git-blame-ignore-revs`.

### .gitignore precedence

Git decides whether a path is ignored by checking these sources; **within one file, the last matching pattern wins; across sources, higher in the list wins**:

1. Patterns on the command line (`git ls-files --exclude=…`, for plumbing)
2. `.gitignore` in the same directory as the path, then each parent up to the repo root (**deeper files override shallower ones**)
3. `.git/info/exclude`: local to this clone, never committed
4. `core.excludesFile` (default `~/.config/git/ignore`): your global

```bash
git check-ignore -v path/to/file            # which file and line ignores it
git check-ignore -v --no-index path         # check even if the file is tracked
git status --ignored                        # show ignored files
git ls-files --others --ignored --exclude-standard   # list them
```

| Pattern | Matches |
|---|---|
| `build/` | a directory named `build` at any depth |
| `/build/` | only `build/` at this `.gitignore`'s level |
| `*.log` | any `.log` file at any depth |
| `logs/**/*.log` | `.log` files anywhere under `logs/` |
| `!keep.log` | re-include a file a previous pattern excluded |
| `\#file`, `\!file` | literal leading `#` or `!` |

> **Gotcha.** **You cannot re-include a file if its parent directory is excluded.** `build/` then `!build/keep.txt` doesn't work: Git never descends into `build/`. Exclude the contents instead: `build/*` then `!build/keep.txt`.

> **Gotcha.** `.gitignore` only affects **untracked** files. A file that's already committed keeps being tracked. `git rm --cached FILE` to untrack it (it stays on disk), then commit.

Where to put what:

| Kind of file | Put the pattern in |
|---|---|
| build output, dependency dirs, generated code for this project | the project's `.gitignore` |
| your editor, OS and tool droppings | `~/.config/git/ignore` |
| your personal scratch files in one repo | `.git/info/exclude` |

### Traps

- **One branch, one worktree.** Detach in the second one.
- **Stash and hooks are shared across worktrees.** Config is too unless `extensions.worktreeConfig` is on.
- **Shallow clones break `describe`, `merge-base` and changelogs.** Full depth for those CI jobs; blob-less for humans.
- **`--filter=tree:0` for humans** makes every history command crawl.
- **Pushing a submodule bump before the submodule commit.** Set `push.recurseSubmodules check`.
- **LFS mirrors without LFS objects** are repos full of pointer files.
- **Re-including a file under an excluded directory** silently fails. `dir/*` then `!dir/file`.
- **Hooks aren't enforcement.** Anything mandatory lives in CI or server push rules.
- **Changing `.gitattributes` line endings** needs `add --renormalize` in its own commit.


---


<a id="07-one-screen-git-reference"></a>

## 07 · One-screen Git reference

*The commands worth memorising, organised by what you're trying to do, plus the three mini-languages (revisions, pathspecs, format placeholders) that every other command accepts. Learn those three and every command gets more powerful at once.*

### Commands by task

#### Look

| Task | Command |
|---|---|
| state, short | `git status -sb` |
| branches with upstream and ahead/behind | `git branch -vv` |
| history graph | `git log --graph --oneline --decorate --all` |
| mainline, one line per MR | `git log --first-parent --oneline main` |
| what I'd push / pull | `git log @{u}..` / `git log ..@{u}` |
| unstaged / staged / both | `git diff` / `git diff --staged` / `git diff HEAD` |
| my branch's change (MR view) | `git diff main...HEAD` |
| a commit | `git show SHA`, `git show --stat SHA` |
| a file at a revision | `git show REV:path` |
| who changed each line | `git blame -w -C -C -M FILE` |
| history of a function | `git log -L :func:FILE` |
| when a string appeared/vanished | `git log -S'STRING'`; any matching line change: `git log -G'REGEX'` |
| search tracked files / another revision | `git grep -n PATTERN [REV] [-- PATH]` |
| where refs point | `git for-each-ref --sort=-committerdate refs/heads` |
| where HEAD has been | `git reflog` |
| repository facts | `git repo info --all`, `git repo structure` |

#### Change

| Task | Command |
|---|---|
| new branch from a start point | `git switch -c NAME START` |
| previous branch | `git switch -` |
| stage hunks | `git add -p` |
| unstage | `git restore --staged FILE` |
| discard worktree edits (no undo) | `git restore FILE` |
| file from another revision | `git restore --source=REV -SW FILE` |
| commit with trailer | `git commit --trailer 'Refs: OPS-1'` |
| fold staged into last commit | `git commit --amend --no-edit` |
| fold staged into older commit | `git commit --fixup=SHA && git rebase --autosquash BASE` |
| stash with a name / with untracked | `git stash push -m MSG` / `-u` |
| stash only staged | `git stash push -S` |

#### Share

| Task | Command |
|---|---|
| update remote-tracking refs | `git fetch --all --prune` |
| replay my commits on upstream | `git rebase origin/main` |
| fast-forward only | `git merge --ff-only origin/main` |
| push, first time | `git push` (with `push.autoSetupRemote`) |
| safe force-push | `git push --force-with-lease --force-if-includes` |
| delete remote branch | `git push origin --delete NAME` |
| push a tag | `git push origin TAG` |
| check out an MR | `git fetch origin refs/merge-requests/IID/head:mr-IID` |
| what the server has, no fetch | `git ls-remote origin` |

#### Rewrite

| Task | Command |
|---|---|
| clean up the branch | `git rebase -i --autosquash main` |
| edit without moving base | `git rebase -i --keep-base main` |
| rebase a stack | `git rebase --update-refs origin/main` |
| cut off an old base | `git rebase --onto NEW OLD BRANCH` |
| test every commit | `git rebase -x 'make test' main` |
| copy commits A through B | `git cherry-pick -x A^..B` |
| undo a pushed commit | `git revert SHA` |
| undo a merged MR | `git revert -m 1 MERGE_SHA` |
| squash branch to one | `git reset --soft $(git merge-base HEAD origin/main) && git commit` |
| compare two versions of a series | `git range-diff OLD...NEW` |
| would it merge? | `git merge-tree --write-tree --name-only A B` (exit 1 = conflict) |

#### Recover

| Task | Command |
|---|---|
| undo last big move | `git reset --hard ORIG_HEAD` |
| where was this branch | `git reflog show BRANCH` |
| restore a lost commit | `git branch rescue SHA` |
| move branch, refuse if dirty | `git reset --keep REV` |
| find dangling commits / stashes | `git fsck --unreachable --no-reflogs \| grep commit` |
| find the breaking commit | `git bisect start BAD GOOD && git bisect run CMD` |
| abort anything in progress | `git rebase --abort`, `merge --abort`, `cherry-pick --abort` |

#### Scale

| Task | Command |
|---|---|
| second checkout | `git worktree add ../DIR -b BRANCH START` |
| big-repo clone | `git clone --filter=blob:none --sparse URL` |
| choose directories | `git sparse-checkout set DIR…` |
| prefetch missing blobs | `git backfill` |
| deepen a shallow clone | `git fetch --deepen=N` / `--unshallow` |
| background maintenance | `git maintenance start` |
| why is this ignored | `git check-ignore -v PATH` |
| what attributes apply | `git check-attr -a PATH` |

### Revision syntax

Anything that takes a commit accepts these. Test any expression with `git rev-parse EXPR` or `git log --oneline -1 EXPR`.

#### Naming one commit

| Syntax | Means |
|---|---|
| `SHA`, `4f2a1c9` | full or unambiguous short ID |
| `main`, `origin/main`, `v1.4.0` | a ref (branch, remote-tracking, tag) |
| `HEAD`, `@` | current commit (`@` alone is shorthand for `HEAD`) |
| `REV^` or `REV^1` | first parent |
| `REV^2` | **second** parent (the merged-in branch of a merge) |
| `REV~3` | third generation back, following first parents (`= REV^^^`) |
| `REV~2^2` | second parent of the grandparent |
| `@{u}`, `@{upstream}`, `BRANCH@{u}` | the branch's upstream (e.g. `origin/main`) |
| `@{push}`, `BRANCH@{push}` | where `git push` would send it (differs from `@{u}` in fork workflows) |
| `@{-1}`, `@{-2}` | previously checked-out branch (`git switch -` uses `@{-1}`) |
| `BRANCH@{1}` | where BRANCH was one move ago (reflog) |
| `HEAD@{2.hours.ago}`, `main@{yesterday}` | reflog by time (local only) |
| `ORIG_HEAD`, `MERGE_HEAD`, `FETCH_HEAD`, `CHERRY_PICK_HEAD` | state refs from the last operation |
| `REV^{tree}`, `REV^{commit}` | peel to a tree / commit (tags to their target) |
| `REV:path/file` | the blob at that path in that revision |
| `:path/file` | the blob in the index (stage 0) |
| `:1:path`, `:2:path`, `:3:path` | base / ours / theirs during a conflict |
| `:/fix probe` | youngest commit, reachable from any ref, whose message matches the regex |
| `REV^{/fix probe}` | youngest commit reachable from REV whose message matches |

#### Naming a range

The dots mean different things in `log` and `diff`. This is the table to memorise.

| Syntax | In `git log` / `rev-list` | In `git diff` |
|---|---|---|
| `A..B` | commits reachable from B **but not** A ("what B has that A doesn't") | same as `A B`: tip-to-tip |
| `A...B` | commits reachable from **either but not both** (symmetric difference) | from **merge-base(A,B)** to B ("what B changed since they split") |
| `..B` / `A..` | `HEAD..B` / `A..HEAD` | `HEAD..B` / `A..HEAD` |
| `^A B` | same as `A..B`; composes: `^A ^C B` | — |
| `REV^!` | just REV, excluding its parents | `diff REV^!` = diff of that commit |
| `REV^@` | all parents of REV | — |
| `REV^-` / `REV^-2` | REV excluding its first / second parent (`REV^..REV` / `REV^2..REV`) | — |

Worked examples, verified with `rev-list --count` on 2.55 against two branches that each had 3 unique commits:

```bash
git rev-list --count main..b                   # 3: on b, not on main
git rev-list --count b..main                   # 3: on main, not on b
git rev-list --count main...b                  # 6: either, not both
git rev-list --left-right --count main...b     # "3	3": left-only, right-only
```

```bash
git log main..feat                        # what feat would add to main
git log feat..main                        # what feat is missing from main
git log --left-right --oneline main...feat   # both, marked < and >
git diff main...feat                      # the MR diff
git log MERGE^-                           # what a merge brought in (= MERGE^..MERGE)
git log --oneline origin/main..@          # unpushed (if main is your upstream)
```

### Pathspec magic

Anything that takes paths (after `--`) accepts these. Quote them in zsh, which treats `:` and `!` and parentheses specially.

| Pathspec | Matches |
|---|---|
| `src/` | everything under `src/` (relative to the current directory) |
| `'*.py'` | Python files at **any depth** (Git's glob, not the shell's: quote it) |
| `':(top)charts'` or `':/charts'` | `charts/` at the repo root, wherever you are |
| `':(exclude)vendor'` or `':!vendor'` or `':^vendor'` | everything **except** `vendor/` |
| `':(icase)readme*'` | case-insensitive |
| `':(glob)src/**/*.go'` | glob where `*` doesn't cross `/` and `**` does |
| `':(literal)file[1].txt'` | no wildcard interpretation |
| `':(attr:linguist-generated)'` | paths with that gitattribute set |
| `':(attr:!linguist-generated)'` | paths without it |
| `':(top,exclude)docs'` | magic words combine with commas |

```bash
git diff main...HEAD -- . ':!**/package-lock.json' ':!vendor'
git log --oneline -- ':/charts' ':!:/charts/*/tests'
git grep -n TODO -- '*.go' ':!*_test.go'
git ls-files -- ':(attr:linguist-generated)'
git add -- ':!*.env'
```

> **Note.** An exclude-only pathspec acts as if no pathspec were given, then subtracts. So its scope is the command's default scope: verified on 2.55 from a subdirectory, `git diff -- ':!b'` listed changes across the whole repo, while `git ls-files -- ':!b'` listed only the current directory. The excluded path itself is relative to where you are; anchor it at the root with `':(top,exclude)vendor'`.

### Format placeholders

For `git log --format=`, `git show --format=`, and (with different syntax) `for-each-ref --format=`.

#### log / show

| Placeholder | Gives |
|---|---|
| `%H` / `%h` | commit hash, full / short |
| `%T` / `%t` | tree hash |
| `%P` / `%p` | parent hashes |
| `%an` / `%ae` / `%al` | author name / email / email local-part |
| `%ad` / `%ar` / `%as` / `%ai` | author date: `--date=` format / relative / short / ISO |
| `%cn` / `%ce` / `%cd` / `%cr` | committer name / email / date / relative |
| `%s` / `%b` / `%B` | subject / body / raw full message |
| `%d` / `%D` | ref names ` (HEAD -> main, origin/main)` / without parens |
| `%G?` | signature: `G` good, `B` bad, `U` good but untrusted, `X`/`Y` expired, `R` revoked key, `E` can't check, `N` none |
| `%GS` / `%GK` / `%GF` | signer / key / fingerprint |
| `%gd` / `%gs` | reflog selector (`HEAD@{1}`) / reflog subject (with `-g`) |
| `%(trailers)` | all trailers; `%(trailers:key=Refs,valueonly)` for one |
| `%(describe)` | `git describe` output for the commit |
| `%C(auto)` / `%C(red)` / `%C(dim)` / `%C(reset)` | colours; `auto` colours hashes and refs like the default output |
| `%n` | newline |
| `%<(20,trunc)` | pad/truncate the next placeholder to 20 columns |

```bash
git log --format='%C(auto)%h%d %s %C(dim)%an, %ar%C(reset)' --graph
git log --format='%h %<(12,trunc)%an %as %s'
git log --format='%H %G? %GS' -20
git log --date=format:'%Y-%m-%d' --format='%ad %s'
git log --format='%(trailers:key=Refs,valueonly,separator=%x2C)' main..
git show -s --format='%an <%ae>%n%B' SHA
```

`--date=` values: `relative`, `local`, `iso`, `iso-strict`, `short`, `human`, `unix`, `format:STRFTIME` (and `-local` suffix variants such as `iso-local`).

#### for-each-ref / branch / tag

```bash
git for-each-ref --sort=-committerdate --count=15 \
  --format='%(committerdate:relative)%09%(refname:short)%09%(upstream:track)%09%(subject)' refs/heads
git branch --format='%(refname:short) %(upstream:short) %(upstream:track)'
git tag -l --sort=-version:refname --format='%(refname:short) %(taggerdate:short) %(subject)'
```

| Atom | Gives |
|---|---|
| `%(refname)` / `%(refname:short)` | `refs/heads/feat` / `feat` |
| `%(objectname:short)` | short SHA |
| `%(upstream:short)` / `%(upstream:track)` | `origin/feat` / `[ahead 2, behind 1]` or `[gone]` |
| `%(push:short)` | push destination |
| `%(committerdate:relative)` / `%(authordate:iso)` | dates |
| `%(subject)` / `%(contents)` | message subject / full |
| `%(HEAD)` | `*` if this is the current branch |
| `%(worktreepath)` | path of the worktree that has it checked out |

### Config keys worth knowing by name

| Key | Chapter |
|---|---|
| `merge.conflictStyle zdiff3`, `rerere.enabled`, `diff.algorithm histogram` | 02, 04 |
| `pull.rebase` / `pull.ff only` | 02 |
| `push.autoSetupRemote`, `push.useForceIfIncludes`, `push.followTags` | 02, 03 |
| `rebase.autoSquash`, `rebase.autoStash`, `rebase.updateRefs`, `rebase.missingCommitsCheck` | 02, 04 |
| `fetch.prune`, `fetch.writeCommitGraph` | 02 |
| `remote.pushDefault`, `push.default current` (fork clones) | 03 |
| `user.useConfigOnly`, `includeIf "hasconfig:remote.*.url:…"` | 02 |
| `gpg.format ssh`, `user.signingKey`, `commit.gpgSign` | 02 |
| `blame.ignoreRevsFile` | 03 |
| `core.fsmonitor`, `core.untrackedCache`, `index.sparse` | 02, 06 |
| `submodule.recurse`, `push.recurseSubmodules check` | 06 |
| `core.hooksPath`, `hook.NAME.command` / `.event` | 06 |

### Environment variables

| Variable | Use |
|---|---|
| `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1` | ignore user and system config (scripts, tests) |
| `GIT_SSH_COMMAND='ssh -v'` | debug SSH auth; or pick a key with `-i` |
| `GIT_TRACE=1`, `GIT_TRACE_PACKET=1`, `GIT_CURL_VERBOSE=1` | trace commands / protocol / HTTP |
| `GIT_TRACE2_PERF=1` | per-phase timing |
| `GIT_EDITOR`, `GIT_SEQUENCE_EDITOR` | editor for messages / the rebase todo (`GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash` accepts the todo as-is) |
| `GIT_LFS_SKIP_SMUDGE=1` | clone LFS repos with pointers only |
| `GIT_DEPTH` | GitLab CI clone depth (runner variable, not Git's) |

### Checklist

- **`..` versus `...`:** log `A..B` is "on B not A"; diff `A...B` is "B since the fork".
- **`^` versus `~`:** `^2` picks a parent; `~2` walks back generations.
- **Quote pathspecs and globs** in zsh: `':!vendor'`, `'*.py'`.
- **`@{u}` and `@{push}`** are the portable way to say "my upstream" and "my push target" in scripts.
- **Reflog syntax (`@{1}`, `@{yesterday}`) is local**: it doesn't exist in a fresh clone or on CI.


---


<a id="08-glab-install-auth-and-config"></a>

## 08 · glab: install, auth and config

*glab resolves three things on every call: which host, which token, which project. Almost every "glab is broken" report is one of those three resolving to something you didn't expect, so set them up deliberately and learn how to ask glab what it resolved.*

### The resolution model

Before any flag matters, glab answers three questions. Knowing the order it asks them in saves most debugging sessions.

```text
  glab mr list
     │
     ├─ 1. HOST     -R URL/host  >  git remote of cwd (remote_alias)  >  GITLAB_HOST  >  config `host`  >  gitlab.com
     │
     ├─ 2. TOKEN    GITLAB_TOKEN / GITLAB_ACCESS_TOKEN / OAUTH_TOKEN  >  keyring  >  hosts.<host>.token in config.yml
     │              (CI_JOB_TOKEN only when GLAB_ENABLE_CI_AUTOLOGIN=true inside a CI job)
     │
     └─ 3. PROJECT  -R GROUP/PROJECT  >  GITLAB_REPO  >  git remote of cwd
```

Two consequences you will hit:

- **An exported `GITLAB_TOKEN` beats everything in the config file**, for every host. Export a gitlab.com token in your shell rc and your self-hosted calls silently authenticate with the wrong token and come back 401. `glab auth status` warns about this explicitly — read the warning.
- **Outside a Git repository there is no project and the host falls back to the config default.** `glab api projects/:fullpath` fails with `Unable to expand placeholder in path: fatal: not a git repository`, and plain `glab api version` goes to whatever `host` says (gitlab.com if unset). Scripts that run from `/tmp` or cron need `--hostname` or `GITLAB_HOST` every time.

> **Note.** The precedence above is assembled from `glab auth login --help`, `glab config get --help` (lookup order "environment variables, then the local repository configuration, then the global configuration") and the environment variable reference at docs.gitlab.com/cli/configuration. glab's README documents `GITLAB_HOST` as the host used "when the current directory is not a `git` directory", which confirms the git remote wins over it. When it matters, pass `-R` or `--hostname` and remove the ambiguity.

### Install and upgrade

#### Pick: the upstream RPM

Fedora packages glab, but it lags well behind upstream: on Fedora 43 the `updates` repo carries **1.89.0** while upstream is at 1.119 (checked 2026-09-23). glab's value is almost entirely in recently added subcommands (`mr note create --file/--line`, `ci get --merge-request`, `repo prune`, `stack`), so a year-old build costs you real features. **Default: the upstream `.rpm` from the GitLab releases page.** It installs to `/usr/bin/glab`, upgrades with one `dnf` command, and ships shell completion.

```bash
# Find the latest version without a browser
VER=$(glab api 'projects/gitlab-org%2Fcli/releases/permalink/latest' | jq -r '.tag_name | ltrimstr("v")')
# (no glab yet? use curl instead)
VER=$(curl -fsSL 'https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases/permalink/latest' | jq -r '.tag_name | ltrimstr("v")')

cd "$(mktemp -d)"
BASE="https://gitlab.com/gitlab-org/cli/-/releases/v${VER}/downloads"
curl -fsSLO "${BASE}/glab_${VER}_linux_amd64.rpm"
curl -fsSLO "${BASE}/checksums.txt"
sha256sum --check --ignore-missing checksums.txt   # must print OK

sudo dnf install -y "./glab_${VER}_linux_amd64.rpm"
glab version
```

Upgrading is the same block with the new version; `dnf` treats it as an upgrade of the local package.

> **Gotcha.** If you ever installed a tarball binary into `~/.local/bin`, it shadows `/usr/bin/glab` because `~/.local/bin` is usually earlier on `PATH`. Run `type -a glab` after every install. Two copies means you upgrade one and keep running the other.

> **Gotcha.** `glab auth login` writes an absolute path into `~/.gitconfig` as the Git credential helper (`helper = !/usr/bin/glab auth git-credential`). **Move or reinstall glab and HTTPS Git operations start failing** with a helper error, while glab itself keeps working. After changing install method, `grep -n glab ~/.gitconfig` and fix the path.

#### Alternatives and when they win

| Method | Version freshness | Use when |
|---|---|---|
| **Upstream `.rpm`** | current | default on a Fedora workstation |
| `sudo dnf install glab` | months behind | a locked-down host where only Fedora repos are allowed |
| Tarball into `~/.local/bin` | current | no sudo; remember the credential-helper path |
| `brew install glab` | current | you already run Linuxbrew for other tools |

#### Keep it current

```bash
glab check-update             # always checks, even if checked <24 h ago
glab whatsnew                 # release notes for the version you just got
glab config set check_update false --global   # silence the nag in scripts and CI images
```

### Authenticate to self-hosted GitLab

#### Pick: a PAT from a file, keyring-backed

For a workstation against self-hosted GitLab, **use a personal access token read from stdin, stored in the keyring**. OAuth is nicer on gitlab.com, but on a self-managed instance it needs an admin-registered OAuth application first (see below), and PATs have a visible expiry you control.

```bash
# Non-interactive: token never touches argv, history or the process list
secret-tool lookup service gitlab host gitlab.example.com \
  | glab auth login --hostname gitlab.example.com \
      --stdin \
      --git-protocol ssh \
      --api-protocol https \
      --use-keyring

glab auth status --hostname gitlab.example.com
```

Store the token in the GNOME keyring once with `secret-tool store --label='GitLab PAT gitlab.example.com' service gitlab host gitlab.example.com` (it prompts; nothing lands in history). Chapter 12 covers token hygiene in full.

> **Version-sensitive.** In glab **1.108** tokens are written in plaintext to `~/.config/glab-cli/config.yml` unless you pass `--use-keyring`. From **1.111** the OS keyring (Secret Service on Linux) is the default, plaintext needs `--insecure-storage`, and `--use-keyring` is deprecated (it prints a warning and only matters in CI, where the default stays plaintext). Keep `--use-keyring` in scripts that must run on both sides of 1.111; drop it once everyone is on 1.111+. From 1.112 glab warns when an env token overrides stored credentials.

#### The interactive path

```bash
glab auth login --hostname gitlab.example.com
```

Inside a Git repository, glab lists the GitLab hosts it finds in your remotes, so you can skip typing the hostname. It then asks for token vs web login, Git protocol and API protocol.

#### Unusual topologies

| Situation | Flag | Config key (per host) |
|---|---|---|
| API on a different host or port than the Git remote | `--api-host gitlab.example.com:3443` | `api_host` |
| SSH on a different hostname (`ssh.gitlab.example.com`) | `--ssh-hostname ssh.gitlab.example.com` | `ssh_host` |
| GitLab served under a path (`https://example.com/gitlab/`) | — | `subfolder` |
| Plain HTTP lab instance | `--api-protocol http` | `api_protocol` |
| Registry on its own domain (for `configure-docker`) | `--container-registry-domains registry.example.com` | `container_registry_domains` |
| Must go through a proxy only for this host | — | `proxy` |
| Extra header (Cloudflare Access, IAP) | — | `custom_headers` |

```bash
secret-tool lookup service gitlab host gitlab.example.com \
  | glab auth login --hostname gitlab.example.com \
      --api-host gitlab.example.com:3443 --api-protocol https \
      --ssh-hostname ssh.gitlab.example.com --git-protocol ssh \
      --stdin --use-keyring
```

`custom_headers` supports `valueFromEnv`, which is the right way to pass an access-proxy secret without writing it to disk:

```yaml
hosts:
    gitlab.example.com:
        custom_headers:
            - name: Cf-Access-Client-Id
              valueFromEnv: CF_ACCESS_CLIENT_ID
            - name: Cf-Access-Client-Secret
              valueFromEnv: CF_ACCESS_CLIENT_SECRET
```

#### OAuth against self-managed

OAuth gives you short-lived access tokens with a refresh token, so nothing long-lived sits in the config. It needs an OAuth application registered on the instance (user, group or admin level) with:

| Setting | Value |
|---|---|
| Redirect URI | `http://localhost:7171/auth/redirect` (not needed for `--device`) |
| Confidential | **unchecked** — checked gives `invalid_client` at login |
| Scopes | `openid`, `profile`, `read_user`, `write_repository`, `api` |

```bash
glab config set client_id APPLICATION_ID --host gitlab.example.com
glab auth login --hostname gitlab.example.com --web --git-protocol ssh

# Headless box (SSH session, no browser): device flow
glab auth login --hostname gitlab.example.com --device
```

> **Version-sensitive.** `--device` needs **GitLab 17.9 or later** on the server.

**Token vs OAuth, close call.** Tiebreaker: whether your GitLab admins will register the OAuth app. If they will, OAuth (no long-lived secret on disk, auto-refresh). If they won't, a PAT with a 90-day expiry in the keyring.

#### Check what you are actually using

```bash
glab auth status                                  # host from current context
glab auth status --all                            # every configured host
glab auth status --hostname gitlab.example.com    # one host
glab api user --hostname gitlab.example.com | jq '{username, is_admin: .is_admin, state}'
glab api version --hostname gitlab.example.com    # server version, useful for every version-sensitive note
```

`glab auth status` prints `Token found: ****` and, crucially, **where the token came from**. A line like `Token is from environment variable GITLAB_TOKEN. This takes precedence over tokens stored in config or keyring` is the answer to half of all "works on my machine" auth problems.

> **One-way door.** `glab auth status --show-token` prints the token in clear. In a screen share, a recorded terminal or a CI log, that token is now burned and must be revoked. Never use it in scripts.

#### Log out

```bash
glab auth logout --hostname gitlab.example.com   # removes from config.yml and the keyring
```

Logging out does not revoke the token server-side. Revoke it in the UI or with `glab token revoke` (below) if it may have leaked.

### Config files and precedence

#### Where things live

| File | Holds | Written by |
|---|---|---|
| `~/.config/glab-cli/config.yml` | global settings and the `hosts:` map, including tokens unless keyring-backed | `glab auth login`, `glab config set --global`, `glab config set --host` |
| `~/.config/glab-cli/aliases.yml` | `glab alias set` definitions | `glab alias set` |
| `.git/glab-cli/config.yml` | per-repository overrides | `glab config set KEY VALUE` (no `--global`) |
| `$GLAB_CONFIG_DIR/config.yml` | replaces the global file location entirely | you |

Search order for the global file: `$GLAB_CONFIG_DIR`, then `~/.config/glab-cli/`, then `$XDG_CONFIG_HOME/glab-cli/`, then `$XDG_CONFIG_DIRS/glab-cli/`. Files are created mode `0600`; keep them that way.

> **Gotcha.** glab rewrites `config.yml` and leaves timestamped backups next to it (`config.yml.bak-NNNNNNNNNN`, `.config.ymlNNNN`). **Those backups contain the same tokens.** If you rotate a token after a leak, delete the backups too, and exclude `~/.config/glab-cli/` from dotfile repos entirely.

#### A self-hosted host block

```yaml
host: gitlab.example.com          # default host when nothing else decides
git_protocol: ssh
glamour_style: dark
check_update: false
no_prompt: false
telemetry: false
hosts:
    gitlab.example.com:
        api_protocol: https
        api_host: gitlab.example.com
        git_protocol: ssh
        ssh_host:
        subfolder:
        proxy:
        ca_cert: /etc/pki/ca-trust/source/anchors/corp-root.pem
        container_registry_domains: registry.gitlab.example.com
        custom_headers: []
        user: USERNAME
    gitlab.com:
        api_protocol: https
        git_protocol: ssh
        is_oauth2: "true"
```

#### Setting keys

```bash
glab config set editor "nvim" --global
glab config set glab_pager "less -R" --global
glab config set telemetry false --global
glab config set host gitlab.example.com --global           # default host
glab config set ca_cert /etc/pki/ca-trust/source/anchors/corp-root.pem --host gitlab.example.com
glab config set proxy http://proxy.corp:3128 --host gitlab.example.com

glab config get host
glab config get ca_cert --host gitlab.example.com
glab config edit            # global file in $VISUAL/$EDITOR
glab config edit -l         # this repo's .git/glab-cli/config.yml
```

`--host` always writes to the global file, with or without `--global`. Without either flag, `config set` writes to the current repository's `.git/glab-cli/config.yml` — surprising the first time a setting "doesn't stick" in another checkout.

#### Keys worth changing on day one

| Key | Set to | Why |
|---|---|---|
| `host` | your self-hosted FQDN | otherwise every out-of-repo call goes to gitlab.com |
| `telemetry` | `false` | glab sends usage data to your instance by default |
| `check_update` | `false` in images/CI | removes a network call and a stderr banner |
| `glab_pager` | `less -R` | long `mr view --comments` output stays readable |
| `remote_alias` | `origin` or `upstream` | forks with two GitLab remotes otherwise resolve to the wrong project |
| `display_hyperlinks` | `false` if your terminal mangles OSC 8 | clean copy-paste of tables |

### Environment variables

The subset that matters on a self-hosted workstation and in CI. Every config key has an env equivalent; env wins over the file. From **1.118** every unprefixed variable (`BROWSER`, `REMOTE_ALIAS`, `GIT_PROTOCOL`, `USE_KEYRING`…) also has a `GLAB_` name that is checked first; set the `GLAB_` form so it wins over an unrelated `BROWSER` or `PROXY` already exported in your shell.

| Variable | Does | When |
|---|---|---|
| `GITLAB_HOST` (`GITLAB_URI`, `GL_HOST`) | default hostname | one-off calls to a non-default host; cron scripts |
| `GITLAB_TOKEN` (`GITLAB_ACCESS_TOKEN`, `OAUTH_TOKEN`) | token, overrides config and keyring **for all hosts** | CI and short-lived subshells only |
| `GITLAB_REPO` | default project for `-R` | a script that works on one project from anywhere |
| `GITLAB_GROUP` | default group for list commands | group-wide `mr list`/`issue list`/`variable list` |
| `GLAB_NO_PROMPT` (`NO_PROMPT`) | disables interactive prompts | every script and CI job |
| `GLAB_ENABLE_CI_AUTOLOGIN` | use `CI_JOB_TOKEN` automatically in CI | glab inside pipelines |
| `GLAB_CA_CERT` | PEM bundle to trust | private CA without touching the config file |
| `GLAB_CLIENT_CERT` / `GLAB_CLIENT_KEY` | mTLS client cert and key | instances behind mutual TLS |
| `GLAB_SKIP_TLS_VERIFY` | disables TLS verification | never, see chapter 12 |
| `GLAB_PROXY` | per-host proxy, overrides `HTTPS_PROXY` | glab needs a different proxy from everything else |
| `GLAB_CONFIG_DIR` | alternative config directory | isolated test profiles; CI images |
| `GLAB_DEBUG` | logs git commands, alias expansion, DNS errors | "which remote did it pick?" |
| `GLAB_DEBUG_HTTP` | dumps HTTP requests and responses | API debugging; **headers include your token** |
| `GLAB_SEND_TELEMETRY` | `0` disables telemetry | CI |
| `NO_COLOR` | no ANSI colour | logs and `grep` |

> **Gotcha.** `GLAB_DEBUG_HTTP=1` prints request headers, including `PRIVATE-TOKEN` or `Authorization`. Never enable it in CI, and scrub the output before pasting it into an issue.

#### Scoped env with direnv

The clean way to use a different host or token per directory tree is direnv, not a global export:

```bash
# ~/work/corp/.envrc
export GITLAB_HOST=gitlab.example.com
export GLAB_NO_PROMPT=1
# token deliberately NOT exported here; glab reads it from the keyring for this host
```

Only export `GITLAB_TOKEN` inside a script's own process, never in `~/.zshrc`.

### Aliases

glab aliases live in `~/.config/glab-cli/aliases.yml` and expand before command parsing. Two kinds:

```bash
# Plain expansion: extra args are appended
glab alias set mine 'mr list --assignee=@me'
glab alias set rev  'mr list --reviewer=@me --not-draft'
glab alias set pipe 'ci status --compact'

# Positional placeholders
glab alias set co 'mr checkout "$1"'

# Shell aliases (-s / --shell): run through sh, can pipe; args only via $1..$N or $@
glab alias set --shell mrurls 'glab mr list --reviewer=@me -F json | jq -r ".[].web_url"'
glab alias set --shell failed 'glab ci list --status=failed -P 5 -R "$1"'

glab alias list
glab alias delete pipe
```

| Kind | Pipes and redirects | Extra args | Use for |
|---|---|---|---|
| plain | no | appended automatically | shortening a subcommand plus fixed flags |
| `--shell` | yes | **dropped** unless you use `$1`/`$@` | anything that ends in `jq`, `grep` or `xargs` |

> **Gotcha.** A shell alias silently ignores arguments you don't reference. `glab failed` with no `$1` in the body runs against the current project no matter what you type after it.

**Pick: zsh functions over glab `--shell` aliases** for anything longer than one pipe. They get completion, `shellcheck`, and `set -euo pipefail`. Keep glab aliases for pure shortening.

### Shell completion in zsh

glab generates a standard zsh completion function (`_glab`). Put it in the first directory on your `fpath` so compinit picks it up:

```bash
print -l $fpath | head -3               # first entry is where user completions belong
mkdir -p ~/.zsh/completions
glab completion -s zsh > ~/.zsh/completions/_glab

# in ~/.zshrc, BEFORE compinit
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
```

Then `rm -f ~/.zcompdump*; exec zsh` once. The upstream RPM also installs a completion into the system site-functions directory; if you use the RPM you may not need the file above. Regenerate after every upgrade — new subcommands don't appear otherwise.

For a single session: `source <(glab completion -s zsh); compdef _glab glab`.

`--no-desc` drops the descriptions if completion menus feel slow.

### Tokens: which kind, which scope

#### Pick by who acts

| Token | Acts as | Scope of reach | Lifetime | Use for |
|---|---|---|---|---|
| **Personal access token (PAT)** | you | everything you can reach | max 365 days by default | glab on your workstation, ad-hoc API work |
| **Fine-grained PAT** | you, but only listed resources and actions | narrower than your user | same limits | scripts you run as yourself that should not be able to do everything you can |
| **Project access token** | a bot user in one project | one project, at a role you choose | max 365 days | automation for a single repo (release bot, Renovate for one project) |
| **Group access token** | a bot user in one group | a group and its subgroups | max 365 days | automation across a group (reports, bulk labelling, backups) |
| **Deploy token** | nothing (no user) | read or write repo and registry/packages only, no API | optional expiry | pulling images or cloning from a cluster, a mirror, an air-gap sync box |
| **Deploy key** | nothing (SSH key) | one or more repositories over SSH | none | read-only Git access for a machine |
| **CI_JOB_TOKEN** | the user who triggered the job | the running project, plus projects that allowlisted it | while the job runs | pipeline calls into GitLab: packages, releases, cross-project clone, triggers |

**Default for automation: a group access token at the lowest role that works, 90-day expiry, rotated by schedule.** It survives staff leaving (PATs die with the user), it is scoped to a group rather than your whole reach, and its bot user shows up in audit logs as itself. Choose a project access token only when the automation truly touches one project.

> **Version-sensitive.** Fine-grained personal access tokens were introduced as beta in **GitLab 18.10** and became GA in **19.2**, on all tiers (docs.gitlab.com/auth/tokens/fine_grained_access_tokens). From 19.2 a self-managed admin can also enforce them instance-wide after a cut-off date, after which legacy PATs stop working. On older instances you only have legacy scoped PATs. Check `glab api version` before planning around them.

> **Gotcha.** Group and project access tokens may be disabled on your instance or tier, and creating one requires Maintainer (project) or Owner (group). If the UI option is missing, it is policy, not a bug.

#### Scopes that matter

| Scope | Grants | Typical holder |
|---|---|---|
| `api` | full read/write API, including Git over HTTPS | glab on a workstation |
| `read_api` | read-only API | reporting and audit scripts |
| `read_user` | your own profile via `/user` | OAuth apps, identity checks |
| `read_repository` | clone/pull over HTTPS | mirrors, deploy-style bots |
| `write_repository` | push over HTTPS | release bots that tag |
| `read_registry` / `write_registry` | container registry pull/push | image sync jobs |
| `create_runner` / `manage_runner` | runner registration and management | runner provisioning |
| `k8s_proxy` | Kubernetes API through the agent | `glab cluster agent update-kubeconfig` |
| `self_rotate` | the token may rotate itself | long-running automation that renews its own token |

glab's documented minimum for full functionality is `api` plus `write_repository`. **For report and audit scripts, issue a separate `read_api` token.** A read-only token cannot be talked into deleting a branch by a buggy loop.

#### Expiry and rotation

- Default and maximum PAT lifetime is **365 days**; admins can lower it. GitLab 17.6+ can extend to 400 days behind the `buffered_token_expiration_limit` feature flag (off by default).
- Expiry emails go out 7 days ahead, and from 17.7 also at 30 and 60 days.
- A token expires at **00:00 UTC** on its expiry date, which is the evening before in Eastern time. Automation that "expires on the 15th" is dead on the evening of the 14th in Toronto.

glab manages tokens directly:

```bash
glab token list --user @me --active                        # your PATs, metadata only
glab token list --group GROUP/SUBGROUP -F json | jq '.[] | {name, expires_at, scopes}'
glab token list --repo GROUP/PROJECT

# Create a 90-day read-only group token for a report job
glab token create --group GROUP --access-level reporter --scope read_api \
  --duration 90d --description "weekly MR report" mr-report-bot

# Rotate: old value dies immediately, new value printed to stdout
glab token rotate --group GROUP mr-report-bot --duration 90d
glab token revoke --group GROUP mr-report-bot
```

> **One-way door.** `glab token rotate` and `glab token revoke` invalidate the old secret **immediately**. Anything still using it breaks on its next call. Have the consumer's update path ready (CI variable, secret store) before you rotate, and pipe the output straight into it rather than to your terminal:
> `glab token rotate --group GROUP mr-report-bot --duration 90d | glab variable update REPORT_TOKEN --group GROUP --masked`

> **Gotcha.** Non-admins can only create personal access tokens for `@me` with the `k8s_proxy` scope through `glab token create`. For a normal `api` PAT, use the UI (User settings > Access tokens).

#### Expiry audit in one line

```bash
glab token list --group GROUP -F json \
  | jq -r --arg d "$(date -d '+30 days' +%F)" '.[] | select(.active and .expires_at != null and .expires_at < $d) | "\(.expires_at)  \(.name)"'
```

### glab in CI

Inside a GitLab job, prefer auto-login with the job token over storing a PAT:

```yaml
release:
  image: registry.gitlab.com/gitlab-org/cli:latest
  variables:
    GLAB_ENABLE_CI_AUTOLOGIN: "true"
    GLAB_NO_PROMPT: "1"
  script:
    - glab release list -R "$CI_PROJECT_PATH"
```

For commands that the job token cannot authorise (most write APIs outside releases, packages and a few others), log in explicitly with a group access token held in a masked, protected variable:

```bash
glab auth login --hostname "$CI_SERVER_FQDN" --api-protocol "$CI_SERVER_PROTOCOL" --stdin <<<"$GROUP_BOT_TOKEN"
```

Chapter 11 covers what `CI_JOB_TOKEN` can and cannot reach, and the allowlist.

### Traps

- **`GITLAB_TOKEN` exported globally** hijacks every host. `glab auth status` tells you; believe it.
- **Out-of-repo calls go to the default host.** Set `host` in config or pass `--hostname`.
- **Fedora's glab is far behind upstream.** Half the flags in chapter 09 don't exist in 1.89.
- **Moved binary, broken Git HTTPS.** The credential helper path in `~/.gitconfig` is absolute.
- **`config set` without `--global` writes to the current repo only.**
- **Config backups hold tokens.** Clean them after rotation.
- **`--show-token` and `GLAB_DEBUG_HTTP` print secrets.** Treat their output as a leak.
- **Tokens expire at midnight UTC**, hours earlier than you think in Canada.
- **PATs die with their owner.** Automation belongs on group or project access tokens.


---


<a id="09-glab-by-intent"></a>

## 09 · glab by intent

*glab defaults every command to "the MR, pipeline or project of the branch I'm on", so the fastest workflow is to stay in the repo and let it infer. Every flag in this chapter was checked against glab 1.108's own --help; anything newer than that is marked.*

### Conventions in this chapter

- Commands run **inside a checkout** unless they show `-R GROUP/PROJECT`. `-R` accepts `GROUP/PROJECT`, `GROUP/SUB/PROJECT`, a full HTTPS URL or a Git URL.
- **MR and issue arguments** accept an IID (`123`), a branch name, and for many commands a full URL. No argument means "the MR for the current branch".
- **Scriptable output** is `-F json` on most list/view commands (issue list uses `-O json`, see below), and most of them take `--jq EXPR` so you don't need a pipe.
- Set `GLAB_NO_PROMPT=1` in scripts. Many commands prompt when an argument is missing.

> **Gotcha.** `glab issue list` is the odd one out: `-F` there is `--output-format` (`details`, `ids`, `urls`) and JSON is `-O json`. On `mr list`, `ci list` and most others, `-F` is `--output` and takes `json`. Muscle memory from one breaks the other.

### Merge requests

#### Open one

**Default: `glab mr create --fill --draft`** from the feature branch. `--fill` takes the title and body from your commits and **pushes the branch for you** (it sets `--push`), so there is no separate `git push -u`.

```bash
# The everyday one: push, create draft, title/body from commits
glab mr create --fill --draft --yes

# Multi-commit branch: body lists each commit's body, not just subjects
glab mr create --fill --fill-commit-body --draft --yes

# Reviewers, labels, target, squash, remove branch, auto-merge when checks pass
glab mr create --fill --yes \
  --target-branch main \
  --reviewer alice,bob \
  --assignee @me \
  --label "type::bug,team::platform" \
  --squash-before-merge \
  --remove-source-branch \
  --auto-merge

# Explicit title/body, from the repo's MR template
glab mr create -t "Fix TLS reload on SIGHUP" --template bug_fix --yes

# From an issue: MR linked to issue 42, title from the issue unless -t is given
glab mr create --related-issue 42 --copy-issue-labels --draft --fill --yes

# Branch doesn't exist remotely yet and you have no local commits to push
glab mr create --create-source-branch -s spike/idea -b main -t "Spike" --draft --yes
```

| Flag | Does | When |
|---|---|---|
| `-f`, `--fill` | title/body from commits, implies push | always, unless you want to type a title |
| `--fill-commit-body` | body = every commit body | branches with meaningful commit bodies |
| `--draft` (`--wip`) | draft MR | anything you haven't finished |
| `--reviewer` / `-a` | reviewers / assignees (comma list or repeated) | every non-draft MR |
| `-l`, `--label` | labels | team boards, scoped labels |
| `-b`, `--target-branch` | target | not the default branch |
| `--push` | push after creating | without `--fill` |
| `--auto-merge` | merge when all checks pass | trivial MRs you trust CI on |
| `--squash-before-merge`, `--remove-source-branch` | override project defaults (true/false) | project default is wrong for this MR |
| `-i`, `--related-issue` | MR for an issue | issue-driven work |
| `--template` | fill body from `.gitlab/merge_request_templates/NAME.md` | repos with templates |
| `-H`, `--head` | source project (fork) | MR from a fork into upstream |
| `--signoff` | append DCO sign-off to the description | DCO-enforcing projects |
| `-y`, `--yes` | skip the "submit?" prompt | scripts, and once you trust `--fill` |

> **Gotcha.** `--template` reads templates from your **local checkout**, not the server. A template added on `main` after you branched is invisible until you rebase.

> **Note.** `glab mr for ISSUE` still works but is deprecated in 1.108; use `glab mr create --related-issue ISSUE`.

#### Find and read

```bash
glab mr list                                   # open MRs in this project
glab mr list --reviewer=@me --not-draft        # your review queue
glab mr list --assignee=@me
glab mr list --author=USERNAME --merged --created-after 2026-09-01
glab mr list --label "team::platform" --not-label "workflow::blocked"
glab mr list -g GROUP                          # across a group (ignored if -R is set)
glab mr list --target-branch main --search "helm"
glab mr list -F json --jq '.[] | "\(.iid)\t\(.title)"'

glab mr view                                   # MR for current branch
glab mr view 123 --comments                    # with discussion
glab mr view 123 --unresolved                  # only open threads
glab mr view 123 --web
glab mr view 123 -F json --jq '{state, merge_status: .detailed_merge_status, pipeline: .head_pipeline.status}'

glab mr issues 123                             # issues this MR closes on merge
glab mr approvers 123                          # who is eligible, from approval rules
```

`detailed_merge_status` in the JSON is the field that tells you *why* an MR won't merge (`not_approved`, `ci_must_pass`, `discussions_not_resolved`, `need_rebase`, `draft_status`, `conflict` and others). It is more useful than anything in the text view.

#### Check out someone's MR

```bash
glab mr checkout 123                           # local branch named after the source branch
glab mr checkout 123 --branch review/123       # your own local name
glab mr checkout 123 --force                   # reset local branch to remote when diverged
glab mr checkout https://gitlab.example.com/GROUP/PROJECT/-/merge_requests/123
```

> **Gotcha.** `--force` resets your local branch to the remote. It refuses if the working tree has changes that would be lost, but **local commits on that branch that aren't on the remote are discarded**. Recover them from `git reflog` (chapter 05) if you do this by accident.

#### Read the diff

```bash
glab mr diff 123                              # coloured, paged
glab mr diff 123 --raw | git apply --check    # raw patch, pipeable
glab mr diff 123 --raw > mr-123.patch
glab mr diff 123 --color=never | grep -n TODO
```

For a real review, `glab mr checkout` plus your own `git diff main...HEAD` in your editor beats reading patches in a pager.

#### Comment and resolve

```bash
# Top-level comment (legacy form, still the shortest)
glab mr note 123 -m "Rebased on main, ready for another look."

# Structured notes (EXPERIMENTAL in 1.108)
glab mr note create 123 -m "LGTM"
glab mr note create 123 -m "Deploy preview: https://..." --resolvable=false   # doesn't block "all threads resolved"
glab mr note create 123 -m "LGTM" --unique                                   # no-op if identical note exists
glab mr note create 123 --file charts/app/values.yaml --line 42 -m "Needs a schema entry"
glab mr note create 123 --file main.go --line 10:15 -m "Extract this block"
glab mr note create 123 --file main.go --old-line 7 -m "Why was this removed?"
glab mr note create 123 --reply abc12345 -m "Fixed in the last push"

glab mr note list 123 --state unresolved
glab mr note list 123 --type diff -F json --jq '.[].notes[] | "\(.author.username): \(.body)"'
glab mr note resolve abc12345          # discussion ID prefix (8+ chars) or a note ID; MR from current branch
glab mr note resolve 123 abc12345      # explicit MR first, discussion last
glab mr note reopen abc12345
```

> **Gotcha.** The rendered usage line in 1.108 reads `resolve <discussion-id> [<id> | <branch>]`, but that's the help formatter reordering it. The source declares `resolve [<id> | <branch>] <discussion-id>` and always takes the **last** argument as the discussion (`mr_note_resolve.go`), so the example `resolve 123 abc12345` is the correct order. `reopen` works the same way.

`--unique` and `--resolvable=false` are the two flags that make bot comments sane: idempotent, and not blocking merge on a status message.

> **Version-sensitive.** The `glab mr note create|list|resolve|reopen|update|delete` subcommands are marked **EXPERIMENTAL** in 1.108 and still are in 1.119. **1.119** adds `mr note create --draft` (a pending review comment) and `glab mr note publish` to submit them as one review. Pin glab in CI images if you script against them.

#### Update

```bash
glab mr update --ready                         # draft -> ready (current branch)
glab mr update 123 --draft
glab mr update 123 --reviewer +carol           # add; '-bob' or '!bob' removes; bare list replaces
glab mr update 123 --assignee -alice
glab mr update 123 --label "workflow::review" --unlabel "workflow::in-dev"
glab mr update 123 --target-branch release/2.4
glab mr update 123 --fill --fill-commit-body --yes   # refresh title/body from commits
glab mr update 123 --milestone ""                    # unassign milestone
```

> **Gotcha.** `--reviewer alice` with no prefix **replaces** the whole reviewer list. Use `+alice` to add. Same for `--assignee`.

#### Approve

```bash
glab mr approve 123
glab mr approve 123 --sha "$(git rev-parse HEAD)"   # only if the MR head is exactly what you reviewed
glab mr revoke 123                                  # withdraw approval
```

**Default: always approve with `--sha` after a local review.** Without it, a force-push between your review and your click gets your approval.

#### Merge

```bash
glab mr merge 123                          # auto-merge if a pipeline is running, else merge now
glab mr merge 123 --squash --remove-source-branch --yes
glab mr merge 123 --rebase --yes           # rebase onto target, then merge
glab mr merge 123 --sha "$(git rev-parse HEAD)" --yes
glab mr merge 123 --auto-merge=false --yes # merge immediately, don't wait for the pipeline
glab mr merge 123 --squash --squash-message "feat(api): keyset pagination (#123)" --yes
```

| Flag | Does |
|---|---|
| `--auto-merge` (default `true`) | set "merge when checks pass" if a pipeline is running |
| `--auto-merge=false` | merge now; fails if checks block it |
| `-s`, `--squash` / `--squash-message` | squash, with a custom commit message |
| `-r`, `--rebase` | rebase the source branch before merging |
| `-d`, `--remove-source-branch` | delete source branch after merge |
| `-m`, `--message` | custom merge commit message |
| `--sha` | merge only if head matches this SHA |

> **Gotcha.** In 1.108 **auto-merge is on by default**. `glab mr merge` on an MR with a running pipeline does not merge; it arms auto-merge and returns. If the pipeline then fails, nothing merges and nothing tells you unless you watch. Check with `glab mr view 123 -F json --jq .merge_when_pipeline_succeeds`.

> **One-way door.** A merge to a protected branch is not undone by anything glab offers. You revert with a new MR (`git revert -m 1 MERGE_SHA`, chapter 04). With `--remove-source-branch`, the source branch is gone too; restore it from the MR's head SHA with `git push origin SHA:refs/heads/BRANCH`.

#### Rebase server-side

```bash
glab mr rebase 123              # GitLab rebases the source branch onto target
glab mr rebase 123 --skip-ci    # don't start a pipeline for the rebased head
```

Use it when the MR shows `need_rebase` and the branch is not yours to force-push locally. It needs push permission on the source branch; without it you get a 403.

#### Close, reopen, delete, bookkeeping

```bash
glab mr close 123 124 125
glab mr reopen 123
glab mr subscribe 123 ; glab mr unsubscribe 123
glab mr todo 123                 # add to your to-do list
glab mr delete 123               # needs Owner or admin
```

> **One-way door.** `glab mr delete` removes the MR and its discussion permanently. Close instead unless it contains something that must not exist (a leaked secret in a description, for example).

### Issues and boards

```bash
glab issue list                                         # open issues
glab issue list --assignee=@me
glab issue list --label "type::bug" --not-label "workflow::done" -P 100
glab issue list -g GROUP --search "OOMKilled" --in title
glab issue list --milestone "2026-Q4" --closed
glab issue list -O json | jq -r '.[] | "\(.iid)\t\(.title)"'
glab issue list -F urls                                 # one URL per line

glab issue view 42 --comments
glab issue view https://gitlab.example.com/GROUP/PROJECT/-/issues/42

glab issue create -t "Loki compactor OOMs at 2Gi" -d "See runbook..." \
  -l "type::bug,team::platform" -a @me -m "2026-Q4" --yes
glab issue create -t "CVE-2026-XXXX in base image" -l security --confidential --yes
glab issue create -t "Upgrade cert-manager" --template chore --yes
glab issue create -t "Rotate group token" --due-date 2026-12-01 --weight 2 --yes

glab issue update 42 --label "workflow::in-progress" --unlabel "workflow::ready"
glab issue update 42 --assignee +bob
glab issue note 42 -m "Reproduced on 17.11; root cause is the default retention."
glab issue close 42
glab issue reopen 42
```

Boards:

```bash
glab issue board view                        # interactive TUI of the project's boards
glab issue board view --labels "team::platform" --assignee USERNAME
glab issue board create --name "Platform sprint"
```

Scoped labels (`workflow::review`) are mutually exclusive by design; `glab issue update --label workflow::review` automatically removes the other `workflow::` label on the server side. That makes them the right primitive for board columns.

Incidents behave like issues with their own subcommand: `glab incident list`, `view`, `note`, `close`, `reopen`.

### Pipelines and jobs

#### Status at a glance

```bash
glab ci status                          # pipeline for current branch
glab ci status --compact
glab ci status --branch main
glab ci status --live                   # redraw until finished
glab ci status --wait                   # block until finished, no prompt at the end
glab ci status -F json --jq '.status'
```

> **Note.** `-F json` is incompatible with `--live`, `--wait` and `--compact` (per `--help`). In text mode, `glab ci status` exits **1 only when the final status is `failed`** (`internal/commands/ci/status/status.go`, same in 1.108 and 1.119). `canceled`, `skipped` and `manual` all exit 0, and `--wait` stops polling at `manual` because it won't progress on its own. `--wait` does follow a newer pipeline when the current one is auto-cancelled. For a CI gate that must treat anything other than `success` as failure, poll `glab ci get -F json --jq .status` and test the value yourself.

#### The TUI

```bash
glab ci view                 # current branch
glab ci view main
glab ci view -p PIPELINE_ID
glab ci view -b main -R GROUP/PROJECT
```

Keys: arrows or `hjkl` to move; `Enter` opens a job's log or a child pipeline (trigger jobs show `»`); `Esc`/`q` back; `Ctrl+R`/`Ctrl+P` run, retry or play a job; `Ctrl+D` cancel; `Ctrl+Space` suspend and dump the log to the terminal; `Ctrl+Q` quit.

**Default for "why is my MR red": `glab ci view`.** It shows downstream and child pipelines in one tree, which the web UI hides behind clicks.

#### Details, logs, retries

```bash
glab ci get                                        # latest pipeline for this branch
glab ci get -p PIPELINE_ID --with-job-details
glab ci get --merge-request 42 --status failed -d  # failed jobs of MR !42's head pipeline
glab ci get -F json --jq '.jobs[] | select(.status=="failed") | .name'

glab ci trace                  # pick a job interactively, stream its log
glab ci trace lint             # by job name, current branch's pipeline
glab ci trace 16627952780      # by job ID
glab ci trace deploy -b main

glab ci retry lint             # retry by name
glab ci retry 16627952780
glab ci trigger deploy-prod    # play a manual job
glab ci cancel pipeline PIPELINE_ID --dry-run
glab ci cancel pipeline PIPELINE_ID
glab ci cancel job JOB_ID
glab ci cancel job JOB_ID --force   # job in a protected environment
```

`glab ci get --merge-request` targets the MR's **head pipeline**, which differs from `--branch` for forks and merged-results pipelines. For MR work, use it.

#### Find pipelines

```bash
glab ci list --status failed -P 10
glab ci list --ref main --status failed --updated-after 2026-09-01T00:00:00Z
glab ci list --source schedule
glab ci list --username renovate-bot
glab ci list -y                                  # pipelines with invalid YAML
glab ci list -F json --jq '.[] | "\(.id) \(.status) \(.ref)"'
```

#### Run a pipeline

```bash
glab ci run                                   # current branch
glab ci run -b main
glab ci run -b main --variables-env DEPLOY_ENV:staging --variables-env DRY_RUN:true
glab ci run -b main --variables-file KUBECONFIG_B64:./kubeconfig.b64
glab ci run -b main --variables-from vars.json
glab ci run -b main --input "replicas:int(3)" --input "debug:bool(false)" --input 'regions:array(ca-central,us-east)'
glab ci run --mr                              # merge request pipeline for this branch's MR
glab ci run -b main --web
```

| Flag | Does | Note |
|---|---|---|
| `--variables`, `--variables-env` | `KEY:value` pipeline variables | not with `--mr` |
| `--variables-file` | `KEY:path` file-type variable | not with `--mr` |
| `-f`, `--variables-from` | JSON array of `{key, value, variable_type}` | not with `--mr` |
| `-i`, `--input` | typed `spec:inputs`, `key:type(value)` | not with `--mr`; quote anything with parentheses |
| `--mr` | MR pipeline instead of branch pipeline | no variables or inputs allowed |

> **Gotcha.** Values with commas: `--variables-env KEY:a,b` is parsed as two variables. Quote and use `--variables "KEY:a,b,c"` as `--help` shows, or use `--variables-from` with JSON, which has no parsing ambiguity.

Trigger tokens (from a different system, or cross-project without an allowlist):

```bash
glab ci run-trig -t "$TRIGGER_TOKEN" -b main --variables DEPLOY_ENV:prod
```

#### Lint and compile config

```bash
glab ci lint                                  # .gitlab-ci.yml in cwd, server-side validation
glab ci lint path/to/.gitlab-ci.yml
glab ci lint --dry-run --ref main --include-jobs   # simulate pipeline creation on main, list jobs
glab ci config compile > /tmp/merged-ci.yml   # includes resolved, extends flattened
```

**Default before pushing CI changes: `glab ci lint --dry-run --ref BRANCH --include-jobs`.** Static lint does not evaluate `rules:`; the dry run does, so it catches "job silently never runs".

`glab ci config compile` is the fastest way to answer "what does this job actually look like after five `include:` and three `extends:`". Diff two compiles to review a CI refactor:

```bash
git stash; glab ci config compile > /tmp/before.yml; git stash pop
glab ci config compile > /tmp/after.yml
diff -u /tmp/before.yml /tmp/after.yml
```

#### Artifacts

```bash
glab job artifact main build                          # latest successful pipeline on main, job "build"
glab job artifact main build --path ./out/ --list-paths
glab job artifact refs/merge-requests/123/head test   # MR pipeline on source head
glab job artifact refs/merge-requests/123/merge test  # merged-results pipeline
```

> **Note.** `glab ci artifact` is deprecated in 1.108 in favour of `glab job artifact`. Same arguments.

#### Delete old pipelines

```bash
glab ci delete --status failed --older-than 720h --dry-run --paginate
glab ci delete --status failed --older-than 720h --paginate
glab ci delete --source api --older-than 168h --dry-run
```

> **One-way door.** Deleting a pipeline deletes its jobs, logs and artifacts. Always run the same command with `--dry-run` first and read the list.

### Releases and changelog

```bash
glab release list
glab release view                 # latest
glab release view v2.4.0 -F json --jq '.assets.links[].name'
glab release download v2.4.0 --asset-name "*.tar.gz" --dir ./dl

# Tag exists and is pushed: create release with notes from a file and assets
glab release create v2.4.0 -F CHANGELOG-2.4.0.md ./dist/*.tar.gz 'dist/checksums.txt#Checksums#other'

# Tag doesn't exist: create it from a ref, annotated
glab release create v2.4.1 --ref main --tag-message "v2.4.1" --notes "Hotfix: ..."

# Attach to milestones (closed on release unless --no-close-milestone)
glab release create v2.5.0 -m "2026-Q4" --notes-file notes.md

# Add assets later; store them in the generic package registry
glab release upload v2.4.0 ./dist/*.rpm --use-package-registry
```

Asset syntax is `path#Display name#type`, type one of the GitLab link types (`other` default, `package`, `image`, `runbook`).

> **Gotcha.** `glab release create TAG` on a tag that **doesn't exist** creates the tag from the tip of the default branch. A typo in the tag name gives you a new, wrong release rather than an error. Pass `--ref` explicitly or create and push the tag first.

> **Gotcha.** `glab release create` on an **existing** release updates it. Use `--no-update` in pipelines where re-running must not overwrite notes.

Changelog generation uses GitLab's server-side changelog API, driven by commit trailers:

```bash
glab changelog generate                          # version from `git describe`
glab changelog generate --version 2.4.0 --from PREV_SHA --to HEAD_SHA
glab changelog generate --trailer Changelog --config-file .gitlab/changelog_config.yml
```

Commits are included only if they carry a trailer like `Changelog: fixed`. If your team doesn't write trailers, this command returns an empty changelog; that is working as designed.

### CI/CD variables

```bash
glab variable list                              # project; values not shown in text output
glab variable list --group GROUP --per-page 100
glab variable get DEPLOY_TOKEN                  # prints the value
glab variable get KUBECONFIG --scope production

# Create: masked + protected, value from stdin (never argv)
secret-tool lookup service gitlab item deploy-token | glab variable set DEPLOY_TOKEN --masked --protected
glab variable set DEPLOY_ENV staging --scope staging --description "set by platform"
glab variable set CA_BUNDLE --type file < corp-ca.pem
glab variable set LITERAL_DOLLARS --raw -v 'pa$$word$HOME'
glab variable set SECRET --hidden --masked < secret.txt       # hidden: value never shown again in UI

glab variable update DEPLOY_ENV production --scope production
glab variable delete OLD_VAR
glab variable export --output env > vars.env    # KEY=VALUE, includes secrets
```

| Flag | Does |
|---|---|
| `-m`, `--masked` | masked in job logs (value must meet masking rules) |
| `-p`, `--protected` | only exposed to pipelines on protected refs |
| `--hidden` | never revealed in the UI or API again; pair with `--masked` (set-only, not on `update`) |
| `-r`, `--raw` | no `$VAR` expansion inside the value |
| `-t file` | written to a temp file; the variable holds the path |
| `-s`, `--scope` | environment scope (default `*`) |

> **Gotcha.** Without `--raw`, a value containing `$` is expanded at job time. A password like `ab$cd` becomes `ab` plus the value of `$cd` (empty). Default to `--raw` for secrets.

> **Gotcha.** `glab variable export` and `glab variable get` print **secret values**. `variable list` in text mode doesn't, but `-F json` does include values. For a names-only audit see chapter 10.

### Schedules

```bash
glab schedule list
glab schedule list -F json --jq '.[] | "\(.id)\t\(.cron)\t\(.ref)\t\(.active)\t\(.description)"'
glab schedule create --cron "0 6 * * 1-5" --cronTimeZone "America/Toronto" \
  --ref main --description "Nightly image rebuild" --variable "REBUILD:true"
glab schedule run SCHEDULE_ID                   # one-off run now, cron unaffected
glab schedule update SCHEDULE_ID --active=false
glab schedule update SCHEDULE_ID --update-variable "REBUILD:false" --delete-variable OLD_VAR
glab schedule delete SCHEDULE_ID
```

> **Gotcha.** `--cronTimeZone` defaults to **UTC**. A schedule created as `0 6 * * *` without it runs at 02:00 Toronto time in summer and 01:00 in winter.

### Repositories

```bash
glab repo view                                 # description + README
glab repo view GROUP/PROJECT -F json --jq '{id, default_branch, visibility, archived}'
glab repo list -g GROUP --include-subgroups -P 100 -F json --jq '.[].path_with_namespace'
glab repo list --member --archived=false
glab repo search -s "helm-charts"

glab repo clone GROUP/PROJECT
glab repo clone GROUP/PROJECT -- --depth 1 --single-branch
glab repo clone -g GROUP --archived=false --paginate --preserve-namespace   # whole group, tree layout

glab repo fork GROUP/PROJECT --clone=true --remote=true
glab repo create GROUP/new-service --private --defaultBranch main --readme
glab repo update GROUP/PROJECT --description "..." --defaultBranch main
glab repo archive GROUP/PROJECT ./out --format tar.gz --sha v2.4.0         # download a tarball
glab repo contributors
glab repo members add --username USERNAME --role developer --expires-at 2026-12-31
glab repo members remove --username USERNAME
glab repo mirror GROUP/PROJECT --direction push --url "ssh://git@backup.example.com/GROUP/PROJECT.git"
```

> **Gotcha.** `glab repo archive` downloads an archive. **It does not archive the project.** To mark a project read-only, use `glab repo update PROJECT --archive`.

> **One-way door.** `glab repo delete` and `glab repo transfer` are the two destructive repo commands. Delete may be delayed (pending deletion) or immediate depending on instance settings; transfer changes every URL, container image path and CI include reference that points at the old namespace.

#### Prune local branches

```bash
glab repo prune --dry-run                     # branches whose MR merged and none still open
glab repo prune --exclude 'wip-*,demo' --yes
glab repo prune --merged --dry-run            # fast, git-only: misses squash and rebase merges
```

**Default: `glab repo prune` without `--merged`.** It asks GitLab which MRs merged, so it catches squash-merged branches that `git branch --merged` never will. It only touches local branches; chapter 12 has the remote-side script.

### Snippets

1.108 only offers `create`; list and read through the API (chapter 10).

```bash
glab snippet create -t "nft ruleset for runners" ./runner.nft             # project snippet
glab snippet create --personal -t "zsh helper" -v private ./helpers.zsh
kubectl get events -A | glab snippet create -t "events at incident" -f events.txt
```

Default visibility is `private`. On self-hosted instances, `internal` means everyone with an account.

### Stacked diffs with glab stack

`glab stack` manages a chain of small branches, one MR per layer, each targeting the one below. It stores metadata under `.git/stacked/`.

```bash
git switch main && git pull
glab stack create api-pagination          # start a stack
# edit ...
glab stack save -a -m "Add keyset cursor type"          # layer 1 = commit + branch
# edit ...
glab stack save -a -m "Use cursor in /projects handler" # layer 2
glab stack sync --reviewer alice --label "team::api"    # push all, create/update MRs

# address review on layer 1
glab stack first            # or: prev / next / last / move (fuzzy picker)
# edit ...
glab stack amend -a -m "Address review: validate cursor"
glab stack sync             # rebases layers above, pushes, updates MRs

glab stack sync --update-base   # rebase entire stack onto latest main
glab stack list
glab stack reorder
glab stack switch other-stack

# Adopt existing commits as a stack
glab stack infer --name api-pagination main..HEAD
```

`glab stack sync` also deletes local branches whose layer merged or closed. Branch names use `branch_prefix` (default `$USER`).

> **Version-sensitive.** `glab stack` is **EXPERIMENTAL** in 1.108 ("might be unstable or removed at any time"). Fine for your own work; don't build team process on it without pinning a version.

**Close call: `glab stack` versus plain branches with `git rebase --update-refs`.** Tiebreaker: whether you want glab to create and retarget the MRs for you. If yes, `glab stack`. If you already manage MRs by hand, `--update-refs` (chapter 04) gives you the same rebasing with no extra metadata.

### To-do list

```bash
glab todo list
glab todo list --type MergeRequest
glab todo list --action build_failed
glab todo list --action approval_required -F json --jq '.[] | .target_url'
glab todo done TODO_ID
glab todo done --all
```

Valid `--action` values in 1.108: `assigned`, `mentioned`, `build_failed`, `marked`, `approval_required`, `directly_addressed`.

### Other daily lookups

```bash
glab label list -F json --jq '.[].name'
glab label create --name "team::platform" --color "#6699cc" --description "Platform team"
glab milestone list --group GROUP --state active
glab iteration list -g GROUP
glab user events -F json --jq '.[] | "\(.created_at) \(.action_name) \(.target_title)"'
glab deploy-key list
glab ssh-key list
glab token list --user @me --active
```

### Traps

- **`-F` means different things** on `issue list` (`--output-format`) and everywhere else (`--output`).
- **`--fill` pushes.** If you didn't want the branch on the server yet, don't use it.
- **`--reviewer alice` replaces**; `+alice` adds.
- **`glab mr merge` arms auto-merge by default** when a pipeline is running.
- **Approve and merge with `--sha`** so a late force-push can't ride your review.
- **`glab release create` on a missing tag** creates one from the default branch.
- **`glab repo archive` downloads**; `repo update --archive` archives.
- **Schedules default to UTC.**
- **Variables without `--raw` expand `$`.**
- **Experimental subcommands** (`mr note create`, `stack`) can change between minor versions; pin glab in CI images.


---


<a id="10-glab-api-in-depth"></a>

## 10 · glab api in depth

*glab api is curl that already knows your host, your token and your project, and it does the pagination for you. Anything the glab subcommands don't cover is one glab api call away, so learn its five flags and keep a recipe file.*

### Why glab api over curl

| Concern | `curl` | `glab api` |
|---|---|---|
| Host | you type it | from the Git remote, `--hostname`, or config |
| Token | you handle it (and leak it into history) | from keyring/config, never on the command line |
| Project path encoding | you `%2F`-encode | `:fullpath` / `:id` placeholders do it |
| Pagination | you parse `Link` headers | `--paginate` |
| GraphQL cursors | you loop | `--paginate` with `$endCursor` |
| Output | raw | pretty JSON, or `--output ndjson` for streaming |

**Default: `glab api` for anything interactive and for scripts that run as you.** Drop to curl (chapter 11) only where glab is not installed (minimal CI images, other people's machines) or you need exact control over retries and headers.

### The flags that matter

```bash
glab api ENDPOINT [flags]
```

| Flag | Does | When |
|---|---|---|
| `-X`, `--method` | HTTP method | anything that isn't a plain GET |
| `-f`, `--raw-field key=value` | string parameter | text values, including numbers you want as strings |
| `-F`, `--field key=value` | typed parameter: `true`/`false`/`null`/integers become JSON types; `@file` reads a file; `@-` reads stdin | booleans, IDs, file contents |
| `--input FILE` | raw request body (`-` for stdin); fields then become query params | JSON arrays and objects |
| `--form key=value` | multipart form; `@path` uploads a file | uploads (wiki attachments, project import) |
| `-H`, `--header` | extra header | `If-None-Match`, `Sudo` |
| `--paginate` | follow every page | any list endpoint |
| `--output ndjson` | one JSON value per line | streaming into `jq` |
| `-i`, `--include` | print response headers | pagination and rate-limit debugging |
| `--silent` | no body | writes where you only care about the exit code |
| `--hostname` | target host | out-of-repo scripts, multiple instances |

#### Method inference is the trap

**Any `-f`, `-F` or `--form` switches the default method from GET to POST.** To send query parameters on a GET, either put them in the URL or force `-X GET`:

```bash
# Both are GETs with the same query string (verified)
glab api 'projects/:fullpath/merge_requests?state=merged&per_page=2'
glab api -X GET projects/:fullpath/merge_requests -f state=merged -F per_page=2
```

> **Gotcha.** `glab api projects/:fullpath/merge_requests -f state=opened` without `-X GET` is a **POST to the create-MR endpoint**. It fails with a 400 for missing fields today; against an endpoint whose POST has no required fields, it creates something. Always write `-X GET` when you use fields to filter.

#### Field typing

```bash
-F per_page=100            # integer 100
-F squash=true             # boolean
-F milestone_id=null       # JSON null
-f title=123               # the string "123"
-F description=@notes.md   # file contents
-F body=@-                 # stdin
```

In 1.108 neither `-f` nor `-F` builds arrays or objects. **glab 1.113+** parses `-F` values that start with `[` or `{` as JSON (`-F 'allowed_to_push=[{"access_level":40}]'`); `-f` still sends them as strings. Until your fleet is on 1.113, arrays in query strings use bracket syntax (`-f 'scope[]=failed' -f 'scope[]=canceled'`); JSON bodies with nested structures go through `--input`:

```bash
jq -n '{allowed_to_push: [{access_level: 40}], allowed_to_merge: [{access_level: 30}]}' \
  | glab api -X PATCH "projects/:id/protected_branches/main" --input - -H 'Content-Type: application/json'
```

### Placeholders

Inside a checkout, glab substitutes values taken from the Git remote. Verified in a repo whose `origin` is `git@gitlab.com:gitlab-org/cli.git`:

| Placeholder | Expanded to | Example use |
|---|---|---|
| `:fullpath` | URL-encoded `namespace/project` (`gitlab-org%2Fcli`) | `projects/:fullpath/...` |
| `:id` | same encoded path, not the numeric ID | `projects/:id/...` |
| `:namespace` | the namespace after the top-level group: `gitlab-org` for `gitlab-org/cli`, but only `sub` for `top/sub/proj` | `groups/:namespace/...` for top-level projects only |
| `:repo` | project path (`cli`) | rarely needed |
| `:branch` | the current local branch | `projects/:id/repository/branches/:branch` |
| `:user`, `:username` | the authenticated username | `users?username=:username` |
| `:group` | the top-level group, and **empty** when the project sits directly under it (`gitlab-org/cli`) | subgroup projects only |

> **Gotcha.** glab splits the remote path as `GROUP/NAMESPACE/REPO` on the first slash (`glrepo.FromURL` in the 1.108 source), so neither `:group` nor `:namespace` is the full namespace path of a subgroup project. For group endpoints, read it from the project: `glab api projects/:fullpath | jq -r .namespace.full_path`, URL-encode it, and build the path yourself.

> **Gotcha.** Placeholders need a Git repo. From anywhere else, glab exits 1 with `Unable to expand placeholder in path: fatal: not a git repository`. Scripts should build the path themselves: `P=$(jq -rn --arg p "$PROJECT" '$p|@uri')`.

> **Gotcha.** `:branch` is your **local** branch. If it hasn't been pushed, the API returns `404 Branch Not Found`, which reads like a permissions problem but isn't.

### Pagination

#### REST

GitLab defaults to 20 items per page, maximum 100. `--paginate` follows `Link: rel="next"` until it runs out, and respects `per_page`, so always pair them:

```bash
glab api --paginate 'projects/:id/repository/tags?per_page=100' | jq length
glab api --paginate --output ndjson 'projects/:id/repository/tags?per_page=100' | wc -l
```

In `json` mode glab merges all pages into one array. In `ndjson` mode it emits one element per line as it goes, so memory stays flat and `jq` can start immediately. **Default: `--output ndjson` for anything that might exceed a few thousand items.**

With `--paginate` and `-X GET -f ...` together, the fields become the query string of every page request. Verified: `-X GET --paginate -f state=opened -F per_page=20` on `merge_requests` returned all 66 open MRs across four pages, each filtered.

> **Note.** When a query matches more than 10,000 records, GitLab stops returning `X-Total`, `X-Total-Pages` and `rel="last"`. `--paginate` keeps working because it follows `rel="next"`; your progress bar based on `X-Total` does not.

#### GraphQL

`--paginate` works for GraphQL when the query takes `$endCursor: String` and selects `pageInfo { hasNextPage endCursor }` on exactly one connection:

```bash
glab api graphql --paginate -f query='
query($endCursor: String) {
  group(fullPath: "GROUP") {
    projects(includeSubgroups: true, first: 100, after: $endCursor) {
      nodes { fullPath archived lastActivityAt }
      pageInfo { hasNextPage endCursor }
    }
  }
}' | jq -r '.data.group.projects.nodes[] | [.fullPath, .archived, .lastActivityAt] | @tsv'
```

Any `-f`/`-F` other than `query` and `operationName` becomes a GraphQL variable:

```bash
glab api graphql -f query='query($p: ID!) { project(fullPath: $p) { name } }' -f p=GROUP/PROJECT
```

### REST or GraphQL

**Default: REST.** It is what the docs and error messages talk about, it pages with `--paginate` without query changes, and every endpoint is one line. Use GraphQL when:

- you need **fields from several resources in one round trip** (MR + pipeline + approvals + author for 200 MRs is one query instead of 600 calls);
- you need a **group-wide view** REST doesn't offer or only offers without the fields you need;
- you are **rate-limited** and the call count matters.

Chapter 11 has the full comparison.

### Output shaping with jq

The patterns that recur in every recipe below:

```bash
# Tab-separated table, then align
... | jq -r '.[] | [.iid, .author.username, .title] | @tsv' | column -ts $'\t'

# CSV for a spreadsheet
... | jq -r '["iid","author","title"], (.[] | [.iid, .author.username, .title]) | @csv'

# Filter by date (ISO strings compare lexically)
... | jq --arg since "$(date -u -d '-7 days' +%FT%TZ)" '.[] | select(.created_at >= $since)'

# Count by key
... | jq -r 'group_by(.state) | map({(.[0].state): length}) | add'

# ndjson stream: use -s to slurp when you need the whole set
glab api --paginate --output ndjson ... | jq -s 'length'

# URL-encode a project path or file path
jq -rn --arg p "GROUP/SUB/PROJECT" '$p|@uri'
```

Many glab subcommands take `--jq` directly (`glab mr list -F json --jq '.[].iid'`). **`glab api` has no `--jq`** (still true in 1.119); pipe to `jq`.

### Read-only recipes

Every recipe in this section is a GET. Safe to run with a `read_api` token. `GROUP` and `GROUP/PROJECT` are paths; encode them once:

```bash
G=$(jq -rn --arg p "GROUP" '$p|@uri')
P=$(jq -rn --arg p "GROUP/PROJECT" '$p|@uri')
```

#### 1. Who am I, which server

```bash
glab api user | jq '{username, id, is_admin, state, two_factor_enabled}'
glab api version | jq '{version, revision}'
```

#### 2. Path to numeric ID and back

```bash
glab api "projects/$P" | jq '{id, path_with_namespace, default_branch, visibility, archived}'
glab api projects/PROJECT_ID | jq -r .path_with_namespace
glab api "groups/$G" | jq '{id, full_path}'
```

Numeric IDs survive renames and transfers; paths don't. Store IDs in long-lived config.

#### 3. Open MRs across a group

```bash
glab api -X GET --paginate "groups/$G/merge_requests" \
  -f state=opened -F per_page=100 -f include_subgroups=true \
  | jq -r '.[] | [.references.full, .author.username, (.draft|tostring), .updated_at[0:10], .title] | @tsv' \
  | column -ts $'\t'
```

#### 4. Open MRs across a group, with pipeline and approval state (GraphQL)

```bash
glab api graphql --paginate -f query='
query($endCursor: String) {
  group(fullPath: "GROUP") {
    mergeRequests(state: opened, includeSubgroups: true, first: 50, after: $endCursor) {
      nodes {
        webUrl title draft createdAt
        author { username }
        approved
        headPipeline { status }
        detailedMergeStatus
      }
      pageInfo { hasNextPage endCursor }
    }
  }
}' | jq -r '.data.group.mergeRequests.nodes[] |
  [.createdAt[0:10], .author.username, (.headPipeline.status // "none"), .detailedMergeStatus, .webUrl] | @tsv'
```

> **Version-sensitive.** `approved` and `detailedMergeStatus` on `MergeRequest` exist on current GitLab (19.x verified against gitlab.com). On older self-managed instances, remove fields the schema rejects; the error names them.

#### 5. MRs waiting on my review, instance-wide

```bash
glab api -X GET --paginate merge_requests \
  -f scope=all -f state=opened -f reviewer_username=:username -f draft=false -F per_page=100 \
  | jq -r '.[] | "\(.references.full)\t\(.title)"'
```

Outside a repo, replace `:username` with your username.

#### 6. Pipelines that failed on main this week

```bash
glab api -X GET "projects/$P/pipelines" \
  -f ref=main -f status=failed -f updated_after="$(date -u -d '-7 days' +%FT%TZ)" -F per_page=100 \
  | jq -r '.[] | [.id, .sha[0:8], .source, .updated_at, .web_url] | @tsv'
```

#### 7. Failed jobs in a pipeline, with the reason

```bash
glab api -X GET "projects/$P/pipelines/PIPELINE_ID/jobs" -f 'scope[]=failed' -F per_page=100 \
  | jq -r '.[] | [.id, .stage, .name, .failure_reason, .runner.description // "-"] | @tsv'
```

`failure_reason` distinguishes `script_failure` (your code) from `runner_system_failure`, `stuck_or_timeout_failure` and `api_failure` (infrastructure). Triage on it before reading logs.

Add `-F include_retried=true` to see jobs that failed and were retried.

#### 8. Download job logs

```bash
# One job's log
glab api "projects/$P/jobs/JOB_ID/trace" > job-JOB_ID.log

# Every failed job's log from the latest failed pipeline on main
PID=$(glab api -X GET "projects/$P/pipelines" -f ref=main -f status=failed -F per_page=1 | jq -r '.[0].id')
glab api -X GET "projects/$P/pipelines/$PID/jobs" -f 'scope[]=failed' -F per_page=100 \
  | jq -r '.[] | "\(.id) \(.name)"' \
  | while read -r id name; do
      glab api "projects/$P/jobs/$id/trace" > "job-${id}-${name//\//_}.log"
    done

# Strip ANSI colours and GitLab section markers for grepping
sed -E 's/\x1b\[[0-9;]*[mK]//g; /section_(start|end):/d' job-*.log | grep -n -i -m5 error
```

Traces for child pipelines live on the child pipeline's jobs; get them via `pipelines/PID/bridges` then `downstream_pipeline.id`.

#### 9. Download artifacts by ref and job name

```bash
glab api "projects/$P/jobs/artifacts/main/download?job=build" > artifacts.zip
glab api "projects/$P/jobs/artifacts/main/raw/dist/report.json?job=build" | jq .
```

The second form pulls one file out of the archive without downloading the rest.

#### 10. Protected branches and who can push

```bash
glab api --paginate "projects/$P/protected_branches?per_page=100" \
  | jq -r '.[] | [.name,
      ([.push_access_levels[].access_level_description] | join(",")),
      ([.merge_access_levels[].access_level_description] | join(",")),
      (.allow_force_push|tostring)] | @tsv' \
  | column -ts $'\t'
```

Anything where push is `Maintainers` on `main` and there's no approval rule means a maintainer can bypass review with a plain push. Anything with `allow_force_push` true on a release branch is a finding.

#### 11. Audit project members and access levels

```bash
glab api --paginate "projects/$P/members/all?per_page=100" \
  | jq -r '
      def role: {"5":"minimal","10":"guest","15":"planner","20":"reporter","30":"developer","40":"maintainer","50":"owner"}[.|tostring] // tostring;
      .[] | [.username, (.access_level|role), (.expires_at // "never"), .state] | @tsv' \
  | sort -t$'\t' -k2,2 | column -ts $'\t'
```

`members/all` includes inherited and shared-group members; `members` is direct only. **Audit with `/all`**; that's what actually has access.

#### 12. Group owners and maintainers across every project

```bash
glab api --paginate "groups/$G/projects?include_subgroups=true&archived=false&per_page=100" --output ndjson \
  | jq -r '.id' \
  | while read -r id; do
      glab api --paginate "projects/$id/members/all?per_page=100" --output ndjson \
        | jq -r --arg id "$id" 'select(.access_level >= 40) | [$id, .username, .access_level] | @tsv'
    done | sort -u
```

N+1 calls; fine for dozens of projects. For hundreds, use GraphQL `group { projects { nodes { projectMembers { ... } } } }`.

#### 13. Stale branches

```bash
CUTOFF=$(date -u -d '-90 days' +%FT%TZ)
glab api --paginate "projects/$P/repository/branches?per_page=100" --output ndjson \
  | jq -r --arg c "$CUTOFF" 'select(.protected|not) | select(.default|not)
      | select(.commit.committed_date < $c)
      | [.commit.committed_date[0:10], (.merged|tostring), .commit.author_name, .name] | @tsv' \
  | sort | column -ts $'\t'
```

`merged: true` means the branch's head is reachable from the default branch. Squash-merged branches show `false`; cross-check with recipe 14 before deleting anything.

#### 14. Was this branch's MR merged (catches squash merges)

```bash
glab api -X GET "projects/$P/merge_requests" -f source_branch="BRANCH" -f state=merged -F per_page=1 \
  | jq -r 'if length>0 then "merged in \(.[0].references.full) at \(.[0].merged_at)" else "no merged MR" end'
```

#### 15. Search code

```bash
# In one project
glab api -X GET "projects/$P/search" -f scope=blobs -f search='CI_JOB_TOKEN' -F per_page=100 \
  | jq -r '.[] | "\(.path):\(.startline)"'

# In a group (needs advanced or exact code search on the instance)
glab api -X GET "groups/$G/search" -f scope=blobs -f search='filename:.gitlab-ci.yml image:' \
  | jq -r '.[] | "\(.project_id) \(.path):\(.startline)"'
```

> **Version-sensitive.** Group- and instance-level `scope=blobs` require Advanced Search (Elasticsearch/OpenSearch) or exact code search to be enabled; without it the API returns an error or nothing. Project-level blob search works on every instance.

#### 16. CI variables: names only

```bash
glab api --paginate "projects/$P/variables?per_page=100" \
  | jq -r '.[] | [.key, .variable_type, .environment_scope, "masked=\(.masked)", "protected=\(.protected)", "hidden=\(.hidden // false)"] | @tsv'

glab api --paginate "groups/$G/variables?per_page=100" | jq -r '.[].key'
```

> **Gotcha.** The API response **includes `value`** for anything not hidden. The `jq` projection is what keeps secrets out of your terminal and scrollback; never pipe this endpoint to a file or a log unfiltered. Requires Maintainer.

Unprotected, unmasked variables whose name contains `TOKEN`, `PASSWORD` or `KEY` are the finding:

```bash
glab api --paginate "projects/$P/variables?per_page=100" \
  | jq -r '.[] | select((.key|test("TOKEN|PASS|SECRET|KEY";"i")) and ((.masked|not) or (.protected|not))) | .key'
```

#### 17. Project inventory for a group

```bash
glab api --paginate "groups/$G/projects?include_subgroups=true&per_page=100" --output ndjson \
  | jq -r '[.path_with_namespace, .default_branch, .visibility, (.archived|tostring), .last_activity_at[0:10]] | @tsv' \
  | sort -t$'\t' -k5 | column -ts $'\t'
```

Sorted oldest activity first: the top of the list is your archive candidate list.

#### 18. Access tokens expiring in 30 days (project and group)

```bash
SOON=$(date -u -d '+30 days' +%F)
glab api "projects/$P/access_tokens" \
  | jq -r --arg s "$SOON" '.[] | select(.active and .expires_at != null and .expires_at <= $s) | [.expires_at, .name, (.scopes|join(","))] | @tsv'
glab api "groups/$G/access_tokens" \
  | jq -r --arg s "$SOON" '.[] | select(.active and .expires_at != null and .expires_at <= $s) | [.expires_at, .name] | @tsv'
```

#### 19. Pipeline schedules and their owners

```bash
glab api --paginate "groups/$G/projects?include_subgroups=true&archived=false&per_page=100" --output ndjson \
  | jq -r '[.id, .path_with_namespace] | @tsv' \
  | while IFS=$'\t' read -r id path; do
      glab api "projects/$id/pipeline_schedules" \
        | jq -r --arg p "$path" '.[] | [$p, .id, .cron, .cron_timezone, (.active|tostring), .owner.username] | @tsv'
    done | column -ts $'\t'
```

A schedule runs as its owner. **When that person leaves and is blocked, the schedule silently stops.** This list is the offboarding checklist.

#### 20. Deploy keys and deploy tokens

```bash
glab api "projects/$P/deploy_keys" | jq -r '.[] | [.id, .title, (.can_push|tostring), .created_at[0:10]] | @tsv'
glab api "projects/$P/deploy_tokens" | jq -r '.[] | [.name, (.scopes|join(",")), (.expires_at // "never"), (.revoked|tostring)] | @tsv'
glab api "groups/$G/deploy_tokens" | jq -r '.[] | [.name, (.scopes|join(",")), (.expires_at // "never")] | @tsv'
```

A deploy key with `can_push: true` is a write credential with no user attached and no expiry.

#### 21. Compare two refs

```bash
glab api -X GET "projects/$P/repository/compare" -f from=v2.3.0 -f to=v2.4.0 \
  | jq -r '.commits[] | "\(.short_id) \(.title)"'
glab api -X GET "projects/$P/repository/compare" -f from=v2.3.0 -f to=v2.4.0 \
  | jq -r '.diffs[].new_path' | sort -u
```

#### 22. Read a file at a ref without cloning

```bash
F=$(jq -rn --arg f "charts/app/values.yaml" '$f|@uri')
glab api "projects/$P/repository/files/$F/raw?ref=main"
```

File paths are URL-encoded like project paths (`/` becomes `%2F`).

#### 23. Runners for a project and their status

```bash
glab api "projects/$P/runners" | jq -r '.[] | [.id, .description, .status, (.is_shared|tostring), .runner_type] | @tsv'
```

#### 24. Container registry size check

```bash
glab api "projects/$P/registry/repositories?tags_count=true" \
  | jq -r '.[] | [.path, .tags_count] | @tsv' | sort -k2 -n -r | head
```

#### 25. List snippets (glab snippet has no list in 1.108)

```bash
glab api "projects/$P/snippets" | jq -r '.[] | [.id, .title, .visibility, .web_url] | @tsv'
glab api snippets | jq -r '.[] | [.id, .title, .visibility] | @tsv'      # your personal snippets
glab api "projects/$P/snippets/SNIPPET_ID/raw"
```

### Recipes that write

Everything below changes state. Each is written so that a dry run is the default: the loop prints what it would do unless `APPLY=1` is set. Run them with a token that has `api` scope and the role the endpoint needs.

> **One-way door.** None of the writes below have an undo in the API. Labels can be removed again, but notes, merges, deleted branches and changed protections leave audit events and, for branches, nothing to restore from except someone's clone.

#### W1. Bulk-label issues matching a search

```bash
APPLY=${APPLY:-0}
glab api -X GET --paginate "projects/$P/issues" -f state=opened -f search="OOMKilled" -F per_page=100 --output ndjson \
  | jq -r '.iid' \
  | while read -r iid; do
      if [ "$APPLY" = 1 ]; then
        glab api -X PUT "projects/$P/issues/$iid" -f add_labels="type::bug,area::memory" --silent && echo "labelled #$iid"
      else
        echo "would label #$iid"
      fi
    done
```

`add_labels` and `remove_labels` are additive; `labels` replaces the whole set. Use the additive ones in bulk operations.

#### W2. Retry every failed job in a pipeline

```bash
glab api -X POST "projects/$P/pipelines/PIPELINE_ID/retry" | jq '{id, status}'
```

Retries all failed and canceled jobs in one call. For one job: `glab api -X POST "projects/$P/jobs/JOB_ID/retry"`.

#### W3. Post an idempotent bot comment on an MR

```bash
MARK='<!-- bot:size-check -->'
EXISTS=$(glab api --paginate "projects/$P/merge_requests/MR_IID/notes?per_page=100" --output ndjson \
  | jq -r --arg m "$MARK" 'select(.body|contains($m)) | .id' | head -1)
BODY="$MARK
Image size grew by 42 MB."
if [ -n "$EXISTS" ]; then
  glab api -X PUT "projects/$P/merge_requests/MR_IID/notes/$EXISTS" -f body="$BODY" --silent
else
  glab api -X POST "projects/$P/merge_requests/MR_IID/notes" -f body="$BODY" --silent
fi
```

The hidden HTML marker makes it update-in-place instead of spamming a new comment every pipeline.

#### W4. Protect a branch with explicit levels

```bash
glab api -X POST "projects/$P/protected_branches" \
  -f name='release/*' -F push_access_level=0 -F merge_access_level=40 -F allow_force_push=false \
  | jq '{name, push: [.push_access_levels[].access_level_description], merge: [.merge_access_levels[].access_level_description]}'
```

`0` = no one, `30` = developers, `40` = maintainers. Creating a rule for a name that is already protected returns 409; update with `PATCH projects/:id/protected_branches/:name`.

#### W5. Enforce MR settings on a project

```bash
glab api -X PUT "projects/$P" \
  -F only_allow_merge_if_pipeline_succeeds=true \
  -F only_allow_merge_if_all_discussions_are_resolved=true \
  -F remove_source_branch_after_merge=true \
  -f squash_option=default_on \
  | jq '{only_allow_merge_if_pipeline_succeeds, only_allow_merge_if_all_discussions_are_resolved, squash_option}'
```

#### W6. Delete one remote branch

```bash
B=$(jq -rn --arg b "BRANCH" '$b|@uri')
glab api -X DELETE "projects/$P/repository/branches/$B" --silent && echo deleted
```

Record the head SHA before deleting (`glab api "projects/$P/repository/branches/$B" | jq -r .commit.id`) so it can be restored with `glab api -X POST projects/$P/repository/branches -f branch=BRANCH -f ref=SHA`, as long as the objects haven't been garbage-collected.

#### W7. GraphQL mutation: mark an MR draft

```bash
glab api graphql -f query='
mutation($p: ID!, $iid: String!) {
  mergeRequestSetDraft(input: {projectPath: $p, iid: $iid, draft: true}) {
    mergeRequest { webUrl draft }
    errors
  }
}' -f p=GROUP/PROJECT -f iid=MR_IID | jq '.data.mergeRequestSetDraft'
```

> **Gotcha.** GraphQL has two error channels. A top-level `errors` array (bad field, bad syntax, some permission failures) makes `glab api` exit 1 (verified with an undefined field), even though the server answered HTTP 200. But a mutation's **own** `errors` field (for example "You don't have permission", validation failures) arrives inside `data` with exit 0. Check it explicitly: `jq -e '.data.mergeRequestSetDraft.errors == []'`.

### Debugging a call

```bash
glab api -i 'projects/:id/merge_requests?per_page=1' | sed -n '1,/^\r\?$/p'     # headers only
glab api --silent projects/:id; echo "exit=$?"                                   # 0 on 2xx, 1 on 4xx/5xx
```

`glab api` exits **1 on HTTP errors** and prints both the JSON error body and a `glab: 404 Project Not Found (HTTP 404)` line to stderr (verified). Scripts can rely on `set -e`.

`GLAB_DEBUG_HTTP=1` shows the full request and response, **including your token header**. Use it locally only and never paste its output unredacted.

### Traps

- **Fields switch the method to POST.** Filtering GETs need `-X GET`.
- **Placeholders need a Git repo** and `:branch` is the local branch.
- **`per_page` defaults to 20.** Always `per_page=100` with `--paginate`.
- **`members` is direct only.** Access audits use `members/all`.
- **Variables endpoints return values.** Project with `jq` before anything reaches the terminal.
- **Mutation payload `errors` don't fail the command.** Check them with `jq -e`.
- **`branches[].merged` misses squash merges.** Check the MR instead.
- **Group code search depends on the instance's search backend.**


---


<a id="11-the-rest-api-with-curl"></a>

## 11 · The REST API with curl

*Raw curl is what you reach for where glab isn't installed, and in any tool you write that other people run. It is also where you meet the API's real behaviour: headers carry the pagination and the rate limit, and a 404 usually means "you may not see this".*

### When curl, when glab

**Default: `glab api` for interactive work, curl in CI images and shipped tooling.** curl is on every image; glab isn't. And once a script is shared, you want it to depend on one HTTP client and one token variable, not on someone's glab config.

Every example assumes two variables, set without the token touching your shell history (chapter 12):

```bash
export GITLAB_URL=https://gitlab.example.com
export GITLAB_TOKEN="$(secret-tool lookup service gitlab host gitlab.example.com)"
```

### Authentication headers

| Header | Accepts | Use for |
|---|---|---|
| `PRIVATE-TOKEN: TOKEN` | personal, project and group access tokens | **default** for scripts |
| `Authorization: Bearer TOKEN` | OAuth access tokens, and also personal/project/group access tokens | OAuth apps; tools that only speak Bearer |
| `JOB-TOKEN: $CI_JOB_TOKEN` | the CI/CD job token | inside a running job, for endpoints that accept it |
| `?private_token=TOKEN` in the URL | same as `PRIVATE-TOKEN` | **never**; URLs end up in proxy and server logs |

Deploy tokens do **not** work against the REST API at large. They authenticate Git over HTTPS and the container/package registries (basic auth, username = token name), nothing else.

#### Keep the token out of argv

`curl -H "PRIVATE-TOKEN: $GITLAB_TOKEN"` puts the token in curl's argument list, visible to every local user via `ps` for the life of the process. Feed the header from a file descriptor instead; `printf` is a shell builtin, so it never appears in the process table:

```bash
curl -sS -H @<(printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN") "$GITLAB_URL/api/v4/user" | jq '{username, id}'
```

`-H @file` reads headers from a file (curl 7.55+; Fedora 43 has 8.15). Chapter 12 wraps this in a function.

```bash
# In a CI job
curl -sS -H "JOB-TOKEN: $CI_JOB_TOKEN" "$CI_API_V4_URL/projects/$CI_PROJECT_ID/releases"
```

Inside CI, `$CI_JOB_TOKEN` is masked and short-lived, so passing it with `-H` directly is acceptable.

### Project and file paths

Namespaced paths are URL-encoded: `/` becomes `%2F`. The same applies to file paths and to branch or tag names containing `/`.

```bash
enc() { jq -rn --arg v "$1" '$v|@uri'; }

P=$(enc "platform/charts/ingress")          # platform%2Fcharts%2Fingress
F=$(enc "charts/app/values.yaml")
B=$(enc "release/2.4")

curl -sS -H @<(printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN") \
  "$GITLAB_URL/api/v4/projects/$P/repository/files/$F/raw?ref=$B"
```

`jq @uri` also encodes `.`, spaces, `+` and `#` correctly, which hand-written `sed 's|/|%2F|g'` does not.

**Pick: numeric project IDs in anything long-lived.** Paths change on rename and transfer; IDs never do. Resolve once: `curl ... "$GITLAB_URL/api/v4/projects/$P" | jq .id`.

> **Gotcha.** A reverse proxy in front of GitLab that decodes `%2F` before forwarding (Apache without `AllowEncodedSlashes NoDecode` and `nocanon`, some ingress configurations) turns every namespaced request into a **404**. If `projects/123` works and `projects/group%2Fproject` doesn't, it is the proxy, not your token.

### Pagination

#### Offset pagination

The default for most list endpoints. `page` and `per_page` (default 20, **maximum 100**).

| Header | Meaning |
|---|---|
| `x-page`, `x-per-page` | this page, page size |
| `x-next-page`, `x-prev-page` | next/previous page number, **empty** when none |
| `x-total`, `x-total-pages` | totals, **omitted above 10,000 results** |
| `link` | `rel="next"`, `rel="prev"`, `rel="first"`, `rel="last"` (last omitted above 10,000) |

Verified against gitlab.com on a 66-item MR list with `per_page=2`: `X-Next-Page: 2`, `X-Total: 66`, `X-Total-Pages: 33`, `Link` with next/first/last.

Offset pagination gets slower the deeper you go, and instances can cap the maximum offset.

> **Note.** GitLab has an instance limit on the maximum offset for offset pagination (see *Max offset allowed by the REST API for offset-based pagination* in instance limits). It is configurable on self-managed; if deep pages start returning 405/400, switch the endpoint to keyset.

#### Keyset pagination

Cursor-based, constant cost per page, no totals. Opt in with `pagination=keyset` plus a supported `order_by` and `sort`:

```bash
curl -sS -D - -o /dev/null -H @<(printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN") \
  "$GITLAB_URL/api/v4/projects?pagination=keyset&order_by=id&sort=asc&per_page=100&simple=true" \
  | grep -i '^link:'
# link: <.../projects?id_after=526&...&pagination=keyset&...>; rel="next"
```

Verified: keyset responses carry **only** `Link: rel="next"`, no `x-next-page` and no totals. Supported on the projects, groups and users lists, audit events, jobs, repository tree, registry tags, issues and a few others, each with restricted `order_by` values.

**Default: follow the `Link: rel="next"` URL in every script.** It works for both offset and keyset responses, it carries all your filters forward, and it's the only thing that survives the 10,000-row cutoff.

#### A robust pagination function

Handles both pagination styles, 429 with `Retry-After`, transient 5xx with exponential backoff, and hard errors with the response body. Emits ndjson. `shellcheck` clean; tested unauthenticated against gitlab.com (163 tags across two pages, a keyset projects query, and a 404).

```bash
#!/usr/bin/env bash
# gl.sh: source it, then: gl_get 'projects/ID/merge_requests?state=opened&per_page=100'
# env: GITLAB_URL (https://gitlab.example.com), GITLAB_TOKEN (optional for public data)
set -euo pipefail

gl_curl() {  # gl_curl URL HEADER_FILE BODY_FILE -> prints HTTP status
  local url=$1 hdr=$2 body=$3
  local -a auth=()
  if [[ -n ${GITLAB_TOKEN:-} ]]; then
    auth=(-H @<(printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN"))
  fi
  curl -sS --connect-timeout 10 --max-time 120 \
       "${auth[@]}" -H 'Accept: application/json' \
       -D "$hdr" -o "$body" -w '%{http_code}' "$url"
}

gl_get() {
  local url="${GITLAB_URL%/}/api/v4/${1#/}"
  local hdr body status attempt wait next
  hdr=$(mktemp) body=$(mktemp)
  trap 'rm -f "$hdr" "$body"' RETURN
  while [[ -n $url ]]; do
    attempt=0
    while :; do
      status=$(gl_curl "$url" "$hdr" "$body") || status=000
      case $status in
        2??) break ;;
        429|502|503|504|000)
          (( ++attempt > 6 )) && { echo "gl_get: giving up after $attempt tries ($status) on $url" >&2; return 1; }
          wait=$(awk 'tolower($1)=="retry-after:" {print $2+0}' "$hdr" | tr -d '\r')
          [[ -z $wait || $wait -eq 0 ]] && wait=$(( 2 ** attempt ))
          echo "gl_get: HTTP $status, retry $attempt in ${wait}s" >&2
          sleep "$wait" ;;
        *) echo "gl_get: HTTP $status on $url: $(head -c 300 "$body")" >&2; return 1 ;;
      esac
    done
    jq -c 'if type=="array" then .[] else . end' "$body"
    next=$(tr -d '\r' < "$hdr" | awk 'tolower($1)=="link:"' \
           | grep -o '<[^>]*>; rel="next"' | sed -E 's/^<([^>]*)>.*/\1/' || true)
    url=$next
  done
}
```

Usage:

```bash
source ./gl.sh
gl_get "groups/$(enc GROUP)/merge_requests?state=opened&include_subgroups=true&per_page=100" \
  | jq -r '[.references.full, .author.username, .title] | @tsv'
gl_get "projects?pagination=keyset&order_by=id&sort=asc&per_page=100&archived=false" | jq -r .path_with_namespace
```

Design notes:

- **Headers go to a temp file, body to another.** Parsing `-i` output where headers and body share a stream breaks on `HTTP/2 100 Continue` and proxies that add a second header block.
- **`000` is curl's status for a connection failure**; it is retried like a 503.
- **4xx other than 429 is never retried.** Retrying a 403 just makes the audit log longer.
- **The file sets `set -euo pipefail`.** Source it from scripts, not your interactive shell, or the first failed command closes your terminal.

### Rate limits and 429

Every response carries the throttle state (verified on gitlab.com):

```text
RateLimit-Name: throttle_authenticated_api
RateLimit-Limit: 2000
RateLimit-Observed: 5
RateLimit-Remaining: 1995
RateLimit-Reset: 1790171280          # Unix time
```

A throttled request gets **HTTP 429** plus `Retry-After` (seconds) and `RateLimit-ResetTime` (HTTP date).

| Situation | Behaviour |
|---|---|
| Self-managed default | user and IP rate limits are **disabled** until an admin enables them (Admin > Settings > Network) |
| Self-managed, enabled | defaults 7,200 authenticated API requests per hour per user; 3,600 unauthenticated per hour per IP |
| gitlab.com | enforced; the name and limit are in the headers above |
| Specific endpoints | have their own limits regardless (project export/import, some search, raw file endpoints on some instances) |

Rules for scripts:

1. **Honour `Retry-After`** when present; fall back to exponential backoff.
2. **Watch `RateLimit-Remaining`** in long loops and slow down before you hit zero, not after.
3. **Don't parallelise blindly.** `xargs -P 16` against one instance is how a report script gets a whole CI fleet throttled, because limits are per user and your automation shares the bot user.
4. Prefer **one GraphQL query over N REST calls** when N is large.

### Status codes and what they actually mean

| Code | GitLab's meaning | What it usually is in practice |
|---|---|---|
| `200` / `201` | success; resource returned | |
| `202` | accepted, processing async | exports, some deletes (project deletion is queued) |
| `204` | success, no body | most DELETEs |
| `304` | not modified | you sent `If-None-Match` |
| `400` | required attribute missing | a wrong field name, a JSON array sent as a string, missing `Content-Type` on a JSON body |
| `401` | not authenticated | token missing, expired, revoked, or wrong header name |
| `403` | not allowed | authenticated but role too low, token scope too narrow (`read_api` on a write), or a policy (protected branch, admin-only setting) |
| `404` | resource not found | **also: you can't see it.** Private project, wrong host, unencoded path, proxy decoding `%2F`, unpushed branch |
| `405` | method not allowed | endpoint exists but not with that verb; or feature disabled on the project (e.g. issues off) |
| `409` | conflict | name already exists (branch, tag, protected rule, label) |
| `412` | precondition failed | `If-Match` / SHA check didn't match |
| `422` | unprocessable | validation failed; the body says which field |
| `429` | rate-limited | see above |
| `500` | server error | real bug, or a timeout on a very expensive query; retry once, then report |
| `502` / `503` / `504` | upstream unavailable | deploys, Puma restarts, overloaded Gitaly; retry with backoff |

> **Gotcha.** **GitLab answers 404, not 403, for resources you're not allowed to know exist.** A private project you're not a member of, a confidential issue, a group your token's user can't see: all 404. Before debugging paths, check with the same token that you can see the parent: `curl ... "$GITLAB_URL/api/v4/projects/$P" | jq .id`. Chapter 12 has the full decision tree.

The error body is JSON, and it's worth printing:

```json
{"message":"404 Project Not Found"}
{"message":{"name":["has already been taken"]}}
{"error":"insufficient_scope","error_description":"The request requires higher privileges than provided by the access token.","scope":"api"}
```

`insufficient_scope` names the scope you need. That's the one error message in the API that tells you exactly how to fix it.

### Writes with curl

JSON body, explicit content type:

```bash
curl -sS -X POST \
  -H @<(printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN") \
  -H 'Content-Type: application/json' \
  --data @- \
  "$GITLAB_URL/api/v4/projects/$P/issues" <<'JSON'
{"title": "Rotate group token", "labels": "chore,security", "due_date": "2026-12-01"}
JSON
```

Form-encoded (what most GitLab docs examples use):

```bash
curl -sS -X PUT -H @<(printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN") \
  --data-urlencode "add_labels=type::bug" \
  "$GITLAB_URL/api/v4/projects/$P/issues/42"
```

`--data-urlencode` handles `::`, spaces and `&` in values. Plain `-d` does not.

Idempotent create-or-update:

```bash
# Create a label, or update it if it exists (409 on create)
code=$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H @<(printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN") \
  --data-urlencode "name=team::platform" --data-urlencode "color=#6699cc" \
  "$GITLAB_URL/api/v4/projects/$P/labels")
if [ "$code" = 409 ]; then
  curl -sS -X PUT -H @<(printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN") \
    --data-urlencode "name=team::platform" --data-urlencode "color=#6699cc" \
    "$GITLAB_URL/api/v4/projects/$P/labels" >/dev/null
fi
```

### python-gitlab

For anything beyond a pipeline of `jq` filters (joins across resources, retries, reports with state), move to Python. python-gitlab 8.5 is installed here (`pip install --user python-gitlab`).

```python
#!/usr/bin/env python3
"""List open MRs older than N days in a group, as TSV."""
import os, sys
from datetime import datetime, timedelta, timezone
import gitlab

url = os.environ.get("GITLAB_URL", "https://gitlab.example.com")
token = os.environ.get("GITLAB_TOKEN")          # never hard-code
group_path = sys.argv[1]
days = int(sys.argv[2]) if len(sys.argv) > 2 else 14

gl = gitlab.Gitlab(url, private_token=token, retry_transient_errors=True, per_page=100)
if token:
    gl.auth()                                   # fail fast on a bad token

cutoff = datetime.now(timezone.utc) - timedelta(days=days)
group = gl.groups.get(group_path)
for mr in group.mergerequests.list(state="opened", include_subgroups=True,
                                   created_before=cutoff.isoformat(), iterator=True):
    print(f"{mr.created_at[:10]}\t{mr.references['full']}\t{mr.author['username']}\t{mr.title}")
```

```bash
GITLAB_URL=https://gitlab.example.com python3 stale_mrs.py platform 14 | column -ts $'\t'
```

Verified unauthenticated against the public `gitlab-org/charts` group on gitlab.com.

| Setting | Why |
|---|---|
| `iterator=True` | lazy pagination: fetches pages as you iterate. Without it you get only the first page. `get_all=True` loads everything into memory |
| `retry_transient_errors=True` | retries 429 and 5xx, honouring `Retry-After` |
| `per_page=100` | five times fewer requests than the default |
| `gl.auth()` | validates the token before a long run |
| `ssl_verify="/path/ca.pem"` | private CA; takes a path, not just a boolean |

python-gitlab also reads `~/.python-gitlab.cfg` (`gitlab.Gitlab.from_config("corp")`). Keep the token out of that file with the `helper:` form, pointing at an executable that prints the token: `private_token = helper: /home/USER/bin/gitlab-token`, where the script runs `secret-tool lookup service gitlab host gitlab.example.com`.

> **Version-sensitive.** python-gitlab 3.x replaced `all=True` with `get_all=True` and `as_list=False` with `iterator=True`. Snippets written for 2.x use the old names; on current releases they either warn or return only the first page. Use the new names (verified present in 8.5's signatures).

### GraphQL versus REST

| | REST | GraphQL |
|---|---|---|
| Endpoint | one URL per resource | `POST /api/graphql` |
| Shape of response | fixed, often large | exactly the fields you ask for |
| N related resources | N calls | one query |
| Pagination | `page`/`Link`, or keyset | cursors: `first`, `after`, `pageInfo` |
| Errors | HTTP status codes | HTTP 200 with an `errors` array |
| Coverage | nearly everything, including admin and settings | read-heavy; many mutations, but gaps in settings and admin |
| Discoverability | docs per endpoint | schema introspection, GraphiQL at `/-/graphql-explorer` |
| Query cost | per request | complexity limits per query |

**Default: REST.** Switch to GraphQL when you would otherwise make more than about 50 calls to assemble one report, or when you need nested data (MR with pipeline, approvals and discussions) in bulk.

```bash
curl -sS -H @<(printf 'Authorization: Bearer %s\n' "$GITLAB_TOKEN") \
  -H 'Content-Type: application/json' \
  --data "$(jq -n --arg p "GROUP/PROJECT" '{query: "query($p: ID!){ project(fullPath:$p){ mergeRequests(state: opened, first: 20){ nodes { iid title headPipeline { status } } } } }", variables: {p: $p}}')" \
  "$GITLAB_URL/api/graphql" | jq '.errors // .data'
```

> **Gotcha.** Always check `.errors` on a GraphQL response. The HTTP status is 200 whether the query worked or not, so `curl --fail` does nothing for you.

Use GitLab's built-in GraphQL explorer (`https://gitlab.example.com/-/graphql-explorer`) to build queries against *your* server's schema; field availability varies by version.

### Webhooks basics

A webhook POSTs a JSON event to your URL on push, MR, pipeline, tag, issue, release and other events.

#### Headers you receive

| Header | Use |
|---|---|
| `X-Gitlab-Event` | event type, e.g. `Merge Request Hook`, `Pipeline Hook` |
| `X-Gitlab-Token` | the secret token you configured, **sent in plain text**; compare it constant-time |
| `X-Gitlab-Instance` | sending instance hostname |
| `X-Gitlab-Webhook-UUID` | which webhook sent it |
| `X-Gitlab-Event-UUID` | this event; shared across recursive webhooks |
| `Idempotency-Key` / `webhook-id` | stable across retries: **dedupe on this** |
| `webhook-timestamp`, `webhook-signature` | HMAC-SHA256 signature, only if a signing token is set |

#### Verifying a signature

With a signing token, `webhook-signature` is `v1,BASE64` over `"{webhook-id}.{webhook-timestamp}.{raw body}"`, keyed with the signing token minus its `whsec_` prefix, base64-decoded:

```python
import base64, hmac, hashlib

def valid(signing_token: str, msg_id: str, ts: str, body: bytes, header: str) -> bool:
    key = base64.b64decode(signing_token.removeprefix("whsec_"))
    mac = hmac.new(key, f"{msg_id}.{ts}.".encode() + body, hashlib.sha256).digest()
    expected = "v1," + base64.b64encode(mac).decode()
    return any(hmac.compare_digest(expected, s) for s in header.split())
```

Reject timestamps more than a few minutes old to stop replays.

> **Version-sensitive.** Webhook signing tokens were introduced in **GitLab 19.0** behind the `webhook_signing_token` feature flag (enabled by default) and went GA in **19.1** (docs.gitlab.com/user/project/integrations/webhooks). On older instances, the only authentication is the plain-text `X-Gitlab-Token`, so terminate TLS properly and restrict the receiver by source IP.

#### Receiver rules

- **Return 2xx fast and do the work asynchronously.** Slow responses count as failures.
- After **4 consecutive failures** GitLab disables the hook temporarily (one minute, backing off up to 24 hours); after **40** it disables it permanently until someone re-enables it.
- **Dedupe on `Idempotency-Key`**; retries resend the same event.
- Don't trust the payload for authorisation decisions; call the API back for the current state.

Manage hooks via the API (`GET/POST/PUT/DELETE /projects/:id/hooks`, and `/groups/:id/hooks` on Premium and up). Keep `enable_ssl_verification` on.

### The CI_JOB_TOKEN allowlist

`CI_JOB_TOKEN` authenticates as the user who triggered the job, **but only for a fixed list of endpoints** and only for the lifetime of the job.

What it can reach (per current docs): repository clone, container and package registries, releases and release links, secure files, deployments and environments, repository files, tags, branches, commits, job artifacts download, `GET /job`, read-only MRs and notes, pipeline triggers, and a few more. What it cannot do: most project settings, variables, members, arbitrary MR writes.

#### The inbound allowlist

By default a job token can only access **its own project**. For a job in project A to clone, pull packages from, or trigger project B, **B** must allowlist A (or A's group). This is configured on the *target* project: Settings > CI/CD > Job token permissions.

```text
  project A (pipeline)                    project B (target)
  job ── CI_JOB_TOKEN ──▶  git clone B  ──▶  B's allowlist contains A?  ── no ──▶ 403/404
                                                    │
                                                   yes ──▶ allowed, as the triggering user's role in B
```

Two conditions both have to hold: A is on B's allowlist, **and** the triggering user has access to B.

```bash
# Read B's settings and allowlist (Maintainer on B)
B=$(enc "GROUP/PROJECT_B")
curl -sS -H @<(printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN") "$GITLAB_URL/api/v4/projects/$B/job_token_scope" | jq .
curl -sS -H @<(printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN") "$GITLAB_URL/api/v4/projects/$B/job_token_scope/allowlist" \
  | jq -r '.[].path_with_namespace'
curl -sS -H @<(printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN") "$GITLAB_URL/api/v4/projects/$B/job_token_scope/groups_allowlist" \
  | jq -r '.[].full_path'

# Allow project A (numeric ID) into B
curl -sS -X POST -H @<(printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN") \
  -F target_project_id=PROJECT_A_ID "$GITLAB_URL/api/v4/projects/$B/job_token_scope/allowlist"

# Allow a whole group
curl -sS -X POST -H @<(printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN") \
  -F target_group_id=GROUP_ID "$GITLAB_URL/api/v4/projects/$B/job_token_scope/groups_allowlist"
```

| Endpoint | Does |
|---|---|
| `GET /projects/:id/job_token_scope` | whether inbound restriction is on |
| `PATCH /projects/:id/job_token_scope` (`enabled`) | turn restriction on/off |
| `GET/POST /projects/:id/job_token_scope/allowlist` | list/add projects (`target_project_id`) |
| `DELETE /projects/:id/job_token_scope/allowlist/:target_project_id` | remove |
| `GET/POST /projects/:id/job_token_scope/groups_allowlist` | list/add groups (`target_group_id`) |
| `DELETE /projects/:id/job_token_scope/groups_allowlist/:target_group_id` | remove |

All require Maintainer or Owner on the target project.

**Default: allowlist individual projects, not groups.** A group entry grants every current and future project in it, including forks' pipelines if they land there.

> **Gotcha.** Admins of self-managed instances can enforce the allowlist for all projects. Turning the restriction off on a project may be impossible there; that's policy, not a bug.

> **Version-sensitive.** Group entries in the allowlist need **GitLab 17.0+**. Fine-grained job token permissions (restricting which REST endpoints an allowlisted project's job token may call) arrived as an experiment in 17.10, beta in 18.0, GA in **18.3** (docs.gitlab.com/ci/jobs/fine_grained_permissions). They're opt-in per project and set per allowlist entry. From 19.0, job tokens are JWTs by default.

> **One-way door.** Disabling the inbound restriction (`PATCH ... enabled=false`) lets *any* project's pipelines use their job tokens against this project, limited only by the triggering user's access. Re-enabling it later breaks every cross-project pipeline that grew to depend on it, and there's no record of which ones did.

### Traps

- **Token in the URL** ends up in logs; token with `-H` ends up in `ps`. Use `-H @<(printf ...)`.
- **Unencoded `/` in paths** gives 404. Encode with `jq @uri`.
- **A proxy decoding `%2F`** gives 404 on every namespaced path.
- **404 often means "can't see it"**, not "doesn't exist".
- **`per_page` caps at 100**; totals vanish above 10,000. Follow `Link: rel="next"`.
- **Keyset has no `x-next-page`.** Only `Link`.
- **Rate limits are per user.** Your bot user's loops throttle every pipeline using it.
- **GraphQL always returns 200.** Check `.errors`.
- **Webhook `X-Gitlab-Token` is plain text.** Signed webhooks need 19.0+.
- **Job token cross-project access needs the target's allowlist** and the user's access.


---


<a id="12-scripting-and-troubleshooting"></a>

## 12 · Scripting and troubleshooting

*A GitLab automation script is a loop holding a credential that can delete things. Make the credential hard to leak, make the loop safe to re-run, and make "print what you would do" the default; then most incidents become a log line instead of a restore.*

### Tokens: keep them out of everything

The token leaks through five channels. Close each deliberately.

| Channel | How it leaks | Fix |
|---|---|---|
| Shell history | `export GITLAB_TOKEN=glpat-...` typed at a prompt | read it from a store; never type it |
| Process list | `curl -H "PRIVATE-TOKEN: $T"`, `glab auth login --token $T` | stdin or `-H @<(printf ...)` |
| Files | `.env` committed, config backups, `set -x` logs | `0600` files outside repos, no `xtrace` near secrets |
| Logs | `GLAB_DEBUG_HTTP=1`, `glab auth status --show-token`, `curl -v` | don't, in CI; scrub locally |
| Environment | `GITLAB_TOKEN` exported in `~/.zshrc` for every process you start | export only inside the script that needs it |

#### Pick: GNOME keyring via secret-tool

`secret-tool` is installed on Fedora Workstation and backed by the login keyring, unlocked when you log in. **Default for a workstation.**

```bash
# Store once. It prompts for the secret; nothing goes to history or argv.
secret-tool store --label='GitLab PAT gitlab.example.com' service gitlab host gitlab.example.com

# Use
secret-tool lookup service gitlab host gitlab.example.com | glab auth login --hostname gitlab.example.com --stdin --use-keyring

# Remove after rotation
secret-tool clear service gitlab host gitlab.example.com
```

A helper every script sources:

```bash
# ~/.local/lib/gitlab-env.sh
gl_token() {
  local host=${1:-${GITLAB_HOST:?}}
  secret-tool lookup service gitlab host "$host" \
    || { echo "no token for $host in keyring" >&2; return 1; }
}
gl_hdr() { printf 'PRIVATE-TOKEN: %s\n' "$(gl_token "$@")"; }

# usage, no token in argv:
# curl -sS -H @<(gl_hdr) "https://$GITLAB_HOST/api/v4/user"
```

**Alternative: `pass`** (GPG-encrypted files, Git-syncable) wins when the same secrets must follow you across machines or be shared with a team via GPG recipients. Not installed here; `sudo dnf install pass`, then `pass show gitlab/gitlab.example.com` in place of `secret-tool lookup`.

**Headless box (no keyring session): an env file.**

```bash
install -d -m 0700 ~/.config/gitlab
install -m 0600 /dev/null ~/.config/gitlab/env
${EDITOR:-vi} ~/.config/gitlab/env        # GITLAB_TOKEN=... ; edit in the editor, not with echo

# In the script, scoped to this process only
set -a; . ~/.config/gitlab/env; set +a
```

#### Typing a token without history

When you must paste one (first-time setup, a token handed to you):

```bash
read -rs -p 'token: ' T; echo
printf '%s' "$T" | secret-tool store --label='GitLab PAT' service gitlab host gitlab.example.com
unset T
```

zsh also skips history for lines starting with a space if `setopt HIST_IGNORE_SPACE` is set. Useful, but a safety net, not the plan.

> **Gotcha.** `set -x` in a script prints every expanded command, **including `$GITLAB_TOKEN` inside any curl or glab arguments**. Wrap tracing around the part you're debugging, or use `-H @<(...)` everywhere so there's nothing to expand.

> **One-way door.** A token that has appeared in a CI log, a pasted terminal, a Slack message or a public repository is compromised. Masking after the fact doesn't un-publish it. Revoke first (`glab token revoke` or the UI), then investigate. Rotation is cheap; an attacker with `api` scope for a week isn't.

### Script skeleton

Every automation script in this chapter follows the same shape:

```bash
#!/usr/bin/env bash
set -euo pipefail                       # fail on errors, unset vars, and inside pipes
: "${GITLAB_HOST:?set GITLAB_HOST}"     # explicit host: scripts never rely on cwd
export GLAB_NO_PROMPT=1                 # a prompt in a cron job hangs forever

APPLY=0; [[ ${1:-} == --apply ]] && APPLY=1

run() {                                 # every write goes through here
  if (( APPLY )); then "$@"; else printf 'DRY-RUN:'; printf ' %q' "$@"; echo; fi
}

run glab api --hostname "$GITLAB_HOST" -X DELETE "projects/$PID/repository/branches/$B" --silent
```

#### The rules

1. **Dry run is the default.** Writes need `--apply`. The dry-run output is the same list the apply will act on, so a reviewer can read it.
2. **Idempotent.** Running it twice produces the same end state and no errors: check before create (409 is "already done", not failure), use additive operations (`add_labels`, not `labels`), compare desired against current and act only on the difference.
3. **Explicit host and project.** Never depend on the current directory; `glab api` from `/` goes to the default host.
4. **Confirmation proportional to blast radius.** A single project: `--apply` is enough. A group: make the operator type the group path.
5. **Write a restore log before destroying.** Branch name and SHA, variable name and scope, project and settings: whatever it takes to undo.
6. **Read-only token for read-only scripts.** A `read_api` token turns a bug in a report into a failed report rather than an incident.
7. **Bounded concurrency.** Sequential is usually fast enough. If not, `xargs -P 4`, never more, and watch `RateLimit-Remaining`.

#### Confirmation that means something

```bash
confirm_typed() {  # confirm_typed EXPECTED "message"
  local answer
  read -r -p "$2 Type '$1' to continue: " answer
  [[ $answer == "$1" ]] || { echo "aborted" >&2; exit 1; }
}
confirm_typed "$GROUP" "About to delete $n branches across $GROUP."
```

`[y/N]` prompts get answered by reflex. Typing the target's name doesn't.

### Script: weekly MR report

Read-only. Markdown to stdout: merged MRs with time-to-merge, merges per author, stale open MRs, and ready MRs nobody was asked to review. Verified against the public `gitlab-org/charts` group on gitlab.com.

```bash
#!/usr/bin/env bash
# mr-weekly-report.sh GROUP [DAYS]  -> Markdown report on stdout. Read-only.
set -euo pipefail
: "${GITLAB_HOST:?set GITLAB_HOST, e.g. gitlab.example.com}"
GROUP=${1:?usage: mr-weekly-report.sh GROUP [DAYS]}
DAYS=${2:-7}
G=$(jq -rn --arg v "$GROUP" '$v|@uri')
SINCE=$(date -u -d "-${DAYS} days" +%FT%TZ)
STALE=$(date -u -d "-14 days" +%FT%TZ)

api() { glab api --hostname "$GITLAB_HOST" -X GET --paginate --output ndjson "$@"; }

merged=$(api "groups/$G/merge_requests" -f state=merged -f include_subgroups=true \
           -f updated_after="$SINCE" -F per_page=100 \
         | jq -c --arg s "$SINCE" 'select(.merged_at >= $s)')
opened=$(api "groups/$G/merge_requests" -f state=opened -f include_subgroups=true -F per_page=100)

printf '# MR report: %s, last %s days (to %s)\n\n' "$GROUP" "$DAYS" "$(date +%F)"

printf '## Merged: %s\n\n' "$(jq -s length <<<"$merged")"
printf '| Project | MR | Author | Days open |\n|---|---|---|---|\n'
jq -r '[(.references.full|split("!")[0]), "[!\(.iid)](\(.web_url)) \(.title|gsub("\\|";"/"))", .author.username,
        (((.merged_at|sub("\\.[0-9]+";"")|fromdateiso8601) - (.created_at|sub("\\.[0-9]+";"")|fromdateiso8601)) / 86400 | floor)]
       | "| " + (map(tostring)|join(" | ")) + " |"' <<<"$merged"

printf '\n## Merged per author\n\n'
jq -rs 'group_by(.author.username) | map({a: .[0].author.username, n: length}) | sort_by(-.n)[] | "- \(.a): \(.n)"' <<<"$merged"

printf '\n## Open and not updated for 14 days\n\n'
jq -r --arg st "$STALE" 'select(.updated_at < $st)
       | "- [\(.references.full)](\(.web_url)) \(.title) (\(.author.username), updated \(.updated_at[0:10]))"' <<<"$opened"

printf '\n## Open, not draft, no reviewer\n\n'
jq -r 'select((.draft|not) and ((.reviewers|length)==0)) | "- [\(.references.full)](\(.web_url)) \(.title)"' <<<"$opened"
```

Run it from a systemd user timer and post the output as an issue or snippet:

```bash
GITLAB_HOST=gitlab.example.com ./mr-weekly-report.sh platform 7 > report.md
glab snippet create -R platform/reports -t "MR report $(date +%F)" -f report.md < report.md
```

```ini
# ~/.config/systemd/user/mr-report.timer
[Timer]
OnCalendar=Mon *-*-* 08:00:00 America/Toronto
Persistent=true

[Install]
WantedBy=timers.target
```

### Script: prune merged branches across a group

Deletes remote branches that are not default, not protected, older than `MIN_AGE_DAYS` (default 30), and whose MR merged with none still open. Checking the MR, not `git branch --merged`, is what catches squash merges. Dry run unless `--apply`; always writes `prune-TIMESTAMP.tsv` with project, branch, SHA and date.

```bash
#!/usr/bin/env bash
# prune-remote-branches.sh GROUP [--apply]
# Deletes remote branches across a group that are: not default, not protected,
# older than MIN_AGE_DAYS, and whose MR was merged (catches squash merges).
# Dry run unless --apply. Writes a restore log of branch -> SHA.
set -euo pipefail
: "${GITLAB_HOST:?set GITLAB_HOST}"
GROUP=${1:?usage: prune-remote-branches.sh GROUP [--apply]}
APPLY=0; [[ ${2:-} == --apply ]] && APPLY=1
MIN_AGE_DAYS=${MIN_AGE_DAYS:-30}
CUTOFF=$(date -u -d "-${MIN_AGE_DAYS} days" +%FT%TZ)
LOG="prune-$(date +%Y%m%dT%H%M%S).tsv"
G=$(jq -rn --arg v "$GROUP" '$v|@uri')
enc() { jq -rn --arg v "$1" '$v|@uri'; }
api() { glab api --hostname "$GITLAB_HOST" "$@"; }

candidates=0
while IFS=$'\t' read -r pid path; do
  while IFS=$'\t' read -r branch sha date; do
    merged=$(api -X GET "projects/$pid/merge_requests" -f source_branch="$branch" \
               -f state=merged -F per_page=1 | jq 'length')
    open=$(api -X GET "projects/$pid/merge_requests" -f source_branch="$branch" \
               -f state=opened -F per_page=1 | jq 'length')
    [[ $merged -gt 0 && $open -eq 0 ]] || continue
    candidates=$((candidates + 1))
    printf '%s\t%s\t%s\t%s\n' "$path" "$branch" "$sha" "$date" | tee -a "$LOG"
    if (( APPLY )); then
      api -X DELETE "projects/$pid/repository/branches/$(enc "$branch")" --silent
    fi
  done < <(api --paginate --output ndjson "projects/$pid/repository/branches?per_page=100" \
           | jq -r --arg c "$CUTOFF" 'select((.protected|not) and (.default|not) and .commit.committed_date < $c)
                                      | [.name, .commit.id, .commit.committed_date[0:10]] | @tsv')
done < <(api --paginate --output ndjson "groups/$G/projects?include_subgroups=true&archived=false&per_page=100" \
         | jq -r '[.id, .path_with_namespace] | @tsv')

if (( APPLY )); then
  echo "deleted $candidates branches; restore data in $LOG" >&2
else
  echo "DRY RUN: $candidates branches would be deleted (listed in $LOG). Re-run with --apply." >&2
fi
```

Restoring a branch from the log:

```bash
glab api --hostname "$GITLAB_HOST" -X POST "projects/$(jq -rn --arg v GROUP/PROJECT '$v|@uri')/repository/branches" \
  -f branch=BRANCH -f ref=SHA
```

> **One-way door.** The SHA in the log restores the branch only while GitLab still has the objects. Merged branches are safe (the commits live on in the target). An unmerged branch deleted and then garbage-collected is gone unless someone has a clone. That's why the script requires a merged MR.

> **Note.** This makes two MR lookups per candidate branch. For a group with thousands of branches, expect a long run and watch rate limits; the age filter runs first to keep the candidate set small.

### Script: mirror and back up a group

Mirror-clones every non-archived project over SSH, updates existing mirrors on re-run, and writes one verified `git bundle` per repository per day. Idempotent: re-running just fetches.

```bash
#!/usr/bin/env bash
# backup-group.sh GROUP DEST_DIR
# Mirror-clones every non-archived project in a group (and subgroups) over SSH,
# updates existing mirrors, and writes a verified git bundle per repo. Idempotent.
set -euo pipefail
: "${GITLAB_HOST:?set GITLAB_HOST}"
GROUP=${1:?usage: backup-group.sh GROUP DEST_DIR}
DEST=${2:?usage: backup-group.sh GROUP DEST_DIR}
G=$(jq -rn --arg v "$GROUP" '$v|@uri')
STAMP=$(date +%F)
mkdir -p "$DEST/mirrors" "$DEST/bundles/$STAMP"
fail=0

while IFS=$'\t' read -r path url; do
  mirror="$DEST/mirrors/$path.git"
  if [[ -d $mirror ]]; then
    git -C "$mirror" remote set-url origin "$url"
    git -C "$mirror" fetch --prune --quiet origin || { echo "FAIL fetch $path" >&2; fail=1; continue; }
  else
    mkdir -p "$(dirname "$mirror")"
    git clone --mirror --quiet "$url" "$mirror" || { echo "FAIL clone $path" >&2; fail=1; continue; }
  fi
  # empty repos have no refs; bundle would fail
  if [[ -n $(git -C "$mirror" for-each-ref --count=1) ]]; then
    bundle="$DEST/bundles/$STAMP/${path//\//__}.bundle"
    git -C "$mirror" bundle create --quiet "$bundle" --all
    git -C "$mirror" bundle verify --quiet "$bundle" || { echo "FAIL verify $path" >&2; fail=1; }
  fi
  echo "ok $path"
done < <(glab api --hostname "$GITLAB_HOST" --paginate --output ndjson \
           "groups/$G/projects?include_subgroups=true&archived=false&per_page=100" \
         | jq -r '[.path_with_namespace, .ssh_url_to_repo] | @tsv')

exit "$fail"
```

What this does **not** back up: issues, MRs, wiki (a separate `.wiki.git` repo), CI variables, LFS objects, container images, packages, settings. For those, use project export (`POST /projects/:id/export`, then download) or instance-level GitLab backups. A Git mirror is a code backup, not a GitLab backup.

**Pick: SSH URLs with a deploy key or your SSH key** over HTTPS with a token in the URL. HTTPS clone URLs with embedded tokens end up in `.git/config` of every mirror.

For continuous off-site sync of a few critical repos, server-side push mirroring (`glab repo mirror PROJECT --direction push --url ssh://...`) beats a cron job: GitLab pushes on every change.

### Script: bulk update CI variables with confirmation

Declarative: a TSV spec lists keys, scopes and flags; values come from the keyring at apply time and flow through stdin, never argv, never a file. The plan shows names and flags only.

```text
# vars.tsv: KEY   SCOPE   FLAGS   SECRET_REF
REGISTRY_TOKEN	*	masked,protected,raw	item registry-token
KUBECONFIG_PROD	production	protected,raw	item kubeconfig-prod
SENTRY_DSN	*	masked	item sentry-dsn
```

```bash
#!/usr/bin/env bash
# sync-ci-vars.sh PROJECT SPEC.tsv [--apply]
# SPEC.tsv columns: KEY <TAB> SCOPE <TAB> FLAGS <TAB> SECRET_REF
#   FLAGS: comma list of masked,protected,raw (or -)
#   SECRET_REF: secret-tool attribute pair "item NAME"; the value is looked up, never stored in the spec
# Shows a plan (create / update / unchanged-flags), asks for confirmation, then applies.
set -euo pipefail
: "${GITLAB_HOST:?set GITLAB_HOST}"
PROJECT=${1:?usage: sync-ci-vars.sh PROJECT SPEC.tsv [--apply]}
SPEC=${2:?usage: sync-ci-vars.sh PROJECT SPEC.tsv [--apply]}
APPLY=0; [[ ${3:-} == --apply ]] && APPLY=1
P=$(jq -rn --arg v "$PROJECT" '$v|@uri')

# Current state: names, scopes and flags only (values are dropped here)
current=$(glab api --hostname "$GITLAB_HOST" --paginate "projects/$P/variables?per_page=100" \
          | jq -c 'map({key, scope: .environment_scope, masked, protected, raw})')

plan=()
while IFS=$'\t' read -r key scope flags ref; do
  [[ -z $key || $key == \#* ]] && continue
  exists=$(jq --arg k "$key" --arg s "$scope" 'any(.[]; .key==$k and .scope==$s)' <<<"$current")
  action=create; [[ $exists == true ]] && action=update
  plan+=("$action"$'\t'"$key"$'\t'"$scope"$'\t'"$flags"$'\t'"$ref")
done < "$SPEC"

printf '%-7s %-30s %-12s %s\n' ACTION KEY SCOPE FLAGS
for line in "${plan[@]}"; do
  IFS=$'\t' read -r action key scope flags _ <<<"$line"
  printf '%-7s %-30s %-12s %s\n' "$action" "$key" "$scope" "$flags"
done

(( APPLY )) || { echo "DRY RUN. Re-run with --apply to change ${#plan[@]} variables." >&2; exit 0; }

read -r -p "Type the project path to confirm changes to ${#plan[@]} variables: " answer
[[ $answer == "$PROJECT" ]] || { echo "aborted" >&2; exit 1; }

for line in "${plan[@]}"; do
  IFS=$'\t' read -r action key scope flags ref <<<"$line"
  args=(--repo "$PROJECT" --scope "$scope")
  [[ $flags == *masked* ]]    && args+=(--masked)
  [[ $flags == *protected* ]] && args+=(--protected)
  [[ $flags == *raw* ]]       && args+=(--raw)
  read -r attr name <<<"$ref"
  sub="set"; [[ $action == update ]] && sub="update"   # glab calls "create" set
  # value flows secret-tool -> stdin -> glab; never argv, never a file
  if ! secret-tool lookup "$attr" "$name" | GITLAB_HOST=$GITLAB_HOST glab variable "$sub" "$key" "${args[@]}" >/dev/null; then
    echo "FAIL $action $key ($scope)" >&2; exit 1
  fi
  echo "$action $key ($scope) done"
done
```

```bash
GITLAB_HOST=gitlab.example.com ./sync-ci-vars.sh platform/api vars.tsv            # plan only
GITLAB_HOST=gitlab.example.com ./sync-ci-vars.sh platform/api vars.tsv --apply    # plan, confirm, apply
```

Flags in the spec are authoritative: every apply passes them explicitly, so a variable someone unmasked in the UI gets re-masked.

> **Gotcha.** A value must meet GitLab's masking rules (minimum length, allowed characters, single line) to be masked; otherwise the API rejects it with 400. Kubeconfigs and PEM files can't be masked; make them `protected` file-type variables instead (`glab variable set KEY --type file`).

> **One-way door.** Overwriting a variable destroys the old value; GitLab keeps no history of variable values. If the old value might be needed (rollback of a rotated credential), keep it in the secret store under a dated name before applying.

### Troubleshooting

#### 401, 403, 404: what they actually mean

| Code | Meaning | First check |
|---|---|---|
| **401** | not authenticated | Which token is used? `glab auth status` (look for "Token is from environment variable"). Expired? `glab token list --user @me`. Wrong header? `PRIVATE-TOKEN`, not `Private-Token: Bearer`. Wrong host? |
| **403** | authenticated, not allowed | Role too low for the action; token scope too narrow (`read_api` doing a write, body says `insufficient_scope`); protected branch or tag rule; admin-only setting; IP allowlist on the group |
| **404** | not found, **or not visible to you** | Can you see the parent? Path encoded? Right host? Branch pushed? Feature enabled on the project? |

#### The 404 that is really a permission problem

GitLab returns 404 rather than 403 for anything you're not allowed to know exists, so it can't be used to enumerate private projects. Work down this list; stop at the first failure:

```bash
H=gitlab.example.com; P=$(jq -rn --arg v "GROUP/PROJECT" '$v|@uri')

glab api --hostname "$H" user | jq -r .username          # 1. am I who I think I am, on the right host?
glab api --hostname "$H" "groups/$(jq -rn --arg v GROUP '$v|@uri')" | jq -r .full_path   # 2. can I see the group?
glab api --hostname "$H" "projects/$P" | jq '{id, visibility, archived}'                 # 3. can I see the project?
glab api --hostname "$H" "projects/$P/members/all/$(glab api --hostname "$H" user | jq .id)" \
  | jq '{access_level}'                                                                  # 4. what's my role?
glab api --hostname "$H" "projects/$P" | jq '{issues_access_level, merge_requests_access_level, builds_access_level}'  # 5. feature on?
```

| Symptom | Real cause |
|---|---|
| 404 on project, 200 on the numeric ID | path not encoded, or a proxy decoding `%2F` |
| 404 on project for the bot, 200 for you | bot isn't a member; group/project access tokens only see their own group/project |
| 404 on `repository/branches/feature/x` | `/` in branch not encoded, or branch never pushed |
| 404 on `/variables` | you are Developer; variables need Maintainer, and the API hides them as 404 |
| 404 on `/issues` | issues disabled on the project, or the issue is confidential |
| 404 from `CI_JOB_TOKEN` on another project | target hasn't allowlisted the source project (chapter 11) |
| 404 on everything, glab only | glab resolved a different host (out of repo, `GITLAB_HOST`, wrong remote) |

#### Self-signed and private CAs

**Pick: add the CA to the system trust store once.** curl, git, glab, podman and Fedora's packaged Python `requests` then just work, and you never touch a verify flag. Fedora's packaged `certifi` already points at the system bundle (verified: `certifi.where()` returns `/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem`). The exception is a virtualenv with pip's own `certifi`, which ships a private bundle: point it at the system one with `REQUESTS_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt`.

```bash
# System config change: run it yourself, it needs root
sudo cp corp-root-ca.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust
trust list --filter=ca-anchors | grep -i -A2 'corp'
curl -sS -o /dev/null -w '%{http_code}\n' https://gitlab.example.com/api/v4/version
```

When you can't change the system store, configure each client per host:

| Client | Per-host CA setting |
|---|---|
| glab | `glab config set ca_cert /path/corp-ca.pem --host gitlab.example.com` (or `GLAB_CA_CERT`) |
| git | `git config --global http.https://gitlab.example.com/.sslCAInfo /path/corp-ca.pem` |
| curl | `--cacert /path/corp-ca.pem` or `CURL_CA_BUNDLE` |
| python-gitlab | `gitlab.Gitlab(url, ssl_verify="/path/corp-ca.pem")` |
| requests (generic) | `REQUESTS_CA_BUNDLE=/path/corp-ca.pem` |
| podman/docker login to the registry | `/etc/containers/certs.d/REGISTRY_HOST/ca.crt` / `/etc/docker/certs.d/REGISTRY_HOST/ca.crt` |

Mutual TLS: glab takes `client_cert` and `client_key` per host (or `GLAB_CLIENT_CERT`/`GLAB_CLIENT_KEY`); git takes `http.<url>.sslCert` and `http.<url>.sslKey`.

> **Gotcha.** `glab config set skip_tls_verify true --host gitlab.example.com` makes the glab error go away and leaves you with **an API client that will hand your token to anyone who can intercept the connection**. It also fixes only glab: `git clone https://...`, the credential helper, `docker login` and your curl scripts still fail, so people then reach for `GIT_SSL_NO_VERIFY=1` and `curl -k`, and the insecure setting spreads. Configure the CA instead; it takes the same two minutes. If you did set it, undo it: `glab config set skip_tls_verify false --host gitlab.example.com`, and check `GLAB_SKIP_TLS_VERIFY` isn't exported anywhere.

Diagnose which certificate the server actually presents:

```bash
openssl s_client -connect gitlab.example.com:443 -servername gitlab.example.com -showcerts </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

A missing intermediate on the server is the usual "works in the browser, fails in curl" cause: browsers fetch intermediates themselves, CLI clients don't. Fix the server's chain, don't add the intermediate to your client.

#### Proxies

```bash
export HTTPS_PROXY=http://proxy.corp:3128
export NO_PROXY=localhost,127.0.0.1,.corp.example.com,gitlab.example.com
```

| Client | Honours | Per-host override |
|---|---|---|
| curl | `HTTPS_PROXY`/`https_proxy`, `NO_PROXY` | `--proxy`, `--noproxy` |
| glab | environment proxies | `proxy` per host (`glab config set proxy http://proxy.corp:3128 --host gitlab.example.com`) or `GLAB_PROXY` |
| git (HTTPS) | environment proxies, `http.proxy` | `git config --global http.https://gitlab.example.com/.proxy ""` to bypass for one host |
| git (SSH) | **none** | `ProxyCommand` / `ProxyJump` in `~/.ssh/config` |
| python-gitlab | environment proxies (via requests) | pass a custom `session` |

> **Gotcha.** `NO_PROXY` matching is by suffix and differs between tools: curl and Go (glab) accept `.example.com` and `example.com`; some tools ignore CIDR ranges. When an internal GitLab works in the browser but times out from the CLI, it is almost always `HTTPS_PROXY` set without the GitLab host in `NO_PROXY`: the request goes to the corporate proxy, which can't reach the internal host.

> **Gotcha.** A TLS-intercepting corporate proxy re-signs traffic with its own CA. That is a CA problem, not a proxy problem: add the proxy's CA to the trust store as above.

#### Quick diagnostic sequence

```bash
glab version; glab auth status --all                      # which glab, which hosts, which token source
env | grep -E '^(GITLAB|GLAB|HTTPS?_PROXY|NO_PROXY)' | sed -E 's/(TOKEN=).*/\1<redacted>/'
glab api --hostname gitlab.example.com version            # server reachable and token accepted
curl -sS -o /dev/null -w '%{http_code} %{ssl_verify_result}\n' https://gitlab.example.com/api/v4/version
git ls-remote git@gitlab.example.com:GROUP/PROJECT.git HEAD   # SSH path, separate from API
grep -n 'glab' ~/.gitconfig                               # credential helper path still valid?
```

`ssl_verify_result` of `0` means curl trusted the chain.

### Checklist

- Token in the keyring (or `pass`), read via stdin or `-H @<(...)`, never typed, never in argv.
- `GITLAB_TOKEN` exported only inside scripts, never in `~/.zshrc`.
- Separate `read_api` token for reports; group access token, not a PAT, for shared automation.
- Every script: `set -euo pipefail`, explicit `GITLAB_HOST`, `GLAB_NO_PROMPT=1`, dry run by default.
- Destructive scripts write a restore log before acting and ask for a typed confirmation.
- Writes are idempotent: 409 is success, additive operations, desired-versus-current diffs.
- Private CA in the system trust store; `skip_tls_verify` never set.
- `NO_PROXY` includes your GitLab host.
- 404 debugged top-down: host, identity, group, project, role, feature.


---
