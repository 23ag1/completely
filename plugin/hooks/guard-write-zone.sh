#!/usr/bin/env bash
# claude-harness :: guard-write-zone (PreToolUse on Write|Edit|MultiEdit|NotebookEdit) —
# fence a worker to its bead's write_zone at EDIT TIME, not just in the worker-contract prose.
#
# The parallel dispatcher (run.sh) assumes disjoint write_zones == no file collision. quality-gate.sh
# is non-blocking (always exit 0), so nothing stopped an out-of-zone Write/Edit — a worker straying
# outside its zone silently broke the disjointness guarantee, surfacing only at merge-slot. This hook
# DENIES (exit 2) any Write/Edit/MultiEdit/NotebookEdit whose target path is OUTSIDE the write_zone of
# the bead named in CMP_WORKER_BEAD.
#
#   CMP_WORKER_BEAD unset  -> interactive/human session: no decidable zone, hook is a NO-OP (exit 0).
#   CMP_WORKER_ZONE set    -> use it verbatim (JSON array) without a bd lookup (fast path / testing).
#
# Fail-open by design wherever there is NO decidable target (empty stdin, unparseable payload, no path
# in tool_input, no/empty write_zone) — this is a collision FENCE, not a security boundary, and must
# never block a legitimate interactive edit. Path matching is by path COMPONENT (not string prefix) so
# zone "plugin/hooks" never falsely matches "plugin/hooks2/x".
set -uo pipefail

# ---------- --self-test: proves deny-outside, allow-inside, interactive no-op, NotebookEdit ----------
if [ "${1:-}" = "--self-test" ]; then
  SELF="$0"; fail=0
  _edit() { printf '{"tool_name":"%s","tool_input":{"%s":"%s"}}' "$1" "$2" "$3"; }

  CMP_WORKER_BEAD=t CMP_WORKER_ZONE='["plugin/hooks/"]' \
    bash "$SELF" <<<"$(_edit Edit file_path plugin/scripts/run.sh)" >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] && echo "  PASS deny edit OUTSIDE write_zone (exit 2)" || { echo "  FAIL outside not denied (rc=$rc)"; fail=1; }

  CMP_WORKER_BEAD=t CMP_WORKER_ZONE='["plugin/hooks/"]' \
    bash "$SELF" <<<"$(_edit Edit file_path plugin/hooks/x.sh)" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && echo "  PASS allow edit INSIDE write_zone (exit 0)" || { echo "  FAIL inside not allowed (rc=$rc)"; fail=1; }

  CMP_WORKER_BEAD=t CMP_WORKER_ZONE='["plugin/hooks/hooks.json"]' \
    bash "$SELF" <<<"$(_edit Edit file_path plugin/hooks/hooks.json)" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && echo "  PASS allow exact-file zone entry" || { echo "  FAIL exact-file zone denied (rc=$rc)"; fail=1; }

  CMP_WORKER_BEAD=t CMP_WORKER_ZONE='["plugin/hooks"]' \
    bash "$SELF" <<<"$(_edit Edit file_path plugin/hooks2/evil.sh)" >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] && echo "  PASS component-match: zone 'plugin/hooks' does NOT cover 'plugin/hooks2/'" || { echo "  FAIL prefix-string false allow (rc=$rc)"; fail=1; }

  CMP_WORKER_ZONE='["plugin/hooks/"]' \
    bash "$SELF" <<<"$(_edit Edit file_path anything/else.py)" >/dev/null 2>&1; rc=$?
  [ "$rc" = 0 ] && echo "  PASS interactive (no CMP_WORKER_BEAD) is a no-op" || { echo "  FAIL interactive fenced (rc=$rc)"; fail=1; }

  CMP_WORKER_BEAD=t CMP_WORKER_ZONE='["plugin/hooks/"]' \
    bash "$SELF" <<<"$(_edit NotebookEdit notebook_path plugin/x.ipynb)" >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] && echo "  PASS deny NotebookEdit OUTSIDE (notebook_path, not file_path)" || { echo "  FAIL notebook outside not denied (rc=$rc)"; fail=1; }

  if [ "$fail" = 0 ]; then echo "guard-write-zone/self-test: OK"; exit 0; else echo "guard-write-zone/self-test: FAILED"; exit 1; fi
fi

# ---------- production gate ----------
BEAD="${CMP_WORKER_BEAD:-}"
[ -z "$BEAD" ] && exit 0                       # interactive session — never fence

INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && exit 0                       # no payload -> no decidable target -> allow

# Target path: file_path (Write/Edit/MultiEdit) OR notebook_path (NotebookEdit).
TARGET="$(printf '%s' "$INPUT" | python3 -c '
import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
ti=d.get("tool_input") or {}
print(ti.get("file_path") or ti.get("notebook_path") or "")
' 2>/dev/null)"
[ -z "$TARGET" ] && exit 0                       # no path in payload -> nothing to fence

# write_zone: explicit override (fast path / tests), else the bead's metadata.
ZONE_JSON="${CMP_WORKER_ZONE:-}"
if [ -z "$ZONE_JSON" ] && command -v bd >/dev/null 2>&1; then
  ZONE_JSON="$(bd show "$BEAD" --json 2>/dev/null | python3 -c '
import sys,json
try: d=json.load(sys.stdin)
except Exception: d=[]
if isinstance(d,list): d=d[0] if d else {}
elif isinstance(d,dict): d=d.get("issue") or d
z=((d or {}).get("metadata") or {}).get("write_zone") or []
print(json.dumps(z if isinstance(z,list) else []))
' 2>/dev/null)"
fi
[ -z "$ZONE_JSON" ] && exit 0                     # zone unknown -> cannot decide -> allow

PROJ="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

DECISION="$(TARGET="$TARGET" PROJ="$PROJ" ZONE_JSON="$ZONE_JSON" python3 -c '
import os,sys,json
target=os.environ["TARGET"]; proj=os.environ["PROJ"]
try: zones=json.loads(os.environ["ZONE_JSON"])
except Exception: zones=[]
zones=[z for z in zones if isinstance(z,str) and z] if isinstance(zones,list) else []
if not zones:
    print("ALLOW"); sys.exit(0)                  # undeclared/global zone -> not fenced here
ap = os.path.abspath(target) if os.path.isabs(target) else os.path.abspath(os.path.join(proj,target))
try: rel=os.path.relpath(ap, proj)
except Exception: rel=target
rel=rel.replace(os.sep,"/")
rb=[c for c in rel.split("/") if c not in ("",".")]
def inside(z):
    zb=[c for c in z.rstrip("/").split("/") if c not in ("",".")]
    return rb[:len(zb)]==zb                       # rel == z, or rel under z/ — by COMPONENT
print("ALLOW" if any(inside(z) for z in zones) else "DENY:"+rel)
' 2>/dev/null)"

case "$DECISION" in
  DENY:*)
    rel="${DECISION#DENY:}"
    {
      echo "[harness/guard] BLOCKED edit OUTSIDE write_zone — '$rel' is not in bead ${BEAD}'s zone."
      echo "[harness/guard]   write_zone: $ZONE_JSON"
      echo "[harness/guard] stay inside your write_zone. If the task genuinely needs this path, split the"
      echo "[harness/guard] bead or update its metadata.write_zone — do not silently stray (breaks parallel disjointness)."
    } >&2
    exit 2 ;;
  *) exit 0 ;;                                     # ALLOW or empty -> permit
esac
