#!/bin/sh
# post-edit-check.sh — PostToolUse hook for Edit|Write
# Allows abbreviated scope check for planning paths.
#
# v2.10.6: non-planning additionalContext trimmed per Draft C.
# All 5 verification questions and all 3 format templates (PASS, CONDITIONAL,
# FAIL) preserved. Only redundant prose removed. Saves ~150 chars per edit.

# Read the tool input to get the file path
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"//')

# Planning paths where abbreviated scope check is permitted
IS_PLANNING=false
case "$FILE_PATH" in
  */docs/specs/*|*/docs/plans/*|*/docs/superpowers/specs/*|*/docs/superpowers/plans/*) IS_PLANNING=true ;;
esac

# Protected filenames that always require full scope check
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
    PREFIX=$(echo "$PATTERN" | sed 's|/\*$||;s|\*$||;s/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$PREFIX" ] && continue
    case "$FILE_PATH" in
      */"$PREFIX"/*) IS_PROTECTED=true; break ;;
    esac
  done
  IFS="$OLD_IFS"
fi

if [ "$IS_PLANNING" = "true" ] && [ "$IS_PROTECTED" = "false" ]; then
  echo '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"PLANNING PATH — abbreviated scope check. Output: [Rule 22 · Scope] OK — planning doc."}}'
else
  echo '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"POST-EDIT SCOPE CHECK — Required output after every edit. Verify: (1) scope held, (2) nothing extra touched, (3) no unnecessary rewrites, (4) matches decision, (5) secondary impact on parents/siblings/dependents. Output one of: PASS: [Rule 22 · Scope] PASS — [why + secondary status]. CONDITIONAL: [Rule 22 · Scope] PASS CONDITIONAL — [what done as planned]. Newline: Secondary: [attention]. Newline: Proposed: [action]. FAIL: [Rule 22 · Scope] FAIL — [what failed + affected]. Newline: Proposed: [fix]."}}'
fi

# SESSION.md in-progress marking (2.24.2-codex.0) — fallback shell path.
# The active Codex adapter implements this in codex-hook.py for multi-file
# apply_patch calls. Keep this script current for direct/synthetic invocations.
if [ "$KT_SESSION_STATE" = "true" ] && [ -n "$FILE_PATH" ] && [ "$(basename "$FILE_PATH" 2>/dev/null)" != "SESSION.md" ]; then
  . "$SCRIPT_DIR/lib-session-state.sh" 2>/dev/null || true
  SS_ROOT=$(kt_ss_find_root "$FILE_PATH" 2>/dev/null) || SS_ROOT=""
  if [ -n "$SS_ROOT" ]; then
    SS_SID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')
    [ -z "$SS_SID" ] && SS_SID=$(echo "$INPUT" | grep -o '"turn_id":"[^"]*"' | head -1 | sed 's/"turn_id":"//;s/"//')
    if [ -n "$SS_SID" ]; then
      SS_KEY="$SS_SID"
    else
      SS_TP=$(echo "$INPUT" | grep -o '"transcript_path":"[^"]*"' | head -1 | sed 's/"transcript_path":"//;s/"//')
      SS_KEY=$(printf '%s' "${SS_TP:-nosession}" | cksum | cut -d' ' -f1)
    fi
    SS_LEDGER="/tmp/aria-session-inprogress-codex-${SS_KEY}"
    if ! { [ -f "$SS_LEDGER" ] && grep -qxF "$SS_ROOT" "$SS_LEDGER" 2>/dev/null; }; then
      SS_AUTHOR=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" 2>/dev/null | grep '^author_tag:' | sed 's/^author_tag: *//')
      kt_ss_mark_inprogress "$SS_ROOT" "$SS_SID" "$SS_AUTHOR" 2>/dev/null || true
      printf '%s\n' "$SS_ROOT" >> "$SS_LEDGER" 2>/dev/null || true
    fi
  fi
fi
