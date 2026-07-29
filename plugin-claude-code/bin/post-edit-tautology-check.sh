#!/bin/sh
# post-edit-tautology-check.sh — PostToolUse:Edit|Write hook.
#
# Warns when a test file gains an assertion that CANNOT FAIL. An assertion that
# cannot fail is a false green: it reports success without ever having been able
# to report failure, which is exactly the condition Rule 36 exists to prevent
# ("a pass signal only counts if it can fail for the right reason").
#
# WARN-ONLY, and deliberately SYNTACTIC. It detects identical-operand
# comparisons and literal-true assertions. It CANNOT detect semantic
# tautologies -- an assertion comparing two different expressions that always
# evaluate equal. The warning says so explicitly, because a hook that stayed
# quiet about its own blind spot would itself become a false green.
#
# Portability note: no regex backreferences anywhere. Backreferences are a BRE
# feature, are not guaranteed in ERE, and some grep implementations hard-error
# on \1 under -E. awk extracts both operands and compares them as strings, which
# behaves identically on every host.
#
# Fail-open on anything unparseable.

INPUT=$(cat)

# printf '%s', NOT echo -- echo interprets backslash escapes, so JSON's \n would
# split the value across lines and this single-line grep would match nothing.
FILE=$(printf '%s' "$INPUT" | grep -o '"file_path":"[^"]*"' | head -1 | sed 's/"file_path":"//;s/"$//')
[ -z "$FILE" ] && exit 0

# Only test-shaped paths. A tautology in production code is a different problem.
case "$FILE" in
  *test*|*spec*|*Test*|*Spec*) ;;
  *) exit 0 ;;
esac

# Write sends "content"; Edit sends "new_string". Two separate passes -- a
# combined sed alternation is a BRE feature that BSD sed does not support and
# would silently yield garbage.
BODY=$(printf '%s' "$INPUT" | grep -o '"content":"[^"]*"' | head -1 | sed 's/"content":"//;s/"$//')
[ -z "$BODY" ] && BODY=$(printf '%s' "$INPUT" | grep -o '"new_string":"[^"]*"' | head -1 | sed 's/"new_string":"//;s/"$//')
[ -z "$BODY" ] && exit 0

# The body arrives with literal backslash-n separators; turn them into real
# newlines so awk can work line by line.
LINES=$(printf '%s' "$BODY" | sed 's/\\n/\
/g')

FOUND=""

# 1. Literal-true assertions.
if printf '%s\n' "$LINES" | grep -qE 'assert[[:space:]]+(True|true)([^A-Za-z0-9_]|$)|assertTrue\([[:space:]]*(True|true)[[:space:]]*\)|expect\([[:space:]]*(true|True)[[:space:]]*\)\.(toBe|toEqual)\([[:space:]]*(true|True)[[:space:]]*\)'; then
  FOUND="a literal-true assertion"
fi

# 2. Identical operands, compared as strings by awk (no backreferences).
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

[ -z "$FOUND" ] && exit 0

MSG="ARIA: this test file contains $FOUND -- it cannot fail, so it proves nothing while still reporting green (Rule 36). Rewrite it so it fails for the right reason, then watch it go RED before trusting it. NOTE: this check is syntactic only. It cannot detect semantic tautologies, so a clean result here is not evidence that the file is free of them."

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$MSG"
