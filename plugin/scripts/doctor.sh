#!/usr/bin/env bash
# completely :: doctor — report upstream tool versions vs the tested lock, flag drift (warn, not fail).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$ROOT/versions.lock"
[ -f "$LOCK" ] || { echo "doctor: no versions.lock (run install)"; exit 0; }
ver(){ case "$1" in
  bd) bd version 2>/dev/null | head -1 ;;
  gsd) cat "$HOME/.claude/get-shit-done/VERSION" 2>/dev/null ;;
  ralph) git -C "$HOME/.claude/ralph-loop" rev-parse --short HEAD 2>/dev/null ;;
  claude-mem) ls "$HOME/.claude/plugins/cache/thedotmack/claude-mem" 2>/dev/null | head -1 ;;
esac; }
ok=0; warn=0
echo "completely doctor — upstream versions"
while IFS='=' read -r tool tested; do
  [ -z "$tool" ] && continue
  case "$tool" in \#*) continue;; esac
  cur="$(ver "$tool")"; cur="${cur:-<absent>}"
  if [ "$cur" = "$tested" ]; then echo "  ok    $tool: $cur"; ok=$((ok+1))
  else echo "  DRIFT $tool: installed=$cur tested=$tested -> review $tool overlays before relying"; warn=$((warn+1)); fi
done < "$LOCK"
echo "doctor: $ok ok, $warn drift"
exit 0
