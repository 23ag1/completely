# What to adopt from ECC (and what to skip)

ECC (208k★) is far bigger than completely on every axis except one: it is **memory/skill/instinct-
centric and has no Beads-like dependency-graph spine**. completely's reason to exist is the auditable
DAG-of-tasks + evidence gates. So we mine ECC for *methodology*, not surface.

## Adopt (high value)
| ECC artifact | What it gives us | Action |
|---|---|---|
| `skills/agent-eval` | the exact with/without measurement design (YAML tasks, worktree isolation, deterministic+LLM judges, >=3 runs, $/passed) | → `docs/BENCH-METHODOLOGY.md`; build `cmpl bench` |
| `skills/benchmark-optimization-loop` | bounded measured-loop discipline + **promotion gate** ("best measured safe", not "optimum") | fold into bench + any perf work |
| `agents/gan-evaluator` + `agents/gan-planner` | **adversarial planner↔evaluator** pair — validates our default-FAIL evaluator; could sharpen it into a plan-vs-grade loop | study; consider an adversarial mode for our evaluator |
| `skills/quality-nonconformance` | structured "what to do when a gate FAILS" (not just detect) | pattern for our gate-fail → bd blocked flow |
| `hooks/` (cost-track, memory-persistence) | a PostToolUse **cost-tracking** hook + session memory pattern | cost hook feeds bench + token-economy |
| `contexts/{dev,research,review}.md` | dynamic system-prompt injection per mode | compare with our `core/roles.md` |

## Skip (against our thesis / already covered)
- **251 skills / 63 agents wholesale** — gsd-core already provides 33 agents; completely **composes**, not reimplements.
- **Language reviewers / build-resolvers** (python-reviewer, rust-build-resolver, …) — gsd-core + our code-reviewer cover these.
- **Multi-harness adapters** (`.cursor/.codex/.zed/.gemini/…`) — completely is Claude-Code-first; only relevant if we ever chase cross-harness reach.
- **Install profiles + Tkinter dashboard + Pro tier** — that's a different product scale.

## Notes worth remembering
- **ECC's `rules/` == the user's global `~/.claude/rules/`** (coding-style, hooks, testing, security, …) — this machine is already running ECC-derived global rules. Account for that when reasoning about why certain behaviors (e.g. the doc-creation guard) appear.
- ECC confirms our cost approach: it tracks **cost alongside pass-rate** and warns "a 95% agent at 10x cost may not be right" — exactly our `$/passed-task` framing.
- ECC's own `EVALUATION.md` is a repo-vs-repo gap analysis, not a with/without-harness benchmark — our bench is a sharper question than ECC currently answers about itself.
