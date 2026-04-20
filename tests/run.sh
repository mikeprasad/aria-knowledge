#!/bin/sh
# tests/run.sh — minimal runner for ARIA hook repros.
# Executes every *.sh under tests/repros/ and aggregates pass/fail.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_SUITES=""

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

printf "=== SUMMARY ===\n"
printf "%d suite(s) passed, %d suite(s) failed\n" "$TOTAL_PASS" "$TOTAL_FAIL"
if [ -n "$FAILED_SUITES" ]; then
  printf "Failed:%s\n" "$FAILED_SUITES"
  exit 1
fi
exit 0
