# The flow — Beads-first (no markdown bridge in steady state)

Steady state has **no markdown plan**. Planning writes structure straight into Beads; the queue is
the single source of truth from the first planning act.

```
idea → /completely:plan  (socratic discovery + decompose + goal-backward self-check)
        → emits structured JSON → cmpl plan-apply
        → Beads: epic + worker-contract tasks + deps + checkpoints + bd swarm (native waves)
   🚦 you review bd ready / bd swarm status, then "go"
        → cmpl run :
             supervised  → drive the swarm's ready front wave-by-wave (gates pause on checkpoints)
             unattended  → one task per fresh claude -p over bd ready, stop when empty
        → per task: TDD → quality hooks → reviewers → evaluator(default-FAIL) → bd close + commit
```

No `PLAN.md`, no `STATE.md`, no `PROGRESS.md`, no `IMPLEMENTATION_PLAN.md`. Status, plan rationale
(`design`), acceptance, progress (comments), and waves (swarm) all live in Beads.

## Where do emit / sync fit now?
**Migration only.** They exist to onboard a repo that ALREADY has markdown plans:
- `cmpl sync` — import existing Ralph `IMPLEMENTATION_PLAN.md` / checkbox lists → Beads (one-time).
- `cmpl emit` — import a GSD `PLAN.md` that was already produced → Beads (one-time).

After migrating, plan with `/completely:plan` (Beads-first). Don't keep authoring markdown plans
and re-importing them — that's the dual-representation trap this design removes.
