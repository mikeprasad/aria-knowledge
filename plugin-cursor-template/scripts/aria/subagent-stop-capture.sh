#!/bin/sh
# subagent-stop-capture.sh — SubagentStop hook for aria-knowledge
# Archives a heavyweight subagent's transcript before it is lost. Capture only —
# synthesis happens later via /extract or /audit-knowledge, because a subagent
# cannot reliably self-extract (it is already done when this hook fires).
# SubagentStop supports no additionalContext, so this is a pure filesystem side
# effect; a bare exit 0 is the correct no-op in every skip case.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

[ "$KT_CONFIGURED" = "false" ] && exit 0
[ -n "$KT_CONFIG_ERROR" ] && exit 0
[ ! -d "$KT_KNOWLEDGE_FOLDER" ] && exit 0
[ "$KT_AUTO_CAPTURE" = "false" ] && exit 0
[ "$KT_SUBAGENT_CAPTURE" = "false" ] && exit 0

INPUT=$(cat)

AGENT_TYPE=$(echo "$INPUT" | grep -o '"agent_type":"[^"]*"' | head -1 | sed 's/"agent_type":"//;s/"//')

# Gate: only archive configured heavyweight types. Comma-wrapped membership test.
case ",$KT_SUBAGENT_CAPTURE_TYPES," in
  *",$AGENT_TYPE,"*) : ;;   # matched — continue
  *) exit 0 ;;              # not a capture type
esac

SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')
AGENT_ID=$(echo "$INPUT" | grep -o '"agent_id":"[^"]*"' | head -1 | sed 's/"agent_id":"//;s/"//')
# IMPORTANT: archive the SUBAGENT's transcript (agent_transcript_path), NOT the
# parent session's (transcript_path). Verified against a live SubagentStop payload
# 2026-05-31. The grep anchors on the leading quote so "agent_transcript_path" and
# "transcript_path" do not collide.
TRANSCRIPT_PATH=$(echo "$INPUT" | grep -o '"agent_transcript_path":"[^"]*"' | head -1 | sed 's/"agent_transcript_path":"//;s/"//')

CAPTURES_DIR="$KT_KNOWLEDGE_FOLDER/intake/subagent-captures"
mkdir -p "$CAPTURES_DIR" 2>/dev/null

# Copy transcript if it exists and is readable. Sticky retention: this body is
# preserved until /extract or /audit-knowledge processes it (no ledger-clear here).
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] && [ -r "$TRANSCRIPT_PATH" ]; then
  TODAY=$(date +%Y-%m-%d)
  SESSION_SHORT=$(echo "$SESSION_ID" | cut -c1-8)
  AGENT_SHORT=$(echo "$AGENT_ID" | cut -c1-8)
  AGENT_TYPE_SAFE=$(printf '%s' "$AGENT_TYPE" | sed 's/[^A-Za-z0-9._-]/-/g')
  SNAPSHOT_FILE="$CAPTURES_DIR/${TODAY}_${SESSION_SHORT}_${AGENT_TYPE_SAFE}_${AGENT_SHORT}.md"
  cp "$TRANSCRIPT_PATH" "$SNAPSHOT_FILE" 2>/dev/null
fi
exit 0
