#!/usr/bin/env bats
# D8a census — every Antigravity suite that runs a wrapper which writes under $HOME must export a
# scratch HOME, or the suite writes the real ~/.gemini/antigravity/. Wrappers are discovered from
# their source (a reference to $HOME), suites from their text (an invocation of that wrapper).

@test "D8a: every suite running a HOME-writing wrapper exports HOME" {
  T="${BATS_TEST_DIRNAME}"
  A="$T/../bin/antigravity"
  missing=""
  checked=0
  for w in "$A"/*-aria.sh; do
    grep -q '\$HOME\|\${HOME' "$w" || continue
    wn=$(basename "$w")
    for f in "$T"/*.bats; do
      [ "$(basename "$f")" = "test-antigravity-tests-isolate-home.bats" ] && continue
      grep -q "$wn" "$f" || continue
      checked=$((checked+1))
      grep -Eq '^[[:space:]]*export HOME=' "$f" || missing="$missing $(basename "$f")"
    done
  done
  echo "suites checked: $checked; without a scratch HOME:${missing:- none}" >&2
  [ "$checked" -ge 2 ]
  [ -z "$missing" ]
}
