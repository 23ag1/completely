#!/usr/bin/env python3
"""completely worker-contract lint.

Reads `bd list --status open --json` on stdin. Every open *task* must carry the worker-contract
sections that close a silent-failure class: acceptance (what proves done), design (approach/why),
metadata.write_zone (which files it may touch), and metadata.verify (the proof command) — and when
the write-zone touches an executable entrypoint (the loop / hooks / bin), that verify must run the
REAL path via `cmpl test` / `contracts.sh` / `CMP_CLAUDE_CMD`, not a proxy unit (the 52v lesson:
a green unit/--self-test alone let a crash ship). Exit 1 if any task is missing one.
"""

import json
import os
import re
import sys

# Executable entrypoints whose bugs live in the runtime path, not a pure unit beside it. A task
# touching one must verify via the real runner (the deterministic floor under Path-Exercised).
# `hooks/` matches the whole gate area (dir or file, relative or absolute — w6c.5 declares the dir);
# `bin/<name>` matches extensionless executables (plugin/bin/cmpl) but not dotted docs (docs/bin/x.md).
ENTRYPOINT_RE = re.compile(r"(^|/)run\.sh$|(^|/)hooks/|(^|/)bin/[^/.]+$")
# String-match only — it does NOT parse shell (`echo contracts.sh` would pass). This is a FLOOR
# (the planner must consciously name a real runner), not a sandbox; the evaluator + the enforced
# VERIFY policy own the actual Path-Exercised guarantee.
REALPATH_RE = re.compile(r"cmpl test|contracts\.sh|CMP_CLAUDE_CMD")

try:
    data = json.load(sys.stdin)
except Exception:
    data = []
data = data if isinstance(data, list) else data.get("issues", [])

bad = 0
for it in data:
    if it.get("issue_type") != "task":
        continue
    labels = it.get("labels") or []
    if "checkpoint" in labels or "gate" in labels:
        continue  # human gates aren't work-tasks — exempt from the worker-contract
    md = it.get("metadata") or {}
    if isinstance(md, str):
        try:
            md = json.loads(md)
        except Exception:
            md = {}
    miss = []
    if not (it.get("acceptance_criteria") or "").strip():
        miss.append("acceptance")
    if not (it.get("design") or "").strip():
        miss.append("design")
    if not md.get("write_zone"):
        miss.append("metadata.write_zone")
    verify = (md.get("verify") or "").strip()
    if not verify:
        miss.append("metadata.verify")
    else:
        eps = [
            p
            for p in (md.get("write_zone") or [])
            if isinstance(p, str) and ENTRYPOINT_RE.search(p)
        ]
        if eps and not REALPATH_RE.search(verify):
            miss.append(
                "metadata.verify must exercise the real entrypoint via cmpl test / contracts.sh / "
                "CMP_CLAUDE_CMD (touches %s), not a proxy"
                % ",".join(os.path.basename(p.rstrip("/")) for p in eps)
            )
    if miss:
        bad += 1
        print("  FAIL %s: missing %s" % (it.get("id"), ", ".join(miss)))

if bad:
    print("  %d task(s) missing required worker-contract sections" % bad)
    sys.exit(1)
print("  ok: all open tasks carry acceptance + design + write_zone + verify")
