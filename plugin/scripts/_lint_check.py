#!/usr/bin/env python3
"""completely worker-contract lint.

Reads `bd list --status open --json` on stdin. Every open *task* must carry the worker-contract
sections that close a silent-failure class: acceptance (what proves done), design (approach/why),
and metadata.write_zone (which files it may touch). Exit 1 if any task is missing one.
"""
import json
import sys

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
    if miss:
        bad += 1
        print("  FAIL %s: missing %s" % (it.get("id"), ", ".join(miss)))

if bad:
    print("  %d task(s) missing required worker-contract sections" % bad)
    sys.exit(1)
print("  ok: all open tasks carry acceptance + design + write_zone")
