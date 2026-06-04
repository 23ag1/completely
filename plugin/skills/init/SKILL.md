---
name: completely:init
description: Scaffold the completely thin layer into the current repository — Definition of Done, the harness rules snippet in CLAUDE.md, and an optional project-specific quality command. Use when setting up claude-harness in a new project, or when the user says "harness init", "set up the harness", or "wire up the quality gates here".
version: 0.1.0
user-invocable: true
argument-hint: "[--force]"
---

You are scaffolding the **claude-harness** project thin layer into the current repo. The
heavy logic (hooks, evaluator agent) ships with the plugin/global install; this only adds
the small per-project pieces. **Never overwrite an existing file without asking** (unless
the user passed `--force`).

## Steps

1. **Locate the repo root** (`git rev-parse --show-toplevel`, else cwd) and **detect the stack**:
   - `pyproject.toml` / `setup.cfg` → Python (commands: `ruff check`, `mypy`, `pytest`)
   - `package.json` → JS/TS (read its `scripts`; commands likely `eslint .`, `tsc --noEmit`, `vitest run` / `jest`)
   - `go.mod` → Go; `Cargo.toml` → Rust. Record the real lint/typecheck/test commands.

2. **Create `.claude/` and `.claude/harness/`** if missing.

3. **Write `.claude/DEFINITION_OF_DONE.md`.** Copy the harness template. Locate it under the
   installed plugin (try `${CLAUDE_PLUGIN_ROOT}/templates/DEFINITION_OF_DONE.md`, then
   `~/.claude/harness/core/`); if you can't find it, regenerate it from the canonical content
   you know (default-FAIL checklist). Fill in the detected stack's commands.

4. **Merge the harness rules into the project `CLAUDE.md`.** If `CLAUDE.md` exists, append the
   `CLAUDE.harness.md` snippet (between its `<!-- claude-harness -->` markers) — do not
   duplicate if already present. If no `CLAUDE.md`, create a minimal one with the snippet.
   Fill in the real project commands you detected in step 1.

5. **Project quality command (optional).** If the repo already has an aggregate check script
   (e.g. `scripts/check.sh`, a `Makefile` `check` target, or a `package.json` `check` script),
   create `.claude/harness/quality-gate.local.sh` that delegates to it — this makes the
   harness `quality-gate` hook reuse the project's own gate instead of guessing. Make it
   executable. If there is no such script, skip this (the hook's built-in stack detection handles it).

6. **Confirm hook activation.** If the plugin is installed, the gates are already active
   globally — say so. Otherwise tell the user to run `install.sh --project <repo>` (manual path).

7. **Report** exactly what you created/changed and what you skipped (and why). Suggest a
   one-line verification:
   `echo '{"tool_input":{"command":"rm -rf /"}}' | bash <guard-dangerous.sh>; echo exit=$?`  (expect exit=2)

## Guardrails
- Idempotent: re-running must not duplicate the CLAUDE.md snippet or clobber edits.
- Do not invent commands — read them from the project's real config.
- This is a self-tooling task: scaffold the FULL thin layer; if something blocks it, return
  `blocked` with the reason — do not silently skip a piece.

## Compose with the user's own skills/rules (never override)
DETECT and LAYER — do not clobber:
- If the repo has a `CLAUDE.md`, APPEND the harness rules between `<!-- claude-harness -->`
  markers (idempotent). Keep the user's content; harness hard-invariants on top, project rules
  below. Never replace the file.
- Leave the user's existing `~/.claude` skills/agents untouched; compose via `core/routing.md`,
  treating user skills as first-class for their intents.
- If a user skill already covers an intent (e.g. their own `/review`), PREFER it over the
  harness default and record the choice in routing. Hierarchy, not replacement.

## Discovery (new vs existing) — do this FIRST
1. **Ask what it is** — one question: what are we building / what is this repo?
2. **New vs existing:**
   - **NEW** (empty repo / no source) → scaffold from zero: CLAUDE.md, `completely.toml`, pick
     stack + architecture (offer presets, recommend a default), set up quality (`cmpl quality`),
     reference the rules. Confirm, then write.
   - **EXISTING** → STUDY first: read CLAUDE.md/AGENTS.md, package.json/pyproject, the dir shape;
     infer stack + architecture; then ask ONLY the gaps — don't re-ask what you can see. Reconcile
     with the existing CLAUDE.md — APPEND harness rules, never overwrite the user's content.
3. **Ask architecture** (see `core/architectures.md`). If unsure → choose the recommended for the
   stack and state the one-line trade-off.
4. Record in `completely.toml` (`[project][stack][architecture]`) and the CLAUDE.md snippet.
One question at a time; idempotent; never interrogate or clobber.
