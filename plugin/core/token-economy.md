# Token economy

Load the least context that still produces the right outcome.

- **Progressive disclosure (native).** A skill costs ~name+description until it matches; its body
  loads only then; nested files only when needed. Keep descriptions sharp so the right skill
  triggers — don't pre-load tool bodies.
- **Don't dump a tool's whole surface.** With GSD/Beads, invoke the specific command you need
  (`/gsd:plan-phase`, `bd ready`) instead of loading every subcommand up front. They're available
  on demand — that's the point.
- **One script, not N round-trips.** `cmpl check` runs lint+types+tests in one pass and prints
  "clean" or only the failing output — instead of the agent running each and reading full logs.
  Same for `cmpl sync`, `cmpl emit`.
- **Scripts over MCP when a shell will do.** If the agent has a terminal, a small command is cheaper
  than an always-loaded MCP tool. Reserve MCP for what a script can't do (a live browser, a remote API).
- **Fresh context per task** beats one long session: re-read only what the task needs.
- **Two compaction levers (input vs output) — be honest about which moves the needle.**
  Most cost lives on the **input** side: tool output the agent reads (test logs, greps, file dumps)
  dwarfs anything it writes. Both levers are OPTIONAL — neither is a hard dep; both degrade to no-op
  when absent. Routed via `cmpl craft`; listed alongside other optional upstreams in `cmpl setup`.
  - **rtk** (the bigger lever — input). Wraps dev commands (git/pytest/ruff/grep) and compresses
    their output *before* the agent reads it. Local, no key.
    Install via `cmpl setup --install` (offered as OPTIONAL alongside gsd/claude-mem/ralph; per-project
    `rtk init` runs automatically on install) — pinned in `versions.lock` so `cmpl doctor` surfaces drift.
    ⚠️ Rewrites command output — **gate cmds (`cmpl check` / `cmpl lint`) are excluded by construction**:
    completely never injects rtk into its own gate invocation chain, and the
    `plugin/tests/contracts.sh` "gate-parser safety" test proves their output is byte-identical with
    or without rtk active (with a negative-control variant that breaks the exclusion to prove the
    test bites). Quantify any saving with `cmpl bench --rtk on,off`, never assume.
  - **caveman** (the smaller lever — output). Keeps the agent's own output terse. Local, no key.
    The *principle* (no preamble, no trailing summary, evidence > prose) is **baked into the worker
    overlay** (overlays/ralph/PROMPT_build.completely.md) and applies whether or not `/caveman` is
    installed — the skill is an OPTIONAL amplifier, not a dependency.
  Output tokens are smaller in absolute terms but the agent controls them directly every turn, so the
  discipline pays off cumulatively. Don't skip it just because rtk is the bigger lever — they stack.
- **Benching the levers.** `cmpl bench` is the only honest answer to "did it help?". Run it with the
  arms held fixed (raw vs completely) and the relevant lever as the dimension you flip:
  `--arms raw,completely` × `rtk on/off` × `caveman on/off`. Today the rtk and caveman dimensions
  are toggled by wrapping `cmpl auto` invocation (rtk: alias the dev commands; caveman: prepend
  `/caveman ` to the seed prompt so the skill triggers when installed and is inert otherwise).
  Report **$ per passed run**, not $ per run — a cheaper arm that fails more isn't cheaper.
- Config knob: `completely.toml [tools] lazy = true` documents deferring heavy surfaces.
