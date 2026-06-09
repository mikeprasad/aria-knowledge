#!/bin/sh
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/helpers.sh"
TMP="$(mktemp -d)"; export APM_TMP="$TMP"
trap 'rm -rf "$TMP"' EXIT
for t in "$DIR"/test-*.sh; do printf '== %s\n' "$(basename "$t")"; . "$t"; done
printf '\n%d passed, %d failed\n' "$APM_PASS" "$APM_FAIL"
[ "$APM_FAIL" -eq 0 ]
