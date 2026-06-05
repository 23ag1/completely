---
name: completely:auto
description: Run completely AUTONOMOUSLY — a fresh `claude -p` per task over the Beads queue (bd ready), Ralph-style context clearing, stopping when the queue is empty. Quality gates + the default-FAIL evaluator run underneath. Use when the spec is unambiguous, tasks are atomic, and you want hands-off execution. Backed by `cmpl auto`.
version: 0.5.0
user-invocable: true
argument-hint: "[--max N] [--dry-run]"
---
**Autonomous mode.** Run `cmpl auto` from the repo root.

- Each iteration: a fresh `claude -p` (cleared context) claims one `bd ready` task → TDD →
  quality hooks → evidence comment → `bd close` → next. Stops when the queue is empty.
- No `--dangerously-skip-permissions`; the guard hook + allowlist gate dangerous ops.
- Safety: `--max N` caps iterations; preview with `--dry-run`.

Use this only when the spec is frozen, tasks are atomic, write-zones disjoint, and verification is
automated. Otherwise use **/completely:control**.
