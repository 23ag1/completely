# Immutability

Create new objects; never mutate existing ones. Mutation hides side effects, makes bugs
non-local, and breaks safe concurrency.

- WRONG: `obj.field = v` / `list.push(x)` on shared/borrowed data.
- RIGHT: return a new copy with the change (`{...obj, field: v}`, `[...list, x]`, frozen dataclasses).
- Treat function inputs as read-only. If you must build up state, build a local then return it.
- **Front:** never mutate React state/props; derive, don't edit. **Back:** prefer pure functions;
  isolate the few places that touch a DB/IO behind a clear boundary.

Exception: a documented, local, performance-critical hot path — measured, commented, contained.
