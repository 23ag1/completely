#!/usr/bin/env bash
# claude-harness :: guard-dangerous (PreToolUse on Bash)
#
# Blocks irreversible / destructive shell commands before they run. exit 2 = block,
# the stderr message is shown to the agent and the human must explicitly confirm
# (re-issue with intent) — matching STOP-rule "dangerous operations need a human".
#
# Tunable: a project may add allow/deny regex lines (one per line) in
#   <project>/.claude/harness/guard-extra.txt   (prefix with "allow:" or "deny:")
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"

CMD=""
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
elif command -v python3 >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin); print(d.get("tool_input",{}).get("command","") or "")
except Exception:
    print("")' 2>/dev/null)"
fi

[ -z "$CMD" ] && exit 0

PROJ="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
EXTRA="$PROJ/.claude/harness/guard-extra.txt"

# project allowlist: if any allow: regex matches, let it through
if [ -f "$EXTRA" ]; then
  while IFS= read -r line; do
    case "$line" in
      allow:*) printf '%s' "$CMD" | grep -qiE "${line#allow:}" && exit 0 ;;
    esac
  done < "$EXTRA"
fi

# default deny patterns (irreversible / wide-blast-radius)
DENY='rm[[:space:]]+(-[a-z]*[[:space:]]+)*-?[a-z]*r[a-z]*f|rm[[:space:]]+(-[a-z]*[[:space:]]+)*-?[a-z]*f[a-z]*r|rm[[:space:]]+-r[[:space:]]+-f|rm[[:space:]]+-f[[:space:]]+-r|drop[[:space:]]+(table|database|schema)|truncate[[:space:]]+table|git[[:space:]]+push[[:space:]].*(--force([^-]|$)|--force-with-lease|[[:space:]]-f([[:space:]]|$))|git[[:space:]]+reset[[:space:]]+--hard|git[[:space:]]+clean[[:space:]]+-[a-z]*f|mkfs(\.|[[:space:]])|dd[[:space:]]+.*of=/dev/|>[[:space:]]*/dev/sd|chmod[[:space:]]+-R[[:space:]]+777[[:space:]]+/|:\(\)\{[[:space:]]*:\|:'

# project denylist additions
if [ -f "$EXTRA" ]; then
  while IFS= read -r line; do
    case "$line" in
      deny:*) DENY="$DENY|${line#deny:}" ;;
    esac
  done < "$EXTRA"
fi

if printf '%s' "$CMD" | grep -qiE "$DENY"; then
  {
    echo "[harness/guard] BLOCKED — irreversible/destructive command."
    echo "[harness/guard] cmd: $CMD"
    echo "[harness/guard] If this is truly intended, the human must confirm and run it explicitly."
  } >&2
  exit 2
fi

exit 0
