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
# v2.30.0: deny-rate circuit breaker. A per-session counter trips after 3
# consecutive denials with zero intervening compliant edits, after which edits
# are ALLOWED with a loud degraded-mode warning instead of deadlocking. This
# converts the "confident-no deny loop" failure class (a transcript-format
# change that parses fine but shifts semantics, yielding "no" -> deny -> deadlock)
# into self-healing fail-open: a single compliant edit deletes the counter and
# restores blocking enforcement. Model-agnostic — no per-model parser patch.
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
STEP_INDEX=$(echo "$INPUT" | grep -o '"step_index":[0-9]*' | head -1 | cut -d':' -f2)
export STEP_INDEX

# Circuit-breaker session key (v2.30.0): prefer session_id, fall back to the
# transcript basename. Sanitized to a safe filename. If neither resolves, the
# breaker is disabled (BREAKER_STATE empty) and the hook degrades to its prior
# behavior — never a shared cross-session counter.
SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')
SESSION_KEY="$SESSION_ID"
[ -z "$SESSION_KEY" ] && [ -n "$TRANSCRIPT" ] && SESSION_KEY=$(basename "$TRANSCRIPT" .jsonl 2>/dev/null)
SESSION_KEY=$(printf '%s' "$SESSION_KEY" | tr -cd 'A-Za-z0-9._-')
BREAKER_STATE=""
[ -n "$SESSION_KEY" ] && BREAKER_STATE="${TMPDIR:-/tmp}/aria-r22-denies-${SESSION_KEY}"

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
  COMPLIANT=$(TRANSCRIPT="$TRANSCRIPT" TOOL_USE_ID="$TOOL_USE_ID" STEP_INDEX="$STEP_INDEX" python3 - <<'PY' 2>/dev/null
import json, os, re, sys
try:
    path = os.environ["TRANSCRIPT"]
    tool_use_id = os.environ.get("TOOL_USE_ID", "")
    step_index_str = os.environ.get("STEP_INDEX", "")
    step_index = int(step_index_str) if step_index_str else None
    MARKER = re.compile(r"\[Rule 22(\s\xb7\s[^\]]+)?\]")
    with open(path) as f:
        lines = f.readlines()

    target_line_idx = None

    if step_index is not None:
        # Antigravity branch: find step by step_index
        for i, line in enumerate(lines):
            try:
                evt = json.loads(line)
            except Exception:
                continue
            if evt.get("step_index") == step_index and evt.get("source") == "MODEL":
                target_line_idx = i
                break
        
        if target_line_idx is None:
            # Fallback to last MODEL event
            for i in range(len(lines) - 1, -1, -1):
                try:
                    evt = json.loads(lines[i])
                except Exception:
                    continue
                if evt.get("source") == "MODEL":
                    target_line_idx = i
                    break

        if target_line_idx is None:
            print("unknown")
            sys.exit(0)

        text_blocks = []
        target_evt = json.loads(lines[target_line_idx])
        target_content = target_evt.get("content", "")
        if target_content:
            text_blocks.append(target_content)

        # Walk backward to collect text blocks within the same assistant turn
        for i in range(target_line_idx - 1, -1, -1):
            try:
                evt = json.loads(lines[i])
            except Exception:
                continue
            if evt.get("source") == "USER_EXPLICIT" or evt.get("type") == "USER_INPUT":
                break
            
            has_prior_edit = False
            for tc in evt.get("tool_calls", []):
                if tc.get("name") in ("write_to_file", "replace_file_content", "multi_replace_file_content", "Edit", "Write"):
                    has_prior_edit = True
                    break
            if has_prior_edit:
                break
                
            if evt.get("source") == "MODEL":
                content = evt.get("content", "")
                if content:
                    text_blocks.insert(0, content)

    else:
        # Claude Code branch: find step by tool_use_id
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

        found_prior_edit_in_target_msg = False
        text_blocks = []

        target_evt = json.loads(lines[target_line_idx])
        target_content = target_evt["message"]["content"]
        for b in target_content[:target_content_idx]:
            if isinstance(b, dict):
                if b.get("type") == "tool_use" and b.get("name") in ("Edit", "Write"):
                    text_blocks = []
                    found_prior_edit_in_target_msg = True
                elif b.get("type") == "text":
                    text_blocks.append(b.get("text", ""))

        if not found_prior_edit_in_target_msg:
            for i in range(target_line_idx - 1, -1, -1):
                try:
                    evt = json.loads(lines[i])
                except Exception:
                    continue
                evt_type = evt.get("type")
                if evt_type == "user":
                    user_content = evt.get("message", {}).get("content", [])
                    if isinstance(user_content, list) and user_content and \
                       all(isinstance(b, dict) and b.get("type") == "tool_result" for b in user_content):
                        continue
                    break
                if evt_type != "assistant":
                    continue
                content = evt.get("message", {}).get("content", [])
                if not isinstance(content, list):
                    continue
                msg_text_blocks = []
                cap_reached = False
                for b in content:
                    if isinstance(b, dict):
                        if b.get("type") == "tool_use" and b.get("name") in ("Edit", "Write"):
                            msg_text_blocks = []
                            cap_reached = True
                        elif b.get("type") == "text":
                            msg_text_blocks.append(b.get("text", ""))
                text_blocks = msg_text_blocks + text_blocks
                if cap_reached:
                    break

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

# Compliant: allow silently. A compliant edit resets the deny-rate breaker
# (v2.30.0) — enforcement self-heals the moment detectable markers resume.
if [ "$COMPLIANT" = "yes" ]; then
  [ -n "$BREAKER_STATE" ] && rm -f "$BREAKER_STATE" 2>/dev/null
  exit 0
fi

# Fail-open (LOUD): the detector could not evaluate this edit — the queried
# tool_use_id was not locatable in the transcript, the transcript was
# unreadable, or python3 was unavailable. This is an INFRASTRUCTURE failure,
# not a "marker absent" decision (a located edit always resolves to yes/no, so
# the model cannot reach this branch by reasoning around enforcement). Allow
# the edit so a detector/schema break never deadlocks the editor (cf. the
# v2.10.5 deadlock), but surface a visible warning so enforcement is never lost
# SILENTLY — on a model/harness change you see this on the first affected edit.
if [ "$COMPLIANT" = "unknown" ]; then
  WARN="aria-knowledge Rule 22: could not verify this edit — enforcement was bypassed for it. The transcript parser may be broken (possible model/harness change). If this appears on every edit, run tests/run.sh and check pre-edit-check.sh against the current transcript format."
  WARN_ESCAPED=$(kt_json_escape "$WARN")
  printf '{"systemMessage":"%s"}\n' "$WARN_ESCAPED"
  exit 0
fi

# Deny-rate circuit breaker (v2.30.0). At this point the edit is genuinely
# non-compliant (a located edit resolved to "no"). Count consecutive denials in
# this session; once 3 have accrued with no intervening compliant edit, degrade
# to allow-with-loud-warning instead of denying forever. This is the same
# fail-open-LOUD philosophy as the "unknown" branch above, extended to cover a
# transcript-format change that parses cleanly but shifts semantics (the
# "confident no" deadlock the plain unknown-guard cannot catch). Disabled when
# no session key resolved (BREAKER_STATE empty) — falls straight through to deny.
if [ -n "$BREAKER_STATE" ]; then
  DENY_COUNT=0
  [ -f "$BREAKER_STATE" ] && DENY_COUNT=$(cat "$BREAKER_STATE" 2>/dev/null)
  case "$DENY_COUNT" in *[!0-9]*|"") DENY_COUNT=0 ;; esac
  if [ "$DENY_COUNT" -ge 3 ]; then
    WARN="aria-knowledge Rule 22: enforcement is in DEGRADED mode. ${DENY_COUNT} consecutive edits were denied for a missing [Rule 22] marker with no compliant edit between them — this usually means a transcript-format change has made the marker undetectable (cf. prior model/harness deadlocks), not that the marker is being skipped. The edit is ALLOWED so the editor does not deadlock; marker discipline is still expected, and a single compliant edit restores blocking enforcement. If this persists, run tests/run.sh and check pre-edit-check.sh against the current transcript format."
    WARN_ESCAPED=$(kt_json_escape "$WARN")
    printf '{"systemMessage":"%s"}\n' "$WARN_ESCAPED"
    exit 0
  fi
  # Below the trip threshold — record this denial, then fall through to deny.
  printf '%s' "$((DENY_COUNT + 1))" > "$BREAKER_STATE" 2>/dev/null || true
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
