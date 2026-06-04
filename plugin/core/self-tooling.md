# Self-tooling contract (no silent stubs)

When a task involves building a tool, script, harness, or any supporting capability:
**build the FULL version as specified.**

Reducing functionality is **not allowed by default**. A "minimal version", a stub, a
placeholder, a `TODO: implement later`, or "I built a simplified variant" is acceptable
**only** through an explicit `blocked` return that states:

- what the full version requires,
- why it can't be built as specified right now,
- the specific question or decision you need from the human.

Never downscope silently. "I assumed a stub was enough" is a **task failure**, not a shortcut.

The `evaluator` agent treats any silent reduction of scope as **FAIL**. If you genuinely
cannot deliver the full scope, STOP and ask — that is the correct, expected move, not a
fallback to a stub.
