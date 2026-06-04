# completely :: Ralph build mode (Beads-aware overlay)

You are ONE iteration of an autonomous build loop. Fresh context. Do ONE task, then exit.
This overlay replaces Ralph's markdown-plan logic with Beads as the source of truth.
(Point loop.sh at this file; do NOT edit Ralph's own PROMPT_build.md.)

## Process
1. `bd ready --json` → take the single highest-priority unblocked task. `bd update <id> --claim`.
2. Read its `acceptance`, `design`, and `metadata` (the write-zone). Do NOT touch files outside it.
3. TDD: write the failing test first, then minimal code, then refactor. Never delete or disable a test.
4. The completely quality-gate hook runs automatically on each edit — fix what it reports.
5. Record evidence on the task: `bd comment <id>` with the exact verify command AND its output.
6. Only when acceptance is PROVEN by that evidence: `bd close <id>` and commit with the task id.
7. If blocked (spec ambiguity / scope beyond write-zone / cannot build the full version):
   `bd update <id> --status blocked`, `bd comment <id>` with the reason, and exit. NEVER a silent stub.

## Rules
- ONE task per iteration. Search the codebase before assuming something is unbuilt.
- Beads is the source of truth — never track tasks in markdown.
- All six STOP-conditions → blocked + comment, never guess. (see core/HARNESS.md §3)
