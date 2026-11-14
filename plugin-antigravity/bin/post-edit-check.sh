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
  */docs/specs/*|*/docs/plans/*|*/.claude/skills/*/templates/*) IS_PLANNING=true ;;
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
  echo '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"PLANNING PATH — abbreviated scope check. Output: [Rule 22 · Scope] OK — planning doc."}}'
else
  echo '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"POST-EDIT SCOPE CHECK — Required output after every edit. Verify: (1) scope held, (2) nothing extra touched, (3) no unnecessary rewrites, (4) matches decision, (5) secondary impact on parents/siblings/dependents. Output one of: PASS: [Rule 22 · Scope] PASS — [why + secondary status]. CONDITIONAL: [Rule 22 · Scope] PASS CONDITIONAL — [what done as planned]. Newline: Secondary: [attention]. Newline: Proposed: [action]. FAIL: [Rule 22 · Scope] FAIL — [what failed + affected]. Newline: Proposed: [fix]."}}'
fi

# SESSION.md in-progress marking (v2.23.0) — first-edit piggyback.
# Deterministic replacement for v2.22.0's soft SessionStart instruction: derives
# the project from the EDITED FILE PATH (works even when cwd is the ~/Projects
# root) and writes lastEvent: in-progress itself, rather than asking Claude to.
# Runs AFTER the scope-check response is emitted, gated on session_state, guarded
# once per (session, project) via a cache in the private state dir (see below). The write is
# fail-safe (|| true everywhere), so it never blocks or delays an edit, and a
# missing session_id degrades to a transcript-path key — never corrupts output.
if [ "$KT_SESSION_STATE" = "true" ] && [ -n "$FILE_PATH" ] && [ "$(basename "$FILE_PATH" 2>/dev/null)" != "SESSION.md" ]; then
  # Skip when the edited file IS a SESSION.md: marking would clobber a /handoff or
  # /wrapup write (flipping its handoff/wrapup state back to in-progress) and would
  # react to the producer's own writes. SESSION.md edits are state, not work.
  . "$SCRIPT_DIR/lib-session-state.sh" 2>/dev/null || true
  SS_ROOT=$(kt_ss_find_root "$FILE_PATH" 2>/dev/null) || SS_ROOT=""
  if [ -n "$SS_ROOT" ]; then
    # kt_session_key (lib-state-key.sh): accepted only as [A-Za-z0-9._-]+, never rewritten. Absent:
    # the transcript-path hash keys the cache, as before. Rejected: no key and no cache, and the
    # project is still marked (spec D3: "Mark anyway") with an EMPTY session id, so the mark keeps
    # SESSION.md's existing sessionId line and the raw id never reaches its front matter
    # (codex-hook.py maybe_mark_session_state applies the same rule).
    KT_STATE_DIR=   # an inherited value is never trusted: only the state-dir resolver sets it
    if [ -f "$SCRIPT_DIR/lib-state-key.sh" ]; then . "$SCRIPT_DIR/lib-state-key.sh"; fi
    SS_SID=$(kt_session_key "$INPUT" session_id 2>/dev/null); _ss_rc=$?
    if [ -n "$SS_SID" ]; then
      SS_KEY="$SS_SID"
    elif [ "$_ss_rc" = 2 ]; then
      SS_KEY=""
    else
      SS_TP=$(echo "$INPUT" | grep -o '"transcript_path":"[^"]*"' | head -1 | sed 's/"transcript_path":"//;s/"//')
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
      # ⛔ THE EDIT-TIME AUTO-CONSUME WAS REMOVED 2026-09-17 (Mike's ruling: "no new post
      # or pre edit hook checks; the only hooks for this should be on session start").
      # DO NOT REINSTATE IT, in any narrowed form. It called
      # kt_ss_ledger_mark_consumed(root, front-matter sid, now, this sid) whenever a
      # DIFFERENT session made its first edit in a project whose lastEvent was `handoff`
      # -- i.e. it inferred "someone resumed this prompt" from "someone edited a file
      # here", which is not the same event. Three measured problems:
      #   1. It could not reach the ACTIVE prompt at all (mark_consumed rewrites only
      #      `### ` headers), so on the common case it was a silent no-op returning 0 --
      #      one real ledger held 142 entries, 0 ever marked consumed.
      #   2. Where it COULD fire (a Pending entry sharing the front-matter sid -- 1 of 62
      #      live ledgers at removal time) it retired a handoff nobody had read.
      #   3. It passed no `at`, so one sid carrying two timestamps retired both.
      # Consumption now happens ONLY on the session-start path, driven by an
      # `aria-handoff:` token actually present in the pasted opener -- evidence that a
      # human resumed the prompt -- via kt_ss_ledger_consume_active. See
      # bin/session-start-check.sh and rules/aria-rules.md (SESSION STATE).
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
