---
name: completely:auto
description: Run completely AUTONOMOUSLY — loop the FULL task engine over the Beads queue, a fresh `claude -p` per task, until the queue is empty. Same complete recipe as /completely:control. Backed by `cmpl auto`. Run it in the FOREGROUND (blocking) — nested workers only run while the launching session is active; it is idempotent/resumable.
version: 0.7.0
user-invocable: true
argument-hint: "[--max N]"
---
Run `cmpl auto --max N` from the repo root to grind the Beads queue with the full task engine
(`core/task-engine.md`): each task gets a fresh `claude -p` running the COMPLETE recipe (understand
→ plan-check → parallel subagents → TDD → checks → reviewers → verifier → evaluator → debug-on-fail
→ **commit → close**), then the next, until `bd ready` is empty.

CRITICAL — how to run it so it actually progresses:
- **Run it in the FOREGROUND. Do NOT background it.** The nested `claude -p` workers only make
  progress while the launching session is active. If you background it (`&` / run_in_background)
  and yield your turn, the workers PAUSE. Block on the single `cmpl auto` call until it exits.
- **It is bounded** by the foreground/session limits. A long run can be cut off (session limit).
  Because the engine **commits BEFORE closing a bead**, completed tasks are durable (committed work
  + closed beads) and never leave a closed bead with uncommitted code.
- **Resuming after an interruption.** The task that was IN FLIGHT when the run died is left
  `in_progress` (claimed), NOT open — and `bd ready` excludes `in_progress`, so a bare re-run would
  silently skip it. `cmpl auto` therefore **auto-reaps orphaned claims at startup**: any
  `in_progress` bead whose holding run is gone/stale (heartbeat) is reopened with an audit comment,
  then re-dispatched. So **just re-run `cmpl auto`** and it genuinely continues. To inspect/clean
  manually: `cmpl orphans` (list) / `cmpl orphans --reap` (reopen). An interrupted worker may also
  leave **uncommitted WIP** in the tree — the run-report flags it; salvage or revert it before the
  next run.
- Always pass `--max N` to bound the run; `--dry-run` previews the queue.

Use when the spec is frozen, tasks are atomic, write-zones disjoint, verification automated.
Otherwise use `/completely:control` (one observed task at a time).
