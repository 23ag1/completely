---
name: completely:sync
description: MIGRATION (one-time). Import existing markdown task state (Ralph IMPLEMENTATION_PLAN.md, checkbox task lists) into Beads, idempotently. Use when adopting completely in a repo that has markdown plans, or after an upstream update, to keep Beads the single source of truth. Backed by `cmpl sync`.
version: 0.2.0
user-invocable: true
argument-hint: "[dir] [extra-markdown-files...]"
---
Run the idempotent markdown → Beads migration so the task queue lives in one place.

1. Ensure the repo has Beads — if `.beads/` is absent, run `bd init` first.
2. From the repo root run `cmpl sync` (backend: `<plugin>/scripts/sync.sh`).
3. It upserts each markdown checkbox task into Beads keyed by a stable `source_ref`
   (label `src-<hash>` + `metadata.source_ref`), so re-running NEVER duplicates and
   reconciles status (`- [x]` → closed, `- [ ]` → open). Safe to run after upstream updates.
4. Report created/reconciled counts. Then prefer `bd ready` over the markdown checklist.

Scope: Ralph-style `IMPLEMENTATION_PLAN.md` + any files you pass. GSD `*-PLAN.md`
(requirements/must_haves/waves) is handled by the GSD→Beads emitter, not this skill.
