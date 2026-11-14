#!/bin/sh
# pre-explore-codemap-check.sh — PreToolUse hook for Glob|Grep
# Reminds to read CODEMAP.md Directory section before exploring a project codebase.
# Fires once per project per session (cooldown in the private state dir, lib-state-key.sh; with no
# state dir the reminder is not emitted, spec D3).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Read the tool input to get the target path
INPUT=$(cat)

# Extract path from Glob (path field) or Grep (path field)
TARGET_PATH=$(echo "$INPUT" | grep -o '"path":"[^"]*"' | head -1 | sed 's/"path":"//;s/"//')

# If no explicit path, target is cwd — skip (SessionStart already covers cwd)
if [ -z "$TARGET_PATH" ]; then
  exit 0
fi

# Resolve to absolute path if relative
case "$TARGET_PATH" in
  /*) ;; # already absolute
  *) TARGET_PATH="$PWD/$TARGET_PATH" ;;
esac

# Walk up from target path looking for a sibling/ancestor CODEMAP.md
SEARCH_DIR="$TARGET_PATH"
# If target is a file path, start from its directory
if [ -f "$SEARCH_DIR" ]; then
  SEARCH_DIR=$(dirname "$SEARCH_DIR")
fi

CODEMAP_PATH=""
WALK_DIR="$SEARCH_DIR"
DEPTH=0
MAX_DEPTH=4
while [ "$DEPTH" -lt "$MAX_DEPTH" ] && [ "$WALK_DIR" != "/" ]; do
  if [ -f "$WALK_DIR/CODEMAP.md" ]; then
    CODEMAP_PATH="$WALK_DIR/CODEMAP.md"
    break
  fi
  WALK_DIR=$(dirname "$WALK_DIR")
  DEPTH=$(( DEPTH + 1 ))
done

# No CODEMAP found — nothing to do
if [ -z "$CODEMAP_PATH" ]; then
  exit 0
fi

# Extract session_id for cooldown scoping
# kt_session_key (lib-state-key.sh): read whitespace-tolerantly, accepted only as [A-Za-z0-9._-]+ and
# never rewritten — the key every hook in this port names this family's state with. Absent: the PID proxy, as before.
# Rejected: no key — the reminder is not emitted (spec D3: no cooldown, so it would repeat).
[ -f "$SCRIPT_DIR/lib-state-key.sh" ] || exit 0
. "$SCRIPT_DIR/lib-state-key.sh"
SESSION_ID=$(kt_session_key "$INPUT" sessionId session_id)
case $? in
  1) SESSION_ID="$$" ;;   # Fallback: use parent PID as session proxy
  2) exit 0 ;;
esac

# Per-project cooldown — derive project key from CODEMAP directory
PROJECT_DIR=$(dirname "$CODEMAP_PATH")
PROJECT_KEY=$(echo "$PROJECT_DIR" | tr '/' '_')
# 2.58.0: the cooldown lives in the private per-user state directory (lib-state-key.sh). With no
# directory (spec D3) the reminder is NOT emitted: without a cooldown it would repeat on every
# search. The id goes through kt_state_path, which refuses one with a "/".
. "$SCRIPT_DIR/lib-state-key.sh"
kt_state_resolve || exit 0
COOLDOWN_FILE=$(kt_state_path "aria-codemap-${SESSION_ID}-${PROJECT_KEY}") || exit 0

# Already reminded for this project in this session — or a non-file at the name (no usable state,
# and a FIFO would block the write below): emit nothing.
if [ -e "$COOLDOWN_FILE" ] || [ -L "$COOLDOWN_FILE" ]; then
  exit 0
fi

# Set cooldown
date +%s > "$COOLDOWN_FILE" 2>/dev/null

# Make path relative to cwd for cleaner display
DISPLAY_PATH=$(echo "$CODEMAP_PATH" | sed "s|$PWD/||")

. "$SCRIPT_DIR/config.sh"

# Check for sibling STITCH.md (cross-repo stitch artifact)
STITCH_SIBLING="$(dirname "$CODEMAP_PATH")/STITCH.md"
STITCH_EXTRA=""
if [ -f "$STITCH_SIBLING" ]; then
  STITCH_DISP=$(echo "$STITCH_SIBLING" | sed "s|$PWD/||")
  STITCH_EXTRA=" STITCH.md also present at ${STITCH_DISP} (endpoint / entity / drift tables for cross-repo reasoning)."
fi

MSG=$(kt_json_escape "CODEMAP exists at ${DISPLAY_PATH} — Read Directory section before exploring further.${STITCH_EXTRA} This fires once per project per session.")
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"'"$MSG"'"}}'
