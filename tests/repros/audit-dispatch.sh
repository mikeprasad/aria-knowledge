#!/bin/sh
# audit-dispatch.sh — /audit documents an unambiguous dispatch grammar over the three
# sub-audits, preserves direct back-compat invocation, and fails loud on unknown verbs.
# (Dogfood ceiling — asserts the SKILL.md DOCUMENTS the contract, not runtime dispatch.)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SK="$REPO_ROOT/plugin-claude-code/skills/audit/SKILL.md"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
[ -f "$SK" ] || { bad "exists" "no audit/SKILL.md"; printf "\n0 passed, 1 failed\n"; exit 1; }
# A: the four bare-menu options documented
for v in knowledge config style all; do
  grep -qiF "$v" "$SK" && ok "menu option: $v" || bad "menu $v" "not documented"
done
# B: delegation via the Skill tool to each sub-skill
for s in audit-knowledge audit-config audit-style; do
  grep -qF "$s" "$SK" && ok "delegates to $s" || bad "delegate $s" "sub-skill not referenced"
done
# C: unknown-verb path documented (no silent fail)
grep -qiE 'unknown|not a valid|list.*verb|valid.*(sub-?command|verb)' "$SK" && ok "unknown-verb handled" || bad "unknown-verb" "no unknown-verb branch"
# D: back-compat — direct /audit-knowledge and /audit-config still valid
grep -qiE 'directly invocable|still.*(invoke|work)|back-?compat|/audit-knowledge' "$SK" && ok "back-compat documented" || bad "back-compat" "no direct-invocation note"
# E: style is opt-in — NOT run by bare /audit's default execution
grep -qiE 'opt-in|explicit|not.*(routine|cadence|default execution)' "$SK" && ok "style opt-in documented" || bad "opt-in" "style opt-in not stated"
printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
