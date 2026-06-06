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

echo "== bd-close gate (commit-before-close) =="
GD=$(mktmp)
( cd "$GD" && git -c user.email=t@t -c user.name=t commit -qm init --allow-empty 2>/dev/null )
gc(){ printf '{"tool_input":{"command":%s}}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" \
        | ( cd "$GD" && bash "$ROOT/hooks/guard-close.sh" >/dev/null 2>&1 ); echo $?; }
gco(){ printf '{"tool_input":{"command":%s}}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" \
        | ( cd "$GD" && CMP_ALLOW_DIRTY_CLOSE=1 bash "$ROOT/hooks/guard-close.sh" >/dev/null 2>&1 ); echo $?; }
[ "$(gc 'bd close abc-1')" = 0 ] && ok "close allowed on clean tree"          || no "close clean allow"
[ "$(gc 'bd ready')" = 0 ]       && ok "gate ignores non-close bd commands"   || no "close gate over-broad"
( cd "$GD" && echo x > f.txt && git add f.txt )
[ "$(gc 'bd close abc-1')" = 2 ] && ok "close BLOCKED on uncommitted tracked changes" || no "close dirty block"
[ "$(gc 'bd update abc-1 --status=closed')" = 2 ] && ok "gate also catches --status=closed (equals form)" || no "close equals-form block"
[ "$(gco 'bd close abc-1')" = 0 ] && ok "CMP_ALLOW_DIRTY_CLOSE overrides the gate" || no "close override"
rm -rf "$GD"

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
  bd create "good" -t task --acceptance "x works" --design "approach" --metadata '{"write_zone":["a.ts"],"verify":"npm test"}' >/dev/null 2>&1 )
( cd "$D" && bash "$ROOT/scripts/lint.sh" >/dev/null 2>&1 ) && r=0 || r=1
[ "$r" = 0 ] && ok "lint PASSes when contract present" || no "lint PASSes when contract present"
rm -rf "$D"

echo "== lint: metadata.verify required + entrypoint real-path floor =="
D=$(mktmp)
( cd "$D" && bd create "nv" -t task --acceptance x --design y --metadata '{"write_zone":["a.ts"]}' >/dev/null 2>&1 )
( cd "$D" && bash "$ROOT/scripts/lint.sh" >/dev/null 2>&1 ) && rv=0 || rv=1
[ "$rv" = 1 ] && ok "lint FAILs on missing metadata.verify" || no "lint missing-verify"
( cd "$D" && nv=$(bd list --json | python3 -c 'import json,sys
d=json.load(sys.stdin); d=d if isinstance(d,list) else d.get("issues",[])
print([i["id"] for i in d if i["title"]=="nv"][0])'); bd close "$nv" >/dev/null 2>&1 )
( cd "$D" && bd create "epx" -t task --acceptance x --design y --metadata '{"write_zone":["plugin/scripts/run.sh"],"verify":"pytest tests/test_x.py"}' >/dev/null 2>&1 )
( cd "$D" && bash "$ROOT/scripts/lint.sh" >/dev/null 2>&1 ) && rv=0 || rv=1
[ "$rv" = 1 ] && ok "lint FAILs entrypoint task with proxy verify" || no "lint entrypoint-proxy-verify"
( cd "$D" && ep=$(bd list --json | python3 -c 'import json,sys
d=json.load(sys.stdin); d=d if isinstance(d,list) else d.get("issues",[])
print([i["id"] for i in d if i["title"]=="epx"][0])'); bd close "$ep" >/dev/null 2>&1 )
( cd "$D" && bd create "epr" -t task --acceptance x --design y --metadata '{"write_zone":["plugin/scripts/run.sh"],"verify":"bash plugin/tests/contracts.sh"}' >/dev/null 2>&1 )
( cd "$D" && bash "$ROOT/scripts/lint.sh" >/dev/null 2>&1 ) && rv=0 || rv=1
[ "$rv" = 0 ] && ok "lint PASSes entrypoint task with real-path verify" || no "lint entrypoint-real-verify"
( cd "$D" && bd create "hookx" -t task --acceptance x --design y --metadata '{"write_zone":["plugin/hooks/guard-x.sh"],"verify":"pytest unit"}' >/dev/null 2>&1 )
( cd "$D" && bash "$ROOT/scripts/lint.sh" >/dev/null 2>&1 ) && rv=0 || rv=1
[ "$rv" = 1 ] && ok "lint FAILs hooks-entrypoint task w/ proxy verify (HIGH#1 fix)" || no "lint hooks-entrypoint"
rm -rf "$D"

echo "== cmpl lint self-test (NCR/blocked path — now gated by cmpl test) =="
if bash "$ROOT/scripts/lint.sh" --self-test >/dev/null 2>&1; then ok "lint.sh --self-test green (NCR + blocked + verify-clean)"; else no "lint.sh --self-test"; fi

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

echo "== emit-gsd parser: latent edge cases (nested dict-in-list, comma-in-quoted scalar) =="
# Latent in GSD 1.3.1 (always inline dict-in-seq, comma-free ids) but the parser must hold.
PR=$( python3 - "$ROOT/scripts/emit-gsd.py" <<'PY' 2>&1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('eg', sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
# (1) seq-dict: first key has a nested mapping block — must NOT drop `path`
fm1 = m.parse_frontmatter('''---
must_haves:
  artifacts:
    - path:
        kind: py
        loc: "100"
      provides: parser
---
body
''')
arts = fm1.get('must_haves', {}).get('artifacts') or []
first = arts[0] if (arts and isinstance(arts[0], dict)) else {}
ok1 = (len(arts) == 1
       and first.get('path') == {'kind': 'py', 'loc': '100'}
       and first.get('provides') == 'parser')
# (2) inline list with comma inside a quoted scalar — must NOT split mid-quote
fm2 = m.parse_frontmatter('''---
requirements: [a, "b, c", d]
---
''')
ok2 = fm2.get('requirements') == ['a', 'b, c', 'd']
print('A' if ok1 else 'a-FAIL:%r' % arts, 'B' if ok2 else 'b-FAIL:%r' % fm2.get('requirements'))
PY
)
case "$PR" in
  "A B") ok "emit-gsd: seq-dict first-key nested block preserved" ; ok "emit-gsd: inline list respects quotes" ;;
  "A "*) ok "emit-gsd: seq-dict first-key nested block preserved" ; no "emit-gsd inline-list quote-aware ($PR)" ;;
  *" B") no "emit-gsd seq-dict first-key nested block ($PR)" ; ok "emit-gsd: inline list respects quotes" ;;
  *)     no "emit-gsd parser edge cases ($PR)" ; no "emit-gsd parser edge cases ($PR)" ;;
esac

echo "== run.sh land-guard (git identity so per-task commits land) =="
D=$(mktmp)
( cd "$D" && bd create "t" -t task --acceptance a --design d --metadata '{"write_zone":["x"]}' >/dev/null 2>&1 )
( cd "$D" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null CMP_CLAUDE_CMD="true" \
    bash "$ROOT/scripts/run.sh" --dry-run >/dev/null 2>&1 )
GI=$( cd "$D" && GIT_CONFIG_GLOBAL=/dev/null git config user.email 2>/dev/null )
[ -n "$GI" ] && ok "run.sh ensures a git identity before the loop ($GI)" || no "run.sh land-guard (no identity set)"
rm -rf "$D"

echo "== run dispatcher (parallel disjoint / serial same-zone) =="
if bash "$ROOT/scripts/run.sh" --self-test >/dev/null 2>&1; then
  ok "cmpl run dispatcher: disjoint tasks parallel, same write_zone serializes"
else
  no "cmpl run dispatcher self-test"
fi

echo "== run parallel spawn loop (real dispatch+reap, mock worker — no LLM) =="
# Integration test: the dispatcher UNIT (self-test) passed while the BASH spawn/reap loop that
# consumes its output crashed at runtime ("invalid variable name" iterating the PID maps). This
# drives the real loop with a mock worker (CMP_CLAUDE_CMD=true) on two disjoint tasks.
PD=$(mktmp)
( cd "$PD" && git -c user.email=t@t -c user.name=t commit -qm init --allow-empty >/dev/null 2>&1
  bd create "A" -t task --acceptance a --design d --metadata '{"write_zone":["a.txt"]}' >/dev/null 2>&1
  bd create "B" -t task --acceptance a --design d --metadata '{"write_zone":["b.txt"]}' >/dev/null 2>&1 )
PDOUT=$( cd "$PD" && CMP_CLAUDE_CMD='true' CMP_PARALLEL=2 CMP_STALL=1 timeout 60 bash "$ROOT/scripts/run.sh" --mode unattended 2>&1 )
if printf '%s' "$PDOUT" | grep -qiE 'invalid variable|: line [0-9]+:|syntax error'; then
  no "run parallel spawn loop crashes ($(printf '%s' "$PDOUT" | grep -iE 'invalid variable|line [0-9]' | head -1))"
elif printf '%s' "$PDOUT" | grep -q 'done after'; then
  ok "run parallel spawn loop: disjoint workers dispatched + reaped, no crash"
else
  no "run parallel spawn loop did not complete cleanly"
fi
rm -rf "$PD"

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

echo "== root completely.toml gates this repo (no-op regression) =="
RNAMES=$(python3 "$ROOT/scripts/config.py" checks "$ROOT/.." 2>/dev/null | python3 -c 'import sys
names=sorted(l.split("\t")[0] for l in sys.stdin.read().splitlines() if l.strip())
print(",".join(names))')
[ "$RNAMES" = "contracts,ruff" ] && ok "root completely.toml resolves ruff + contracts (cmpl check not a no-op)" || no "root [check] regression ($RNAMES)"

echo "== plan-apply (Beads-first, no markdown) =="
D=$(mktmp)
printf '%s' '{"epic":"E","tasks":[{"key":"a","title":"A","acceptance":"x","design":"y","write_zone":["a"],"verify":"pytest -q","deps":[]},{"key":"b","title":"B","acceptance":"x","design":"y","write_zone":["b"],"verify":"pytest -q","deps":["a"]}]}' \
  | ( cd "$D" && bash "$ROOT/scripts/plan.sh" >/dev/null 2>&1 )
n1=$(count "$D")
printf '%s' '{"epic":"E","tasks":[{"key":"a","title":"A","acceptance":"x","design":"y","write_zone":["a"],"verify":"pytest -q","deps":[]},{"key":"b","title":"B","acceptance":"x","design":"y","write_zone":["b"],"verify":"pytest -q","deps":["a"]}]}' \
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

echo "== evaluator: adversarial claim-vs-refute mode (port ECC gan-* pair) =="
EV="$ROOT/agents/evaluator.md"
grep -q "Adversarial mode" "$EV" && ok "evaluator: adversarial mode section present" || no "evaluator: missing adversarial mode section"
grep -qi "claim" "$EV" && grep -qi "refute" "$EV" && ok "evaluator: claim + refute language present" || no "evaluator: claim/refute language missing"
grep -q "eval_mode" "$EV" && ok "evaluator: opt-in trigger documented (eval_mode)" || no "evaluator: opt-in trigger missing"
# REFUTED stays default until the evaluator finds the claim withstands an active refutation attempt
grep -q "REFUTED" "$EV" && grep -q "WITHSTOOD" "$EV" && ok "evaluator: per-claim verdicts named (REFUTED/WITHSTOOD)" || no "evaluator: per-claim verdict tokens missing"
# regression-bite: not just "tokens exist" — the output table header AND the Beads comment tag must be present
grep -q '| # | Claim |' "$EV" && ok "evaluator: adversarial output table header wired" || no "evaluator: adversarial output table header missing"
grep -q 'EVALUATOR (adversarial)' "$EV" && ok "evaluator: Beads comment carries (adversarial) tag" || no "evaluator: missing (adversarial) tag on Beads comment"

echo "== cost-tracker hook (opt-in PostToolUse — exit 0, bounded, no secrets) =="
CT_HOOK="$ROOT/hooks/cost-tracker.sh"
[ -x "$CT_HOOK" ] && ok "cost-tracker.sh exists and is executable" || no "cost-tracker.sh missing/not-executable"
# wired into hooks.json under PostToolUse with matcher * (real-path floor)
python3 - "$ROOT/hooks/hooks.json" <<'PY' >/dev/null 2>&1 && ok "hooks.json wires cost-tracker under PostToolUse *" || no "hooks.json missing cost-tracker wiring"
import json, sys
d=json.load(open(sys.argv[1]))
post=d.get("hooks",{}).get("PostToolUse",[])
hit=any(h.get("matcher")=="*" and any("cost-tracker.sh" in (x.get("command","") or "") for x in (h.get("hooks") or [])) for h in post)
sys.exit(0 if hit else 1)
PY
CT_DIR=$(mktemp -d /tmp/cmpct.XXXXXX)
CT_LOG="$CT_DIR/cost.jsonl"
# opt-out: no CMP_COST_TRACK -> no log, exit 0
printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"output":"ok"}}' \
  | CMP_COST_LOG="$CT_LOG" bash "$CT_HOOK" >/dev/null 2>&1
rc=$?
{ [ "$rc" = 0 ] && [ ! -f "$CT_LOG" ]; } && ok "opt-out: hook is a no-op (no file, exit 0)" || no "opt-out: rc=$rc, file?=$( [ -f "$CT_LOG" ] && echo yes || echo no )"
# opt-in: payload carrying multiple secret shapes (AWS key, sk- token, cookie, Bearer)
CT_SECRET='AWS_SECRET_ACCESS_KEY=wJalrXUtSECRET-cookie=sess=abcd-Bearer-tok-1234'
printf '{"tool_name":"Bash","tool_input":{"command":"%s curl evil"},"tool_response":{"output":"sk-leaked-2222"}}' "$CT_SECRET" \
  | CMP_COST_TRACK=1 CMP_COST_LOG="$CT_LOG" bash "$CT_HOOK" >/dev/null 2>&1
rc=$?
[ "$rc" = 0 ] && ok "opt-in: exit 0" || no "opt-in: rc=$rc"
[ -s "$CT_LOG" ] && ok "opt-in: record written" || no "opt-in: no record written"
# log must contain NONE of the secret material we fed in
if grep -qE 'AWS_SECRET|wJalrXUtSECRET|sk-leaked|cookie=sess|Bearer-tok|evil|curl' "$CT_LOG" 2>/dev/null; then
  no "cost-tracker LEAKED secrets — log contains forbidden strings"
else
  ok "cost-tracker carries NO secrets (only ts/tool/sizes/ok)"
fi
# Stronger bite: every record's keys must be a subset of the fixed schema. This
# catches a regression like `rec["cmd"] = (ti.get("command") or "")[:128]` even
# if the test payload doesn't happen to contain any of the sentinel strings.
python3 - "$CT_LOG" <<'PY' >/dev/null 2>&1 && ok "cost-tracker record has ONLY schema keys (ts/tool/in_b/out_b/ok)" || no "cost-tracker record carries extra (potentially content) keys"
import json, sys
allowed = {"ts","tool","in_b","out_b","ok"}
for line in open(sys.argv[1]):
    line = line.strip()
    if not line: continue
    extra = set(json.loads(line).keys()) - allowed
    if extra: raise SystemExit(1)
PY
# bounded: every line strictly < 1024 bytes
awk '{ if (length($0) >= 1024) exit 1 }' "$CT_LOG" 2>/dev/null && ok "cost-tracker line bounded (< 1024 B)" || no "cost-tracker line unbounded"
# exactly one record per invocation
[ "$(wc -l < "$CT_LOG" 2>/dev/null)" = 1 ] && ok "cost-tracker writes exactly one record per call" || no "cost-tracker record count != 1"
# malformed JSON in -> exit 0 still
printf 'not json at all' | CMP_COST_TRACK=1 CMP_COST_LOG="$CT_DIR/bad.jsonl" bash "$CT_HOOK" >/dev/null 2>&1
[ $? = 0 ] && ok "cost-tracker handles malformed payload (exit 0)" || no "cost-tracker crashes on malformed payload"
# rotation: tiny cap forces .1 rollover, original resets
for i in 1 2 3 4 5; do
  printf '{"tool_name":"Bash","tool_input":{},"tool_response":{}}' \
    | CMP_COST_TRACK=1 CMP_COST_LOG="$CT_DIR/rot.jsonl" CMP_COST_MAX_BYTES=64 bash "$CT_HOOK" >/dev/null 2>&1
done
{ [ -f "$CT_DIR/rot.jsonl.1" ] && [ "$(wc -c < "$CT_DIR/rot.jsonl" 2>/dev/null)" -le 200 ]; } \
  && ok "cost-tracker rotates to .1 when CMP_COST_MAX_BYTES exceeded" || no "cost-tracker rotation broken"
# end-to-end self-test green (schema + rotation + malformed combined)
bash "$CT_HOOK" --self-test >/dev/null 2>&1 && ok "cost-tracker --self-test green" || no "cost-tracker --self-test FAILED"
rm -rf "$CT_DIR"

echo "== live-agent contracts =="
skip "orchestrator builds parallel-decomposition matrix before delegating"
skip "two independent streams actually spawn in parallel"
skip "closeout rejects a completion with no verification evidence"

echo
echo "tests: $PASS passed, $FAIL failed, $SKIP skipped (live)"
[ "$FAIL" -eq 0 ]
