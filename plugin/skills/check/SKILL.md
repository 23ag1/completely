---
name: completely:check
description: Run all configured quality checks (lint, types, tests) in one pass with terse output — reports "clean" when green, and only the failing check's output when not. Token-frugal; configured via completely.toml [check] or auto-detected per stack (front+back). Use before committing or to verify a change. Backed by `cmpl check`.
version: 0.3.0
user-invocable: true
argument-hint: "[dir]"
---
Run `cmpl check` from the repo root instead of running lint/types/tests separately (fewer tokens,
fixed sequence). It runs every check in `completely.toml [check]`, or auto-detects
eslint/tsc/vitest for a frontend and ruff/mypy/pytest for a backend.
- Clean → one line ("clean (N checks)"). A failure → only that check's output tail, not all logs.
- Add a check by editing `completely.toml`, not the script.
