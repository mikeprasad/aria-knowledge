#!/bin/sh
# post-compact-check.sh — PostCompact hook for aria-knowledge
# (a) Notifies user that pre-compaction snapshots exist for review.
# (b) Re-surfaces the active-mode session ledger so Claude can reload
#     knowledge files that were active before compaction wiped them.

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

# Parse hook input — session_id is needed for the ledger path.
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')

MESSAGES=""

# Block 1: pre-compaction transcript snapshots (existing behavior).
CAPTURES_DIR="$KT_KNOWLEDGE_FOLDER/intake/pre-compact-captures"
SNAPSHOT_COUNT=$(find "$CAPTURES_DIR" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')

if [ "$SNAPSHOT_COUNT" -gt 0 ]; then
  MESSAGES="ARIA: ${SNAPSHOT_COUNT} pre-compaction transcript snapshot(s) saved in ${CAPTURES_DIR}/. Uncaptured knowledge from the prior conversation may exist. Prompt user: Want me to scan the pre-compaction snapshot for extractable knowledge before continuing? "
fi

# Block 2: active-surfacing ledger re-surface (v2.15.0+).
# Only fires if active mode is enabled, ledger exists, and has entries.
if [ "$KT_ACTIVE_SURFACING" = "true" ] && [ -n "$SESSION_ID" ]; then
  LEDGER="/tmp/aria-active-${SESSION_ID}"
  if [ -f "$LEDGER" ] && [ -s "$LEDGER" ]; then
    LEDGER_COUNT=$(wc -l < "$LEDGER" | tr -d ' ')
    # Format the first 5 paths into a compact list. Compaction is expensive
    # to recover from; even 5 file Reads is cheaper than re-discovering the
    # whole session's knowledge surface.
    LEDGER_LIST=$(head -5 "$LEDGER" | sed 's/^/  - /' | tr '\n' ';' | sed 's/;$//;s/;/ /g')
    MESSAGES="${MESSAGES}ARIA ACTIVE — Compaction wiped context. ${LEDGER_COUNT} knowledge file(s) were previously surfaced this session: ${LEDGER_LIST}. Re-Read the relevant ones (prefer recently-active topic; skip if no longer applicable) and summarize what reloaded in 1-2 sentences before continuing. Ledger preserved at ${LEDGER}. "
  fi
fi

# Block 3: re-inject the always-on rules digest.
# Compaction is the main way an always-on rule stops being always-on: the
# SessionStart injection is gone from context and nothing replaces it until the
# next session.
DIGEST="$SCRIPT_DIR/../rules/aria-rules.md"
if [ -f "$DIGEST" ]; then
  MESSAGES="${MESSAGES}
ARIA WORKING RULES — re-injected after compaction; still in force for this session.

$(cat "$DIGEST")
"
fi

# Emit single additionalContext (hooks emit one JSON per fire).
if [ -n "$MESSAGES" ]; then
  # kt_json_escape_multiline, NOT kt_json_escape: the latter strips newlines and
  # would collapse the digest above into one run-on line, silently.
  MSG=$(kt_json_escape_multiline "$MESSAGES")
  # printf, NOT echo. echo's handling of backslash escapes is
  # implementation-defined, and under sh it converts the \n sequences the escape
  # just produced BACK into real newlines — emitting invalid JSON.
  printf '{"hookSpecificOutput":{"hookEventName":"PostCompact","additionalContext":"%s"}}\n' "$MSG"
fi
