#!/bin/sh
# Repro: deny-rate circuit breaker in pre-edit-check.sh (v2.30.0).
# Proves D1: 3 consecutive denials with no intervening compliant edit trip the
# breaker (allow + loud systemMessage); a compliant edit resets it; the unknown
# path never touches the counter; distinct session keys don't share state.
# Hermetic — the breaker counter lives in a per-run scratch TMPDIR.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$HERE/../.." && pwd)
HOOK="$REPO_ROOT/plugin-claude-code/bin/pre-edit-check.sh"
FIXTURES="$REPO_ROOT/tests/fixtures"
fail() { echo "FAIL: $1"; exit 1; }
export TMPDIR=$(mktemp -d); trap 'rm -rf "$TMPDIR"' EXIT

invoke() {  # session_key fixture tool_use_id
  printf '{"file_path":"/tmp/test.txt","session_id":"%s","transcript_path":"%s","tool_use_id":"%s"}' \
    "$1" "$FIXTURES/$2" "$3" | sh "$HOOK" 2>&1
}
is_deny()   { printf '%s' "$1" | grep -q '"permissionDecision":"deny"'; }
is_sysmsg() { printf '%s' "$1" | grep -q '"systemMessage"'; }

NC="transcript-split-noncompliant.jsonl"; NCID="toolu_test_noncompliant"
CP="transcript-split-compliant.jsonl";    CPID="toolu_test_compliant"

# --- 1) three denials, then trip on the 4th -------------------------------
SK="sess-breaker-A"
SF="$TMPDIR/aria-r22-denies-$SK"
is_deny "$(invoke "$SK" "$NC" "$NCID")" || fail "deny 1 expected"
is_deny "$(invoke "$SK" "$NC" "$NCID")" || fail "deny 2 expected"
is_deny "$(invoke "$SK" "$NC" "$NCID")" || fail "deny 3 expected"
o=$(invoke "$SK" "$NC" "$NCID")
is_sysmsg "$o" || fail "4th invocation should emit a systemMessage (breaker tripped): $o"
is_deny  "$o" && fail "4th invocation must NOT deny once tripped"
[ -f "$SF" ] || fail "counter file should exist while tripped"
[ "$(cat "$SF")" = "3" ] || fail "counter should read 3, got $(cat "$SF")"
# stays tripped on subsequent edits
o=$(invoke "$SK" "$NC" "$NCID"); is_sysmsg "$o" || fail "5th invocation should still warn-allow"
is_deny "$o" && fail "5th invocation must NOT deny while tripped"

# --- 2) a compliant edit resets the breaker -------------------------------
o=$(invoke "$SK" "$CP" "$CPID")
[ -z "$o" ] || fail "compliant edit should be allow-silent (empty stdout), got: $o"
[ -f "$SF" ] && fail "counter file should be removed after a compliant edit"
is_deny "$(invoke "$SK" "$NC" "$NCID")" || fail "post-reset noncompliant must deny again (reset proven)"
[ "$(cat "$SF")" = "1" ] || fail "post-reset counter should restart at 1, got $(cat "$SF" 2>/dev/null)"

# --- 3) unknown path never touches the counter ----------------------------
SK_U="sess-unknown"
SF_U="$TMPDIR/aria-r22-denies-$SK_U"
o=$(invoke "$SK_U" "transcript-id-absent.jsonl" "toolu_absent_xyz")
is_sysmsg "$o" || fail "id-absent should fail-open LOUD (systemMessage)"
is_deny "$o" && fail "id-absent should allow, not deny"
[ -f "$SF_U" ] && fail "unknown path must not create a counter file"

# --- 4) distinct session keys are independent -----------------------------
SK_B="sess-breaker-B"
SF_B="$TMPDIR/aria-r22-denies-$SK_B"
is_deny "$(invoke "$SK_B" "$NC" "$NCID")" || fail "B deny 1 expected"
[ "$(cat "$SF_B")" = "1" ] || fail "B counter should be 1, got $(cat "$SF_B" 2>/dev/null)"
[ "$(cat "$SF")"   = "1" ] || fail "A counter must be unchanged by B (independent), got $(cat "$SF" 2>/dev/null)"

echo "PASS r22-circuit-breaker"
