#!/bin/sh
# tests/run.sh — minimal runner for ARIA hook repros.
# Executes every *.sh under tests/repros/ and aggregates pass/fail.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_SUITES=""

# Real-rules guard (2026-10-25): session-start-check.sh writes $HOME/.claude/rules/,
# so a test that does not isolate HOME overwrites the developer's live rules files.
# Compare both files' bytes before and after the whole run.
rr_state() {
  for f in "$HOME/.claude/rules/aria-rules.md" "$HOME/.claude/rules/aria-user-rules.md"; do
    if [ -f "$f" ]; then cksum < "$f"; else echo absent; fi
  done
}
RR_BEFORE=$(rr_state)

for suite in repros/*.sh; do
  printf "=== %s ===\n" "$suite"
  if sh "$suite"; then
    TOTAL_PASS=$((TOTAL_PASS + 1))
  else
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    FAILED_SUITES="$FAILED_SUITES $suite"
  fi
  printf "\n"
done

if [ "$(rr_state)" != "$RR_BEFORE" ]; then
  printf "FAIL: a suite modified the real ~/.claude/rules files\n"
  TOTAL_FAIL=$((TOTAL_FAIL + 1)); FAILED_SUITES="$FAILED_SUITES real-rules-guard"
fi

printf "=== SUMMARY ===\n"
printf "%d suite(s) passed, %d suite(s) failed\n" "$TOTAL_PASS" "$TOTAL_FAIL"
if [ -n "$FAILED_SUITES" ]; then
  printf "Failed:%s\n" "$FAILED_SUITES"
  exit 1
fi
exit 0
