#!/bin/sh
# pre-edit-check.sh — PreToolUse hook for Edit|Write
#
# Decision hierarchy (most-specific first):
#   1. Planning path (and not protected) -> abbreviated assessment
#   2. Protected path -> full Rule 22 format (protection cannot be weakened
#      by batch manifests)
#   3. Active batch manifest + current file matches an op:
#      a. Declared low-impact + no structural signals -> compressed directive
#      b. Declared low-impact + signals detected -> full Rule 22 with
#         "BATCH SIGNAL OVERRIDE" prefix (signals are ground truth)
#      c. Declared high-impact -> full Rule 22 with "BATCH DECLARED-HIGH" prefix
#   4. Active batch manifest + current file does NOT match any op -> full Rule 22
#      (scope-drift detection; this is the load-bearing value-add per ADR 021)
#   5. No active batch manifest -> full Rule 22 (unchanged from pre-v2.10.0)
#
# Safety floor: layers 2, 3b, 3c, and 4 all preserve the "don't miss important
# checks" requirement. Residual risk (HIGH-impact edit without structural
# signal, mis-declared as LOW, in-scope of manifest) is documented in OVERVIEW.md.

# Read the tool input to get the file path
# The hook receives tool input via stdin as JSON
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"//')

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

# Check if file is inside the knowledge folder
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"
if [ "$KT_CONFIGURED" = "true" ] && [ -n "$KT_KNOWLEDGE_FOLDER" ]; then
  case "$FILE_PATH" in
    "$KT_KNOWLEDGE_FOLDER"/*) IS_PROTECTED=true ;;
  esac
fi

# Check user-configured critical paths (comma-separated path fragments)
if [ "$KT_CONFIGURED" = "true" ] && [ -n "$KT_CRITICAL_PATHS" ] && [ "$IS_PROTECTED" = "false" ]; then
  OLD_IFS="$IFS"
  IFS=','
  for PATTERN in $KT_CRITICAL_PATHS; do
    # Strip trailing /* or *, then trim surrounding whitespace
    PREFIX=$(echo "$PATTERN" | sed 's|/\*$||;s|\*$||;s/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$PREFIX" ] && continue
    case "$FILE_PATH" in
      */"$PREFIX"/*) IS_PROTECTED=true; break ;;
    esac
  done
  IFS="$OLD_IFS"
fi

# Detect structural signals (auth, migration, model, routing, external-service)
# In v2.10.0 these are promoted from advisory-only to having override authority
# when a batch manifest is active (any signal on a declared-low op forces full).
SIGNALS=$(kt_detect_signals "$FILE_PATH")

# Check for active batch manifest match
BATCH_MATCH=$(kt_batch_find_match "$FILE_PATH")

# Decision hierarchy — layer 1: planning path
if [ "$IS_PLANNING" = "true" ] && [ "$IS_PROTECTED" = "false" ]; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"PLANNING PATH — abbreviated assessment permitted. Output: Planning edit — [filename]. If this file is NOT a planning/spec document, STOP and use the full assessment per change-decision-framework.md instead."}}'
  exit 0
fi

# Layer 3a: batch compression path — only when NOT protected AND no structural signals
if [ "$IS_PROTECTED" = "false" ] && [ -z "$SIGNALS" ] && [ -n "$BATCH_MATCH" ]; then
  BATCH_IMPACT=$(printf '%s' "$BATCH_MATCH" | cut -d'|' -f1)
  BATCH_JUSTIFICATION=$(printf '%s' "$BATCH_MATCH" | cut -d'|' -f2)
  BATCH_PLAN=$(printf '%s' "$BATCH_MATCH" | cut -d'|' -f3)
  BATCH_IDX=$(printf '%s' "$BATCH_MATCH" | cut -d'|' -f4)
  BATCH_TOTAL=$(printf '%s' "$BATCH_MATCH" | cut -d'|' -f5)

  if [ "$BATCH_IMPACT" = "low" ]; then
    # Emit compressed directive — single-line acknowledgment expected
    BATCH_MSG=$(printf 'BATCH OPERATION (%s/%s) — declared scope: %s. Justification: %s. Acknowledge with one line: \\"Batch %s/%s — [filename] per declared scope.\\" If this edit has surprising impact or exceeds declared scope, STOP and use full CHANGE DECISION CHECK instead.' "$BATCH_IDX" "$BATCH_TOTAL" "$BATCH_PLAN" "$BATCH_JUSTIFICATION" "$BATCH_IDX" "$BATCH_TOTAL")
    BATCH_MSG_ESCAPED=$(kt_json_escape "$BATCH_MSG")
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$BATCH_MSG_ESCAPED"
    exit 0
  fi
  # Declared-high in batch falls through to full format below with HIGH prefix
fi

# Layers 2, 3b, 3c, 4, 5: full Rule 22 format with contextual prefixes
PREFIX=""
if [ -n "$BATCH_MATCH" ]; then
  BATCH_IMPACT=$(printf '%s' "$BATCH_MATCH" | cut -d'|' -f1)
  if [ "$BATCH_IMPACT" = "high" ]; then
    # Layer 3c: declared-high inside batch
    PREFIX="BATCH DECLARED-HIGH — this edit was declared high-impact in the active batch manifest; full assessment required. "
  elif [ "$BATCH_IMPACT" = "low" ] && [ -n "$SIGNALS" ]; then
    # Layer 3b: declared-low but signals detected — safety override
    PREFIX="BATCH SIGNAL OVERRIDE — this edit was declared low-impact but structural signals (${SIGNALS}) escalated it to full assessment. "
  fi
fi
[ -n "$SIGNALS" ] && [ -z "$PREFIX" ] && PREFIX="Structural signals: ${SIGNALS}. "

MAIN_MSG='CHANGE DECISION CHECK (change-decision-framework.md) — Output this REQUIRED format before proceeding: Assess impact: HIGH (behavior, architecture, key logic, many dependents) or LOW (content, simple functions, docs). --- HIGH IMPACT FORMAT: Line 1: High Impact — [what] ([why high]). Then one line each: Change — [what + context]. Intake — [information gathered]. Criteria — [objective basis]. Solutions — [all options ranked, best first]. Rank — [winner + why]. Validate — [does it hold up? contradictions?]. Execute — [precise scope]. FLAG if Validate or Execute fails and newline with Proposed: or Question: for next step. --- LOW IMPACT FORMAT: Line 1: Low Impact — [what] ([why low]). Then: Change — [what + intake + criteria in one line]. Solutions — [options ranked, best first]. Execute — [decision; scope check, secondary impact check, functional impact]. If Execute flags: add FLAG and newline with Proposed: or Question: for clarification needed. --- If you have not completed this assessment, STOP and do so before proceeding.'

FULL_MSG="${PREFIX}${MAIN_MSG}"
FULL_MSG_ESCAPED=$(kt_json_escape "$FULL_MSG")
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$FULL_MSG_ESCAPED"
