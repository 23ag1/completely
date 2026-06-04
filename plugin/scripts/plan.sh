#!/usr/bin/env bash
# completely :: plan-apply — materialize a structured plan (JSON, stdin or file) into Beads.
# Backend for `cmpl plan-apply` and the `/completely:plan` skill. Beads-first: no PLAN.md.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -d .beads ] || { echo "plan-apply: run from a repo with 'bd init'" >&2; exit 1; }
exec python3 "$ROOT/scripts/plan-apply.py" "$@"
