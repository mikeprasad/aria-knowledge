#!/bin/sh
# pm-notify.sh — desktop + best-effort iMessage, driven by pm_* config keys; --dry-run emits the osascript.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$(cd "$SCRIPT_DIR/../../plugin-claude-code/bin" && pwd)"
. "$SCRIPT_DIR/../pm-helpers.sh"
PM_TMP="$(mktemp -d)"; trap 'rm -rf "$PM_TMP"' EXIT

export KT_CONFIG="$PM_TMP/aria-knowledge.local.md"
cat > "$KT_CONFIG" <<'EOF'
---
knowledge_folder: /tmp/knowledge
pm_notify_desktop: true
pm_notify_imessage: true
pm_imessage_handle: me@example.com
---
EOF
out=$(sh "$BIN/pm-notify.sh" "Morning review ready" "3 active, 2 ideas" --dry-run)
case "$out" in *"display notification"*) ok=1 ;; *) ok=0 ;; esac
assert_eq "dry-run emits desktop notification" "1" "$ok"
case "$out" in *"Messages"*"me@example.com"*) ok=1 ;; *) ok=0 ;; esac
assert_eq "dry-run emits iMessage to handle" "1" "$ok"

cat > "$KT_CONFIG" <<'EOF'
---
knowledge_folder: /tmp/knowledge
pm_notify_desktop: true
pm_notify_imessage: false
pm_imessage_handle: me@example.com
---
EOF
out=$(sh "$BIN/pm-notify.sh" "t" "b" --dry-run)
case "$out" in *"Messages"*) ok=0 ;; *) ok=1 ;; esac
assert_eq "imessage off -> no Messages line" "1" "$ok"
pm_summary
exit "$PM_FAIL"
