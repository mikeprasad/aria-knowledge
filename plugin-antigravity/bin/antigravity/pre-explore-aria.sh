#!/bin/bash
# pre-explore-aria.sh — Antigravity PreToolUse wrapper for search-class tools.
# Matched on hooks.json by: grep_search|find_by_name
# Wraps canonical pre-explore-codemap-check.sh which surfaces CODEMAP-read
# reminders when exploring an unfamiliar codebase.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-antigravity-input.sh
source "$LIB_DIR/lib-antigravity-input.sh"

CANONICAL="$CLAUDE_PLUGIN_ROOT/bin/pre-explore-codemap-check.sh"

if [ ! -x "$CANONICAL" ]; then
  aria_emit_decision "allow"
  exit 0
fi

# Translate Antigravity tool args into the canonical script's expectations.
# The canonical script reads CLAUDE_TOOL_NAME and an optional path arg.
export CLAUDE_TOOL_NAME="$ARIA_TOOL_NAME"
case "$ARIA_TOOL_NAME" in
  grep_search)
    export CLAUDE_SEARCH_PATH=$(jq -r '.toolCall.args.SearchPath // ""' <<<"$ARIA_HOOK_INPUT")
    ;;
  find_by_name)
    export CLAUDE_SEARCH_PATH=$(jq -r '.toolCall.args.SearchDirectory // ""' <<<"$ARIA_HOOK_INPUT")
    ;;
esac

ADVISORY=$(jq -cn \
  --arg path "$CLAUDE_SEARCH_PATH" \
  --arg sid "$ARIA_CONVERSATION_ID" \
  '{path: $path, session_id: $sid}' | "$CANONICAL" 2>&1)
CANONICAL_EXIT=$?

if [ $CANONICAL_EXIT -eq 0 ]; then
  if [ -n "$ADVISORY" ]; then
    aria_emit_decision "allow" "$ADVISORY"
  else
    aria_emit_decision "allow"
  fi
else
  aria_emit_decision "deny" "${ADVISORY:-Codemap pre-check denied this exploration.}"
fi
