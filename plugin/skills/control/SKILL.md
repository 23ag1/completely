---
name: completely:control
description: Run completely UNDER CONTROL — supervised execution of the Beads queue with human gates at checkpoints (no context clearing; you review between steps). Use for ambiguous, architectural, or first-of-kind work where you want to stay in the loop. Backed by `cmpl control`.
version: 0.5.0
user-invocable: true
argument-hint: ""
---
**Under-control mode.** Run `cmpl control` from the repo root.

- Shows the ready front (from `bd swarm status` / `bd ready`) and PAUSES on human checkpoints (⏸)
  — you verify, then `bd close <id>` to release the downstream wave.
- Same context throughout (no fresh-`-p` clearing); you review between tasks.
- Quality hooks + the default-FAIL evaluator run underneath; status + evidence stay in Beads.

Use this when the spec isn't fully frozen or the work is architectural. For hands-off, use **/completely:auto**.
