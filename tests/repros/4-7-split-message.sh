#!/bin/sh
# 4-7-split-message.sh — regression test for v2.10.5 -> v2.10.6 fix.
#
# Validates that pre-edit-check.sh correctly handles Opus 4.7's split-message
# transcript shape (text and tool_use in separate assistant messages).
#
# Three cases:
#   A. compliant split-message — marker in preceding assistant text message,
#      tool_use in next assistant message. Expected: empty stdout (allow).
#   B. non-compliant split-message — no marker in any preceding text block.
#      Expected: stdout contains 'permissionDecision":"deny'.
#   C. second-edit-uncovered — marker covers first edit's tool_use_id, but
#      querying the second edit's tool_use_id should deny (marker belongs to
#      the first edit; second edit needs its own marker).
#
# Run from any directory; resolves its own paths.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/plugin/bin/pre-edit-check.sh"
FIXTURES="$REPO_ROOT/tests/fixtures"

PASS=0
FAIL=0

run_case() {
  case_name="$1"
  fixture="$2"
  tool_use_id="$3"
  expect="$4"  # "allow" or "deny"

  input=$(printf '{"file_path":"/tmp/test.txt","transcript_path":"%s","tool_use_id":"%s"}' "$fixture" "$tool_use_id")
  output=$(printf '%s' "$input" | sh "$HOOK" 2>&1)
  exit_code=$?

  actual="allow"
  if printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then
    actual="deny"
  fi

  if [ "$actual" = "$expect" ] && [ "$exit_code" -eq 0 ]; then
    printf "PASS  %s (expected=%s actual=%s exit=%d)\n" "$case_name" "$expect" "$actual" "$exit_code"
    PASS=$((PASS + 1))
  else
    printf "FAIL  %s (expected=%s actual=%s exit=%d)\n" "$case_name" "$expect" "$actual" "$exit_code"
    printf "      output: %s\n" "$output"
    FAIL=$((FAIL + 1))
  fi
}

run_case "A-compliant-split-message"       "$FIXTURES/transcript-split-compliant.jsonl"       "toolu_test_compliant"       "allow"
run_case "B-noncompliant-no-marker"        "$FIXTURES/transcript-split-noncompliant.jsonl"    "toolu_test_noncompliant"    "deny"
run_case "C-second-edit-needs-own-marker"  "$FIXTURES/transcript-second-edit-uncovered.jsonl" "toolu_second_edit_uncovered" "deny"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
