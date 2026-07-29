#!/bin/sh
# pre-cron-check.sh — PreToolUse hook enforcing standing directive D2.
#
# A scheduled prompt that begins with '/' is parsed as a slash command. In a
# scheduled or headless context it usually does not resolve, the runtime reports
# an unknown command, and the ENTIRE remaining mandate is silently discarded --
# the failure is total and quiet, which is what makes it worth a hard gate.
#
# The rule shipped as prose in v2.37.3 and was violated twice afterward. Prose in
# a step that only executes on unattended runs is not enforcement.
#
# Scope: leading-slash detection only. Does NOT validate the cron expression, the
# schedule, or the mandate's content.
#
# Fail-open on anything unparseable: this hook must never block a well-formed
# schedule because it could not read its own input.

INPUT=$(cat)

# Extract the prompt. POSIX grep/sed only -- no jq dependency, matching the
# sibling hooks (bash-cd-check.sh uses the same idiom for "command"). JSON
# escapes real newlines as a literal backslash-n, so the first character after
# the opening quote is exactly the character the parser will see.
PROMPT=$(echo "$INPUT" | grep -o '"prompt":"[^"]*"' | head -1 | sed 's/"prompt":"//;s/"$//')
[ -z "$PROMPT" ] && exit 0

# The parser strips leading whitespace before dispatching, so strip it here too --
# otherwise a padded prompt smuggles the slash past this check.
TRIMMED=$(printf '%s' "$PROMPT" | sed 's/^[[:space:]]*//')

# Only a LEADING slash is a problem. A slash inside the prose (a path, a URL, a
# mid-sentence skill reference) is legitimate and must pass.
case "$TRIMMED" in
  /*) ;;
  *)  exit 0 ;;
esac

REASON='Scheduled prompt starts with a slash -- blocked by ARIA standing directive D2. A leading slash token is parsed as a command, and when it does not resolve the whole mandate is silently discarded, so the scheduled run does nothing and reports nothing. Rewrite the prompt to LEAD WITH PROSE (name a skill mid-sentence if you need to reference one), make it self-sufficient so it works whether or not that skill resolves, and instruct the next scheduled run to start prose-first as well.'

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$REASON"
