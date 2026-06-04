#!/bin/bash
# post-plan-prospect-aria.sh — Antigravity PostToolUse wrapper for write_to_file.
# Wraps canonical post-plan-prospect-check.sh.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-antigravity-input.sh
source "$LIB_DIR/lib-antigravity-input.sh"

CANONICAL="$CLAUDE_PLUGIN_ROOT/bin/post-plan-prospect-check.sh"

if [ ! -x "$CANONICAL" ]; then
  printf '{}\n'
  exit 0
fi

LOG_FILE="$HOME/.gemini/antigravity/aria-knowledge-scope-check.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Construct JSON containing file_path to pass to canonical script.
OUT=$(jq -cn --arg fp "$ARIA_TOOL_TARGET_FILE" '{file_path: $fp}' | "$CANONICAL" 2>/dev/null || echo "")

if [ -n "$OUT" ]; then
  # Parse additionalContext from the JSON output.
  CONTEXT=$(echo "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || echo "")
  if [ -n "$CONTEXT" ]; then
    {
      echo "--- $(date -u '+%Y-%m-%dT%H:%M:%SZ') stepIdx=$ARIA_STEP_IDX"
      echo "$CONTEXT"
    } >> "$LOG_FILE"
  fi
fi

printf '{}\n'
