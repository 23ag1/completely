#!/usr/bin/env bash
# claude-harness :: quality-gate (PostToolUse on Edit|Write|MultiEdit)
#
# Runs fast deterministic checks (format + lint, optional typecheck) on the file the
# agent just edited, and feeds failures BACK into the agent's context so it self-corrects
# on the next step. Non-blocking by design: exit 0 always, so a failing check informs
# rather than halts (the commit-time gate / evaluator is where FAIL stops the work).
#
# Stack-agnostic: detects language by extension, runs a tool only if it's installed,
# skips gracefully otherwise. Projects can fully override by providing an executable
# <project>/.claude/harness/quality-gate.local.sh (it receives the edited path as $1).
#
# Tests are intentionally NOT run here (too slow per-edit) — they belong to the
# pre-commit/CI gate and the evaluator. Typecheck is opt-in via HARNESS_TYPECHECK=1.
set -uo pipefail

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

# find nearest ancestor dir containing $1, starting from the file's directory
find_up() {
  local marker="$1" d; d="$(cd "$(dirname "$FILE")" 2>/dev/null && pwd)" || return 1
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -e "$d/$marker" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  return 1
}

run() { # run() "label" cmd...  — echo a FAIL marker if the command fails
  local label="$1"; shift
  "$@" >/tmp/harness-qg.out 2>&1 || {
    say "$label FAILED — fix before continuing:"
    sed 's/^/    /' /tmp/harness-qg.out | head -40
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

exit 0
