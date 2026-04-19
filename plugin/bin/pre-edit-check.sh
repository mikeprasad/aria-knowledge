#!/bin/sh
# pre-edit-check.sh — PreToolUse hook for Edit|Write
#
# v2.10.5: compliance-detecting blocker. Reads the current assistant turn from
# transcript_path; if a [Rule 22...] marker appears in a text block preceding
# the Edit/Write tool_use, allow silently. Otherwise deny with permissionDecision
# so Claude retries with the block emitted prospectively. This eliminates the
# duplicate-emission failure mode observed under Claude 4.7 where the v2.10.4
# "output retroactively AND prospectively" instruction was read as unconditional,
# causing ~200-400 wasted tokens per edit. The retroactive path is unreachable
# by construction — there is no "AND" clause to duplicate.
#
# Decision hierarchy (path classification — unchanged from v2.10.x):
#   1. Planning path (and not protected)              -> abbreviated variant expected
#   2. Protected path                                  -> full variant expected
#   3. Active batch manifest + match:
#      a. Declared low-impact + no structural signals -> batch variant expected
#      b. Declared low-impact + signals detected      -> full variant (signal override)
#      c. Declared high-impact                        -> full variant (declared high)
#   4. Active batch manifest + no match               -> full variant (scope-drift)
#   5. No active batch manifest                       -> full variant
#
# Every expected variant is marked with [Rule 22] or [Rule 22 · <sub>] on its
# header line, so a single regex detects compliance across all paths.
#
# Safety: fail-open on any detector or parse failure. Never block an edit due
# to hook error. The worst case degrades to v2.10.4 behavior (allow without
# enforcement), not to over-blocking.

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

FILE_PATH=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"//')
TRANSCRIPT=$(echo "$INPUT" | grep -o '"transcript_path":"[^"]*"' | head -1 | sed 's/"transcript_path":"//;s/"//')
TOOL_USE_ID=$(echo "$INPUT" | grep -o '"tool_use_id":"[^"]*"' | head -1 | sed 's/"tool_use_id":"//;s/"//')

# Planning paths where abbreviated assessment is permitted
IS_PLANNING=false
case "$FILE_PATH" in
  */docs/specs/*|*/docs/plans/*) IS_PLANNING=true ;;
esac

# Protected filenames that always require full assessment
IS_PROTECTED=false
BASENAME=$(basename "$FILE_PATH" 2>/dev/null)
case "$BASENAME" in
  CLAUDE.md|working-rules.md|change-decision-framework.md|enforcement-mechanisms.md|settings.local.json|plugin.json)
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

# Compliance detection: parse transcript, find this tool_use's assistant message,
# check text blocks BEFORE the tool_use for the [Rule 22] marker.
COMPLIANT="unknown"
if [ -n "$TRANSCRIPT" ] && [ -n "$TOOL_USE_ID" ] && [ -f "$TRANSCRIPT" ]; then
  COMPLIANT=$(TRANSCRIPT="$TRANSCRIPT" TOOL_USE_ID="$TOOL_USE_ID" python3 - <<'PY' 2>/dev/null
import json, os, re, sys
try:
    path = os.environ["TRANSCRIPT"]
    tool_use_id = os.environ["TOOL_USE_ID"]
    MARKER = re.compile(r"\[Rule 22(\s·\s[^\]]+)?\]")
    with open(path) as f:
        lines = f.readlines()
    for line in reversed(lines):
        try:
            evt = json.loads(line)
        except Exception:
            continue
        if evt.get("type") != "assistant":
            continue
        content = evt.get("message", {}).get("content", [])
        if not isinstance(content, list):
            continue
        idx = None
        for i, b in enumerate(content):
            if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("id") == tool_use_id:
                idx = i
                break
        if idx is None:
            continue
        for b in content[:idx]:
            if isinstance(b, dict) and b.get("type") == "text" and MARKER.search(b.get("text", "")):
                print("yes")
                sys.exit(0)
        print("no")
        sys.exit(0)
    print("unknown")
except Exception:
    print("unknown")
PY
  )
  # Coerce empty stdout to "unknown" (python crashed before printing)
  [ -z "$COMPLIANT" ] && COMPLIANT="unknown"
fi

# Fail-open: allow silently when compliant or when we couldn't verify.
if [ "$COMPLIANT" = "yes" ] || [ "$COMPLIANT" = "unknown" ]; then
  exit 0
fi

# Non-compliant: deny with a concise recovery message naming the expected format
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

REASON="Rule 22 compliance block missing before this Edit/Write. Emit the block ABOVE the tool call in the same assistant turn, then retry the edit.${SIGNAL_NOTE} Expected format for this edit: ${FMT}. See rules/change-decision-framework.md \"Ordering (required)\"."
REASON_ESCAPED=$(kt_json_escape "$REASON")

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$REASON_ESCAPED"
