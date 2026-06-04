# Error handling

Handle errors explicitly at every level. Never silently swallow.

- Fail with context: include the operation, inputs (no secrets), and cause.
- **UI-facing:** show a clear, actionable, non-technical message; never a raw stack trace.
- **Server-side:** log the full context (structured), keep the user message generic.
- Don't catch-and-ignore. If you catch, you either recover, translate, or re-raise — never drop.
- Distinguish expected failures (validation, not-found) from bugs (assert/throw) — handle the
  first as control flow, let the second surface loudly.
- No error message should leak secrets, internal paths, or SQL.
