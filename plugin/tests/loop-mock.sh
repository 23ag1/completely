#!/usr/bin/env bash
# completely :: loop-mock — exercise the auto loop with the mock worker (no real agent) to surface
# orchestration problems deterministically. Reports per-scenario; FINDING = a real weakness.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMPL="$ROOT/bin/cmpl"
WORKER="$ROOT/tests/mock-worker.sh"

mkbd() {  # mkbd <n> <chain|indep> -> tempdir with n tasks
  local n="$1" mode="${2:-indep}" d prev=""
  d=$(mktemp -d /tmp/loopmockXXXXXX)
  (
    cd "$d" && git init -q 2>/dev/null && git commit -q --allow-empty -m init 2>/dev/null
    bd init proj --stealth >/dev/null 2>&1
    for i in $(seq 1 "$n"); do
      id=$(bd create "task $i" -t task --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')
      [ "$mode" = chain ] && [ -n "$prev" ] && bd dep add "$id" --depends-on "$prev" >/dev/null 2>&1
      prev="$id"
    done
  )
  printf '%s' "$d"
}
cnt() { ( cd "$1" && bd list --status "$2" --json 2>/dev/null | python3 -c 'import json,sys;d=json.load(sys.stdin);print(len(d if isinstance(d,list) else d.get("issues",[])))' ); }
commits() { ( cd "$1" && git log --oneline 2>/dev/null | grep -c 'mock:' ); }
run() { ( cd "$1" && CMP_CLAUDE_CMD="bash $WORKER" MOCK_MODE="$2" timeout 60 bash "$CMPL" auto --max "$3" >/tmp/loopmock.log 2>&1; echo $? ); }

echo "===== S1 happy: 3 chained tasks, good worker ====="
D=$(mkbd 3 chain); rc=$(run "$D" good 8)
c=$(cnt "$D" closed); k=$(commits "$D")
echo "  exit=$rc  closed=$c/3  commits=$k"
{ [ "$c" = 3 ] && [ "$k" = 3 ]; } && echo "  PASS — all landed, commit-before-close (commits==closed)" || echo "  FINDING — expected 3 closed + 3 commits"
rm -r "$D" 2>/dev/null

echo "===== S2 block: worker blocks every task ====="
D=$(mkbd 3 indep); rc=$(run "$D" block 8)
echo "  exit=$rc  closed=$(cnt "$D" closed)  blocked=$(cnt "$D" blocked)  iters=$(grep -c 'iteration' /tmp/loopmock.log)"
[ "$rc" != 124 ] && echo "  PASS — loop terminated (no infinite loop on blocked tasks)" || echo "  FINDING — loop did not terminate (timeout)"
rm -r "$D" 2>/dev/null

echo "===== S3 die: worker claims then crashes (no close/block) ====="
D=$(mkbd 3 indep); rc=$(run "$D" die 8)
ip=$(cnt "$D" in_progress); cl=$(cnt "$D" closed)
echo "  exit=$rc  closed=$cl  in_progress=$ip  iters=$(grep -c 'iteration' /tmp/loopmock.log)"
echo "  >>> watch: do crashed tasks get stuck in_progress (lost), or re-picked forever?"
rm -r "$D" 2>/dev/null

echo "===== S4 noop: worker never makes progress ====="
D=$(mkbd 2 indep); rc=$(run "$D" noop 4)
echo "  exit=$rc  closed=$(cnt "$D" closed)  iters=$(grep -c 'iteration' /tmp/loopmock.log) (cap --max 4)"
echo "  >>> watch: loop spends all --max iterations re-running the SAME stuck task (no stuck-detector)"
rm -r "$D" 2>/dev/null

echo "===== S5 resume: commit-but-not-closed, then good worker continues ====="
D=$(mkbd 2 indep)
# one iteration where the worker commits but does NOT close (simulate interrupt after commit)
( cd "$D" && id=$(bd ready --json | python3 -c 'import json,sys;d=json.load(sys.stdin);d=d if isinstance(d,list) else d.get("issues",[]);print(d[0]["id"])')
  bd update "$id" --claim >/dev/null 2>&1; echo x > w.txt; git add w.txt
  git -c user.name=m -c user.email=m@x commit -q -m "mock: $id (interrupted before close)" 2>/dev/null )
echo "  after interrupt: commits=$(commits "$D") closed=$(cnt "$D" closed) (committed but bead still open)"
run "$D" good 8 >/dev/null
echo "  after resume:    commits=$(commits "$D") closed=$(cnt "$D" closed)/2"
echo "  >>> watch: does resume DOUBLE-commit the already-committed task (no fresh-tree guard)?"
rm -r "$D" 2>/dev/null

echo "===== done ====="
