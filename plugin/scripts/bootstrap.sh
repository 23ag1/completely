#!/usr/bin/env bash
# completely :: setup/bootstrap — verify upstreams, optionally install missing ones, wire a project.
#
# Default: REPORT what's present/missing (safe, no mutation).
#   --install     install MISSING deps via their real channels (consent = this flag).
#   --dry-run     with --install: print the commands instead of running them.
#   --apply       `bd init` the project + run cmpl sync.
#   --project DIR target project (default: cwd).
#
# Dependency reality (honest): completely HARD-depends only on **Beads (bd)**. GSD (planning) and
# claude-mem (memory) are optional composition; **Ralph is NOT used by completely's loop** (the
# overlay supersedes it) — offered only because it's part of the stack. GSD has no verified plugin
# channel (manual install). Backend for `cmpl setup` and the plugin Setup hook.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="."; APPLY=0; INSTALL=0; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:-.}"; shift 2 ;;
    --apply)   APPLY=1; shift ;;
    --install) INSTALL=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) echo "cmpl setup [--project DIR] [--install [--dry-run]] [--apply]"; exit 0 ;;
    *) echo "setup: unknown arg '$1'" >&2; exit 1 ;;
  esac
done

present() {  # echo version if installed, empty if absent (CMP_FAKE_MISSING forces absent, for tests)
  case " ${CMP_FAKE_MISSING:-} " in *" $1 "*) return 0 ;; esac
  case "$1" in
    bd)         command -v bd >/dev/null 2>&1 && bd version 2>/dev/null | head -1 ;;
    gsd)        cat "$HOME/.claude/get-shit-done/VERSION" 2>/dev/null ;;
    ralph)      git -C "$HOME/.claude/ralph-loop" rev-parse --short HEAD 2>/dev/null ;;
    claude-mem) ls "$HOME/.claude/plugins/cache/thedotmack/claude-mem" 2>/dev/null | head -1 ;;
  esac
}
hint() {
  case "$1" in
    bd)         echo "brew install beads | npm i -g @beads/bd | github.com/steveyegge/beads" ;;
    gsd)        echo "manual — TACHES get-shit-done (no verified plugin channel)" ;;
    ralph)      echo "claude plugin install ralph-loop@claude-plugins-official" ;;
    claude-mem) echo "claude plugin install claude-mem@thedotmack" ;;
  esac
}
run() { if [ "$DRY" = 1 ]; then echo "    [dry-run] $*"; else echo "    \$ $*"; eval "$@"; fi; }
install_one() {
  case "$1" in
    bd)
      if command -v brew >/dev/null 2>&1; then run "brew install beads"
      elif command -v npm >/dev/null 2>&1; then run "npm install -g @beads/bd"
      else echo "    bd: install manually → $(hint bd)"; fi ;;
    claude-mem)
      if command -v claude >/dev/null 2>&1; then
        run "claude plugin marketplace add thedotmack/claude-mem"
        run "claude plugin install claude-mem@thedotmack"
      else echo "    claude CLI not found → $(hint claude-mem)"; fi ;;
    ralph)
      if command -v claude >/dev/null 2>&1; then run "claude plugin install ralph-loop@claude-plugins-official"
      else echo "    claude CLI not found → $(hint ralph)"; fi ;;
    gsd) echo "    gsd: $(hint gsd)" ;;
  esac
}

REQUIRED="bd"
OPTIONAL="gsd claude-mem ralph"

echo "== upstreams =="
missing=""
for d in $REQUIRED $OPTIONAL; do
  v="$(present "$d")"
  tag="optional"; case " $REQUIRED " in *" $d "*) tag="required" ;; esac
  if [ -n "$v" ]; then printf "  ok     %-11s %-8s %s\n" "$d" "$tag" "$v"
  else printf "  ABSENT %-11s %-8s → %s\n" "$d" "$tag" "$(hint "$d")"; missing="$missing $d"; fi
done

if [ "$INSTALL" = 1 ]; then
  if [ -z "$missing" ]; then echo "== install: nothing missing =="
  else
    echo "== install missing:$missing =="
    for d in $missing; do echo "  $d:"; install_one "$d"; done
  fi
else
  [ -n "$missing" ] && echo "  → to install the above: cmpl setup --install   (preview: --install --dry-run)"
fi

echo "== doctor (version drift) =="
bash "$ROOT/scripts/doctor.sh" 2>/dev/null | sed 's/^/  /'

echo "== project: $PROJECT =="
cd "$PROJECT" 2>/dev/null || { echo "  no such dir: $PROJECT" >&2; exit 1; }
if [ -d .beads ]; then echo "  beads: present"
elif [ "$APPLY" = 1 ]; then bd init "$(basename "$PWD" | tr -cd 'a-zA-Z0-9-')" >/dev/null 2>&1 && echo "  beads: initialized"
else echo "  beads: ABSENT — pass --apply to run 'bd init'"; fi
if [ -d .beads ] && [ "$APPLY" = 1 ]; then echo "  sync:"; bash "$ROOT/scripts/sync.sh" "$PWD" 2>&1 | sed 's/^/    /'
else echo "  sync: skipped (needs .beads + --apply)"; fi

echo "setup: done. Next → /completely:init (scaffold), then 'cmpl run' to drive bd ready."
