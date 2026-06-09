# shellcheck shell=sh
# test-aria-assist.sh — .aria-assist.json overlay: helper + script integration
BIN="$(cd "$(dirname "$0")/../bin" && pwd)"

# --- apm_write_assist_status: create + deep-merge sections, preserve siblings/fields ---
AS_KF="$APM_TMP/as/knowledge"
( export KT_KNOWLEDGE_FOLDER="$AS_KF"; export KT_CONFIG="$APM_TMP/as/absent.md"
  . "$BIN/pm-lib.sh"
  apm_write_assist_status schedule '{"enabled":true,"time":"08:30","label":"com.aria.morning"}'
  apm_write_assist_status lastRun  '{"digest":"2026-06-09","result":"ok"}'
  apm_write_assist_status schedule '{"enabled":false}' )   # deep-merge: flip enabled, keep time/label
ASF="$AS_KF/pm-reviews/.aria-assist.json"
assert_eq "assist: file created"     "1"          "$( [ -f "$ASF" ] && echo 1 || echo 0 )"
assert_eq "assist: enabled flipped"  "false"      "$(jq -r '.schedule.enabled' "$ASF" 2>/dev/null)"
assert_eq "assist: time preserved"   "08:30"      "$(jq -r '.schedule.time' "$ASF" 2>/dev/null)"
assert_eq "assist: label preserved"  "com.aria.morning" "$(jq -r '.schedule.label' "$ASF" 2>/dev/null)"
assert_eq "assist: sibling lastRun"  "2026-06-09" "$(jq -r '.lastRun.digest' "$ASF" 2>/dev/null)"
