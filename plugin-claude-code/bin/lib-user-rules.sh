#!/bin/sh
# lib-user-rules.sh — shared U-namespace user-rule DIGEST builder for aria-knowledge
# Extracted from session-start-rules.sh:57-73 (v2.47.x → the file/hook split), then
# widened from a bare title index to a digest (Mike's ruling, 2026-08-26).
#
# ⛔ ONE IMPLEMENTATION, TWO CALLERS — do not copy this logic anywhere.
# The split moves the U-rule block onto the file channel, but the hook must keep
# emitting it for installs that do not yet have the file (the no-flag-day rule).
# So the generator is shared and the SECOND caller — the hook's fallback arm — is
# retired only when that fallback arm is. A copy would drift silently, because
# nothing compares the two renderings.
#
# WHY A DIGEST AND NOT TITLES.
# The working-rules digest gives each rule a title AND a one-line summary — 320 ch
# per rule. The U-rule block gave bare titles, 80 ch per rule. That asymmetry was an
# artifact of how each was built (one hand-authored, one grepped from headers), not a
# decision: it meant a user's own standing rules arrived as headlines they would have
# to go and read, while the plugin's rules arrived ready to apply. Measured on a real
# 19-rule corpus: titles 1,532 ch, digest 5,793 ch (304 ch/rule) — matching the
# working-rules density and well inside the file channel's proven capacity.
#
# WHY THE FULL FILE CANNOT TRAVEL INSTEAD.
# A mature user-rules.md is large — 66,238 B measured on the maintainer's — which
# exceeds every capacity figure proven for any always-on channel. So the two-tier
# shape (summary always-on, full text on demand) is forced by SIZE and would be
# required even on an uncapped channel. It is not a workaround for the hook cap.
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
#     concatenates it directly. A refactor that trims either runs the surrounding
#     directives together, with no error and nothing else failing.
#   - Each rule renders as  - **U<n> — <title>** — <first paragraph, <=240 ch>
#     Truncation backs off to the last space, so it can never split a multi-byte
#     character; an ellipsis marks it. The '**Origin:' provenance block is skipped —
#     it records how a rule came to exist, not what it asks of you.
#     Bold markers are stripped (they would nest inside the line's own bold title);
#     backticks are deliberately KEPT, because a rule naming `sed -i` or `Edit|Write`
#     is quoting a literal, and stripping the span makes it read as prose.
#   - Two tiers. Above KT_USER_RULES_MAX (default 20000) the digest is replaced by a
#     count-plus-pointer. The bound protects the FILE channel, which is the primary
#     consumer; the hook's fallback copy is truncated by the harness anyway, so it
#     needs no separate bound. The old 3000 was sized for the hook and would
#     mis-fire here — at 304 ch/rule it degrades a ten-rule user to a pointer.
#   - Never writes. Never emits. Pure string construction.

kt_user_rules_block() {
  KT_USER_RULES_BLOCK=""
  KT_USER_RULES_COUNT=0

  _kt_ur_file="$KT_KNOWLEDGE_FOLDER/rules/user-rules.md"
  [ -f "$_kt_ur_file" ] || return 0

  _kt_ur_n=$(grep -c '^### U' "$_kt_ur_file" 2>/dev/null)
  [ "${_kt_ur_n:-0}" -gt 0 ] || return 0
  KT_USER_RULES_COUNT="$_kt_ur_n"

  _kt_ur_digest=$(awk '
    function flush(   p) {
      if (tag == "") return
      p = para
      gsub(/\*\*/, "", p)
      if (length(p) > 240) {
        p = substr(p, 1, 240)
        sub(/[^ ]*$/, "", p)
        sub(/[ \t]+$/, "", p)
        p = p "\342\200\246"
      }
      printf "%s- **%s — %s** — %s", sep, tag, title, p
      sep = "\n"
      tag = ""
    }
    /^### U/ {
      flush()
      line = $0
      sub(/^### /, "", line)
      tag = line
      sub(/[ \t].*$/, "", tag)
      sub(/[.:)]$/, "", tag)
      title = line
      sub(/^U[0-9]+[.:)]?[ \t]*/, "", title)
      para = ""
      next
    }
    tag != "" && para == "" {
      t = $0
      sub(/^[ \t]+/, "", t)
      sub(/[ \t]+$/, "", t)
      if (t == "") next
      if (t ~ /^\*\*Origin:/) next
      para = t
    }
    END { flush() }
  ' "$_kt_ur_file" 2>/dev/null)

  _kt_ur_max="${KT_USER_RULES_MAX:-20000}"
  if [ -z "$_kt_ur_digest" ] || [ ${#_kt_ur_digest} -gt "$_kt_ur_max" ]; then
    KT_USER_RULES_BLOCK="
STANDING USER RULES — ${_kt_ur_n} of the user's own rules are in force, at ${_kt_ur_file} (too many to summarise inline). Read that file before acting on anything it plausibly covers.
"
  else
    KT_USER_RULES_BLOCK="
STANDING USER RULES (${_kt_ur_n}, always in force — the user's own rules, binding alongside the working rules above). These are summaries; read ${_kt_ur_file} for the full text of any rule bearing on the task.
${_kt_ur_digest}
"
  fi
}
