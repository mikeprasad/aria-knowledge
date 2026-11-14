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
# kt_session_key (lib-state-key.sh): read whitespace-tolerantly, accepted only as [A-Za-z0-9._-]+ and
# never rewritten — the key every hook in this port names this family's state with. Absent or rejected: no key, nothing
# surfaced (spec D3).
[ -f "$SCRIPT_DIR/lib-state-key.sh" ] || exit 0
. "$SCRIPT_DIR/lib-state-key.sh"
SESSION_ID=$(kt_session_key "$INPUT" session_id) || exit 0

# Check cooldown — skip if last fire was less than 30 seconds ago.
# 2.58.0: the cooldown lives in the private per-user state directory (lib-state-key.sh). With no
# directory (spec D3) nothing is surfaced: without a cooldown every task dispatch would repeat it.
# The id goes through kt_state_path, which refuses one with a "/". Only a regular file that is not
# a link is read (a FIFO would block the read); anything else at the name is no state: emit nothing.
. "$SCRIPT_DIR/lib-state-key.sh"
kt_state_resolve || exit 0
COOLDOWN_FILE=$(kt_state_path "aria-context-${SESSION_ID}") || exit 0
# The session ledger (active mode) lives in the same directory.
LEDGER=$(kt_state_path "aria-active-${SESSION_ID}") || exit 0
if [ -L "$COOLDOWN_FILE" ] || { [ -e "$COOLDOWN_FILE" ] && [ ! -f "$COOLDOWN_FILE" ]; }; then
  exit 0
fi
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
# printf '%s', NOT echo — these two are FREE TEXT and routinely multi-line. Under POSIX sh,
# echo interprets the \n that JSON uses for a newline, the value splits across lines, and the
# single-line grep below matches nothing (silent fail-open).
TASK_SUBJECT=$(printf '%s' "$INPUT" | grep -o '"task_subject":"[^"]*"' | head -1 | sed 's/"task_subject":"//;s/"//')
TASK_DESCRIPTION=$(printf '%s' "$INPUT" | grep -o '"task_description":"[^"]*"' | head -1 | sed 's/"task_description":"//;s/"//')

# Delegate tokenize→match→collect to the shared helper. Threshold (≥2 tags)
# and emission cap (5 files) are policy enforced by the helper; cooldown,
# session-ledger dedup, and wording stay this script's responsibility.
. "$SCRIPT_DIR/lib-index-match.sh"
kt_index_match "$TASK_SUBJECT $TASK_DESCRIPTION"

# v2.16.1: compute tracked artifacts (CODEMAP/STITCH) for $PWD — surfaces
# alongside (or independently of) any knowledge-tag matches so subagents
# get project structural context.
. "$SCRIPT_DIR/lib-tracked-artifacts.sh"
kt_artifact_compute_for_path "$PWD"

# Active-mode session ledger: filter out files/artifacts already surfaced
# earlier in this session, so we don't re-emit the same paths on every task
# dispatch. Passive mode skips the ledger entirely. LEDGER is set beside the cooldown above.
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

# Set cooldown
date +%s > "$COOLDOWN_FILE" 2>/dev/null

# Knowledge-file processing
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

# Branch wording on KT_ACTIVE_SURFACING + presence of each surfacing kind.
COMBINED_MSG=""

if [ "$KT_MATCH_COUNT" -gt 0 ]; then
  if [ "$KT_ACTIVE_SURFACING" = "true" ]; then
    COMBINED_MSG="ARIA ACTIVE — ${KT_MATCH_COUNT} knowledge file(s) match this task (tags: ${KT_MATCH_TAGS}). Read each, then summarize what loaded in 1-2 sentences before composing the subagent prompt or proceeding. Files: ${FILE_LIST}. (Recorded to session ledger — won't re-surface.) "
  else
    COMBINED_MSG="ARIA: Found ${KT_MATCH_COUNT} relevant knowledge file(s) matching tags: ${KT_MATCH_TAGS}. ${FILE_LIST}. Run /context ${KT_MATCH_TAGS} to load, or proceed without. "
  fi
fi

if [ "$KT_ARTIFACTS_COUNT" -gt 0 ]; then
  COMBINED_MSG="${COMBINED_MSG}${KT_ARTIFACTS_INSTRUCTION}"
fi

MSG=$(kt_json_escape "$COMBINED_MSG")
echo '{"systemMessage":"'"$MSG"'"}'
