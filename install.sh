#!/usr/bin/env bash
# claude-harness installer.
#
# Two ways to install:
#
#   (A) As a Claude Code plugin (RECOMMENDED — handles hooks/agents/skills for you):
#         claude plugin marketplace add <you>/claude-harness
#         claude plugin install harness@claude-harness
#       Then, inside any project:  /harness-init
#
#   (B) Manual / non-plugin (this script). Copies the gates into ~/.claude/harness,
#       and (with --project DIR) scaffolds a project's thin layer (DoD + CLAUDE snippet
#       + a settings.json wiring the hooks). Use this for tools that read .claude files
#       but don't support the plugin system.
#
# Usage:
#   ./install.sh                      # copy gates+agent+core into ~/.claude/harness
#   ./install.sh --project /path/repo # also scaffold that repo's thin layer
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="${HARNESS_HOME:-$HOME/.claude/harness}"
PROJECT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

echo "==> installing the full harness into $DEST"
mkdir -p "$DEST"
cp -rf "$SRC/plugin/." "$DEST/"            # full tree: bin, scripts, overlays, templates, tests, hooks, core, ...
chmod +x "$DEST/scripts/"*.sh "$DEST/bin/cmpl" 2>/dev/null || true
mkdir -p "$HOME/.claude/agents" && cp -f "$SRC/plugin/agents/evaluator.md" "$HOME/.claude/agents/evaluator.md"
# put the FULL cmpl on PATH via a wrapper (not a stripped shim)
BIN="${HARNESS_BIN:-$HOME/.local/bin}"; mkdir -p "$BIN"
printf '#!/usr/bin/env bash\nexec bash "%s" "$@"\n' "$DEST/bin/cmpl" > "$BIN/cmpl"
chmod +x "$BIN/cmpl"
echo "    full harness installed; 'cmpl' -> $BIN/cmpl (ensure $BIN is on PATH)."

if [ -n "$PROJECT" ]; then
  [ -d "$PROJECT" ] || { echo "no such project dir: $PROJECT" >&2; exit 1; }
  echo "==> scaffolding project thin layer in $PROJECT/.claude"
  mkdir -p "$PROJECT/.claude/harness"
  # Definition of Done
  cp -f "$SRC/plugin/templates/DEFINITION_OF_DONE.md" "$PROJECT/.claude/DEFINITION_OF_DONE.md"
  # settings.json wiring hooks to the installed gates (only if no settings.json yet)
  if [ ! -f "$PROJECT/.claude/settings.json" ]; then
    sed "s#__HARNESS_DIR__#$DEST#g" "$SRC/plugin/templates/settings.json" > "$PROJECT/.claude/settings.json"
    echo "    wrote .claude/settings.json (hooks wired to $DEST)"
  else
    echo "    .claude/settings.json exists — NOT overwriting. Merge hooks manually (see template)."
  fi
  echo "    NOTE: append plugin/templates/CLAUDE.harness.md into your project's CLAUDE.md."
fi

echo "==> done. Verify hooks fire with:  echo '{\"tool_input\":{\"command\":\"rm -rf /\"}}' | bash $DEST/guard-dangerous.sh; echo exit=\$?"
