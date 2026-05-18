#!/bin/sh
# pre-compact-check.sh — PreCompact hook for aria-knowledge
# Saves a transcript snapshot before compaction wipes conversation detail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

# Skip if not configured or config invalid
if [ "$KT_CONFIGURED" = "false" ] || [ -n "$KT_CONFIG_ERROR" ]; then
  exit 0
fi

# Skip if knowledge folder missing
if [ ! -d "$KT_KNOWLEDGE_FOLDER" ]; then
  exit 0
fi

# Skip if auto_capture disabled
if [ "$KT_AUTO_CAPTURE" = "false" ]; then
  exit 0
fi

# Read hook input from stdin
INPUT=$(cat)

# Extract session_id and transcript_path from JSON
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')
TRANSCRIPT_PATH=$(echo "$INPUT" | grep -o '"transcript_path":"[^"]*"' | head -1 | sed 's/"transcript_path":"//;s/"//')

# Ensure captures directory exists
CAPTURES_DIR="$KT_KNOWLEDGE_FOLDER/intake/pre-compact-captures"
mkdir -p "$CAPTURES_DIR" 2>/dev/null

# Copy transcript if it exists and is readable
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] && [ -r "$TRANSCRIPT_PATH" ]; then
  TODAY=$(date +%Y-%m-%d)
  SESSION_SHORT=$(echo "$SESSION_ID" | cut -c1-8)
  SNAPSHOT_FILE="$CAPTURES_DIR/${TODAY}_${SESSION_SHORT}.md"

  cp "$TRANSCRIPT_PATH" "$SNAPSHOT_FILE" 2>/dev/null

  if [ -f "$SNAPSHOT_FILE" ]; then
    MSG=$(kt_json_escape "ARIA pre-compaction: transcript snapshot saved to $SNAPSHOT_FILE. Uncaptured knowledge from the prior conversation may exist — consider running /extract to capture insights before continuing.")
    echo '{"hookSpecificOutput":{"hookEventName":"PreCompact","additionalContext":"'"$MSG"'"}}'
  fi
fi
