#!/usr/bin/env bash
# completely :: doctor — upstream version drift + overlay quarantine.
#
# Reports installed vs tested (versions.lock). On drift it QUARANTINES the completely components
# that depend on the drifted tool (writes a marker); those commands then refuse to run without
# --force / CMP_FORCE=1, so an upstream change can't silently corrupt a step. Drift = handled,
# not silent. Backend for `cmpl doctor`.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="${CMP_LOCK:-$ROOT/versions.lock}"
STATE="${CMP_STATE:-$ROOT}"
QFILE="$STATE/quarantine.txt"
[ -f "$LOCK" ] || { echo "doctor: no versions.lock (run install)"; exit 0; }

ver(){ case "$1" in
  bd)         bd version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
  gsd)        cat "$HOME/.claude/gsd-core/VERSION" 2>/dev/null ;;
  ralph)      git -C "$HOME/.claude/ralph-loop" rev-parse --short HEAD 2>/dev/null ;;
  claude-mem) ls "$HOME/.claude/plugins/cache/thedotmack/claude-mem" 2>/dev/null | sort -V | tail -1 ;;
  rtk)        command -v rtk >/dev/null 2>&1 && rtk --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
esac; }
affected(){ case "$1" in   # which completely components depend on this upstream
  gsd)        echo "emit (GSD PLAN.md parser)";;
  bd)         echo "sync, emit, lint, run (bd JSON fields)";;
  ralph)      echo "run unattended overlay";;
  claude-mem) echo "memory recall only";;
  # rtk affects ONLY the rtk=on bench arm — gate cmds (cmpl check / cmpl lint) are excluded from rtk
  # wrapping by construction, so drift here never quarantines the harness's gates. Narrow on purpose.
  rtk)        echo "cmpl bench --rtk on (token-economy lever; gate cmds excluded)";;
esac; }

ok=0; warn=0; DRIFT=""
echo "completely doctor — upstream versions"
while IFS='=' read -r tool tested; do
  [ -z "$tool" ] && continue
  case "$tool" in \#*) continue;; esac
  cur="$(ver "$tool")"; cur="${cur:-<absent>}"
  if [ "$cur" = "$tested" ]; then
    echo "  ok    $tool: $cur"; ok=$((ok+1))
  else
    echo "  DRIFT $tool: installed=$cur tested=$tested → quarantines: $(affected "$tool")"
    warn=$((warn+1)); DRIFT="$DRIFT $tool"
  fi
done < "$LOCK"

DRIFT="$(echo "$DRIFT" | xargs 2>/dev/null || true)"
if [ -n "$DRIFT" ]; then
  printf '%s\n' $DRIFT > "$QFILE"
  echo "doctor: $ok ok, $warn drift — quarantined: $DRIFT (affected commands need --force until re-tested)"
  exit 1   # meaningful for automation: drift present (quarantine written); 0 = no drift
else
  rm -f "$QFILE" 2>/dev/null || true
  echo "doctor: $ok ok, 0 drift — no quarantine"
fi
exit 0
