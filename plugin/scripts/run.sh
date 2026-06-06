#!/usr/bin/env bash
# completely :: run — drive `bd ready` with ONE engine, two modes (the autonomy dial).
#
#   unattended (Ralph-style): a fresh `claude -p` per iteration reading the Beads-aware overlay
#     prompt; ONE task per iteration; stop when `bd ready` is empty. This fixes two Ralph gaps:
#       • the done-definition is real (queue empty), not a vibe-loop;
#       • NO `--dangerously-skip-permissions` — the completely guard hook + an allowlist gate
#         dangerous ops instead (override the invocation via CMP_CLAUDE_CMD if you must).
#     It does NOT edit Ralph's files — it points a loop at our overlay prompt (overlay, not patch).
#
#   supervised: hand off to GSD's wave executor (interactive); completely gates + evaluator run
#     underneath either way.
#
# Parallelism (CMP_PARALLEL, default 4): each iteration the parent reads `bd ready`, greedily picks
# tasks whose `metadata.write_zone`s are DISJOINT from every running worker (and from each other),
# pre-claims each via `bd update --claim`, and spawns up to N fresh `claude -p` workers in parallel
# — each told its assigned task via an injected header. Same-write-zone tasks SERIALIZE (the next
# one waits for the current to finish). Beads stays the spine; the queue is still empty-when-done.
# Set CMP_PARALLEL=1 to fall back to strictly one-at-a-time (legacy flow). The worker's own commit
# step still uses `bd merge-slot` for the rare cross-zone file collision.
#
# Backend for `cmpl run` and the `/completely:run` skill.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT="${CMP_RUN_PROMPT:-$ROOT/overlays/ralph/PROMPT_build.completely.md}"
CLAUDE_CMD="${CMP_CLAUDE_CMD:-claude -p --permission-mode acceptEdits}"
MODE=unattended; MAX=0; DRY=0; SELF_TEST=0
PARALLEL="${CMP_PARALLEL:-4}"

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)      MODE="${2:-}"; shift 2 ;;
    --max)       MAX="${2:-0}"; shift 2 ;;
    --parallel)  PARALLEL="${2:-1}"; shift 2 ;;
    --dry-run)   DRY=1; shift ;;
    --self-test) SELF_TEST=1; shift ;;
    -h|--help)
      echo "cmpl run [--mode unattended|supervised] [--max N] [--parallel N] [--dry-run] [--self-test]"
      echo "  CMP_PARALLEL=N    max concurrent workers (default 4; 1 = legacy serial flow)"
      echo "  CMP_BENCH_LOG=...  forces PARALLEL=1 to avoid concurrent-write races on the log"
      exit 0 ;;
    *) echo "run: unknown arg '$1'" >&2; exit 1 ;;
  esac
done

# bench mode collects each worker's JSON output to one log file; concurrent appends would interleave
# JSON objects. Force serial there. Operators can opt out only by reducing PARALLEL explicitly.
if [ -n "${CMP_BENCH_LOG:-}" ] && [ "$PARALLEL" -gt 1 ]; then
  echo "run: CMP_BENCH_LOG set — forcing --parallel 1 to keep the bench log race-free." >&2
  PARALLEL=1
fi

# ---------- dispatch helpers (pure Python, no side effects — testable via --self-test) ----------
# Reads ready JSON + the running-zones set from env, prints space-separated task IDs to dispatch
# now. The selector is greedy in priority order: keep a task only if its write_zone is disjoint
# from every running zone AND from every already-selected zone in this batch. A task with NO
# declared write_zone is treated as a global zone (serialized as if it touches everything) — that
# matches "stay inside the write-zone" being a worker-contract requirement.
#
# Inputs (env): CMP_READY_JSON (json text), CMP_RUNNING_ZONES_JSON (json [[...]] of zone lists),
#               CMP_SLOTS_FREE (int), CMP_DEBUG (1 to also emit a per-task decision trace).
_dispatch_py='
import json, os, sys
ready_raw = os.environ.get("CMP_READY_JSON","[]")
running = json.loads(os.environ.get("CMP_RUNNING_ZONES_JSON","[]"))
slots = int(os.environ.get("CMP_SLOTS_FREE","1"))
debug = os.environ.get("CMP_DEBUG","") == "1"

def zones_overlap(a, b):
    # "no declared write_zone" sentinel is the empty list — treat as the global zone (overlaps all).
    if a == [] or b == []:
        return True
    for pa in a:
        pa_n = pa.rstrip("/")
        for pb in b:
            pb_n = pb.rstrip("/")
            if pa_n == pb_n: return True
            if pa_n.startswith(pb_n + "/"): return True
            if pb_n.startswith(pa_n + "/"): return True
    return False

try:
    issues = json.loads(ready_raw)
except Exception:
    issues = []
issues = issues if isinstance(issues, list) else issues.get("issues", [])

picked, picked_zones, trace = [], [], []
for it in issues:
    if slots <= 0: break
    if it.get("issue_type") == "epic":
        continue
    if "checkpoint" in (it.get("labels") or []):
        trace.append((it.get("id"), "skip:checkpoint")); continue
    if it.get("status") not in (None, "open"):
        continue
    md = it.get("metadata") or {}
    zone = md.get("write_zone") or []
    if not isinstance(zone, list):
        zone = []
    if any(zones_overlap(zone, z) for z in running):
        trace.append((it.get("id"), "wait:overlap-running")); continue
    if any(zones_overlap(zone, z) for z in picked_zones):
        trace.append((it.get("id"), "wait:overlap-batch")); continue
    picked.append(it.get("id"))
    picked_zones.append(zone)
    slots -= 1
    trace.append((it.get("id"), "dispatch:" + (",".join(zone) if zone else "GLOBAL")))

# stdout: space-separated IDs (parent reads this). stderr (if CMP_DEBUG): one decision per line.
print(" ".join(picked))
if debug:
    for tid, reason in trace:
        sys.stderr.write(f"  · {tid}\t{reason}\n")
print(json.dumps(picked_zones), file=sys.stderr if not debug else sys.stderr)
'

# Resolve a task's write_zone (JSON array) by ID. Empty array means undeclared (global).
_zone_for_py='
import json, os, sys
tid = os.environ["CMP_LOOKUP_ID"]
ready_raw = os.environ.get("CMP_READY_JSON","[]")
try: data = json.loads(ready_raw)
except Exception: data = []
data = data if isinstance(data, list) else data.get("issues", [])
for it in data:
    if it.get("id") == tid:
        md = it.get("metadata") or {}
        z = md.get("write_zone") or []
        print(json.dumps(z if isinstance(z, list) else []))
        sys.exit(0)
print("[]")
'

dispatch_ids() {
  # Args: $1=ready_json $2=running_zones_json $3=slots_free
  CMP_READY_JSON="$1" CMP_RUNNING_ZONES_JSON="$2" CMP_SLOTS_FREE="$3" \
    python3 -c "$_dispatch_py" 2>/dev/null
}

zone_for() {
  # Args: $1=ready_json $2=task_id  → echoes a JSON array
  CMP_READY_JSON="$1" CMP_LOOKUP_ID="$2" python3 -c "$_zone_for_py"
}

# ---------- self-test: prove disjoint-parallel + same-zone-serial WITHOUT calling claude ----------
if [ "$SELF_TEST" = 1 ]; then
  echo "run/self-test: dispatcher unit"
  fail=0
  # Case 1: two disjoint tasks should both dispatch in one batch (slots=2).
  R1='[
    {"id":"t-a","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/scripts/run.sh"]}},
    {"id":"t-b","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/hooks/foo.sh"]}}
  ]'
  got="$(dispatch_ids "$R1" '[]' 2)"
  [ "$got" = "t-a t-b" ] && echo "  PASS disjoint tasks dispatch together (got: '$got')" \
    || { echo "  FAIL disjoint dispatch (got: '$got' want 't-a t-b')"; fail=1; }

  # Case 2: same write_zone → second waits (only first dispatches in this batch).
  R2='[
    {"id":"s-a","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/scripts/run.sh"]}},
    {"id":"s-b","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/scripts/run.sh"]}}
  ]'
  got="$(dispatch_ids "$R2" '[]' 4)"
  [ "$got" = "s-a" ] && echo "  PASS same-zone serializes (got: '$got')" \
    || { echo "  FAIL same-zone (got: '$got' want 's-a')"; fail=1; }

  # Case 3: directory-prefix overlap (one path is a parent of another).
  R3='[
    {"id":"p-a","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/scripts/"]}},
    {"id":"p-b","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/scripts/lint.sh"]}},
    {"id":"p-c","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/core/flow.md"]}}
  ]'
  got="$(dispatch_ids "$R3" '[]' 4)"
  [ "$got" = "p-a p-c" ] && echo "  PASS prefix overlap detected, unrelated proceeds (got: '$got')" \
    || { echo "  FAIL prefix overlap (got: '$got' want 'p-a p-c')"; fail=1; }

  # Case 4: undeclared write_zone is a global zone — serializes with everything.
  R4='[
    {"id":"g-a","issue_type":"task","status":"open","metadata":{}},
    {"id":"g-b","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/x"]}}
  ]'
  got="$(dispatch_ids "$R4" '[]' 4)"
  [ "$got" = "g-a" ] && echo "  PASS undeclared zone serializes globally (got: '$got')" \
    || { echo "  FAIL undeclared zone (got: '$got' want 'g-a')"; fail=1; }

  # Case 5: respects already-running zones.
  R5='[
    {"id":"r-a","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/scripts/run.sh"]}},
    {"id":"r-b","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/core/flow.md"]}}
  ]'
  got="$(dispatch_ids "$R5" '[["plugin/scripts/run.sh"]]' 4)"
  [ "$got" = "r-b" ] && echo "  PASS running zone blocks new overlap (got: '$got')" \
    || { echo "  FAIL running-zone block (got: '$got' want 'r-b')"; fail=1; }

  # Case 6: respects slot budget (only 1 slot free → 1 task even when more are disjoint).
  got="$(dispatch_ids "$R1" '[]' 1)"
  [ "$got" = "t-a" ] && echo "  PASS slot budget honored (got: '$got')" \
    || { echo "  FAIL slot budget (got: '$got' want 't-a')"; fail=1; }

  # Case 7: checkpoint label skipped (human gate, not a worker task).
  R7='[
    {"id":"c-a","issue_type":"task","status":"open","labels":["checkpoint"],"metadata":{"write_zone":["x"]}},
    {"id":"c-b","issue_type":"task","status":"open","metadata":{"write_zone":["y"]}}
  ]'
  got="$(dispatch_ids "$R7" '[]' 4)"
  [ "$got" = "c-b" ] && echo "  PASS checkpoint task not dispatched (got: '$got')" \
    || { echo "  FAIL checkpoint skip (got: '$got' want 'c-b')"; fail=1; }

  if [ "$fail" = 0 ]; then echo "run/self-test: OK"; exit 0; else echo "run/self-test: FAILED"; exit 1; fi
fi

command -v bd >/dev/null 2>&1 || { echo "run: bd (beads) not installed" >&2; exit 1; }
[ -d .beads ] || { echo "run: no .beads here — run from a repo with 'bd init'" >&2; exit 1; }

# Land-step guard: the engine commits per task BEFORE closing it (commit-before-close). With no
# usable git author identity that commit silently fails — and a task could close with uncommitted
# code (observed during dogfood). Ensure a repo-local identity up front so per-task commits always
# land (override via your own git config). Deterministic preflight; per-task ordering still lives
# in the task engine.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
   && [ -z "$(git config user.email 2>/dev/null)" ]; then
  git config user.email "completely-agent@localhost"
  git config user.name "completely agent"
  echo "run: no git identity found — set repo-local fallback (completely agent) so per-task commits land."
fi

# count ready WORK (exclude the epic container itself)
ready_count() {
  bd ready --json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: d=[]
d=d if isinstance(d,list) else d.get("issues",[])
print(sum(1 for i in d if i.get("issue_type")!="epic"))'
}

if [ "$MODE" = supervised ]; then
  echo "run/supervised: Beads-driven waves (ready front from 'bd swarm status' / 'bd ready')."
  CP="$(bd ready --json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: d=[]
d=d if isinstance(d,list) else d.get("issues",[])
for it in d:
    if it.get("issue_type")=="epic": continue
    if "checkpoint" in (it.get("labels") or []):
        print(it["id"], it.get("title",""), sep="  "); break
')"
  if [ -n "$CP" ]; then
    echo "  ⏸ checkpoint pending: $CP"
    echo "     verify it, then: bd close <id>  (downstream waves stay blocked until then)"
    exit 0
  fi
  NEXT="$(bd ready --json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: d=[]
d=d if isinstance(d,list) else d.get("issues",[])
for it in d:
    if it.get("issue_type")=="epic": continue
    if "checkpoint" in (it.get("labels") or []): continue
    print(it["id"]); break
')"
  if [ -z "$NEXT" ]; then echo "  bd ready is empty — nothing to do."; exit 0; fi
  echo "  next task: $NEXT — its contract:"
  bd show "$NEXT" 2>/dev/null | sed -n '1,18p' | sed 's/^/    /'
  echo "  → run the FULL task engine on THIS ONE task (skill /completely:control · core/task-engine.md):"
  echo "    understand(map/research) → plan-check → parallel subagents (merge-slot) → TDD + craft skills"
  echo "    → cmpl check + cmpl lint → code-reviewer + security-reviewer → gsd-verifier + evaluator"
  echo "    → evidence comment → bd close (only if ACCEPTED). Pause at gates; STOP after this one task."
  exit 0
fi

[ -f "$PROMPT" ] || { echo "run: overlay prompt missing: $PROMPT" >&2; exit 1; }

closed_count() { bd list --status closed --json 2>/dev/null | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: d=[]
print(len(d if isinstance(d,list) else d.get("issues",[])))'; }

# ---------- worker spawn (one fresh claude -p; reads the assigned task ID from injected header) ----
# We pre-claim the task in the parent so concurrent workers can't race for the same ready item, then
# prepend a small header to the overlay prompt over stdin. The header is the source of truth for
# WHICH task the worker should work on — the rest of the prompt (step 0 onward) still applies.
spawn_worker() {
  # $1 = task_id  $2 = log_file_path
  local tid="$1" log="$2"
  {
    printf '<<COMPLETELY_DISPATCH>>\n'
    printf 'Your assigned task: %s\n' "$tid"
    printf 'The parent has ALREADY claimed it for you (bd update %s --claim).\n' "$tid"
    printf 'Skip the selection part of step 0 — read THIS task directly:\n'
    printf '  bd show %s\n' "$tid"
    printf 'Then proceed step 1 (UNDERSTAND) onward. Stay inside its write-zone.\n'
    printf 'If you cannot proceed: bd update %s --status blocked + a comment with the reason.\n' "$tid"
    printf '<<END_DISPATCH>>\n\n'
    cat "$PROMPT"
  } | $CLAUDE_CMD >"$log" 2>&1
}

# ---------- main loop: rolling parallel dispatch over `bd ready` ----------
# Bash gotcha: under `set -u`, `${#assoc[@]}` errors on a never-assigned-to associative array. Keep
# an explicit NRUN counter alongside the maps so the loop arithmetic is always defined.
declare -A PID_TASK=() PID_ZONE=() PID_LOG=()
NRUN=0
i=0; stall=0; STALL_MAX="${CMP_STALL:-3}"; prev_closed="$(closed_count)"

# zones currently in flight, as a JSON array of arrays — fed to dispatch_ids each iteration.
running_zones_json() {
  local pid lines=""
  for pid in ${!PID_ZONE[@]+"${!PID_ZONE[@]}"}; do
    lines+="${PID_ZONE[$pid]}"$'\n'
  done
  printf '%s' "$lines" | python3 -c '
import json, sys
xs = []
for line in sys.stdin.read().splitlines():
    if not line.strip(): continue
    try: xs.append(json.loads(line))
    except Exception: pass
print(json.dumps(xs))'
}

reap_finished() {
  # Walk our tracked PIDs once; any that are no longer alive get reaped.
  local pid
  # `${!PID_TASK[@]+...}` keeps `set -u` happy when the map has never been written to.
  for pid in ${!PID_TASK[@]+"${!PID_TASK[@]}"}; do
    if ! kill -0 "$pid" 2>/dev/null; then
      local tid="${PID_TASK[$pid]}" log="${PID_LOG[$pid]}"
      wait "$pid" 2>/dev/null || true
      echo "run: worker pid=$pid task=$tid finished — log tail:"
      [ -f "$log" ] && tail -8 "$log" | sed 's/^/    /' || echo "    (no log)"
      [ -f "$log" ] && rm -f "$log"
      unset 'PID_TASK[$pid]' 'PID_ZONE[$pid]' 'PID_LOG[$pid]'
      NRUN=$((NRUN > 0 ? NRUN - 1 : 0))
    fi
  done
}

while true; do
  # Reap any finished workers (non-blocking) so freed slots get refilled on this tick.
  reap_finished || true

  n="$(ready_count)"; n="${n:-0}"
  if [ "$n" -le 0 ] && [ "$NRUN" -eq 0 ]; then
    echo "run: bd ready is empty — done after $i iteration(s)."; break
  fi

  free=$(( PARALLEL - $NRUN ))
  if [ "$free" -le 0 ]; then
    # Saturated — block until at least one worker exits, then loop.
    wait -n 2>/dev/null || true
    reap_finished || true
    continue
  fi

  # Snapshot the queue + currently-running zones, then ask the dispatcher who to send next.
  ready_json="$(bd ready --json 2>/dev/null || echo '[]')"
  rzj="$(running_zones_json)"
  ids="$(dispatch_ids "$ready_json" "$rzj" "$free")"

  if [ -z "$ids" ]; then
    # Nothing else dispatchable right now (everything pending overlaps something running, or queue
    # is fully empty). If workers are alive, wait one out and retry. If not, we're truly done.
    if [ "$NRUN" -gt 0 ]; then
      wait -n 2>/dev/null || true
      reap_finished || true
      continue
    else
      echo "run: bd ready is empty — done after $i iteration(s)."; break
    fi
  fi

  for tid in $ids; do
    zone_json="$(zone_for "$ready_json" "$tid")"
    i=$((i+1))
    echo "run: iteration $i — dispatch task=$tid zone=$zone_json (running=$NRUN of $PARALLEL)"

    if [ "$DRY" = 1 ]; then
      # Trace-only mode: show the dispatch decision without claiming or spawning. Loop once, then
      # exit so callers can capture the plan. Preserves the legacy dry-run shape (top of queue +
      # would-run command) and extends it with the parallel plan.
      echo "  [dry-run] would claim:     bd update $tid --claim"
      echo "  [dry-run] would spawn:     cat \"$PROMPT\" | $CLAUDE_CMD   (with task=$tid header)"
      echo "  [dry-run] write_zone:      $zone_json"
      continue
    fi

    if ! bd update "$tid" --claim >/dev/null 2>&1; then
      echo "  · claim failed for $tid (another agent grabbed it?) — skipping this iteration"
      continue
    fi

    log="$(mktemp /tmp/cmpl-run-XXXXXX.log)"
    if [ -n "${CMP_BENCH_LOG:-}" ]; then
      # Serial bench mode: capture the full JSON output into the shared log (PARALLEL was forced 1
      # at startup, so no race).
      _out="$(spawn_worker "$tid" "$log" && cat "$log")"
      printf '%s\n' "$_out" >> "$CMP_BENCH_LOG"
      printf '%s\n' "$_out" | tail -8
      rm -f "$log"
    else
      spawn_worker "$tid" "$log" &
      pid=$!
      PID_TASK[$pid]="$tid"
      PID_ZONE[$pid]="$zone_json"
      PID_LOG[$pid]="$log"
      NRUN=$((NRUN + 1))
    fi
  done

  if [ "$DRY" = 1 ]; then
    echo "  [dry-run] single pass only; no execution."
    break
  fi

  # push only when asked (CMP_PUSH=1) — default is local commits, so a half-done run never
  # pushes broken intermediate state to the remote.
  [ "${CMP_PUSH:-0}" = 1 ] && { git push >/dev/null 2>&1 || true; }

  # stall detector: bail if no task has closed for STALL_MAX iterations (a crashing/no-op worker or
  # an unresolvable task) — don't burn the whole --max budget making zero progress. We check this
  # only when nothing is in flight, otherwise an active worker counts as progress in progress.
  if [ "$NRUN" -eq 0 ]; then
    now_closed="$(closed_count)"
    if [ "${now_closed:-0}" -gt "${prev_closed:-0}" ]; then stall=0; else stall=$((stall + 1)); fi
    prev_closed="$now_closed"
    if [ "$stall" -ge "$STALL_MAX" ]; then
      echo "run: no task closed in $STALL_MAX iteration(s) — stopping (stuck/crashing worker or unresolvable task)."
      echo "     inspect 'bd list --status in_progress' for abandoned claims (reset: bd update <id> --status open)."
      break
    fi
  fi
  if [ "$MAX" -gt 0 ] && [ "$i" -ge "$MAX" ]; then
    echo "run: reached max $MAX iteration(s) — draining in-flight workers."
    while [ "$NRUN" -gt 0 ]; do
      wait -n 2>/dev/null || true; reap_finished || true
    done
    break
  fi
done
