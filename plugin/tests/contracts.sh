#!/usr/bin/env bash
# completely :: contract tests — assert the harness's deterministic contracts actually bite.
# "TDD for the process" (Maslennikov): test the contracts, not the model. Backend for `cmp test`.
#
# Covers what is verifiable without a live agent: guard, sync idempotency, lint, emit, doctor.
# Live-agent contracts (matrix-before-delegate / real parallel spawn / closeout rejects no-evidence)
# are SKIPPED with a clear marker — they need a real session, and are NOT silently dropped.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"   # plugin root
PASS=0; FAIL=0; SKIP=0
ok()   { echo "  PASS $1"; PASS=$((PASS+1)); }
no()   { echo "  FAIL $1"; FAIL=$((FAIL+1)); }
skip() { echo "  SKIP $1"; SKIP=$((SKIP+1)); }
mktmp(){ local d; d=$(mktemp -d /tmp/cmptestXXXXXX); ( cd "$d" && git init -q 2>/dev/null && bd init proj --stealth >/dev/null 2>&1 ); printf '%s' "$d"; }
count(){ ( cd "$1" && bd list --all --json 2>/dev/null | python3 -c 'import json,sys
d=json.load(sys.stdin); print(len(d if isinstance(d,list) else d.get("issues",[])))' ); }

echo "== guard-dangerous =="
g(){ printf '{"tool_input":{"command":%s}}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" \
       | bash "$ROOT/hooks/guard-dangerous.sh" >/dev/null 2>&1; echo $?; }
[ "$(g 'rm -rf /')" = 2 ]          && ok "blocks rm -rf"      || no "blocks rm -rf"
[ "$(g 'git push --force')" = 2 ]  && ok "blocks force-push"  || no "blocks force-push"
[ "$(g 'DROP TABLE users;')" = 2 ] && ok "blocks DROP TABLE"  || no "blocks DROP TABLE"
[ "$(g 'ls -la')" = 0 ]            && ok "allows ls"          || no "allows ls"

echo "== sync idempotency =="
D=$(mktmp); printf -- '- [ ] alpha\n- [x] beta\n' > "$D/IMPLEMENTATION_PLAN.md"
bash "$ROOT/scripts/sync.sh" "$D" >/dev/null 2>&1; n1=$(count "$D")
bash "$ROOT/scripts/sync.sh" "$D" >/dev/null 2>&1; n2=$(count "$D")
{ [ "$n1" = 2 ] && [ "$n2" = 2 ]; } && ok "sync upserts 2, no dupes ($n1->$n2)" || no "sync idempotency ($n1->$n2)"
rm -rf "$D"

echo "== lint worker-contract =="
D=$(mktmp); ( cd "$D" && bd create "bad" -t task >/dev/null 2>&1 )
( cd "$D" && bash "$ROOT/scripts/lint.sh" >/dev/null 2>&1 ) && r=0 || r=1
[ "$r" = 1 ] && ok "lint FAILs on missing contract" || no "lint FAILs on missing contract"
( cd "$D" && BAD=$(bd list --json | python3 -c 'import json,sys
d=json.load(sys.stdin); d=d if isinstance(d,list) else d.get("issues",[])
print([i["id"] for i in d if i["title"]=="bad"][0])'); bd close "$BAD" >/dev/null 2>&1
  bd create "good" -t task --acceptance "x works" --design "approach" --metadata '{"write_zone":["a.ts"]}' >/dev/null 2>&1 )
( cd "$D" && bash "$ROOT/scripts/lint.sh" >/dev/null 2>&1 ) && r=0 || r=1
[ "$r" = 0 ] && ok "lint PASSes when contract present" || no "lint PASSes when contract present"
rm -rf "$D"

echo "== emit idempotency =="
D=$(mktmp)
printf '# P\n<tasks>\n<task type="auto"><name>T1</name><files>a.ts</files><action>do</action><verify>t</verify><done>acc</done></task>\n</tasks>\n' > "$D/X-PLAN.md"
( cd "$D" && bash "$ROOT/scripts/emit.sh" X-PLAN.md >/dev/null 2>&1 ); m1=$(count "$D")
( cd "$D" && bash "$ROOT/scripts/emit.sh" X-PLAN.md >/dev/null 2>&1 ); m2=$(count "$D")
{ [ "$m1" = 2 ] && [ "$m2" = 2 ]; } && ok "emit epic+task idempotent ($m1->$m2)" || no "emit idempotency ($m1->$m2)"
rm -rf "$D"

echo "== doctor =="
bash "$ROOT/scripts/doctor.sh" >/dev/null 2>&1 && ok "doctor runs" || no "doctor runs"

echo "== doctor quarantine =="
ST=$(mktemp -d /tmp/cmpqtXXXXXX)
sed 's/^gsd=.*/gsd=0.0.0-FAKE/' "$ROOT/versions.lock" > "$ST/lock"
CMP_LOCK="$ST/lock" CMP_STATE="$ST" bash "$ROOT/scripts/doctor.sh" >/dev/null 2>&1
grep -qx gsd "$ST/quarantine.txt" 2>/dev/null && ok "drift writes quarantine" || no "drift writes quarantine"
DQ=$(mktmp)
printf '# P\n<tasks>\n<task type="auto"><name>T</name><files>a</files><action>x</action><verify>v</verify><done>d</done></task>\n</tasks>\n' > "$DQ/P-PLAN.md"
( cd "$DQ" && CMP_STATE="$ST" bash "$ROOT/scripts/emit.sh" P-PLAN.md >/dev/null 2>&1 ); rc=$?
[ "$rc" = 3 ] && ok "quarantined emit refuses (exit 3)" || no "quarantined emit refuses (got $rc)"
rm -rf "$ST" "$DQ"

echo "== cmp check (concise output) =="
D=$(mktmp)
printf '[check]\ncommands = [ { name = "ok", cmd = "true" }, { name = "bad", cmd = "echo E123; exit 1" } ]\n' > "$D/completely.toml"
bash "$ROOT/scripts/check.sh" "$D" >/tmp/cmpcc.out 2>&1; rc=$?
{ [ "$rc" = 1 ] && grep -q '✗ bad' /tmp/cmpcc.out && grep -q E123 /tmp/cmpcc.out && ! grep -q '✗ ok' /tmp/cmpcc.out; } \
  && ok "check fails, shows only failing output" || no "check fail-path"
printf '[check]\ncommands = [ { name = "ok", cmd = "true" } ]\n' > "$D/completely.toml"
bash "$ROOT/scripts/check.sh" "$D" >/dev/null 2>&1 && ok "check clean -> exit 0" || no "check clean exit"
rm -rf "$D" /tmp/cmpcc.out

echo "== live-agent contracts =="
skip "orchestrator builds parallel-decomposition matrix before delegating"
skip "two independent streams actually spawn in parallel"
skip "closeout rejects a completion with no verification evidence"

echo
echo "tests: $PASS passed, $FAIL failed, $SKIP skipped (live)"
[ "$FAIL" -eq 0 ]
