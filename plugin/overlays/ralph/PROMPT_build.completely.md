# completely :: AUTO worker — ONE task, the FULL task engine (no cuts)

You are ONE iteration of the autonomous loop. Fresh context. Do ONE task EXCELLENTLY using the
full engine below, then exit. The runner loops you over `bd ready` until the queue is empty.
Beads is the single source of truth — never track work in markdown.

0. CLAIM: `bd ready --json` → highest-priority unblocked task → `bd update <id> --claim`. Read its
   acceptance, design, metadata.write_zone, metadata.verify. If the next ready item is a human gate
   (label `checkpoint`) → STOP (a human must close it). Don't touch files outside the write-zone.
1. UNDERSTAND: unfamiliar code → spawn gsd-codebase-mapper; unclear approach/new lib → spawn
   gsd-phase-researcher (+ Context7 for fresh docs). Don't guess.
2. PLAN-CHECK (goal-backward): acceptance user-observable? deps ok? artifacts wired? scope sane?
   Too big/ambiguous → split via `cmpl plan-apply` or return blocked.
3. DECOMPOSE: independent sub-streams with disjoint write-zones → spawn subagents in PARALLEL
   (one write-zone each); serialize conflicting writes with `bd merge-slot`. Else sequential.
4. BUILD: tdd (failing test → minimal code → refactor; never disable a test). Frontend →
   /impeccable + /ui-ux-pro-max. Stay in the write-zone.
5. GATES: the quality-gate hook runs on each edit. Then `cmpl check` and `cmpl lint` MUST be green.
6. REVIEW: spawn code-reviewer + security-reviewer subagents; fix what they flag.
7. VERIFY: gsd-verifier (goal achieved, not just "done") → then the evaluator agent (read-only,
   default-FAIL): every criterion FAIL until proven by evidence you ran. A single FAIL → not done.
8. DEBUG on repeated failure (≥3): spawn gsd-debugger (scientific method). Don't thrash.
9. CLOSE: `bd comment <id>` with the exact verify command + output (+ subagent verdicts);
   `bd close <id>` ONLY if the evaluator ACCEPTED; commit with the task id.
10. STOP-conditions → `bd update <id> --status blocked` + comment the reason. NEVER a silent stub.

Spawn the named subagents — don't do their job in your head. Full detail: core/task-engine.md.
