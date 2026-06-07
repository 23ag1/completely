# Memory policy — one canon, no contradictions

Route every fact to exactly one home by its TYPE:

- **Task-bound fact** (a decision or blocker tied to an issue) → `bd comment <id>` / `bd remember --key`.
- **Per-task progress log** → `bd comment` (replaces Ralph `PROGRESS.md`).
- **Cross-task architecture decision** (lib/pattern/contract that future tasks must inherit) →
  a standalone ADR bead: `bd create --type=decision --title "..." --description "context · choice · consequences"`.
  Built-in `decision` type (see `bd types`). Retrieve with `bd query "type=decision"`; the task engine's
  PLAN-CHECK step (`core/task-engine.md` §2) requires this query before picking an approach.
- **Cross-session "did we do/solve this?"** → claude-mem search, or `bd search` / `bd find-duplicates`.
- **Durable fact about the user / project / preferences** → your global memory (`MEMORY.md`).
- **Task status** → ONLY Beads. Never markdown.

This resolves the contradiction between Beads' `AGENTS.md` ("use `bd remember`, NOT MEMORY.md")
and the global memory system ("use MEMORY.md") by **scoping, not banning**: Beads owns task-bound
facts + status; `MEMORY.md` owns durable user/project facts. They do not overlap.
