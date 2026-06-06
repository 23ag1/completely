# Path-Exercised — committed negative-control artifact (claude-harness-tu3.1)

Reproducible proof that the evaluator's **Path-Exercised** dimension (`plugin/agents/evaluator.md`)
*causes* proxy-green evidence to be REJECTED — and is not a blanket reject. This is the committed
artifact the evaluator demanded in place of a narrative.

## The A/B (same grader model, same proxy-green fixture, ONLY the contract differs)

| Arm | Contract | Fixture | Verdict |
|-----|----------|---------|---------|
| A (control) | OLD `git show HEAD~1:plugin/agents/evaluator.md` | `proxy-green-evidence.md` | **ACCEPTED** (reproduces the blind spot) |
| B | NEW `plugin/agents/evaluator.md` | `proxy-green-evidence.md` | **REJECTED** — "real path not exercised" |
| B' | NEW `plugin/agents/evaluator.md` | `real-path-evidence.md` | **ACCEPTED** (not a blanket reject) |

Verdict flips ACCEPT→REJECT solely from the new dimension → the dimension is **causal**, and B'
shows it still ACCEPTs genuinely real-path evidence.

## Re-run it yourself (the verify command)

Spawn a faithful grader (any capable model) told to *"apply EXACTLY the contract in <file>, invent no
criteria beyond it"* on each arm:

- **A:** contract `git show HEAD~1:plugin/agents/evaluator.md` · fixture `proxy-green-evidence.md` → expect **ACCEPTED**
- **B:** contract `plugin/agents/evaluator.md` · fixture `proxy-green-evidence.md` → expect **REJECTED** (path not exercised)
- **B':** contract `plugin/agents/evaluator.md` · fixture `real-path-evidence.md` → expect **ACCEPTED**

Deterministic sub-proof (no LLM) that the proxy fixture's cited commands never run the real path is
embedded in `proxy-green-evidence.md`.

## Recorded grader verdicts (captured during tu3.1 execution)

**Arm A — OLD contract on proxy-green → ACCEPTED:**
> VERDICT: ACCEPTED — "Both acceptance criteria are met with direct, reproduced evidence … self-test
> Case 1 (`t-a t-b`), `--dry-run --parallel 3` (3 disjoint tasks), suite 39 passed."
(The old contract has no path-exercised requirement, so the unit + dry-run satisfy "a test/trace shows…".)

**Arm B — NEW contract on proxy-green → REJECTED:**
> EVIDENCE SET 1 → REJECTED. "All three cited evidences short-circuit before the real production
> path. `--self-test` only calls the pure `dispatch_ids` selector + `exit`s — it never reaches
> `spawn_worker`/`reap_finished`; `--dry-run` `continue`/`break`s, never populating `PID_TASK`. The
> real failure surface is the bash `set -u` array-iteration in the spawn/reap loop, which none of
> this evidence exercises, and there is no negative control on that path. Stays FAIL: real path not
> exercised."

**Arm B' — NEW contract on real-path → ACCEPTED:**
> EVIDENCE SET 2 → ACCEPTED. "The `CMP_CLAUDE_CMD=true … --mode unattended` run drives the actual
> loop … the negative control mutates the true failure surface and goes RED: I reproduced the
> documented `invalid variable name` crash from the old array-iteration guard, wired into
> contracts.sh — meeting the mutation-on-the-real-path mandate."

(Grader B independently reverted the loop fix and reproduced the crash to confirm the mutation
requirement — i.e. it exercised the real path itself.)
