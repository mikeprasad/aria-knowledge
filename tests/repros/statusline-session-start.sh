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
printf -- '---\nknowledge_folder: %s/.claude/k\n---\n' "$HOME" > "$KT_CONFIG"
unset CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH __CFBundleIdentifier 2>/dev/null || true

out=$(printf '{"session_id":"S1","source":"startup"}' | sh "$SCRIPT" 2>/dev/null)

# Path keyed by the resolved (CLI) account, not a hard-coded ~/.claude.json read
printf '%s' "$out" | grep -q "aria-statusline-state-cli-uuid-1.json" || fail "USAGE_SNAP key not resolved: $out"
# Staleness/scope rule taught to the agent
printf '%s' "$out" | grep -qi "resets_at" || fail "missing resets_at staleness rule"
printf '%s' "$out" | grep -qi "re-read" || fail "missing re-read-fresh directive"
printf '%s' "$out" | grep -qi "session_id" || fail "missing context session-scope rule"
echo "PASS statusline-session-start"
