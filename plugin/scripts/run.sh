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
  echo "run/supervised: drive with GSD — /gsd:execute-phase <phase>."
  echo "  completely's quality-gate hook, evaluator, and the no-stub contract run underneath."
  echo "  Status stays in Beads; learnings go to bd comments (not STATE.md)."
  exit 0
fi

[ -f "$PROMPT" ] || { echo "run: overlay prompt missing: $PROMPT" >&2; exit 1; }

i=0
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
  cat "$PROMPT" | $CLAUDE_CMD 2>&1 | tail -8 || true
  git push >/dev/null 2>&1 || true
  if [ "$MAX" -gt 0 ] && [ "$i" -ge "$MAX" ]; then echo "run: reached max $MAX iteration(s)."; break; fi
done
