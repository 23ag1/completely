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
   **Query prior decisions FIRST.** Before choosing a lib / pattern / contract, run
   `bd query "type=decision"` (and a topic-scoped variant, e.g.
   `bd query 'type=decision AND title=auth'`) — a sibling or earlier task may have already locked
   that choice as an ADR. Inherit it; if you must contradict it, record a superseding ADR
   (`bd create --type=decision --title "..." --description "context · choice · consequences"` and
   `bd supersede <new> <old>`), don't silently diverge. This is the cross-task analogue to
   `bd comment` (task-bound) — see `core/memory-policy.md` (Cross-task architecture decision).
   The **planning thinking-models** (Pre-Mortem, MECE-Decomposition, Constraint-Analysis,
   Reversibility-Test) are **ENFORCED**, not referenced: `cmpl run` injects a
   `<<COMPLETELY_ENFORCED step=plan-check policy=thinking-models-planning>>` block into the worker's
   stdin at spawn — the rule text travels with the prompt, not as a doc the worker chooses to read.
   Each model counters a documented agent failure mode; skipping any is a stop-condition. Skip the
   whole block only for boilerplate (don't burn tokens — see token-economy). Inspect the exact
   injection a worker will see with `cmpl run --show-prompt <task-id>` (zero side effects).

3. **DECOMPOSE if parallelizable.** Independent sub-streams with DISJOINT write-zones? Build a
   decomposition table and spawn **subagents in parallel** (gsd-executor pattern / Task tool), each
   with its own write-zone; serialize any conflicting writes with `bd merge-slot`. Else sequential.
   This is the WITHIN-task fan-out. The cross-task fan-out (multiple `bd ready` tasks running at
   once) is owned by `cmpl run` — see "queue-level parallelism" below.

4. **BUILD (TDD + craft, routed by stack).** `tdd`: failing test → minimal code → refactor; never
   delete/disable a test. Then ELEVATE with the specialist `cmpl craft` named for this stack —
   frontend → `/ui-ux-pro-max` + `/impeccable`; readability → `/simplify` / `/refactor-clean`;
   backend → the stack reviewer. Gates verify "passes"; craft makes it "excellent." Apply GSD's
   **execution thinking-models** (Curse-of-Knowledge: re-read each change as if first seeing it).
   Stay inside the write-zone.

5. **GATES (deterministic).** The quality-gate hook runs on every edit. Then `cmpl check`
   (lint+types+tests, one pass) and `cmpl lint` (worker-contract) MUST be green.

6. **REVIEW (independent subagents).** Spawn **code-reviewer** (readability/maintainability) and
   **security-reviewer** (injection/authz/secrets/validation) — fix what they flag. The security
   reviewer requirement is **ENFORCED**: `cmpl run` injects
   `<<COMPLETELY_ENFORCED step=review policy=security>>` into the worker's prompt at spawn, listing
   the diff-trigger surfaces (input handling, authn/authz, secrets, interpolation, deserialization,
   file/URL ingestion, crypto, sandbox boundaries) and treating CRITICAL/HIGH findings as blocking.
   Trace with `cmpl run --show-prompt <task-id>`. Self-test: `cmpl run --self-test` asserts both
   enforced blocks appear in the worker prompt in the correct order (dispatch → plan-check → review).

7. **VERIFY (goal + acceptance).** **gsd-verifier**: did it achieve the GOAL (not just "tasks
   done")? Then the completely **evaluator** (read-only, default-FAIL): every acceptance criterion —
   AND the task's `metadata.must_haves` (GSD goal-backward: truths/artifacts/key_links) — is FAIL
   until proven by evidence you actually ran. The verifier feeds evidence; the evaluator owns the
   verdict. A single FAIL → not done.
   **Path-Exercised (enforced).** Evidence must run the REAL runtime path, not a proxy —
   *tests-green ≠ failing-path-exercised*: a green unit, a `--dry-run`, or a mock at the wrong layer
   can pass while the production path never runs (this is how the parallel-dispatch crash once
   shipped green). `cmpl run` injects `<<COMPLETELY_ENFORCED step=verify policy=path-exercised>>`
   into every worker prompt at spawn (trace: `cmpl run --show-prompt <id>`; gated by
   `cmpl run --self-test`). **Convention for orchestration/shell:** drive the real loop with a mock
   backend (`CMP_CLAUDE_CMD=true`) so the spawn/reap path actually runs — a unit + dry-run skip it —
   and add a negative control that goes RED when the impl is broken. See `plugin/agents/evaluator.md`
   (Path-Exercised) and `plugin/tests/fixtures/path-exercised/`.

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

## Queue-level parallelism (`cmpl run` dispatcher)

Inside a task the worker can parallelize via subagents (step 3). Across the `bd ready` queue,
`cmpl run` (unattended mode) is also parallel by default: each iteration the parent reads the
queue, picks the highest-priority tasks whose `metadata.write_zone`s are **disjoint** from every
running worker (and from each other), pre-claims them via `bd update --claim`, and spawns up to
`CMP_PARALLEL` (default 4) fresh `claude -p` workers in parallel. Same-write-zone tasks
**serialize** — the next one waits for the current to finish before being dispatched.

The worker receives its assigned task ID via an injected stdin header (skip the selection step 0,
work the specific task). A task with NO declared `write_zone` is treated as a global zone and
serializes against everything (the worker-contract requires a declared zone — `cmpl lint` enforces
this on plan-apply).

Knobs:
- `CMP_PARALLEL=N` (or `--parallel N`) — max concurrent workers (1 = legacy serial flow).
- `CMP_BENCH_LOG=...` — forces `--parallel 1` so JSON results in the shared log stay race-free.
- `--dry-run` prints the dispatch plan (which tasks would spawn in parallel, which would wait).
- `--self-test` runs the dispatcher's unit cases (disjoint dispatch / same-zone serialize /
  prefix-overlap / undeclared-zone-is-global / running-zone-blocks-overlap / slot-budget /
  checkpoint-skip) without touching `claude` or Beads.

Merge-slot is still the safety net at COMMIT time for rare cross-zone file collisions (two tasks
whose declared zones don't overlap but happen to both touch a file at land time); the dispatcher
covers the common case at SPAWN time.

## Run-report — the loop never lies about "done" (`cmpl run`)

On EVERY exit (queue drained / wall-clock stall / `--max`) the loop prints a **run-report** with an
honest verdict:
- **DONE** only if `bd ready` is empty AND there are **zero `in_progress` orphans** AND the tree is
  **clean**. Otherwise **STOPPED — INCOMPLETE**, listing the orphaned beads (a worker that died or
  was killed without closing — reset with `bd update <id> --status open`) and the uncommitted files.
- It also reports: tasks closed this run, blocked count, stop reason, approximate spend.

This kills the overnight-run trap — the loop stopping with orphans + a dirty tree while a near-empty
`bd ready` *looks* finished. `cmpl run --self-test` Case 10 drives the real loop against a worker
that dies mid-run and asserts the report flags the orphan + reports INCOMPLETE (negative control).

## control vs auto — same engine

- **control** runs steps 0–10 for the SINGLE next `bd ready` task, in this session, showing each
  subagent result and pausing at human gates. Then it STOPS — you decide whether to continue.
  Maximum observation and control; one task done excellently.
- **auto** runs steps 0–10 per task in a fresh `claude -p` (cleared context), looping over
  `bd ready` until the queue is empty. Same recipe, no human between tasks except STOP-conditions.

**control is one observed iteration of auto.** Same engine, full GSD+Beads+skills power, no cuts.
