#!/bin/bash
# post-edit-aria.sh — Antigravity PostToolUse wrapper for edit-class tools.
# Matched on hooks.json by: write_to_file|replace_file_content|multi_replace_file_content
# Wraps canonical post-edit-check.sh which emits the Rule 22 scope-check
# PASS / CONDITIONAL / FAIL output for the just-completed edit.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-antigravity-input.sh
source "$LIB_DIR/lib-antigravity-input.sh"

CANONICAL="$CLAUDE_PLUGIN_ROOT/bin/post-edit-check.sh"

# PostToolUse output schema per docs: empty JSON {} on success. The canonical
# script writes scope-check text to stdout; we surface that as the agent sees it
# via stderr-equivalent (Antigravity's hook log), but the protocol-level reply
# is {} unless we want to short-circuit (we don't here).

# Translate Antigravity error field into a canonical-friendly signal.
ERROR_FIELD=$(jq -r '.error // ""' <<<"$ARIA_HOOK_INPUT")
export CLAUDE_TOOL_ERROR="$ERROR_FIELD"
export CLAUDE_TRANSCRIPT_PATH="$ARIA_TRANSCRIPT_PATH"

# Run canonical, capture but don't propagate output. Antigravity's PostToolUse
# does NOT support reasoning back to the agent — output is {}. If we want to
# show the scope-check to the user, it has to go via a side channel (e.g. file
# log). For v1, log to ~/.gemini/antigravity/aria-knowledge-scope-check.log.
LOG_FILE="$HOME/.gemini/antigravity/aria-knowledge-scope-check.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

if [ -x "$CANONICAL" ]; then
  {
    echo "--- $(date -u '+%Y-%m-%dT%H:%M:%SZ') stepIdx=$ARIA_STEP_IDX error=${ERROR_FIELD:-none}"
    "$CANONICAL" 2>&1
  } >> "$LOG_FILE" || true
fi

# Per docs/hooks PostToolUse: output is {} on success.
printf '{}\n'
