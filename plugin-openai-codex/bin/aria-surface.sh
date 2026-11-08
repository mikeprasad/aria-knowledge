#!/bin/sh
# aria-surface.sh — CLI over the shared matcher (kt_index_match) so skills and
# other non-hook callers get the same ranked knowledge files the hooks get.
#
# Usage (a model, or anything that goes through a shell):
#   sh "<plugin-root>/scripts/aria-surface.sh" - <<'ARIA_TASK'
#   <the text, on its own lines>
#   ARIA_TASK
# `-` reads the text from stdin; so does no argument when stdin is not a
# terminal. ⛔ Never put untrusted text inside double quotes on a command line:
# there, backticks and $(...) in it RUN and $VAR expands. The quoted delimiter
# ('ARIA_TASK') makes the heredoc literal. A program that execs this without a
# shell (codex-hook.py passes an argv list) may pass the text as argument 1.
#
# Output (stdout), exactly one of:
#   fired        line 1 `tags: <space-separated matched tags>`, then one ranked
#                PATH per line (the part before ` — `, no description)
#   nothing      the match did not fire (no tag matched, below the firing rule,
#                or fired on tags carrying no files), or there was no text
#   unavailable  one line `unavailable: <reason>` — config, knowledge folder or
#                matcher library missing, or the matcher reported an error (no
#                index, unreadable index, temp-file or cache failure). This is
#                "could not look", never "0 matches".
# Exit: 0 whenever this script runs. A caller must never be blocked by surfacing.

unavailable() { printf 'unavailable: %s\n' "$1"; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || unavailable "cannot locate the plugin scripts"
[ -n "$SCRIPT_DIR" ] || unavailable "cannot locate the plugin scripts"

if [ "$#" -eq 0 ]; then
  [ -t 0 ] && exit 0
  _as_text=$(cat)
elif [ "$1" = "-" ]; then
  _as_text=$(cat)
else
  _as_text=$1
fi
[ -n "$_as_text" ] || exit 0

# shellcheck disable=SC1091
. "$SCRIPT_DIR/config.sh" >/dev/null 2>&1 || unavailable "config.sh failed to load"
[ -z "$KT_CONFIG_ERROR" ] || unavailable "config error (run /setup)"
[ -n "$KT_KNOWLEDGE_FOLDER" ] || unavailable "no knowledge folder configured"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib-index-match.sh" >/dev/null 2>&1 || unavailable "matcher library failed to load"

KT_MATCH_STATUS=""
kt_index_match "$_as_text" 2>/dev/null
case "$KT_MATCH_STATUS" in
  ok)
    if [ "${KT_MATCH_COUNT:-0}" -gt 0 ] 2>/dev/null && [ -f "$KT_MATCH_FILES_TMP" ]; then
      printf 'tags: %s\n' "$KT_MATCH_TAGS"
      awk -F ' — ' '{print $1}' "$KT_MATCH_FILES_TMP"
    else
      kt_match_cleanup 2>/dev/null
      unavailable "matcher reported a match but no files"
    fi
    ;;
  nofire) ;;
  error:*)
    kt_match_cleanup 2>/dev/null
    unavailable "matcher error: ${KT_MATCH_STATUS#error:}"
    ;;
  *)
    kt_match_cleanup 2>/dev/null
    unavailable "matcher reported no status"
    ;;
esac
kt_match_cleanup 2>/dev/null
exit 0
