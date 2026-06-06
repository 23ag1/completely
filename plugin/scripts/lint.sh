#!/usr/bin/env bash
# completely :: lint — enforce the worker-contract on Beads tasks.
# Built-in `bd lint` (acceptance/success-criteria by type) + completely's extra check that every
# open task has acceptance + design + metadata.write_zone. Backend for `cmpl lint`.
#
# NCR-on-fail (ECC quality-nonconformance pattern, ported): when this script FAILS *inside a worker
# context* — env `CMP_WORKER_BEAD=<id>` set, OR exactly one in_progress task in this Beads DB — we
# emit a structured nonconformance record as a `bd comment` on that bead and transition it to
# `blocked`. That replaces the silent-pass class (a worker iteration noticing a fail and ignoring
# it) with a documented, auditable containment event. Direct CLI runs without a worker context
# behave as before: print + exit 1. Opt-out per-run with CMP_NCR=0.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ---------- NCR helpers (ported pattern: detect → document → contain) ----------------------------

# detect_worker_bead → prints bead ID on stdout (empty if no worker context).
# Explicit env wins (single-source-of-truth for parallel-worker mode); otherwise we fall back to the
# single-in_progress heuristic, which only fires when there is exactly one — never when several
# concurrent workers each hold a claim, since auto-blocking the wrong bead would be worse than not
# blocking at all.
detect_worker_bead() {
  if [ "${CMP_NCR:-1}" = "0" ]; then return 0; fi
  if [ -n "${CMP_WORKER_BEAD:-}" ]; then printf '%s' "$CMP_WORKER_BEAD"; return 0; fi
  command -v bd >/dev/null 2>&1 || return 0
  [ -d .beads ] || return 0
  bd list --status in_progress --json 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
d = d if isinstance(d, list) else d.get("issues", [])
if len(d) == 1:
    print(d[0].get("id", "") or "")
' 2>/dev/null
}

# emit_ncr <stage> <reason> <output_tail_file> [block:1|0]
# Records the NCR on the active bead and (when block=1) transitions to blocked.
# Always returns 0 — failing to record an NCR must NOT mask the original failure.
emit_ncr() {
  local stage="$1" reason="$2" out_file="$3" block="${4:-1}"
  local bead; bead="$(detect_worker_bead)"
  [ -n "$bead" ] || return 0
  command -v bd >/dev/null 2>&1 || return 0
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local tail_text=""
  if [ -n "$out_file" ] && [ -s "$out_file" ]; then
    tail_text="$(tail -n 20 "$out_file" 2>/dev/null | sed 's/^/    /')"
  fi
  local msg
  msg="$(printf 'NCR %s  cmpl-lint FAILED in worker context\n  stage: %s\n  reason: %s\n  bead:   %s\n  output (tail):\n%s\n  containment: %s — investigate root cause before proceeding.' \
    "$ts" "$stage" "$reason" "$bead" "$tail_text" \
    "$([ "$block" = "1" ] && printf 'status -> blocked' || printf 'recorded (no auto-block)')")"
  bd comment "$bead" "$msg" >/dev/null 2>&1 || true
  if [ "$block" = "1" ]; then
    bd update "$bead" --status blocked >/dev/null 2>&1 || true
  fi
  printf '::ncr:: recorded on %s%s\n' "$bead" "$([ "$block" = "1" ] && printf ' (status -> blocked)' || printf '')" >&2
}

# ---------- self-test: tmp repo, bad open task, claimed worker bead, assert NCR + blocked ------
# Mirrors the real failure mode: a worker has claimed its bead (in_progress) and `cmpl lint` fails
# because OTHER open tasks in the backlog don't satisfy the worker-contract — the worker's iteration
# must turn that fail into an NCR + bd blocked, not silently move on.
if [ "${1:-}" = "--self-test" ]; then
  fetch_bid() { ( cd "$1" && bd list --all --json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin); d=d if isinstance(d,list) else d.get("issues",[])
hits=[i["id"] for i in d if i.get("title","")==sys.argv[1]]
print(hits[0] if hits else "")' "$2" ); }
  bd_status() { ( cd "$1" && bd show "$2" --json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except: d=None
if isinstance(d,list) and d: d=d[0]
print(d.get("status","") if isinstance(d,dict) else "")' ); }
  ncr_count() { ( cd "$1" && bd comments "$2" 2>/dev/null | grep -c 'NCR ' ); }

  D=$(mktemp -d /tmp/cmpl-lint-st.XXXXXX)
  trap 'rm -rf "$D"' EXIT
  ( cd "$D" && git init -q && bd init proj --stealth >/dev/null 2>&1 ) || { echo "FAIL init"; exit 1; }
  # WORKER bead: well-formed, claimed (in_progress). This is the bead the NCR must attach to.
  ( cd "$D" && bd create "worker bead" -t task --acceptance a --design d --metadata '{"write_zone":["a"]}' >/dev/null 2>&1 )
  WID="$(fetch_bid "$D" "worker bead")"
  [ -n "$WID" ] || { echo "FAIL locate WID"; exit 1; }
  ( cd "$D" && bd update "$WID" --claim >/dev/null 2>&1 )
  # OFFENDER bead: missing contract — open. Triggers the lint failure.
  ( cd "$D" && bd create "bad open task" -t task >/dev/null 2>&1 )

  fails=0

  # 1) FAIL path: explicit worker bead → exit 1, bead -> blocked, NCR comment recorded.
  ( cd "$D" && CMP_WORKER_BEAD="$WID" bash "$ROOT/scripts/lint.sh" >/dev/null 2>&1 ); rc=$?
  ST="$(bd_status "$D" "$WID")"; CN="$(ncr_count "$D" "$WID")"
  [ "$rc" = 1 ]              && echo "  PASS exit=1 on contract violation"        || { echo "  FAIL exit ($rc != 1)"; fails=$((fails+1)); }
  [ "$ST" = "blocked" ]      && echo "  PASS worker bead -> blocked"               || { echo "  FAIL bead status ($ST != blocked)"; fails=$((fails+1)); }
  [ "${CN:-0}" -ge 1 ]       && echo "  PASS NCR comment recorded"                 || { echo "  FAIL no NCR comment (cnt=$CN)"; fails=$((fails+1)); }

  # 2) OPT-OUT: CMP_NCR=0 must still fail the lint but NOT touch the bead.
  ( cd "$D" && bd update "$WID" --status in_progress >/dev/null 2>&1 )
  CN_BEFORE="$(ncr_count "$D" "$WID")"
  ( cd "$D" && CMP_NCR=0 CMP_WORKER_BEAD="$WID" bash "$ROOT/scripts/lint.sh" >/dev/null 2>&1 ); rc2=$?
  ST2="$(bd_status "$D" "$WID")"; CN_AFTER="$(ncr_count "$D" "$WID")"
  { [ "$rc2" = 1 ] && [ "$ST2" = "in_progress" ] && [ "${CN_AFTER:-0}" = "${CN_BEFORE:-0}" ]; } \
    && echo "  PASS CMP_NCR=0 disables NCR (exit=1, status & comments unchanged)" \
    || { echo "  FAIL opt-out (rc=$rc2, st=$ST2, cn=$CN_BEFORE->$CN_AFTER)"; fails=$((fails+1)); }

  # 3) AUTO-DETECT: no env hint, but exactly one in_progress task → still records NCR on it.
  ( cd "$D" && bd update "$WID" --status in_progress >/dev/null 2>&1 )
  CN_BEFORE="$(ncr_count "$D" "$WID")"
  ( cd "$D" && bash "$ROOT/scripts/lint.sh" >/dev/null 2>&1 ); rc3=$?
  ST3="$(bd_status "$D" "$WID")"; CN_AFTER="$(ncr_count "$D" "$WID")"
  { [ "$rc3" = 1 ] && [ "$ST3" = "blocked" ] && [ "${CN_AFTER:-0}" -gt "${CN_BEFORE:-0}" ]; } \
    && echo "  PASS auto-detect single in_progress as worker bead" \
    || { echo "  FAIL auto-detect (rc=$rc3, st=$ST3, cn=$CN_BEFORE->$CN_AFTER)"; fails=$((fails+1)); }

  # 4) CLEAN run: no contract violations → exit 0, no NCR.
  OID="$(fetch_bid "$D" "bad open task")"
  ( cd "$D" && bd close "$OID" >/dev/null 2>&1 )
  ( cd "$D" && bd update "$WID" --status in_progress >/dev/null 2>&1 )
  CN_BEFORE="$(ncr_count "$D" "$WID")"
  ( cd "$D" && CMP_WORKER_BEAD="$WID" bash "$ROOT/scripts/lint.sh" >/dev/null 2>&1 ); rc4=$?
  CN_AFTER="$(ncr_count "$D" "$WID")"
  { [ "$rc4" = 0 ] && [ "${CN_AFTER:-0}" = "${CN_BEFORE:-0}" ]; } \
    && echo "  PASS clean lint -> exit 0, no NCR" \
    || { echo "  FAIL clean run (rc=$rc4, cn=$CN_BEFORE->$CN_AFTER)"; fails=$((fails+1)); }

  if [ "$fails" = 0 ]; then echo "cmpl-lint self-test: OK"; exit 0; fi
  echo "cmpl-lint self-test: $fails failure(s)"; exit 1
fi

# ---------- normal run ------------------------------------------------------------------------
[ -d .beads ] || { echo "lint: run from a repo with 'bd init'" >&2; exit 1; }

OUT="$(mktemp)"; trap 'rm -f "$OUT"' EXIT

echo "== bd lint (built-in: required sections by type) =="
bd lint 2>&1 | tee -a "$OUT" | sed 's/^/  /' || true

echo "== completely worker-contract (acceptance + design + write_zone) =="
bd list --status open --json 2>/dev/null | python3 "$ROOT/scripts/_lint_check.py" | tee -a "$OUT"
rc=${PIPESTATUS[1]}

if [ "$rc" != "0" ]; then
  emit_ncr "worker-contract" "open task(s) missing acceptance/design/write_zone" "$OUT" 1
  exit "$rc"
fi
exit 0
