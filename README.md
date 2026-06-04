# claude-harness

> **Agent = Model + Harness.** This is the *harness* — the stuff around the model that
> makes it hard for an agent to quietly cut a corner, fake "done", or silently ship a stub.
> Stack-agnostic. Built for Claude Code; the file formats (`SKILL.md`, `AGENTS.md`, hooks)
> are open standards other agents read too.

## Why

Agents fail in predictable ways: they lose context, claim work is done without proof,
disable a failing test, or downscope a tool into a stub without telling you. You don't fix
that by *asking nicely in a prompt* — you fix it by **engineering the environment** so the
failure can't happen the same way again. Three structural moves:

1. **Quality is deterministic, not trusted.** Format/lint/typecheck run automatically via
   hooks after every edit and feed failures back to the agent. It can't "forget".
2. **"Done" requires evidence.** A read-only `evaluator` agent grades against a Definition
   of Done where **every criterion starts FAIL** and only flips to PASS with proof (command
   output, a passing test, a file). Agents systematically over-grade themselves; this catches it.
3. **No silent stubs.** A self-tooling contract forbids downscoping. "Minimal version" is
   only allowed via an explicit `blocked` return with a reason — never quietly.

## Install

**As a Claude Code plugin (recommended):**

```bash
claude plugin marketplace add 23ag1/completely
claude plugin install harness@completely
```

Then, inside any repo:

```
/harness-init
```

…which scaffolds the project's thin layer (`Definition of Done`, a `CLAUDE.md` snippet,
and an optional project-specific quality command).

**Manual / non-plugin** (other tools, or no plugin system):

```bash
git clone https://github.com/23ag1/completely && cd completely
./install.sh --project /path/to/your/repo
```

## What's inside

| Component | What it does | File |
|---|---|---|
| `quality-gate` hook | After every edit: format + lint (+ opt-in typecheck) on the changed file, by detected stack (TS/JS, Python, Go, Rust). Failures return to the agent. | `plugin/hooks/quality-gate.sh` |
| `guard-dangerous` hook | Before every Bash call: blocks `rm -rf`, `DROP TABLE`, force-push, `mkfs`, fork-bombs, … (exit 2). | `plugin/hooks/guard-dangerous.sh` |
| `evaluator` agent | Read-only, default-FAIL acceptance grader. No write tools — it can only judge. | `plugin/agents/evaluator.md` |
| `Definition of Done` | Checklist where each item is FAIL until proven, output attached. | `plugin/templates/DEFINITION_OF_DONE.md` |
| self-tooling contract | The no-silent-stub rule, for `CLAUDE.md`. | `plugin/core/self-tooling.md` |
| `/harness-init` skill | Scaffolds the per-project thin layer. | `plugin/skills/harness-init/` |
| the principle | The full A→B→C→D flow, role-ownership map, STOP-conditions. | `plugin/core/HARNESS.md`, `plugin/core/roles.md` |

## How it fits with your other tools

This harness is the **quality + verification layer**. It does **not** own planning or the
task queue — it composes with whatever you use:

- **Planning** (specs, decomposition): your spec-driven flow (e.g. GSD, Spec Kit, plan mode).
- **Task queue / memory**: a task tracker like Beads owns *status*; never track status in markdown.
- **Execution loop**: a driver like Ralph, or GSD's executor — pick **one** per run.
- **This harness**: gates + evaluator + DoD + the no-stub contract, underneath all of the above.

See [`plugin/core/roles.md`](plugin/core/roles.md) for the full "who owns what" map and how to
avoid double-ownership (the most common source of quiet bugs when stacking tools).

## Scope

- **v0.1 (this release):** the gates, evaluator, DoD, self-tooling contract, `/harness-init`.
  A complete, usable quality+verification floor.
- **v0.2 (planned):** `/harness-start` (full A→B→C→D orchestrator), `/harness-verify`
  (evidence-based acceptance run), an optional MCP bundle (Context7 / Playwright).

## Caveats (read these)

- **Token cost.** The evaluator + reviewers cost multiples of a single session. Add a
  fast-path for trivial edits; don't run the full ceremony on a typo.
- **Hooks can be finicky.** If you hit invisible init failures, move a check into an explicit
  command the agent calls itself.
- **Models improve.** After a model upgrade, disable parts of the harness one at a time and
  see what became dead weight.
- **Ecosystem trust.** Install skills/MCP only from sources you trust; review before running.

## License

MIT — see [`LICENSE`](LICENSE).
