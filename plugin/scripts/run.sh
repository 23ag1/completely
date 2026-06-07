#!/usr/bin/env bash
# completely :: run — drive `bd ready` with ONE engine, two modes (the autonomy dial).
#
#   unattended (Ralph-style): a fresh `claude -p` per iteration reading the Beads-aware overlay
#     prompt; ONE task per iteration; stop when `bd ready` is empty. This fixes two Ralph gaps:
#       • the done-definition is real (queue empty), not a vibe-loop;
#       • NO `--dangerously-skip-permissions` — the completely guard hook + an allowlist gate
#         dangerous ops instead (override the invocation via CMP_CLAUDE_CMD if you must).
#     It does NOT edit Ralph's files — it points a loop at our overlay prompt (overlay, not patch).
#
#   supervised: hand off to GSD's wave executor (interactive); completely gates + evaluator run
#     underneath either way.
#
# Parallelism (CMP_PARALLEL, default 4): each iteration the parent reads `bd ready`, greedily picks
# tasks whose `metadata.write_zone`s are DISJOINT from every running worker (and from each other),
# pre-claims each via `bd update --claim`, and spawns up to N fresh `claude -p` workers in parallel
# — each told its assigned task via an injected header. Same-write-zone tasks SERIALIZE (the next
# one waits for the current to finish). Beads stays the spine; the queue is still empty-when-done.
# Set CMP_PARALLEL=1 to fall back to strictly one-at-a-time (legacy flow). The worker's own commit
# step still uses `bd merge-slot` for the rare cross-zone file collision.
#
# Backend for `cmpl run` and the `/completely:run` skill.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT="${CMP_RUN_PROMPT:-$ROOT/overlays/ralph/PROMPT_build.completely.md}"
CLAUDE_CMD="${CMP_CLAUDE_CMD:-claude -p --permission-mode acceptEdits}"
MODE=unattended; MAX=0; DRY=0; SELF_TEST=0; SHOW_PROMPT_ID=""
PARALLEL="${CMP_PARALLEL:-4}"

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)         MODE="${2:-}"; shift 2 ;;
    --max)          MAX="${2:-0}"; shift 2 ;;
    --parallel)     PARALLEL="${2:-1}"; shift 2 ;;
    --dry-run)      DRY=1; shift ;;
    --self-test)    SELF_TEST=1; shift ;;
    --show-prompt)  SHOW_PROMPT_ID="${2:-DEMO}"; shift 2 ;;
    -h|--help)
      echo "cmpl run [--mode unattended|supervised] [--max N] [--parallel N] [--dry-run]"
      echo "         [--self-test] [--show-prompt <task-id>]"
      echo "  CMP_PARALLEL=N    max concurrent workers (default 4; 1 = legacy serial flow)"
      echo "  CMP_BENCH_LOG=...  forces PARALLEL=1 to avoid concurrent-write races on the log"
      echo "  --show-prompt   prints the exact stdin a worker would receive for <task-id>"
      echo "                  (no claim, no spawn) — trace evidence for the enforced-policy"
      echo "                  injection at PLAN-CHECK / security step boundaries."
      exit 0 ;;
    *) echo "run: unknown arg '$1'" >&2; exit 1 ;;
  esac
done

# bench mode collects each worker's JSON output to one log file; concurrent appends would interleave
# JSON objects. Force serial there. Operators can opt out only by reducing PARALLEL explicitly.
if [ -n "${CMP_BENCH_LOG:-}" ] && [ "$PARALLEL" -gt 1 ]; then
  echo "run: CMP_BENCH_LOG set — forcing --parallel 1 to keep the bench log race-free." >&2
  PARALLEL=1
fi

# ---------- dispatch helpers (pure Python, no side effects — testable via --self-test) ----------
# Reads ready JSON + the running-zones set from env, prints space-separated task IDs to dispatch
# now. The selector is greedy in priority order: keep a task only if its write_zone is disjoint
# from every running zone AND from every already-selected zone in this batch. A task with NO
# declared write_zone is treated as a global zone (serialized as if it touches everything) — that
# matches "stay inside the write-zone" being a worker-contract requirement.
#
# Inputs (env): CMP_READY_JSON (json text), CMP_RUNNING_ZONES_JSON (json [[...]] of zone lists),
#               CMP_SLOTS_FREE (int), CMP_DEBUG (1 to also emit a per-task decision trace).
_dispatch_py='
import json, os, sys
ready_raw = os.environ.get("CMP_READY_JSON","[]")
running = json.loads(os.environ.get("CMP_RUNNING_ZONES_JSON","[]"))
slots = int(os.environ.get("CMP_SLOTS_FREE","1"))
debug = os.environ.get("CMP_DEBUG","") == "1"

def zones_overlap(a, b):
    # "no declared write_zone" sentinel is the empty list — treat as the global zone (overlaps all).
    if a == [] or b == []:
        return True
    for pa in a:
        pa_n = pa.rstrip("/")
        for pb in b:
            pb_n = pb.rstrip("/")
            if pa_n == pb_n: return True
            if pa_n.startswith(pb_n + "/"): return True
            if pb_n.startswith(pa_n + "/"): return True
    return False

try:
    issues = json.loads(ready_raw)
except Exception:
    issues = []
issues = issues if isinstance(issues, list) else issues.get("issues", [])

picked, picked_zones, trace = [], [], []
for it in issues:
    if slots <= 0: break
    if it.get("issue_type") == "epic":
        continue
    if "checkpoint" in (it.get("labels") or []):
        trace.append((it.get("id"), "skip:checkpoint")); continue
    if it.get("status") not in (None, "open"):
        continue
    md = it.get("metadata") or {}
    zone = md.get("write_zone") or []
    if not isinstance(zone, list):
        zone = []
    if any(zones_overlap(zone, z) for z in running):
        trace.append((it.get("id"), "wait:overlap-running")); continue
    if any(zones_overlap(zone, z) for z in picked_zones):
        trace.append((it.get("id"), "wait:overlap-batch")); continue
    picked.append(it.get("id"))
    picked_zones.append(zone)
    slots -= 1
    trace.append((it.get("id"), "dispatch:" + (",".join(zone) if zone else "GLOBAL")))

# stdout: space-separated IDs (parent reads this). stderr (if CMP_DEBUG): one decision per line.
print(" ".join(picked))
if debug:
    for tid, reason in trace:
        sys.stderr.write(f"  · {tid}\t{reason}\n")
print(json.dumps(picked_zones), file=sys.stderr if not debug else sys.stderr)
'

# Resolve a task's write_zone (JSON array) by ID. Empty array means undeclared (global).
_zone_for_py='
import json, os, sys
tid = os.environ["CMP_LOOKUP_ID"]
ready_raw = os.environ.get("CMP_READY_JSON","[]")
try: data = json.loads(ready_raw)
except Exception: data = []
data = data if isinstance(data, list) else data.get("issues", [])
for it in data:
    if it.get("id") == tid:
        md = it.get("metadata") or {}
        z = md.get("write_zone") or []
        print(json.dumps(z if isinstance(z, list) else []))
        sys.exit(0)
print("[]")
'

dispatch_ids() {
  # Args: $1=ready_json $2=running_zones_json $3=slots_free
  CMP_READY_JSON="$1" CMP_RUNNING_ZONES_JSON="$2" CMP_SLOTS_FREE="$3" \
    python3 -c "$_dispatch_py" 2>/dev/null
}

zone_for() {
  # Args: $1=ready_json $2=task_id  → echoes a JSON array
  CMP_READY_JSON="$1" CMP_LOOKUP_ID="$2" python3 -c "$_zone_for_py"
}

# ---------- enforced-policy injection (step-bound system-style blocks) -----------------------------
# v0.11's weakness: thinking-models + security + path-exercised policy were named in task-engine.md but never delivered
# to the worker — the worker had to read the doc, then choose to apply them. We now inject the policy
# INLINE into the stdin prompt at spawn time, tagged to a specific step. The block text IS the rule
# (not a pointer to a file), so the worker can't no-op past it via "I didn't read that md".
#
# Honest scope: this is at-spawn injection for the `claude -p` worker (single fresh prompt per task).
# True mid-conversation injection at the actual step boundary requires the Messages API (system
# message appended live as the worker enters step 2 / step 6) — out of scope here. The trace below
# (--show-prompt) is the falsifiable evidence that the policy reached the worker.
ENFORCED_PLAN_CHECK='<<COMPLETELY_ENFORCED step=plan-check policy=thinking-models-planning>>
At STEP 2 (PLAN-CHECK) you MUST apply ALL of the following thinking-models before
proceeding to STEP 3 (DECOMPOSE). Each counters a documented agent failure mode —
skipping ANY is a stop-condition (`bd update --status blocked` + reason in a comment):
  · Pre-Mortem        — name 3 ways this task could ship "done" but be broken.
  · MECE-Decomposition — list sub-streams; verify mutually exclusive AND collectively
                         exhaustive over the acceptance criteria + metadata.must_haves.
  · Constraint-Analysis — name the BINDING constraint (write_zone, deps, context budget).
  · Reversibility-Test — classify each non-trivial choice as reversible vs. one-way.
Quote each model briefly in your plan-check comment on the bead BEFORE you start STEP 4.
No applied model, no build.
<<END_ENFORCED>>'

ENFORCED_SECURITY='<<COMPLETELY_ENFORCED step=review policy=security>>
At STEP 6 (REVIEW) you MUST spawn the **security-reviewer** subagent (Task tool) — not
inline reasoning — whenever the diff touches ANY of: user-input handling, authn/authz,
secret/token storage, SQL/shell/HTML/URL interpolation, deserialization, file ingestion,
crypto primitives, or sandbox/permission boundaries. Treat its CRITICAL and HIGH findings
as BLOCKING: fix in this task, or `bd update --status blocked` with the finding quoted.
Do NOT paraphrase its verdict — quote the relevant findings on the bead in STEP 9 (LAND).
<<END_ENFORCED>>'

ENFORCED_VERIFY='<<COMPLETELY_ENFORCED step=verify policy=path-exercised>>
At STEP 7 (VERIFY) your evidence MUST exercise the real runtime path, not a proxy.
Tests-green != failing-path-exercised: a passing unit, a --dry-run, or a mock at the wrong layer
can stay green while the production code path never runs. For each behavioral acceptance criterion:
  · name the real runtime path (the entrypoint it runs through in production) + its failure surface;
  · cite evidence that invokes THAT entrypoint end-to-end — a unit / dry-run / wrong-layer-mock
    ALONE means the criterion is unproven (stop-condition);
  · supply a negative control — break the impl along its failure surface (a throwaway copy, NEVER
    the repo) and show the cited test goes RED; a test that stays green when the impl is broken is
    vacuous.
For orchestration/shell, drive the real loop with a mock backend (CMP_CLAUDE_CMD=true). Post the
real-path command + its output on the bead in STEP 9 (LAND). A proxy-only claim is a stop-condition.
<<END_ENFORCED>>'

# Build the exact stdin a worker will receive for a given task. Pure function — no Beads writes,
# no spawn — so it's safe to call from --show-prompt and --self-test for trace evidence.
build_worker_prompt() {
  # $1 = task_id
  local tid="$1"
  printf '<<COMPLETELY_DISPATCH>>\n'
  printf 'Your assigned task: %s\n' "$tid"
  printf 'The parent has ALREADY claimed it for you (bd update %s --claim).\n' "$tid"
  printf 'Skip the selection part of step 0 — read THIS task directly:\n'
  printf '  bd show %s\n' "$tid"
  printf 'Then proceed step 1 (UNDERSTAND) onward. Stay inside its write-zone.\n'
  printf 'If you cannot proceed: bd update %s --status blocked + a comment with the reason.\n' "$tid"
  printf '<<END_DISPATCH>>\n\n'
  printf '%s\n\n' "$ENFORCED_PLAN_CHECK"
  printf '%s\n\n' "$ENFORCED_SECURITY"
  printf '%s\n\n' "$ENFORCED_VERIFY"
  cat "$PROMPT"
}

# ---------- self-test: prove disjoint-parallel + same-zone-serial WITHOUT calling claude ----------
if [ "$SELF_TEST" = 1 ]; then
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
    '<<COMPLETELY_ENFORCED step=verify' \
    'policy=path-exercised' \
    'real runtime path' \
    'negative control' \
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

  if [ "$fail" = 0 ]; then echo "run/self-test: OK"; exit 0; else echo "run/self-test: FAILED"; exit 1; fi
fi

# --show-prompt: trace evidence — print the exact stdin a worker would receive, no side effects.
# Runs before the bd / .beads preflight so it works in any directory (testable without a repo).
if [ -n "$SHOW_PROMPT_ID" ]; then
  if [ ! -f "$PROMPT" ]; then
    echo "run: overlay prompt missing: $PROMPT — printing injected header + policy only" >&2
    PROMPT=/dev/null build_worker_prompt "$SHOW_PROMPT_ID"
  else
    build_worker_prompt "$SHOW_PROMPT_ID"
  fi
  exit 0
fi

command -v bd >/dev/null 2>&1 || { echo "run: bd (beads) not installed" >&2; exit 1; }
[ -d .beads ] || { echo "run: no .beads here — run from a repo with 'bd init'" >&2; exit 1; }

# Land-step guard: the engine commits per task BEFORE closing it (commit-before-close). With no
# usable git author identity that commit silently fails — and a task could close with uncommitted
# code (observed during dogfood). Ensure a repo-local identity up front so per-task commits always
# land (override via your own git config). Deterministic preflight; per-task ordering still lives
# in the task engine.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
   && [ -z "$(git config user.email 2>/dev/null)" ]; then
  git config user.email "completely-agent@localhost"
  git config user.name "completely agent"
  echo "run: no git identity found — set repo-local fallback (completely agent) so per-task commits land."
fi

# count ready WORK (exclude the epic container itself)
ready_count() {
  bd ready --json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: d=[]
d=d if isinstance(d,list) else d.get("issues",[])
print(sum(1 for i in d if i.get("issue_type")!="epic"))'
}

if [ "$MODE" = supervised ]; then
  echo "run/supervised: Beads-driven waves (ready front from 'bd swarm status' / 'bd ready')."
  CP="$(bd ready --json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: d=[]
d=d if isinstance(d,list) else d.get("issues",[])
for it in d:
    if it.get("issue_type")=="epic": continue
    if "checkpoint" in (it.get("labels") or []):
        print(it["id"], it.get("title",""), sep="  "); break
')"
  if [ -n "$CP" ]; then
    echo "  ⏸ checkpoint pending: $CP"
    echo "     verify it, then: bd close <id>  (downstream waves stay blocked until then)"
    exit 0
  fi
  NEXT="$(bd ready --json 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: d=[]
d=d if isinstance(d,list) else d.get("issues",[])
for it in d:
    if it.get("issue_type")=="epic": continue
    if "checkpoint" in (it.get("labels") or []): continue
    print(it["id"]); break
')"
  if [ -z "$NEXT" ]; then echo "  bd ready is empty — nothing to do."; exit 0; fi
  echo "  next task: $NEXT — its contract:"
  bd show "$NEXT" 2>/dev/null | sed -n '1,18p' | sed 's/^/    /'
  echo "  → run the FULL task engine on THIS ONE task (skill /completely:control · core/task-engine.md):"
  echo "    understand(map/research) → plan-check → parallel subagents (merge-slot) → TDD + craft skills"
  echo "    → cmpl check + cmpl lint → code-reviewer + security-reviewer → gsd-verifier + evaluator"
  echo "    → evidence comment → bd close (only if ACCEPTED). Pause at gates; STOP after this one task."
  exit 0
fi

[ -f "$PROMPT" ] || { echo "run: overlay prompt missing: $PROMPT" >&2; exit 1; }

closed_count() { bd list --status closed --json 2>/dev/null | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: d=[]
print(len(d if isinstance(d,list) else d.get("issues",[])))'; }

# ---------- worker spawn (one fresh claude -p; reads the assigned task ID from injected header) ----
# We pre-claim the task in the parent so concurrent workers can't race for the same ready item, then
# pipe the constructed prompt (dispatch header + enforced policy blocks + overlay) to stdin.
spawn_worker() {
  # $1 = task_id  $2 = log_file_path
  local tid="$1" log="$2"
  build_worker_prompt "$tid" | $CLAUDE_CMD >"$log" 2>&1
}

# ---------- main loop: rolling parallel dispatch over `bd ready` ----------
# Bash gotcha: under `set -u`, `${#assoc[@]}` errors on a never-assigned-to associative array. Keep
# an explicit NRUN counter alongside the maps so the loop arithmetic is always defined.
declare -A PID_TASK=() PID_ZONE=() PID_LOG=() PID_START=() PID_DONE_AT=()
NRUN=0
i=0; prev_closed="$(closed_count)"
NOW() { date +%s; }
LAST_PROGRESS_TS="$(NOW)"

# Linger/stall knobs (wall-clock, seconds). Override via env in tests.
#   CMP_POLL_SECS         — saturated-wait poll cadence (no more bare wait -n that hangs forever).
#   CMP_WORKER_GRACE      — grace after bd shows task closed/blocked before we kill a lingering pid.
#   CMP_WORKER_TIMEOUT    — absolute per-worker wall-clock cap (kill regardless of bd state).
#   CMP_STALL_SECS        — no-progress wall-clock cap (advances even while NRUN>0 — the evaluator's
#                            blind-spot fix: the old iteration-counter was gated on NRUN==0 and never
#                            ticked while a worker lingered forever).
POLL_SECS="${CMP_POLL_SECS:-2}"
WORKER_GRACE="${CMP_WORKER_GRACE:-30}"
WORKER_TIMEOUT="${CMP_WORKER_TIMEOUT:-1800}"
STALL_SECS="${CMP_STALL_SECS:-600}"

# zones currently in flight, as a JSON array of arrays — fed to dispatch_ids each iteration.
running_zones_json() {
  local pid lines=""
  for pid in "${!PID_ZONE[@]}"; do
    lines+="${PID_ZONE[$pid]}"$'\n'
  done
  printf '%s' "$lines" | python3 -c '
import json, sys
xs = []
for line in sys.stdin.read().splitlines():
    if not line.strip(): continue
    try: xs.append(json.loads(line))
    except Exception: pass
print(json.dumps(xs))'
}

# Resolve a task's bd status (open|in_progress|closed|blocked|…). Empty string if unknown.
bd_status_for() {
  bd show "$1" --json 2>/dev/null | python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: d = []
if isinstance(d, list):
    d = d[0] if d else {}
elif isinstance(d, dict):
    d = d.get("issue") or d
print((d or {}).get("status") or "")' 2>/dev/null
}

# Drop tracking for one PID + free its slot + clean log + mark progress made.
_drop_pid() {
  local pid="$1"
  [ -f "${PID_LOG[$pid]:-/dev/null}" ] && rm -f "${PID_LOG[$pid]}" 2>/dev/null || true
  unset 'PID_TASK[$pid]' 'PID_ZONE[$pid]' 'PID_LOG[$pid]' 'PID_START[$pid]' 'PID_DONE_AT[$pid]'
  NRUN=$((NRUN > 0 ? NRUN - 1 : 0))
  LAST_PROGRESS_TS="$(NOW)"
}

# Bounded kill: SIGTERM, brief grace, SIGKILL. Reaps the child's exit too.
_kill_worker() {
  local pid="$1"
  kill -TERM "$pid" 2>/dev/null || true
  # short grace for graceful shutdown
  local g=0
  while [ "$g" -lt 3 ] && kill -0 "$pid" 2>/dev/null; do sleep 1; g=$((g+1)); done
  kill -KILL "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

reap_finished() {
  # Walk our tracked PIDs once. For each:
  #   · already exited → wait + log tail + drop.
  #   · alive AND bd shows task closed/blocked → it's a "finished-but-not-exited" linger.
  #       Mark first-seen, wait WORKER_GRACE seconds, then kill+drop. This is the bug the bead
  #       names: p4f committed + marked blocked but the claude pid hung around for 29min, NRUN
  #       never dropped, and downstream disjoint work never dispatched.
  #   · alive AND running too long (WORKER_TIMEOUT) → kill+drop. Backstop against generic hangs.
  # Also: every iteration, refresh prev_closed and bump LAST_PROGRESS_TS on any new close — that's
  # the wall-clock progress signal that subsumes the old NRUN==0-gated counter.
  local pid now; now="$(NOW)"
  for pid in "${!PID_TASK[@]}"; do
    local tid="${PID_TASK[$pid]}" log="${PID_LOG[$pid]}"
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null || true
      echo "run: worker pid=$pid task=$tid finished — log tail:"
      [ -f "$log" ] && tail -8 "$log" | sed 's/^/    /' || echo "    (no log)"
      _drop_pid "$pid"
      continue
    fi
    # Alive: classify.
    local s; s="$(bd_status_for "$tid")"
    if [ "$s" = "closed" ] || [ "$s" = "blocked" ]; then
      if [ -z "${PID_DONE_AT[$pid]:-}" ]; then
        PID_DONE_AT[$pid]="$now"
        echo "run: worker pid=$pid task=$tid settled in bd ($s) but pid still alive — grace ${WORKER_GRACE}s before reap"
      fi
      local done_at="${PID_DONE_AT[$pid]}"
      if [ "$((now - done_at))" -ge "$WORKER_GRACE" ]; then
        echo "run: reaping lingering worker pid=$pid task=$tid (state=$s, waited $((now - done_at))s)"
        _kill_worker "$pid"
        _drop_pid "$pid"
      fi
    else
      local start="${PID_START[$pid]:-$now}"
      if [ "$((now - start))" -ge "$WORKER_TIMEOUT" ]; then
        echo "run: worker pid=$pid task=$tid exceeded WORKER_TIMEOUT ${WORKER_TIMEOUT}s — killing"
        _kill_worker "$pid"
        _drop_pid "$pid"
      fi
    fi
  done
  local cc; cc="$(closed_count)"; cc="${cc:-0}"
  if [ "$cc" -gt "${prev_closed:-0}" ]; then
    prev_closed="$cc"
    LAST_PROGRESS_TS="$(NOW)"
  fi
}

# Bounded wait for a worker slot to free. NEVER `wait -n`: a lingering child whose process refuses
# to exit makes that block forever (the original failure mode). Instead poll-then-reap and check
# the wall-clock stall budget on every tick so the loop always makes a decision.
wait_for_slot() {
  while [ "$NRUN" -ge "$PARALLEL" ]; do
    sleep "$POLL_SECS"
    reap_finished || true
    local now; now="$(NOW)"
    if [ "$((now - LAST_PROGRESS_TS))" -ge "$STALL_SECS" ]; then
      echo "run: no progress for ${STALL_SECS}s while saturated — killing in-flight workers and stopping."; STOP_REASON="stall"
      _kill_all_workers
      return 1
    fi
  done
  return 0
}

_kill_all_workers() {
  local pid
  for pid in "${!PID_TASK[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  sleep 1
  for pid in "${!PID_TASK[@]}"; do
    kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    _drop_pid "$pid"
  done
}

# ---------- run-report: honest exit summary. DONE only if queue empty + no orphans + clean tree ----
# The loop must NEVER let a user assume "done" when in_progress orphans or a dirty tree remain
# (the overnight-run scenario: it stopped, left mess, and a near-empty `bd ready` looked finished).
run_report() {
  [ "$DRY" = 1 ] && return 0
  local reason="${1:-unknown}" closed_now blocked_n inprog inprog_ids dirty_n
  closed_now=$(( $(closed_count) - ${START_CLOSED:-0} ))
  inprog_ids="$(bd list --status in_progress --json 2>/dev/null | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: d=[]
d=d if isinstance(d,list) else d.get("issues",[])
print(" ".join(i["id"] for i in d if i.get("issue_type")!="epic"))' 2>/dev/null)"
  inprog=$(printf '%s' "$inprog_ids" | wc -w)
  blocked_n="$(bd list --status blocked --json 2>/dev/null | python3 -c 'import json,sys
try: d=json.load(sys.stdin)
except Exception: d=[]
print(len(d if isinstance(d,list) else d.get("issues",[])))' 2>/dev/null)"
  dirty_n=0
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 && dirty_n=$(git status --porcelain 2>/dev/null | wc -l)
  echo ""
  echo "================= run-report ================="
  if [ "${inprog:-0}" -eq 0 ] && [ "${dirty_n:-0}" -eq 0 ]; then
    echo "  STATUS: DONE — ready queue empty, no in_progress orphans, clean tree"
  else
    echo "  STATUS: STOPPED — INCOMPLETE (do NOT assume done)"
    [ "${inprog:-0}" -gt 0 ] && echo "    · ${inprog} in_progress ORPHAN(s): ${inprog_ids}   (reset: bd update <id> --status open)"
    [ "${dirty_n:-0}" -gt 0 ] && echo "    · ${dirty_n} uncommitted tree file(s) — commit or revert"
  fi
  echo "  closed this run: ${closed_now}    blocked: ${blocked_n}    stop reason: ${reason}"
  echo "  spend: ${RUN_SPEND:-n/a (track via CMP_BENCH_LOG or claude -p --output-format json)}"
  echo "=============================================="
}

STOP_REASON=""
START_CLOSED="$(closed_count)"
while true; do
  # Reap any finished/settled workers (non-blocking) so freed slots get refilled on this tick.
  reap_finished || true

  n="$(ready_count)"; n="${n:-0}"
  if [ "$n" -le 0 ] && [ "$NRUN" -eq 0 ]; then
    echo "run: ready queue drained after $i iteration(s)."; STOP_REASON="queue-empty"; break
  fi

  free=$(( PARALLEL - $NRUN ))
  if [ "$free" -le 0 ]; then
    if ! wait_for_slot; then break; fi
    continue
  fi

  # Snapshot the queue + currently-running zones, then ask the dispatcher who to send next.
  ready_json="$(bd ready --json 2>/dev/null || echo '[]')"
  rzj="$(running_zones_json)"
  ids="$(dispatch_ids "$ready_json" "$rzj" "$free")"

  if [ -z "$ids" ]; then
    # Nothing else dispatchable right now (everything pending overlaps something running, or queue
    # is fully empty). If workers are alive, poll until one frees up; if not, we're truly done.
    if [ "$NRUN" -gt 0 ]; then
      if ! wait_for_slot; then break; fi
      continue
    else
      echo "run: ready queue drained after $i iteration(s)."; STOP_REASON="queue-empty"; break
    fi
  fi

  for tid in $ids; do
    zone_json="$(zone_for "$ready_json" "$tid")"
    i=$((i+1))
    echo "run: iteration $i — dispatch task=$tid zone=$zone_json (running=$NRUN of $PARALLEL)"

    if [ "$DRY" = 1 ]; then
      # Trace-only mode: show the dispatch decision without claiming or spawning. Loop once, then
      # exit so callers can capture the plan. Preserves the legacy dry-run shape (top of queue +
      # would-run command) and extends it with the parallel plan.
      echo "  [dry-run] would claim:     bd update $tid --claim"
      echo "  [dry-run] would spawn:     cat \"$PROMPT\" | $CLAUDE_CMD   (with task=$tid header)"
      echo "  [dry-run] write_zone:      $zone_json"
      continue
    fi

    if ! bd update "$tid" --claim >/dev/null 2>&1; then
      echo "  · claim failed for $tid (another agent grabbed it?) — skipping this iteration"
      continue
    fi

    log="$(mktemp /tmp/cmpl-run-XXXXXX.log)"
    if [ -n "${CMP_BENCH_LOG:-}" ]; then
      # Serial bench mode: capture the full JSON output into the shared log (PARALLEL was forced 1
      # at startup, so no race).
      _out="$(spawn_worker "$tid" "$log" && cat "$log")"
      printf '%s\n' "$_out" >> "$CMP_BENCH_LOG"
      printf '%s\n' "$_out" | tail -8
      rm -f "$log"
    else
      spawn_worker "$tid" "$log" &
      pid=$!
      PID_TASK[$pid]="$tid"
      PID_ZONE[$pid]="$zone_json"
      PID_LOG[$pid]="$log"
      PID_START[$pid]="$(NOW)"
      NRUN=$((NRUN + 1))
    fi
  done

  if [ "$DRY" = 1 ]; then
    echo "  [dry-run] single pass only; no execution."
    break
  fi

  # push only when asked (CMP_PUSH=1) — default is local commits, so a half-done run never
  # pushes broken intermediate state to the remote.
  [ "${CMP_PUSH:-0}" = 1 ] && { git push >/dev/null 2>&1 || true; }

  # Wall-clock stall: works whether NRUN is 0 or >0. The old iteration-counter ticked only when
  # NRUN==0, which let a lingering-but-alive worker hold the loop hostage indefinitely.
  now_ts="$(NOW)"
  if [ "$((now_ts - LAST_PROGRESS_TS))" -ge "$STALL_SECS" ]; then
    echo "run: no progress (no close/reap) for ${STALL_SECS}s — stopping; killing in-flight workers."
    echo "     inspect 'bd list --status in_progress' for abandoned claims (reset: bd update <id> --status open)."
    _kill_all_workers
    STOP_REASON="stall"; break
  fi
  if [ "$MAX" -gt 0 ] && [ "$i" -ge "$MAX" ]; then
    echo "run: reached max $MAX iteration(s) — draining in-flight workers."
    while [ "$NRUN" -gt 0 ]; do
      if ! wait_for_slot; then break; fi
    done
    STOP_REASON="max"; break
  fi
done

run_report "$STOP_REASON"
