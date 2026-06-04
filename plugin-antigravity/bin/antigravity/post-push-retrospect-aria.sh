#!/bin/bash
# post-push-retrospect-aria.sh — Antigravity PostToolUse wrapper for run_command.
# Wraps canonical post-push-retrospect-check.sh.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-antigravity-input.sh
source "$LIB_DIR/lib-antigravity-input.sh"

CANONICAL="$CLAUDE_PLUGIN_ROOT/bin/post-push-retrospect-check.sh"

if [ ! -x "$CANONICAL" ]; then
  printf '{}\n'
  exit 0
fi

LOG_FILE="$HOME/.gemini/antigravity/aria-knowledge-scope-check.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# Extract stdout/stderr/output of the command execution robustly from the payload.
STDERR=$(jq -r '.toolResponse.stderr // .toolResponse.stdout // .toolResponse // .tool_result.output // .tool_result // .result // .stdout // .stderr // .output // ""' <<<"$ARIA_HOOK_INPUT")

# Construct JSON containing command and stderr to pass to canonical script.
# The canonical script executes within the git repo context.
OUT=$(jq -cn --arg cmd "$ARIA_TOOL_COMMANDLINE" --arg err "$STDERR" '{command: $cmd, stderr: $err}' | "$CANONICAL" 2>/dev/null || echo "")

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
