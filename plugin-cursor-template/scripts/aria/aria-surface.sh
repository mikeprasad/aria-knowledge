#!/bin/sh
# aria-surface.sh — CLI over the shared matcher (kt_index_match) so skills and
# other non-hook callers get the same ranked knowledge files the hooks get.
#
# Usage: sh "<plugin-root>/scripts/aria-surface.sh" "<text>"
# Output (stdout): line 1 `tags: <space-separated matched tags>`, then one
#   ranked PATH per line (the part before ` — `, no description). Nothing at
#   all when the matcher does not fire.
# Exit: 0 always — no args, no config, no index and unreadable files included.
#   A caller must never be blocked by surfacing.

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0
[ -n "$SCRIPT_DIR" ] || exit 0

[ -n "$1" ] || exit 0

# shellcheck disable=SC1091
. "$SCRIPT_DIR/config.sh" >/dev/null 2>&1 || exit 0
[ -n "$KT_KNOWLEDGE_FOLDER" ] || exit 0
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib-index-match.sh" >/dev/null 2>&1 || exit 0

kt_index_match "$1" 2>/dev/null
if [ "${KT_MATCH_COUNT:-0}" -gt 0 ] 2>/dev/null && [ -f "$KT_MATCH_FILES_TMP" ]; then
  printf 'tags: %s\n' "$KT_MATCH_TAGS"
  awk -F ' — ' '{print $1}' "$KT_MATCH_FILES_TMP"
fi
kt_match_cleanup 2>/dev/null
exit 0
