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
#   - Each rule renders as  - **U<n> — <title>** — <lead paragraph>, in ONE of four
#     ways, none of which severs a claim (2026-08-28, replacing a hard cut):
#       (i)   lead <= window                        -> full lead
#       (ii)  over, a '. ' boundary in the window   -> cut there (a whole sentence)
#       (iii) over, no boundary, <= ceiling         -> carried WHOLE
#       (iv)  over, no boundary, past the ceiling   -> title only
#     There is no ellipsis and no mid-word cut: the old space-backoff is GONE because
#     nothing truncates mid-lead any more. The '**Origin:' provenance block is skipped
#     when it leads and ends the lead when it follows — it records how a rule came to
#     exist, not what it asks of you.
#     Bold markers are stripped (they would nest inside the line's own bold title);
#     backticks are deliberately KEPT, because a rule naming `sed -i` or `Edit|Write`
#     is quoting a literal, and stripping the span makes it read as prose.
#   - Two tiers. Above KT_USER_RULES_MAX (default 21000, see A1 below) the digest is replaced by a
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

  # ⛔ THIS NUMBER AND bin/check-rule-lead-bytes.sh's DEFAULT MUST MOVE TOGETHER.
  # /audit rules Step 7 item 2 tells an author to verify a new lead fits this budget, and
  # that gate defaults to the same value. The pairing is what matters: change one alone and
  # the gate starts reporting leads the generator renders fine, or stops reporting leads it
  # truncates. A test asserts the RELATIONSHIP, not this literal — a literal pin would guard
  # spelling and go red on a correct coordinated change.
  #
  # ⚠ 240 is NOT an independently-ruled authoring budget, and an earlier version of this
  # comment wrongly called it "a contract, not a tunable". Traced 2026-08-28: the audit gate
  # holds 240 BECAUSE this generator does (its skill text is descriptive — "the builder
  # truncates … verify each lead fits"), and it was created to fix a chars-vs-bytes unit
  # error, not to set a budget. This 240 in turn came from an implementation choice under a
  # 2026-08-26 ruling whose subject was titles-vs-summaries, and which cited 320 ch/rule as
  # the density to match. So the value is open to revision as a PAIR; what is not open is
  # letting the two drift apart.
  _kt_ur_window=240
  # Absolute bound on rendering (iii): a lead that cannot be cut honestly is carried
  # whole, but not without limit. Deliberately inert on a healthy corpus.
  _kt_ur_ceiling=800

  # LC_ALL=C so length()/substr() count BYTES, matching check-rule-lead-bytes.sh. Without
  # it the unit is awk-and-locale dependent — BSD awk counts bytes, gawk under a UTF-8
  # locale counts characters — so the generator and its own gate would silently disagree
  # off-macOS about what "240" means.
  # Multi-byte safety (branch ii): the window scan may split a UTF-8 sequence, but every
  # continuation byte is >= 0x80 while '.' and ' ' are ASCII, so a split can never
  # fabricate a boundary; and the cut itself indexes the ORIGINAL string.
  _kt_ur_digest=$(LC_ALL=C awk -v window="$_kt_ur_window" -v ceiling="$_kt_ur_ceiling" '
    function flush(   p, w, cut, i, k) {
      if (tag == "") return
      p = para
      gsub(/\*\*/, "", p)
      if (length(p) <= window) {
        # (i) fits — full lead.
        printf "%s- **%s — %s** — %s", sep, tag, title, p
      } else {
        w = substr(p, 1, window)
        cut = 0; i = 1
        while ((k = index(substr(w, i), ". ")) > 0) { cut = i + k; i = i + k }
        if (cut > 40) {
          # (ii) cut at the LAST sentence boundary inside the window. The 40 is a
          # usefulness floor: a boundary at position 10 would leave a 9-character
          # body, which says less than the title does.
          printf "%s- **%s — %s** — %s", sep, tag, title, substr(p, 1, cut - 1)
        } else if (length(p) <= ceiling) {
          # (iii) no boundary to cut at — carry the lead WHOLE rather than sever a
          # claim. A severed qualifier can invert the meaning of a rule ("never X unless
          # Y" cut before "unless" instructs the opposite), so a few extra bytes are
          # the cheaper side of that trade.
          printf "%s- **%s — %s** — %s", sep, tag, title, p
        } else {
          # (iv) uncuttable AND past the ceiling — title only, so one malformed rule
          # cannot emit without bound. Inert on any corpus whose longest lead is
          # under the ceiling; a fixture is what exercises it.
          printf "%s- **%s — %s**", sep, tag, title
        }
      }
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
      collecting = 1
      next
    }
    tag != "" && collecting {
      t = $0
      sub(/^[ \t]+/, "", t)
      sub(/[ \t]+$/, "", t)
      # Blank line ENDS the lead paragraph. Before the paragraph starts it is just
      # spacing under the heading, so it is skipped rather than treated as an end.
      if (t == "") { if (para != "") collecting = 0; next }
      # The provenance block records how a rule came to exist, not what it asks of
      # you. Skipped when it LEADS; when it follows the lead it is a new paragraph,
      # so it ends collection instead of being joined in.
      if (t ~ /^\*\*Origin:/) { if (para == "") next; collecting = 0; next }
      # D3 (2026-08-28): accumulate the WHOLE paragraph. The old guard was
      # `para == ""`, which captured only the FIRST line and discarded the rest with
      # no ellipsis and no signal — strictly worse than truncation, which at least
      # marks itself. check-rule-lead-bytes.sh:52 already joins the paragraph, so
      # the gate and the generator measured different quantities; they now agree by
      # construction rather than by the corpus happening to be single-line.
      para = (para == "" ? t : para " " t)
    }
    END { flush() }
  ' "$_kt_ur_file" 2>/dev/null)

  # A1 (maintainer ruling, 2026-08-28): the digest may not exceed what the PLUGIN's own
  # always-on rules digest takes (rules/aria-rules.md, 21,221 B measured) — the user's
  # rules never dominate the always-on surface over the framework's. Stated as a
  # RELATIONSHIP so it stays meaningful as both files change.
  # ⛔ It is NOT derived from channel capacity, and must not be: the channel threshold is
  # per-tool and remotely mutable, so no payload may be sized against it
  # (docs/superpowers/specs/2026-08-25-always-on-rules-delivery-design.md §10.7).
  _kt_ur_max="${KT_USER_RULES_MAX:-21000}"
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
