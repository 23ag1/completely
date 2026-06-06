# Skill routing — one canonical skill per intent

Overlapping skills make the agent pick inconsistently. Map each INTENT to ONE canonical skill;
the others are fallbacks/aliases, never parallel choices. The driver's asset-routing step picks
the canonical for the task's intent and records it in the task `metadata.skills`.

| Intent | Canonical | Also exists (do NOT call in parallel) |
|---|---|---|
| brainstorm / spec | `/gsd:discuss-phase` (or `/gsd:new-project`) | superpowers brainstorm |
| plan / decompose | `/gsd:plan-phase` → `cmpl emit` | `commands/plan.md`, openclaw make-plan, built-in `/plan` |
| execute / drive | `/completely:run` | `/gsd:execute-phase` (= supervised mode), `ralph:build` |
| TDD | `commands/tdd.md` | gsd `references/tdd.md` |
| simplify code | built-in `/simplify` | — |
| code review | `code-reviewer` agent | built-in `/code-review`, `commands/code-review.md` |
| acceptance | completely `evaluator` agent | `gsd-verifier` (feeds evidence), built-in `/verify` |
| security | `security-reviewer` agent | built-in `/security-review` |
| UI craft | `/impeccable`, `/ui-ux-pro-max` | the design-skill family |
| migrate md→bd | `/completely:sync` | — |
| reasoning at decisions | GSD **thinking-models** (`references/thinking-models-*.md`) | ad-hoc "think harder" |
| spec / UI / security / eval *phase* | `/gsd-spec-phase` / `/gsd-ui-phase` / `/gsd-secure-phase` / `/gsd-eval-review` | rolling them by hand |
| which craft tool for THIS stack | **`cmpl craft`** (the resolver) | hardcoding per stack |
| token compaction | rtk (input) · `/caveman` (output) | — |

Rule: never invoke two skills for the same intent. If a user skill already covers an intent,
prefer it (see init's compose rule) and record the choice in routing.
