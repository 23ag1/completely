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
- Config knob: `completely.toml [tools] lazy = true` documents deferring heavy surfaces.
