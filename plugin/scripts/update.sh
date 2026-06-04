#!/usr/bin/env bash
# completely :: update — after upstreams change, re-check + re-apply + re-sync so no step breaks.
#
# Safe by default: re-runs doctor (refreshes quarantine), notes overlays (they ship with the
# plugin, so they're always "re-applied"), and re-runs the idempotent md→Beads sync. Pass --apply
# to also `git pull` Ralph (the one safe auto-pull). GSD/Beads/claude-mem update via their own
# channels — printed, never auto-run, so an upstream bump is always your explicit call.
# Backend for `cmp update`.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1

echo "== re-check upstream versions (refreshes quarantine) =="
bash "$ROOT/scripts/doctor.sh" | sed 's/^/  /'

if [ "$APPLY" = 1 ] && [ -d "$HOME/.claude/ralph-loop/.git" ]; then
  echo "== pull Ralph =="
  git -C "$HOME/.claude/ralph-loop" pull --ff-only 2>&1 | sed 's/^/  /' || true
fi

echo "== overlays =="
echo "  shipped with the plugin (plugin/overlays/*) — always present, nothing to re-drop."

if [ -d .beads ]; then
  echo "== re-sync md→Beads (idempotent) =="
  bash "$ROOT/scripts/sync.sh" "$PWD" 2>&1 | sed 's/^/  /'
else
  echo "== sync skipped (no .beads here) =="
fi

echo "update: done. Update GSD/Beads/claude-mem via their channels (/gsd:update, beads installer,"
echo "        /plugin update), then re-run 'cmp update' to refresh sync + quarantine."
