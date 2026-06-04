# The harness principle (stack-agnostic)

> **Agent = Model + Harness.** The harness is everything around the model — context,
> constraints, feedback loops, quality control. You don't improve an agent only by hoping
> the next model is smarter; you **engineer the environment so a given mistake can't recur
> the same way.** Quality is deterministic (hooks/tests), not trusted. "Done" requires proof.

## The flow (a funnel: heavy human involvement up front, autonomy in the middle, control at the end)

```
IDEA
 │
 ▼  A — UNDERSTAND & SPEC            ← you are involved
 │   socratic brainstorm (one question at a time, 2–3 approaches with trade-offs)
 │   → spec with acceptance criteria stating the FULL scope + non-functional needs
 │
 ▼  🚦 GATE 1: spec frozen = the single source of truth
 │
 ▼  B — ARCHITECTURE & PLAN         ← you review
 │   design doc → decompose into atomic tasks (2–5 min, each with a test BEFORE code)
 │   → task graph with dependencies in your tracker
 │
 ▼  🚦 GATE 2: review architecture + plan → say "GO"
 │
 ▼  C — AUTONOMOUS EXECUTION        ← you're out, except STOP-conditions
 │   loop over ready tasks, ONE at a time, FRESH context each:
 │     TDD (RED → GREEN → REFACTOR)
 │     → hooks (format/lint/types/security) auto, failures fed back
 │     → code-reviewer → security-reviewer
 │     → evaluator (DEFAULT-FAIL, read-only)
 │     → commit with task ID → close → next task, fresh context
 │
 ▼  🛑 surface to the human ONLY on STOP-conditions
 │
 ▼  D — ACCEPTANCE & CLOSEOUT       ← final review
     evidence checks, close tasks, push, report (what's proven, with command output)
```

Fresh context per task is the cure for both "loses context" and "cuts corners near the end
of the window" — the agent is always near the start of its context, making better decisions.

## Human gates + STOP-conditions

Two human gates, concentrated **before** execution. Inside C the agent works silently
**except** these — then it stops, returns `blocked`, and asks one concrete question:

1. **Spec ambiguity** — the task needs a decision not in the spec. Ask, don't guess.
2. **Scope conflict** — needs to leave its write-zone, touch a neighbouring module, or change a frozen contract.
3. **Security finding** not fixable within the task.
4. **Repeated failure** — task failed N times (e.g. 3); tests won't converge. Stop, don't disable the test.
5. **Forced downscope** — the full version can't be built as specified → `blocked` with a reason, **never a silent stub**.
6. **Architecture fork** not covered by the plan.

Everything else (routine compile errors, legitimately failing tests, small reviewer fixes) it fixes itself.

## Quality / security / readability layer

- **Machine (deterministic, via hooks):** format → lint → types → tests → security, on each
  edit; failures return to context. Dangerous commands blocked (exit 2).
- **Inferential (subagents):** `code-reviewer` (naming/complexity/duplication/dead code),
  `security-reviewer` (injection/authz/secrets/input validation), `evaluator` (acceptance,
  default-FAIL — agents over-grade themselves).
- **Readability is checkable:** cognitive-complexity limits, function length, duplication,
  no magic numbers.

## Self-tooling (no silent stubs)

A task that builds a tool/script/harness builds the **full** version. Any reduction is allowed
**only** via an explicit `blocked` return with a reason. Silent stubbing = task failure; the
evaluator flags it as FAIL. (see `self-tooling.md`)

## Two layers of the harness

- **Core (portable):** this principle, the evaluator, the gates' logic, the contracts. Says *how* you work.
- **Project thin layer:** the concrete stack commands (lint/typecheck/test), paths, the spec link. Says *what* exactly.

New project = copy the thin layer, fill in commands. The core never changes with the stack.

## Sober caveats

- **Token cost.** Multi-agent verification costs multiples of a single session. Add a fast-path for trivial work.
- **Don't duplicate the queue owner.** One tool owns task status. (see `roles.md`)
- **Hooks are finicky.** On invisible init failures, move a check into an explicit command the agent calls.
- **Models grow.** After an upgrade, disable harness parts one at a time and drop what became dead weight.
- **Ecosystem trust.** Skills/MCP only from trusted sources; review before running.
