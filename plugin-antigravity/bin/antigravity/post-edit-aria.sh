#!/bin/bash
# post-edit-aria.sh — Antigravity PostToolUse wrapper for edit-class tools.
# Matched on hooks.json by: write_to_file|replace_file_content|multi_replace_file_content
# Wraps canonical post-edit-check.sh which emits the Rule 22 scope-check
# PASS / CONDITIONAL / FAIL output for the just-completed edit.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-antigravity-input.sh
source "$LIB_DIR/lib-antigravity-input.sh"

CANONICAL_CHECK="$CLAUDE_PLUGIN_ROOT/bin/post-edit-check.sh"
CANONICAL_TAUTOLOGY="$CLAUDE_PLUGIN_ROOT/bin/post-edit-tautology-check.sh"

# Run canonical, capture but don't propagate output. Antigravity's PostToolUse
# does NOT support reasoning back to the agent — output is {}. If we want to
# show the scope-check to the user, it has to go via a side channel (e.g. file
# log). For v1, log to ~/.gemini/antigravity/aria-knowledge-scope-check.log.
LOG_FILE="$HOME/.gemini/antigravity/aria-knowledge-scope-check.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

PAYLOAD=$(jq -cn \
  --arg fp "$ARIA_TOOL_TARGET_FILE" \
  --arg sid "$ARIA_CONVERSATION_ID" \
  --arg tp "$ARIA_TRANSCRIPT_PATH" \
  --arg err "$ERROR_FIELD" \
  '{file_path: $fp, session_id: $sid, transcript_path: $tp, error: $err}')

if [ -x "$CANONICAL_CHECK" ]; then
  {
    echo "--- $(date -u '+%Y-%m-%dT%H:%M:%SZ') stepIdx=$ARIA_STEP_IDX error=${ERROR_FIELD:-none}"
    printf '%s' "$PAYLOAD" | "$CANONICAL_CHECK" 2>&1
  } >> "$LOG_FILE" || true
fi

if [ -x "$CANONICAL_TAUTOLOGY" ]; then
  TAUTOLOGY_OUT=$(printf '%s' "$PAYLOAD" | "$CANONICAL_TAUTOLOGY" 2>&1 || true)
  if [ -n "$TAUTOLOGY_OUT" ]; then
    echo "$TAUTOLOGY_OUT" >> "$LOG_FILE" || true
  fi
fi

# Per docs/hooks PostToolUse: output is {} on success.
printf '{}\n'
