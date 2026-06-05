#!/bin/sh
# Repro: statusline-meter.sh writes a runtime-aware snapshot — keyed by the resolved
# account, with session_id / runtime / seven_day_resets_at, CLI-only email, and
# context_pct omitted when the payload carries no context measurement (post-/compact).
# Runtime pinned to CLI; real PATH kept so jq is reachable.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
METER="$HERE/../../plugin-claude-code/bin/statusline-meter.sh"
fail() { echo "FAIL: $1"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP statusline-meter (no jq)"; exit 0; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"; mkdir -p "$HOME/.claude"
cat > "$HOME/.claude.json" <<'JSON'
{"oauthAccount":{"accountUuid":"cli-uuid-1","emailAddress":"a@example.com"}}
JSON
unset CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH __CFBundleIdentifier 2>/dev/null || true

PAYLOAD='{"session_id":"S1","model":{"display_name":"Opus"},"context_window":{"used_percentage":40},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1780000000},"seven_day":{"used_percentage":50,"resets_at":1781000000}}}'
printf '%s' "$PAYLOAD" | sh "$METER" >/dev/null
ST="$HOME/.claude/aria-statusline-state-cli-uuid-1.json"
[ -f "$ST" ] || fail "snapshot not written to resolved key"
[ "$(jq -r '.session_id' "$ST")" = "S1" ] || fail "session_id not stamped"
[ "$(jq -r '.runtime' "$ST")" = "cli" ] || fail "runtime not stamped cli"
[ "$(jq -r '.seven_day_resets_at' "$ST")" = "1781000000" ] || fail "seven_day_resets_at missing"
[ "$(jq -r '.account_email' "$ST")" = "a@example.com" ] || fail "CLI email should be present"
[ "$(jq -r '.context_pct' "$ST")" = "40" ] || fail "context_pct should be 40"

# context null payload (post-/compact) -> context_pct omitted
P2='{"session_id":"S1","model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1780000000}}}'
printf '%s' "$P2" | sh "$METER" >/dev/null
v=$(jq -r '.context_pct // "ABSENT"' "$ST")
[ "$v" = "ABSENT" ] || fail "context_pct should be absent when payload has no context; got $v"
echo "PASS statusline-meter"
