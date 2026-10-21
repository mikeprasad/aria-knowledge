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
fi

# ⛔ Print NOTHING. PreCompact has no hookSpecificOutput variant in the harness schema
# (an emission is rejected as invalid) and the docs say it discards systemMessage, so no
# output from this hook reaches the model or the user. The "/extract this snapshot"
# prompt is emitted after compaction by session-start-rules.sh (source=compact), which
# finds this file by session id.
