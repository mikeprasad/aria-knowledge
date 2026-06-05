#!/bin/sh
set -eu
# pm-collect.sh OUT_FILE -> read-only scan of the projects_list roster -> facts.json
# Config source: ~/.claude/aria-knowledge.local.md (via config.sh). Roster: projects_list (tag:path).
# Thresholds: pm_active_max_days / pm_warm_max_days (via pm_cfg). Honors ARIA_PM_NOW_EPOCH for tests.
BIN="$(cd "$(dirname "$0")" && pwd)"
. "$BIN/config.sh"      # sets KT_CONFIG, KT_PROJECTS_LIST, KT_PROJECTS_ENABLED, KT_CONFIGURED
. "$BIN/pm-lib.sh"      # apm_* helpers + pm_cfg
OUT="${1:?out path required}"
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

if [ "$KT_PROJECTS_ENABLED" != "true" ] || [ -z "$KT_PROJECTS_LIST" ]; then
  printf '{"generated_at":"%s","projects":[]}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUT"
  echo "wrote $OUT (0 projects — projects_enabled=$KT_PROJECTS_ENABLED)"
  exit 0
fi

AMAX=$(pm_cfg pm_active_max_days 3)
WMAX=$(pm_cfg pm_warm_max_days 9)

_items=""; _n=0
_old_ifs="$IFS"; IFS=','
for _entry in $KT_PROJECTS_LIST; do
  [ -z "$_entry" ] && continue
  case "$_entry" in *:*) ;; *) continue ;; esac   # skip malformed (no colon)
  name="${_entry%%:*}"
  rawp="${_entry#*:}"
  [ -z "$rawp" ] && continue
  path=$(apm_expand_tilde "$rawp")
  rec=$(apm_recency_days "$path")
  st=$(apm_session_state "$path")
  nx=$(apm_session_next "$path")
  tier=$(apm_tier "$rec" "$st" "" "$AMAX" "$WMAX")
  obj=$(jq -n -c --arg name "$name" --arg path "$path" \
        --arg tier "$tier" --arg state "$st" --arg next "$nx" --arg rec "$rec" \
        '{name:$name,path:$path,tier:$tier,session_state:$state,session_next:$next,
          recency_days:(if $rec=="" then null else ($rec|tonumber) end)}')
  _items="${_items}${obj}
"
  _n=$((_n+1))
done
IFS="$_old_ifs"

printf '%s' "$_items" | jq -s --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{generated_at:$at, projects:.}' > "$OUT"
printf 'wrote %s (%s projects)\n' "$OUT" "$_n"
