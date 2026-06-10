#!/bin/sh
# 4-8-thinking-and-failopen.sh — Opus 4.8 readiness regression.
#
# Locks two contracts a model/harness bump could silently break:
#   D. thinking-only marker — [Rule 22] marker appears ONLY in a thinking
#      block, never visible text. Contract: NON-compliant -> DENY. The marker
#      is an auditable, user-visible artifact; a thinking-only marker must not
#      satisfy enforcement. (If Opus 4.8 is found to route the marker into
#      thinking by default, the fix is a SessionStart nudge to emit it as text,
#      NOT flipping this expectation.)
#   E. id-absent (LOUD fail-open) — queried tool_use_id is not in the
#      transcript -> detector returns "unknown". Contract: ALLOW (no v2.10.5
#      deadlock) AND emit a visible warning systemMessage (enforcement is never
#      lost silently — Option 3).
#
# Run from any directory; resolves its own paths.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/plugin-claude-code/bin/pre-edit-check.sh"
FIXTURES="$REPO_ROOT/tests/fixtures"

# Isolate the deny-rate breaker's per-session counter (v2.30.0) to a fresh
# scratch dir so repeated suite runs never accumulate denials across runs.
export TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0

run_case() {
  case_name="$1"; fixture="$2"; tool_use_id="$3"; expect="$4"  # "allow" or "deny"
  input=$(printf '{"file_path":"/tmp/test.txt","transcript_path":"%s","tool_use_id":"%s"}' "$fixture" "$tool_use_id")
  output=$(printf '%s' "$input" | sh "$HOOK" 2>&1)
  exit_code=$?
  actual="allow"
  if printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then actual="deny"; fi
  if [ "$actual" = "$expect" ] && [ "$exit_code" -eq 0 ]; then
    printf "PASS  %s (expected=%s actual=%s exit=%d)\n" "$case_name" "$expect" "$actual" "$exit_code"; PASS=$((PASS + 1))
  else
    printf "FAIL  %s (expected=%s actual=%s exit=%d)\n" "$case_name" "$expect" "$actual" "$exit_code"
    printf "      output: %s\n" "$output"; FAIL=$((FAIL + 1))
  fi
}

run_warn_case() {
  # asserts: allowed (no deny) AND a degradation warning systemMessage present
  case_name="$1"; fixture="$2"; tool_use_id="$3"
  input=$(printf '{"file_path":"/tmp/test.txt","transcript_path":"%s","tool_use_id":"%s"}' "$fixture" "$tool_use_id")
  output=$(printf '%s' "$input" | sh "$HOOK" 2>&1)
  exit_code=$?
  if printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then
    printf "FAIL  %s (expected allow+warning, got DENY)\n      output: %s\n" "$case_name" "$output"; FAIL=$((FAIL + 1)); return
  fi
  if printf '%s' "$output" | grep -q 'could not verify this edit'; then
    printf "PASS  %s (allow + warning present, exit=%d)\n" "$case_name" "$exit_code"; PASS=$((PASS + 1))
  else
    printf "FAIL  %s (allowed but NO warning systemMessage)\n      output: %s\n" "$case_name" "$output"; FAIL=$((FAIL + 1))
  fi
}

run_planning_case() {
  # asserts a no-marker edit to a docs/superpowers/plans path is DENIED with the
  # PLANNING variant named — proving the path is classified as a planning path.
  case_name="$1"; fixture="$2"; tool_use_id="$3"; file_path="$4"
  input=$(printf '{"file_path":"%s","transcript_path":"%s","tool_use_id":"%s"}' "$file_path" "$fixture" "$tool_use_id")
  output=$(printf '%s' "$input" | sh "$HOOK" 2>&1)
  if printf '%s' "$output" | grep -q 'Planning'; then
    printf "PASS  %s (planning variant named in deny message)\n" "$case_name"; PASS=$((PASS + 1))
  else
    printf "FAIL  %s (expected planning variant; got full)\n      output: %s\n" "$case_name" "$output"; FAIL=$((FAIL + 1))
  fi
}

run_case          "D-thinking-only-marker-denies"   "$FIXTURES/transcript-thinking-only-marker.jsonl" "toolu_thinking_only" "deny"
run_warn_case     "E-id-absent-failopen-loud"       "$FIXTURES/transcript-id-absent.jsonl"            "toolu_query_missing"
run_planning_case "F-superpowers-plans-is-planning" "$FIXTURES/transcript-no-marker-planning.jsonl"   "toolu_plan_edit" "/x/docs/superpowers/plans/p.md"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
