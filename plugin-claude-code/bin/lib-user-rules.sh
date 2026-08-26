#!/bin/sh
# lib-user-rules.sh — shared U-namespace user-rule index builder for aria-knowledge
# Extracted verbatim from session-start-rules.sh:57-73 (v2.47.x → the file/hook split).
#
# ⛔ ONE IMPLEMENTATION, TWO CALLERS — do not copy this logic anywhere.
# The split moves the U-rule index onto the file channel, but the hook must keep
# emitting it for installs that do not yet have the file (the no-flag-day rule).
# So the generator is shared and the SECOND caller — the hook's fallback arm — is
# retired only when that fallback arm is. A copy would drift silently, because
# nothing compares the two renderings.
#
# Why it cannot stay hook-only: session-start-rules.sh bounds the inline index at
# 3000 chars of titles before falling back to a pointer. That block plus a config
# block is ~3,527 ch, above the 3,321 ch that is the only size measured to cross
# the hook channel intact. See spec §10.8.
#
# Usage:
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   . "$SCRIPT_DIR/config.sh"          # provides KT_KNOWLEDGE_FOLDER
#   . "$SCRIPT_DIR/lib-user-rules.sh"  # provides kt_user_rules_block
#
#   kt_user_rules_block
#   MESSAGES="${MESSAGES}${KT_USER_RULES_BLOCK}"
#
# Contract:
#   - Sets/resets KT_USER_RULES_BLOCK and KT_USER_RULES_COUNT on entry.
#   - KT_USER_RULES_BLOCK is EMPTY when the file is absent or holds zero '### U'
#     headers. That is the correct brand-new-user behaviour: inject nothing.
#   - When non-empty it carries its own LEADING and TRAILING newline, so a caller
#     concatenates it directly. This preserves the exact bytes the inline version
#     produced via  MESSAGES="${MESSAGES}\n<text>\n".
#   - Two tiers, switching at 3000 chars of joined titles: inline index below,
#     count-plus-pointer above. Titles are the always-loaded recognition layer;
#     a mature user-rules.md runs 50KB+ and cannot be injected whole.
#   - Never writes. Never emits. Pure string construction.

kt_user_rules_block() {
  KT_USER_RULES_BLOCK=""
  KT_USER_RULES_COUNT=0

  _kt_ur_file="$KT_KNOWLEDGE_FOLDER/rules/user-rules.md"
  [ -f "$_kt_ur_file" ] || return 0

  _kt_ur_n=$(grep -c '^### U' "$_kt_ur_file" 2>/dev/null)
  [ "${_kt_ur_n:-0}" -gt 0 ] || return 0
  KT_USER_RULES_COUNT="$_kt_ur_n"

  _kt_ur_headers=$(grep '^### U' "$_kt_ur_file" 2>/dev/null | sed 's/^### //' | awk '{printf "%s%s", sep, $0; sep="; "}')

  if [ ${#_kt_ur_headers} -gt 3000 ]; then
    KT_USER_RULES_BLOCK="
STANDING USER RULES — ${_kt_ur_n} of the user's own rules are in force, at ${_kt_ur_file} (too many to index inline). Read that file before acting on anything it plausibly covers.
"
  else
    KT_USER_RULES_BLOCK="
STANDING USER RULES (${_kt_ur_n}, always in force — the user's own rules, binding alongside the working rules above): ${_kt_ur_headers}. These titles are the index; read ${_kt_ur_file} for the full text of any rule bearing on the task.
"
  fi
}
