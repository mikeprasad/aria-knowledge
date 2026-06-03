#!/bin/sh
# post-plan-prospect-check.sh — afterFileEdit hook (Cursor port of PostToolUse:Write).
# When a plan file is written and auto_prospect is nudge|run, surface /prospect instruction.

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

[ "$KT_CONFIGURED" = "true" ] || exit 0
case "$KT_AUTO_PROSPECT" in nudge|run) ;; *) exit 0 ;; esac

FILE_PATH=$(echo "$INPUT" | grep -o '"filePath":"[^"]*"' | head -1 | sed 's/"filePath":"//;s/"//')
[ -z "$FILE_PATH" ] && FILE_PATH=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"//')
[ -n "$FILE_PATH" ] || exit 0

case "$FILE_PATH" in
  */docs/plans/*.md|*/docs/superpowers/plans/*.md) ;;
  *) exit 0 ;;
esac

if [ "$KT_AUTO_PROSPECT" = "run" ]; then
  MSG="AUTO-PROSPECT (run): a plan was written at ${FILE_PATH}. Run /prospect file ${FILE_PATH} inline now, before any execution."
else
  MSG="AUTO-PROSPECT (nudge): a plan was written at ${FILE_PATH}. Offer to run /prospect file ${FILE_PATH} before execution and ask the user (do not auto-run)."
fi
MSG_ESCAPED=$(kt_json_escape "$MSG")
printf '{"agentMessage":"%s"}\n' "$MSG_ESCAPED"
