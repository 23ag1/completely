---
name: completely
description: Overview and entry point for the completely harness — a quality-first agent workflow unifying GSD (planning depth), Ralph (autonomous loop), and Beads (the spine), under deterministic gate hooks and a default-FAIL evaluator. Use to see what's installed, the command surface, and how to start.
version: 0.2.0
user-invocable: true
---
**completely** makes it hard for an agent to quietly cut a corner, fake "done", or ship a stub.
Short CLI: `cmpl`.  Slash: `/completely:*`.

## Command surface
- `/completely:init` — scaffold the thin layer (DoD, CLAUDE.md rules, project gate) into this repo.
- `/completely:sync` (`cmpl sync`) — migrate markdown task state into Beads, idempotently.
- `/completely:run` — drive `bd ready`: supervised (GSD wave subagents) or unattended (Ralph loop).
- `/completely:doctor` (`cmpl doctor`) — upstream version drift + overlay health.

## How it fits (one engine, one spine)
Beads = the spine (status + memory via comments/notes/remember + coordination via swarm/gate/merge-slot).
GSD = planning depth (discuss→plan→plan-checker loop). Ralph = the OS-level autonomous loop.
completely = the quality floor (gate hooks + default-FAIL `evaluator` + no-stub contract) under all of them.
GSD and Ralph are two autonomy *modes* of the same loop over `bd ready`, not a choice of tools.

See `plugin/core/HARNESS.md` (the principle), `plugin/core/roles.md` (who owns what),
and `docs/TOOL-COMPATIBILITY.md` (the full design + per-tool detail).
