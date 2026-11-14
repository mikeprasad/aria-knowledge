#!/bin/sh
# tests/run.sh — minimal runner for ARIA hook repros.
# Executes every *.sh under tests/repros/ and aggregates pass/fail.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 2.58.0: every suite gets one scratch TMPDIR, stripped of any ACL it inherited. The state-dir
# resolver refuses a directory with an ACL (spec G2-1), and an inheritable ACL on the caller's TMPDIR
# passes down to every mktemp dir a suite makes there, so every hook went silent and dozens of arms
# failed for a reason unrelated to what they test (measured 2026-11-14). Stripping it once here cuts
# the inheritance for every suite below.
# The inherited TMPDIR's trailing "/" is stripped first: macOS sets TMPDIR with one, and an embedded
# "//" in every path below is kept by sh but normalised by Python, which split the resolver parity arms.
_kt_inherited_tmp=${TMPDIR:-/tmp}
KT_TEST_TMP=$(mktemp -d "${_kt_inherited_tmp%/}/aria-tests.XXXXXX")
chmod -N "$KT_TEST_TMP" 2>/dev/null || :
if command -v setfacl >/dev/null 2>&1; then setfacl -b "$KT_TEST_TMP" 2>/dev/null || :; fi
TMPDIR=$KT_TEST_TMP
export TMPDIR
trap 'rm -rf "$KT_TEST_TMP"' EXIT
# 2.58.0: the session-start sweeps now reach the real /tmp (they start at "/tmp/"), so every hook a
# repro runs sweeps a scratch dir instead (KT_TMP_SWEEP_ROOT is the test-only override).
KT_TMP_SWEEP_ROOT=$(mktemp -d "$TMPDIR/aria-sweep-root.XXXXXX")
export KT_TMP_SWEEP_ROOT
# 2.58.0: hook state lives in <base>/aria-knowledge-<uid> (lib-state-key.sh). Every hook a repro runs
# resolves it under this scratch base (KT_STATE_BASE is the test-only override), never in the user's
# real state directory.
KT_STATE_BASE=$(mktemp -d "$TMPDIR/aria-state-base.XXXXXX")
export KT_STATE_BASE

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
