---
name: completely:control
description: Run completely UNDER CONTROL — execute the SINGLE next Beads task through the FULL task engine (understand → map → plan-check → parallel subagents → TDD → checks → reviewers → verifier → evaluator → debug-on-fail → commit → close), in this session, showing every step and pausing at human gates. One task done excellently, then stop. control = one observed step of auto, same engine, no cuts.
version: 0.7.0
user-invocable: true
---
Execute the **single next `bd ready` task** — exactly ONE — through the full task engine
(`core/task-engine.md`), in this session, with maximum observation and control.

Follow steps 0–10 of the engine for that one task: claim → understand (spawn gsd-codebase-mapper /
gsd-phase-researcher as needed) → plan-check (goal-backward) → decompose & spawn subagents in
parallel where write-zones are disjoint (serialize with `bd merge-slot`) → TDD + craft skills →
`cmpl check` + `cmpl lint` → spawn code-reviewer + security-reviewer → gsd-verifier + the
default-FAIL evaluator → gsd-debugger on repeated failure → **LAND: bd comment evidence → git commit
(confirm it landed) → ONLY THEN `bd close` if the evaluator ACCEPTED**.

Show me each subagent's result. PAUSE at any human gate (checkpoint) and at STOP-conditions. After
the one task lands, STOP and report — I decide whether to run the next.

Identical to one iteration of `/completely:auto` — same full engine — just observed and
one-at-a-time. Nothing is reduced.
