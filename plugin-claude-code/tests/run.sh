#!/bin/sh
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/helpers.sh"
TMP="$(mktemp -d)"; export APM_TMP="$TMP"
trap 'rm -rf "$TMP"' EXIT
# v2.54.2: isolate TMPDIR for every test. Tests write hook state under
# ${TMPDIR:-/tmp}, and test-external-fetch-gate.sh's ef_reset removes aria-extfetch-*
# there — against the REAL TMPDIR that deleted every live session's fetch cooldowns and
# breaker counters on each run. Guarded by tests/repros/plugin-suite-leaves-real-tmpdir-alone.sh.
export TMPDIR="$TMP/tmpdir"; mkdir -p "$TMPDIR"
# Real-rules guard (2026-10-25): session-start-check.sh writes $HOME/.claude/rules/,
# so a test that does not isolate HOME overwrites the developer's live rules files.
# Compare both files' bytes before and after the whole run.
rr_state() {
  for f in "$HOME/.claude/rules/aria-rules.md" "$HOME/.claude/rules/aria-user-rules.md"; do
    if [ -f "$f" ]; then cksum < "$f"; else echo absent; fi
  done
}
RR_BEFORE=$(rr_state)
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
if [ "$(rr_state)" != "$RR_BEFORE" ]; then
  APM_FAIL=$((APM_FAIL+1))
  printf '  FAIL: a test modified the real ~/.claude/rules files\n'
fi
printf '\n%d passed, %d failed\n' "$APM_PASS" "$APM_FAIL"
[ "$APM_FAIL" -eq 0 ]
