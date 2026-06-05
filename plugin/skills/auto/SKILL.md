---
name: completely:auto
description: Run completely AUTONOMOUSLY — loop the FULL task engine over the Beads queue, a fresh `claude -p` per task (cleared context), until the queue is empty. Each task runs the SAME complete recipe as /completely:control (understand → map → plan-check → parallel subagents → TDD → checks → reviewers → verifier → evaluator → debug-on-fail → evidence → close), just many tasks hands-off. Backed by `cmpl auto`.
version: 0.6.0
user-invocable: true
argument-hint: "[--max N] [--dry-run]"
---
Run `cmpl auto` from the repo root. It loops the **full task engine** (`core/task-engine.md`) over
`bd ready`: each task gets a fresh `claude -p` (cleared context) that runs the COMPLETE recipe —
understand (gsd-codebase-mapper / phase-researcher) → plan-check → parallel subagent spawns
(serialized by `bd merge-slot`) → TDD + craft skills → `cmpl check` + `cmpl lint` → code-reviewer +
security-reviewer → gsd-verifier + the default-FAIL evaluator → gsd-debugger on failure → evidence
→ `bd close` — then the next task, until the queue is empty.

Same engine as `/completely:control`, just autonomous and many-at-once (control = one observed step).
- `--max N` caps iterations; `--dry-run` previews.
- Use when the spec is frozen, tasks are atomic, write-zones disjoint, verification automated.
  Otherwise use `/completely:control`.
