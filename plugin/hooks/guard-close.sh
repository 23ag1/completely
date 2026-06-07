#!/usr/bin/env bash
# claude-harness :: guard-close (PreToolUse on Bash) — enforce commit-before-close.
#
# Blocks `bd close` / `bd update --status closed` when the working tree has UNCOMMITTED tracked
# changes, so a task can never close with its write-zone uncommitted. This makes the
# commit-before-close invariant a DETERMINISTIC gate instead of prose in task-engine.md: if the
# per-task commit failed for ANY reason (no git identity, a rejecting pre-commit hook, a blocked
# shared-tree gate, nothing staged), the tree stays dirty and the close is refused (exit 2).
#
# Pattern: commit your write-zone in one step, confirm it landed, THEN close in a separate step
# (a clean tree). Override (rare, e.g. closing a non-code/bd-only task amid unrelated WIP):
#   CMP_ALLOW_DIRTY_CLOSE=1
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

# Only gate task-closing commands; everything else passes through.
printf '%s' "$CMD" | grep -qiE 'bd[[:space:]]+close([[:space:]]|$)|--status[[:space:]=]+closed' || exit 0

# b3y: refuse close while the bead carries unresolved CRITICAL/HIGH reviewer findings. The worker /
# reviewer records each as metadata.open_findings; addressing it means fixing + clearing the entry,
# or `bd update --status blocked` quoting it — never paraphrasing a verdict as addressed without the
# change. This makes "findings are binding" a deterministic gate, not prose. Override: CMP_ALLOW_OPEN_FINDINGS=1.
if [ "${CMP_ALLOW_OPEN_FINDINGS:-0}" != 1 ] && command -v bd >/dev/null 2>&1; then
  CID="$(printf '%s' "$CMD" | sed -n 's/.*bd[[:space:]]\+close[[:space:]]\+\([A-Za-z0-9._-]\+\).*/\1/p' | head -1)"
  [ -z "$CID" ] && CID="$(printf '%s' "$CMD" | sed -n 's/.*bd[[:space:]]\+update[[:space:]]\+\([A-Za-z0-9._-]\+\).*/\1/p' | head -1)"
  if [ -n "$CID" ]; then
    OF="$(bd show "$CID" --json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: d={}
if isinstance(d,list): d=d[0] if d else {}
elif isinstance(d,dict): d=d.get("issue") or d
of=((d or {}).get("metadata") or {}).get("open_findings") or []
print(len(of) if isinstance(of,list) else (1 if of else 0))' 2>/dev/null)"
    if [ -n "$OF" ] && [ "$OF" -gt 0 ] 2>/dev/null; then
      {
        echo "[harness/guard] BLOCKED bd close — ${CID} has ${OF} unresolved reviewer finding(s) (metadata.open_findings)."
        echo "[harness/guard] address each CRITICAL/HIGH finding (fix + clear open_findings), or bd update --status blocked quoting it."
        echo "[harness/guard] never restate a finding as addressed without the change. override (rare): CMP_ALLOW_OPEN_FINDINGS=1"
      } >&2
      exit 2
    fi
  fi
fi

[ "${CMP_ALLOW_DIRTY_CLOSE:-0}" = 1 ] && exit 0

PROJ="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$PROJ" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
git rev-parse HEAD >/dev/null 2>&1 || exit 0   # no commits yet -> nothing to enforce

# Tracked, uncommitted changes (staged or unstaged, incl. git-added new files) make the tree
# differ from HEAD. Untracked-never-added files are intentionally ignored to avoid false blocks.
if ! git diff --quiet HEAD 2>/dev/null; then
  {
    echo "[harness/guard] BLOCKED bd close — working tree has uncommitted tracked changes."
    echo "[harness/guard] commit your write-zone FIRST (commit-before-close), confirm it landed, then close."
    echo "[harness/guard] override (rare, e.g. bd-only task amid unrelated WIP): CMP_ALLOW_DIRTY_CLOSE=1"
  } >&2
  exit 2
fi

exit 0
