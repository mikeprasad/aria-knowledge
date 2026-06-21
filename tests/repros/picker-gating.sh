#!/bin/sh
# tests/repros/picker-gating.sh — SessionStart picker block gating (spec 2026-06-06)
# Verifies: emits "ARIA Project Picker" + menu when both gates on; silent when flag off.
set -e
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DIR/plugin-claude-code/bin/session-start-check.sh"

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
out=$(cd "$TMP" && KT_CONFIG="$CFG" sh "$HOOK" 2>/dev/null || true)
echo "$out" | grep -q "ARIA Project Picker" || { echo "FAIL: picker absent when enabled"; echo "--out--"; echo "$out"; rm -rf "$TMP"; exit 1; }
echo "$out" | grep -q "alpha (Alpha App), beta" || { echo "FAIL: menu string missing/incorrect"; echo "$out"; rm -rf "$TMP"; exit 1; }

# Disable the flag -> picker must be silent.
sed 's/session_start_project_picker: true/session_start_project_picker: false/' "$CFG" > "$CFG.off"
out2=$(cd "$TMP" && KT_CONFIG="$CFG.off" sh "$HOOK" 2>/dev/null || true)
echo "$out2" | grep -q "ARIA Project Picker" && { echo "FAIL: picker emitted while disabled"; rm -rf "$TMP"; exit 1; }

rm -rf "$TMP"
echo "picker-gating: PASS"
