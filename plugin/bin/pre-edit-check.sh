#!/bin/sh
# pre-edit-check.sh — PreToolUse hook for Edit|Write
# Checks if the file being edited is in a planning path.
# If so, allows abbreviated assessment per change-decision-framework.md.
# Otherwise, requires full assessment.

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

# Detect structural signals (advisory hints for full CHANGE DECISION CHECK branch)
SIGNALS=$(kt_detect_signals "$FILE_PATH")
SIGNAL_PREFIX=""
[ -n "$SIGNALS" ] && SIGNAL_PREFIX="Structural signals: ${SIGNALS}. "

if [ "$IS_PLANNING" = "true" ] && [ "$IS_PROTECTED" = "false" ]; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"PLANNING PATH — abbreviated assessment permitted. Output: Planning edit — [filename]. If this file is NOT a planning/spec document, STOP and use the full assessment per change-decision-framework.md instead."}}'
else
  MAIN_MSG='CHANGE DECISION CHECK (change-decision-framework.md) — Output this REQUIRED format before proceeding: Assess impact: HIGH (behavior, architecture, key logic, many dependents) or LOW (content, simple functions, docs). --- HIGH IMPACT FORMAT: Line 1: High Impact — [what] ([why high]). Then one line each: Change — [what + context]. Intake — [information gathered]. Criteria — [objective basis]. Solutions — [all options ranked, best first]. Rank — [winner + why]. Validate — [does it hold up? contradictions?]. Execute — [precise scope]. FLAG if Validate or Execute fails and newline with Proposed: or Question: for next step. --- LOW IMPACT FORMAT: Line 1: Low Impact — [what] ([why low]). Then: Change — [what + intake + criteria in one line]. Solutions — [options ranked, best first]. Execute — [decision; scope check, secondary impact check, functional impact]. If Execute flags: add FLAG and newline with Proposed: or Question: for clarification needed. --- If you have not completed this assessment, STOP and do so before proceeding.'
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s%s"}}\n' "$SIGNAL_PREFIX" "$MAIN_MSG"
fi
