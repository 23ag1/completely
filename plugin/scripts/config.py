#!/usr/bin/env python3
"""completely config — resolve quality checks from completely.toml, or auto-detect per stack.

Usage:
  config.py checks <dir>   -> TSV lines: name<TAB>cwd<TAB>command   (for `cmpl check`)
  config.py show <dir>     -> the resolved config as JSON (for debugging)

A project customizes the pipeline by editing completely.toml; with no config we detect a
frontend (package.json) and/or backend (pyproject.toml), including common subdirs, so the same
command works for front, back, or a monorepo with both — one adaptive system, not two.
"""
import json
import os
import sys

try:
    import tomllib
except Exception:  # pragma: no cover - py<3.11
    tomllib = None

FRONT_SUBDIRS = (".", "frontend", "web", "app", "client")
BACK_SUBDIRS = (".", "backend", "api", "server")


def load(d):
    for name in ("completely.toml", ".completely.toml"):
        p = os.path.join(d, name)
        if os.path.isfile(p) and tomllib:
            with open(p, "rb") as f:
                return tomllib.load(f)
    return {}


def _first_with(d, subdirs, marker):
    for sub in subdirs:
        if os.path.isfile(os.path.join(d, sub, marker)):
            return os.path.normpath(os.path.join(d, sub))
    return None


def detect(d):
    checks = []
    front = _first_with(d, FRONT_SUBDIRS, "package.json")
    if front:
        checks += [
            ("eslint", front, "npx --no-install eslint ."),
            ("tsc", front, "npx --no-install tsc --noEmit"),
            ("vitest", front, "npx --no-install vitest run"),
        ]
    back = _first_with(d, BACK_SUBDIRS, "pyproject.toml")
    if back:
        ruff = os.path.join(back, ".venv/bin/ruff")
        mypy = os.path.join(back, ".venv/bin/mypy")
        pytest = os.path.join(back, ".venv/bin/pytest")
        ruff = ruff if os.path.exists(ruff) else "ruff"
        mypy = mypy if os.path.exists(mypy) else "mypy"
        pytest = pytest if os.path.exists(pytest) else "pytest"
        checks += [
            ("ruff", back, "%s check ." % ruff),
            ("mypy", back, "%s ." % mypy),
            ("pytest", back, "%s -q" % pytest),
        ]
    return checks


def resolve_checks(d):
    cfg = load(d)
    cc = cfg.get("check", {})
    cmds = cc.get("commands") if isinstance(cc, dict) else None
    if cmds:
        out = []
        for item in cmds:
            if not isinstance(item, dict) or "cmd" not in item:
                continue
            cwd = os.path.normpath(os.path.join(d, item.get("cwd", ".")))
            out.append((item.get("name", "check"), cwd, item["cmd"]))
        return out
    return detect(d)


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "checks":
        d = os.path.abspath(sys.argv[2])
        for name, cwd, cmd in resolve_checks(d):
            print("%s\t%s\t%s" % (name, cwd, cmd))
        return 0
    if len(sys.argv) >= 3 and sys.argv[1] == "show":
        print(json.dumps(load(os.path.abspath(sys.argv[2])), indent=2))
        return 0
    print("usage: config.py checks|show <dir>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
