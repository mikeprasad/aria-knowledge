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
# Hook debug log (spec §5; 2.58.0 D4): <state dir>/aria-hook-debug.log, in the private per-user state
# directory from lib-state-key.sh. With no state directory nothing is logged (spec D3) and the
# path is empty. aria_hook_dbg builds the line first, creates the log only with kt_create_new,
# and appends only when it is a regular file of ours that is not a link (lib-tracked-artifacts.sh
# only defines functions; without it nothing is logged). KT_HOOK_DEBUG_LOG is a TEST-ONLY override
# of the path. Identical in pre-edit-check.sh, post-edit-check.sh, capture-task-boundary.sh and
# record-edit-intent.sh (tests/repros/safe-create-census.sh CC1b).
. "$SCRIPT_DIR/lib-tracked-artifacts.sh" 2>/dev/null || true
KT_STATE_DIR=   # an inherited value is never trusted: only the state-dir resolver sets it
if [ -f "$SCRIPT_DIR/lib-state-key.sh" ]; then . "$SCRIPT_DIR/lib-state-key.sh"; fi
ARIA_HOOK_DEBUG_LOG=${KT_HOOK_DEBUG_LOG:-}
if [ -z "$ARIA_HOOK_DEBUG_LOG" ] && kt_state_resolve 2>/dev/null; then
  ARIA_HOOK_DEBUG_LOG=$(kt_state_path aria-hook-debug.log) || ARIA_HOOK_DEBUG_LOG=
fi
aria_hook_dbg() {
  [ -n "$ARIA_HOOK_DEBUG_LOG" ] || return 0
  _ahd_l="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) $*"
  [ -e "$ARIA_HOOK_DEBUG_LOG" ] || [ -L "$ARIA_HOOK_DEBUG_LOG" ] || kt_create_new "$ARIA_HOOK_DEBUG_LOG" 2>/dev/null || :
  kt_is_ours "$ARIA_HOOK_DEBUG_LOG" 2>/dev/null || return 0
  printf '%s\n' "$_ahd_l" >> "$ARIA_HOOK_DEBUG_LOG" 2>/dev/null
  return 0
}

# Debug log: confirms hook fires (Cursor port verification)
aria_hook_dbg "$0 fired"

# Cursor uses camelCase; fallback to snake_case during testing
FILE_PATH=$(echo "$INPUT" | grep -o '"filePath":"[^"]*"' | head -1 | sed 's/"filePath":"//;s/"//')
[ -z "$FILE_PATH" ] && FILE_PATH=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"//')

# Edit-intent marker handling. If a marker exists and matches the file just
# edited, log the consumption and remove the file so subsequent edits must
# record fresh intent. Mismatches are logged but not removed (they belong to
# a different file/session). Logged to the hook debug log only — never
# emitted in agentMessage so we don't confuse the scope-check format.
INTENT_FILE="${KT_EDIT_INTENT_FILE:-$KT_ROOT/.cursor/aria-edit-intent.json}"
if [ -f "$INTENT_FILE" ] && [ -n "$FILE_PATH" ]; then
  INTENT_FP=$(grep -o '"filePath":"[^"]*"' "$INTENT_FILE" 2>/dev/null | head -1 | sed 's/"filePath":"//;s/"$//')
  INTENT_MARKER=$(grep -o '"marker":"[^"]*"' "$INTENT_FILE" 2>/dev/null | head -1 | sed 's/"marker":"//;s/"$//')
  if [ "$INTENT_FP" = "$FILE_PATH" ]; then
    aria_hook_dbg "$0 consumed intent marker ($INTENT_MARKER) for $FILE_PATH"
    rm -f "$INTENT_FILE" 2>/dev/null
  else
    aria_hook_dbg "$0 intent marker mismatch (had=$INTENT_FP, edited=$FILE_PATH) — left in place"
  fi
else
  aria_hook_dbg "$0 no intent marker present for $FILE_PATH"
fi

# Planning paths where abbreviated scope check is permitted
IS_PLANNING=false
case "$FILE_PATH" in
  */docs/specs/*|*/docs/plans/*|*/docs/superpowers/specs/*|*/docs/superpowers/plans/*|*/.cursor/skills/*/templates/*|*/.claude/skills/*/templates/*) IS_PLANNING=true ;;
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

# User-declared planning paths (inverse of critical_paths). Mirrors pre-edit-check.sh
# so the scope-check advisory matches the pre-hook's planning decision. Protect wins
# (the decision below only honors planning when IS_PROTECTED=false).
if [ "$KT_CONFIGURED" = "true" ] && [ -n "$KT_PLANNING_PATHS" ] && [ "$IS_PLANNING" = "false" ]; then
  OLD_IFS="$IFS"
  IFS=','
  for PATTERN in $KT_PLANNING_PATHS; do
    PREFIX=$(echo "$PATTERN" | sed 's|/\*$||;s|\*$||;s/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$PREFIX" ] && continue
    case "$FILE_PATH" in
      */"$PREFIX"/*) IS_PLANNING=true; break ;;
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

# SESSION.md in-progress marking (v2.23.0) — first-edit piggyback on afterFileEdit.
if [ "$KT_SESSION_STATE" = "true" ] && [ -n "$FILE_PATH" ] && [ "$(basename "$FILE_PATH" 2>/dev/null)" != "SESSION.md" ]; then
  . "$SCRIPT_DIR/lib-session-state.sh" 2>/dev/null || true
  SS_ROOT=$(kt_ss_find_root "$FILE_PATH" 2>/dev/null) || SS_ROOT=""
  if [ -n "$SS_ROOT" ]; then
    # kt_session_key (lib-state-key.sh): accepted only as [A-Za-z0-9._-]+, never rewritten. Absent:
    # the transcript-path hash keys the cache, as before. Rejected: no key and no cache, and the
    # project is still marked (spec D3: "Mark anyway") with an EMPTY session id, so the mark keeps
    # SESSION.md's existing sessionId line and the raw id never reaches its front matter
    # (codex-hook.py maybe_mark_session_state applies the same rule).
    if [ -f "$SCRIPT_DIR/lib-state-key.sh" ]; then . "$SCRIPT_DIR/lib-state-key.sh"; fi
    SS_SID=$(kt_session_key "$INPUT" sessionId session_id 2>/dev/null); _ss_rc=$?
    if [ -n "$SS_SID" ]; then
      SS_KEY="$SS_SID"
    elif [ "$_ss_rc" = 2 ]; then
      SS_KEY=""
    else
      SS_TP=$(echo "$INPUT" | grep -o '"transcriptPath":"[^"]*"' | head -1 | sed 's/"transcriptPath":"//;s/"//')
      [ -z "$SS_TP" ] && SS_TP=$(echo "$INPUT" | grep -o '"transcript_path":"[^"]*"' | head -1 | sed 's/"transcript_path":"//;s/"//')
      SS_KEY=$(printf '%s' "${SS_TP:-nosession}" | cksum | cut -d' ' -f1)
    fi
    # 2.58.0: the once-per-(session, project) cache lives in the private per-user state directory
    # (lib-state-key.sh); the id goes through kt_state_path, which refuses one with a "/". It is read
    # and appended to only when it is a regular file of ours that is not a link, and created only by
    # kt_create_new, from lib-tracked-artifacts.sh (which only defines functions).
    # With no usable cache — no state directory (spec D3), a refused id, or that lib missing — the
    # project is marked ANYWAY, guarded by one read of SESSION.md: when its front matter already
    # reads lastEvent: in-progress under THIS session id the mark is skipped, so the file is written
    # once, not on every edit (the mark refreshes `at:`, so re-running it is not byte-idempotent).
    SS_LEDGER=
    if [ -f "$SCRIPT_DIR/lib-state-key.sh" ]; then . "$SCRIPT_DIR/lib-state-key.sh"; fi
    if kt_state_resolve 2>/dev/null; then
      [ -n "$SS_KEY" ] && SS_LEDGER=$(kt_state_path "aria-session-inprogress-${SS_KEY}") || SS_LEDGER=
    fi
    . "$SCRIPT_DIR/lib-tracked-artifacts.sh" 2>/dev/null || true
    if [ -n "$SS_LEDGER" ] && kt_is_ours "$SS_LEDGER" 2>/dev/null && grep -qxF "$SS_ROOT" "$SS_LEDGER" 2>/dev/null; then
      :   # this session already marked this project
    elif [ -z "$SS_LEDGER" ] && [ -n "$SS_SID" ] && [ -f "$SS_ROOT/SESSION.md" ] && awk -v sid="$SS_SID" '
        NR == 1 { if ($0 != "---") exit 1; next }
        $0 == "---" { ok = (le == "in-progress" && si == sid); done = 1; exit }
        !gle && /^lastEvent:/ { le = $0; sub(/^lastEvent:[ ]*/, "", le); gle = 1 }
        !gsi && /^sessionId:/ { si = $0; sub(/^sessionId:[ ]*/, "", si); gsi = 1 }
        END { exit (done && ok) ? 0 : 1 }' "$SS_ROOT/SESSION.md" 2>/dev/null; then
      :   # no cache, and SESSION.md already carries this session's mark
    else
      # Consume a prior handoff before flipping to in-progress (latch-clear on resume).
      # (v2.53.2 parity) Handoff consumption is NOT inferred from an edit — it happens only on
      # the session-start resume path, keyed on an aria-handoff token in the opener.
      SS_AUTHOR=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" 2>/dev/null | grep '^author_tag:' | sed 's/^author_tag: *//')
      kt_ss_mark_inprogress "$SS_ROOT" "$SS_SID" "$SS_AUTHOR" 2>/dev/null || true
      if [ -n "$SS_LEDGER" ]; then
        [ -e "$SS_LEDGER" ] || [ -L "$SS_LEDGER" ] || kt_create_new "$SS_LEDGER" 2>/dev/null || :
        if kt_is_ours "$SS_LEDGER" 2>/dev/null; then
          printf '%s\n' "$SS_ROOT" >> "$SS_LEDGER" 2>/dev/null || true
        fi
      fi
    fi
  fi
fi
