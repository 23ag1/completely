#!/usr/bin/env bash
# completely :: emit — turn GSD PLAN.md file(s) into Beads (epic + tasks). Backend for `cmp emit`.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -d .beads ] || { echo "emit: run from a repo with 'bd init'" >&2; exit 1; }
[ $# -ge 1 ] || { echo "usage: cmp emit <PLAN.md> [more-PLAN.md...]"; exit 1; }
rc=0
for f in "$@"; do
  [ -f "$f" ] || { echo "emit: no such file: $f" >&2; rc=1; continue; }
  echo "emit: $f"
  python3 "$ROOT/scripts/emit-gsd.py" "$f" || rc=1
done
exit "$rc"
