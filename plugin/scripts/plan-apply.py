#!/usr/bin/env python3
"""completely :: plan-apply — materialize a structured plan straight into Beads (no markdown).

Reads a JSON plan on stdin (or a file arg) and creates an epic + worker-contract tasks + deps +
a `bd swarm`. This is the Beads-FIRST path: the planner emits STRUCTURE, not a PLAN.md file, so
there is one source of truth from the moment of planning — no md→bd transfer, no dual copies to
drift. Idempotent: keyed by source_ref label `src-<sha1[:8]>`, re-applying reconciles.

JSON schema:
{
  "epic": "Phase title",
  "tasks": [
    {"key":"schema","title":"...","acceptance":"...","design":"...",
     "write_zone":["db/x.py"],"verify":"pytest -q","deps":["otherkey"],"labels":["backend"],
     "requirements":["R-01"],"must_haves":{"truths":[],"artifacts":[],"key_links":[]},
     "read_context":["src/x.py"]}, ...
  ],
  "checkpoints": [
    {"key":"verify","title":"Human-verify X","after":"endpoint","how":"open /login"}
  ]
}
A task may depend on a checkpoint via deps:["cp:<key>"] so downstream waits for the human gate.
"""

import hashlib
import json
import re
import subprocess
import sys


def bd(*a):
    return subprocess.run(["bd", *a], capture_output=True, text=True)


def srclabel(ref):
    return "src-" + hashlib.sha1(ref.encode()).hexdigest()[:8]


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", (s or "").lower()).strip("-")[:40] or "plan"


def load_existing():
    r = bd("list", "--all", "--json")
    try:
        d = json.loads(r.stdout or "[]")
    except Exception:
        d = []
    d = d if isinstance(d, list) else d.get("issues", [])
    out = {}
    for it in d:
        for lab in it.get("labels", []) or []:
            if isinstance(lab, str) and lab.startswith("src-"):
                out[lab] = it["id"]
    return out


def main():
    if len(sys.argv) > 1 and sys.argv[1] not in ("-", ""):
        raw = open(sys.argv[1]).read()
    else:
        raw = sys.stdin.read()
    try:
        plan = json.loads(raw)
    except Exception as e:
        print("plan-apply: invalid JSON: %s" % e, file=sys.stderr)
        return 2

    epic_title = plan.get("epic") or "Plan"
    es = slug(epic_title)
    existing = load_existing()

    def upsert(
        ref,
        title,
        typ="task",
        parent=None,
        acceptance="",
        design="",
        metadata=None,
        labels=(),
    ):
        lab = srclabel(ref)
        if lab in existing:
            eid = existing[lab]
            cur = bd("show", eid, "--json")
            try:
                d = json.loads(cur.stdout)
                d = d[0] if isinstance(d, list) else d
            except Exception:
                d = {}
            upd = []
            if acceptance and (d.get("acceptance_criteria") or "") != acceptance:
                upd += ["--acceptance", acceptance]
            if design and (d.get("design") or "") != design:
                upd += ["--design", design]
            if metadata is not None:
                cm = d.get("metadata") or {}
                if isinstance(cm, str):
                    try:
                        cm = json.loads(cm)
                    except Exception:
                        cm = {}
                if cm != metadata:
                    upd += ["--metadata", json.dumps(metadata)]
            if upd:
                bd("update", eid, *upd)
                return eid, "updated"
            return eid, "exists"
        args = [
            "create",
            title,
            "-t",
            typ,
            "-l",
            ",".join([lab, *labels]),
            "--no-inherit-labels",
        ]
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
            print(
                "  ! create failed: %s\n    %s" % (title, r.stderr.strip()),
                file=sys.stderr,
            )
            return None, "error"
        existing[lab] = nid
        return nid, "created"

    epic_id, _ = upsert("plan:%s#epic" % es, epic_title, typ="epic")
    if not epic_id:
        return 1

    keymap = {}
    created = 0

    for t in plan.get("tasks", []):
        key = t.get("key") or slug(t.get("title", "task"))
        md = {}
        if t.get("write_zone"):
            md["write_zone"] = t["write_zone"]
        if t.get("verify"):
            md["verify"] = t["verify"]
        if t.get("requirements"):
            md["requirements"] = t["requirements"]
        if t.get("must_haves"):
            md["must_haves"] = t["must_haves"]
        # read_context = what to READ first to understand the task (interfaces/contracts outside the
        # write_zone). Canonical key is read_context; read_first is accepted as a back-compat alias.
        rc = t.get("read_context") or t.get("read_first")
        if rc:
            md["read_context"] = rc
        nid, st = upsert(
            "plan:%s#%s" % (es, key),
            t.get("title", key),
            parent=epic_id,
            acceptance=t.get("acceptance", ""),
            design=t.get("design", ""),
            metadata=md or None,
            labels=tuple(t.get("labels", [])),
        )
        if nid:
            keymap[key] = nid
        if st == "created":
            created += 1

    for c in plan.get("checkpoints", []):
        key = c.get("key") or slug(c.get("title", "checkpoint"))
        nid, st = upsert(
            "plan:%s#cp-%s" % (es, key),
            c.get("title", "Checkpoint"),
            parent=epic_id,
            design=c.get("how", ""),
            metadata={"checkpoint": "human"},
            labels=("checkpoint",),
        )
        if nid:
            keymap["cp:" + key] = nid
            after = c.get("after")
            if after in keymap:
                bd("dep", "add", nid, "--depends-on", keymap[after])
        if st == "created":
            created += 1

    for t in plan.get("tasks", []):
        key = t.get("key") or slug(t.get("title", "task"))
        for dep in t.get("deps", []):
            if key in keymap and dep in keymap:
                bd("dep", "add", keymap[key], "--depends-on", keymap[dep])

    sw = bd("swarm", "create", epic_id)
    print("  epic %s, +%d issues created" % (epic_id, created))
    print("  swarm: %s" % ("created" if sw.returncode == 0 else "exists/skip"))
    for line in bd("swarm", "validate", epic_id).stdout.splitlines():
        if "Wave" in line:
            print("   ", line.strip())
    return 0


if __name__ == "__main__":
    sys.exit(main())
