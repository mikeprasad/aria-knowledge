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

# --- pm-schedule.sh writes schedule status on install + flips enabled on --uninstall ---
SC="$APM_TMP/sched"; mkdir -p "$SC/home/Library/LaunchAgents" "$SC/knowledge"
printf -- '---\nknowledge_folder: %s/knowledge\npm_schedule_time: 08:30\n---\n' "$SC" > "$SC/cfg.md"
STUB="$SC/stub"; mkdir -p "$STUB"
for b in launchctl plutil osascript; do printf '#!/bin/sh\nexit 0\n' > "$STUB/$b"; chmod +x "$STUB/$b"; done
SCF="$SC/knowledge/pm-reviews/.aria-assist.json"
( export HOME="$SC/home"; export KT_CONFIG="$SC/cfg.md"; PATH="$STUB:$PATH"; sh "$BIN/pm-schedule.sh" ) >/dev/null 2>&1
assert_eq "schedule: install enabled" "true"  "$(jq -r '.schedule.enabled' "$SCF" 2>/dev/null)"
assert_eq "schedule: install time"    "08:30" "$(jq -r '.schedule.time' "$SCF" 2>/dev/null)"
( export HOME="$SC/home"; export KT_CONFIG="$SC/cfg.md"; PATH="$STUB:$PATH"; sh "$BIN/pm-schedule.sh" --uninstall ) >/dev/null 2>&1
assert_eq "schedule: uninstall flips" "false" "$(jq -r '.schedule.enabled' "$SCF" 2>/dev/null)"
assert_eq "schedule: time preserved"  "08:30" "$(jq -r '.schedule.time' "$SCF" 2>/dev/null)"

# --- pm-morning-run.sh writes a lastRun block (claude stubbed, hermetic) ---
MR="$APM_TMP/mrun"; mkdir -p "$MR/home/.claude/logs" "$MR/knowledge/pm-reviews"
printf -- '---\nknowledge_folder: %s/knowledge\npm_light_writes: false\n---\n' "$MR" > "$MR/cfg.md"
printf '2 active\n' > "$MR/knowledge/pm-reviews/.last-summary"
MSTUB="$MR/stub"; mkdir -p "$MSTUB"
for b in claude osascript; do printf '#!/bin/sh\nexit 0\n' > "$MSTUB/$b"; chmod +x "$MSTUB/$b"; done
MRF="$MR/knowledge/pm-reviews/.aria-assist.json"
( export HOME="$MR/home"; export KT_CONFIG="$MR/cfg.md"; PATH="$MSTUB:$PATH"; sh "$BIN/pm-morning-run.sh" ) >/dev/null 2>&1
assert_eq "morning: lastRun result"  "ok" "$(jq -r '.lastRun.result' "$MRF" 2>/dev/null)"
assert_eq "morning: lastRun digest"  "1"  "$( [ -n "$(jq -r '.lastRun.digest // empty' "$MRF" 2>/dev/null)" ] && echo 1 || echo 0 )"
