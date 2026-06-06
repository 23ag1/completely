#!/usr/bin/env bash
# completely :: bench-mock — exercise `cmpl bench` end-to-end with a fake agent (NO LLM spend).
# Proves the harness: worktree isolation, arms x repeats, judge eval, cost capture, CSV + summary.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMPL="$ROOT/bin/cmpl"
FAKE="$ROOT/tests/bench-fake.sh"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  PASS $1"; }
no(){ fail=$((fail+1)); echo "  FAIL $1"; }

WORK="$(mktemp -d /tmp/benchmock.XXXXXX)"; cd "$WORK"
git init -q; git -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
mkdir -p suite
cat > suite/t1.json <<'JSON'
{"name":"t1","prompt":"make judged.txt say ok","files":["judged.txt"],
 "judge":[{"type":"grep","pattern":"ok bench","files":"judged.txt"}]}
JSON

OUT="$WORK/results.csv"
CMP_BENCH_CMD="bash $FAKE" timeout 60 bash "$CMPL" bench --tasks suite --arms raw,completely --repeats 2 --out "$OUT" > run.log 2>&1
rc=$?
[ "$rc" = 0 ] && ok "cmpl bench exit 0" || { no "cmpl bench exit ($rc)"; sed 's/^/    /' run.log | tail -12; }
[ -f "$OUT" ] && ok "results.csv written" || no "results.csv missing"
if [ -f "$OUT" ]; then
  rows=$(($(wc -l < "$OUT")-1))
  [ "$rows" = 4 ] && ok "4 rows (2 arms x 2 repeats)" || no "expected 4 rows, got $rows"
  allpass=$(awk -F, 'NR>1 && $9==1' "$OUT" | wc -l)
  [ "$allpass" = 4 ] && ok "all 4 runs judged pass" || no "judged pass=$allpass/4"
  grep -q '0.03' "$OUT" && ok "cost captured (0.03)" || no "cost not captured in CSV"
fi
grep -qiE '(^|[^a-z])raw([^a-z]|$)' run.log && grep -qi 'completely' run.log && ok "summary lists both arms" || no "summary missing an arm"
grep -qiE 'passed' run.log && ok "summary reports passed metric" || no "no passed metric in summary"

echo "bench-mock: $pass passed, $fail failed"
[ "$fail" = 0 ]
