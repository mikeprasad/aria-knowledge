#!/bin/sh
# bash-cd-check.sh — beforeShellExecution hook for Cursor (port of PreToolUse:Bash)
# Detects `cd <path>` invocations (including in compound commands), derives
# a tag query from the destination path's basename(s), and surfaces matched
# knowledge files via the shared lib-index-match.sh helper.
#
# Cursor port notes:
#   - Cursor payload uses camelCase (sessionId, command); fallback to snake_case during testing.
#   - Output uses agentMessage rather than systemMessage / additionalContext.
#
# Scope: knowledge-surfacing only. Does NOT block the cd. Does NOT validate
# the path. Returns silently (exit 0, no output) on any unfit input —
# non-cd commands, paths we can't parse, no index, threshold not met.
#
# Cooldown: per-project-per-session via /tmp/aria-bashcd-{sessionId}-{key}
# so repeated cd into the same project doesn't re-prompt.
#
# Ledger: in active mode, surfaced paths get appended to /tmp/aria-active-
# {sessionId} for cross-trigger dedup (read by task-context-check).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

# Debug log: confirms hook fires (Cursor port verification)
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $0 fired" >> /tmp/aria-hook-debug.log 2>/dev/null

# Skip if not configured, config invalid, or knowledge folder missing.
if [ "$KT_CONFIGURED" = "false" ] || [ -n "$KT_CONFIG_ERROR" ]; then
  exit 0
fi
if [ ! -d "$KT_KNOWLEDGE_FOLDER" ]; then
  exit 0
fi
if [ "$KT_AUTO_CAPTURE" = "false" ]; then
  exit 0
fi

INPUT=$(cat)

# Extract the Bash/shell command. We pull the command field from the JSON input.
COMMAND=$(echo "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//')
[ -z "$COMMAND" ] && exit 0

# Extract `cd <path>` — match anywhere in a compound command. We pre-pad the
# command with a leading space so `cd` at the start matches the same
# "after-space" pattern as `foo && cd bar` — sidesteps GNU-vs-BSD sed
# differences with the `\|` alternation operator (which is literal on BSD).
# Three fallthrough attempts in order: double-quoted, single-quoted,
# unquoted (stop at first separator: ;, &&, ||, |, >, end-of-string).
# First non-empty wins; graceful no-op if none match.
PADDED=" $COMMAND"
CD_PATH=$(printf '%s' "$PADDED" | sed -n 's/.* cd  *"\([^"]*\)".*/\1/p' | head -1)
if [ -z "$CD_PATH" ]; then
  CD_PATH=$(printf '%s' "$PADDED" | sed -n "s/.* cd  *'\\([^']*\\)'.*/\\1/p" | head -1)
fi
if [ -z "$CD_PATH" ]; then
  CD_PATH=$(printf '%s' "$PADDED" | sed -n 's/.* cd  *\([^ ;&|>][^ ;&|>]*\).*/\1/p' | head -1)
fi
[ -z "$CD_PATH" ] && exit 0

# Resolve relative paths against PWD. Strip trailing slashes.
case "$CD_PATH" in
  /*) ;;
  '~'|'~/'*) CD_PATH="$HOME${CD_PATH#~}" ;;
  *) CD_PATH="$PWD/$CD_PATH" ;;
esac
CD_PATH="${CD_PATH%/}"
[ -z "$CD_PATH" ] && exit 0

# Build a query from path basenames. We take the last 2 path components so
# `cd cs/cs-builder` → query "cs cs-builder", which lines up with how
# project tags are typically named in your index (one tag per directory).
LAST=$(basename "$CD_PATH" 2>/dev/null)
PARENT=$(basename "$(dirname "$CD_PATH")" 2>/dev/null)
QUERY="$PARENT $LAST"
QUERY=$(printf '%s' "$QUERY" | sed 's/^ *//;s/ *$//')
[ -z "$QUERY" ] && exit 0

# Session id for cooldown + ledger — Cursor uses camelCase; fallback to snake_case
SESSION_ID=$(echo "$INPUT" | grep -o '"sessionId":"[^"]*"' | head -1 | sed 's/"sessionId":"//;s/"//')
[ -z "$SESSION_ID" ] && SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')
[ -z "$SESSION_ID" ] && exit 0

# Per-project-per-session cooldown — same project shouldn't re-prompt.
PROJECT_KEY=$(printf '%s' "$CD_PATH" | tr '/' '_')
COOLDOWN_FILE="/tmp/aria-bashcd-${SESSION_ID}-${PROJECT_KEY}"
[ -f "$COOLDOWN_FILE" ] && exit 0

# Match
INDEX_FILE="$KT_KNOWLEDGE_FOLDER/index.md"
[ ! -f "$INDEX_FILE" ] && exit 0

. "$SCRIPT_DIR/lib-index-match.sh"
kt_index_match "$QUERY"

# v2.16.1: compute tracked artifacts (CODEMAP/STITCH) for the cd destination —
# surfaces alongside (or independently of) any knowledge-tag matches.
. "$SCRIPT_DIR/lib-tracked-artifacts.sh"
kt_artifact_compute_for_path "$CD_PATH"

# Ledger filter (active mode) — applied to BOTH knowledge files and artifacts
LEDGER="/tmp/aria-active-${SESSION_ID}"
if [ "$KT_ACTIVE_SURFACING" = "true" ]; then
  if [ "$KT_MATCH_COUNT" -gt 0 ]; then
    kt_match_filter_ledger "$LEDGER"
  fi
  if [ "$KT_ARTIFACTS_COUNT" -gt 0 ]; then
    kt_artifact_filter_ledger "$LEDGER"
  fi
fi

# Exit if NEITHER surfacing has results
if [ "$KT_MATCH_COUNT" -eq 0 ] && [ "$KT_ARTIFACTS_COUNT" -eq 0 ]; then
  kt_match_cleanup
  exit 0
fi

# Mark cooldown (covers both surfacing kinds for this project this session)
date +%s > "$COOLDOWN_FILE" 2>/dev/null

# Knowledge-file processing (if matches present)
FILE_LIST=""
if [ "$KT_MATCH_COUNT" -gt 0 ]; then
  FILE_LIST=$(head -5 "$KT_MATCH_FILES_TMP" | sed 's/^/  - /' | tr '\n' ';' | sed 's/;$//;s/;/ /g')
  if [ "$KT_ACTIVE_SURFACING" = "true" ]; then
    kt_match_record_ledger "$LEDGER"
  fi
fi
kt_match_cleanup

# Record artifacts to ledger (active mode only)
if [ "$KT_ACTIVE_SURFACING" = "true" ] && [ "$KT_ARTIFACTS_COUNT" -gt 0 ]; then
  kt_artifact_record_ledger "$LEDGER"
fi

# Emit via agentMessage — does not block the cd, just adds context for the
# agent's next turn. Branch wording on active mode + presence.
COMBINED_MSG=""

if [ "$KT_MATCH_COUNT" -gt 0 ]; then
  if [ "$KT_ACTIVE_SURFACING" = "true" ]; then
    COMBINED_MSG="ARIA ACTIVE — switching into ${LAST} (tags matched: ${KT_MATCH_TAGS}). Read these ${KT_MATCH_COUNT} knowledge file(s) before exploring the new directory, then summarize what loaded in 1-2 sentences: ${FILE_LIST}. (Recorded to session ledger.) "
  else
    COMBINED_MSG="ARIA: Detected cd into ${LAST}. ${KT_MATCH_COUNT} relevant knowledge file(s) match tags: ${KT_MATCH_TAGS}. ${FILE_LIST}. Ask 'load knowledge about ${KT_MATCH_TAGS}' to load, or proceed without. "
  fi
fi

# Append tracked-artifacts part (CODEMAP/STITCH instruction from lib-tracked-artifacts.sh)
if [ "$KT_ARTIFACTS_COUNT" -gt 0 ]; then
  COMBINED_MSG="${COMBINED_MSG}${KT_ARTIFACTS_INSTRUCTION}"
fi

MSG=$(kt_json_escape "$COMBINED_MSG")
printf '{"agentMessage":"%s"}\n' "$MSG"
