#!/usr/bin/env bash
# completely :: sync — idempotent migration of markdown task state -> Beads.
#
# Backend for `cmp sync` and the `/completely:sync` skill. Upserts each markdown task
# into Beads keyed by a stable source_ref (label `src-<sha1[:8]>` + metadata.source_ref),
# so it is SAFE TO RE-RUN — after an upstream update it reconciles instead of duplicating.
# That is what makes "pull updates, no step breaks" hold (design §11).
#
# v1 scope (explicit, not a silent stub): Ralph-style `IMPLEMENTATION_PLAN.md` and any extra
# markdown checkbox lists passed as args. GSD `*-PLAN.md` (requirements/must_haves/waves) is
# handled by the richer GSD->Beads emitter, tracked separately — NOT silently dropped here.
set -uo pipefail

PROJ="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
# first non-flag arg may override the project dir
case "${1:-}" in -*|"") ;; *) [ -d "$1" ] && { PROJ="$1"; shift; } ;; esac
cd "$PROJ" || { echo "completely/sync: no dir $PROJ" >&2; exit 1; }
command -v bd >/dev/null 2>&1 || { echo "completely/sync: bd (beads) not installed" >&2; exit 1; }
[ -d .beads ] || { echo "completely/sync: no .beads in $PROJ — run 'bd init' first" >&2; exit 1; }

hashref() { printf '%s' "$1" | sha1sum | cut -c1-8; }

# snapshot existing src-* label -> issue id, across ALL statuses (so closed tasks still match)
declare -A EXIST
while IFS=$'\t' read -r id lab; do
  [ -n "$lab" ] && EXIST["$lab"]="$id"
done < <(bd list --all --json 2>/dev/null | python3 -c '
import json,sys
try: data=json.load(sys.stdin)
except Exception: data=[]
if isinstance(data,dict): data=data.get("issues",data.get("data",[]))
for it in data or []:
    for l in it.get("labels",[]) or []:
        if isinstance(l,str) and l.startswith("src-"):
            print(it.get("id"), l, sep="\t")
')

status_of() { # status_of <id> -> stored status string
  bd show "$1" --json 2>/dev/null | python3 -c '
import json,sys
try:
    d=json.load(sys.stdin); d=d[0] if isinstance(d,list) else d
    print(d.get("status",""))
except Exception: print("")'
}

created=0; updated=0; unchanged=0
upsert() { # upsert <source_ref> <open|closed> <title>
  local ref="$1" want="$2" title="$3"
  local lab="src-$(hashref "$ref")"
  local id="${EXIST[$lab]:-}"
  if [ -z "$id" ]; then
    id=$(bd create "$title" -t task -l "$lab,completely-sync" \
          --metadata "{\"source_ref\":\"$ref\"}" --json 2>/dev/null \
          | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])' 2>/dev/null)
    [ -z "$id" ] && { echo "  ! create failed: $title" >&2; return; }
    EXIST["$lab"]="$id"
    [ "$want" = closed ] && bd close "$id" >/dev/null 2>&1
    created=$((created+1)); printf '  + %s  %s\n' "$id" "$title"
  else
    local cur; cur=$(status_of "$id")
    if [ "$want" = closed ] && [ "$cur" != closed ]; then
      bd close "$id" >/dev/null 2>&1; updated=$((updated+1)); printf '  ~ %s  closed\n' "$id"
    elif [ "$want" = open ] && [ "$cur" = closed ]; then
      bd reopen "$id" >/dev/null 2>&1; updated=$((updated+1)); printf '  ~ %s  reopened\n' "$id"
    else
      unchanged=$((unchanged+1))
    fi
  fi
}

# files to scan: Ralph IMPLEMENTATION_PLAN.md (+ nested) plus any passed explicitly
FILES=()
for f in IMPLEMENTATION_PLAN.md ./*/IMPLEMENTATION_PLAN.md "$@"; do
  [ -f "$f" ] && FILES+=("$f")
done
[ ${#FILES[@]} -eq 0 ] && { echo "completely/sync: no IMPLEMENTATION_PLAN.md (or files given) under $PROJ"; exit 0; }

for f in "${FILES[@]}"; do
  echo "scan: $f"
  n=0
  while IFS= read -r line; do
    # match markdown task checkboxes only: "- [ ] text" / "- [x] text" (not links)
    if [[ "$line" =~ ^-[[:space:]]\[([[:space:]xX])\][[:space:]](.+) ]]; then
      n=$((n+1))
      local_mark="${BASH_REMATCH[1]}"; text="${BASH_REMATCH[2]}"
      want=open; [[ "$local_mark" =~ [xX] ]] && want=closed
      upsert "md:$f#$n" "$want" "$text"
    fi
  done < "$f"
done

echo "completely/sync: +${created} created, ~${updated} reconciled, =${unchanged} unchanged"
