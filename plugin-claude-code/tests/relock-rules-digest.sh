#!/bin/sh
# relock-rules-digest.sh — refresh the digest lock after REVIEWING specific rules.
#
#   sh plugin-claude-code/tests/relock-rules-digest.sh 7 23    # re-lock rules 7 and 23
#   sh plugin-claude-code/tests/relock-rules-digest.sh --init  # first lock only; refuses if one exists
#
# There is deliberately no "all" mode. The lock exists so that changing a working rule, or its
# line in the always-on digest, forces someone to look at the other half. A command that
# restamps every rule turns that into a ritual, which is how PORT-LEDGER's bulk --update came to
# be refused for codex ("a bump would assert a parity that does not exist"). Naming each rule
# makes each restamp a statement that that rule was reviewed.
set -u
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PCC="$(cd "$TESTS_DIR/.." && pwd)"
SRC="$PCC/template/rules/working-rules.md"
DIGEST="$PCC/rules/aria-rules.md"
LOCK="$TESTS_DIR/fixtures/aria-rules.digest-lock.tsv"
. "$TESTS_DIR/lib-digest-lock.sh"

die() { echo "relock-rules-digest: $*" >&2; exit 1; }
EMPTY=$(kt_dl_empty_sha)

line_for() { # N -> "N<TAB>source<TAB>digest", or die on an empty extraction
  s=$(kt_dl_source_sha "$SRC" "$1"); d=$(kt_dl_digest_sha "$DIGEST" "$1")
  [ "$s" = "$EMPTY" ] && die "rule $1: source section extracted empty — not locking"
  [ "$d" = "$EMPTY" ] && die "rule $1: digest line extracted empty — not locking"
  printf '%s\t%s\t%s\n' "$1" "$s" "$d"
}

[ $# -eq 0 ] && die "name the rules you reviewed (e.g. 7 23), or --init for the first lock"

TMP="$LOCK.tmp.$$"
trap 'rm -f "$TMP"' EXIT

if [ "$1" = "--init" ]; then
  [ $# -eq 1 ] || die "--init takes no other arguments"
  [ -e "$LOCK" ] && die "a lock already exists at $LOCK — re-lock specific rules instead"
  mkdir -p "$(dirname "$LOCK")" || die "cannot create $(dirname "$LOCK")"
  for n in $(kt_dl_source_nums "$SRC"); do line_for "$n" >> "$TMP" || exit 1; done
  [ -s "$TMP" ] || die "no rules found in $SRC"
  mv "$TMP" "$LOCK" || die "could not write $LOCK"
  echo "relock-rules-digest: wrote $(wc -l < "$LOCK" | tr -d ' ') rule(s) to $LOCK"
  exit 0
fi

[ -s "$LOCK" ] || die "no lock at $LOCK — run --init first"
known=" $(kt_dl_source_nums "$SRC" | tr '\n' ' ') "
for n in "$@"; do
  case "$n" in ''|*[!0-9]*) die "not a rule number: $n" ;; esac
  case "$known" in *" $n "*) ;; *) die "rule $n is not in $SRC" ;; esac
done

cp "$LOCK" "$TMP" || die "could not copy $LOCK"
for n in "$@"; do
  new=$(line_for "$n") || exit 1
  awk -F'\t' -v n="$n" -v new="$new" 'BEGIN { OFS = "\t" } $1 == n { print new; done = 1; next } { print } END { if (!done) print new }' \
    "$TMP" > "$TMP.2" && mv "$TMP.2" "$TMP" || die "could not update rule $n"
done
sort -n -k1,1 "$TMP" > "$TMP.2" && mv "$TMP.2" "$LOCK" || die "could not write $LOCK"
echo "relock-rules-digest: re-locked rule(s) $*"
