# completely

**Make a coding agent hard to lie to you.** `completely` turns *"the agent said it's done"* into
*"here's the proof, graded by an independent checker"* — and fuses **GSD** (planning), **Ralph**
(autonomous loop), and **Beads** (memory) into one install with quality and safety gates baked in.

Short CLI: **`cmpl`**. Slash commands: **`/completely:*`**.

---

## The problem this solves

Coding agents fail in the same boring ways, and a longer `CLAUDE.md` doesn't fix it (an essay
nobody executes):

- claim **"done"** without actually running anything;
- quietly **downscope** a tool into a stub;
- **disable a failing test** to go green;
- **lose context** between sessions — redo or forget work;
- you stack GSD + Ralph + Beads and they **fight** (three task queues, drift, no single truth).

`completely` fixes these *structurally* — by engineering the environment so they can't happen —
instead of asking nicely in a prompt.

## Before → after

| Without | With `completely` |
|---|---|
| "I ran the tests, all green" *(no output)* | acceptance **proven by evidence in Beads**, graded by a read-only **default-FAIL evaluator** |
| you hope edits were linted | a hook lints/type-checks **every edit**; `cmpl check` runs all checks in **one terse pass** |
| `rm -rf`, force-push slip through | a guard hook **blocks** them (exit 2) |
| GSD todos + Ralph plan + Beads = **3 queues** | **one spine** (Beads); GSD plans → `cmpl emit`; the loop drives `bd ready` |
| "minimal version" stub, silently | **no-stub contract** — downscope only via an explicit `blocked` |
| an upstream update breaks your wiring | `cmpl doctor` **quarantines** on drift; `cmpl update` re-syncs — no step breaks |

## What you get (one install)

- **Spine** — Beads holds status, memory (comments/notes/`remember`), and coordination.
- **Planning** — GSD (discuss → plan → plan-checker), emitted into Beads with `cmpl emit`.
- **Execution** — *one engine, two modes*: **supervised** (GSD wave subagents) or **unattended**
  (Ralph-style fresh-context loop), both over `bd ready`. Pick the mode with the autonomy dial.
- **Quality floor** — gate hooks (lint/types + dangerous-command block), a default-FAIL
  `evaluator`, a worker-contract `cmpl lint`, and one-pass `cmpl check`.
- **Adaptive** — frontend **and** backend in one system, detected automatically (no modes to pick).
- **Upgrade-safe** — overlays (it never edits GSD/Ralph) + version drift quarantine.

## Install

```bash
claude plugin marketplace add 23ag1/completely
claude plugin install completely@completely
```

**Requires Beads (`bd`)** — the only hard dependency. GSD (planning) and claude-mem (memory) are
optional; Ralph is *not* required (completely's loop is built in). On install, a Setup hook reports
what's missing. To auto-install it all (with consent):

```bash
cmpl setup --install            # install missing deps via their real channels
cmpl setup --install --dry-run  # preview the exact commands first
```

Then, in any repo:

```bash
cmpl setup          # report deps; add --install to auto-install missing ones
/completely:init    # discovery: new vs existing, stack + architecture, scaffold the thin layer
cmpl quality        # install a pre-commit gate (cmpl check) + starter lint configs
/completely:plan    # plan a feature straight into Beads (no markdown) — discovery + decompose
cmpl check          # run all checks in one pass → "clean" or just the failure
cmpl run --dry-run  # see the queue, then `cmpl run` to drive bd ready
```

**Manual / non-plugin:** `git clone https://github.com/23ag1/completely && cd completely && ./install.sh --project /path/to/repo`

## Command surface

`cmpl` (short CLI):

| Command | Does |
|---|---|
| `cmpl check` | run all configured quality checks, one pass, terse output |
| `cmpl lint` | enforce the worker-contract (acceptance+design+write-zone) on Beads tasks |
| `cmpl plan-apply` | materialize a structured plan → Beads epic+tasks+swarm (the **Beads-first** path, no markdown) |
| `cmpl sync` | *migration:* import existing markdown task lists → Beads |
| `cmpl emit <PLAN.md>` | *migration:* import an existing GSD `PLAN.md` → Beads |
| `cmpl run` | drive `bd ready` — supervised (GSD) or unattended (Ralph) |
| `cmpl setup` | verify upstreams + wire project Beads |
| `cmpl quality` | scaffold pre-commit gate + lint configs |
| `cmpl doctor` | upstream version drift + overlay quarantine |
| `cmpl update` | re-check + re-sync after upstreams change |
| `cmpl test` | run the contract regression suite |

Slash: `/completely` · `/completely:init` · `/completely:sync` · `/completely:run` · `/completely:check`

## Configure

A `completely.toml` (optional — sane defaults) lets you customize the pipeline without touching
scripts: `[stack]`, `[architecture]`, `[check].commands`, `[skills].prefer`, `[tools].lazy`. Your
own skills and rules compose *on top* — `completely` layers, it never overrides.

## How it fits with your tools

`completely` is the quality + verification + glue layer. It does **not** own your planning or task
queue — it composes with them, routing everything through Beads. See
[`docs/TOOL-COMPATIBILITY.md`](docs/TOOL-COMPATIBILITY.md) for the full design (per-tool detail,
"who owns what", the two-modes engine, upgrade-safety) and [`plugin/core/`](plugin/core/) for the
principle, roles, routing, architectures, token-economy, and adaptivity.

## Caveats

- **Token cost.** Multi-agent verification costs multiples of a single session — keep a fast path
  for trivial edits.
- **The live autonomous loop** (`cmpl run` unattended) needs a real session to prove end-to-end;
  every *deterministic* contract is covered by `cmpl test`.
- **Hooks can be finicky** — prefer explicit `cmpl`/`bd` commands over fragile session hooks.
- **Trust** — install skills/MCP only from sources you trust.

## License

MIT — see [`LICENSE`](LICENSE).
