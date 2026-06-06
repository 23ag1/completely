# Ecosystem shortlist — awesome-* catalog mining for `completely`

**Task:** claude-harness-w6c.7 · **Date:** 2026-06-06 · **Method:** WebSearch/WebFetch over awesome-* lists + 2026 landscape articles. WebSearch was available; entries below are evidence-backed unless marked **[SPECULATIVE]**.

## Framing — what `completely` already routes (so we mine for GAPS, not dupes)

`completely` is a quality-first connecting layer: it ROUTES concerns to existing tools, keeps **Beads** the single source of truth, runs **deterministic gates + an independent default-FAIL evaluator**. Its current concern map (from `plugin/scripts/craft.py` RULES + `core/routing.md`):

`reason` (GSD thinking-models) · `understand` (gsd-map-codebase) · `spec`/`plan` (GSD → Beads) · `tdd` · `test` (per-stack) · `ui-craft` (impeccable/ui-ux-pro-max) · `review` (code-reviewer) · `readability` (simplify/refactor-clean) · `security` (security-reviewer) · `verify`+`eval` (gsd-verifier → evaluator default-FAIL, `cmpl bench`) · `debug` (gsd-debug) · `token-in` (**rtk**) · `token-out` (**caveman**).

So the open gaps worth mining are: **token/context packing** (rtk is per-tool-output, not whole-repo), **eval-as-CLI-gate** (evaluator is an agent, not a deterministic assertion runner), **usage/cost telemetry** (completely has none), **MCP servers** (none wired), **cross-session memory** (claude-mem is referenced in roles.md but not routed), **agent coordination** (completely IS the coordinator — mine only for primitives, not replacements).

Mining catalogs scanned: `hesreallyhim/awesome-claude-code` (45.8k★), `rohitg00/awesome-claude-code-toolkit`, `ComposioHQ/awesome-claude-skills`, `wong2`/`punkpeye`/`appcypher/awesome-mcp-servers`, `modelcontextprotocol/servers`, plus 2026 landscape rankings for observability/memory/orchestration.

---

## Concern: token economy (compaction / context packing)

`completely` has rtk (compress tool *output* → input tokens) and caveman (terse agent *output*). The gap is **whole-repo context packing** before a task and **per-file token accounting** — a different layer from rtk.

| Tool | What it does | completely concern → route to | install / repo | Why it's a fit | Overlaps existing? |
|---|---|---|---|---|---|
| **Repomix** | Packs an entire codebase into one AI-friendly file; tree-sitter "compress" mode ~70% token reduction; per-file + total token counts | `understand` / a new `pack` concern feeding `understand` | `npx repomix` · github.com/yamadashy/repomix · repomix.com | Whole-repo→prompt packing is the layer ABOVE rtk; useful to prime fresh-context workers cheaply | **Partial** — complements rtk (rtk = per-tool-output, Repomix = whole-repo). No overlap with caveman. |
| **files-to-prompt** | Minimal, pipe-friendly dir→prompt concatenator; plain/Markdown/**Claude-XML** output (Simon Willison) | `understand` (lightweight alt to Repomix) | `pip install files-to-prompt` · github.com/simonw/files-to-prompt | UNIX-composable, zero-config; good degraded fallback when Repomix isn't installed | Yes — same niche as Repomix; list as the lighter alternative, not both as primary. |
| **code2prompt** | CLI: codebase→single prompt w/ source tree, glob/.gitignore filtering, Handlebars templates, token counting | `understand` | `cargo install code2prompt` / npx · github.com/mufeedvh/code2prompt | Templating + token budget; Rust, fast | Yes — third entrant in the same packing niche. **Pick ONE** (recommend Repomix as canonical). |

**Pick:** Repomix as canonical "pack" tool, files-to-prompt as the degraded fallback. Honestly: this is a *new* concern, not a gap in an existing one — adopt only if priming fresh-context workers proves token-expensive in `cmpl bench`.

---

## Concern: eval / acceptance (deterministic assertion gate)

`completely`'s evaluator is an *agent* (default-FAIL, reads acceptance + must_haves). The gap is a **deterministic, CLI-runnable, CI-gateable assertion layer** that the evaluator could DELEGATE cheap checks to — keeping LLM-judge calls only for subjective criteria.

| Tool | What it does | completely concern → route to | install / repo | Why it's a fit | Overlaps existing? |
|---|---|---|---|---|---|
| **promptfoo** | CLI/lib for prompt+agent+RAG eval & red-team; 3 assertion tiers — **deterministic** (contains/regex/latency/**cost**) free+instant, **llm-rubric** (LLM judge), CI/CD integration; MIT (OpenAI-acquired Mar 2026, still OSS) | `eval` — the deterministic-assertion floor UNDER the evaluator agent | `npx promptfoo` · github.com/promptfoo/promptfoo | Exactly matches completely's "deterministic gates + independent judgment" thesis; cheap checks run free, LLM-judge reserved for subjective. **Strongest fit in this doc.** | **Complements** evaluator (deterministic floor) — does NOT replace the default-FAIL agent. Overlaps `cmpl bench` slightly on cost-measurement. |
| **DeepEval** | Python-first, **pytest-integrated** eval; 50+ metrics (G-Eval, hallucination, relevancy); blocks deploys on thresholds; Apache-2.0 | `eval` for `python`-tagged repos (pytest gate) | `pip install deepeval` · github.com/confident-ai/deepeval | Plugs into the existing pytest gate completely already runs for python stacks; threshold-gating = default-FAIL semantics | Complements; Python-only. Route alongside `test` when stack=python. |
| **Ragas** | Deepest RAG-specific metric family (faithfulness, context precision/recall) | `eval` **only if** repo is a RAG app **[SPECULATIVE for general use]** | `pip install ragas` · github.com/explodinggradients/ragas | Niche; only fits if completely is used on RAG codebases | No overlap, but narrow. Skip unless RAG detected. |

**Pick:** **promptfoo** — deterministic+LLM-rubric+cost in one CLI is the cleanest match to completely's gate philosophy. The evaluator agent stays as the default-FAIL backstop; promptfoo becomes its cheap deterministic floor.

---

## Concern: usage / cost telemetry (NEW — completely has none)

`completely` measures quality/\$ via `cmpl bench` (with-vs-without) but has **no live per-session token/cost telemetry**. This is a real gap.

| Tool | What it does | completely concern → route to | install / repo | Why it's a fit | Overlaps existing? |
|---|---|---|---|---|---|
| **ccusage** | Reads **local** Claude Code usage data → daily/weekly/session cost reports; statusline integration; burn rate, session cost, context % | new `telemetry`/`cost` concern; feeds `cmpl bench` ground-truth | `npx ccusage` · github.com/ryoppippi/ccusage | Zero-infra, local-only (no proxy), reads the same data completely runs on; could give `cmpl bench` real \$ numbers instead of estimates. **Strong, low-risk fit.** | **Complements** `cmpl bench` (bench = experiment harness, ccusage = ground-truth meter). No overlap. |
| **LiteLLM** | OpenAI-compatible proxy → 100+ providers w/ reliable cost tracking | `cost` IF completely ever routes through a proxy **[SPECULATIVE]** | `pip install litellm` · github.com/BerriAI/litellm | Only relevant if completely proxies model calls — it currently does not | Overkill for a CLI harness; skip unless proxy architecture adopted. |
| **Langfuse** | OSS (MIT) observability: tracing+eval+token/cost tracking, self-host; built-in Anthropic tokenizers/pricing | heavyweight `eval`+`telemetry` if completely ever needs persistent trace storage **[SPECULATIVE]** | github.com/langfuse/langfuse | Mature, but self-host needs Postgres+ClickHouse+Redis+S3 — far too heavy for a thin connecting layer | Heavy overlap w/ evaluator+bench+ccusage combined. **Skip** — violates completely's "don't reimplement, stay thin" thesis. |

**Pick:** **ccusage** — local, zero-infra, directly upgrades `cmpl bench` from estimated to measured \$. Langfuse explicitly rejected as too heavy (documented so we don't re-litigate).

---

## Concern: MCP servers (completely wires none today)

The reference servers are the safe, high-value picks; they're capabilities completely's *routed workers* could use, not things completely reimplements.

| Tool | What it does | completely concern → route to | install / repo | Why it's a fit | Overlaps existing? |
|---|---|---|---|---|---|
| **Context7 MCP** | Fetches live, version-specific library docs into the prompt | `understand` / craft (API verification) — already in user's CLAUDE.md frontend rule | github.com/upstash/context7 | Already mandated in user's global rules for library-API verification; routing it makes the rule executable | None — fills a stated need. **Good fit.** |
| **Sequential Thinking MCP** | Externalizes reasoning as explicit ordered steps/branches | `reason` (alongside GSD thinking-models) | modelcontextprotocol/servers (reference) | Could back the `reason` concern with a structured-steps tool | **Overlaps** GSD thinking-models (the canonical `reason` owner). List as alt, do NOT route in parallel — roles.md forbids double-ownership. |
| **Git / Filesystem MCP (reference)** | Safe scoped FS + git read/search/manipulate | low priority — Claude Code already has native Bash/Read/Edit | modelcontextprotocol/servers | Marginal; native tools already cover this | **Redundant** with native tooling. Skip. |
| **GitHub MCP** | Repo/PR/issue ops via MCP | optional — `gh` CLI already covers this for completely | github.com/github/github-mcp-server | completely already uses `gh`; MCP is alt transport | Overlaps `gh`. Skip unless a worker needs MCP-native GitHub. |

**Pick:** **Context7 MCP** (fills a rule the user already wrote). Sequential-Thinking noted but deliberately NOT routed (would double-own `reason`).

---

## Concern: cross-session memory

`roles.md` already names **claude-mem** as the semantic-memory owner ("have we done/decided this before?") and Beads as task-bound memory — so the *architecture* is decided. Mine only confirms claude-mem's slot; heavier frameworks are out of scope for a thin layer.

| Tool | What it does | completely concern → route to | install / repo | Why it's a fit | Overlaps existing? |
|---|---|---|---|---|---|
| **claude-mem** | Captures observations across sessions; semantic recall; already installed in this env (mcp tools present) | `memory` (semantic) — already the designated owner in roles.md | (installed plugin in this harness) | Already chosen; just needs to be *routed* (it's referenced but not in craft.py RULES) | **Already the owner.** Gap = it's documented but not wired into the craft router. |
| **Mem0 / Zep / Letta / Cognee** | Standalone agent-memory layers (vector/temporal/self-managed/graph) | — **[SPECULATIVE]** general agent memory | mem0.ai · getzep.com · letta.com · cognee.ai | Powerful but they'd compete with claude-mem+Beads → violates "multiple memories, split by fact type" rule in roles.md | **Conflicts** with the decided split. **Skip all** — adopting one = re-litigating settled ownership. |

**Pick:** No new tool. **Action item instead:** wire the already-chosen **claude-mem** into the craft router's `RULES` (it's in prose but absent from code). The 4 standalone frameworks are explicitly rejected to protect the single-source-of-truth thesis.

---

## Concern: agent coordination

`completely` IS the coordinator (GSD waves / Ralph loop / Beads spine). Mining here is about *primitives it could borrow*, NOT orchestrators that would replace it.

| Tool | What it does | completely concern → route to | install / repo | Why it's a fit | Overlaps existing? |
|---|---|---|---|---|---|
| **Claude Code Agent Teams (native)** | Built-in experimental multi-agent: one "team lead" coordinates workers via a shared task list | reference pattern for completely's own wave/loop driver | native Claude Code (experimental, off by default) | Validates completely's supervisor topology; shared-task-list ≈ Beads-as-spine. Worth tracking as the native baseline | **Overlaps completely's core** — it's an alternative driver, not a tool to route to. Track, don't adopt. |
| **Claude Flow / Conductor / Vibe Kanban / Claude Squad** | External multi-agent orchestrators / swarm frameworks | — | various | These ARE competing connecting layers | **Direct overlap with completely itself.** Skip — adopting any = replacing the harness. |

**Pick:** None to route. Agent Teams noted as the native baseline to benchmark `cmpl bench` against. All external orchestrators are competitors, not dependencies.

---

## Already covered — skip (do NOT re-add)

| Concern | completely already routes to | Don't re-add |
|---|---|---|
| planning / spec | GSD (`/gsd-spec-phase`, `/gsd-plan-phase` → Beads) | Spec Kit, openclaw make-plan, generic planners |
| task state / dep graph | **Beads** (single source of truth) | any markdown task list, Linear/Jira MCP as primary tracker |
| code review | `code-reviewer` agent | duplicate reviewer skills/commands |
| security | `security-reviewer` + `/gsd-secure-phase` | other SAST wrappers as primary |
| acceptance / verify | `evaluator` (default-FAIL) + `gsd-verifier` | second LLM-judge as primary owner |
| token-in (tool output) | **rtk** | other per-output compressors |
| token-out (agent output) | **caveman** | other terse-output skills |
| UI craft | `/impeccable`, `/ui-ux-pro-max` | the rest of the design-skill family in parallel |
| debug | `/gsd-debug` + `gsd-debugger` | duplicate debug skills |
| reasoning at decisions | GSD thinking-models | ad-hoc "think harder", Sequential-Thinking as parallel owner |

---

## Top picks (honest, ranked)

1. **promptfoo** — `eval`. Deterministic-assertion + cost CLI that becomes the cheap floor *under* the default-FAIL evaluator agent. Best thesis-match in this doc. **Complements, not replaces.**
2. **ccusage** — `cost`/`telemetry` (NEW concern). Local, zero-infra \$ meter that upgrades `cmpl bench` from estimated to measured. Lowest-risk genuine gap-fill.
3. **Repomix** (canonical) + **files-to-prompt** (fallback) — whole-repo context packing, a layer ABOVE rtk. Adopt only if fresh-context priming proves token-costly in bench.
4. **Context7 MCP** — `understand`. Makes the user's existing "Context7 for library-API verification" rule executable.
5. **Wire claude-mem into craft.py RULES** — not a new tool; the chosen memory owner is in prose but missing from the router code.

**Explicitly rejected (documented to avoid re-litigation):** Langfuse (too heavy for a thin layer), Mem0/Zep/Letta/Cognee (conflict with Beads+claude-mem single-source-of-truth), Claude Flow/Conductor/Squad (competing connecting layers), Git/Filesystem/GitHub MCP (redundant with native tools + `gh`).
