#!/bin/bash
# bash-cd-aria.sh — Antigravity PreToolUse wrapper for run_command.
# Matched on hooks.json by: run_command
# Wraps canonical bash-cd-check.sh which surfaces path-keyed knowledge
# files when the agent runs cd into a tracked directory.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-antigravity-input.sh
source "$LIB_DIR/lib-antigravity-input.sh"

CANONICAL="$CLAUDE_PLUGIN_ROOT/bin/bash-cd-check.sh"

if [ ! -x "$CANONICAL" ]; then
  aria_emit_decision "allow"
  exit 0
fi

# Canonical script expects CLAUDE_BASH_COMMAND.
export CLAUDE_BASH_COMMAND="$ARIA_TOOL_COMMANDLINE"
export CLAUDE_BASH_CWD="$ARIA_TOOL_CWD"

ADVISORY=$(jq -cn \
  --arg cmd "$ARIA_TOOL_COMMANDLINE" \
  --arg sid "$ARIA_CONVERSATION_ID" \
  '{command: $cmd, session_id: $sid}' | "$CANONICAL" 2>&1)
CANONICAL_EXIT=$?

if [ $CANONICAL_EXIT -eq 0 ]; then
  if [ -n "$ADVISORY" ]; then
    aria_emit_decision "allow" "$ADVISORY"
  else
    aria_emit_decision "allow"
  fi
else
  aria_emit_decision "deny" "${ADVISORY:-bash-cd-check denied this command.}"
fi
