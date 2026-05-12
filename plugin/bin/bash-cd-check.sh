#!/bin/sh
# bash-cd-check.sh — PreToolUse:Bash hook for aria-knowledge
# Detects `cd <path>` invocations (including in compound commands), derives
# a tag query from the destination path's basename(s), and surfaces matched
# knowledge files via the shared lib-index-match.sh helper.
#
# Scope: knowledge-surfacing only. Does NOT block the cd. Does NOT validate
# the path. Returns silently (exit 0, no output) on any unfit input —
# non-cd commands, paths we can't parse, no index, threshold not met.
#
# Cooldown: per-project-per-session via /tmp/aria-bashcd-{session_id}-{key}
# so repeated cd into the same project doesn't re-prompt.
#
# Ledger: in active mode, surfaced paths get appended to /tmp/aria-active-
# {session_id} for cross-trigger dedup (read by post-compact, filtered by
# task-context).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

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

# Extract the Bash command. We pull the command field from the JSON input.
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

# Session id for cooldown + ledger
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')
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
if [ "$KT_MATCH_COUNT" -eq 0 ]; then
  kt_match_cleanup
  exit 0
fi

# Ledger filter (active mode)
LEDGER="/tmp/aria-active-${SESSION_ID}"
if [ "$KT_ACTIVE_SURFACING" = "true" ]; then
  kt_match_filter_ledger "$LEDGER"
  if [ "$KT_MATCH_COUNT" -eq 0 ]; then
    kt_match_cleanup
    exit 0
  fi
fi

# Mark cooldown
date +%s > "$COOLDOWN_FILE" 2>/dev/null

FILE_LIST=$(head -5 "$KT_MATCH_FILES_TMP" | sed 's/^/  - /' | tr '\n' ';' | sed 's/;$//;s/;/ /g')

if [ "$KT_ACTIVE_SURFACING" = "true" ]; then
  kt_match_record_ledger "$LEDGER"
fi
kt_match_cleanup

# Emit via additionalContext (PreToolUse) — does not block the cd, just adds
# context for Claude's next turn. Branch wording on active mode.
if [ "$KT_ACTIVE_SURFACING" = "true" ]; then
  MSG=$(kt_json_escape "ARIA ACTIVE — switching into ${LAST} (tags matched: ${KT_MATCH_TAGS}). Read these ${KT_MATCH_COUNT} knowledge file(s) before exploring the new directory, then summarize what loaded in 1-2 sentences: ${FILE_LIST}. (Recorded to session ledger.)")
else
  MSG=$(kt_json_escape "ARIA: Detected cd into ${LAST}. ${KT_MATCH_COUNT} relevant knowledge file(s) match tags: ${KT_MATCH_TAGS}. ${FILE_LIST}. Run /context ${KT_MATCH_TAGS} to load, or proceed without.")
fi
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"'"$MSG"'"}}'
