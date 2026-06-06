#!/usr/bin/env python3
"""completely :: craft router — the connecting layer's "which tool" answer.

completely does NOT reimplement craft. It DETECTS a repo's stack/domain and ROUTES each concern to
the best EXISTING specialist already in the ecosystem — GSD agents/skills + thinking-models, the
design skills, the reviewers, the token tools — degrading gracefully when one isn't installed.
This is what makes the harness stack-agnostic: the recipe asks `cmpl craft`, it doesn't hardcode.

Usage: cmpl craft [path] [--json]
"""
import argparse
import glob
import json
import os
import shutil
import sys

HOME = os.path.expanduser("~")


def detect(path):
    """Return the set of stack/domain tags present in `path`."""
    tags = set()

    def has(*names):
        return any(os.path.exists(os.path.join(path, n)) for n in names)

    def globs(*pats):
        return any(glob.glob(os.path.join(path, "**", p), recursive=True) for p in pats)

    pkg = os.path.join(path, "package.json")
    pkgtext = ""
    if os.path.exists(pkg):
        try:
            pkgtext = open(pkg).read()
        except OSError:
            pass
    front_fw = any(s in pkgtext for s in
                   ('"react"', '"vue"', '"svelte"', '"next"', '"@angular', '"solid-js"', '"nuxt"'))
    if front_fw or globs("*.tsx", "*.jsx", "*.vue", "*.svelte") or \
            has("tailwind.config.js", "tailwind.config.ts"):
        tags.add("frontend")
    if has("pyproject.toml", "requirements.txt", "setup.py", "setup.cfg") or globs("*.py"):
        tags.add("python")
    if has("go.mod"):
        tags.add("go")
    if has("Cargo.toml"):
        tags.add("rust")
    if has("pom.xml", "build.gradle", "build.gradle.kts"):
        tags.add("jvm")
    if os.path.exists(pkg) and not front_fw:
        tags.add("node")
    if globs("*.sql") or has("alembic.ini") or os.path.isdir(os.path.join(path, "migrations")):
        tags.add("db")
    return tags


def avail(spec):
    """spec 'kind:name' -> (display_name, installed_bool_or_None). Unknown kinds: display only."""
    if ":" not in spec:
        return spec, None
    kind, name = spec.split(":", 1)
    if kind == "agent":
        return name, os.path.exists(os.path.join(HOME, ".claude", "agents", name + ".md"))
    if kind == "skill":
        n = name.lstrip("/")
        return name, (os.path.isdir(os.path.join(HOME, ".claude", "skills", n))
                      or os.path.exists(os.path.join(HOME, ".claude", "skills", n + ".md")))
    if kind == "bin":
        return name, shutil.which(name) is not None
    if kind == "ref":
        return name, os.path.exists(os.path.join(HOME, ".claude", "gsd-core", name))
    return name, None


# concern -> (applies(tags) -> bool, [tool specs]). Tools are EXISTING ecosystem capabilities.
RULES = [
    ("reason",        lambda t: True,
     ["ref:references/thinking-models-planning.md", "ref:references/thinking-models-execution.md",
      "thinking-models: Pre-Mortem / MECE / Constraint-Analysis / Reversibility / Curse-of-Knowledge"]),
    ("understand",    lambda t: True, ["skill:/gsd-map-codebase", "agent:gsd-codebase-mapper"]),
    ("spec",          lambda t: True, ["skill:/gsd-spec-phase", "skill:/gsd-discuss-phase"]),
    ("plan",          lambda t: True, ["skill:/gsd-plan-phase -> cmpl plan-apply -> Beads"]),
    ("tdd",           lambda t: True, ["skill:/tdd"]),
    ("test",          lambda t: "python" in t, ["pytest"]),
    ("test",          lambda t: "node" in t or "frontend" in t, ["vitest / jest"]),
    ("test",          lambda t: "go" in t, ["go test"]),
    ("test",          lambda t: "rust" in t, ["cargo test"]),
    ("ui-craft",      lambda t: "frontend" in t,
     ["skill:/ui-ux-pro-max", "skill:/impeccable", "skill:/gsd-ui-phase", "skill:/gsd-ui-review"]),
    ("backend-review", lambda t: "python" in t, ["agent:fastapi-reviewer", "agent:python-reviewer"]),
    ("backend-review", lambda t: "db" in t, ["agent:database-reviewer"]),
    ("review",        lambda t: True, ["agent:code-reviewer", "agent:gsd-code-reviewer"]),
    ("readability",   lambda t: True, ["skill:/simplify", "skill:/refactor-clean"]),
    ("security",      lambda t: True,
     ["agent:security-reviewer", "skill:/gsd-secure-phase", "agent:gsd-security-auditor"]),
    ("verify",        lambda t: True,
     ["agent:gsd-verifier -> feeds evidence", "agent:evaluator (default-FAIL, reads acceptance + must_haves)"]),
    ("eval",          lambda t: True, ["skill:/gsd-eval-review", "cmpl bench (quality/$ with-vs-without)"]),
    ("debug",         lambda t: True, ["skill:/gsd-debug", "agent:gsd-debugger"]),
    ("token-in",      lambda t: True, ["bin:rtk (compress tool output -> input tokens)"]),
    ("token-out",     lambda t: True, ["skill:/caveman (terse agent output)"]),
]


def route(tags):
    out = {}
    for concern, applies, tools in RULES:
        if not applies(tags):
            continue
        bucket = out.setdefault(concern, [])
        for spec in tools:
            name, inst = avail(spec)
            bucket.append({"tool": name, "installed": inst})
    return out


def main():
    ap = argparse.ArgumentParser(prog="cmpl craft")
    ap.add_argument("path", nargs="?", default=".")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    path = os.path.abspath(a.path)
    tags = sorted(detect(path))
    concerns = route(set(tags))

    if a.json:
        print(json.dumps({"path": path, "stacks": tags, "concerns": concerns}, indent=2))
        return 0

    print(f"craft router — {path}")
    print(f"  stacks: {', '.join(tags) or '(none detected)'}")
    print("  route each concern to its EXISTING specialist (✓ installed · ○ optional/absent):")
    for concern, tools in concerns.items():
        print(f"  {concern}:")
        for t in tools:
            mark = "✓" if t["installed"] else ("○" if t["installed"] is False else " ")
            print(f"      {mark} {t['tool']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
