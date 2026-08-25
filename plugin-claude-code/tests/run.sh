#!/bin/sh
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/helpers.sh"
TMP="$(mktemp -d)"; export APM_TMP="$TMP"
trap 'rm -rf "$TMP"' EXIT
for t in "$DIR"/test-*.sh; do
  printf '== %s\n' "$(basename "$t")"
  # Syntax-check BEFORE sourcing. A test file that fails to PARSE used to abort
  # the run mid-way: the parse error printed, the totals line never did, and the
  # suite exited 0 — a false green that a CI gate would pass. Counting it as a
  # failure keeps the run going and makes the exit code mean something.
  if ! PARSE_ERR=$(sh -n "$t" 2>&1); then
    APM_FAIL=$((APM_FAIL+1))
    printf '  FAIL: %s does not parse\n    %s\n' "$(basename "$t")" "$PARSE_ERR"
    continue
  fi
  . "$t"
done
printf '\n%d passed, %d failed\n' "$APM_PASS" "$APM_FAIL"
[ "$APM_FAIL" -eq 0 ]
