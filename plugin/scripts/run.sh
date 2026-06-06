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
# Backend for `cmpl run` and the `/completely:run` skill.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT="${CMP_RUN_PROMPT:-$ROOT/overlays/ralph/PROMPT_build.completely.md}"
CLAUDE_CMD="${CMP_CLAUDE_CMD:-claude -p --permission-mode acceptEdits}"
MODE=unattended; MAX=0; DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)    MODE="${2:-}"; shift 2 ;;
    --max)     MAX="${2:-0}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) echo "cmpl run [--mode unattended|supervised] [--max N] [--dry-run]"; exit 0 ;;
    *) echo "run: unknown arg '$1'" >&2; exit 1 ;;
  esac
done

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

i=0; stall=0; STALL_MAX="${CMP_STALL:-3}"; prev_closed="$(closed_count)"
while true; do
  n="$(ready_count)"; n="${n:-0}"
  if [ "$n" -le 0 ]; then echo "run: bd ready is empty — done after $i iteration(s)."; break; fi
  i=$((i+1))
  echo "run: iteration $i — $n ready task(s) — mode=unattended"
  if [ "$DRY" = 1 ]; then
    echo "  [dry-run] would run:  cat \"$PROMPT\" | $CLAUDE_CMD   (fresh context, ONE task)"
    echo "  [dry-run] top of queue:"; bd ready 2>/dev/null | sed -n '1p'
    echo "  [dry-run] single pass only; no execution."
    break
  fi
  # shellcheck disable=SC2086
  if [ -n "${CMP_BENCH_LOG:-}" ]; then
    # bench mode: capture the inner agent's JSON result (claude -p --output-format json) so the bench
    # harness can sum cost for the 'completely' arm. Still show a tail for the operator.
    _out="$(cat "$PROMPT" | $CLAUDE_CMD 2>/dev/null)"; printf '%s\n' "$_out" >> "$CMP_BENCH_LOG"
    printf '%s\n' "$_out" | tail -8
  else
    cat "$PROMPT" | $CLAUDE_CMD 2>&1 | tail -8 || true
  fi
  # push only when asked (CMP_PUSH=1) — default is local commits, so a half-done run never
  # pushes broken intermediate state to the remote.
  [ "${CMP_PUSH:-0}" = 1 ] && { git push >/dev/null 2>&1 || true; }
  # stall detector: bail if no task has closed for STALL_MAX iterations (a crashing/no-op worker or
  # an unresolvable task) — don't burn the whole --max budget making zero progress.
  now_closed="$(closed_count)"
  if [ "${now_closed:-0}" -gt "${prev_closed:-0}" ]; then stall=0; else stall=$((stall + 1)); fi
  prev_closed="$now_closed"
  if [ "$stall" -ge "$STALL_MAX" ]; then
    echo "run: no task closed in $STALL_MAX iteration(s) — stopping (stuck/crashing worker or unresolvable task)."
    echo "     inspect 'bd list --status in_progress' for abandoned claims (reset: bd update <id> --status open)."
    break
  fi
  if [ "$MAX" -gt 0 ] && [ "$i" -ge "$MAX" ]; then echo "run: reached max $MAX iteration(s)."; break; fi
done
