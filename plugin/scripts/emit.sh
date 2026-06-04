#!/usr/bin/env bash
# completely :: emit — turn GSD PLAN.md file(s) into Beads (epic + tasks). Backend for `cmpl emit`.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -d .beads ] || { echo "emit: run from a repo with 'bd init'" >&2; exit 1; }
[ $# -ge 1 ] || { echo "usage: cmpl emit <PLAN.md> [more-PLAN.md...]"; exit 1; }
QFILE="${CMP_STATE:-$ROOT}/quarantine.txt"
if [ -f "$QFILE" ] && grep -qx gsd "$QFILE" && [ "${CMP_FORCE:-0}" != 1 ]; then
  echo "emit: gsd is quarantined (version drift) — its PLAN.md format may have changed." >&2
  echo "      Re-test emit-gsd.py against your GSD, then set CMP_FORCE=1 to override." >&2
  exit 3
fi
rc=0
for f in "$@"; do
  [ -f "$f" ] || { echo "emit: no such file: $f" >&2; rc=1; continue; }
  echo "emit: $f"
  python3 "$ROOT/scripts/emit-gsd.py" "$f" || rc=1
done
exit "$rc"
