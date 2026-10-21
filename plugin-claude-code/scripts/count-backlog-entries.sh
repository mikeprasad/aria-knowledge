#!/bin/sh
# count-backlog-entries.sh — the one live-entry counter for the four action-eligible backlogs
# (insights, decisions, extraction, rules). Used by session-start-check.sh (audit trigger) and
# /audit knowledge Step 1 (audit scope). intake/ideas/ is excluded: ideas route out via the
# Accept submenu rather than promoting.
#
# USAGE: count-backlog-entries.sh <knowledge_folder> [--total | --list]
#   (default)  one line per backlog + a TOTAL line:  <name>: canonical=N h2=N h4suspect=N live=N
#   --total    the TOTAL live number only
#   --list     one line per non-### live block:     <file>:<line>: <kind>: <heading>
#
# WHY IT EXISTS. The old counter was `awk '… /^### /{c++}'`. At the 127th /audit pass it read 117
# against a true 181: 53 standalone `## ` entries and 11 mis-levelled `####` entries were invisible
# to it, and because the count is also the audit's scope, invisible entries were never audited.
#
# SCOPE: lines below the FIRST `^---$` of each file, outside `<!-- … -->` regions. A block starts
# at any `## `, `### ` or `#### ` heading and runs to the next one.
#   canonical  a `### ` block. Identical to the old counter — it is the CONTROL for the other arms.
#   h2         a `## ` block whose body holds a non-blank line. With an empty body it is a group
#              header (its children are separate blocks) and is not counted.
#   h4suspect  a `#### YYYY-MM-DD` block dated ON OR AFTER the last audit pass whose HEADING
#              carries no disposition marker. Passes demote processed entries `###`→`####`, so an
#              unmarked recent `####` may be processed history OR an entry born at the wrong level;
#              nothing on disk separates the two, so it is reported, not asserted.
#   live       canonical + h2 + h4suspect.
#
# ⛔ THE DATE ONLY BOUNDS THE WINDOW — IT CANNOT CLASSIFY. The 127th pass is stamped 2026-09-26
# (machine clock PDT) yet demoted entries dated 2026-09-27 (JST). Only the marker classifies.
# ⛔ THE MARKER IS READ FROM THE HEADING ONLY. Measured 2026-09-29: all 201 real markers sit in the
# heading, and every body-only match was content ([EXISTS], [IDEA], [DRAFT …, [ENRIQUE-REVIEW]) —
# scanning bodies would have hidden 24 entries.
# Marker = `[` + 3+ capitals (hyphens allowed) + space, colon, `]` or em dash. Lenient on purpose:
# the corpus has undated forms like `[ALREADY-PROMOTED — cleared …]` and `[SUPERSEDED by …]`.
#
# KNOWN BOUNDS: an UNDATED `####` born at the wrong level stays invisible (nothing to window it by);
# a heading carrying a content token shaped like a marker (`[WIP] …`) reads as dispositioned; with
# no audit log (fresh install) the h4suspect arm is off and reported as cutoff=none.
#
# ⚠ awk here must stay BSD-awk-safe (macOS): no `{m,n}` interval expressions.

set -u

KF="${1:-}"
MODE="${2:-}"
if [ -z "$KF" ] || [ ! -d "$KF" ]; then
  echo "usage: count-backlog-entries.sh <knowledge_folder> [--total | --list]" >&2
  exit 2
fi
case "$MODE" in
  ''|--total|--list) ;;
  *) echo "count-backlog-entries.sh: unknown mode '$MODE'" >&2; exit 2 ;;
esac

# Last audit pass date — same parse session-start-check.sh has always used: the first
# `- **Date:**` line of the audit log, first token only.
CUTOFF=""
LOG="$KF/logs/knowledge-audit-log.md"
if [ -f "$LOG" ]; then
  CUTOFF=$(grep '^- \*\*Date:\*\*' "$LOG" 2>/dev/null | head -1 | sed 's/.*\*\*Date:\*\* //; s/ .*//')
  echo "$CUTOFF" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || CUTOFF=""
fi

T3=0; T2=0; T4=0
for name in insights decisions extraction rules; do
  f="$KF/intake/$name-backlog.md"
  if [ ! -f "$f" ]; then
    [ -z "$MODE" ] && echo "$name: missing"
    continue
  fi
  out=$(awk -v cutoff="$CUTOFF" -v file="$f" -v list="$([ "$MODE" = --list ] && echo 1)" '
    function flush() {
      if (kind == 3) c3++
      else if (kind == 2 && body) {
        c2++; if (list) print file ":" hl ": h2-entry: " head
      } else if (kind == 4 && cutoff != "" && hdate != "" && hdate >= cutoff && !marked) {
        c4++; if (list) print file ":" hl ": h4-suspect: " head
      }
      kind = 0
    }
    function open_block(k) {
      flush(); kind = k; hl = FNR; head = $0; body = 0; hdate = ""; marked = 0
      if (k == 4) {
        if ($0 ~ /^#### [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) hdate = substr($0, 6, 10)
        if ($0 ~ /\[[A-Z][A-Z][A-Z][A-Z-]*([ :\]]|—)/) marked = 1
      }
    }
    !sep { if ($0 == "---") sep = 1; next }
    incomment { if (index($0, "-->")) incomment = 0; next }
    /^[ \t]*<!--/ {
      rest = substr($0, index($0, "<!--") + 4)
      if (!index(rest, "-->")) incomment = 1
      next
    }
    /^## /   { open_block(2); next }
    /^### /  { open_block(3); next }
    /^#### / { open_block(4); next }
    kind == 2 && $0 ~ /[^ \t]/ { body = 1 }
    END { flush(); if (!list) print c3 + 0, c2 + 0, c4 + 0 }
  ' "$f") || { echo "count-backlog-entries.sh: awk failed on $f" >&2; exit 1; }

  if [ "$MODE" = --list ]; then
    [ -n "$out" ] && printf '%s\n' "$out"
    continue
  fi
  set -- $out
  n3=$1; n2=$2; n4=$3
  T3=$((T3 + n3)); T2=$((T2 + n2)); T4=$((T4 + n4))
  [ -z "$MODE" ] && echo "$name: canonical=$n3 h2=$n2 h4suspect=$n4 live=$((n3 + n2 + n4))"
done

case "$MODE" in
  --total) echo $((T3 + T2 + T4)) ;;
  --list)  ;;
  *) echo "TOTAL: canonical=$T3 h2=$T2 h4suspect=$T4 live=$((T3 + T2 + T4)) cutoff=${CUTOFF:-none}" ;;
esac
