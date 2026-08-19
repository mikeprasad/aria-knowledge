#!/bin/sh
# pre-bash-write-check.sh — beforeShellExecution hook (Cursor port of
# Claude Code's PreToolUse:Bash in-place-write guard).
#
# Warns when a shell command MUTATES A FILE IN PLACE, because that routes around
# the Edit/Write tools and therefore around the Rule 22 pre-edit gate.
#
# WARN-ONLY BY DESIGN. This hook never denies. Cursor CAN deny shell commands;
# we still warn, matching canonical: a false positive that blocks legitimate
# shell work is worse than the lapse this catches.
#
# SCOPE — in-place mutation only, NOT file creation. Measured on the Claude
# corpus (25,508 Bash calls): `cat > newfile` is overwhelmingly a throwaway
# probe, while `sed -i` and `.write_text()` on a tracked file are the lapse.
#
# Fail-open on anything unparseable.

INPUT=$(cat)

# printf '%s', NOT echo — echo in sh interprets backslash escapes.
COMMAND=$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//')
[ -z "$COMMAND" ] && exit 0

case "$COMMAND" in
  */tmp/*|*scratchpad*|*/var/folders/*) exit 0 ;;
esac

IDIOM=""
case "$COMMAND" in
  *sed\ -i*)        IDIOM="sed -i" ;;
  *.write_text\(*)  IDIOM="Path.write_text()" ;;
  *write_text\ \(*) IDIOM="Path.write_text()" ;;
esac

if [ -z "$IDIOM" ]; then
  if echo "$COMMAND" | grep -qE '>>[[:space:]]*[^[:space:]]+\.(py|ts|tsx|js|jsx|sh|swift|kt|java|rb|go|rs)([[:space:]]|$)'; then
    IDIOM="an append-redirect into a source file"
  fi
fi

[ -z "$IDIOM" ] && exit 0

_bw_sid=$(printf '%s' "$INPUT" | grep -o '"sessionId":"[^"]*"' | head -1 | sed 's/"sessionId":"//;s/"$//')
[ -z "$_bw_sid" ] && _bw_sid=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"$//')
if [ -n "$_bw_sid" ]; then
  printf '%s\t%s\n' "$IDIOM" "$(printf '%s' "$COMMAND" | cut -c1-120)" \
    >> "${TMPDIR:-/tmp}/aria-r22-bypass-$_bw_sid" 2>/dev/null || true
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh" 2>/dev/null || true

MSG="ARIA: this command uses $IDIOM to modify a file in place. A structural edit made through the shell bypasses Edit/Write, and therefore the Rule 22 pre-edit gate — the change lands with no scope assessment recorded. Use Edit or Write instead. If this is genuinely not a structural edit (a generated artifact, a disposable probe, a log), go ahead and say why."
MSG_ESCAPED=$(kt_json_escape "$MSG" 2>/dev/null || printf '%s' "$MSG" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ')
printf '{"agentMessage":"%s"}\n' "$MSG_ESCAPED"
exit 0
