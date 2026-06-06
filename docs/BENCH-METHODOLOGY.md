# cmpl bench — measuring completely's effect (WITH vs WITHOUT)

Answers the question: **"how much does code quality / token spend change with the completely harness
vs without it?"**

Method adapted from ECC's `agent-eval` skill + `benchmark-optimization-loop` (MIT; mirrored under
`research/ecc/`). agent-eval compares different *agents*; we hold the **agent + model fixed** and
compare two **arms** — raw `claude -p` vs the full completely recipe — to isolate the *harness's*
contribution, not the model's.

## Honest expectation (to be disproven, not confirmed)
completely spawns extra subagents (mapper, reviewer, security, evaluator, verifier) → it **will cost
more tokens per task**. The question is not "cheaper" but **"does the correctness/quality gain pay for
the extra spend?"** Headline metric is **`$ per PASSED task`**, not `$ per task`. If pass-rate doesn't
move, that's a finding — use completely only on non-trivial work.

## Unit of comparison: a pinned task with a deterministic judge (YAML)
```yaml
name: search-metrics
base: 6bb0501            # commit pinned for reproducibility (agent-eval practice)
prompt: |               # the task text (raw arm) / mirrors the bd issue acceptance (completely arm)
  Implement precision_at_k / recall_at_k in modules/search/metrics.py with tests.
files: [backend/app/modules/search/metrics.py]
judge:                  # >=1 deterministic judge REQUIRED (LLM judges add noise)
  - {type: command, command: "cd backend && pytest tests/test_search_metrics.py -q"}
  - {type: command, command: "cd backend && ruff check && mypy app"}
  - {type: grep, pattern: "precision_at_k|recall_at_k", files: "backend/app/modules/search/metrics.py"}
```

## Arms (same agent, same model, same base commit)
| arm | invocation |
|-----|------------|
| **A raw** | `cat task.prompt \| claude -p --output-format json --model M` — no harness, no gates, no subagents |
| **B completely** | `CMP_CLAUDE_CMD="claude -p --output-format json …" cmpl auto --max 1` — full recipe; sum every nested `claude` call |

## Isolation & repeats
- **One git worktree per (arm × task × run)** from the pinned base — runs can't interfere (agent-eval).
- **>=3 runs per (arm × task)** — LLMs are stochastic. Report mean +/- spread + **consistency** (k/N passed).

## Judges (identical for both arms, blind to which produced the tree)
- **deterministic (>=1 required):** `cmpl check` -> tests pass, coverage %, lint/type clean; build.
- **default-FAIL evaluator** (completely's own grader, reused as an independent judge) -> per-acceptance PASS/FAIL.
- **pattern:** grep for required symbols.
- **killer metric — "claimed-done-but-broken":** the arm reported success but the judge FAILs (the orphan/silent-done class).

## Cost capture (verified working)
`claude -p --output-format json` returns `total_cost_usd`, `usage.{input,output,cache_*}_tokens`,
`num_turns`, `duration_ms`, `is_error`. Arm B sums every nested `claude` call (via `CMP_BENCH_LOG`).
`total_cost_usd` is the only honest spend number (cache writes dominate raw token counts).

## Output: a ledger (CSV row per run) + summary
```
arm,task,run,cost_usd,in_tok,out_tok,cache_tok,turns,dur_s,judge_pass,coverage,review_high,sec_findings
```
-> per-arm aggregate: **pass %**, `$/run`, **`$/passed-run`**, tokens, time, consistency.

## Promotion gate (from benchmark-optimization-loop)
A claim like "the harness lifts pass-rate X%" only stands if: the delta repeats across >=3 runs, at
least one judge is deterministic, rollback is obvious, and the summary carries the exact commands +
numbers. Say **"best measured safe result"**, never "proven better", unless the task set was exhaustive.

## Tiers
- **tier-0** (cheap, a few $): 1 task x 3 runs x 2 arms — directional read in ~10 min.
- **full matrix:** 3-5 *real* tasks (not toys) x >=3 runs x 2 arms.

## Build target
```
cmpl bench --tasks bench/suite/ --arms raw,completely --repeats 3
-> bench/results.csv + a summary table
```
`run.sh` already drives one task per iteration; the only new plumbing is `CMP_BENCH_LOG` to sum the
nested `claude` JSON for arm B, plus a YAML task runner + judge harness.
