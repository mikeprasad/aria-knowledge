#!/bin/sh
# post-push-retrospect-check.sh — PostToolUse hook for Bash.
# When a `git push` lands a real fast-forward range and auto_retrospect is
# nudge|run, surface an instruction to /retrospect the pushed range.
# Parses the range from tool_response.stderr (git push writes its summary to
# stderr). No jq — decode literal \n escapes, then grep the SHA-range line.

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

# Gate 1: configured + enabled
[ "$KT_CONFIGURED" = "true" ] || exit 0
case "$KT_AUTO_RETROSPECT" in nudge|run) ;; *) exit 0 ;; esac

# Gate 2: is this a git push?
COMMAND=$(echo "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//')
case "$COMMAND" in *"git push"*) ;; *) exit 0 ;; esac

# Gate 3: force-push skip. Space-wrap $COMMAND so an end-of-command flag
# (e.g. `git push origin main -f`) is caught. NOTE: the SHA-range regex
# below is the AUTHORITATIVE correctness gate (it rejects forced three-dot
# `a...b` ranges); this glob is just a cheap pre-filter — do not "tighten"
# the regex on the assumption this glob catches every force.
case " $COMMAND " in *" --force"*|*" -f "*|*" --force-with-lease"*) exit 0 ;; esac

# Decode the whole payload's literal \n escapes to real newlines, then find
# the SHA-range summary line. Two-dot range = fast-forward; forced pushes use
# ...three-dot and won't match (and are gated out above anyway).
DECODED=$(printf '%s' "$INPUT" | sed 's/\\n/\
/g')
SUMMARY=$(printf '%s' "$DECODED" | grep -E '[0-9a-f]{7,40}\.\.[0-9a-f]{7,40}' | head -1)
[ -n "$SUMMARY" ] || exit 0   # no range line (up-to-date / new branch) → skip

RANGE=$(printf '%s' "$SUMMARY" | grep -oE '[0-9a-f]{7,40}\.\.[0-9a-f]{7,40}' | head -1)
[ -n "$RANGE" ] || exit 0
BRANCH=$(printf '%s' "$SUMMARY" | sed -n 's/.*-> \([A-Za-z0-9._/-]*\).*/\1/p')

# Gate 4: branch filter (empty list = any branch)
if [ -n "$KT_RETROSPECT_BRANCHES" ] && [ -n "$BRANCH" ]; then
  case ",$KT_RETROSPECT_BRANCHES," in
    *",$BRANCH,"*) ;;
    *) exit 0 ;;
  esac
fi

# Gate 5: commit-count threshold (local objects still present post-push)
COUNT=$(git rev-list --count "$RANGE" 2>/dev/null)
[ -n "$COUNT" ] || exit 0
[ "$COUNT" -ge "$KT_RETROSPECT_MIN_COMMITS" ] 2>/dev/null || exit 0

if [ "$KT_AUTO_RETROSPECT" = "run" ]; then
  MSG="AUTO-RETROSPECT (run): pushed ${COUNT} commits (${RANGE}) to ${BRANCH}. Run /retrospect range ${RANGE} inline now."
else
  MSG="AUTO-RETROSPECT (nudge): pushed ${COUNT} commits (${RANGE}) to ${BRANCH}. Offer to run /retrospect range ${RANGE} and ask the user (do not auto-run)."
fi
MSG_ESCAPED=$(kt_json_escape "$MSG")
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$MSG_ESCAPED"
