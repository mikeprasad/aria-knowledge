#!/bin/sh
# pre-explore-codemap-check.sh — beforeReadFile hook for Cursor (port of PreToolUse:Glob|Grep)
# Reminds to read CODEMAP.md Directory section before exploring a project codebase.
# Fires once per project per session (cooldown via temp file).
#
# Cursor port notes:
#   - Cursor payload uses camelCase (sessionId, filePath); fallback to snake_case during testing.
#   - Output uses agentMessage rather than systemMessage / additionalContext.

# Read the tool input to get the target path
INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

# Debug log: confirms hook fires (Cursor port verification)
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $0 fired" >> /tmp/aria-hook-debug.log 2>/dev/null

# Cursor's beforeReadFile uses filePath; fallback to path / file_path during testing
TARGET_PATH=$(echo "$INPUT" | grep -o '"filePath":"[^"]*"' | head -1 | sed 's/"filePath":"//;s/"//')
[ -z "$TARGET_PATH" ] && TARGET_PATH=$(echo "$INPUT" | grep -o '"path":"[^"]*"' | head -1 | sed 's/"path":"//;s/"//')
[ -z "$TARGET_PATH" ] && TARGET_PATH=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"//')

# If no explicit path, target is cwd — skip (sessionStart already covers cwd)
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

# Extract sessionId for cooldown scoping — Cursor camelCase with snake_case fallback
SESSION_ID=$(echo "$INPUT" | grep -o '"sessionId":"[^"]*"' | head -1 | sed 's/"sessionId":"//;s/"//')
[ -z "$SESSION_ID" ] && SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')
if [ -z "$SESSION_ID" ]; then
  # Fallback: use parent PID as session proxy
  SESSION_ID="$$"
fi

# Per-project cooldown — derive project key from CODEMAP directory
PROJECT_DIR=$(dirname "$CODEMAP_PATH")
PROJECT_KEY=$(echo "$PROJECT_DIR" | tr '/' '_')
COOLDOWN_FILE="/tmp/aria-codemap-${SESSION_ID}-${PROJECT_KEY}"

if [ -f "$COOLDOWN_FILE" ]; then
  # Already reminded for this project in this session
  exit 0
fi

# Set cooldown
date +%s > "$COOLDOWN_FILE" 2>/dev/null

# Make path relative to cwd for cleaner display
DISPLAY_PATH=$(echo "$CODEMAP_PATH" | sed "s|$PWD/||")

# Check for sibling STITCH.md (cross-repo stitch artifact)
STITCH_SIBLING="$(dirname "$CODEMAP_PATH")/STITCH.md"
STITCH_EXTRA=""
if [ -f "$STITCH_SIBLING" ]; then
  STITCH_DISP=$(echo "$STITCH_SIBLING" | sed "s|$PWD/||")
  STITCH_EXTRA=" STITCH.md also present at ${STITCH_DISP} (endpoint / entity / drift tables for cross-repo reasoning)."
fi

MSG=$(kt_json_escape "CODEMAP exists at ${DISPLAY_PATH} — Read Directory section before exploring further.${STITCH_EXTRA} This fires once per project per session.")
printf '{"agentMessage":"%s"}\n' "$MSG"
