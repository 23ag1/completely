#!/usr/bin/env bash
# completely :: setup/bootstrap — verify all upstreams and wire a project onto the Beads spine.
#
# Safe by default: REPORTS upstream presence/versions, runs doctor, and tells you what's missing
# with the install command. Pass --apply to actually `bd init` the project and run `cmp sync`.
# It never auto-installs upstream tools or mutates your global setup — installing GSD/Ralph/etc.
# stays an explicit, your-call step (printed hints), so an upstream change can't break you silently.
#
# Backend for `cmp setup` and the plugin Setup hook.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="."; APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:-.}"; shift 2 ;;
    --apply)   APPLY=1; shift ;;
    -h|--help) echo "cmp setup [--project DIR] [--apply]"; exit 0 ;;
    *) echo "setup: unknown arg '$1'" >&2; exit 1 ;;
  esac
done

echo "== upstreams =="
chk() { # chk <name> <version-or-empty> <install-hint>
  if [ -n "$2" ]; then printf "  ok     %-11s %s\n" "$1" "$2"
  else printf "  ABSENT %-11s → %s\n" "$1" "$3"; fi
}
chk bd         "$(command -v bd >/dev/null 2>&1 && bd version 2>/dev/null | head -1)" "github.com/steveyegge/beads (install.sh)"
chk gsd        "$(cat "$HOME/.claude/get-shit-done/VERSION" 2>/dev/null)"              "claude plugin install gsd"
chk ralph      "$(git -C "$HOME/.claude/ralph-loop" rev-parse --short HEAD 2>/dev/null)" "claude plugin install ralph-loop"
chk claude-mem "$(ls "$HOME/.claude/plugins/cache/thedotmack/claude-mem" 2>/dev/null | head -1)" "claude plugin install claude-mem@thedotmack"

echo "== doctor (version drift vs tested lock) =="
bash "$ROOT/scripts/doctor.sh" 2>/dev/null | sed 's/^/  /'

echo "== project: $PROJECT =="
cd "$PROJECT" 2>/dev/null || { echo "  no such dir: $PROJECT" >&2; exit 1; }
if [ -d .beads ]; then
  echo "  beads: present"
elif [ "$APPLY" = 1 ]; then
  bd init "$(basename "$PWD" | tr -cd 'a-zA-Z0-9-')" >/dev/null 2>&1 && echo "  beads: initialized"
else
  echo "  beads: ABSENT — pass --apply to run 'bd init', or run it yourself"
fi
if [ -d .beads ] && [ "$APPLY" = 1 ]; then
  echo "  sync:"; bash "$ROOT/scripts/sync.sh" "$PWD" 2>&1 | sed 's/^/    /'
else
  echo "  sync: skipped (needs .beads + --apply)"
fi

echo "setup: done. Next → /completely:init (scaffold thin layer), then 'cmp run' to drive bd ready."
