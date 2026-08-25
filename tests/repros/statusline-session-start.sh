#!/bin/sh
# Repro: session-start-check.sh keys the TASK BUDGET snapshot pointer via the shared
# resolver, and teaches the agent the staleness/scope rule. Runtime pinned to CLI.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../../plugin-claude-code/bin/session-start-check.sh"
fail() { echo "FAIL: $1"; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"; mkdir -p "$HOME/.claude"
cat > "$HOME/.claude.json" <<'JSON'
{"oauthAccount":{"accountUuid":"cli-uuid-1"}}
JSON
export KT_CONFIG="$HOME/.claude/aria-knowledge.local.md"
mkdir -p "$HOME/.claude/k/logs"   # folder must exist or session-start short-circuits with a /setup reminder
# A non-first-run audit log (not "(no audits yet)") so the script passes the welcome
# branch and reaches the TASK BUDGET section we're testing.
echo "# knowledge audit log" > "$HOME/.claude/k/logs/knowledge-audit-log.md"
# Statusline meter installed: a state file keyed by the resolved (CLI) account must
# exist for the hook to emit the snapshot-pointer TASK BUDGET branch this repro asserts
# (the v2.25.1 branch-gating at session-start-check.sh:238 gates on file presence).
cat > "$HOME/.claude/aria-statusline-state-cli-uuid-1.json" <<'JSON'
{"session_id":"S1","context_pct":12,"five_hour_pct":8,"seven_day_pct":21,"five_hour_resets_at":"2026-06-11T18:00:00Z","seven_day_resets_at":"2026-06-15T00:00:00Z"}
JSON
printf -- '---\nknowledge_folder: %s/.claude/k\n---\n' "$HOME" > "$KT_CONFIG"
unset CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH __CFBundleIdentifier 2>/dev/null || true

out=$(printf '{"session_id":"S1","source":"startup"}' | sh "$SCRIPT" 2>/dev/null)

# Path keyed by the resolved (CLI) account, not a hard-coded ~/.claude.json read
printf '%s' "$out" | grep -q "aria-statusline-state-cli-uuid-1.json" || fail "USAGE_SNAP key not resolved: $out"
# Staleness/scope rule taught to the agent.
#
# RE-SCOPED (v2.47.0), not relaxed. This used to assert against
# session-start-check.sh, which emits systemMessage — a channel that renders to
# the user's terminal and never reaches the model. So the guard was passing on a
# payload the agent could not read. The directive now lives in
# session-start-rules.sh on hookSpecificOutput.additionalContext, so the
# assertion follows it there and is checked on the DECODED payload: the property
# is "the agent is taught the rule", and only the decoded value proves that.
RULES_HOOK="$HERE/../../plugin-claude-code/bin/session-start-rules.sh"
rules_out=$(sh "$RULES_HOOK" 2>/dev/null)
printf '%s' "$rules_out" | grep -q "additionalContext" \
  || fail "session-start-rules.sh did not emit additionalContext: $rules_out"
printf '%s' "$rules_out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null \
  | grep -qi "resets_at" || fail "missing resets_at staleness rule in the model-facing payload"
# And it must NOT have regressed into telling the agent to decide from usage.
printf '%s' "$rules_out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null \
  | grep -qi "judging whether to keep going" \
  && fail "TASK BUDGET regressed: tells the agent to gate stopping on usage"
# Same re-scope, same reason: these assert content of the TASK BUDGET directive,
# which now lives in the model-facing hook.
rules_ctx=$(printf '%s' "$rules_out" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)
printf '%s' "$rules_ctx" | grep -qi "re-read" || fail "missing re-read-fresh directive"
printf '%s' "$rules_ctx" | grep -qi "session_id" || fail "missing context session-scope rule"
# The user-facing hook keeps a pointer to the snapshot, but must no longer carry
# the directive body — leaving it there keeps a corrected behaviour one
# channel-flip from returning.
printf '%s' "$out" | grep -qi "re-read it fresh at decision time" \
  && fail "old hook still carries the TASK BUDGET directive body"
echo "PASS statusline-session-start"
