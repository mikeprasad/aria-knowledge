#!/bin/sh
# cron-slash-guard.sh — standing directive D2: a scheduled prompt must never begin
# with '/'. A leading slash token is parsed as a command; when it does not resolve,
# the whole mandate is silently discarded.
#
# This rule shipped as PROSE in v2.37.3 and was violated twice afterward, which is
# the evidence that prose alone does not hold it. The guard is a hook, and this
# suite exists to watch the guard FAIL on a violating input — a guard never
# observed failing is not a guard.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/plugin-claude-code/bin/pre-cron-check.sh"
MANIFEST="$REPO_ROOT/plugin-claude-code/.claude-plugin/plugin.json"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

[ -x "$HOOK" ] && ok "A hook exists and is executable" || bad "A exists" "missing or not +x"

# B — the RED case: a slash-leading prompt must be denied.
OUT=$(printf '%s' '{"tool_name":"CronCreate","tool_input":{"cron":"5 4 * * *","prompt":"/auto execute the plan"}}' | sh "$HOOK" 2>/dev/null || true)
echo "$OUT" | grep -q '"permissionDecision":"deny"' \
  && ok "B denies a /-leading prompt" || bad "B deny" "no deny for '/auto ...' (got: $OUT)"
echo "$OUT" | grep -qi 'prose' \
  && ok "B reason tells the caller what to do" || bad "B reason" "deny reason lacks guidance"

# C — the GREEN case: a prose-leading prompt must pass silently.
OUT2=$(printf '%s' '{"tool_name":"CronCreate","tool_input":{"cron":"5 4 * * *","prompt":"This is a scheduled resume. Verify state first."}}' | sh "$HOOK" 2>/dev/null || true)
echo "$OUT2" | grep -q '"permissionDecision":"deny"' \
  && bad "C allows prose" "denied a legitimate prose prompt" || ok "C allows a prose prompt"

# D — leading whitespace must not smuggle a slash past the guard.
OUT3=$(printf '%s' '{"tool_name":"CronCreate","tool_input":{"prompt":"   /auto continue"}}' | sh "$HOOK" 2>/dev/null || true)
echo "$OUT3" | grep -q '"permissionDecision":"deny"' \
  && ok "D strips leading whitespace before testing" || bad "D whitespace" "whitespace + slash slipped through"

# E — a slash appearing mid-prompt is legitimate and must NOT be denied.
OUT4=$(printf '%s' '{"tool_name":"CronCreate","tool_input":{"prompt":"Resume the arc; you may invoke the auto skill and read docs/plans/x.md."}}' | sh "$HOOK" 2>/dev/null || true)
echo "$OUT4" | grep -q '"permissionDecision":"deny"' \
  && bad "E mid-prompt slash" "denied a prompt whose slash is not leading" || ok "E allows a mid-prompt slash"

# F — the other scheduling verb is covered by the same rule.
OUT5=$(printf '%s' '{"tool_name":"mcp__scheduled-tasks__create_scheduled_task","tool_input":{"taskId":"x","prompt":"/auto continue"}}' | sh "$HOOK" 2>/dev/null || true)
echo "$OUT5" | grep -q '"permissionDecision":"deny"' \
  && ok "F covers the persisted-task verb too" || bad "F scheduled-tasks" "not denied (got: $OUT5)"

# G — unparseable input must fail OPEN, never block a well-formed schedule.
OUT6=$(printf '%s' '{"tool_name":"CronCreate","tool_input":{"cron":"5 4 * * *"}}' | sh "$HOOK" 2>/dev/null || true)
[ -z "$OUT6" ] && ok "G fails open on a missing prompt" || bad "G fail-open" "emitted output with no prompt field: $OUT6"

# H — registered in the manifest, matching both scheduling verbs.
grep -q 'pre-cron-check.sh' "$MANIFEST" \
  && ok "H registered in plugin.json" || bad "H registered" "hook not wired"
grep -q 'CronCreate' "$MANIFEST" \
  && ok "H matcher covers CronCreate" || bad "H matcher" "no CronCreate matcher"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
