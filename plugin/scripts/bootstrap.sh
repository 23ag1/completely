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
# overlay supersedes it) — offered only because it's part of the stack. GSD installs via npx
# (open-gsd/gsd-core, --claude --global). Backend for `cmpl setup` and the plugin Setup hook.
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
    bd)         command -v bd >/dev/null 2>&1 && bd version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
    gsd)        cat "$HOME/.claude/gsd-core/VERSION" 2>/dev/null ;;
    ralph)      git -C "$HOME/.claude/ralph-loop" rev-parse --short HEAD 2>/dev/null ;;
    claude-mem) ls "$HOME/.claude/plugins/cache/thedotmack/claude-mem" 2>/dev/null | sort -V | tail -1 ;;
    rtk)        command -v rtk >/dev/null 2>&1 && rtk --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 ;;
  esac
}
hint() {
  case "$1" in
    bd)         echo "brew install beads | npm i -g @beads/bd | github.com/gastownhall/beads" ;;
    gsd)        echo "npx --yes @opengsd/gsd-core@latest --claude --global  (open-gsd, npm)" ;;
    ralph)      echo "claude plugin install ralph-loop@claude-plugins-official" ;;
    claude-mem) echo "claude plugin install claude-mem@thedotmack" ;;
    rtk)        echo "claude plugin install rtk@claude-plugins-official  (OPTIONAL token-economy lever; local, no key)" ;;
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
    gsd)
      if command -v npx >/dev/null 2>&1; then run "npx --yes @opengsd/gsd-core@latest --claude --global"
      else echo "    npx (node) not found → $(hint gsd)"; fi ;;
    rtk)
      # rtk is an OPTIONAL token-economy lever (input-side: compresses tool output before the agent
      # reads it). Local, no key. After install we run `rtk init` in the target project so its
      # per-project config exists — guarded by `command -v rtk`, so it's a no-op if rtk isn't on PATH
      # after install (e.g. plugin CLI not yet linked). NEVER touches `cmpl check` / `cmpl lint`
      # invocations — those bypass rtk by construction (see token-economy.md "gate cmds excluded").
      if command -v claude >/dev/null 2>&1; then run "claude plugin install rtk@claude-plugins-official"
      else echo "    claude CLI not found → $(hint rtk)"; fi
      if command -v rtk >/dev/null 2>&1 && [ "$DRY" != 1 ]; then
        ( cd "$PROJECT" 2>/dev/null && rtk init >/dev/null 2>&1 ) \
          && echo "    rtk: per-project config initialized in $PROJECT" \
          || echo "    rtk: 'rtk init' skipped (project=$PROJECT — run manually if needed)"
      fi ;;
  esac
}

REQUIRED="bd"
# rtk joins the OPTIONAL set — installing it never changes the harness contract; gate cmds
# (cmpl check/lint) are excluded from rtk wrapping by construction so absence is a no-op.
OPTIONAL="gsd claude-mem ralph rtk"

# ensure completely AUTO-UPDATES for this user: register its marketplace with autoUpdate=true
# (third-party marketplaces default to auto-update OFF, so we opt in explicitly via the NATIVE
# mechanism — no custom self-update hook). Idempotent; only writes when a change is needed.
SETTINGS="$HOME/.claude/settings.json"
if command -v python3 >/dev/null 2>&1; then
  python3 - "$SETTINGS" <<'PY' || true
import json, os, sys
p = sys.argv[1]
try:
    s = json.load(open(p)) if os.path.exists(p) else {}
except Exception:
    s = {}
ekm = s.setdefault("extraKnownMarketplaces", {})
entry = ekm.get("completely") or {}
changed = False
if not entry.get("source"):
    entry["source"] = {"source": "github", "repo": "23ag1/completely"}; changed = True
if entry.get("autoUpdate") is not True:
    entry["autoUpdate"] = True; changed = True
if changed:
    ekm["completely"] = entry
    json.dump(s, open(p, "w"), indent=2)
    print("== completely: auto-update ENABLED (extraKnownMarketplaces.completely.autoUpdate=true) ==")
PY
fi

# ensure the FULL cmpl is on PATH (the plugin doesn't add bin/ to PATH itself — this is the fix
# for the "cmpl is only the minimal sync|doctor build" bug). Runs on the Setup hook + cmpl setup.
FULL_CMPL="$ROOT/bin/cmpl"
if [ -f "$FULL_CMPL" ]; then
  BINDIR="${HARNESS_BIN:-$HOME/.local/bin}"; mkdir -p "$BINDIR"
  if ! grep -q "$FULL_CMPL" "$BINDIR/cmpl" 2>/dev/null; then
    printf '#!/usr/bin/env bash\nexec bash "%s" "$@"\n' "$FULL_CMPL" > "$BINDIR/cmpl" && chmod +x "$BINDIR/cmpl"
    echo "== cmpl: full CLI linked -> $BINDIR/cmpl (ensure $BINDIR is on PATH) =="
  fi
fi

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
