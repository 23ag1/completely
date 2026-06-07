#!/usr/bin/env bash
# completely :: status — anytime, READ-ONLY snapshot of loop health.
#
# Complements the exit-time run-report (ovi): a loop alive? (live workers/PIDs), bead counts by
# status, orphaned claims (dead/stale worker — cva's heartbeat rule), dirty-tree files, approx spend
# this run, and a DONE / INCOMPLETE / RUNNING verdict. Pure read-only: probes processes + queries bd +
# reads git status; NEVER mutates (no claim, no reap, no git-identity preflight).
set -uo pipefail

command -v bd >/dev/null 2>&1 || { echo "cmpl status: bd (beads) not installed" >&2; exit 1; }
[ -d .beads ] || { echo "cmpl status: no .beads here — run from a repo with 'bd init'" >&2; exit 1; }

HEARTBEAT_STALE="${CMP_HEARTBEAT_STALE:-300}"

# loop alive? (read-only process probe — never kill/signal). pgrep -c already prints "0" on no
# match (and exits 1); piping `|| echo 0` would double it, so just capture + sanitize to digits.
WK=$(pgrep -fc 'claude -p --permission-mode acceptEdits' 2>/dev/null || true); WK=$(printf '%s' "$WK" | tr -dc '0-9'); WK=${WK:-0}
PAR=$(pgrep -fc 'run\.sh --mode' 2>/dev/null || true); PAR=$(printf '%s' "$PAR" | tr -dc '0-9'); PAR=${PAR:-0}
ALIVE="no"; { [ "$WK" -gt 0 ] || [ "$PAR" -gt 0 ]; } && ALIVE="yes"

NOW=$(date +%s)
DIRTY=0; DIRTY_FILES=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  DIRTY=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  DIRTY_FILES=$(git status --porcelain 2>/dev/null | head -6)
fi

# approx spend this run: best-effort from a bench/cost log of claude -p JSON results, else n/a.
SPEND="n/a (set CMP_BENCH_LOG to a claude -p --output-format json log)"
if [ -n "${CMP_BENCH_LOG:-}" ] && [ -r "${CMP_BENCH_LOG:-/nonexistent}" ]; then
  _s=$(python3 -c '
import json,sys
tot=0.0; n=0
for line in open(sys.argv[1]):
    line=line.strip()
    if not line: continue
    try: d=json.loads(line)
    except Exception: continue
    c=d.get("total_cost_usd") or d.get("cost_usd")
    if isinstance(c,(int,float)): tot+=c; n+=1
print(f"${tot:.4f} over {n} result(s)".replace("$",chr(36))) if n else print("")
' "$CMP_BENCH_LOG" 2>/dev/null)
  [ -n "$_s" ] && SPEND="$_s"
fi

BDJSON="$(bd list --json 2>/dev/null || echo '[]')"
export BDJSON NOW HEARTBEAT_STALE ALIVE WK DIRTY DIRTY_FILES SPEND
python3 - <<'PY'
import json, os
from collections import Counter
now = int(os.environ["NOW"]); stale = int(os.environ["HEARTBEAT_STALE"])
alive = os.environ["ALIVE"]; wk = os.environ.get("WK", "0")
dirty = int(os.environ["DIRTY"] or 0); dirty_files = os.environ.get("DIRTY_FILES", "")
spend = os.environ.get("SPEND", "n/a")
try: data = json.loads(os.environ["BDJSON"])
except Exception: data = []
data = data if isinstance(data, list) else data.get("issues", [])

c = Counter(); orphans = []
for i in data:
    if i.get("issue_type") == "epic":
        continue
    st = i.get("status") or "open"; c[st] += 1
    if st == "in_progress":
        m = i.get("metadata") or {}
        wid = m.get("worker_id")
        if wid:                                    # interactive claims (no worker_id) are not orphans
            hb = m.get("heartbeat"); age = now - int(hb) if hb else 10**9
            if age >= stale:
                orphans.append((i.get("id"), wid, age))

print("completely :: status")
print(f"  loop:     {'RUNNING' if alive == 'yes' else 'idle'}   (live workers={wk})")
print(f"  beads:    open={c['open']}  in_progress={c['in_progress']}  blocked={c['blocked']}  closed={c['closed']}")
if orphans:
    print(f"  orphans:  {len(orphans)} stale claim(s) (cmpl orphans --reap to recover):")
    for iid, wid, age in orphans:
        print(f"              {iid}  worker={wid}  stale={age}s")
else:
    print("  orphans:  none")
print(f"  tree:     {dirty} uncommitted file(s)")
for ln in [l for l in dirty_files.splitlines() if l.strip()][:6]:
    print(f"              {ln}")
print(f"  spend:    {spend}")

incomplete = bool(orphans) or dirty > 0 or c["in_progress"] > 0
if alive == "yes":
    print("  verdict:  RUNNING — a loop is active; re-check after it exits")
elif incomplete:
    bits = []
    if orphans: bits.append(f"{len(orphans)} orphan(s)")
    if dirty: bits.append(f"{dirty} dirty file(s)")
    if c["in_progress"]: bits.append(f"{c['in_progress']} in_progress")
    print("  verdict:  INCOMPLETE — " + ", ".join(bits) + " (do NOT assume done)")
elif c["open"] > 0:
    print(f"  verdict:  PENDING — {c['open']} task(s) ready, none in flight (run: cmpl auto)")
else:
    print("  verdict:  DONE — queue empty, no orphans, clean tree")
PY
