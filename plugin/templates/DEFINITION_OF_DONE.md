# Definition of Done

> Every item is **FAIL by default**. It flips to **PASS only with attached proof**
> (command output, a passing test, a file reference). The `evaluator` agent enforces this.

- [ ] All acceptance criteria from the spec are met **IN FULL** (not downscoped — see self-tooling contract)
- [ ] Tests written **before** the implementation, cover the behavior, and pass — *(attach output)*
- [ ] Lint passes with 0 errors — *(attach output: e.g. `ruff check` / `eslint .`)*
- [ ] Type check passes with 0 errors — *(attach output: e.g. `mypy` / `tsc --noEmit`)*
- [ ] Security scan: no findings — *(attach output if configured: `bandit` / `semgrep` / `gitleaks`)*
- [ ] `code-reviewer` subagent: readability/maintainability approved
- [ ] `security-reviewer` subagent: approved (for anything touching input, auth, or data)
- [ ] **No test deleted, skipped, or disabled** — *(verify with `git diff`)*
- [ ] Commit message references the task ID
