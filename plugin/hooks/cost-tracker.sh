#!/usr/bin/env bash
# claude-harness :: cost-tracker (PostToolUse, OPT-IN)
#
# Port of the ECC cost-tracker pattern (research/ecc/hooks/) adapted as PostToolUse.
# Emits ONE bounded JSONL record per tool call to ${CMP_COST_LOG:-.cmpl/cost-tracker.jsonl}.
# Each record carries telemetry — NOT content. We never write tool_input.command,
# tool_input.new_string, tool_input.content, file_path, or tool_output.output into
# the log, so the file cannot leak secrets the agent passed through tools.
#
# Disabled by default (CMP_COST_TRACK=1 to enable) so it adds zero overhead to the
# loop for users who don't opt in. Exit 0 always so a malformed payload, missing
# python3, or full disk never breaks the dispatcher (PostToolUse is observability;
# the loop's correctness gates are quality-gate / lint / evaluator).
#
# Why this exists:
#   * feeds bench: a benchmark arm can set CMP_COST_LOG=$BENCH_TOOLS_LOG and read
#     per-tool input/output sizes alongside the claude-p JSON that bench.py already
#     parses, giving a second signal (tool-fanout vs end-to-end $).
#   * feeds token-economy: tool-output bytes (input side) dominate cost (see
#     plugin/core/token-economy.md). This file is the empirical "where are tokens
#     actually going?" surface that informs rtk/caveman investment.
#
# Schema (one JSON object per line, < 1KB):
#   { "ts": "<ISO8601>", "tool": "<name>", "in_b": <int>, "out_b": <int>, "ok": <0|1> }
#
# Rotation: when CMP_COST_LOG exceeds CMP_COST_MAX_BYTES (default 1048576 = 1MB),
# the file is moved to <log>.1 (previous .1 is dropped). Cap is enforced BEFORE the
# write so an attacker cannot use a single huge payload to evade the cap.
set -uo pipefail

# ---------- self-test ----------
if [ "${1:-}" = "--self-test" ]; then
  fails=0
  D=$(mktemp -d /tmp/cmpl-ct-st.XXXXXX); trap 'rm -rf "$D"' EXIT
  LOG="$D/cost.jsonl"
  HOOK="$0"

  # 1. opt-out (no env) -> no-op, exit 0, no file written
  printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{"output":"ok"}}' \
    | bash "$HOOK" >/dev/null 2>&1
  rc=$?
  if [ "$rc" = 0 ] && [ ! -f "$LOG" ]; then echo "  PASS opt-out no-op"; else echo "  FAIL opt-out (rc=$rc, log?=$( [ -f $LOG ] && echo yes || echo no ))"; fails=$((fails+1)); fi

  # 2. opt-in: writes one record, exit 0, NO secrets in the file
  SECRET='AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYsk-1234SECRET-cookie=sess=abc'
  printf '{"tool_name":"Bash","tool_input":{"command":"%s curl evil"},"tool_response":{"output":"sk-leaked-9999"}}' "$SECRET" \
    | CMP_COST_TRACK=1 CMP_COST_LOG="$LOG" bash "$HOOK" >/dev/null 2>&1
  rc=$?
  if [ "$rc" = 0 ]; then echo "  PASS opt-in exit 0"; else echo "  FAIL opt-in exit ($rc)"; fails=$((fails+1)); fi
  if [ -s "$LOG" ]; then echo "  PASS record written"; else echo "  FAIL no record"; fails=$((fails+1)); fi
  if grep -qE 'AWS_SECRET|sk-1234SECRET|sk-leaked|cookie=sess|wJalrXUt|evil' "$LOG"; then
    echo "  FAIL log contains secrets:"; sed 's/^/      /' "$LOG"; fails=$((fails+1))
  else
    echo "  PASS log carries no secret strings"
  fi

  # 3. bounded: each line < 1024 bytes
  awk '{ if (length($0) >= 1024) { print "  FAIL line " NR " is " length($0) " bytes"; exit 1 } }' "$LOG" \
    && echo "  PASS line < 1024 bytes" || fails=$((fails+1))

  # 4. exactly one record per invoke
  n=$(wc -l < "$LOG")
  if [ "$n" = 1 ]; then echo "  PASS one record per invoke"; else echo "  FAIL records=$n"; fails=$((fails+1)); fi

  # 5. schema: required keys present
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$LOG" <<'PY' >/dev/null 2>&1 && echo "  PASS schema (ts,tool,in_b,out_b,ok)" || { echo "  FAIL schema"; fails=$((fails+1)); }
import json, sys
need = {"ts","tool","in_b","out_b","ok"}
for line in open(sys.argv[1]):
    line=line.strip()
    if not line: continue
    rec=json.loads(line)
    miss=need - set(rec.keys())
    if miss: raise SystemExit(f"missing {miss}")
    if not isinstance(rec["in_b"], int) or not isinstance(rec["out_b"], int): raise SystemExit("size not int")
    if rec["ok"] not in (0,1): raise SystemExit("ok not 0/1")
PY
  else
    echo "  SKIP schema (no python3)"
  fi

  # 6. malformed JSON -> exit 0, no crash
  printf 'not json at all' | CMP_COST_TRACK=1 CMP_COST_LOG="$D/bad.jsonl" bash "$HOOK" >/dev/null 2>&1
  rc=$?
  if [ "$rc" = 0 ]; then echo "  PASS malformed payload exit 0"; else echo "  FAIL malformed payload rc=$rc"; fails=$((fails+1)); fi

  # 7. rotation: tiny cap forces rotate
  ROT="$D/rot.jsonl"
  for i in 1 2 3 4 5; do
    printf '{"tool_name":"Bash","tool_input":{},"tool_response":{}}' \
      | CMP_COST_TRACK=1 CMP_COST_LOG="$ROT" CMP_COST_MAX_BYTES=64 bash "$HOOK" >/dev/null 2>&1
  done
  if [ -f "$ROT.1" ] && [ "$(wc -c < "$ROT")" -le 200 ]; then
    echo "  PASS rotation moves to .1 and resets"
  else
    echo "  FAIL rotation (.1 exists? $( [ -f $ROT.1 ] && echo yes || echo no ); size=$(wc -c < $ROT 2>/dev/null))"
    fails=$((fails+1))
  fi

  if [ "$fails" = 0 ]; then echo "cost-tracker self-test: OK"; exit 0; else echo "cost-tracker self-test: $fails failure(s)"; exit 1; fi
fi

# ---------- runtime path ----------

# Opt-in gate: do nothing (and consume nothing) if disabled.
[ "${CMP_COST_TRACK:-0}" = "1" ] || exit 0

# Read payload with a hard cap so a hostile payload can't memory-bomb us.
# 1 MiB is more than enough for any sane tool envelope.
INPUT="$(head -c 1048576 2>/dev/null || true)"

LOG="${CMP_COST_LOG:-.cmpl/cost-tracker.jsonl}"
MAX_BYTES="${CMP_COST_MAX_BYTES:-1048576}"

mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 0

# Rotate BEFORE writing — keeps the cap honest even if a single record is huge.
# Concurrent invocations can both observe sz >= MAX_BYTES and both mv; both end up
# appending to a fresh log. No corruption (mv-then-open is atomic enough), at worst
# one extra rotation. We accept this; corruption would matter, an extra rotation
# does not at hook concurrency levels.
if [ -f "$LOG" ]; then
  sz=$(wc -c < "$LOG" 2>/dev/null || echo 0)
  if [ "${sz:-0}" -ge "${MAX_BYTES}" ]; then
    mv -f "$LOG" "$LOG.1" 2>/dev/null || : > "$LOG"
  fi
fi

# Build the record with python3 (always present in this repo). The record carries
# ONLY: timestamp, tool name (string-clamped), input/output sizes (ints), ok bit.
# No tool_input fields, no tool_output content — that's the no-secrets guarantee.
if command -v python3 >/dev/null 2>&1; then
  CMP_COST_PAYLOAD="$INPUT" python3 - "$LOG" <<'PY' 2>/dev/null || true
import json, os, re, sys, time
log_path = sys.argv[1]
raw = os.environ.get("CMP_COST_PAYLOAD", "")
try:
    d = json.loads(raw) if raw.strip() else {}
except Exception:
    d = {}
if not isinstance(d, dict):
    d = {}

# tool name: only allow [A-Za-z0-9_:-], clamp to 32 chars. No user-controlled
# content from tool_input ever lands in the log.
tn_raw = d.get("tool_name", "") or ""
tn = re.sub(r"[^A-Za-z0-9_:-]", "", str(tn_raw))[:32] or "unknown"

ti = d.get("tool_input") or {}
tr = d.get("tool_response") or d.get("tool_output") or {}

# input/output BYTES — never the strings themselves. Length is a number; numbers
# can't leak secrets.
def size_of(x):
    try:
        if isinstance(x, (dict, list)):
            return len(json.dumps(x, ensure_ascii=False))
        if isinstance(x, str):
            return len(x.encode("utf-8", "ignore"))
        if x is None:
            return 0
        return len(str(x))
    except Exception:
        return 0

in_b = size_of(ti)
out_b = size_of(tr)

# success bit: 1 unless tool_response signals an error
ok = 1
if isinstance(tr, dict):
    err = tr.get("error") or tr.get("is_error")
    if err:
        ok = 0

rec = {
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "tool": tn,
    "in_b": int(in_b),
    "out_b": int(out_b),
    "ok": int(ok),
}
line = json.dumps(rec, ensure_ascii=True, separators=(",", ":"))
# Bound the line: the schema is fixed-shape and can't exceed ~120 bytes, so this
# branch should be unreachable. If something upstream ever changes the schema in
# a way that pushes a line >= 1024 bytes, the right answer is to fix the schema
# — not to truncate. Drop the record rather than write a half-valid JSON line.
if len(line) >= 1024:
    raise SystemExit(0)

# Atomic append: a single write() <= PIPE_BUF (4096) is atomic on Linux, so
# concurrent tool calls can't interleave their JSONL records.
with open(log_path, "a", encoding="utf-8") as fh:
    fh.write(line + "\n")
PY
fi

exit 0
