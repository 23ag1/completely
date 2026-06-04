<!-- ===== claude-harness (append into your project CLAUDE.md) ===== -->
## Harness rules (non-negotiable)

- **TDD:** no production code without a failing test first (RED → GREEN → REFACTOR).
- **Never** delete, skip, disable, or comment out a test. Broken test → fix it or file an issue, don't hide it.
- **"Done" = evidence.** A command was run, its full output read, and the output confirms the claim. Otherwise: not done.
- **Full scope only.** Stubs / "minimal version" / downscoping are allowed **only** via an explicit `blocked` return with a reason. Never silently. (see self-tooling contract)
- **Fresh context per task:** one task = one session, then restart.
- **Dangerous ops** (`rm -rf`, `DROP TABLE`, force-push, writing secrets) require explicit human confirmation.

## Source of truth
- Spec / plan: `.planning/` or `spec.md` (frozen = the only source of truth; divergence → STOP and ask).
- Task status: your task tracker (e.g. Beads) — **never** track status in markdown.

## Project commands (fill these in)
- Lint:       `<e.g. ruff check  |  eslint .>`
- Typecheck:  `<e.g. mypy .  |  tsc --noEmit>`
- Test:       `<e.g. pytest  |  vitest run>`
- Quality gate (all): `<e.g. scripts/check.sh>`
<!-- ===== end claude-harness ===== -->
