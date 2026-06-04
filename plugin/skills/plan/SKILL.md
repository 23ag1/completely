---
name: completely:plan
description: Plan a phase or feature DIRECTLY into Beads — no PLAN.md, no markdown bridge. Runs GSD-style socratic discovery + decomposition + a goal-backward self-check, then emits a structured plan that `cmpl plan-apply` materializes as a Beads epic + worker-contract tasks + dependency waves + human checkpoints. One source of truth from the first planning act. Use to turn an idea or phase into ready Beads work.
version: 0.4.0
user-invocable: true
argument-hint: "[phase or feature]"
---
Plan **into Beads directly**. Do NOT write a `PLAN.md` / `STATE.md` — the plan lives in Beads.

## Method (GSD methodology, Beads-first)
1. **Discover (socratic).** Ask clarifying questions ONE at a time until the goal is unambiguous;
   offer 2–3 approaches with trade-offs; confirm scope. If a spec is already frozen, read it instead.
2. **Decompose** into atomic tasks (2–5 min each). Each task MUST carry the worker-contract:
   `title` (imperative), `acceptance` (observable/testable), `design` (approach/why),
   `write_zone` (exact files/globs), `verify` (the proof command), `deps` (other task keys).
   ~2–3 tasks per unit; split if a unit exceeds ~5 tasks or ~10 files (context budget).
3. **Checkpoints.** Where a human must verify/decide, add `{key,title,after,how}`; make downstream
   tasks depend on `cp:<key>` so the wave blocks until the human closes it.
4. **Self-check (goal-backward, GSD plan-checker's 7 dimensions).** Before applying, verify:
   requirement coverage · task completeness (acceptance+verify present) · dependencies acyclic ·
   artifacts wired together (not isolated) · scope within context budget · acceptance is
   user-observable · honors the user's frozen decisions. Fix gaps — don't apply a plan that won't reach the goal.
5. **Apply.** Emit the plan as JSON and pipe it to the materializer:
   `cat <<'PLAN' | cmpl plan-apply` … `PLAN`. It creates the epic + tasks + deps + checkpoints +
   a `bd swarm` (native waves). Then show `bd ready` and `bd swarm status`.

## Plan JSON schema
`{ "epic": "...", "tasks": [ {"key","title","acceptance","design","write_zone":[...],"verify","deps":[...],"labels":[...]} ], "checkpoints": [ {"key","title","after","how"} ] }`

## Rules
- Beads is the only artifact. Never persist a markdown plan.
- Every task lint-clean (acceptance + design + write_zone) — `plan-apply` + `cmpl lint` enforce it.
- One question at a time; respect a frozen spec; don't over-interrogate.
