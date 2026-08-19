#!/bin/sh
# post-edit-tautology-check.sh — afterFileEdit hook (Cursor port of
# Claude Code's PostToolUse:Edit|Write tautology guard, Rule 36).
#
# Warns when a test file gains an assertion that CANNOT FAIL.
#
# Cursor afterFileEdit typically does NOT include the edit body (`content` /
# `new_string`). Native equivalent: read the file from disk after the write
# lands (the edit has already succeeded) and scan it. Cap the scan so a huge
# fixture cannot blow the hook budget. Fails toward a missed warning.
#
# WARN-ONLY and SYNTACTIC. Cannot detect semantic tautologies — the warning
# says so, because a hook quiet about its own blind spot would itself be a
# false green.
#
# Fail-open on anything unparseable.

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh" 2>/dev/null || true

FILE=$(printf '%s' "$INPUT" | grep -o '"filePath":"[^"]*"' | head -1 | sed 's/"filePath":"//;s/"$//')
[ -z "$FILE" ] && FILE=$(printf '%s' "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"$//')
[ -z "$FILE" ] && exit 0

case "$FILE" in
  *test*|*spec*|*Test*|*Spec*) ;;
  *) exit 0 ;;
esac

[ -f "$FILE" ] || exit 0

# Cap: first 400 lines is enough for assertion-shaped files and keeps the
# hook inside Cursor's timeout. A tautology buried past that is a miss, never
# a false positive.
LINES=$(head -400 "$FILE" 2>/dev/null)
[ -z "$LINES" ] && exit 0

FOUND=""

if printf '%s\n' "$LINES" | grep -qE 'assert[[:space:]]+(True|true)([^A-Za-z0-9_]|$)|assertTrue\([[:space:]]*(True|true)[[:space:]]*\)|expect\([[:space:]]*(true|True)[[:space:]]*\)\.(toBe|toEqual)\([[:space:]]*(true|True)[[:space:]]*\)'; then
  FOUND="a literal-true assertion"
fi

if [ -z "$FOUND" ]; then
  DUP=$(printf '%s\n' "$LINES" | awk '
    {
      s = ""
      if (match($0, /assert[ \t]+[A-Za-z_][A-Za-z0-9_.]*[ \t]*==[ \t]*[A-Za-z_][A-Za-z0-9_.]*/)) {
        s = substr($0, RSTART, RLENGTH)
        sub(/^assert[ \t]+/, "", s)
      } else if (match($0, /expect\([A-Za-z_][A-Za-z0-9_.]*\)\.(toBe|toEqual)\([A-Za-z_][A-Za-z0-9_.]*\)/)) {
        s = substr($0, RSTART, RLENGTH)
        sub(/^expect\(/, "", s)
        sub(/\)\.toBe\(/, "==", s)
        sub(/\)\.toEqual\(/, "==", s)
        sub(/\)$/, "", s)
      }
      if (s == "") next
      n = index(s, "==")
      if (n == 0) next
      l = substr(s, 1, n - 1)
      r = substr(s, n + 2)
      gsub(/[ \t]/, "", l)
      gsub(/[ \t]/, "", r)
      if (l != "" && l == r) { print l; exit }
    }')
  [ -n "$DUP" ] && FOUND="an assertion whose two operands are both '$DUP'"
fi

if [ -z "$FOUND" ]; then
  SDUP=$(printf '%s\n' "$LINES" | awk '
    {
      line = $0
      gsub(/\[/, " ", line); gsub(/\]/, " ", line); gsub(/"/, "", line)
      n = 0
      if (match(line, /[ \t]==?[ \t]/)) { n = RSTART; w = RLENGTH }
      else if (match(line, /[ \t]-eq[ \t]/)) { n = RSTART; w = RLENGTH }
      if (n == 0) next
      l = substr(line, 1, n - 1); r = substr(line, n + w)
      sub(/^.*[ \t]/, "", l); sub(/[ \t].*$/, "", r)
      gsub(/[ \t{}]/, "", l); gsub(/[ \t{}]/, "", r)
      if (l != "" && l == r && l ~ /^\$/) { print l; exit }
    }')
  [ -n "$SDUP" ] && FOUND="a shell test comparing $SDUP to itself"
fi

[ -z "$FOUND" ] && exit 0

MSG="ARIA: this test file contains $FOUND -- it cannot fail, so it proves nothing while still reporting green (Rule 36). Rewrite it so it fails for the right reason, then watch it go RED before trusting it. NOTE: this check is syntactic only. It cannot detect semantic tautologies, so a clean result here is not evidence that the file is free of them."
MSG_ESCAPED=$(kt_json_escape "$MSG" 2>/dev/null || printf '%s' "$MSG" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ')
printf '{"agentMessage":"%s"}\n' "$MSG_ESCAPED"
exit 0
