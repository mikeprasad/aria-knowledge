#!/bin/sh
# subagent-stop-capture.sh — subagentStop hook for aria-knowledge (Cursor port).
# Archives a subagent transcript to intake/subagent-captures/ when configured.
# Pure filesystem side effect — exit 0 on all skip paths.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

[ "$KT_CONFIGURED" = "false" ] && exit 0
[ -n "$KT_CONFIG_ERROR" ] && exit 0
[ ! -d "$KT_KNOWLEDGE_FOLDER" ] && exit 0
[ "$KT_AUTO_CAPTURE" = "false" ] && exit 0
[ "$KT_SUBAGENT_CAPTURE" = "false" ] && exit 0

INPUT=$(cat)

AGENT_TYPE=$(echo "$INPUT" | grep -oE '"(agentType|agent_type)":"[^"]*"' | head -1 | sed 's/.*:"//;s/"$//')
case ",$KT_SUBAGENT_CAPTURE_TYPES," in
  *",$AGENT_TYPE,"*) : ;;
  *) exit 0 ;;
esac

SESSION_ID=$(echo "$INPUT" | grep -oE '"(sessionId|session_id)":"[^"]*"' | head -1 | sed 's/.*:"//;s/"$//')
AGENT_ID=$(echo "$INPUT" | grep -oE '"(agentId|agent_id)":"[^"]*"' | head -1 | sed 's/.*:"//;s/"$//')
TRANSCRIPT_PATH=$(echo "$INPUT" | grep -o '"agent_transcript_path":"[^"]*"' | head -1 | sed 's/"agent_transcript_path":"//;s/"//')
[ -z "$TRANSCRIPT_PATH" ] && TRANSCRIPT_PATH=$(echo "$INPUT" | grep -o '"transcriptPath":"[^"]*"' | head -1 | sed 's/"transcriptPath":"//;s/"//')
[ -z "$TRANSCRIPT_PATH" ] && TRANSCRIPT_PATH=$(echo "$INPUT" | grep -o '"transcript_path":"[^"]*"' | head -1 | sed 's/"transcript_path":"//;s/"//')

CAPTURES_DIR="$KT_KNOWLEDGE_FOLDER/intake/subagent-captures"
mkdir -p "$CAPTURES_DIR" 2>/dev/null

if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] && [ -r "$TRANSCRIPT_PATH" ]; then
  TODAY=$(date +%Y-%m-%d)
  SESSION_SHORT=$(echo "$SESSION_ID" | cut -c1-8)
  AGENT_SHORT=$(echo "$AGENT_ID" | cut -c1-8)
  AGENT_TYPE_SAFE=$(printf '%s' "$AGENT_TYPE" | sed 's/[^A-Za-z0-9._-]/-/g')
  SNAPSHOT_FILE="$CAPTURES_DIR/${TODAY}_${SESSION_SHORT}_${AGENT_TYPE_SAFE}_${AGENT_SHORT}.md"
  cp "$TRANSCRIPT_PATH" "$SNAPSHOT_FILE" 2>/dev/null
fi
exit 0
