# Problem map — failure modes of the completely cycle (grounded in upstream issues + mock tests)

Sources: my deterministic mock-loop tests (`plugin/tests/loop-mock.sh`), the live istok auto run,
and the real bug trackers of the upstreams completely sits on — Beads (gastownhall/beads, ~30 open),
GSD (gsd-build/get-shit-done), and the ralph pattern (no public tracker; failure modes from its
blog/our observation + claude-plugins-official). Each row: does it apply to us, is it verified, status.

Legend: ✅ fixed · 🟡 mitigated/partial · 🔴 open · ⬜ N/A (design avoids it)

## A. Loop / orchestration (mock-verified)
| # | Problem | Source | Applies | Status |
|---|---|---|---|---|
| A1 | worker closes bead then dies before commit → closed bead, uncommitted code | istok run + mock S1 | yes | ✅ v0.7 commit-BEFORE-close |
| A2 | worker crashes mid-task → task stuck `in_progress`, loop reports "done" silently; re-run won't re-pick (in_progress ∉ ready) | mock S3 | yes | 🟡 v0.7 stall-detector bails+points to it; auto-reset = `cmpl recover` (WIP) |
| A3 | worker makes no progress → loop burns all `--max` iterations on one task | mock S4 | yes | ✅ v0.7 stall-detector (no close in N iters → stop) |
| A4 | resume after commit-but-not-closed → **double-commits** the task (no "already-done" guard) | mock S5 | yes | 🔴 needs claim-time guard (`git log --grep '(<id>)'` → close, don't redo) |
| A5 | nested `claude -p` workers pause when the main session idles / hit session limit | istok run + claude-plugins #2283 | yes | 🟡 auto skill: run FOREGROUND + idempotent/resumable; fundamental env constraint |
| A6 | worker tests need live infra (PG/Qdrant) that isn't up → fail | istok run (user's lesson) | yes | 🟡 `cmpl up` from `[services]` config (WIP) |

## B. Beads — the SPINE completely depends on (every loop calls `bd ready`)
| # | Problem | Source | Applies | Status |
|---|---|---|---|---|
| B1 | **`bd ready`/`bd list` PANIC** ("nil parent context") on full-table scan, embedded Dolt | beads #4293, #4267 | yes (on bd 1.0.x; we run 0.63.3 — not hit, but users upgrading hit it) | 🔴 + see B-NEW |
| B-NEW | **completely treats a `bd ready` FAILURE as "queue empty" → silent false "done".** Exposed by B1. | analysis | yes | 🔴 HIGH — `ready_count` must check bd's exit code; error ≠ empty |
| B2 | embedded dolt sql-server daemons never reaped → orphaned servers leak | beads #4282 | yes (we spawn bd constantly) | 🔴 note/reap |
| B3 | silent JSONL auto-import overwrites/leaks live bd data | beads #4239/4240/4245/4304 | yes — bd is our source of truth; silent data loss = catastrophic | 🔴 HIGH — set `import.auto=false`, back up `.beads`, doctor check |
| B4 | migration/schema drift → `bd list/ready` query references removed column → fails | beads #4297/4295 | yes — confirms the drift risk doctor was built for | 🟡 doctor/quarantine pins versions; + B-NEW error-detection |
| B5 | repeated no-op `schema: auto-migrate` commits pollute history | beads #4274 | yes | 🔴 low (noise) |

## C. GSD-class (from GSD's tracker)
| # | Problem | Source | Applies | Status |
|---|---|---|---|---|
| C1 | installer overwrites user `settings.json` hooks on upgrade | gsd #3856 | completely AVOIDS — overlays, never edits user settings | ⬜ design-validated |
| C2 | PostToolUse hook crashes the session (400 / bad output) | gsd #3878 | yes — we have a PostToolUse quality-gate hook | 🟡 verify our hooks exit 0 + bounded output |
| C3 | slash colon vs hyphen confusion (`/x:cmd` vs `/x-cmd`) | gsd #3862/3865/3868 | yes — we use `/completely:*` | 🟡 verify they invoke (they loaded — likely ok) |
| C4 | STATE.md corruption / milestone progress stomped / wrong phase | gsd #3880/3881/3866/3863/3882 | completely is Beads-first (no STATE.md) | ⬜ design-validated |
| C5 | silent no-op when a parsed field changes shape (JSON-wrapped / non-numeric) | gsd #3890/3889 | yes — we parse bd JSON | 🟡 defensive parsing + tests |
| C6 | agent told "Edit-only" but its `tools:` lacks Edit → can't act | gsd #3888 | yes — our agents (evaluator read-only etc.) | 🟡 verify each agent's tools match its role |
| C7 | concurrent tooling → intermittent failures under N-way concurrency | gsd #3869 | yes — parallel subagents hit bd concurrently | 🔴 merge-slot (advanced, unspiked); default sequential |
| C8 | fix merged to main but never released → no-op on installed version | gsd #3879 | yes — installed plugin/bd lags the repo | 🟡 version pinning + update discipline |

## D. Plugin / distribution
| # | Problem | Source | Applies | Status |
|---|---|---|---|---|
| D1 | missing `version` in plugin.json → `unknown/` cache dir, breaks | claude-plugins #2361 | yes — I hit version-pinning issues | ✅ version set + bumped each release |
| D2 | `cmpl` not on PATH (stripped shim) / symlink resolution | observed | yes | ✅ v0.5 full-CLI wrapper + readlink |
| D3 | upstream channel is a squatter (`get-shit-done` npm = a timer) | observed | yes | ✅ verified real channels (`get-shit-done-cc`) |

## Top priorities (what to fix next, by impact)
1. **B-NEW** — `cmpl auto` must distinguish a `bd ready` ERROR from an empty queue (today a bd crash = silent false "done"). HIGH, cheap.
2. **B3** — bd data integrity: `import.auto=false` + back up `.beads` before a run + doctor check. HIGH.
3. **A2/A6** — `cmpl recover` (reset stale in_progress) + `cmpl up` (infra from `[services]`), auto-called pre-loop. (in progress)
4. **A4** — resume "already-done" guard (no double-commit).
5. **C2/C6** — audit our hooks (exit 0, bounded output) and agent tool/role match.
6. **B4/C8** — keep doctor version-pinning honest; treat bd schema/version as a hard dependency.
