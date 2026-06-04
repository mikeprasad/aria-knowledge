#!/bin/sh
# pre-edit-check.sh — PreToolUse hook for Edit|Write
#
# v2.10.6: turn-scoped compliance detection. Walks backward through the
# transcript's assistant messages, collecting text blocks up to (but not
# including) the previous Edit/Write tool_use or the previous user message —
# whichever comes first. Scans those text blocks for a [Rule 22...] marker.
#
# v2.10.5 scanned `content[:idx]` within a single assistant message. Under
# Opus 4.7, the harness splits text and tool_use into separate assistant
# messages, so the same-message scan never found the marker and denied every
# edit (deadlock). v2.10.6 fixes this by walking turn-scope instead — matching
# the framework doc's "same assistant turn" semantic. Per-edit requirement is
# preserved because the walk stops at the previous Edit/Write tool_use, so
# each edit still needs its own dedicated marker emitted after the prior edit.
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
# to hook error. The worst case degrades to allow-without-enforcement, not
# to over-blocking.

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

FILE_PATH=$(echo "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"//')
TRANSCRIPT=$(echo "$INPUT" | grep -o '"transcript_path":"[^"]*"' | head -1 | sed 's/"transcript_path":"//;s/"//')
TOOL_USE_ID=$(echo "$INPUT" | grep -o '"tool_use_id":"[^"]*"' | head -1 | sed 's/"tool_use_id":"//;s/"//')

# Planning paths where abbreviated assessment is permitted
IS_PLANNING=false
case "$FILE_PATH" in
  */docs/specs/*|*/docs/plans/*|*/docs/superpowers/specs/*|*/docs/superpowers/plans/*) IS_PLANNING=true ;;
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

# Compliance detection (v2.10.6): parse transcript, walk BACKWARD through
# assistant messages from the one containing our tool_use, collecting text
# blocks until we hit either (a) the previous Edit/Write tool_use, or (b)
# a user message — whichever is first. Scan those text blocks for the marker.
# This matches the framework doc's "same assistant turn" semantic, which
# under 4.7's split-message harness spans multiple assistant messages.
COMPLIANT="unknown"
if [ -n "$TRANSCRIPT" ] && [ -n "$TOOL_USE_ID" ] && [ -f "$TRANSCRIPT" ]; then
  COMPLIANT=$(TRANSCRIPT="$TRANSCRIPT" TOOL_USE_ID="$TOOL_USE_ID" python3 - <<'PY' 2>/dev/null
import json, os, re, sys
try:
    path = os.environ["TRANSCRIPT"]
    tool_use_id = os.environ["TOOL_USE_ID"]
    MARKER = re.compile(r"\[Rule 22(\s\xb7\s[^\]]+)?\]")
    with open(path) as f:
        lines = f.readlines()

    # First pass: find the assistant message containing our tool_use_id.
    # Record its line index and the position of the tool_use within its content.
    target_line_idx = None
    target_content_idx = None
    for i, line in enumerate(lines):
        try:
            evt = json.loads(line)
        except Exception:
            continue
        if evt.get("type") != "assistant":
            continue
        content = evt.get("message", {}).get("content", [])
        if not isinstance(content, list):
            continue
        for j, b in enumerate(content):
            if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("id") == tool_use_id:
                target_line_idx = i
                target_content_idx = j
                break
        if target_line_idx is not None:
            break

    if target_line_idx is None:
        print("unknown")
        sys.exit(0)

    # Second pass: walk backward collecting text blocks from the turn window.
    # Turn window = from target tool_use back to either the previous Edit/Write
    # tool_use or a user message (whichever is encountered first).
    #
    # Within the target message, scan content[:target_content_idx] for text
    # blocks and also check for a previous Edit/Write tool_use that would
    # cap the walk early.
    found_prior_edit_in_target_msg = False
    text_blocks = []

    target_evt = json.loads(lines[target_line_idx])
    target_content = target_evt["message"]["content"]
    for b in target_content[:target_content_idx]:
        if isinstance(b, dict):
            if b.get("type") == "tool_use" and b.get("name") in ("Edit", "Write"):
                # A prior Edit/Write in the same message caps the walk.
                # Reset collected text blocks (none of them belong to this edit).
                text_blocks = []
                found_prior_edit_in_target_msg = True
            elif b.get("type") == "text":
                text_blocks.append(b.get("text", ""))

    # If the target message didn't already cap the walk, walk backward through
    # prior lines until we hit a user message or a previous Edit/Write tool_use.
    if not found_prior_edit_in_target_msg:
        for i in range(target_line_idx - 1, -1, -1):
            try:
                evt = json.loads(lines[i])
            except Exception:
                continue
            evt_type = evt.get("type")
            if evt_type == "user":
                # v2.15.2: tool_results are also encoded as type:"user" in Claude
                # Code transcripts. They carry tool_result content blocks rather
                # than user-authored text. Walk past them — they're not turn
                # boundaries. Only stop at actual user prompts.
                user_content = evt.get("message", {}).get("content", [])
                if isinstance(user_content, list) and user_content and \
                   all(isinstance(b, dict) and b.get("type") == "tool_result" for b in user_content):
                    continue  # tool_result only — not a real user message
                # Actual user prompt → hit the turn boundary going backward.
                break
            if evt_type != "assistant":
                continue
            content = evt.get("message", {}).get("content", [])
            if not isinstance(content, list):
                continue
            # Walk this message's content in order. If it contains a prior
            # Edit/Write, only text blocks AFTER that Edit/Write belong to
            # our current turn window. Since we're walking backward across
            # messages but forward within each message, we collect this
            # message's blocks into a local list, then prepend.
            msg_text_blocks = []
            cap_reached = False
            for b in content:
                if isinstance(b, dict):
                    if b.get("type") == "tool_use" and b.get("name") in ("Edit", "Write"):
                        # Previous Edit/Write — walk stops. Discard anything
                        # collected BEFORE this Edit/Write in the same message
                        # (those belong to the prior turn window).
                        msg_text_blocks = []
                        cap_reached = True
                    elif b.get("type") == "text":
                        msg_text_blocks.append(b.get("text", ""))
            # Prepend this message's post-cap text blocks to the overall list.
            text_blocks = msg_text_blocks + text_blocks
            if cap_reached:
                break

    # Scan collected text blocks for the marker.
    for txt in text_blocks:
        if MARKER.search(txt):
            print("yes")
            sys.exit(0)
    print("no")
except Exception:
    print("unknown")
PY
  )
  # Coerce empty stdout to "unknown" (python crashed before printing)
  [ -z "$COMPLIANT" ] && COMPLIANT="unknown"
fi

# Compliant: allow silently.
if [ "$COMPLIANT" = "yes" ]; then
  exit 0
fi

# Fail-open (LOUD): the detector could not evaluate this edit. Allow the edit so
# a detector/schema break never deadlocks Codex, but surface a visible warning so
# Rule 22 enforcement is never lost silently.
if [ "$COMPLIANT" = "unknown" ]; then
  WARN="aria-knowledge Rule 22: could not verify this edit — enforcement was bypassed for it. The transcript parser may be broken (possible model/harness change). If this appears on every edit, run plugin-openai-codex/tests/run.sh and check pre-edit-check.sh against the current Codex transcript format."
  WARN_ESCAPED=$(kt_json_escape "$WARN")
  printf '{"systemMessage":"%s"}\n' "$WARN_ESCAPED"
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

REASON="Rule 22 compliance block missing. Emit the [Rule 22] marker as a text output (not thinking) ABOVE this Edit/Write tool call in the same assistant turn, between the previous Edit/Write (if any) and this one. Then retry the same tool call.${SIGNAL_NOTE} Format: ${FMT}. See rules/change-decision-framework.md 'Ordering (required)'."
REASON_ESCAPED=$(kt_json_escape "$REASON")

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$REASON_ESCAPED"
