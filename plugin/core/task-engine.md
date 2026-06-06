# The task engine — how completely does ONE task, excellently

Both **control** (one step, observed) and **auto** (many steps, autonomous) run THIS EXACT recipe
per task. There are no reduced modes — the only difference is one-vs-many iterations and human
oversight. completely is the **connecting layer**: it does NOT reimplement craft — it ROUTES each
step to the best EXISTING tool. Beads (spine/coordination); the GSD specialist subagents (research →
map → plan-check → execute → verify → debug) **plus its thinking-models + phase-modes**; the design/
craft skills; the deterministic quality floor; token-compaction tools. `cmpl craft [path]` detects the
stack and names which specialist to invoke per concern — stack-agnostic, never hardcode.

## Per-task recipe (full power, no cuts)

0. **CLAIM.** `bd update <id> --claim`; read `acceptance`, `design`, `metadata.write_zone`,
   `metadata.verify`. If the next ready item is a human gate (label `checkpoint`) → PAUSE for the
   human; do not proceed past a gate.

1. **UNDERSTAND (don't guess).**
   - First: **`cmpl craft`** → the stack-routed specialist list for THIS repo (reviewers, craft
     skills, test runner, thinking-models, token tools). Makes the generic recipe concrete.
   - Unfamiliar code in the write-zone? Spawn **gsd-codebase-mapper** (or `/gsd:map-codebase`) to
     map the relevant area and read its analysis — don't load the whole tree.
   - Approach unclear / new library? Spawn **gsd-phase-researcher** (or `/gsd:research-phase`) +
     Context7 for current API docs.

2. **PLAN-CHECK the task (goal-backward, gsd-plan-checker's dimensions).** Is acceptance
   user-observable? write-zone correct? deps satisfied? artifacts wired (not created in isolation)?
   scope within context budget? If too big/ambiguous → split with `cmpl plan-apply`, or `blocked`.
   Inject GSD's **planning thinking-models** here (`gsd-core/references/thinking-models-planning.md`:
   Pre-Mortem, MECE-decomposition, Constraint-Analysis, Reversibility-Test) — each counters a
   documented agent failure. Skip them for boilerplate (don't burn tokens — see token-economy).

3. **DECOMPOSE if parallelizable.** Independent sub-streams with DISJOINT write-zones? Build a
   decomposition table and spawn **subagents in parallel** (gsd-executor pattern / Task tool), each
   with its own write-zone; serialize any conflicting writes with `bd merge-slot`. Else sequential.

4. **BUILD (TDD + craft, routed by stack).** `tdd`: failing test → minimal code → refactor; never
   delete/disable a test. Then ELEVATE with the specialist `cmpl craft` named for this stack —
   frontend → `/ui-ux-pro-max` + `/impeccable`; readability → `/simplify` / `/refactor-clean`;
   backend → the stack reviewer. Gates verify "passes"; craft makes it "excellent." Apply GSD's
   **execution thinking-models** (Curse-of-Knowledge: re-read each change as if first seeing it).
   Stay inside the write-zone.

5. **GATES (deterministic).** The quality-gate hook runs on every edit. Then `cmpl check`
   (lint+types+tests, one pass) and `cmpl lint` (worker-contract) MUST be green.

6. **REVIEW (independent subagents).** Spawn **code-reviewer** (readability/maintainability) and
   **security-reviewer** (injection/authz/secrets/validation) — fix what they flag.

7. **VERIFY (goal + acceptance).** **gsd-verifier**: did it achieve the GOAL (not just "tasks
   done")? Then the completely **evaluator** (read-only, default-FAIL): every acceptance criterion —
   AND the task's `metadata.must_haves` (GSD goal-backward: truths/artifacts/key_links) — is FAIL
   until proven by evidence you actually ran. The verifier feeds evidence; the evaluator owns the
   verdict. A single FAIL → not done.

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

## Cross-cutting (every step routes to existing tools)
- **Token economy:** Beads holds state (not md the agent re-reads); fresh context per task; one
  `cmpl check`, not N; optional **rtk** compresses tool output (cuts input tokens), **caveman** keeps
  agent output terse. `cmpl craft` flags which are installed; both degrade gracefully if absent.
- **Phase-modes (GSD) when the task is a whole phase, not a unit:** `/gsd-spec-phase` (the *what*),
  `/gsd-ui-phase` (UI contract), `/gsd-secure-phase` (threats), `/gsd-eval-review` (AI eval). The
  per-task recipe above still runs underneath each.

## control vs auto — same engine

- **control** runs steps 0–10 for the SINGLE next `bd ready` task, in this session, showing each
  subagent result and pausing at human gates. Then it STOPS — you decide whether to continue.
  Maximum observation and control; one task done excellently.
- **auto** runs steps 0–10 per task in a fresh `claude -p` (cleared context), looping over
  `bd ready` until the queue is empty. Same recipe, no human between tasks except STOP-conditions.

**control is one observed iteration of auto.** Same engine, full GSD+Beads+skills power, no cuts.
