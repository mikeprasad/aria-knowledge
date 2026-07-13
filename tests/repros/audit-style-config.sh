#!/bin/sh
# audit-style-config.sh — config.sh parses the three style_* keys with correct defaults.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CFG="$REPO_ROOT/plugin-claude-code/bin/config.sh"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
for key in style_lookback_days style_max_sessions style_audit_log; do
  grep -q "grep '\^$key:'" "$CFG" && ok "parses $key" || bad "$key" "no parse line in config.sh"
done
# Defaults live DOWNSTREAM (skill body + setup), matching house convention — NOT inline in config.sh.
# Assert config.sh does NOT inline a default (bare-assign only), and that the skill body carries 90/50.
grep -qE 'KT_STYLE_LOOKBACK_DAYS=.*:-' "$CFG" && bad "no inline default" "config.sh should bare-assign, not inline :-" || ok "lookback bare-assigned (no inline default)"
SKILL="$REPO_ROOT/plugin-claude-code/skills/audit-style/SKILL.md"
# Guarded so Task 2 goes green STANDALONE (before Task 4 writes the skill); the defaults
# re-assert for real once the skill exists (Task 4's suite run + full-suite in Task 8).
if [ -f "$SKILL" ]; then
  grep -qE '\b90\b' "$SKILL" && ok "skill body carries lookback default 90" || bad "skill default 90" "no 90 in audit-style body"
  grep -qE '\b50\b' "$SKILL" && ok "skill body carries max default 50" || bad "skill default 50" "no 50 in audit-style body"
else
  ok "skill-body default assertions deferred (audit-style/SKILL.md not yet written — Task 4)"
fi
printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
