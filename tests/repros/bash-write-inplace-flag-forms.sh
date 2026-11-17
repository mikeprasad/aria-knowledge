#!/bin/sh
# bash-write-inplace-flag-forms.sh — option-grammar controls for pre-bash-write-resolve.py (GitHub #3).
#
# The resolver decided "in place" with `u == "-i" or u.startswith("-i")`. That is a token comparison
# with no model of how sed and perl read options, and it was wrong in both directions:
#
#   MISSED   `perl -pi -e`, `perl -pi.bak`, `sed -ni`, `sed --in-place[=SUF]` — the flag is bundled
#            or long, so no token STARTS with -i.
#   FLAGGED  `perl -pe '…' f -i` — perl stops reading switches at its first non-switch argument, so
#            that -i is a filename and nothing is edited (measured on a real file).
#   FLAGGED  the SCRIPT FILE in `sed -i -f script.sed f` — an option's argument read as a target.
#
# ⛔ The fix suggested on the issue, `^-[A-Za-z]*i`, would also FLAG `perl -Mstrict -e …` and
# `perl -Ilib -e …`: -M and -I consume the rest of their token, so the `i` there is part of a
# module name or a path. Those two rows are in MUST-STAY-SILENT for that reason.
#
# Grammar was measured, not read: on a scratch file `perl -lpi`, `-0pi`, `-l0pi` and
# `-Mstrict -pi` edit in place; `-Mstrict -pe`, `-I. -pe` and `-pe … f -i` do not.
#
# ⛔ Every fixture is a REAL file in a repo-local directory: the resolver only reports targets that
# exist and are outside temp roots, so a missing or /tmp fixture would make a silence row pass for
# the wrong reason. Run from any directory; resolves its own paths.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESOLVER="$REPO_ROOT/plugin-claude-code/scripts/pre-bash-write-resolve.py"

WORK=$(mktemp -d "$REPO_ROOT/tests/.inplace-work.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
F="$WORK/f.txt"
S="$WORK/script.sed"
printf 'a\n' > "$F"
printf 's/a/b/\n' > "$S"

PASS=0
FAIL=0

resolve() {
  printf '%s' "$1" \
    | python3 -c 'import json,sys; print(json.dumps({"tool_input":{"command":sys.stdin.read()}}))' \
    | python3 -I "$RESOLVER"
}

# expect <label> <command> <expected output, newline-separated, "" for silence>
expect() {
  got=$(resolve "$2")
  if [ "$got" = "$3" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL %s\n  cmd:      %s\n  expected: [%s]\n  got:      [%s]\n' "$1" "$2" "$3" "$got"
  fi
}

# ── POSITIVE CONTROLS — reported before the fix too; prove the instrument fires ──
expect "ctl sed -i"             "sed -i 's/a/b/' $F"                 "$F"
expect "ctl perl -i -pe"        "perl -i -pe 's/a/b/' $F"            "$F"
expect "ctl sed -E -i ''"       "sed -E -i '' 's/a/b/' $F"           "$F"

# ── MUST REPORT — the issue's forms and their siblings ──
expect "perl -pi"               "perl -pi -e 's/a/b/' $F"            "$F"
expect "perl -pi.bak"           "perl -pi.bak -e 's/a/b/' $F"        "$F"
expect "perl -i.bak -pe"        "perl -i.bak -pe 's/a/b/' $F"        "$F"
expect "perl -lpi (-l digits)"  "perl -lpi -e 's/a/b/' $F"           "$F"
expect "perl -l0pi"             "perl -l0pi -e 's/a/b/' $F"          "$F"
expect "perl -0pi"              "perl -0pi -e 's/a/b/' $F"           "$F"
expect "perl -0x1e -pi (hex)"   "perl -0x1e -pi -e 's/a/b/' $F"      "$F"
expect "perl -Mstrict -pi"      "perl -Mstrict -pi -e 's/a/b/' $F"   "$F"
expect "sed -ni"                "sed -ni 's/a/b/p' $F"               "$F"
expect "sed --in-place"         "sed --in-place 's/a/b/' $F"         "$F"
expect "sed --in-place=.bak"    "sed --in-place=.bak 's/a/b/' $F"    "$F"
expect "sed --in (abbrev)"      "sed --in 's/a/b/' $F"               "$F"
expect "BSD sed -I .bak"        "sed -I .bak 's/a/b/' $F"            "$F"
expect "GNU sed permuted -i"    "sed 's/a/b/' $F -i"                 "$F"
expect "sed -i -e -e"           "sed -i -e 's/a/b/' -e 's/c/d/' $F"  "$F"
expect "sed -i -f: target only" "sed -i -f $S $F"                    "$F"
expect "sed -if: target only"   "sed -i -f$S $F"                     "$F"
expect "sed --file= target only" "sed --in-place --file=$S $F"       "$F"

# ── MUST STAY SILENT — reads, and the false-positive traps ──
expect "sed -n"                 "sed -n 's/a/b/p' $F"                ""
expect "sed -e with i in script" "sed -e 's/i/j/' $F"                ""
expect "sed -f no -i"           "sed -f $S $F"                       ""
expect "perl -e"                "perl -e 'print 1' $F"               ""
expect "perl -Mstrict -e"       "perl -Mstrict -e 'print 1' $F"      ""
expect "perl -Ilib -pe"         "perl -Ilib -pe 's/a/b/' $F"         ""
expect "perl -pe f -i (switches end)" "perl -pe 's/a/b/' $F -i"      ""
expect "perl -- -i"             "perl -pe 's/a/b/' -- -i $F"         ""

printf 'bash-write-inplace-flag-forms: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
