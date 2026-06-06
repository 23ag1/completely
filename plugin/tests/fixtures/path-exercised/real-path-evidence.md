# Fixture: real-path evidence — MUST be ACCEPTED by the Path-Exercised contract

TASK / acceptance_criteria / write_zone: identical to proxy-green-evidence.md.

IMPLEMENTER EVIDENCE:
- `CMP_CLAUDE_CMD=true CMP_PARALLEL=2 bash plugin/scripts/run.sh --mode unattended` on two disjoint
  bd tasks -> log: `dispatch task=A`, `dispatch task=B`, two `worker pid=.. finished`, `done after 2
  iterations`. The real spawn/reap loop ran end-to-end, no crash.
- Negative control: reverting the loop's array-iteration fix reproduces
  `run.sh: line N: invalid variable name`, and the integration test goes RED.
- `cmpl test` green — the real-loop integration test `== run parallel spawn loop ==` is wired into
  plugin/tests/contracts.sh (drives the loop with the `CMP_CLAUDE_CMD=true` mock backend).

WHY THIS IS REAL-PATH: `--mode unattended` drives the actual loop (`spawn_worker` -> `&` ->
`reap_finished`), the exact path `--self-test`/`--dry-run` skip; and the negative control mutates the
real failure surface (the assoc-array iteration), not a proxy unit.

EXPECTED VERDICT under the Path-Exercised contract: **ACCEPTED** — real entrypoint exercised + a
negative control on the real failure surface goes RED. (Proves the new dimension is NOT a blanket
reject.)
