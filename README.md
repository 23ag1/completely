# completely

[![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-6E56CF)](https://github.com/23ag1/completely)
[![Stars](https://img.shields.io/github/stars/23ag1/completely?style=flat)](https://github.com/23ag1/completely/stargazers)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Contracts](https://img.shields.io/badge/contracts-39%2F0%20green-brightgreen)](plugin/tests/contracts.sh)

**Make a coding agent hard to lie to you.** `completely` turns *"the agent said it's done"* into
*"here's the proof, graded by an independent checker"* — unifying **GSD** (planning depth) and
**Beads** (the spine) under deterministic gates and a default‑FAIL evaluator, in one install.

Short CLI: **`cmpl`**. Slash commands: **`/completely:*`**.

> It holds *itself* to the same bar: this repo is built through its own engine, every deterministic
> contract is in `cmpl test` (**39 passing**), and during development its own default‑FAIL evaluator
> caught a real over‑graded task and a flagship‑loop crash before they could ship.

---

## The problem this solves

Coding agents fail in the same boring ways, and a longer `CLAUDE.md` doesn't fix it (an essay
nobody executes):

- claim **"done"** without actually running anything;
- quietly **downscope** a tool into a stub;
- **disable a failing test** to go green;
- **close a task with the code uncommitted**, or **lose context** between sessions;
- you stack GSD + a loop + Beads and they **fight** (three task queues, drift, no single truth).

`completely` fixes these *structurally* — by engineering the environment so they can't happen —
instead of asking nicely in a prompt.

## Before → after

| Without | With `completely` |
|---|---|
| "I ran the tests, all green" *(no output)* | acceptance **proven by evidence in Beads**, graded by a read‑only **default‑FAIL evaluator** |
| you hope edits were linted | a hook lints/type‑checks **every edit**; `cmpl check` runs all checks in **one terse pass** |
| `rm -rf`, force‑push slip through | a guard hook **blocks** them (exit 2) |
| a task closes with code uncommitted | a **commit‑before‑close gate** refuses `bd close` while the tree is dirty |
| GSD todos + a loop's plan + Beads = **3 queues** | **one spine** (Beads); GSD plans land as native epics + dependency **waves** |
| "minimal version" stub, silently | **no‑stub contract** — downscope only via an explicit `blocked` |
| an upstream update breaks your wiring | `cmpl doctor` **quarantines** on drift; `cmpl update` re‑syncs |

## What you get (one install)

- **Spine** — Beads holds status, memory (comments/notes), and coordination. *Status never lives in markdown.*
- **Planning** — GSD (discuss → plan → plan‑checker). Plans land **straight into Beads** as an
  epic + worker‑contract tasks + dependency **waves** + goal‑backward `must_haves`.
- **Execution** — *one engine, two modes*: **supervised** (GSD wave subagents, human gates) or
  **unattended** (fresh‑context loop over `bd ready`). The loop is **parallel by default** — it
  dispatches tasks whose write‑zones are *disjoint* concurrently and serializes same‑file ones.
- **Quality floor** — gate hooks (lint/types on every edit · dangerous‑command block ·
  commit‑before‑close), a default‑FAIL `evaluator` (with an adversarial claim‑vs‑refute mode), a
  worker‑contract `cmpl lint`, and one‑pass `cmpl check`.
- **Adaptive** — frontend **and** backend in one system, detected automatically (no modes to pick).
- **Upgrade‑safe** — overlays (it never edits your GSD install) + version‑drift quarantine.

> The autonomous loop is real, not a diagram: it runs a fresh `claude -p` worker per task and was
> driven end‑to‑end during this project's own development.

## Install

```bash
claude plugin marketplace add 23ag1/completely
claude plugin install completely@completely
```

**Requires Beads (`bd`)** — the only hard dependency. GSD (planning) and claude‑mem (memory) are
optional; a loop dependency is **not** required (completely's loop is built in). On install, a Setup
hook reports what's missing. To auto‑install (with consent):

```bash
cmpl setup --install            # install missing deps via their real channels
cmpl setup --install --dry-run  # preview the exact commands first
```

| Dependency | Required? | Install command |
|---|---|---|
| **Beads** (`bd`) | **yes** — the spine | `npm i -g @beads/bd` · `brew install beads` |
| GSD | optional — planning | `npx get-shit-done-cc --global` |
| claude‑mem | optional — memory | `claude plugin install claude-mem@thedotmack` |

Then, in any repo:

```bash
cmpl setup          # report deps; add --install to auto-install missing ones
/completely:init    # discovery: new vs existing, stack + architecture, scaffold the thin layer
cmpl quality        # install a pre-commit gate (cmpl check) + starter lint configs
/completely:plan    # plan a feature straight into Beads (no markdown) — discovery + decompose
cmpl check          # run all checks in one pass → "clean" or just the failure
cmpl run --dry-run  # see the queue + parallel plan, then `cmpl run` to drive bd ready
```

**Manual / non‑plugin:** `git clone https://github.com/23ag1/completely && cd completely && ./install.sh --project /path/to/repo`

## Command surface

`cmpl` (short CLI):

| Command | Does |
|---|---|
| `cmpl check` | run all configured quality checks, one pass, terse output |
| `cmpl lint` | enforce the worker‑contract (acceptance+design+write‑zone) on Beads tasks |
| `cmpl plan-apply` | materialize a structured plan → Beads epic+tasks+waves (the **Beads‑first** path, no markdown) |
| `cmpl run` | drive `bd ready` — supervised (GSD) or unattended (parallel, fresh‑context loop) |
| `cmpl emit <PLAN.md>` | *migration:* import an existing GSD `PLAN.md` (frontmatter `must_haves`/waves) → Beads |
| `cmpl sync` | *migration:* import existing markdown task lists → Beads |
| `cmpl setup` | verify upstreams + wire project Beads |
| `cmpl quality` | scaffold pre‑commit gate + lint configs |
| `cmpl doctor` | upstream version drift + overlay quarantine |
| `cmpl update` | re‑check + re‑sync after upstreams change |
| `cmpl test` | run the contract regression suite |

Slash: `/completely` · `/completely:init` · `/completely:plan` · `/completely:run` · `/completely:check`

## Configure

A `completely.toml` (optional — sane defaults) customizes the pipeline without touching scripts:
`[stack]`, `[architecture]`, `[check].commands`, `[skills].prefer`, `[tools].lazy`. Your own skills
and rules compose *on top* — `completely` layers, it never overrides. Knobs:
`CMP_PARALLEL` (worker concurrency, default 4) · `CMP_ALLOW_DIRTY_CLOSE` · `CMP_PUSH`.

## How it fits with your tools

`completely` is the quality + verification + glue layer. It does **not** own your planning or task
queue — it **routes** to the best existing tool for each concern and keeps everything in Beads. See
[`docs/TOOL-COMPATIBILITY.md`](docs/TOOL-COMPATIBILITY.md) for the full design and
[`plugin/core/`](plugin/core/) for the principle, roles, routing, the task engine, and token‑economy.

## Caveats (honest)

- **Token cost.** Multi‑agent verification costs multiples of a single session — keep a fast path for
  trivial edits. A real `quality/$` measurement (`cmpl bench`) is on the roadmap, not yet published.
- **Hooks can be finicky** — prefer explicit `cmpl`/`bd` commands over fragile session hooks.
- **Trust** — install skills/MCP only from sources you trust.

## License

MIT — see [`LICENSE`](LICENSE).
