# Who owns what (avoiding double-ownership)

Stacking agent tools fails quietly when two of them think they own the same thing.
Pick one owner per concern. Reference split:

| Concern | Single owner | NOT owned by |
|---|---|---|
| Plans & specs (the "what/why") | your spec flow (GSD / Spec Kit / plan mode) → `.planning/` or `spec.md` | the task tracker |
| **Task status** & dependency graph | a task tracker (e.g. Beads) | markdown, the planner |
| Execution loop (driving the work) | **one** driver per run: Ralph loop *or* a phase executor | — |
| "How" of a specific craft | skills (tdd, design, simplify, review) | the loop, the gates |
| Always-on enforcement | **hooks** (format/lint/types/dangerous-cmd) | CLAUDE.md (advisory only) |
| Independent judgment | subagents (code-reviewer, security-reviewer, **evaluator**) | the implementer |

> **Reviewers judge more than the diff.** The **code-reviewer** owns code merits **AND project-wide
> fit** — duplication vs existing shared utilities, adherence to the architecture preset (layering,
> module boundaries, public-API surface), naming/pattern consistency with neighbouring modules, and
> cross-module ripple. The **security-reviewer** owns the injection/authz/secret/validation surface.
> Green tests + clean lint are NECESSARY, NOT SUFFICIENT: a clear project-level problem blocks the
> task even with a passing suite (fix it or `bd update --status blocked`). This is enforced at spawn —
> `<<COMPLETELY_ENFORCED step=review policy=project-fit>>` / `policy=security`.

## Three conflicts to resolve explicitly

1. **Two execution drivers** (e.g. a phase executor vs a Ralph-style loop). → **One per run.**
   Supervised, gated by phase → executor. Long autonomous grind in fresh contexts → loop.
   Never both at once.
2. **Plans vs status.** Plans/specs live in files and change rarely; **status lives only in the
   task tracker** and changes constantly. Never record task status in markdown.
3. **Multiple memories.** If you run more than one memory system, split by fact type:
   - fact bound to a task (decision/blocker on an issue) → the task tracker's memory;
   - "have we done/decided this before?" across sessions → semantic memory (e.g. claude-mem);
   - durable fact about the user/project/preferences → your global memory file;
   - work status → only the task tracker. No overlap.

## The flow these roles run inside

`IDEA → A understand+spec → 🚦gate 1 → B architecture+plan → 🚦gate 2 "go" →
 C autonomous execution (fresh context per task: TDD → hooks → reviewers → evaluator(default-FAIL)
 → commit → next) → 🛑STOP-conditions only → D acceptance/closeout`

Human gates are concentrated **before** execution (A/B). Inside C the agent is silent except
on STOP-conditions. See `HARNESS.md` for the full version.
