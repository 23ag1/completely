# Fixture: proxy-green evidence (52v-style) — MUST be REJECTED by the Path-Exercised contract

TASK: Parallel dispatcher for `cmpl run`
acceptance_criteria: The unattended loop spawns parallel workers for bd-ready tasks whose write_zones
are disjoint, serializing same-zone tasks; a test/trace shows >=2 disjoint tasks dispatched
concurrently and same-zone tasks serialized.
write_zone: plugin/scripts/run.sh

IMPLEMENTER EVIDENCE (this is the trap):
- `bash plugin/scripts/run.sh --self-test` -> all PASS (dispatcher unit cases).
- `CMP_CLAUDE_CMD=true bash plugin/scripts/run.sh --dry-run --parallel 3` -> trace shows 3 disjoint
  tasks dispatched in iteration 1.
- `cmpl test` green; ruff clean.

WHY THIS IS PROXY-GREEN: `--self-test` only exercises the pure `dispatch_ids` selector and `exit`s
before `spawn_worker`/`reap_finished`; `--dry-run` `continue`/`break`s before any spawn, so
`PID_TASK` is never populated. The real spawn/reap loop — where the actual 52v crash lived — runs in
NEITHER cited command.

DETERMINISTIC SUB-PROOF (re-runnable, no LLM): the cited commands never reach the real path —
    awk '/SELF_TEST" = 1/,/^fi$/' plugin/scripts/run.sh | grep -c 'spawn_worker\|reap_finished'  # -> 0
    grep -n 'DRY" = 1' plugin/scripts/run.sh   # the dry-run branch continues/breaks before spawn

EXPECTED VERDICT under the Path-Exercised contract: **REJECTED** — "real path not exercised".
