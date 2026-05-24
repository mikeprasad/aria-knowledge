#!/bin/bash
# lib-antigravity-input.sh — shared stdin-JSON → env-var translator
#
# Sourced (not exec'd) by every Antigravity hook wrapper in this directory.
# Reads the hook input payload on stdin and exports env vars matching what
# ARIA's canonical bash scripts (in ../../../plugin/bin/) expect.
#
# Hard dependency: jq. If missing, the lib writes a deny-JSON to stdout
# and exits the calling wrapper with code 1 (fail-closed).

if ! command -v jq >/dev/null 2>&1; then
  printf '{"decision":"deny","reason":"aria-knowledge requires jq to parse Antigravity hook input. Install jq (apt-get install jq / brew install jq) and re-try."}\n'
  exit 1
fi

# Read stdin once and cache it; subsequent jq invocations operate on the cache.
ARIA_HOOK_INPUT="$(cat -)"
export ARIA_HOOK_INPUT

# Extract common fields. All hook events deliver these per docs/hooks.
export ARIA_CONVERSATION_ID
export ARIA_WORKSPACE_PATHS
export WORKSPACE_PATH               # first workspace, for canonical-script convenience
export ARIA_TRANSCRIPT_PATH
export ARIA_ARTIFACT_DIR
export ARIA_STEP_IDX

ARIA_CONVERSATION_ID=$(jq -r '.conversationId // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_WORKSPACE_PATHS=$(jq -r '.workspacePaths // [] | join(":")' <<<"$ARIA_HOOK_INPUT")
WORKSPACE_PATH=$(jq -r '.workspacePaths[0] // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_TRANSCRIPT_PATH=$(jq -r '.transcriptPath // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_ARTIFACT_DIR=$(jq -r '.artifactDirectoryPath // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_STEP_IDX=$(jq -r '.stepIdx // 0' <<<"$ARIA_HOOK_INPUT")

# Tool-call fields (PreToolUse / PostToolUse only). Empty string when absent.
export ARIA_TOOL_NAME
export ARIA_TOOL_TARGET_FILE
export ARIA_TOOL_COMMANDLINE
export ARIA_TOOL_CWD
export ARIA_TOOL_QUERY
export ARIA_TOOL_PATTERN
export ARIA_TOOL_ARGS_JSON

ARIA_TOOL_NAME=$(jq -r '.toolCall.name // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_TOOL_TARGET_FILE=$(jq -r '.toolCall.args.TargetFile // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_TOOL_COMMANDLINE=$(jq -r '.toolCall.args.CommandLine // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_TOOL_CWD=$(jq -r '.toolCall.args.Cwd // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_TOOL_QUERY=$(jq -r '.toolCall.args.Query // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_TOOL_PATTERN=$(jq -r '.toolCall.args.Pattern // ""' <<<"$ARIA_HOOK_INPUT")
ARIA_TOOL_ARGS_JSON=$(jq -c '.toolCall.args // {}' <<<"$ARIA_HOOK_INPUT")

# CLAUDE_PLUGIN_ROOT: ARIA's canonical scripts read this. In Antigravity there
# is no equivalent env var, so derive it from the wrapper's own path. The lib
# lives at <plugin-root>/bin/antigravity/lib-antigravity-input.sh, so the
# plugin root is two levels up.
export CLAUDE_PLUGIN_ROOT
CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Helper: emit Antigravity stdout JSON decision payload.
# Usage: aria_emit_decision allow|deny|ask|force_ask "reason text"
aria_emit_decision() {
  local decision="$1"
  local reason="${2:-}"
  jq -cn --arg d "$decision" --arg r "$reason" '{decision: $d} + (if $r == "" then {} else {reason: $r} end)'
}
