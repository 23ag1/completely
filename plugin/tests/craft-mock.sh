#!/usr/bin/env bash
# completely :: craft-mock — assert the craft router DETECTS stack and ROUTES to existing tools
# (no reimplementation). Stack-agnostic: frontend repo gets UI craft, python repo does NOT.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; CMPL="$ROOT/bin/cmpl"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  PASS $1"; }
no(){ fail=$((fail+1)); echo "  FAIL $1"; }

# --- frontend repo (react) ---
F="$(mktemp -d /tmp/craftfe.XXXXXX)"; printf '{"dependencies":{"react":"^18"}}' > "$F/package.json"
JF="$(bash "$CMPL" craft "$F" --json 2>/dev/null)"
echo "$JF" | grep -qi 'frontend'       && ok "detects frontend stack"        || no "detect frontend"
echo "$JF" | grep -qi 'ui-ux-pro-max'  && ok "frontend -> /ui-ux-pro-max"    || no "frontend ui craft"

# --- python backend repo ---
P="$(mktemp -d /tmp/craftpy.XXXXXX)"; printf '[project]\nname = "x"\n' > "$P/pyproject.toml"
JP="$(bash "$CMPL" craft "$P" --json 2>/dev/null)"
echo "$JP" | grep -qi 'python'         && ok "detects python stack"          || no "detect python"
echo "$JP" | grep -qi 'pytest'         && ok "python -> pytest"              || no "python test routing"
if echo "$JP" | grep -qi 'ui-ux-pro-max'; then no "python repo must NOT route UI craft"; else ok "python repo: no UI craft (stack-aware)"; fi

# --- always-on concerns regardless of stack ---
echo "$JP" | grep -qi 'thinking-models' && ok "always routes GSD thinking-models" || no "thinking-models routed"
echo "$JP" | grep -qi 'evaluator'       && ok "verify routes default-FAIL evaluator" || no "evaluator routed"
echo "$JP" | grep -qi 'security'        && ok "always routes security review"   || no "security routed"

echo "craft-mock: $pass passed, $fail failed"
[ "$fail" = 0 ]
