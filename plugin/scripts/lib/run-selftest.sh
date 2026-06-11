# run-selftest.sh — the `cmpl run --self-test` suite, sourced by run.sh when --self-test is set.
# Runs in run.shs shell (same process): dispatch_ids / build_worker_prompt / PROMPT / CLAUDE_CMD
# and the PID_* state are all already defined above the source point. SELF_ABS re-invokes the
# REAL run.sh as a subprocess to drive the live loop. Ends by exiting the process (OK/FAILED).

  echo "run/self-test: dispatcher unit"
  fail=0
  # Case 1: two disjoint tasks should both dispatch in one batch (slots=2).
  R1='[
    {"id":"t-a","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/scripts/run.sh"]}},
    {"id":"t-b","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/hooks/foo.sh"]}}
  ]'
  got="$(dispatch_ids "$R1" '[]' 2)"
  [ "$got" = "t-a t-b" ] && echo "  PASS disjoint tasks dispatch together (got: '$got')" \
    || { echo "  FAIL disjoint dispatch (got: '$got' want 't-a t-b')"; fail=1; }

  # Case 2: same write_zone → second waits (only first dispatches in this batch).
  R2='[
    {"id":"s-a","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/scripts/run.sh"]}},
    {"id":"s-b","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/scripts/run.sh"]}}
  ]'
  got="$(dispatch_ids "$R2" '[]' 4)"
  [ "$got" = "s-a" ] && echo "  PASS same-zone serializes (got: '$got')" \
    || { echo "  FAIL same-zone (got: '$got' want 's-a')"; fail=1; }

  # Case 3: directory-prefix overlap (one path is a parent of another).
  R3='[
    {"id":"p-a","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/scripts/"]}},
    {"id":"p-b","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/scripts/lint.sh"]}},
    {"id":"p-c","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/core/flow.md"]}}
  ]'
  got="$(dispatch_ids "$R3" '[]' 4)"
  [ "$got" = "p-a p-c" ] && echo "  PASS prefix overlap detected, unrelated proceeds (got: '$got')" \
    || { echo "  FAIL prefix overlap (got: '$got' want 'p-a p-c')"; fail=1; }

  # Case 4: undeclared write_zone is a global zone — serializes with everything.
  R4='[
    {"id":"g-a","issue_type":"task","status":"open","metadata":{}},
    {"id":"g-b","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/x"]}}
  ]'
  got="$(dispatch_ids "$R4" '[]' 4)"
  [ "$got" = "g-a" ] && echo "  PASS undeclared zone serializes globally (got: '$got')" \
    || { echo "  FAIL undeclared zone (got: '$got' want 'g-a')"; fail=1; }

  # Case 5: respects already-running zones.
  R5='[
    {"id":"r-a","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/scripts/run.sh"]}},
    {"id":"r-b","issue_type":"task","status":"open","metadata":{"write_zone":["plugin/core/flow.md"]}}
  ]'
  got="$(dispatch_ids "$R5" '[["plugin/scripts/run.sh"]]' 4)"
  [ "$got" = "r-b" ] && echo "  PASS running zone blocks new overlap (got: '$got')" \
    || { echo "  FAIL running-zone block (got: '$got' want 'r-b')"; fail=1; }

  # Case 6: respects slot budget (only 1 slot free → 1 task even when more are disjoint).
  got="$(dispatch_ids "$R1" '[]' 1)"
  [ "$got" = "t-a" ] && echo "  PASS slot budget honored (got: '$got')" \
    || { echo "  FAIL slot budget (got: '$got' want 't-a')"; fail=1; }

  # Case 7: checkpoint label skipped (human gate, not a worker task).
  R7='[
    {"id":"c-a","issue_type":"task","status":"open","labels":["checkpoint"],"metadata":{"write_zone":["x"]}},
    {"id":"c-b","issue_type":"task","status":"open","metadata":{"write_zone":["y"]}}
  ]'
  got="$(dispatch_ids "$R7" '[]' 4)"
  [ "$got" = "c-b" ] && echo "  PASS checkpoint task not dispatched (got: '$got')" \
    || { echo "  FAIL checkpoint skip (got: '$got' want 'c-b')"; fail=1; }

  # Case 8: enforced-policy injection — both step blocks must appear in the worker prompt and must
  # carry the right step tag, the right policy tag, and inline rule text (not just a ref to an md file).
  # If a prompt file is missing we still PASS the structural assertions (the blocks come from run.sh,
  # not from the overlay) but skip the trailing `cat $PROMPT` content check.
  if [ ! -f "$PROMPT" ]; then
    echo "  WARN overlay prompt missing ($PROMPT) — checking injected blocks only" >&2
    inj="$(PROMPT=/dev/null build_worker_prompt T1)"
  else
    inj="$(build_worker_prompt T1)"
  fi
  # Each substring must lie on a single line (grep -F is line-oriented).
  has() { printf '%s' "$inj" | grep -qF "$1"; }
  miss=""
  for s in \
    '<<COMPLETELY_ENFORCED step=plan-check' \
    '<<COMPLETELY_ENFORCED step=review' \
    'policy=thinking-models-planning' \
    'policy=security' \
    'Pre-Mortem' \
    'MECE-Decomposition' \
    'Constraint-Analysis' \
    'Reversibility-Test' \
    'security-reviewer' \
    'CRITICAL' \
    'BLOCKING' \
    'policy=project-fit' \
    'project-wide' \
    'duplication' \
    'architecture drift' \
    '<<COMPLETELY_ENFORCED step=verify' \
    'policy=path-exercised' \
    'real runtime path' \
    'negative control' \
    'USER-PERCEIVED correctness' \
    'READ THE CODE ITSELF' \
    '<<END_ENFORCED>>' \
    '<<COMPLETELY_DISPATCH>>' \
    'Your assigned task: T1'; do
    has "$s" || miss+="    · $s
"
  done
  if [ -z "$miss" ]; then
    echo "  PASS enforced-policy injection: both step blocks present with rule text"
  else
    echo "  FAIL enforced-policy injection — missing markers:"
    printf '%s' "$miss"
    fail=1
  fi
  # Ordering matters: dispatch header BEFORE policy BEFORE overlay — keeps the worker's reading
  # cadence stable (who am I → what's enforced → how to run the engine).
  if [ -f "$PROMPT" ]; then
    p_dispatch="$(printf '%s' "$inj" | grep -n '<<COMPLETELY_DISPATCH>>' | head -1 | cut -d: -f1)"
    p_plan="$(printf '%s' "$inj" | grep -n '<<COMPLETELY_ENFORCED step=plan-check' | head -1 | cut -d: -f1)"
    p_sec="$(printf '%s' "$inj" | grep -n '<<COMPLETELY_ENFORCED step=review' | head -1 | cut -d: -f1)"
    p_verify="$(printf '%s' "$inj" | grep -n '<<COMPLETELY_ENFORCED step=verify' | head -1 | cut -d: -f1)"
    if [ -n "$p_dispatch" ] && [ -n "$p_plan" ] && [ -n "$p_sec" ] && [ -n "$p_verify" ] \
       && [ "$p_dispatch" -lt "$p_plan" ] && [ "$p_plan" -lt "$p_sec" ] && [ "$p_sec" -lt "$p_verify" ]; then
      echo "  PASS enforced-policy ordering: dispatch < plan-check < review < verify"
    else
      echo "  FAIL enforced-policy ordering (dispatch=$p_dispatch plan=$p_plan review=$p_sec verify=$p_verify)"
      fail=1
    fi
  fi

  # Case 9: lingering-blocked worker (THE p4f failure mode — auto stuck on a worker that committed +
  # marked its task blocked but whose pid did not exit). Drives the REAL run.sh main loop in a
  # subprocess against a temp bd repo, with CMP_CLAUDE_CMD pointing at an inline mock that claims +
  # blocks the task, then sleeps for far longer than our budget. Asserts:
  #   · the loop reaps the lingering pid via the grace-then-kill path,
  #   · the loop reports clean termination ("done after N iteration(s)"),
  #   · the bd task ended up in `blocked` (worker's protocol did land before linger).
  # Negative-control friendly: if the linger-detection branch (alive PID + terminal bd state) is
  # removed, the subprocess hits the outer `timeout` and this case turns red. Likewise if `wait -n`
  # is reintroduced anywhere in the saturated-wait path with PARALLEL=1 + 1 task.
  if command -v bd >/dev/null 2>&1; then
    LD=$(mktemp -d /tmp/cmpl-linger-XXXXXX)
    LMOCK=$(mktemp /tmp/cmpl-linger-mock-XXXXXX.sh)
    # Resolve our own absolute path — the subprocess cd's into a tmp bd repo before re-invoking us.
    SELF_ABS="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    # Inline mock: read+discard stdin overlay, claim the first ready task, mark it blocked, then
    # sleep WAY past the test's timeout. Exits the parent's grace-kill, not by sleep finishing.
    cat > "$LMOCK" <<'MOCK'
#!/usr/bin/env bash
# Linger mock: reads the dispatch header from stdin to learn its assigned task ID (parent already
# claimed it), marks it blocked, then sleeps forever to simulate the p4f failure mode.
set -uo pipefail
in="$(cat)"
id="$(printf '%s' "$in" | sed -n 's/^Your assigned task: //p' | head -1)"
[ -n "$id" ] || exit 0
bd update "$id" --status blocked >/dev/null 2>&1
bd comment "$id" "linger-mock: blocked, now sleeping (simulating p4f)" >/dev/null 2>&1
exec sleep 9999
MOCK
    chmod +x "$LMOCK"
    if ( cd "$LD" && git init -q >/dev/null 2>&1 \
         && git -c user.email=t@t -c user.name=t commit -qm init --allow-empty >/dev/null 2>&1 \
         && bd init proj --stealth >/dev/null 2>&1 \
         && bd create "linger" -t task --acceptance a --design d \
              --metadata '{"write_zone":["a.txt"],"verify":"true"}' >/dev/null 2>&1 ); then
      # Tight wall-clock budgets force the new path quickly: 1s grace, 6s outer cap.
      # Pin the overlay prompt path so the subprocess does not depend on its own $ROOT (lets us run
      # this self-test from a moved copy of run.sh for negative-control purposes).
      LD_OUT=$( cd "$LD" && CMP_CLAUDE_CMD="bash $LMOCK" CMP_PARALLEL=1 \
        CMP_RUN_PROMPT="$PROMPT" \
        CMP_WORKER_GRACE=1 CMP_POLL_SECS=1 CMP_STALL_SECS=30 CMP_WORKER_TIMEOUT=60 \
        timeout 12 bash "$SELF_ABS" --mode unattended 2>&1 ); LD_RC=$?
      LD_STATUS=$( cd "$LD" && bd list --status blocked --json 2>/dev/null | python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: d = []
d = d if isinstance(d, list) else d.get("issues", [])
print("BLOCKED" if any(i.get("title") == "linger" for i in d) else "OPEN")' )
      if [ "$LD_RC" = 124 ]; then
        echo "  FAIL linger-detection: outer timeout fired — loop hung waiting for lingering worker (rc=124)"
        echo "$LD_OUT" | tail -10 | sed 's/^/      | /'
        fail=1
      elif ! printf '%s' "$LD_OUT" | grep -q 'reaping lingering worker'; then
        echo "  FAIL linger-detection: reap message never appeared (worker was not reclaimed)"
        echo "$LD_OUT" | tail -10 | sed 's/^/      | /'
        fail=1
      elif ! printf '%s' "$LD_OUT" | grep -q 'ready queue drained'; then
        echo "  FAIL linger-detection: loop did not announce clean termination"
        echo "$LD_OUT" | tail -10 | sed 's/^/      | /'
        fail=1
      elif [ "$LD_STATUS" != "BLOCKED" ]; then
        echo "  FAIL linger-detection: task did not end up blocked (got $LD_STATUS)"
        fail=1
      else
        echo "  PASS lingering-blocked worker reaped (grace-then-kill), loop terminated cleanly, task blocked"
      fi
    else
      echo "  SKIP lingering-blocked worker (bd repo setup failed in tmp)"
    fi
    rm -rf "$LD" "$LMOCK" 2>/dev/null || true
  else
    echo "  SKIP lingering-blocked worker (bd not installed)"
  fi

  # Case 10 (ovi): a mid-run worker DEATH — parent claims, worker process dies WITHOUT closing —
  # must surface in the run-report as an in_progress ORPHAN + STATUS: STOPPED — INCOMPLETE, never a
  # bare "done". Real loop; mock worker = `false` (ignores stdin, exits non-zero = "died").
  if command -v bd >/dev/null 2>&1; then
    RR=$(mktemp -d /tmp/cmpl-rep-st.XXXXXX)
    if ( cd "$RR" && git init -q && git -c user.email=t@t -c user.name=t commit -qm i --allow-empty \
           && bd init proj --stealth ) >/dev/null 2>&1; then
      ( cd "$RR" && bd create "orphan-me" -t task --acceptance a --design d \
          --metadata '{"write_zone":["a"],"verify":"x"}' >/dev/null 2>&1 )
      RR_OUT="$( cd "$RR" && CMP_CLAUDE_CMD='false' CMP_STALL_SECS=25 CMP_WORKER_TIMEOUT=20 \
          timeout 40 bash "$SELF_ABS" --mode unattended 2>&1 )"
      if printf '%s' "$RR_OUT" | grep -q 'STOPPED — INCOMPLETE' \
         && printf '%s' "$RR_OUT" | grep -q 'in_progress ORPHAN'; then
        echo "  PASS run-report flags mid-run worker death (orphan + STOPPED — INCOMPLETE)"
      else
        echo "  FAIL run-report: mid-run death not flagged as orphan/incomplete"
        printf '%s\n' "$RR_OUT" | tail -8 | sed 's/^/      | /'
        fail=1
      fi
    else
      echo "  SKIP run-report orphan (bd repo setup failed in tmp)"
    fi
    rm -rf "$RR" 2>/dev/null || true
  else
    echo "  SKIP run-report orphan (bd not installed)"
  fi

  # Case 11 (kpt): a HEALTHY long worker that keeps emitting output past STALL_SECS must NOT be
  # stall-killed. Mock writes a line/second for ~8s (> STALL_SECS=4), then closes its task + exits.
  # NEGATIVE CONTROL: the old wall-clock-since-close stall fires at 4s -> kills -> orphan (RED);
  # the activity-based _stalled survives because the log keeps growing.
  if command -v bd >/dev/null 2>&1; then
    KD=$(mktemp -d /tmp/cmpl-kpt-XXXXXX); KMOCK=$(mktemp /tmp/cmpl-kpt-mock-XXXXXX.sh)
    cat > "$KMOCK" <<'MOCK'
#!/usr/bin/env bash
set -uo pipefail
in="$(cat)"; id="$(printf '%s' "$in" | sed -n 's/^Your assigned task: //p' | head -1)"
[ -n "$id" ] || exit 0
for n in $(seq 1 8); do echo "working chunk $n"; sleep 1; done
bd close "$id" >/dev/null 2>&1
echo "DONE $id"
MOCK
    chmod +x "$KMOCK"
    if ( cd "$KD" && git init -q && git -c user.email=t@t -c user.name=t commit -qm i --allow-empty \
           && bd init proj --stealth ) >/dev/null 2>&1; then
      ( cd "$KD" && bd create "longtask" -t task --acceptance a --design d \
          --metadata '{"write_zone":["a"],"verify":"true"}' >/dev/null 2>&1 )
      KD_OUT="$( cd "$KD" && CMP_CLAUDE_CMD="bash $KMOCK" CMP_PARALLEL=1 CMP_RUN_PROMPT="$PROMPT" \
          CMP_POLL_SECS=1 CMP_STALL_SECS=4 CMP_WORKER_TIMEOUT=60 CMP_TICK_GAP_MAX=60 \
          timeout 25 bash "$SELF_ABS" --mode unattended 2>&1 )"
      # Assert on stall + completion, NOT the run-report DONE/dirty verdict (the tmp repo doesn't
      # track .beads, so bd writes leave the tree "dirty" — unrelated to the stall fix under test).
      if printf '%s' "$KD_OUT" | grep -q 'killing in-flight workers'; then
        echo "  FAIL kpt: healthy long worker (output past STALL_SECS) was stall-killed"
        printf '%s\n' "$KD_OUT" | tail -8 | sed 's/^/      | /'; fail=1
      elif ! printf '%s' "$KD_OUT" | grep -q 'closed this run: 1'; then
        echo "  FAIL kpt: long worker did not complete its task (closed this run != 1)"
        printf '%s\n' "$KD_OUT" | tail -8 | sed 's/^/      | /'; fail=1
      else
        echo "  PASS healthy long worker survives stall window (activity-based), task closed"
      fi
    else
      echo "  SKIP kpt long-worker (bd repo setup failed in tmp)"
    fi
    rm -rf "$KD" "$KMOCK" 2>/dev/null || true
  else
    echo "  SKIP kpt long-worker (bd not installed)"
  fi

  # Case 12 (cva): a stale-heartbeat claim (worker_id set, old heartbeat) is reopened by the reaper
  # — the case pure process-death misses. An interactive claim (in_progress, NO worker_id) is left.
  if command -v bd >/dev/null 2>&1; then
    CD=$(mktemp -d /tmp/cmpl-cva-XXXXXX)
    if ( cd "$CD" && git init -q && git -c user.email=t@t -c user.name=t commit -qm i --allow-empty \
           && bd init proj --stealth ) >/dev/null 2>&1; then
      ( cd "$CD"
        bd create "orphaned" -t task --acceptance a --design d --metadata '{"write_zone":["a"],"verify":"x"}' >/dev/null 2>&1
        bd create "interactive" -t task --acceptance a --design d --metadata '{"write_zone":["b"],"verify":"x"}' >/dev/null 2>&1
        OID=$(bd list --json | python3 -c 'import json,sys;d=json.load(sys.stdin);d=d if isinstance(d,list) else d.get("issues",[]);print([i["id"] for i in d if i.get("title")=="orphaned"][0])')
        IID=$(bd list --json | python3 -c 'import json,sys;d=json.load(sys.stdin);d=d if isinstance(d,list) else d.get("issues",[]);print([i["id"] for i in d if i.get("title")=="interactive"][0])')
        bd update "$OID" --status in_progress >/dev/null 2>&1
        bd update "$IID" --status in_progress >/dev/null 2>&1
        bd update "$OID" --metadata '{"write_zone":["a"],"verify":"x","worker_id":"run-dead/pid999","heartbeat":1}' >/dev/null 2>&1 )
      CD_OUT="$( cd "$CD" && CMP_HEARTBEAT_STALE=300 bash "$SELF_ABS" --reap-orphans 2>&1 )"
      OST=$( cd "$CD" && bd list --json | python3 -c 'import json,sys;d=json.load(sys.stdin);d=d if isinstance(d,list) else d.get("issues",[]);print([i["status"] for i in d if i.get("title")=="orphaned"][0])')
      IST=$( cd "$CD" && bd list --json | python3 -c 'import json,sys;d=json.load(sys.stdin);d=d if isinstance(d,list) else d.get("issues",[]);print([i["status"] for i in d if i.get("title")=="interactive"][0])')
      if [ "$OST" = "open" ] && [ "$IST" = "in_progress" ]; then
        echo "  PASS cva reaper reopened stale-heartbeat claim, left interactive (no worker_id) untouched"
      else
        echo "  FAIL cva reaper: orphaned=$OST (want open), interactive=$IST (want in_progress)"
        printf '%s\n' "$CD_OUT" | tail -6 | sed 's/^/      | /'; fail=1
      fi
    else
      echo "  SKIP cva reaper (bd repo setup failed in tmp)"
    fi
    rm -rf "$CD" 2>/dev/null || true
  else
    echo "  SKIP cva reaper (bd not installed)"
  fi

  # Case 13 (b8n): after a batch of >=2 landed tasks, the integration gate runs over the UNION; a
  # non-composing union (CMP_INTEGRATION_CMD=false) files a BLOCKED integration bead, never a silent pass.
  if command -v bd >/dev/null 2>&1; then
    BD=$(mktemp -d /tmp/cmpl-b8n-XXXXXX); BMOCK=$(mktemp /tmp/cmpl-b8n-mock-XXXXXX.sh)
    cat > "$BMOCK" <<'MOCK'
#!/usr/bin/env bash
set -uo pipefail
in="$(cat)"; id="$(printf '%s' "$in" | sed -n 's/^Your assigned task: //p' | head -1)"
[ -n "$id" ] || exit 0
bd close "$id" >/dev/null 2>&1
MOCK
    chmod +x "$BMOCK"
    if ( cd "$BD" && git init -q && git -c user.email=t@t -c user.name=t commit -qm i --allow-empty \
           && bd init proj --stealth ) >/dev/null 2>&1; then
      ( cd "$BD"
        bd create "u-a" -t task --acceptance a --design d --metadata '{"write_zone":["a"],"verify":"true"}' >/dev/null 2>&1
        bd create "u-b" -t task --acceptance a --design d --metadata '{"write_zone":["b"],"verify":"true"}' >/dev/null 2>&1 )
      BD_OUT="$( cd "$BD" && CMP_CLAUDE_CMD="bash $BMOCK" CMP_PARALLEL=2 CMP_RUN_PROMPT="$PROMPT" \
          CMP_INTEGRATION_CMD=false CMP_INTEGRATION_MIN=2 CMP_STALL_SECS=60 \
          timeout 40 bash "$SELF_ABS" --mode unattended 2>&1 )"
      BD_BLK=$( cd "$BD" && bd list --status blocked --json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: d=[]
d=d if isinstance(d,list) else d.get("issues",[])
print("YES" if any("integration" in (i.get("title") or "") for i in d) else "NO")' )
      if printf '%s' "$BD_OUT" | grep -q 'INTEGRATION GATE FAILED' && [ "$BD_BLK" = "YES" ] \
         && printf '%s' "$BD_OUT" | grep -q 'STOPPED — INCOMPLETE'; then
        echo "  PASS integration gate catches a non-composing union -> blocked bead + STOPPED (not silent pass)"
      else
        echo "  FAIL b8n: union-fail not caught/blocked (blocked=$BD_BLK)"
        printf '%s\n' "$BD_OUT" | tail -12 | sed 's/^/      | /'; fail=1
      fi
    else
      echo "  SKIP b8n integration gate (bd repo setup failed in tmp)"
    fi
    rm -rf "$BD" "$BMOCK" 2>/dev/null || true
  else
    echo "  SKIP b8n integration gate (bd not installed)"
  fi

  if [ "$fail" = 0 ]; then echo "run/self-test: OK"; exit 0; else echo "run/self-test: FAILED"; exit 1; fi
