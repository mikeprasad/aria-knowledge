#!/bin/sh
# task-context-check.sh — TaskCreated hook for aria-knowledge
# Checks knowledge index for tags matching the new task and surfaces relevant files

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

# Extract session_id for cooldown
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')
if [ -z "$SESSION_ID" ]; then
  exit 0
fi

# Check cooldown — skip if last fire was less than 30 seconds ago
COOLDOWN_FILE="/tmp/aria-context-${SESSION_ID}"
if [ -f "$COOLDOWN_FILE" ]; then
  LAST_FIRE=$(cat "$COOLDOWN_FILE" 2>/dev/null)
  NOW=$(date +%s)
  if [ -n "$LAST_FIRE" ] && [ -n "$NOW" ]; then
    ELAPSED=$(( NOW - LAST_FIRE ))
    if [ "$ELAPSED" -lt 30 ]; then
      exit 0
    fi
  fi
fi

# Check index exists
INDEX_FILE="$KT_KNOWLEDGE_FOLDER/index.md"
if [ ! -f "$INDEX_FILE" ]; then
  exit 0
fi

# Extract task subject and description
TASK_SUBJECT=$(echo "$INPUT" | grep -o '"task_subject":"[^"]*"' | head -1 | sed 's/"task_subject":"//;s/"//')
TASK_DESCRIPTION=$(echo "$INPUT" | grep -o '"task_description":"[^"]*"' | head -1 | sed 's/"task_description":"//;s/"//')

# Combine and extract words: lowercase, strip punctuation, deduplicate
WORDS=$(printf '%s %s' "$TASK_SUBJECT" "$TASK_DESCRIPTION" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' ' ' | tr ' ' '\n' | sort -u)

if [ -z "$WORDS" ]; then
  exit 0
fi

# Extract tag headers from the Tag Index section of index.md
# Tags appear as "### tagname" lines after "## Tag Index"
TAG_SECTION=$(sed -n '/^## Tag Index$/,/^## /p' "$INDEX_FILE" | grep '^### ' | sed 's/^### //' | tr '[:upper:]' '[:lower:]')

if [ -z "$TAG_SECTION" ]; then
  exit 0
fi

# Match words against tags (exact match)
MATCHED_TAGS=""
MATCH_COUNT=0
for TAG in $TAG_SECTION; do
  for WORD in $WORDS; do
    if [ "$WORD" = "$TAG" ]; then
      MATCHED_TAGS="${MATCHED_TAGS} ${TAG}"
      MATCH_COUNT=$(( MATCH_COUNT + 1 ))
      break
    fi
  done
done

# Require 2+ tag matches
if [ "$MATCH_COUNT" -lt 2 ]; then
  exit 0
fi

# Collect files for matched tags, dedup after
TEMP_RAW=$(mktemp /tmp/aria-context-raw.XXXXXX)
TEMP_FILES=$(mktemp /tmp/aria-context-files.XXXXXX)
for TAG in $MATCHED_TAGS; do
  # Extract file lines under this tag's section (awk for portable range extraction)
  awk "/^### ${TAG}\$/{found=1; next} /^##/{found=0} found && /^- /" "$INDEX_FILE" | sed 's/^- //' >> "$TEMP_RAW"
done

# Dedup by file path (text before " — "), cap at 5
if [ -s "$TEMP_RAW" ]; then
  awk -F ' — ' '!seen[$1]++' "$TEMP_RAW" | head -5 > "$TEMP_FILES"
fi
rm -f "$TEMP_RAW" 2>/dev/null
if [ ! -f "$TEMP_FILES" ] || [ ! -s "$TEMP_FILES" ]; then
  rm -f "$TEMP_FILES" 2>/dev/null
  exit 0
fi

FILE_COUNT=$(wc -l < "$TEMP_FILES" | tr -d ' ')
if [ "$FILE_COUNT" -eq 0 ]; then
  rm -f "$TEMP_FILES" 2>/dev/null
  exit 0
fi

# Set cooldown
date +%s > "$COOLDOWN_FILE" 2>/dev/null

# Build output
TRIMMED_TAGS=$(echo "$MATCHED_TAGS" | sed 's/^ //')
FILE_LIST=$(head -5 "$TEMP_FILES" | sed 's/^/  - /' | tr '\n' ';' | sed 's/;$//;s/;/ /g')
rm -f "$TEMP_FILES" 2>/dev/null

MSG=$(kt_json_escape "ARIA: Found ${FILE_COUNT} relevant knowledge file(s) matching tags: ${TRIMMED_TAGS}. ${FILE_LIST}. Run /context ${TRIMMED_TAGS} to load, or proceed without.")
echo '{"systemMessage":"'"$MSG"'"}'
