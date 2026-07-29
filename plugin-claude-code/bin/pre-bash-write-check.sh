#!/bin/sh
# pre-bash-write-check.sh — PreToolUse:Bash hook.
#
# Warns when a shell command MUTATES A FILE IN PLACE, because that routes around
# the Edit/Write tools and therefore around the Rule 22 pre-edit gate: the change
# lands with no scope assessment recorded, and the enforcement that exists for
# every other structural edit simply does not fire.
#
# WARN-ONLY BY DESIGN. This hook never denies. A false positive would interfere
# with legitimate shell work in every session, which is worse than the lapse it
# catches. Escalating to deny would need a fresh measurement.
#
# SCOPE — in-place mutation only, NOT file creation. That distinction is measured,
# not assumed: across 25,508 real Bash calls, `cat > newfile` is overwhelmingly a
# throwaway probe or diagnostic harness (legitimate, frequent), while `sed -i` and
# `.write_text()` on a tracked file are the actual lapse. The narrowed rule fires
# on 0.674% of calls, roughly 1 in 148.
#
# Also exempt, both measured as benign:
#   - temp / scratchpad paths          (11.4% of all calls)
#   - appends to .md / .json backlogs  (1.27% of all calls)
#
# Fail-open on anything unparseable.

INPUT=$(cat)
# printf '%s', NOT echo -- `echo` in sh interprets backslash escapes, so JSON's
# \n becomes a real newline, the value splits across lines, and this single-line
# grep silently matches nothing. Heredoc commands are routinely multi-line.
COMMAND=$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//')
[ -z "$COMMAND" ] && exit 0

# Temp and scratchpad writes are legitimate by construction.
case "$COMMAND" in
  */tmp/*|*scratchpad*|*/var/folders/*) exit 0 ;;
esac

IDIOM=""
case "$COMMAND" in
  *sed\ -i*)        IDIOM="sed -i" ;;
  *.write_text\(*)  IDIOM="Path.write_text()" ;;
  *write_text\ \(*) IDIOM="Path.write_text()" ;;
esac

# Append-redirect into a source file. Markdown and JSON are deliberately absent:
# appending to a backlog or a log is normal and was measured as always benign.
if [ -z "$IDIOM" ]; then
  if echo "$COMMAND" | grep -qE '>>[[:space:]]*[^[:space:]]+\.(py|ts|tsx|js|jsx|sh|swift|kt|java|rb|go|rs)([[:space:]]|$)'; then
    IDIOM="an append-redirect into a source file"
  fi
fi

[ -z "$IDIOM" ] && exit 0

MSG="ARIA: this command uses $IDIOM to modify a file in place. A structural edit made through the shell bypasses the Edit and Write tools, and therefore the Rule 22 pre-edit gate -- the change lands with no scope assessment recorded. Use Edit or Write instead. If this is genuinely not a structural edit (a generated artifact, a disposable probe, a log), go ahead and say why."

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$MSG"
