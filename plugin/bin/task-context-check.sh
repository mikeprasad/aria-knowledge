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

# Delegate tokenize→match→collect to the shared helper. Threshold (≥2 tags)
# and emission cap (5 files) are policy enforced by the helper; cooldown,
# session-ledger dedup, and wording stay this script's responsibility.
. "$SCRIPT_DIR/lib-index-match.sh"
kt_index_match "$TASK_SUBJECT $TASK_DESCRIPTION"
if [ "$KT_MATCH_COUNT" -eq 0 ]; then
  kt_match_cleanup
  exit 0
fi

# Active-mode session ledger: filter out files already surfaced earlier in
# this session, so we don't re-emit the same paths on every task dispatch.
# Passive mode skips the ledger entirely (it's a no-cost suggestion anyway).
LEDGER="/tmp/aria-active-${SESSION_ID}"
if [ "$KT_ACTIVE_SURFACING" = "true" ]; then
  kt_match_filter_ledger "$LEDGER"
  if [ "$KT_MATCH_COUNT" -eq 0 ]; then
    kt_match_cleanup
    exit 0
  fi
fi

# Set cooldown
date +%s > "$COOLDOWN_FILE" 2>/dev/null

# Build file list (formatted) before cleanup releases the temp file.
FILE_LIST=$(head -5 "$KT_MATCH_FILES_TMP" | sed 's/^/  - /' | tr '\n' ';' | sed 's/;$//;s/;/ /g')

# Record surfaced paths to the session ledger so subsequent triggers in this
# session won't re-emit the same files. Only in active mode — passive mode's
# "suggest /context" doesn't load anything, so dedup is irrelevant.
if [ "$KT_ACTIVE_SURFACING" = "true" ]; then
  kt_match_record_ledger "$LEDGER"
fi

kt_match_cleanup

# Branch wording on KT_ACTIVE_SURFACING. Active instructs Claude to Read the
# matched files immediately, then summarize. Passive falls back to /context
# suggestion (the v2.14.x behavior, opt-out path for users who set
# active_knowledge_surfacing: false).
if [ "$KT_ACTIVE_SURFACING" = "true" ]; then
  MSG=$(kt_json_escape "ARIA ACTIVE — ${KT_MATCH_COUNT} knowledge file(s) match this task (tags: ${KT_MATCH_TAGS}). Read each, then summarize what loaded in 1-2 sentences before composing the subagent prompt or proceeding. Files: ${FILE_LIST}. (Recorded to session ledger — won't re-surface.)")
else
  MSG=$(kt_json_escape "ARIA: Found ${KT_MATCH_COUNT} relevant knowledge file(s) matching tags: ${KT_MATCH_TAGS}. ${FILE_LIST}. Run /context ${KT_MATCH_TAGS} to load, or proceed without.")
fi
echo '{"systemMessage":"'"$MSG"'"}'
