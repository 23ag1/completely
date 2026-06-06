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
  That's fine: **just re-run `cmpl auto`** — it is idempotent, continuing from the remaining
  `bd ready`. Because the engine **commits BEFORE closing a bead**, an interrupted run leaves a
  clean, resumable state (committed work + still-open beads for unfinished tasks) — never a closed
  bead with uncommitted code.
- Always pass `--max N` to bound the run; `--dry-run` previews the queue.

Use when the spec is frozen, tasks are atomic, write-zones disjoint, verification automated.
Otherwise use `/completely:control` (one observed task at a time).
