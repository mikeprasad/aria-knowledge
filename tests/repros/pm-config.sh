#!/bin/sh
# pm-config.sh — pm_cfg reads pm_* keys from the aria-knowledge.local.md frontmatter, with defaults.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../pm-helpers.sh"
. "$SCRIPT_DIR/../../plugin-claude-code/bin/pm-lib.sh"
PM_TMP="$(mktemp -d)"; trap 'rm -rf "$PM_TMP"' EXIT

KT_CONFIG="$PM_TMP/aria-knowledge.local.md"
cat > "$KT_CONFIG" <<'EOF'
---
knowledge_folder: /tmp/knowledge
projects_enabled: true
projects_list: alpha:/Users/x/Projects/alpha,beta:/Users/x/Projects/beta/beta-ui
pm_active_max_days: 3
pm_warm_max_days: 9
pm_notify_desktop: true
pm_imessage_handle: me@example.com
---
# body
EOF

assert_eq "pm_cfg reads a set key"        "3"               "$(pm_cfg pm_active_max_days 99)"
assert_eq "pm_cfg reads warm"             "9"               "$(pm_cfg pm_warm_max_days 99)"
assert_eq "pm_cfg reads a string key"     "me@example.com"  "$(pm_cfg pm_imessage_handle '')"
assert_eq "pm_cfg falls back to default"  "30"              "$(pm_cfg pm_dormant_nudge_days 30)"
assert_eq "pm_cfg empty default ok"       ""                "$(pm_cfg pm_missing '')"
pm_summary
exit "$PM_FAIL"
