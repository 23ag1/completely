#!/usr/bin/env python3
"""completely :: bench — measure code-quality / token-spend WITH vs WITHOUT completely.

Ports ECC's agent-eval + benchmark-optimization-loop (see research/ecc/, docs/BENCH-METHODOLOGY.md):
a pinned task + deterministic judges + git-worktree isolation + >=N repeats + cost from
`claude -p --output-format json`. The arms hold agent+model fixed; the variable is the HARNESS.
Headline metric: **$ per PASSED run** (not $ per run).

Task files: bench/suite/*.json  →  {name, base?, prompt, files[], judge[]}
  judge entry: {"type":"command"|"pytest","command":"..."}  or  {"type":"grep","pattern":"re","files":"a,b"}

Arms (built-in):
  raw         : prompt | claude -p --output-format json           (no harness, no gates, no subagents)
  completely  : seed the prompt as a bd task, then `cmpl auto --max 1` with CMP_BENCH_LOG=<cost file>
                so run.sh appends each inner claude JSON → we sum it.

Mock seam (tests, NO LLM spend): set CMP_BENCH_CMD to a command run for EVERY arm; it works in the
per-run worktree (cwd), reads BENCH_PROMPT, and writes a result JSON to BENCH_COST.
"""

import argparse
import glob
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile


def sh(cmd, cwd=None, env=None, capture=False):
    return subprocess.run(
        ["bash", "-c", cmd], cwd=cwd, env=env, capture_output=capture, text=True
    )


def load_tasks(tasks_dir):
    out = []
    for p in sorted(glob.glob(os.path.join(tasks_dir, "*.json"))):
        try:
            out.append((p, json.load(open(p))))
        except Exception as e:
            print(f"bench: skip {p}: {e}", file=sys.stderr)
    return out


def parse_cost(path):
    """Sum total_cost_usd (+ tokens/turns/dur) over a result file: one JSON object or JSONL."""
    agg = {"cost": 0.0, "in": 0, "out": 0, "turns": 0, "dur": 0}
    try:
        txt = open(path).read().strip()
    except Exception:
        return agg
    recs = []
    try:
        d = json.loads(txt)
        recs = d if isinstance(d, list) else [d]
    except Exception:
        for line in txt.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                recs.append(json.loads(line))
            except Exception:
                pass
    for r in recs:
        if not isinstance(r, dict):
            continue
        agg["cost"] += float(r.get("total_cost_usd") or 0)
        u = r.get("usage") or {}
        agg["in"] += int(u.get("input_tokens") or 0)
        agg["out"] += int(u.get("output_tokens") or 0)
        agg["turns"] += int(r.get("num_turns") or 0)
        agg["dur"] += int(r.get("duration_ms") or 0)
    return agg


def run_arm(arm, prompt, workdir, cost_path, rtk_on=False):
    # rtk dimension (OPTIONAL token-economy input lever): when rtk_on=True we set CMP_RTK=1 in the
    # subprocess env. Downstream wrappers (rtk shell aliases set in the agent's shell init) can
    # see it and route dev commands through `rtk wrap …`. completely's own gate cmds (cmpl check /
    # cmpl lint) are NEVER wrapped — see token-economy.md and the gate-parser-safety contract test
    # (which proves byte-equal output for `cmpl check` whether rtk is "active" or not).
    env = {**os.environ, "BENCH_PROMPT": prompt, "BENCH_COST": cost_path}
    if rtk_on:
        env["CMP_RTK"] = "1"
    else:
        env.pop("CMP_RTK", None)
    override = os.environ.get("CMP_BENCH_CMD")
    if override:  # mock seam — same runner for every arm
        sh(override, cwd=workdir, env=env)
        return
    if arm == "raw":
        claude = os.environ.get("CMP_CLAUDE_CMD", "claude -p --output-format json")
        sh(
            f'printf %s "$BENCH_PROMPT" | {claude} > {shlex.quote(cost_path)}',
            cwd=workdir,
            env=env,
        )
    elif arm == "completely":
        env["CMP_BENCH_LOG"] = cost_path  # run.sh appends each inner claude JSON here
        if os.path.isdir(os.path.join(workdir, ".beads")):
            sh(
                f"bd create {shlex.quote(prompt[:72])} -t task --json >/dev/null 2>&1",
                cwd=workdir,
                env=env,
            )
        sh("cmpl auto --max 1", cwd=workdir, env=env)
    else:
        print(f"bench: unknown arm '{arm}'", file=sys.stderr)


def judge(judges, workdir):
    for j in judges or []:
        t = j.get("type")
        if t in ("command", "pytest"):
            if sh(j.get("command", "false"), cwd=workdir).returncode != 0:
                return False
        elif t == "grep":
            pat = j.get("pattern", "")
            files = j.get("files", "")
            files = files if isinstance(files, list) else re.split(r"[,\n]", files)
            hit = False
            for f in (x.strip() for x in files if x.strip()):
                fp = os.path.join(workdir, f)
                try:
                    if re.search(pat, open(fp).read()):
                        hit = True
                        break
                except Exception:
                    pass
            if not hit:
                return False
        else:
            print(
                f"bench: unknown judge type '{t}' — treating as fail", file=sys.stderr
            )
            return False
    return True


def main():
    ap = argparse.ArgumentParser(prog="cmpl bench")
    ap.add_argument("--tasks", default="bench/suite")
    ap.add_argument("--arms", default="raw,completely")
    ap.add_argument("--repeats", type=int, default=3)
    ap.add_argument("--model", default=os.environ.get("CMP_BENCH_MODEL", ""))
    ap.add_argument("--base", default="")
    ap.add_argument("--out", default="bench/results.csv")
    ap.add_argument(
        "--rtk",
        default="off",
        help="rtk dimension: 'off' | 'on' | 'off,on' (input-token compaction lever; "
        "gate cmds excluded by construction — see token-economy.md).",
    )
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    arms = [x for x in a.arms.split(",") if x]
    rtk_dim = [v for v in a.rtk.split(",") if v in ("on", "off")] or ["off"]
    base_repo = os.getcwd()
    if sh("git rev-parse --git-dir", cwd=base_repo, capture=True).returncode != 0:
        print("bench: not a git repo (worktree isolation needs git)", file=sys.stderr)
        return 1
    tasks = load_tasks(a.tasks)
    if not tasks:
        print(f"bench: no *.json tasks in {a.tasks}", file=sys.stderr)
        return 1

    rows = []
    for tpath, task in tasks:
        name = task.get("name") or os.path.basename(tpath)
        base = a.base or task.get("base") or "HEAD"
        for arm in arms:
            for rtk_v in rtk_dim:
                for r in range(1, a.repeats + 1):
                    if a.dry_run:
                        print(
                            f"  [dry-run] {name} arm={arm} rtk={rtk_v} run={r} base={base}"
                        )
                        continue
                    wt = tempfile.mkdtemp(prefix="benchwt.")
                    cost_path = os.path.join(
                        tempfile.gettempdir(),
                        f"benchcost.{name}.{arm}.rtk{rtk_v}.{r}.{os.getpid()}",
                    )
                    open(cost_path, "w").close()
                    sh(
                        f"git worktree add --detach {shlex.quote(wt)} {shlex.quote(base)}",
                        cwd=base_repo,
                        capture=True,
                    )
                    try:
                        run_arm(
                            arm,
                            task.get("prompt", ""),
                            wt,
                            cost_path,
                            rtk_on=(rtk_v == "on"),
                        )
                        passed = judge(task.get("judge"), wt)
                        c = parse_cost(cost_path)
                        arm_label = f"{arm}+rtk" if rtk_v == "on" else arm
                        rows.append(
                            [
                                arm_label,
                                name,
                                r,
                                f"{c['cost']:.6g}",
                                c["in"],
                                c["out"],
                                c["turns"],
                                c["dur"],
                                1 if passed else 0,
                            ]
                        )
                        print(
                            f"  {name} arm={arm_label} run={r}: {'PASS' if passed else 'FAIL'}  ${c['cost']:.4f}"
                        )
                    finally:
                        sh(
                            f"git worktree remove --force {shlex.quote(wt)}",
                            cwd=base_repo,
                            capture=True,
                        )
                        try:
                            os.remove(cost_path)
                        except OSError:
                            pass
    if a.dry_run:
        return 0

    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "w") as f:
        f.write("arm,task,run,cost_usd,in_tok,out_tok,turns,dur_ms,judge_pass\n")
        for row in rows:
            f.write(",".join(str(x) for x in row) + "\n")

    # summary: per arm — runs, passed, pass%, total $, $/passed (the honest metric)
    print(f"\nbench summary  ({a.out})")
    print(
        f"  {'arm':<14}{'runs':>5}{'passed':>8}{'pass%':>7}{'total$':>10}{'$/passed':>11}"
    )
    # arm labels include the rtk dim ("arm" vs "arm+rtk") so each combo gets its own summary row.
    # Note: do NOT use `a` as the comprehension loop var — it shadows `a = ap.parse_args()` above.
    arm_labels = list(arms) + (
        [f"{lbl}+rtk" for lbl in arms] if "on" in rtk_dim else []
    )
    seen = set()
    arm_labels = [lbl for lbl in arm_labels if not (lbl in seen or seen.add(lbl))]
    for arm_label in arm_labels:
        ar = [x for x in rows if x[0] == arm_label]
        n = len(ar)
        p = sum(1 for x in ar if x[8] == 1)
        tot = sum(float(x[3]) for x in ar)
        per = (tot / p) if p else 0.0
        pct = (100 * p // n) if n else 0
        print(
            f"  {arm_label:<14}{n:>5}{p:>8}{pct:>6}%{tot:>10.4f}{(f'{per:.4f}' if p else 'n/a'):>11}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
