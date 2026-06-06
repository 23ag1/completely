#!/usr/bin/env bash
# claude-harness :: quality-gate (PostToolUse on Edit|Write|MultiEdit)
#
# Runs fast deterministic checks (format + lint, optional typecheck) on the file the
# agent just edited, and feeds failures BACK into the agent's context so it self-corrects
# on the next step. Non-blocking by design: exit 0 always, so a failing check informs
# rather than halts (the commit-time gate / evaluator is where FAIL stops the work).
#
# NCR-on-fail (ECC quality-nonconformance pattern, ported, OPTIONAL here): when a per-edit
# check fails *inside a worker context* — env `CMP_WORKER_BEAD=<id>` set or exactly one
# in_progress task in this Beads DB — and `CMP_NCR_QG=1`, a structured NCR comment is
# recorded on that bead so the worker leaves an auditable trail rather than silently
# absorbing the failure. Auto-block (`CMP_NCR_BLOCK=1`) is OFF by default because this
# hook fires on every edit and would over-block on transient mid-iteration failures —
# `cmpl lint` is the authoritative blocking gate (see plugin/scripts/lint.sh).
#
# Stack-agnostic: detects language by extension, runs a tool only if it's installed,
# skips gracefully otherwise. Projects can fully override by providing an executable
# <project>/.claude/harness/quality-gate.local.sh (it receives the edited path as $1).
#
# Tests are intentionally NOT run here (too slow per-edit) — they belong to the
# pre-commit/CI gate and the evaluator. Typecheck is opt-in via HARNESS_TYPECHECK=1.
set -uo pipefail

# ---------- self-test (mirrors the NCR-record path for the per-edit hook) ----------
if [ "${1:-}" = "--self-test" ]; then
  D=$(mktemp -d /tmp/cmpl-qg-st.XXXXXX); trap 'rm -rf "$D"' EXIT
  ( cd "$D" && git init -q && bd init proj --stealth >/dev/null 2>&1 ) || { echo "FAIL init"; exit 1; }
  ( cd "$D" && bd create "qg test" -t task --acceptance a --design d --metadata '{"write_zone":["a.py"]}' >/dev/null 2>&1 )
  BID=$( cd "$D" && bd list --json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin); d=d if isinstance(d,list) else d.get("issues",[])
print(d[0]["id"] if d else "")' )
  ( cd "$D" && bd update "$BID" --claim >/dev/null 2>&1 )
  # Simulate the helper directly (we don't need to actually fail a real linter — the goal of the
  # self-test is to prove the NCR recorder fires correctly when invoked).
  ( cd "$D" && CMP_WORKER_BEAD="$BID" CMP_NCR_QG=1 bash -c "
      $(sed -n '/^emit_ncr_qg()/,/^}$/p' "$0")
      echo 'simulated lint failure' > /tmp/cmpl-qg-st.out
      emit_ncr_qg 'self-test' 'simulated check failure' /tmp/cmpl-qg-st.out 0
  " 2>/dev/null )
  CNT=$( cd "$D" && bd comments "$BID" 2>/dev/null | grep -c 'NCR ' )
  STATUS=$( cd "$D" && bd show "$BID" --json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except: d=None
if isinstance(d,list) and d: d=d[0]
print(d.get("status","") if isinstance(d,dict) else "")' )
  fails=0
  [ "${CNT:-0}" -ge 1 ]            && echo "  PASS NCR comment recorded by quality-gate" || { echo "  FAIL no NCR (cnt=$CNT)"; fails=$((fails+1)); }
  [ "$STATUS" = "in_progress" ]    && echo "  PASS bead NOT auto-blocked (record-only mode)" || { echo "  FAIL unexpected status ($STATUS)"; fails=$((fails+1)); }
  # Auto-block escalation path
  ( cd "$D" && CMP_WORKER_BEAD="$BID" CMP_NCR_QG=1 bash -c "
      $(sed -n '/^emit_ncr_qg()/,/^}$/p' "$0")
      echo 'persistent failure' > /tmp/cmpl-qg-st.out
      emit_ncr_qg 'self-test' 'escalated' /tmp/cmpl-qg-st.out 1
  " 2>/dev/null )
  STATUS2=$( cd "$D" && bd show "$BID" --json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except: d=None
if isinstance(d,list) and d: d=d[0]
print(d.get("status","") if isinstance(d,dict) else "")' )
  [ "$STATUS2" = "blocked" ] && echo "  PASS CMP_NCR_BLOCK escalates to blocked" || { echo "  FAIL no escalation ($STATUS2)"; fails=$((fails+1)); }
  rm -f /tmp/cmpl-qg-st.out
  if [ "$fails" = 0 ]; then echo "quality-gate self-test: OK"; exit 0; else echo "quality-gate self-test: $fails failure(s)"; exit 1; fi
fi

INPUT="$(cat 2>/dev/null || true)"

# --- parse the edited file path from the hook payload (jq if present, else python3) ---
FILE=""
if command -v jq >/dev/null 2>&1; then
  FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
elif command -v python3 >/dev/null 2>&1; then
  FILE="$(printf '%s' "$INPUT" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path","") or "")
except Exception:
    print("")' 2>/dev/null)"
fi

PROJ="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# --- project override hook ------------------------------------------------------------
if [ -x "$PROJ/.claude/harness/quality-gate.local.sh" ]; then
  "$PROJ/.claude/harness/quality-gate.local.sh" "$FILE" || true
  exit 0
fi

[ -z "$FILE" ] && exit 0
[ -f "$FILE" ] || exit 0

say() { printf '%s\n' "::harness/quality-gate:: $*"; }

# ---------- NCR helpers (record-only by default; block on explicit escalation) ----------
# Mirrors plugin/scripts/lint.sh; per-edit hook stays exit-0 even on fail by design.
emit_ncr_qg() {
  # $1=stage  $2=reason  $3=output_tail_file  $4=block(1|0)
  local stage="$1" reason="$2" out_file="$3" block="${4:-0}"
  [ "${CMP_NCR_QG:-0}" = "1" ] || return 0
  [ "${CMP_NCR:-1}" = "0" ] && return 0
  command -v bd >/dev/null 2>&1 || return 0
  [ -d .beads ] || return 0
  local bead=""
  if [ -n "${CMP_WORKER_BEAD:-}" ]; then
    bead="$CMP_WORKER_BEAD"
  else
    bead="$(bd list --status in_progress --json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except: sys.exit(0)
d=d if isinstance(d,list) else d.get("issues",[])
if len(d)==1: print(d[0].get("id","") or "")
' 2>/dev/null)"
  fi
  [ -n "$bead" ] || return 0
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local tail_text=""
  if [ -n "$out_file" ] && [ -s "$out_file" ]; then
    tail_text="$(tail -n 20 "$out_file" 2>/dev/null | sed 's/^/    /')"
  fi
  local mode; mode="$([ "$block" = "1" ] && printf 'status -> blocked' || printf 'recorded (no auto-block)')"
  local msg
  msg="$(printf 'NCR %s  quality-gate FAIL (per-edit)\n  stage: %s\n  reason: %s\n  bead:   %s\n  file:   %s\n  output (tail):\n%s\n  containment: %s' \
    "$ts" "$stage" "$reason" "$bead" "${FILE:-n/a}" "$tail_text" "$mode")"
  bd comment "$bead" "$msg" >/dev/null 2>&1 || true
  [ "$block" = "1" ] && bd update "$bead" --status blocked >/dev/null 2>&1 || true
  return 0
}

# find nearest ancestor dir containing $1, starting from the file's directory
find_up() {
  local marker="$1" d; d="$(cd "$(dirname "$FILE")" 2>/dev/null && pwd)" || return 1
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -e "$d/$marker" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  return 1
}

GATE_FAIL=0
GATE_OUT="$(mktemp)"
trap 'rm -f "$GATE_OUT" /tmp/harness-qg.out' EXIT

run() { # run() "label" cmd...  — echo a FAIL marker if the command fails
  local label="$1"; shift
  "$@" >/tmp/harness-qg.out 2>&1 || {
    say "$label FAILED — fix before continuing:"
    sed 's/^/    /' /tmp/harness-qg.out | head -40
    cat /tmp/harness-qg.out >> "$GATE_OUT" 2>/dev/null || true
    GATE_FAIL=1
    return 1
  }
}

check_js() {
  local dir bin; dir="$(find_up package.json)" || { say "skip JS (no package.json up-tree)"; return; }
  bin="$dir/node_modules/.bin"
  [ -x "$bin/prettier" ] && "$bin/prettier" --write "$FILE" >/dev/null 2>&1 || true
  [ -x "$bin/eslint" ]   && run "eslint $FILE"      "$bin/eslint" "$FILE"
  if [ "${HARNESS_TYPECHECK:-0}" = "1" ] && [ -x "$bin/tsc" ]; then
    ( cd "$dir" && run "tsc --noEmit" "$bin/tsc" --noEmit )
  fi
}

check_py() {
  local dir; dir="$(find_up pyproject.toml || find_up setup.cfg || git rev-parse --show-toplevel 2>/dev/null)"
  [ -n "$dir" ] || dir="$PROJ"
  local ruff mypy
  ruff="$(command -v ruff || echo "$dir/.venv/bin/ruff")"
  mypy="$(command -v mypy || echo "$dir/.venv/bin/mypy")"
  if [ -x "$ruff" ]; then
    "$ruff" format "$FILE" >/dev/null 2>&1 || true
    run "ruff check $FILE" "$ruff" check "$FILE"
  else
    say "skip ruff (not installed)"
  fi
  if [ "${HARNESS_TYPECHECK:-0}" = "1" ] && [ -x "$mypy" ]; then
    ( cd "$dir" && run "mypy" "$mypy" "$FILE" )
  fi
}

case "$FILE" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) check_js ;;
  *.py)                              check_py ;;
  *.go)   command -v gofmt >/dev/null 2>&1 && { gofmt -w "$FILE" 2>/dev/null || true; command -v go >/dev/null 2>&1 && run "go vet" go vet "$FILE"; } ;;
  *.rs)   command -v rustfmt >/dev/null 2>&1 && { rustfmt "$FILE" 2>/dev/null || true; } ;;
  *)      : ;;  # unknown extension — nothing to do
esac

# Record an NCR if any per-edit check failed and we're inside a worker context that opted in.
if [ "$GATE_FAIL" = 1 ]; then
  emit_ncr_qg "per-edit" "post-edit check failed on $FILE" "$GATE_OUT" "${CMP_NCR_BLOCK:-0}"
fi

exit 0
