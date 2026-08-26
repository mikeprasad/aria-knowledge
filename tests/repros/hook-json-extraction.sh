#!/bin/sh
# hook-json-extraction.sh — hook input extraction must be escape-safe.
#
# THE HAZARD, measured rather than assumed:
#
#   echo "$INPUT" | grep -o '"command":"[^"]*"'
#
#   under bash  -> matches         (bash's echo does not interpret backslashes)
#   under sh    -> matches NOTHING (POSIX echo interprets \n, the JSON value
#                                   splits across lines, the single-line grep
#                                   finds no closing quote, and the caller sees
#                                   an empty string and silently fails open)
#
# Every bin/ script declares '#!/bin/sh', but plugin.json invokes them as
# 'bash ${CLAUDE_PLUGIN_ROOT}/bin/x.sh'. So the shebang and the invocation
# disagree: the scripts are correct only by accident of how they happen to be
# called. Anything that runs one directly, or under a POSIX sh, gets the failing
# behaviour -- and it fails OPEN, so a guard silently stops guarding.
#
# printf '%s' behaves identically under both shells and removes the dependence.
#
# Scope: fields whose value can contain a backslash escape -- 'command', 'content',
# 'prompt', 'new_string', 'task_subject', 'task_description'. Fields like session_id /
# file_path / transcript_path / agent_type / tool_use_id / step_index cannot contain
# escapes, so echo and printf are equivalent there and those sites are deliberately
# left alone.
#
# DERIVE THIS LIST BY ENUMERATION, NEVER FROM MEMORY. The first version of this guard
# listed four field names written from recollection, and was therefore blind to
# task_subject and task_description -- two genuinely free-text fields carrying the exact
# defect it exists to forbid. Re-derive with:
#   grep -oh 'echo "$INPUT" | grep -o .\{0,3\}"[a-z_]*"' bin/*.sh \
#     | grep -o '"[a-z_]*"$' | sort -u
# then classify each field as free-text or not.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BIN="$REPO_ROOT/plugin-claude-code/bin"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

# A — demonstrate the hazard is real on this host, so the rule below is grounded
# in observed behaviour and not folklore. If these two ever agree, the rule can
# be revisited; until then it stands.
A_BASH=$(bash -c 'IN='"'"'{"command":"a\nb"}'"'"'; echo "$IN" | grep -c "command" || true')
A_SH=$(sh    -c 'IN='"'"'{"command":"a\nb"}'"'"'; echo "$IN" | grep -o '"'"'"command":"[^"]*"'"'"' | grep -c . || true')
[ "$A_BASH" -ge 1 ] && ok "A echo works under bash (the production invocation)" \
                    || bad "A bash" "unexpected: echo failed under bash too"
[ "$A_SH" -eq 0 ] && ok "A echo FAILS under sh (the declared shebang)" \
                  || bad "A sh" "echo no longer eats escapes under sh — revisit this rule"

# B — printf '%s' is escape-safe under BOTH shells. This is the idiom the rule
# below mandates, and it is proven here rather than asserted.
B_BASH=$(bash -c 'IN='"'"'{"command":"a\nb"}'"'"'; printf "%s" "$IN" | grep -o '"'"'"command":"[^"]*"'"'"' | grep -c . || true')
B_SH=$(sh    -c 'IN='"'"'{"command":"a\nb"}'"'"'; printf "%s" "$IN" | grep -o '"'"'"command":"[^"]*"'"'"' | grep -c . || true')
[ "$B_BASH" -ge 1 ] && [ "$B_SH" -ge 1 ] \
  && ok "B printf '%s' extracts correctly under BOTH shells" \
  || bad "B printf" "printf idiom failed (bash=$B_BASH sh=$B_SH)"

# C — THE RULE: no hook may extract a free-text field with echo.
OFFENDERS=$(grep -ln 'echo "\$INPUT"' "$BIN"/*.sh 2>/dev/null | while read -r f; do
  if grep -q 'echo "\$INPUT" | grep -o .\{0,4\}"\(command\|content\|prompt\|new_string\|task_subject\|task_description\)"' "$f" 2>/dev/null; then
    basename "$f"
  fi
done)
if [ -z "$OFFENDERS" ]; then
  ok "C no hook extracts a free-text field with echo"
else
  bad "C echo extraction" "escape-unsafe in: $(echo "$OFFENDERS" | tr '\n' ' ')"
fi

# D — per-file, the four hooks handling free-text input must be free of the
# UNSAFE idiom. Checking for presence of printf is not enough: a file can carry
# both, and post-push-retrospect-check.sh actually did -- printf on one path,
# echo on another. An assertion that passes without being able to detect the
# defect it names is itself a false green.
# ⚠ pre-bash-write-check.sh was in this list until 2026-08-26, was retired that day,
# and was RESTORED 2026-08-27 (v2.48.1) with its method replaced — targets are now
# resolved by bin/pre-bash-write-resolve.py rather than matched in the command string.
# It is shipped again, so the old "an archived script parses nothing" reason no longer
# applies. It stays out of THIS loop for a different and narrower reason: it no longer
# extracts a free-text field at all. It pre-filters with a builtin `case "$INPUT"` and
# extracts only session_id (with printf, not echo), so the idiom this loop guards has
# no site in it. Re-add it here the moment it parses one of the fields above.
# lapse-guards.sh C1 pins the restoration; bash-write-target-resolution.sh proves the
# behaviour.
for h in bash-cd-check.sh post-push-retrospect-check.sh pre-cron-check.sh task-context-check.sh; do
  if [ ! -f "$BIN/$h" ]; then
    bad "D $h" "missing"
  elif grep -q 'echo "\$INPUT" | grep -o .\{0,4\}"\(command\|content\|prompt\|new_string\|task_subject\|task_description\)"' "$BIN/$h"; then
    bad "D $h" "still extracts a free-text field with echo"
  else
    ok "D free-text extraction is escape-safe: $h"
  fi
done

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
