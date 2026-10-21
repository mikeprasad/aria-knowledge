#!/bin/sh
# subagent-start-selfreport.sh — SubagentStart hook for aria-knowledge
# Injects a self-report instruction into routine subagents so their durable
# findings ride back in the return message for the parent's /extract. Validated
# 2026-05-31 that SubagentStart additionalContext reaches the subagent's context.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

[ "$KT_CONFIGURED" = "false" ] && exit 0
[ -n "$KT_CONFIG_ERROR" ] && exit 0
[ ! -d "$KT_KNOWLEDGE_FOLDER" ] && exit 0
[ "$KT_AUTO_CAPTURE" = "false" ] && exit 0
[ "$KT_SUBAGENT_CAPTURE" = "false" ] && exit 0

INPUT=$(cat)
AGENT_TYPE=$(echo "$INPUT" | grep -o '"agent_type":"[^"]*"' | head -1 | sed 's/"agent_type":"//;s/"//')

# Gate: only inject into configured routine types. Comma-wrapped membership test.
case ",$KT_SUBAGENT_SELFREPORT_TYPES," in
  *",$AGENT_TYPE,"*) : ;;   # matched — continue
  *) exit 0 ;;              # not a self-report type
esac

MSG=$(kt_json_escape "Before you return, briefly surface any durable findings worth persisting — non-obvious discoveries, dead-ends you ruled out (and why), and decisions you made. Put them in your final message so they aren't lost when this subagent ends.")
printf '%s' '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"'"$MSG"'"}}'
exit 0
