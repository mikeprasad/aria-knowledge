#!/bin/bash
# pre-edit-aria.sh — Antigravity PreToolUse wrapper for edit-class tools.
#
# Matched on hooks.json by: write_to_file|replace_file_content|multi_replace_file_content
# Reads stdin JSON via lib-antigravity-input.sh, sets env vars for the canonical
# script, then translates exit code + stderr into the Antigravity decision JSON.

# --- ONE-SHOT PROBE (self-deletes after first successful run) ---
PROBE_FLAG="$HOME/.gemini/antigravity/.aria-probe-fired"
if [ ! -f "$PROBE_FLAG" ]; then
  {
    echo "=== aria-knowledge first-session probe @ $(date -u '+%Y-%m-%dT%H:%M:%SZ') ==="
    echo "--- pwd ---"
    pwd
    echo "--- which bash ---"
    which bash
    echo "--- env (filtered) ---"
    env | grep -iE 'PLUGIN|AGY|ANTIGRAVITY|GEMINI|HOME|PATH' | sort
    echo "--- bash version ---"
    bash --version | head -1
    echo "--- jq version ---"
    jq --version 2>&1 || echo "jq missing"
    echo "--- BASH_SOURCE[0] ---"
    echo "${BASH_SOURCE[0]}"
    echo "--- derived CLAUDE_PLUGIN_ROOT ---"
    cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
    cd - >/dev/null
    echo "--- stdin payload (first 1000 bytes) ---"
    cat - | head -c 1000
  } > "$HOME/aria-antigravity-probe.log" 2>&1
  mkdir -p "$(dirname "$PROBE_FLAG")" 2>/dev/null || true
  touch "$PROBE_FLAG"
  # Read stdin again for normal hook execution. Since cat consumed it above,
  # the wrapper will see empty stdin this once. Emit allow + reason.
  printf '{"decision":"allow","reason":"aria-knowledge probe-hook fired; see ~/aria-antigravity-probe.log. Future hooks operate normally."}\n'
  exit 0
fi
# --- END PROBE ---

set -uo pipefail

# Source the shared parser. It reads stdin, sets env vars including
# CLAUDE_PLUGIN_ROOT, ARIA_TOOL_NAME, ARIA_TOOL_TARGET_FILE, WORKSPACE_PATH.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-antigravity-input.sh
source "$LIB_DIR/lib-antigravity-input.sh"

# Canonical script lives at <plugin-root>/bin/pre-edit-check.sh. CLAUDE_PLUGIN_ROOT
# is set by the lib to <plugin-antigravity>/, so the canonical script in the
# install layout is co-located with the wrapper's parent.
CANONICAL="$CLAUDE_PLUGIN_ROOT/bin/pre-edit-check.sh"

if [ ! -x "$CANONICAL" ]; then
  aria_emit_decision "allow" "aria-knowledge canonical pre-edit-check.sh not found at $CANONICAL; allowing without Rule 22 scan."
  exit 0
fi

# Canonical script reads Claude Code env vars. Translate Antigravity's tool
# names into the file path the canonical script expects to scan.
export CLAUDE_TOOL_NAME="$ARIA_TOOL_NAME"
export CLAUDE_TARGET_FILE="$ARIA_TOOL_TARGET_FILE"
export CLAUDE_TRANSCRIPT_PATH="$ARIA_TRANSCRIPT_PATH"

# Capture canonical script's stdout + stderr; advisory output goes to stderr in
# the canonical impl (visible to the agent in Claude Code via the hook log).
ADVISORY=$("$CANONICAL" 2>&1)
CANONICAL_EXIT=$?

if [ $CANONICAL_EXIT -eq 0 ]; then
  # Allow. Pass any advisory text through as the reason so the agent sees it.
  if [ -n "$ADVISORY" ]; then
    aria_emit_decision "allow" "$ADVISORY"
  else
    aria_emit_decision "allow"
  fi
else
  # Non-zero exit from canonical = Rule 22 deny.
  aria_emit_decision "deny" "${ADVISORY:-Rule 22 pre-edit check denied this edit.}"
fi
