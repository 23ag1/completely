---
name: completely:run
description: Drive the Beads queue (`bd ready`) with one engine in two autonomy modes — supervised (GSD wave subagents, human gates at phase boundaries) or unattended (Ralph-style fresh-context loop, stops when the queue is empty). Quality gates + the default-FAIL evaluator run underneath both. Use to execute planned work. Backed by `cmpl run`.
version: 0.2.0
user-invocable: true
argument-hint: "[--mode supervised|unattended] [--max N] [--dry-run]"
---
Execute planned work from Beads with the right autonomy level.

**Pick the mode (the dial):** run **unattended** only when the spec is unambiguous, tasks are
atomic, write-zones are disjoint, and verification is automated. Otherwise run **supervised**.

- **Unattended** (`cmpl run` / `cmpl run --max N`): fresh `claude -p` per iteration reading the
  Beads-aware overlay prompt; ONE task per iteration; stops when `bd ready` is empty. No
  `--dangerously-skip-permissions` — the guard hook + allowlist gate dangerous ops.
- **Supervised** (`cmpl run --mode supervised`): hand off to `/gsd:execute-phase <phase>` (wave
  subagents, checkpoints). Either way, status lives in Beads and evidence in `bd comment`.

Use `--dry-run` first to see how many tasks are ready and what would execute, without running.
Each iteration: claim one task → TDD → gates → evidence comment → `bd close` → next. Blocked →
`bd ... --status blocked` + comment, never a silent stub.
