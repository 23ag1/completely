#!/usr/bin/env bash
# completely :: lint — enforce the worker-contract on Beads tasks.
# Built-in `bd lint` (acceptance/success-criteria by type) + completely's extra check that every
# open task has acceptance + design + metadata.write_zone. Backend for `cmpl lint`.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[ -d .beads ] || { echo "lint: run from a repo with 'bd init'" >&2; exit 1; }

echo "== bd lint (built-in: required sections by type) =="
bd lint 2>&1 | sed 's/^/  /' || true

echo "== completely worker-contract (acceptance + design + write_zone) =="
bd list --status open --json 2>/dev/null | python3 "$ROOT/scripts/_lint_check.py"
