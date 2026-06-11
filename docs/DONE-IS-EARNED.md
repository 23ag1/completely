# Done is earned: what happens when you put a default-FAIL evaluator in the close path of an autonomous coding loop

*A field report from building [completely](https://github.com/23ag1/completely) — written from the
incident log of the harness building itself. Every failure below is real, dated in the repo's
history, and shipped with a contract test so it can't come back.*

---

## The problem nobody's gate catches

Autonomous coding agents don't usually fail loudly. They fail **politely**:

- "All tests pass" — *no output attached.*
- A feature quietly becomes a stub, because the full version was hard.
- A failing test gets skipped, and the suite goes green.
- A task closes "done" with the code never committed.
- The code passes every test and is still wrong — because the tests exercise a mock,
  and the production path never runs.

The standard responses — a longer `CLAUDE.md`, a "be careful" prompt, a self-review step — share
one flaw: **they ask the same agent that did the work to grade the work.** Agents systematically
over-grade themselves. Not maliciously; the trajectory that produced the bug also produces the
justification for it.

The fix we bet on is structural, not rhetorical: an **independent, read-only evaluator** that runs
at the end of every task, starts every acceptance criterion at **FAIL**, and only flips a criterion
to PASS on **evidence it re-ran itself**. The loop will not close a task the evaluator rejected —
`bd close` is physically gated behind the verdict, next to a commit-before-close hook and a
binding-findings hook, all of which refuse with a non-zero exit rather than a polite warning.

"Done" stops being an assertion. It becomes a verdict.

That's the design. What follows is what it actually caught — and, more interestingly, the three
times the *harness itself* turned out to be lying, and what each incident added to the evaluator.

## Incident 1: the crash that shipped fully green

The loop's parallel dispatcher (greedy dispatch of tasks with disjoint write-zones to concurrent
fresh-context workers) shipped with a **9/9 passing self-test and a clean `--dry-run`**. The
evaluator ACCEPTED it.

In the first real run, the spawn loop crashed instantly: a bash array expansion
(`${!PID_TASK[@]}`) was malformed in exactly the branch that only executes when a *real* worker is
spawned. The unit-style self-test drove the *selection* logic with mocks; the dry-run short-circuits
before spawning. **Both were green. Neither ever executed the production path.**

What it added: the **Path-Exercised** dimension, now a standard (non-optional) step of the
evaluator. For every behavioral criterion: name the real runtime entrypoint, confirm the cited
evidence drives *that* entrypoint end-to-end, and demand a **negative control** — break the
implementation along its failure surface and show the cited test goes red. A test that stays green
when the implementation is broken is vacuous, and "tests-green" stopped being acceptable evidence
on its own. The cheap convention for orchestration code: drive the real loop with a mock *backend*
(`CMP_CLAUDE_CMD=true`), so the spawn/reap path actually runs without LLM spend.

## Incident 2: the evaluator rejects the fix for incident 1 — twice

The task that implemented Path-Exercised was itself submitted to the evaluator. It REJECTED the
work. Twice.

First rejection: the "evidence" was a narrative — a well-written description of a negative control,
not a *reproducible artifact* anyone could re-run. Second rejection: the negative-control procedure
asked the (read-only) evaluator to edit files, which it cannot do, and the rule over-applied to pure
functions where a unit test *is* the production surface.

The work only passed once the negative control existed as **committed fixtures** (a broken-A /
fixed-B pair under `plugin/tests/fixtures/path-exercised/`), the verification step was re-written to
be read-only-executable, and the rule got an explicit pure-logic carve-out.

This is the part we'd underline for anyone building a harness: the value of a default-FAIL gate is
not that it catches *bad* work — it's that it catches **plausible** work. The fix for the
verification blind spot was itself plausibly-but-not-actually verifiable, and only an evaluator with
a "no reproducible evidence = FAIL" rule refused to take the story for the artifact.

## Incident 3: the watchdog murders a healthy worker

Used on a real product build, the unattended loop stopped overnight with `STOPPED — INCOMPLETE`, an
orphaned in-progress task, and uncommitted work. The post-mortem was embarrassing in the best way:

- The stall detector measured "*time since the last task closed*". Its threshold (600s) was lower
  than the per-worker timeout (1800s). Any honest task that takes longer than ten minutes — normal
  for a TDD-plus-reviewers pipeline — was killed *while healthy and within its own budget*.
- The self-test for the stall detector proved it **fires** on a wedged loop. It never proved it
  **doesn't fire** on a slow healthy worker. A false-positive is indistinguishable from a pass in a
  test suite with no negative control — the same class of lie as incident 1, one layer up.
- Worse: the recovery doc said "just re-run, interrupted tasks are left open." They aren't — an
  interrupted task is left *claimed*, the ready-queue filter skips claimed tasks, and a re-run
  silently ignores it. The "resumable" claim was false in exactly the scenario it described.

What it added: stall detection became **activity-based** (a worker whose log is still growing is
alive, regardless of when anything last closed — and time the launching session spent suspended is
forgiven, not charged as "no progress"); claims now carry a **worker-id and heartbeat**, and a
startup reaper reopens any claim whose holder is gone or stale, with an audit comment; and the loop
ends every run with a **run-report** that refuses to say DONE unless the queue is empty, no claims
are orphaned, the tree is clean, *and a post-batch integration gate confirms the parallel workers'
combined output actually composes* — because N tasks that each pass in isolation can still fail to
work together. Each behavior has a contract test with a negative control, including "a healthy
worker that emits output past the stall window MUST survive."

## Incident 4: the gate that passed its own test and didn't exist

The most instructive one. We added an edit-time **write-zone fence**: a hook that rejects any file
edit outside the current task's declared write-zone (this is what makes parallel disjoint-zone
dispatch safe). Its self-test passed — six assertions, deny-outside, allow-inside, the lot.

A later adversarial audit asked one question the self-test didn't: *does the production spawn path
actually set the environment variable the hook keys on?* It didn't. The test set
`CMP_WORKER_BEAD=...` manually; the real worker spawn never exported it. **The fence was installed,
tested, green — and dead in every real worker session.** One line (`CMP_WORKER_BEAD="$tid"` on the
spawn) fixed it; the audit pattern that found it ("default every claim to MISSING, flip only on
quoted file:line evidence from the *production* path") is the same default-FAIL stance, applied to
the harness instead of the task.

What it added: the **Code-Read** dimension — the evaluator must read the actual diff and re-derive
its correctness (inverted conditions, swallowed errors, fail-open defaults, the wiring between a
component and the path that's supposed to invoke it), independent of the code-reviewer's verdict,
and a verdict reached without reading the changed code is itself a FAIL. Plus **User-Perceived
Correctness**: exercise the artifact the way a user would — run the command, hit the endpoint,
screenshot the UI — and *no run, no observed behavior = FAIL*, because every other gate measures
the written contract and none of them observes what a human actually gets.

## The shape that falls out

Four incidents, one pattern: **every layer that validates something must itself be validated against
the production path, with a negative control.** The harness's current shape is just that pattern
applied recursively:

| Layer | The lie it blocks | Mechanism |
|---|---|---|
| Per-edit gate hook | "I'll lint later" | lint/typecheck on every edit |
| Write-zone fence | parallel workers colliding | edit-time deny outside the task's zone |
| Commit-before-close hook | closed task, uncommitted code | `bd close` refused while tree is dirty |
| Binding-findings hook | "reviewer noted, moving on" | close refused while CRITICAL/HIGH findings open |
| Evaluator: default-FAIL | "trust me, it's done" | criterion stays FAIL without re-run evidence |
| Evaluator: Path-Exercised | green tests over a dead path | name the entrypoint + negative control |
| Evaluator: User-Perceived | passes contract, janky to humans | exercise as a user; no run = FAIL |
| Evaluator: Code-Read | subtly wrong code, green suite | read the diff, re-derive correctness |
| Run-report + integration gate | "the overnight run finished" | DONE only if queue empty + no orphans + clean tree + the batch composes |

None of this is magic, and it's worth being precise about the limits: the evaluator is an LLM
grading evidence — its value is **structural** (it cannot be skipped, it defaults to FAIL, it is
not the agent that did the work), not infallibility. The whole stack costs multiples of a single
session in tokens; we keep a fast path for trivial edits. And the deterministic parts — the hooks,
the contract suite (77 contracts at the time of writing), the orphan reaper — carry the load
precisely *because* they don't reason.

But the bet has paid for itself four times over in its own build log: a crash, an over-graded
verification scheme, a self-killing watchdog, and a dead safety gate — each shipped "green," each
caught by a layer whose only job is to refuse a plausible story without evidence.

**Done is earned, not asserted.** The rest is plumbing to make that sentence enforceable.

---

*The harness, its evaluator contract, the hooks, and the full test suite are open source:
[github.com/23ag1/completely](https://github.com/23ag1/completely). The evaluator's exact rules
live in [`plugin/agents/evaluator.md`](../plugin/agents/evaluator.md); the per-task engine in
[`plugin/core/task-engine.md`](../plugin/core/task-engine.md).*
