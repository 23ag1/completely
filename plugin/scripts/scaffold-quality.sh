#!/usr/bin/env bash
# completely :: quality scaffold — install a pre-commit gate (cmpl check) + starter lint configs.
# Safe: writes only ABSENT files, per detected stack. Backend for `cmpl quality`.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
Q="$ROOT/templates/quality"
PROJ="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$PROJ" || { echo "quality: no dir $PROJ" >&2; exit 1; }

put(){ if [ -e "$2" ]; then echo "  skip $2 (exists)"; else mkdir -p "$(dirname "$2")"; cp "$1" "$2"; echo "  + $2"; fi; }

mkdir -p .githooks
put "$Q/pre-commit" .githooks/pre-commit; chmod +x .githooks/pre-commit 2>/dev/null || true
if git rev-parse --git-dir >/dev/null 2>&1; then
  git config core.hooksPath .githooks && echo "  git hooksPath -> .githooks"
fi

[ -f package.json ]          && { put "$Q/eslint.config.mjs" eslint.config.mjs; put "$Q/prettierrc.json" .prettierrc.json; }
[ -f frontend/package.json ] && { put "$Q/eslint.config.mjs" frontend/eslint.config.mjs; put "$Q/prettierrc.json" frontend/.prettierrc.json; }
[ -f pyproject.toml ]         && put "$Q/ruff.toml" ruff.toml
[ -f backend/pyproject.toml ] && put "$Q/ruff.toml" backend/ruff.toml

echo "quality: done. Pre-commit runs 'cmpl check' before each commit (bypass: git commit --no-verify)."
