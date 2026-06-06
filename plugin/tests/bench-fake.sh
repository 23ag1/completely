#!/usr/bin/env bash
# completely :: bench fake agent — stands in for a real `claude -p` arm so the bench harness
# (worktree isolation, judge eval, cost capture, CSV + summary) is testable with ZERO LLM spend.
# Contract (set by bench.py): runs in the per-run worktree (cwd); BENCH_PROMPT = task prompt;
# BENCH_COST = path to write a result JSON. It satisfies the mock suite's judge and emits a fixed cost.
set -uo pipefail
echo "ok bench" > judged.txt
printf '{"total_cost_usd":0.03,"usage":{"input_tokens":120,"output_tokens":40},"num_turns":1,"duration_ms":900,"is_error":false}\n' > "${BENCH_COST:?BENCH_COST unset}"
