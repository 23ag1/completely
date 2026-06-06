#!/usr/bin/env bash
# completely :: mock worker — stands in for a real `claude -p` worker so the auto loop can be
# exercised deterministically (no agent, no real code). It reads (and ignores) the overlay prompt
# on stdin, picks the next ready task, and behaves per MOCK_MODE:
#   good  — claim → commit (BEFORE close) → close   (the correct path)
#   block — claim → mark blocked                     (legit STOP)
#   die   — claim → exit nonzero (no close/block)    (crash mid-task)
#   noop  — do nothing                               (worker that never makes progress)
set -uo pipefail
cat >/dev/null 2>&1 || true   # consume the overlay prompt

MODE="${MOCK_MODE:-good}"
id="$(bd ready --json 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = []
d = d if isinstance(d, list) else d.get("issues", [])
for i in d:
    if i.get("issue_type") == "epic":
        continue
    if "checkpoint" in (i.get("labels") or []):
        continue
    print(i["id"]); break
')"

[ -z "$id" ] && { echo "mock(${MODE}): nothing ready"; exit 0; }
[ "$MODE" = noop ] && { echo "mock(noop): saw $id, did nothing"; exit 0; }

bd update "$id" --claim >/dev/null 2>&1

[ "$MODE" = die ] && { echo "mock(die): claimed $id then crashed (no close/block)"; exit 1; }
[ "$MODE" = block ] && {
  bd update "$id" --status blocked >/dev/null 2>&1
  bd comment "$id" "mock: blocked (simulated STOP-condition)" >/dev/null 2>&1
  echo "mock(block): blocked $id"; exit 0
}

# good: commit BEFORE close (the recipe's order)
f="work_$(echo "$id" | tr -cd 'a-zA-Z0-9').txt"
echo "$id done by mock" > "$f"
bd comment "$id" "mock evidence: created $f" >/dev/null 2>&1
git add "$f" >/dev/null 2>&1
git -c user.name=mock -c user.email=mock@example.com commit -q -m "mock: $id" 2>/dev/null
bd close "$id" >/dev/null 2>&1
echo "mock(good): landed $id"
