#!/bin/sh
# post-push-retrospect-check.sh — afterShellExecution hook (Cursor port of PostToolUse:Bash).
# When a git push lands a real fast-forward range and auto_retrospect is nudge|run,
# surface an instruction to /retrospect the pushed range.

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

[ "$KT_CONFIGURED" = "true" ] || exit 0
case "$KT_AUTO_RETROSPECT" in nudge|run) ;; *) exit 0 ;; esac

COMMAND=$(echo "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//')
case "$COMMAND" in *"git push"*) ;; *) exit 0 ;; esac
case " $COMMAND " in *" --force"*|*" -f "*|*" --force-with-lease"*) exit 0 ;; esac

OUTPUT=$(echo "$INPUT" | grep -o '"output":"[^"]*"' | head -1 | sed 's/"output":"//;s/"$//')
STDERR=$(echo "$INPUT" | grep -o '"stderr":"[^"]*"' | head -1 | sed 's/"stderr":"//;s/"$//')
DECODED=$(printf '%s\n%s' "$OUTPUT" "$STDERR" | sed 's/\\n/\
/g')
SUMMARY=$(printf '%s' "$DECODED" | grep -E '[0-9a-f]{7,40}\.\.[0-9a-f]{7,40}' | head -1)
[ -n "$SUMMARY" ] || exit 0

RANGE=$(printf '%s' "$SUMMARY" | grep -oE '[0-9a-f]{7,40}\.\.[0-9a-f]{7,40}' | head -1)
[ -n "$RANGE" ] || exit 0
BRANCH=$(printf '%s' "$SUMMARY" | sed -n 's/.*-> \([A-Za-z0-9._/-]*\).*/\1/p')

if [ -n "$KT_RETROSPECT_BRANCHES" ] && [ -n "$BRANCH" ]; then
  case ",$KT_RETROSPECT_BRANCHES," in
    *",$BRANCH,"*) ;;
    *) exit 0 ;;
  esac
fi

COUNT=$(git rev-list --count "$RANGE" 2>/dev/null)
[ -n "$COUNT" ] || exit 0
[ "$COUNT" -ge "$KT_RETROSPECT_MIN_COMMITS" ] 2>/dev/null || exit 0

if [ "$KT_AUTO_RETROSPECT" = "run" ]; then
  MSG="AUTO-RETROSPECT (run): pushed ${COUNT} commits (${RANGE}) to ${BRANCH}. Run /retrospect range ${RANGE} inline now."
else
  MSG="AUTO-RETROSPECT (nudge): pushed ${COUNT} commits (${RANGE}) to ${BRANCH}. Offer to run /retrospect range ${RANGE} and ask the user (do not auto-run)."
fi
MSG_ESCAPED=$(kt_json_escape "$MSG")
printf '{"agentMessage":"%s"}\n' "$MSG_ESCAPED"
