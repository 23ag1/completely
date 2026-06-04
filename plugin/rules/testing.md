# Testing

TDD by default: RED → GREEN → REFACTOR. The test is an objective, machine-checkable target.

- Write the failing test first; confirm it fails for the RIGHT reason; then minimal code to pass.
- Cover behavior, not implementation detail — tests should survive a refactor.
- Three kinds, all matter: **unit** (functions/components), **integration** (API/DB), **e2e**
  (critical user flows).
- Never delete, skip, `xfail`, or comment out a failing test to go green. Fix the code or file an
  issue. A disabled test is a silent lie.
- Fix the implementation, not the test — unless the test itself is provably wrong.
- Keep tests isolated and deterministic (no shared state, no real clock/network unless intended).
