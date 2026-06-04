#!/usr/bin/env bash
# completely :: check — run every configured quality check in ONE pass, token-frugal output.
#
# One command instead of the agent running lint+types+tests separately (saves tokens, fixed
# sequence). Output is terse: a "✓ name" line per passing check; for a FAILING check, only that
# check's captured output (tail) — not every log. Clean run = one "clean" line. Adding a check =
# edit completely.toml [check], not this script. Backend for `cmp check`.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJ="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
case "${1:-}" in -*|"") ;; *) [ -d "$1" ] && { PROJ="$1"; shift; } ;; esac
TAIL="${CMP_CHECK_TAIL:-30}"

CHECKS="$(python3 "$ROOT/scripts/config.py" checks "$PROJ" 2>/dev/null)"
if [ -z "$CHECKS" ]; then
  echo "cmp check: no checks configured or detected in $PROJ (add a [check] table to completely.toml)"
  exit 0
fi

fail=0; total=0
out="$(mktemp)"
while IFS=$'\t' read -r name cwd cmd; do
  [ -z "${name:-}" ] && continue
  total=$((total + 1))
  if ( cd "$cwd" 2>/dev/null && eval "$cmd" ) >"$out" 2>&1; then
    echo "  ✓ $name"
  else
    echo "  ✗ $name"
    tail -n "$TAIL" "$out" | sed 's/^/      /'
    fail=$((fail + 1))
  fi
done <<< "$CHECKS"
rm -f "$out"

if [ "$fail" -eq 0 ]; then
  echo "cmp check: clean ($total checks)"
  exit 0
fi
echo "cmp check: $fail/$total checks FAILED (only failures shown above)"
exit 1
