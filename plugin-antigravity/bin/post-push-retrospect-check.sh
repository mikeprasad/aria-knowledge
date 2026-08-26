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
# printf '%s', NOT echo -- under POSIX sh, echo interprets the \n that JSON uses
# for a newline, this single-line grep then finds no closing quote, and COMMAND
# comes back empty (silent fail-open). A pushed commit range is routinely
# multi-line. Note line ~30 below already used printf for the same reason; this
# extraction was the one path still exposed.
COMMAND=$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//')
# ⛔ Was `case "$COMMAND" in *"git push"*)`, which MISSED every `git -C <dir> push`
# — a real push whose text never contains the substring `git push` — so a scripted
# or `git -C` push produced no retrospect offer at all. Identical miss to the one
# v2.46.1 fixed in pre-commit-preflight-check.sh; the fix was applied there and not
# to this sibling. Same anchored ERE, `push` for `commit`.
#
# ⚠ Unlike that sibling, the quoted-phrase false positive does NOT matter here and
# this pattern is NOT the correctness gate. A command that merely mentions the words
# produces no push summary, so Gate 3 below (the SHA-range line, and it says so at
# its own comment) rejects it. This is a cheap pre-filter, like the force glob under
# it — do not promote it into the authoritative test.
#
# Validated against 12 forms before the change: matches `git push`, `git -C /d push`,
# `git -c k=v push`, `git --no-pager push`, `cd /a && git push`; rejects `mygit push`,
# `git pushx`, `git push-nonexistent`, `git status`, `echo pushing`.
printf '%s' "$COMMAND" | grep -qE \
  '(^|[[:space:];&|(])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+push([[:space:]]|$)' \
  || exit 0

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
