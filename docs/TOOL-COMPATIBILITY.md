# Tool compatibility analysis — what to keep, what to compensate, what to fix

> **Status: RESEARCH ONLY.** This documents the conflicts between the tools and the target
> design. Nothing here is implemented yet. It answers "what needs to be done", not "done".
> Scope: every tool in the stack, not just the ones first discussed.

## 0. What was read (grounding, not hand-waving)
- Ralph: `~/.claude/ralph-loop/loop.sh`, `commands/ralph/build.md`, `ralph-loop/AGENTS.md`.
- GSD: `~/.claude/commands/gsd/*` (execute-phase, check-todos, …), `get-shit-done/workflows/`, `agents/gsd-*`.
- Beads: live db (`bd ready/stats`), `.beads/` git-managed hooks, project `AGENTS.md` rules.
- claude-mem: `plugins/.../claude-mem` hooks (SessionStart context injection).
- harness (this repo): hooks + evaluator + DoD + self-tooling.

## 1. The core problem, in one picture

Three+ **disjoint state stores**, none of which references the others:

```
   PLAN / "what to do"          STATUS / "where am I"        LEARNINGS / "what happened"
 ┌───────────────────────┐   ┌────────────────────────┐   ┌──────────────────────────┐
 │ GSD  .planning/*.md    │   │ GSD  STATE.md + todos   │   │ Ralph PROGRESS.md (append)│
 │ Ralph IMPLEMENTATION_  │   │      + TodoWrite        │   │ GSD pause/resume handoff  │
 │       PLAN.md          │   │ Ralph IMPLEMENTATION_   │   │ claude-mem (semantic)     │
 │ Beads issues (graph)   │   │       PLAN.md checkboxes│   │ bd remember               │
 └───────────────────────┘   │ Beads status (db)       │   └──────────────────────────┘
                              └────────────────────────┘
```

**Neither GSD nor Ralph knows Beads exists** (`grep -ri beads` over both = empty). The
project rule "track tasks in bd, never markdown" is a *human-imposed bridge* that actively
fights each tool's native design: GSD wants `TodoWrite` + `STATE.md` + its own todo store;
Ralph wants `IMPLEMENTATION_PLAN.md`. Every time you run them "as designed", they re-create a
second queue and you get double-entry drift. **That friction is the root cause.**

## 2. Per-tool ledger

| Tool | Strength to KEEP | Weakness to COMPENSATE | Native state (the conflict) |
|---|---|---|---|
| **GSD** | Best structured planning: discuss→research→plan→verify, phase/milestone lifecycle, codebase mapping, **wave-parallel subagents at ~15% orchestrator context** | Owns a task queue it shouldn't (STATE.md + todos + TodoWrite); token-heavy (~4:1); zero Beads awareness | `.planning/*.md`, `STATE.md`, own todos, `TodoWrite` |
| **Ralph** | Dead-simple **OS-level fresh-session loop** (`claude -p` per iteration — a *harder* context reset than in-session subagents; ideal for very long unattended grinds); "one thing, search-before-assume, append progress" discipline | Re-implements the queue in markdown; `--dangerously-skip-permissions` removes the human gate; no quality gates by default; can "vibe-loop" with no done-definition | `IMPLEMENTATION_PLAN.md`, `PROGRESS.md`, `AGENTS.md` (commands), `specs/` |
| **Beads** | Durable **dependency-aware queue + status** surviving restarts; `bd ready` = unblocked work; `bd remember` | Not a planner, not a driver, not a verifier — pure memory; needs something to fill it and something to consume it | DB (`.beads/`) — the one store that *should* be canonical |
| **claude-mem** | Auto **semantic recall** across sessions; SessionStart context index ("72% reduction from reuse") | Overlaps `bd remember`; can bloat context if unscoped | own store + hooks |
| **skills** (impeccable, ui-ux-pro-max, tdd, simplify, code-review, verify, plan, shape) | Best-in-class **craft finishers**; on-demand, cheap (progressive disclosure) | Heavy overlap among themselves (simplify vs distill; code-review skill vs code-reviewer agent vs gsd verify) — unclear which to call when | n/a |
| **harness** (this) | Deterministic **quality/security gates** + default-FAIL evaluator + no-stub contract — the floor under everything | New; not yet wired into GSD/Ralph loops | hooks + agent |

## 3. Conflict matrix (the overlaps that actually bite)

| # | Conflict | Tools | Symptom |
|---|---|---|---|
| A | **Three task queues** | Beads vs GSD(STATE+todos+TodoWrite) vs Ralph(IMPLEMENTATION_PLAN) | Double-entry; "bd-only" rule fights native designs |
| B | **Four progress/handoff stores** | Ralph PROGRESS vs GSD pause/resume+STATE vs claude-mem vs bd remember | No single "where am I"; stale handoffs |
| C | **Three command specs** | Ralph AGENTS.md vs harness CLAUDE snippet vs GSD detection | Lint/test command defined 3×, drifts |
| D | **Two execution drivers** | GSD execute-phase (wave subagents) vs Ralph loop (OS fresh sessions) | Both want to own the run |
| E | **Permissions/safety** | Ralph `--dangerously-skip-permissions` vs user rule "never skip" vs harness guard hook | Unattended Ralph removes the human STOP-gate |
| F | **Multiple planning entries** | GSD discuss/plan vs Ralph PROMPT_plan vs `plan`/`shape` skills vs brainstorm | Unclear front door |
| G | **Multiple verifiers, different stances** | gsd-verifier (goal-backward) vs harness evaluator (default-FAIL) vs `verify`/`code-review` skills vs code-reviewer agent | No single acceptance gate; inconsistent rigor |
| H | **Memory contradiction** | AGENTS.md says "bd remember, NOT MEMORY.md"; global memory system uses MEMORY.md; claude-mem adds a third | Directly contradictory instructions |

## 4. Target architecture — Beads as the spine

Keep every strength; route all of them through **one** queue and **one** quality floor.

```
            ┌──────────── PLANNING (GSD) ────────────┐
   idea →   │ discuss → research → plan → decompose   │   .planning/*.md = specs/rationale ONLY
            └───────────────┬────────────────────────┘   (the "what/why", not status)
                            │  EMIT issues (epic=phase, child=task, deps)
                            ▼
                  ╔═════════════════════╗
                  ║   BEADS = the spine ║   single source of truth for STATUS + queue
                  ║   bd ready / close  ║
                  ╚═════════╤═══════════╝
              consume bd ready │ (ONE driver per run)
        ┌───────────────┬─────┴───────────────┐
        ▼ supervised    │                     ▼ unattended grind
   GSD execute-phase    │              Ralph loop (Beads-aware PROMPT)
   (wave subagents)     │              (claude -p, fresh session each)
        └───────────────┴─────┬───────────────┘
                              ▼  per task
            TDD → harness hooks (always on) → reviewers → EVALUATOR (default-FAIL)
                              ▼
                       bd close + commit(bd-id)
        learnings → bd remember (task) + claude-mem (semantic). NO PROGRESS.md/STATE queue.
```

Rules that fall out of this:
- **One queue:** Beads. GSD *emits* into it; Ralph *consumes* from it. GSD's TodoWrite/STATE/own-todos are demoted to a thin pointer, never the queue.
- **Two modes, one engine, one dial:** GSD (supervised) and Ralph (unattended) are not a choice between tools but two *autonomy levels* of the same loop over `bd ready` (see §4a). One mode at a time per task; hand off freely between them because status lives in Beads, not in either tool's markdown.
- **One acceptance gate:** harness `evaluator` (default-FAIL). `gsd-verifier` becomes a goal-backward *feeder* of evidence into the DoD; `verify`/`code-review` run inside the loop, not as rival gates.
- **One quality floor:** harness hooks, on under every driver.
- **One commands source:** the project's `scripts/check.sh`; Ralph `AGENTS.md` and the harness hook both point at it (no re-spec).
- **Memory split (canonical):** `bd remember` = task-bound facts · claude-mem = semantic recall · MEMORY.md = durable user/project. Fix the AGENTS.md↔global contradiction by scoping, not by banning one.
- **Safety:** do **not** use Ralph's blanket `--dangerously-skip-permissions`. For unattended runs use a permission *allowlist* + the harness guard hook + STOP-conditions, preserving a real gate.

### 4a. Two modes of one engine — the autonomy dial

GSD = control, Ralph = autonomy — correct. But the unification is **not "pick one"**: they are
the *same execution loop at different autonomy levels*, sharing one spine (Beads), one quality
floor (harness gates + evaluator), one set of contracts (worker contract, Parallel
Decomposition Matrix, closeout). Only two things actually differ:

| | **GSD mode** (supervised) | **Ralph mode** (unattended) |
|---|---|---|
| Human gate frequency | at phase/wave boundaries | only on STOP-conditions |
| Context reset | in-session wave subagents (~15% orch.) | OS-level fresh session per task (`claude -p`) |
| Best for | ambiguous / architectural / first-of-kind | atomic, unambiguous, green-spec backlog |
| Contributes to the merge | planning depth, control, real parallelism | hardest reset, long unattended grind |

**The dial.** A phase/task may run in Ralph mode *only* when: spec unambiguous **+** tasks atomic
**+** write-zones disjoint **+** verification automated (red/green). Otherwise GSD mode. Make it an
explicit field — `autonomy: supervised | unattended` + a reason — same discipline as
Maslennikov's enumerated sequential-reasons (no vague "seemed simple").

**The handoff that "combines the best."** GSD plans the phase and does the risky/ambiguous first
tasks under supervision; once the pattern is set and the rest of `bd ready` is atomic, flip the
**same queue** to Ralph mode and grind it unattended. Both modes leave identical artifacts
(commit + `bd close` + evidence), so either can resume the other's work mid-phase.

**Why this is only possible with Beads as the spine.** If status lived in GSD's `STATE.md` or
Ralph's `IMPLEMENTATION_PLAN.md`, the modes could not hand off — you'd be locked into one tool's
memory. Routing all status through Beads is exactly what turns "choose a tool" into "turn a dial".
That single decision is what makes "best of both" mechanically possible rather than aspirational.

## 5. The work this implies (future — NOT done here)

1. **GSD→Beads emitter.** A post-`plan-phase` step that turns plan files into bd issues (epic per phase, child per task, `bd dep add` for deps). Removes the manual bridge.
2. **Beads-aware Ralph PROMPT.** Replace IMPLEMENTATION_PLAN.md logic with: `bd ready --json` → claim one → TDD → harness gates → evaluator → `bd close` → commit. (IMPLEMENTATION_PLAN.md, if kept, is generated *from* bd as a read-only view.)
3. **Verifier reconciliation.** Make `evaluator` canonical; map `gsd-verifier` output into DoD evidence rows.
4. **Single commands source.** Generate Ralph `AGENTS.md` validation section + harness `quality-gate.local.sh` from one `scripts/check.sh`.
5. **Memory policy.** One short doc resolving H; stop the contradictory instructions.
6. **Demote GSD's native queue.** Convention/config so Beads is the sole queue (don't let `check-todos`/STATE act as a second backlog).
7. **Unattended-safety profile.** Allowlist + guard hook instead of skip-permissions.

## 6. Open decisions (yours — they change the above)
- **Primary driver:** GSD execute-phase vs Ralph loop as the default Phase-C engine?
- **claude-mem vs bd remember:** keep both with the split above, or drop one?
- **How far to bend GSD:** lightweight emitter (GSD stays mostly itself) vs deeper fork (GSD natively writes bd)? The former is cheaper and reversible; recommended first.

## 7. Sober caveats
- This is an **integration/adapter** layer — keep each tool, route through Beads, wrap with gates. It is **not** a rewrite of GSD or Ralph.
- Token cost compounds (GSD ~4:1 × multi-agent ~15×). Keep a fast-path for trivial work.
- GSD, Ralph, Beads are young and move fast; adapters must be thin and re-pointable.
- After a model upgrade, re-test whether some of this scaffolding became dead weight.

---

## 8. Field report: "orchestrator = contract dispatcher" (Maslennikov, Habr)

A practitioner running the same stack (Beads + Superpowers, then a Codex port) independently
hit and solved our exact problems. His conclusions sharpen the target design above.

**Root cause, confirmed.** "The orchestrator confidently reads the contract, nods, then
quietly cuts corners." A vague contract gives the agent freedom to reinterpret
("delegate medium/complex" → "delegate only when I'm unsure"), and on average it takes the
easier path. **One big AGENTS.md/CLAUDE.md is an essay, not a contract — nobody executes an
essay.** (A commenter's fix: keep the root file for hard invariants only; move modular
contracts into folders + slash-commands so a contract loads only when its context is active.)
→ Validates: our gates must be *structural*, and the v0.2 orchestrator must be small
contextual contracts + machine-readable config, **not** a growing CLAUDE.md.

**Mechanisms worth adopting (for v0.2, not now):**

1. **Lifecycle-split skills**, not one prompt: `setup` (repo baseline) · `stage` (active
   medium/complex work) · `router` (asset/skill/agent routing within a step) · **`closeout`**
   (evidence-checks, update Beads/handoff, clean worktrees). He calls closeout the most
   valuable — "stage can't close without passing evidence-checks; silent debt ended."
   → This is exactly our `evaluator`/DoD, but lifted to a *stage* gate that also cleans state.
2. **Parallel Decomposition Matrix** — a mandatory table *before* delegating: Stream · Goal ·
   Agent · **Write zone** · Dependencies · Verification · Model · Decision · Reason. Rule:
   ≥2 independent streams ⇒ run parallel; sequential needs a reason from an *enumerated* list
   (dependency chain, write conflict, shared verification bottleneck, shared external
   resource, uncertain scope, repo limit). **"Files are related" is not on the list.**
   → Compensates GSD/Ralph "decorative parallelism" (claims parallel, runs sequential).
3. **Machine-readable contract** (`orchestrator.toml`): `inline_subagents_allowed = false`,
   `parallel_decomposition_matrix = "required_for_medium_complex"`, model policy, etc.
   Plus an explicit per-task **spawn authorization** phrase, because the runtime obeys the
   *user in the current session*, not the repo file.
4. **Worker contract fields each close one silent-failure class:** write zone (don't touch a
   sibling's files), stop rules (return `blocked`, don't redesign), verification (don't claim
   without running), asset routing (don't re-discover), parallel group (know you're not alone).
   → Confirms our task-contract template; adopt verbatim.
5. **Completion ≠ acceptance**, 4-way: completion event · artifact · orchestrator review ·
   local verification. `accepted: yes` is illegal without verification evidence (the exact
   command + output), re-checked at closeout. → Sharpen our DoD: the artifact must *record*
   the verification command and its output, not assert "green".

**A caveat that changes our conflict E + the hooks design:** he **removed his Beads hooks**
("worked yesterday, not today" — init order, worktrees, approval mode) and went to **explicit
`bd ready/create/update --claim` commands**: less hidden behavior, portable, explainable.
→ Important distinction for us: this applies to **stateful/session hooks** (auto-priming
Beads on SessionStart) — prefer explicit `bd` calls there. It does **not** condemn our
**deterministic gate hooks** (PostToolUse lint, PreToolUse guard), which are idempotent and
don't depend on session state. Design rule: **hooks for deterministic gates; explicit commands
for state.** Also reinforces dropping Ralph's blanket `--dangerously-skip-permissions`.

**Future direction he names — and we should steal:** *behavioral / pressure tests for the
orchestrator* ("TDD for the process"): give a medium/complex task → assert it built the matrix;
give two independent subtasks → assert it actually spawned them in parallel; submit a completion
with no evidence → assert closeout rejected it. Tests for the *contracts*, not the model — to
find where the agent still slips through. This is the natural QA layer for this harness.

Source: Игорь Масленников, "Собрал оркестратор для Codex на базе Beads и Superpowers", Habr
(baseline `balanced-v2.12`). Same author the original blueprint cited on hook flakiness.
