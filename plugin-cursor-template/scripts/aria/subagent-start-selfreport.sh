#!/bin/sh
# subagent-start-selfreport.sh — subagentStart hook for aria-knowledge (Cursor port).
#
# Cursor subagentStart supports permission + user_message (not additionalContext
# into the subagent). We emit agentMessage as best-effort guidance to the parent
# agent dispatching the subagent — weaker than Claude Code's SubagentStart injection.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

[ "$KT_CONFIGURED" = "false" ] && exit 0
[ -n "$KT_CONFIG_ERROR" ] && exit 0
[ ! -d "$KT_KNOWLEDGE_FOLDER" ] && exit 0
[ "$KT_AUTO_CAPTURE" = "false" ] && exit 0
[ "$KT_SUBAGENT_CAPTURE" = "false" ] && exit 0

INPUT=$(cat)
AGENT_TYPE=$(echo "$INPUT" | grep -oE '"(agentType|agent_type)":"[^"]*"' | head -1 | sed 's/.*:"//;s/"$//')

case ",$KT_SUBAGENT_SELFREPORT_TYPES," in
  *",$AGENT_TYPE,"*) : ;;
  *) exit 0 ;;
esac

MSG=$(kt_json_escape "SUBAGENT SELF-REPORT — Before this subagent returns, instruct it to surface durable findings in its final message: non-obvious discoveries, dead-ends ruled out (and why), and decisions made. Those findings must ride back to the parent for /extract.")
printf '{"agentMessage":"%s"}\n' "$MSG"
exit 0
