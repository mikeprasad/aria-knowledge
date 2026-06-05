#!/bin/sh
# pm-collect.sh — pm-collect.sh scans the projects_list roster into facts.json with correct tiers.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$(cd "$SCRIPT_DIR/../../plugin-claude-code/bin" && pwd)"
. "$SCRIPT_DIR/../pm-helpers.sh"
. "$BIN/pm-lib.sh"
PM_TMP="$(mktemp -d)"; trap 'rm -rf "$PM_TMP"' EXIT
NOW=1780531200   # 2026-06-04T00:00:00Z

make_fixture "$PM_TMP/fresh"  "$(utc_iso $((NOW-86400)))"     # 1 day ago
make_fixture "$PM_TMP/stale"  "$(utc_iso $((NOW-40*86400)))"  # 40d ago, handed off
make_fixture "$PM_TMP/closed" "$(utc_iso $((NOW-40*86400)))"  # 40d ago, wrapped up
printf -- '---\nlastEvent: handoff\nat: 2026-06-04T08:45:00Z\nnextAction: Mike pushes the integration branch\n---\n' > "$PM_TMP/stale/SESSION.md"
printf -- '---\nlastEvent: wrapup\nat: 2026-06-04T08:45:00Z\n---\n' > "$PM_TMP/closed/SESSION.md"

# Config = an aria-knowledge.local.md with projects_enabled + a projects_list roster + pm_* thresholds.
export KT_CONFIG="$PM_TMP/aria-knowledge.local.md"
cat > "$KT_CONFIG" <<EOF
---
knowledge_folder: $PM_TMP/knowledge
projects_enabled: true
projects_list: fresh:$PM_TMP/fresh,stale:$PM_TMP/stale,closed:$PM_TMP/closed
pm_active_max_days: 3
pm_warm_max_days: 9
---
EOF

OUT="$PM_TMP/facts.json"
ARIA_PM_NOW_EPOCH=$NOW sh "$BIN/pm-collect.sh" "$OUT" >/dev/null
assert_eq "fresh -> ACTIVE"            "ACTIVE"  "$(jq -r '.projects[]|select(.name=="fresh").tier' "$OUT")"
assert_eq "stale+handoff -> ACTIVE"    "ACTIVE"  "$(jq -r '.projects[]|select(.name=="stale").tier' "$OUT")"
assert_eq "stale+wrapup -> DORMANT"    "DORMANT" "$(jq -r '.projects[]|select(.name=="closed").tier' "$OUT")"
assert_eq "facts surfaces nextAction"  "Mike pushes the integration branch" "$(jq -r '.projects[]|select(.name=="stale").session_next' "$OUT")"
assert_eq "name is the roster tag"     "fresh"   "$(jq -r '.projects[]|select(.name=="fresh").name' "$OUT")"
pm_summary
exit "$PM_FAIL"
