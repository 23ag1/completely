# The task engine — how completely does ONE task, excellently

Both **control** (one step, observed) and **auto** (many steps, autonomous) run THIS EXACT recipe
per task. There are no reduced modes — the only difference is one-vs-many iterations and human
oversight. The recipe uses the best of every tool: Beads (spine/coordination), the GSD specialist
subagents (research → map → plan-check → execute → verify → debug), completely's quality floor,
and the craft skills.

## Per-task recipe (full power, no cuts)

0. **CLAIM.** `bd update <id> --claim`; read `acceptance`, `design`, `metadata.write_zone`,
   `metadata.verify`. If the next ready item is a human gate (label `checkpoint`) → PAUSE for the
   human; do not proceed past a gate.

1. **UNDERSTAND (don't guess).**
   - Unfamiliar code in the write-zone? Spawn **gsd-codebase-mapper** (or `/gsd:map-codebase`) to
     map the relevant area and read its analysis — don't load the whole tree.
   - Approach unclear / new library? Spawn **gsd-phase-researcher** (or `/gsd:research-phase`) +
     Context7 for current API docs.

2. **PLAN-CHECK the task (goal-backward, gsd-plan-checker's dimensions).** Is acceptance
   user-observable? write-zone correct? deps satisfied? artifacts wired (not created in isolation)?
   scope within context budget? If too big/ambiguous → split with `cmpl plan-apply`, or `blocked`.

3. **DECOMPOSE if parallelizable.** Independent sub-streams with DISJOINT write-zones? Build a
   decomposition table and spawn **subagents in parallel** (gsd-executor pattern / Task tool), each
   with its own write-zone; serialize any conflicting writes with `bd merge-slot`. Else sequential.

4. **BUILD (TDD + craft).** `tdd`: failing test → minimal code → refactor; never delete/disable a
   test. Frontend → `/impeccable` + `/ui-ux-pro-max`; cleanup → `/simplify`. Stay inside the write-zone.

5. **GATES (deterministic).** The quality-gate hook runs on every edit. Then `cmpl check`
   (lint+types+tests, one pass) and `cmpl lint` (worker-contract) MUST be green.

6. **REVIEW (independent subagents).** Spawn **code-reviewer** (readability/maintainability) and
   **security-reviewer** (injection/authz/secrets/validation) — fix what they flag.

7. **VERIFY (goal + acceptance).** **gsd-verifier**: did it achieve the GOAL (not just "tasks
   done")? Then the completely **evaluator** (read-only, default-FAIL): every acceptance criterion
   is FAIL until proven by evidence you actually ran. A single FAIL → not done.

8. **DEBUG on failure.** Tests/checks fail repeatedly (≥3)? Spawn **gsd-debugger** (scientific
   method, persistent session) — don't thrash, don't disable the test.

9. **LAND — commit BEFORE close** (so an interruption never leaves a closed bead with uncommitted
   code). In this EXACT order: (a) `bd comment <id>` with the verify command + output + subagent
   verdicts; (b) `git add` the write-zone and `git commit -m "... (<id>)"`, and CONFIRM it landed
   (if the commit is blocked by a shared-tree gate, fix it or return blocked — do NOT close);
   (c) ONLY after the commit landed AND the evaluator ACCEPTED → `bd close <id>`.

10. **STOP-conditions** (spec ambiguity / scope beyond write-zone / cannot build full version /
    security finding / repeated failure / architecture fork) → `bd update <id> --status blocked` +
    comment with the reason, and surface to the human. NEVER a silent stub.

## control vs auto — same engine

- **control** runs steps 0–10 for the SINGLE next `bd ready` task, in this session, showing each
  subagent result and pausing at human gates. Then it STOPS — you decide whether to continue.
  Maximum observation and control; one task done excellently.
- **auto** runs steps 0–10 per task in a fresh `claude -p` (cleared context), looping over
  `bd ready` until the queue is empty. Same recipe, no human between tasks except STOP-conditions.

**control is one observed iteration of auto.** Same engine, full GSD+Beads+skills power, no cuts.
