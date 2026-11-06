---
name: technical-plan
description: Generate a structured multi-subtask implementation plan with a dependency graph and wave-based execution order, sized so each subtask is one reviewable PR/MR. The output is a contract another step (ticket creation, an orchestrator, a team) can consume. Use when a feature or change is too large for one PR and needs decomposing before any code is written, or when asked to "plan this", "break this down", "decompose this into tickets".
argument-hint: "<the feature, change or problem to plan>"
---

# Technical Plan

Produce an implementation plan that decomposes work into subtasks, states their dependencies, and
computes the waves they can run in. **The output is an input** — to ticket creation, to an
orchestrator, to a team splitting the work — so the structure below is a contract, not a preference.

## Input

`$ARGUMENTS` — the feature, change or problem to plan. If empty, ask what to plan and stop.

## Phase 1 — Parse requirements

Extract, and **state explicitly what you inferred rather than read**:

- The outcome, in the user's language, not the component's.
- Hard constraints (an air gap, a customer-operated cluster, a compliance regime, a freeze date).
- What is explicitly out of scope.
- Anything you cannot determine — carry it into the plan as an open question with an owner rather
  than guessing.

## Phase 2 — Explore the codebase

Read the repo's `CLAUDE.md` and `.claude/rules/`. Explore with LSP or a code index for exact
symbols, grep/Read otherwise — and grep **first** for infra, SQL, YAML, Helm, Terraform and docs.

Name the actual files each subtask will touch. **A plan that does not name files is not a plan** — it
cannot be sized, dependency-ordered, or reviewed.

Check the governing record before designing anything: ADRs, design docs, a technology-adoption list.
**A decision may already be settled.**

## Phase 3 — Design subtasks

Size each subtask so it is **one coherent, independently reviewable PR**.

A subtask is too big if its description needs the word "and" between two unrelated changes. It is
too small if it cannot be merged on its own without breaking the branch.

For each subtask state: title, why it exists, the files it touches, what "done" means as a testable
assertion, and its blockers.

**Sequence additive-before-destructive.** Add the new path, move the consumers, *then* delete the old
one — and the delete is its own subtask, last.

**A migration subtask that creates a resource includes the grant** for whatever role the service
runs as; without it the deploy is clean and the runtime fails.

## Phase 4 — Dependency graph and waves

```
DEPENDENCY_GRAPH = {
  "S1": { blocked_by: [],           blocks: ["S2", "S3"] },
  "S2": { blocked_by: ["S1"],       blocks: ["S4"] },
  "S3": { blocked_by: ["S1"],       blocks: ["S4"] },
  "S4": { blocked_by: ["S2","S3"],  blocks: [] },
}
```

Wave 1 is every subtask with no blockers; wave N+1 is every subtask whose blockers are all in waves
≤ N. Identify the **critical path** — the longest chain — because that is the real duration whatever
the parallelism.

**A dependency is real only if the later subtask cannot compile, run or be reviewed without the
earlier one.** "It would be tidier in this order" is not a dependency; it serializes work for nothing.

## Phase 5 — Write the plan

```markdown
# <Feature Title>

**Settled by:** <ADR / design doc> — or "no existing record"

## Context
<the outcome in the user's language; the constraint that shapes it>

## Out of scope
<what this deliberately does not do>

## Dependency Graph
S1 ──┬──▶ S2 ──┬──▶ S4
     └──▶ S3 ──┘

## Subtasks

### Subtask 1: <title>
- **Why:** <one sentence>
- **Files:** <real paths>
- **Done when:** <a testable assertion>
- **Blocked by:** none
- **Blocks:** S2, S3

## Execution Plan
- **Wave 1**: S1
- **Wave 2** (parallel): S2, S3
- **Wave 3**: S4
- **Critical path**: S1 → S2 → S4 (3 waves)

## Verification
<the command that proves the whole feature works, runnable locally>

## Open questions
- <question> — owner: <who> (do not guess these away)
```

## Self-check before output

Do not emit the plan until all of these hold:

- [ ] Every subtask names real files that exist (or states it creates them).
- [ ] Every dependency is a real blocker, not a preference.
- [ ] No subtask needs "and" between two unrelated changes.
- [ ] Destructive subtasks come last and are separate.
- [ ] Any migration creating a resource includes its grant.
- [ ] The verification command is one someone else can run.
- [ ] Open questions have owners and are not silently resolved.
- [ ] The governing record was checked and cited, or its absence stated.
