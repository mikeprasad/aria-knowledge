#!/bin/bash
# bash-cd-aria.sh — Antigravity PreToolUse wrapper for run_command.
# Matched on hooks.json by: run_command
# Wraps canonical bash-cd-check.sh which surfaces path-keyed knowledge
# files when the agent runs cd into a tracked directory.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-antigravity-input.sh
source "$LIB_DIR/lib-antigravity-input.sh"

CANONICAL_CD="$CLAUDE_PLUGIN_ROOT/bin/bash-cd-check.sh"
CANONICAL_WRITE="$CLAUDE_PLUGIN_ROOT/bin/pre-bash-write-check.sh"
CANONICAL_PREFLIGHT="$CLAUDE_PLUGIN_ROOT/bin/pre-commit-preflight-check.sh"

# Canonical script expects CLAUDE_BASH_COMMAND.
export CLAUDE_BASH_COMMAND="$ARIA_TOOL_COMMANDLINE"
export CLAUDE_BASH_CWD="$ARIA_TOOL_CWD"

PAYLOAD=$(jq -cn \
  --arg cmd "$ARIA_TOOL_COMMANDLINE" \
  --arg sid "$ARIA_CONVERSATION_ID" \
  '{command: $cmd, session_id: $sid}')

ADVISORIES=()
DENIAL_REASON=""

run_bash_hook() {
  local script="$1"
  [ -x "$script" ] || return 0

  local output
  output=$(printf '%s' "$PAYLOAD" | "$script" 2>&1)
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    DENIAL_REASON="${output:-Hook $(basename "$script") denied this command.}"
    return 1
  fi

  if [ -n "$output" ]; then
    if jq -e . >/dev/null 2>&1 <<<"$output"; then
      local decision
      decision=$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$output" 2>/dev/null)
      if [ "$decision" = "deny" ]; then
        local reason
        reason=$(jq -r '.hookSpecificOutput.permissionDecisionReason // empty' <<<"$output" 2>/dev/null)
        DENIAL_REASON="${reason:-Pre-commit preflight check denied this commit.}"
        return 1
      fi
      local ctx
      ctx=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$output" 2>/dev/null)
      if [ -n "$ctx" ]; then
        ADVISORIES+=("$ctx")
      fi
    else
      ADVISORIES+=("$output")
    fi
  fi
  return 0
}

run_bash_hook "$CANONICAL_CD" || {
  aria_emit_decision "deny" "$DENIAL_REASON"
  exit 0
}

run_bash_hook "$CANONICAL_WRITE" || {
  aria_emit_decision "deny" "$DENIAL_REASON"
  exit 0
}

run_bash_hook "$CANONICAL_PREFLIGHT" || {
  aria_emit_decision "deny" "$DENIAL_REASON"
  exit 0
}

if [ ${#ADVISORIES[@]} -gt 0 ]; then
  COMBINED_ADVISORY=$(IFS=$'\n'; echo "${ADVISORIES[*]}")
  aria_emit_decision "allow" "$COMBINED_ADVISORY"
else
  aria_emit_decision "allow"
fi
