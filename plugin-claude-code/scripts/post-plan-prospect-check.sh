#!/bin/sh
# post-plan-prospect-check.sh — PostToolUse hook for Write.
# When a plan file is written and auto_prospect is nudge|run, surface an
# instruction to /prospect the plan. Decision B (2026-06-01): docs/specs/
# is intentionally NOT a trigger path (a spec is pre-plan).

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

# Gate 1: configured + enabled
[ "$KT_CONFIGURED" = "true" ] || exit 0
case "$KT_AUTO_PROSPECT" in nudge|run) ;; *) exit 0 ;; esac

# Extract the written file path
FILE_PATH=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"//')
[ -n "$FILE_PATH" ] || exit 0

# Gate 2: plan-path glob (decision B — specs excluded)
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
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$MSG_ESCAPED"
