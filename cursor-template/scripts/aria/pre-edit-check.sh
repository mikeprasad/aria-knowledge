#!/bin/sh
# pre-edit-check.sh — beforeFileEdit hook for Cursor (port of Claude Code's PreToolUse:Edit|Write)
#
# Cursor port notes:
#   - Cursor payload uses camelCase (filePath, sessionId); fallback to snake_case during testing.
#   - Cursor does not expose a transcript file to hooks, so the Python turn-scoped
#     compliance scan from the Claude Code version has been removed. Rule 22 enforcement
#     shifts to instruction-based via AGENTS.md and .cursor/rules/aria-rule-22.mdc.
#   - Output uses agentMessage / permission:deny rather than systemMessage / permissionDecision.
#
# Decision hierarchy (path classification — unchanged from Claude Code version):
#   1. Planning path (and not protected)              -> abbreviated variant expected
#   2. Protected path                                  -> full variant expected
#   3. Active batch manifest + match:
#      a. Declared low-impact + no structural signals -> batch variant expected
#      b. Declared low-impact + signals detected      -> full variant (signal override)
#      c. Declared high-impact                        -> full variant (declared high)
#   4. Active batch manifest + no match               -> full variant (scope-drift)
#   5. No active batch manifest                       -> full variant
#
# Safety: fail-open on any detector or parse failure. Never block an edit due
# to hook error. The worst case degrades to allow-without-enforcement, not
# to over-blocking.

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

# Debug log: confirms hook fires (Cursor port verification)
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $0 fired" >> /tmp/aria-hook-debug.log 2>/dev/null

# Cursor uses camelCase; fallback to snake_case during testing
FILE_PATH=$(echo "$INPUT" | grep -o '"filePath":"[^"]*"' | head -1 | sed 's/"filePath":"//;s/"//')
[ -z "$FILE_PATH" ] && FILE_PATH=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"//')

SESSION_ID=$(echo "$INPUT" | grep -o '"sessionId":"[^"]*"' | head -1 | sed 's/"sessionId":"//;s/"//')
[ -z "$SESSION_ID" ] && SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')

# Planning paths where abbreviated assessment is permitted
IS_PLANNING=false
case "$FILE_PATH" in
  */docs/specs/*|*/docs/plans/*) IS_PLANNING=true ;;
esac

# Protected filenames that always require full assessment (Cursor port: AGENTS.md/hooks.json)
IS_PROTECTED=false
BASENAME=$(basename "$FILE_PATH" 2>/dev/null)
case "$BASENAME" in
  AGENTS.md|working-rules.md|change-decision-framework.md|enforcement-mechanisms.md|hooks.json)
    IS_PROTECTED=true ;;
esac

# Structural signals (auth, migration, model, routing, external-service) —
# v2.10.0 promoted signals to override batch-manifest low-impact declarations.
SIGNALS=$(kt_detect_signals "$FILE_PATH")

# Batch manifest match (empty if no active manifest or no match for this file)
BATCH_MATCH=$(kt_batch_find_match "$FILE_PATH")
BATCH_IMPACT=""
if [ -n "$BATCH_MATCH" ]; then
  BATCH_IMPACT=$(printf '%s' "$BATCH_MATCH" | cut -d'|' -f1)
fi

# Knowledge folder protection — v2.10.1 conditional: declared-low batch match
# with NO structural signals allows the file through to batch compression.
if [ "$KT_CONFIGURED" = "true" ] && [ -n "$KT_KNOWLEDGE_FOLDER" ]; then
  case "$FILE_PATH" in
    "$KT_KNOWLEDGE_FOLDER"/*)
      if [ "$BATCH_IMPACT" != "low" ] || [ -n "$SIGNALS" ]; then
        IS_PROTECTED=true
      fi
      ;;
  esac
fi

# User-declared critical paths (always protected, no batch override)
if [ "$KT_CONFIGURED" = "true" ] && [ -n "$KT_CRITICAL_PATHS" ] && [ "$IS_PROTECTED" = "false" ]; then
  OLD_IFS="$IFS"
  IFS=','
  for PATTERN in $KT_CRITICAL_PATHS; do
    PREFIX=$(echo "$PATTERN" | sed 's|/\*$||;s|\*$||;s/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$PREFIX" ] && continue
    case "$FILE_PATH" in
      */"$PREFIX"/*) IS_PROTECTED=true; break ;;
    esac
  done
  IFS="$OLD_IFS"
fi

# Determine which variant is expected for this edit
EXPECTED="full"
if [ "$IS_PLANNING" = "true" ] && [ "$IS_PROTECTED" = "false" ]; then
  EXPECTED="planning"
elif [ "$IS_PROTECTED" = "false" ] && [ -z "$SIGNALS" ] && [ -n "$BATCH_MATCH" ] && [ "$BATCH_IMPACT" = "low" ]; then
  EXPECTED="batch"
fi

# Cursor port: no transcript access, so we cannot structurally verify compliance.
# Rule 22 enforcement is now instruction-based (see AGENTS.md and aria-rule-22.mdc).
# The hook fires before every edit and emits a recovery-style reminder via agentMessage
# describing the expected format for this edit's tier. Cursor's agent reads this and
# is expected to emit the [Rule 22] block above the Edit/Write in the same turn.

case "$EXPECTED" in
  planning)
    FMT='[Rule 22 · Planning] <filename>'
    ;;
  batch)
    BATCH_IDX=$(printf '%s' "$BATCH_MATCH" | cut -d'|' -f4)
    BATCH_TOTAL=$(printf '%s' "$BATCH_MATCH" | cut -d'|' -f5)
    FMT="[Rule 22 · Batch ${BATCH_IDX}/${BATCH_TOTAL}] <filename> per declared scope."
    ;;
  *)
    FMT='[Rule 22] Low Impact — <change> (<why low>) / Change — ... / Solutions — ... / Execute — ...  OR  [Rule 22] High Impact — <change> (<why high>) with full 7-step format per rules/change-decision-framework.md'
    ;;
esac

SIGNAL_NOTE=""
[ -n "$SIGNALS" ] && SIGNAL_NOTE=" Structural signals detected (${SIGNALS}) — full assessment required regardless of batch declaration."

# Edit-intent marker check (Cursor parity equivalent for prospective Rule 22 enforcement).
# Cursor has no transcript access, so we can't structurally verify the [Rule 22] block
# was emitted above the tool call. Instead, AGENTS.md and aria-rule-22.mdc instruct
# agents to run scripts/aria/record-edit-intent.sh before each Edit/Write — this hook
# verifies a recent matching marker for the same file (and, when present, the same
# session) exists. Missing / stale / mismatched markers escalate the advisory wording.
# Cursor's hooks plan does not document a stable agent-side deny for beforeFileEdit,
# so this remains advisory — protected-file edits get the strongest wording.
INTENT_STATUS="ok"
INTENT_FILE="${KT_EDIT_INTENT_FILE:-$KT_ROOT/.cursor/aria-edit-intent.json}"
INTENT_MAX_AGE=600  # 10 minutes
if [ "${KT_EDIT_INTENT:-true}" = "true" ] && [ -n "$FILE_PATH" ]; then
  if [ ! -f "$INTENT_FILE" ]; then
    INTENT_STATUS="missing"
  else
    INTENT_FP=$(grep -o '"filePath":"[^"]*"' "$INTENT_FILE" 2>/dev/null | head -1 | sed 's/"filePath":"//;s/"$//')
    INTENT_SID=$(grep -o '"sessionId":"[^"]*"' "$INTENT_FILE" 2>/dev/null | head -1 | sed 's/"sessionId":"//;s/"$//')
    INTENT_TS=$(grep -o '"timestamp":[0-9]*' "$INTENT_FILE" 2>/dev/null | head -1 | sed 's/"timestamp"://')
    NOW_EPOCH=$(date +%s)
    AGE=0
    if [ -n "$INTENT_TS" ] && [ -n "$NOW_EPOCH" ]; then
      AGE=$((NOW_EPOCH - INTENT_TS))
    else
      AGE=$((INTENT_MAX_AGE + 1))
    fi

    if [ "$INTENT_FP" != "$FILE_PATH" ]; then
      INTENT_STATUS="mismatch"
    elif [ "$AGE" -gt "$INTENT_MAX_AGE" ]; then
      INTENT_STATUS="stale"
    elif [ -n "$SESSION_ID" ] && [ -n "$INTENT_SID" ] && [ "$INTENT_SID" != "manual" ] && [ "$INTENT_SID" != "$SESSION_ID" ]; then
      INTENT_STATUS="mismatch"
    fi
  fi
fi

INTENT_NOTE=""
# Build the intent note. For protected files and meaningful edits, escalate the
# wording — Cursor advisory only (no agent-side deny in the documented hooks plan).
case "$INTENT_STATUS" in
  missing)
    if [ "$IS_PROTECTED" = "true" ]; then
      INTENT_NOTE=" PROTECTED FILE + NO EDIT-INTENT MARKER: run \`bash scripts/aria/record-edit-intent.sh <filePath> rule22-high \"<rationale>\"\` BEFORE this Edit/Write, emit the [Rule 22] block above the tool call, then proceed. Skipping is a Rule 22 violation."
    else
      INTENT_NOTE=" No recent edit-intent marker found. Before invoking Edit/Write, run \`bash scripts/aria/record-edit-intent.sh <filePath> rule22-low|rule22-high \"<rationale>\"\` and emit the [Rule 22] block in the same turn above the tool call."
    fi
    ;;
  stale)
    INTENT_NOTE=" Edit-intent marker is stale (>10 min old). Re-record via \`bash scripts/aria/record-edit-intent.sh\` for this specific edit before proceeding — a stale marker means the Rule 22 reasoning may not match the current change."
    ;;
  mismatch)
    INTENT_NOTE=" Edit-intent marker does not match this file or session. Re-record via \`bash scripts/aria/record-edit-intent.sh <filePath>\` for the file you are about to edit."
    ;;
  ok)
    : # silent on success
    ;;
esac

REASON="Rule 22 reminder: emit the [Rule 22] marker as a text output (not thinking) ABOVE this Edit/Write tool call in the same assistant turn, between the previous Edit/Write (if any) and this one.${SIGNAL_NOTE}${INTENT_NOTE} Format: ${FMT}. See rules/change-decision-framework.md 'Ordering (required)'."
REASON_ESCAPED=$(kt_json_escape "$REASON")

# Cursor agentMessage output — instruction-based reminder, never blocks the edit.
printf '{"agentMessage":"%s"}\n' "$REASON_ESCAPED"
