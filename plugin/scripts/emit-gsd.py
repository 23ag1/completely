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
Validated against GSD 1.3.1 PLAN.md — frontmatter (wave/depends_on/requirements/must_haves) +
task tags <name>/<files>/<action>/<verify>/<done>. Re-check against your GSD version if it drifts.
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


def _fm_unq(v):
    v = v.strip()
    if len(v) >= 2 and v[0] in "\"'" and v[-1] == v[0]:
        return v[1:-1]
    return v


def _fm_split_inline(inner: str):
    """Split an inline-list payload on TOP-LEVEL commas, respecting quoted regions.
    Latent today (GSD 1.3.1 emits comma-free ids), but `[a, "b, c", d]` must not break."""
    parts, buf, quote = [], [], None
    for ch in inner:
        if quote:
            buf.append(ch)
            if ch == quote:
                quote = None
        elif ch in ('"', "'"):
            quote = ch
            buf.append(ch)
        elif ch == ",":
            parts.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
    if quote is not None:
        raise ValueError("unmatched %s in inline list: %r" % (quote, inner))
    parts.append("".join(buf))
    return [p for p in parts if p.strip()]


def _fm_scalar(v):
    v = v.strip()
    if v.startswith("[") and v.endswith("]"):
        inner = v[1:-1].strip()
        return [_fm_unq(x) for x in _fm_split_inline(inner)] if inner else []
    return _fm_unq(v)


def _fm_parse(toks, i, indent):
    """Recursive-descent over (indent, text) tokens: mappings, block/flow lists, dicts-in-seq."""
    if toks[i][1].startswith("- "):
        seq = []
        while i < len(toks) and toks[i][0] == indent and toks[i][1].startswith("- "):
            body = toks[i][1][2:].strip()
            if ":" in body and not body.startswith("["):
                d = {}
                k, _, v = body.partition(":")
                i += 1
                # `- ` is 2 chars, so body (and thus sibling keys) sits at column indent+2.
                # Strictly greater = nested under THIS key; equal = sibling. Off-by-one matters.
                sibling_col = indent + 2
                if v.strip():
                    d[k.strip()] = _fm_scalar(v)
                elif i < len(toks) and toks[i][0] > sibling_col:
                    child, i = _fm_parse(toks, i, toks[i][0])
                    d[k.strip()] = child
                else:
                    d[k.strip()] = ""
                while (
                    i < len(toks)
                    and toks[i][0] > indent
                    and not toks[i][1].startswith("- ")
                ):
                    kk, _, vv = toks[i][1].partition(":")
                    d[kk.strip()] = _fm_scalar(vv) if vv.strip() else ""
                    i += 1
                seq.append(d)
            else:
                seq.append(_fm_scalar(body))
                i += 1
        return seq, i
    d = {}
    while i < len(toks) and toks[i][0] == indent and not toks[i][1].startswith("- "):
        k, _, v = toks[i][1].partition(":")
        key = k.strip()
        if v.strip():
            d[key] = _fm_scalar(v)
            i += 1
        else:
            i += 1
            if i < len(toks) and toks[i][0] > indent:
                child, i = _fm_parse(toks, i, toks[i][0])
                d[key] = child
            else:
                d[key] = []
    return d, i


def parse_frontmatter(text):
    """Parse a leading `--- ... ---` YAML frontmatter block. Minimal subset, no yaml dep —
    handles scalars, inline [a, b] and block lists, nested mappings, and `- key: val` dicts.
    Returns {} if absent; on parse error returns {'_raw': block} + warns (never silent)."""
    m = re.match(r"^---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n|\Z)", text, re.S)
    if not m:
        return {}
    rawfm = m.group(1)
    toks = [
        (len(ln) - len(ln.lstrip(" ")), ln.strip())
        for ln in rawfm.split("\n")
        if ln.strip() and not ln.lstrip().startswith("#")
    ]
    if not toks:
        return {}
    try:
        node, _ = _fm_parse(toks, 0, toks[0][0])
        return node if isinstance(node, dict) else {}
    except Exception as e:
        print("  ! frontmatter parse failed (%s) — storing raw" % e, file=sys.stderr)
        return {"_raw": rawfm}


def _bd_list_all():
    """Fetch every issue once (callers share it — avoids N+1 `bd list` and TOCTOU skew)."""
    r = bd("list", "--all", "--json")
    try:
        d = json.loads(r.stdout or "[]")
    except Exception:
        d = []
    return d if isinstance(d, list) else d.get("issues", [])


def epics_by_planlabel(data):
    """Map `gsd-plan-<phase>-<plan>` label -> epic id, for cross-plan dependency resolution."""
    out = {}
    for it in data:
        if it.get("issue_type") != "epic":
            continue
        for lab in it.get("labels", []) or []:
            if isinstance(lab, str) and lab.startswith("gsd-plan-"):
                out[lab] = it["id"]
    return out


def children_of(epic_id, data):
    """Task ids under an epic (bd uses hierarchical ids: <epic>.<n>)."""
    pre = epic_id + "."
    return [
        it["id"]
        for it in data
        if str(it.get("id", "")).startswith(pre) and it.get("issue_type") != "epic"
    ]


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: emit-gsd.py <PLAN.md>", file=sys.stderr)
        return 2
    plan = sys.argv[1]
    text = open(plan).read()
    rel = os.path.relpath(plan)
    existing = load_existing()

    def upsert(
        ref,
        title,
        typ="task",
        parent=None,
        acceptance="",
        design="",
        metadata=None,
        extra_labels=(),
    ):
        lab = srclabel(ref)
        labels = ",".join([lab, "gsd-emit", *extra_labels])
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
            print(
                "  ! create failed: %s\n    %s" % (title, r.stderr.strip()),
                file=sys.stderr,
            )
            return None, "error"
        existing[lab] = nid
        return nid, "created"

    fm = parse_frontmatter(text)
    m = re.search(r"^#\s+(.+)$", text, re.M)
    epic_title = m.group(1).strip() if m else os.path.basename(plan)
    epic_meta = {
        k: fm[k]
        for k in ("phase", "plan", "wave", "depends_on", "requirements", "must_haves")
        if fm.get(k) not in (None, "", [], {})
    }
    plan_label = ()
    if fm.get("phase") and fm.get("plan"):
        plan_label = ("gsd-plan-%s-%s" % (fm["phase"], fm["plan"]),)
    epic_id, _ = upsert(
        "gsd:%s#epic" % rel,
        epic_title,
        typ="epic",
        metadata=epic_meta or None,
        extra_labels=plan_label,
    )
    if not epic_id:
        return 1

    def el(body, tag):
        mm = re.search(r"<%s>(.*?)</%s>" % (tag, tag), body, re.S)
        return mm.group(1).strip() if mm else ""

    created = updated = 0
    task_ids = []
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
                ref,
                name,
                parent=epic_id,
                design=el(body, "how-to-verify") or el(body, "what-built"),
                metadata={"checkpoint": typ},
                extra_labels=("checkpoint", typ.replace(":", "-")),
            )
        else:
            md = {}
            files = el(body, "files")
            verify = el(body, "verify")
            if files:
                md["write_zone"] = [
                    f.strip() for f in re.split(r"[,\n]", files) if f.strip()
                ]
            if verify:
                md["verify"] = verify
            if fm.get("requirements"):
                md["requirements"] = fm["requirements"]
            nid, st = upsert(
                ref,
                name,
                parent=epic_id,
                acceptance=el(body, "done"),
                design=el(body, "action"),
                metadata=md,
                extra_labels=(typ,),
            )
        if st == "created":
            created += 1
        elif st == "updated":
            updated += 1
        if nid:
            task_ids.append(nid)
            print("  %s %s  %s" % ("+" if st == "created" else "=", nid, name))

    # intra-plan dependency chain (document order) — interface-first default. This APPROXIMATES
    # GSD's wave DAG: GSD encodes parallelism ACROSS PLAN files, not within one. The cross-plan
    # edges below carry the real wave ordering at task level (so `bd ready` actually gates waves).
    for prev, cur in zip(task_ids, task_ids[1:]):
        bd("dep", "add", cur, "--depends-on", prev)
    deps = fm.get("depends_on") or []
    if task_ids and deps:
        allissues = _bd_list_all()
        label_map = epics_by_planlabel(allissues)
        for dep in deps:
            # exact match only: depends_on uses GSD's `<phase>-<plan>` id, label is gsd-plan-<that>.
            # No substring fallback — a near-miss is a real data bug to surface loudly, not guess.
            dep_epic = label_map.get("gsd-plan-%s" % dep)
            if not dep_epic:
                print(
                    "  ! cross-plan dep '%s' (label gsd-plan-%s) not found — emit it first? skipped"
                    % (dep, dep),
                    file=sys.stderr,
                )
                continue
            for t in children_of(dep_epic, allissues):
                bd("dep", "add", task_ids[0], "--depends-on", t)

    print("emit: epic %s; +%d created, ~%d existing" % (epic_id, created, updated))
    return 0


if __name__ == "__main__":
    sys.exit(main())
