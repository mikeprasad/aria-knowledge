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
#   exit 1 — one or more leads over budget; each is listed as "OVER U<n> <bytes>"
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
  function report() {
    if (tag == "" || lead == "") return
    p = lead
    gsub(/\*\*/, "", p)
    n = length(p)
    if (n > budget) { printf "OVER %s %d bytes (budget %d)\n", tag, n, budget; over++ }
    else            { printf "OK %s %d bytes\n", tag, n }
    tag = ""; lead = ""; started = 0
  }
  /^### U[0-9]+/ {
    report()
    tag = $2
    sub(/\.$/, "", tag)
    collecting = 1; started = 0; lead = ""
    next
  }
  collecting {
    if ($0 ~ /^[ \t]*$/) {
      if (started) { report(); collecting = 0 }
      next
    }
    started = 1
    lead = (lead == "" ? $0 : lead " " $0)
  }
  END {
    if (collecting && started) report()
    exit (over > 0 ? 1 : 0)
  }
' "$FILE"
