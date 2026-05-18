#!/bin/sh
# post-edit-check.sh — afterFileEdit hook for Cursor (port of Claude Code's PostToolUse:Edit|Write)
# Allows abbreviated scope check for planning paths.
#
# Cursor port notes:
#   - Cursor payload uses camelCase (filePath); fallback to snake_case during testing.
#   - Output uses agentMessage rather than systemMessage / additionalContext.

# Read the tool input to get the file path
INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

# Debug log: confirms hook fires (Cursor port verification)
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $0 fired" >> /tmp/aria-hook-debug.log 2>/dev/null

# Cursor uses camelCase; fallback to snake_case during testing
FILE_PATH=$(echo "$INPUT" | grep -o '"filePath":"[^"]*"' | head -1 | sed 's/"filePath":"//;s/"//')
[ -z "$FILE_PATH" ] && FILE_PATH=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"//')

# Edit-intent marker handling. If a marker exists and matches the file just
# edited, log the consumption and remove the file so subsequent edits must
# record fresh intent. Mismatches are logged but not removed (they belong to
# a different file/session). Logged to /tmp/aria-hook-debug.log only — never
# emitted in agentMessage so we don't confuse the scope-check format.
INTENT_FILE="${KT_EDIT_INTENT_FILE:-$KT_ROOT/.cursor/aria-edit-intent.json}"
if [ -f "$INTENT_FILE" ] && [ -n "$FILE_PATH" ]; then
  INTENT_FP=$(grep -o '"filePath":"[^"]*"' "$INTENT_FILE" 2>/dev/null | head -1 | sed 's/"filePath":"//;s/"$//')
  INTENT_MARKER=$(grep -o '"marker":"[^"]*"' "$INTENT_FILE" 2>/dev/null | head -1 | sed 's/"marker":"//;s/"$//')
  if [ "$INTENT_FP" = "$FILE_PATH" ]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $0 consumed intent marker ($INTENT_MARKER) for $FILE_PATH" >> /tmp/aria-hook-debug.log 2>/dev/null
    rm -f "$INTENT_FILE" 2>/dev/null
  else
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $0 intent marker mismatch (had=$INTENT_FP, edited=$FILE_PATH) — left in place" >> /tmp/aria-hook-debug.log 2>/dev/null
  fi
else
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $0 no intent marker present for $FILE_PATH" >> /tmp/aria-hook-debug.log 2>/dev/null
fi

# Planning paths where abbreviated scope check is permitted
IS_PLANNING=false
case "$FILE_PATH" in
  */docs/specs/*|*/docs/plans/*) IS_PLANNING=true ;;
esac

# Protected filenames that always require full scope check (Cursor port: AGENTS.md/hooks.json)
IS_PROTECTED=false
BASENAME=$(basename "$FILE_PATH" 2>/dev/null)
case "$BASENAME" in
  AGENTS.md|working-rules.md|change-decision-framework.md|enforcement-mechanisms.md|hooks.json)
    IS_PROTECTED=true ;;
esac

# Check if file is inside the knowledge folder
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
    PREFIX=$(echo "$PATTERN" | sed 's|/\*$||;s|\*$||;s/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$PREFIX" ] && continue
    case "$FILE_PATH" in
      */"$PREFIX"/*) IS_PROTECTED=true; break ;;
    esac
  done
  IFS="$OLD_IFS"
fi

if [ "$IS_PLANNING" = "true" ] && [ "$IS_PROTECTED" = "false" ]; then
  MSG=$(kt_json_escape "PLANNING PATH — abbreviated scope check. Output: [Rule 22 · Scope] OK — planning doc.")
  printf '{"agentMessage":"%s"}\n' "$MSG"
else
  MSG=$(kt_json_escape "POST-EDIT SCOPE CHECK — Required output after every edit. Verify: (1) scope held, (2) nothing extra touched, (3) no unnecessary rewrites, (4) matches decision, (5) secondary impact on parents/siblings/dependents. Output one of: PASS: [Rule 22 · Scope] PASS — [why + secondary status]. CONDITIONAL: [Rule 22 · Scope] PASS CONDITIONAL — [what done as planned]. Newline: Secondary: [attention]. Newline: Proposed: [action]. FAIL: [Rule 22 · Scope] FAIL — [what failed + affected]. Newline: Proposed: [fix].")
  printf '{"agentMessage":"%s"}\n' "$MSG"
fi
