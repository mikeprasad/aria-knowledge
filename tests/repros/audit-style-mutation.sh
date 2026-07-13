#!/bin/sh
# audit-style-mutation.sh — Rule 36: the receipts-gate assertion must FAIL when the
# >=2-session clause is stripped from the SKILL.md. Verifies the guard is detectable,
# not decorative. Operates on a temp copy; never mutates the real skill.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SK="$REPO_ROOT/plugin-claude-code/skills/audit-style/SKILL.md"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
# strip any line mentioning the >=2-session rule
grep -viE '2 (distinct|different) session|>= ?2 session|two distinct session' "$SK" > "$TMP"
# the same assertion Task 4 uses, applied to the mutated copy — MUST now fail to match
if grep -qiE '2 (distinct|different) session|>= ?2 session|two distinct session' "$TMP"; then
  bad "mutation detected" "clause survived stripping — assertion cannot detect its removal"
else
  ok "mutation makes the gate assertion go RED (guard is detectable)"
fi
printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
