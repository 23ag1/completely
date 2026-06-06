#!/usr/bin/env bash
# completely :: contract tests — assert the harness's deterministic contracts actually bite.
# "TDD for the process" (Maslennikov): test the contracts, not the model. Backend for `cmpl test`.
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

echo "== bridge: GSD frontmatter -> Beads (waves + must_haves) =="
D=$(mktmp)
cat > "$D/09-01-PLAN.md" <<'PLAN'
---
phase: 09-bridge
plan: 01
type: execute
wave: 1
depends_on: []
requirements: [BR-01, BR-02]
must_haves:
  truths:
    - "emit writes must_haves onto the epic"
  artifacts:
    - path: "plugin/scripts/emit-gsd.py"
      provides: "frontmatter parser"
  key_links:
    - from: "epic"
      to: "evaluator"
---
# Bridge plan 01
<tasks>
<task type="auto">
  <name>T1 alpha</name>
  <files>a.py</files>
  <action>do A</action>
  <verify>pytest</verify>
  <done>alpha works</done>
</task>
<task type="auto">
  <name>T2 beta</name>
  <files>b.py</files>
  <action>do B</action>
  <verify>pytest</verify>
  <done>beta works</done>
</task>
</tasks>
PLAN
( cd "$D" && bash "$ROOT/scripts/emit.sh" 09-01-PLAN.md >/dev/null 2>&1 )
EM=$( cd "$D" && bd list --all --json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin); d=d if isinstance(d,list) else d.get("issues",[])
ep=[i for i in d if i.get("issue_type")=="epic"]
m=(ep[0].get("metadata") or {}) if ep else {}
print("OK" if (m.get("must_haves") and m.get("requirements")) else "NO")' )
[ "$EM" = OK ] && ok "bridge: epic carries must_haves + requirements" || no "bridge epic metadata ($EM)"
RW=$( cd "$D" && bd ready --json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin); d=d if isinstance(d,list) else d.get("issues",[])
t=[i["title"] for i in d if i.get("issue_type")!="epic"]
print("OK" if (any("alpha" in x for x in t) and not any("beta" in x for x in t)) else "NO")' )
[ "$RW" = OK ] && ok "bridge: intra-plan edge — only T1 ready" || no "bridge wave gating ($RW)"
AC=$( cd "$D" && bd list --all --json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin); d=d if isinstance(d,list) else d.get("issues",[])
v=[i.get("acceptance_criteria") for i in d if "alpha" in i.get("title","")]
print(v[0] if v else "")' )
[ "$AC" = "alpha works" ] && ok "bridge: acceptance maps from <done>" || no "bridge acceptance source ($AC)"
cat > "$D/09-02-PLAN.md" <<'PLAN'
---
phase: 09-bridge
plan: 02
type: execute
wave: 2
depends_on: [09-bridge-01]
requirements: [BR-03]
must_haves:
  truths:
    - "second plan exists"
---
# Bridge plan 02
<tasks>
<task type="auto">
  <name>T3 gamma</name>
  <files>c.py</files>
  <action>do C</action>
  <verify>pytest</verify>
  <done>gamma works</done>
</task>
</tasks>
PLAN
( cd "$D" && bash "$ROOT/scripts/emit.sh" 09-02-PLAN.md >/dev/null 2>&1 )
XP=$( cd "$D" && bd ready --json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin); d=d if isinstance(d,list) else d.get("issues",[])
print("OK" if not any("gamma" in i["title"] for i in d) else "NO")' )
[ "$XP" = OK ] && ok "bridge: cross-plan edge gates plan-02 tasks" || no "bridge cross-plan edge ($XP)"
( cd "$D" && bash "$ROOT/scripts/emit.sh" 09-01-PLAN.md >/dev/null 2>&1 )
RE=$( cd "$D" && bd ready --json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin); d=d if isinstance(d,list) else d.get("issues",[])
t=[i["title"] for i in d if i.get("issue_type")!="epic"]
print("OK" if (any("alpha" in x for x in t) and not any("beta" in x for x in t) and not any("gamma" in x for x in t)) else "NO")' )
[ "$RE" = OK ] && ok "bridge: re-emit keeps edges stable (idempotent graph)" || no "bridge re-emit idempotency ($RE)"
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

echo "== cmpl check (concise output) =="
D=$(mktmp)
printf '[check]\ncommands = [ { name = "ok", cmd = "true" }, { name = "bad", cmd = "echo E123; exit 1" } ]\n' > "$D/completely.toml"
bash "$ROOT/scripts/check.sh" "$D" >/tmp/cmpcc.out 2>&1; rc=$?
{ [ "$rc" = 1 ] && grep -q '✗ bad' /tmp/cmpcc.out && grep -q E123 /tmp/cmpcc.out && ! grep -q '✗ ok' /tmp/cmpcc.out; } \
  && ok "check fails, shows only failing output" || no "check fail-path"
printf '[check]\ncommands = [ { name = "ok", cmd = "true" } ]\n' > "$D/completely.toml"
bash "$ROOT/scripts/check.sh" "$D" >/dev/null 2>&1 && ok "check clean -> exit 0" || no "check clean exit"
rm -rf "$D" /tmp/cmpcc.out

echo "== plan-apply (Beads-first, no markdown) =="
D=$(mktmp)
printf '%s' '{"epic":"E","tasks":[{"key":"a","title":"A","acceptance":"x","design":"y","write_zone":["a"],"deps":[]},{"key":"b","title":"B","acceptance":"x","design":"y","write_zone":["b"],"deps":["a"]}]}' \
  | ( cd "$D" && bash "$ROOT/scripts/plan.sh" >/dev/null 2>&1 )
n1=$(count "$D")
printf '%s' '{"epic":"E","tasks":[{"key":"a","title":"A","acceptance":"x","design":"y","write_zone":["a"],"deps":[]},{"key":"b","title":"B","acceptance":"x","design":"y","write_zone":["b"],"deps":["a"]}]}' \
  | ( cd "$D" && bash "$ROOT/scripts/plan.sh" >/dev/null 2>&1 )
n2=$(count "$D")
{ [ "$n1" = "$n2" ] && [ "$n1" -ge 3 ]; } && ok "plan-apply idempotent ($n1->$n2)" || no "plan-apply idempotency ($n1->$n2)"
( cd "$D" && bash "$ROOT/scripts/lint.sh" >/dev/null 2>&1 ) && ok "plan-apply tasks are lint-clean" || no "plan-apply lint"
rm -rf "$D"

echo "== plan-apply field reconcile =="
D=$(mktmp)
printf '%s' '{"epic":"R","tasks":[{"key":"a","title":"A","acceptance":"v1","design":"d","write_zone":["a"]}]}' \
  | ( cd "$D" && bash "$ROOT/scripts/plan.sh" >/dev/null 2>&1 )
printf '%s' '{"epic":"R","tasks":[{"key":"a","title":"A","acceptance":"v2","design":"d","write_zone":["a"]}]}' \
  | ( cd "$D" && bash "$ROOT/scripts/plan.sh" >/dev/null 2>&1 )
AC=$( cd "$D" && bd list --all --json | python3 -c 'import json,sys
d=json.load(sys.stdin); d=d if isinstance(d,list) else d.get("issues",[])
vals=[i.get("acceptance_criteria") for i in d if i.get("title")=="A"]
print(vals[0] if vals else "")' )
[ "$AC" = "v2" ] && ok "plan-apply reconciles changed acceptance" || no "plan-apply reconcile (got: $AC)"
rm -rf "$D"

echo "== plan-apply must_haves + requirements (bridge consumer parity) =="
D=$(mktmp)
printf '%s' '{"epic":"M","tasks":[{"key":"a","title":"A","acceptance":"x","design":"d","write_zone":["a"],"requirements":["R-1"],"must_haves":{"truths":["t1"]}}]}' \
  | ( cd "$D" && bash "$ROOT/scripts/plan.sh" >/dev/null 2>&1 )
MM=$( cd "$D" && bd list --all --json | python3 -c 'import json,sys
d=json.load(sys.stdin); d=d if isinstance(d,list) else d.get("issues",[])
m=[i.get("metadata") or {} for i in d if i.get("title")=="A"]
m=m[0] if m else {}
print("OK" if (m.get("must_haves") and m.get("requirements")) else "NO")' )
[ "$MM" = OK ] && ok "plan-apply: must_haves + requirements in task metadata" || no "plan-apply must_haves/requirements ($MM)"
rm -rf "$D"

echo "== bench harness (mock, no LLM spend) =="
if bash "$ROOT/tests/bench-mock.sh" >/dev/null 2>&1; then ok "cmpl bench: worktree/judge/cost/CSV/\$per-passed green"; else no "cmpl bench mock-harness failed"; fi

echo "== craft router (stack -> existing tools) =="
if bash "$ROOT/tests/craft-mock.sh" >/dev/null 2>&1; then ok "cmpl craft: stack-aware routing to existing specialists"; else no "cmpl craft router failed"; fi

echo "== live-agent contracts =="
skip "orchestrator builds parallel-decomposition matrix before delegating"
skip "two independent streams actually spawn in parallel"
skip "closeout rejects a completion with no verification evidence"

echo
echo "tests: $PASS passed, $FAIL failed, $SKIP skipped (live)"
[ "$FAIL" -eq 0 ]
