# One adaptive system (not two; not front/back modes)

**Decision:** completely is ONE system that adapts — not separate front/back systems, not modes.

**Why:** a split duplicates the spine (Beads), the gates, the evaluator, and the docs, and doubles
the upgrade surface. The front/back difference is only *which checks, rules, and architecture*
apply — data, not structure.

**How it adapts (detection by `config.py`):**
- `package.json` (root or `frontend/web/app/client`) → frontend: eslint/tsc/vitest, FSD/feature presets.
- `pyproject.toml` (root or `backend/api/server`) → backend: ruff/mypy/pytest, modular-monolith preset.
- Both → a monorepo; checks + rules apply per sub-tree; `cmpl check` runs both.
- Other stacks (`go.mod`, `Cargo.toml`) → add their checks in `completely.toml [check]`.

Everything else — the loop, quarantine, worker-contract, memory policy — is identical regardless of
stack. Extend by editing `completely.toml`, never by forking the system.
