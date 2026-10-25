#!/bin/sh
# tests/repros/picker-gating.sh — SessionStart picker block gating (spec 2026-06-06)
# Verifies: emits "ARIA Project Picker" + menu when both gates on; silent when flag off.
set -e
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DIR/plugin-claude-code/scripts/session-start-check.sh"

TMP=$(mktemp -d)
KN="$TMP/kn"
mkdir -p "$KN/logs"
# Seed an audit log so the hook does NOT take the first-run welcome early-exit (line ~79-85),
# which would return before reaching the picker block.
printf -- '- **Date:** 2026-06-06 (seeded for test)\n' > "$KN/logs/knowledge-audit-log.md"
CFG="$TMP/aria-knowledge.local.md"
cat > "$CFG" <<EOF
---
knowledge_folder: $KN
knowledge_root: $KN
configured: true
projects_enabled: true
session_start_project_picker: true
projects_list: alpha:alpha,beta:beta
projects_labels: alpha:Alpha App
pm_projects_root: ~/Projects
active_knowledge_surfacing: false
---
EOF

# Run from a non-project dir so the picker is not skipped by a CWD match.
out=$(cd "$TMP" && HOME="$TMP" KT_CONFIG="$CFG" sh "$HOOK" </dev/null 2>/dev/null || true)
# ⛔ RE-POINTED 2026-10-25: the picker used to be banner text, which never reaches the model. It is
# now a value line in the decoded model context; the behaviour lives in the digest.
ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
printf '%s' "$ctx" | grep -qF "ARIA PROJECTS — menu: alpha (Alpha App), beta" || { echo "FAIL: picker value absent or wrong when enabled"; echo "--ctx--"; echo "$ctx" | grep -n 'ARIA ' ; rm -rf "$TMP"; exit 1; }
printf '%s' "$out" | jq -r '.systemMessage // ""' 2>/dev/null | grep -q "Project Picker" && { echo "FAIL: picker text still in the banner"; rm -rf "$TMP"; exit 1; }
# Not on compact: the offer belongs to the opening message.
outc=$(cd "$TMP" && printf '{"session_id":"pg","source":"compact"}' | HOME="$TMP" KT_CONFIG="$CFG" sh "$HOOK" 2>/dev/null || true)
printf '%s' "$outc" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null | grep -q "ARIA PROJECTS" && { echo "FAIL: picker offered again after compaction"; rm -rf "$TMP"; exit 1; }

# Disable the flag -> picker must be silent.
sed 's/session_start_project_picker: true/session_start_project_picker: false/' "$CFG" > "$CFG.off"
out2=$(cd "$TMP" && HOME="$TMP" KT_CONFIG="$CFG.off" sh "$HOOK" </dev/null 2>/dev/null || true)
printf '%s' "$out2" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null | grep -q "ARIA PROJECTS" && { echo "FAIL: picker emitted while disabled"; rm -rf "$TMP"; exit 1; }

rm -rf "$TMP"
echo "picker-gating: PASS"
