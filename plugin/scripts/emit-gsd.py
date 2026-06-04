#!/usr/bin/env python3
"""completely :: GSD -> Beads emitter.

Parse a GSD PLAN.md and emit an epic + child tasks into Beads, mapping the GSD worker-contract
onto Beads fields so the queue (not markdown) is the source of truth:

    <name>  -> title            <done>   -> acceptance_criteria
    <action>-> design           <files>  -> metadata.write_zone
    <verify>-> metadata.verify  type     -> label (gsd type)

Idempotent: each task is keyed by a stable source_ref (label `src-<sha1[:8]>`), so re-emitting
after GSD re-plans reconciles instead of duplicating. checkpoint:* tasks become human-gate
issues labelled `checkpoint` (skipped by `cmpl lint`'s worker-contract check).

Usage: emit-gsd.py <PLAN.md>
Validated against GSD 1.20.x PLAN.md task syntax. Re-check against your GSD version if it drifts.
"""
import hashlib
import json
import os
import re
import subprocess
import sys


def bd(*args):
    return subprocess.run(["bd", *args], capture_output=True, text=True)


def srclabel(ref: str) -> str:
    return "src-" + hashlib.sha1(ref.encode()).hexdigest()[:8]


def load_existing() -> dict:
    r = bd("list", "--all", "--json")
    try:
        data = json.loads(r.stdout or "[]")
    except Exception:
        data = []
    data = data if isinstance(data, list) else data.get("issues", [])
    out = {}
    for it in data:
        for lab in it.get("labels", []) or []:
            if isinstance(lab, str) and lab.startswith("src-"):
                out[lab] = it["id"]
    return out


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: emit-gsd.py <PLAN.md>", file=sys.stderr)
        return 2
    plan = sys.argv[1]
    text = open(plan).read()
    rel = os.path.relpath(plan)
    existing = load_existing()

    def upsert(ref, title, typ="task", parent=None, acceptance="", design="",
               metadata=None, extra_labels=()):
        lab = srclabel(ref)
        labels = ",".join([lab, "gsd-emit", *extra_labels])
        if lab in existing:
            return existing[lab], "updated"
        args = ["create", title, "-t", typ, "-l", labels, "--no-inherit-labels"]
        if parent:
            args += ["--parent", parent]
        if acceptance:
            args += ["--acceptance", acceptance]
        if design:
            args += ["--design", design]
        if metadata:
            args += ["--metadata", json.dumps(metadata)]
        args += ["--json"]
        r = bd(*args)
        try:
            nid = json.loads(r.stdout)["id"]
        except Exception:
            print("  ! create failed: %s\n    %s" % (title, r.stderr.strip()), file=sys.stderr)
            return None, "error"
        existing[lab] = nid
        return nid, "created"

    m = re.search(r"^#\s+(.+)$", text, re.M)
    epic_title = m.group(1).strip() if m else os.path.basename(plan)
    epic_id, _ = upsert("gsd:%s#epic" % rel, epic_title, typ="epic")
    if not epic_id:
        return 1

    def el(body, tag):
        mm = re.search(r"<%s>(.*?)</%s>" % (tag, tag), body, re.S)
        return mm.group(1).strip() if mm else ""

    created = updated = 0
    for tb in re.finditer(r"<task\b([^>]*)>(.*?)</task>", text, re.S):
        attrs, body = tb.group(1), tb.group(2)
        tm = re.search(r'type="([^"]+)"', attrs)
        typ = tm.group(1) if tm else "auto"
        name = el(body, "name")
        if not name and typ.startswith("checkpoint"):
            name = el(body, "what-built") or el(body, "how-to-verify")[:60]
        if not name:
            name = "checkpoint" if typ.startswith("checkpoint") else "task"
        ref = "gsd:%s#%s" % (rel, name)
        if typ.startswith("checkpoint"):
            nid, st = upsert(
                ref, name, parent=epic_id,
                design=el(body, "how-to-verify") or el(body, "what-built"),
                metadata={"checkpoint": typ},
                extra_labels=("checkpoint", typ.replace(":", "-")),
            )
        else:
            md = {}
            files = el(body, "files")
            verify = el(body, "verify")
            if files:
                md["write_zone"] = [f.strip() for f in re.split(r"[,\n]", files) if f.strip()]
            if verify:
                md["verify"] = verify
            nid, st = upsert(
                ref, name, parent=epic_id,
                acceptance=el(body, "done"), design=el(body, "action"),
                metadata=md, extra_labels=(typ,),
            )
        if st == "created":
            created += 1
        elif st == "updated":
            updated += 1
        if nid:
            print("  %s %s  %s" % ("+" if st == "created" else "=", nid, name))

    print("emit: epic %s; +%d created, ~%d existing" % (epic_id, created, updated))
    return 0


if __name__ == "__main__":
    sys.exit(main())
