#!/bin/sh
# check-rule-lead-bytes.sh — verify each U-rule's lead paragraph fits the always-on
# digest builder's truncation window.
#
# WHY BYTES, NOT CHARS: lib-user-rules.sh builds the per-rule digest line from the
# rule's first non-empty paragraph and truncates it with awk length() under the C
# locale — i.e. in BYTES. Multi-byte punctuation (em-dashes, curly quotes, ellipses)
# counts 2-3x, so a lead that passes a 240-CHARACTER check can still truncate
# mid-claim in the digest. Measured origin (2026-08-27): a 237-char lead carrying
# em-dashes rendered with its operative test clause cut to an ellipsis.
#
# Usage: check-rule-lead-bytes.sh <user-rules.md> [budget]
#   exit 0 — every rule lead fits the budget (default 240 bytes)
#   exit 1 — one or more leads OVER budget ("OVER U<n> <bytes>") or with NO operative lead
#            ("NOLEAD U<n>"). A lead opening with an unrecognised bold label also emits a
#            non-fatal "UNKNOWNLABEL U<n>" line.
#   exit 2 — usage error / file missing
#
# Extraction mirrors lib-user-rules.sh: the lead is the FIRST non-empty paragraph
# after a '### U<n>.' heading, lines joined by single spaces, '**' markers stripped
# (the digest strips them before measuring; backticks are kept, as the digest keeps
# them).

FILE="${1:-}"
BUDGET="${2:-240}"
if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "usage: $(basename "$0") <user-rules.md> [budget-bytes]" >&2
  exit 2
fi

LC_ALL=C awk -v budget="$BUDGET" '
  # METADATA PARAGRAPHS are not the lead — see the identical set and the full reasoning in
  # lib-user-rules.sh. THE TWO SETS MUST STAY IDENTICAL: before 2026-09-05 this gate had no
  # metadata concept at all, so on an Origin-first rule it measured the Origin block while the
  # generator rendered the lead. Why and How to apply are deliberately absent (they FOLLOW the
  # lead per /audit rules Step 7.1); an unlisted **Label: lead is reported UNKNOWNLABEL, never
  # skipped, so a marker nobody anticipated is LOUD rather than silently guessed.
  function ismeta(t) { return t ~ /^\*\*(Origin|Last updated|Status|Superseded):/ }
  function islabel(t) { return t ~ /^\*\*[A-Z][A-Za-z ]*:/ }
  function report(   p, n) {
    if (tag == "") return
    if (lead == "") {
      # NOLEAD — the rule has no operative paragraph; every one was a metadata marker (or it
      # has none at all). The generator renders such a rule TITLE-ONLY, so its lead reaches no
      # session. Reported as a failure, never a silent pass.
      # ORDERING: this arm and the ismeta() skip must ship together. With the skip alone, lead
      # goes empty and the old "if (tag == 0 || lead == 0) return" dropped the rule from output
      # entirely — a silent missing-rule bug, strictly worse than a wrong number.
      printf "NOLEAD %s (no operative lead paragraph)\n", tag; over++
      tag = ""; lead = ""; started = 0; first = ""
      return
    }
    if (islabel(first)) printf "UNKNOWNLABEL %s (lead starts with an unrecognised bold label; not skipped)\n", tag
    p = lead
    gsub(/\*\*/, "", p)
    n = length(p)
    if (n > budget) { printf "OVER %s %d bytes (budget %d)\n", tag, n, budget; over++ }
    else            { printf "OK %s %d bytes\n", tag, n }
    tag = ""; lead = ""; started = 0; first = ""
  }
  /^### U[0-9]+/ {
    report()
    tag = $2
    sub(/\.$/, "", tag)
    collecting = 1; started = 0; lead = ""; first = ""
    next
  }
  collecting {
    if ($0 ~ /^[ \t]*$/) {
      # A blank line ENDS the lead only once the lead has started. Before that it is spacing
      # under the heading, or the gap after a skipped leading-metadata block, so it is ignored.
      # KEYED ON lead, NOT on a started flag: with a started flag, skipping a leading metadata
      # block still marked the rule as started, so the blank line after it terminated collection
      # and the real lead was never read — the rule then reported NOLEAD. Measured 2026-09-05.
      # This mirrors lib-user-rules.sh, which keys the same decision on para.
      if (lead != "") { report(); collecting = 0 }
      next
    }
    if (ismeta($0)) {
      # Leading metadata is skipped; metadata AFTER the lead ends it (mirrors the generator).
      if (lead == "") next
      report(); collecting = 0; next
    }
    started = 1
    if (first == "") first = $0
    lead = (lead == "" ? $0 : lead " " $0)
  }
  END {
    if (collecting) report()
    exit (over > 0 ? 1 : 0)
  }
' "$FILE"
