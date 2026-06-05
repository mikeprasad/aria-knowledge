#!/bin/sh
# Repro: usage-threshold-inject 5h/7d staleness guard + context session/null guard,
# keyed via the shared runtime-aware resolver. Runtime pinned to CLI/default by
# unsetting Desktop signals; real PATH kept so jq stays reachable.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
HOOK="$HERE/../../plugin-claude-code/bin/usage-threshold-inject.sh"
fail() { echo "FAIL: $1"; exit 1; }
TMP=$(mktemp -d)
SP="injtest-$$"
trap 'rm -rf "$TMP"; rm -f /tmp/aria-usage-warn-${SP}-* 2>/dev/null' EXIT
export HOME="$TMP"; mkdir -p "$HOME/.claude"
cat > "$HOME/.claude.json" <<'JSON'
{"oauthAccount":{"accountUuid":"cli-uuid-1","emailAddress":"a@example.com"}}
JSON
export KT_CONFIG="$HOME/.claude/aria-knowledge.local.md"
printf -- '---\nusage_alert_threshold: 80\n---\n' > "$KT_CONFIG"
unset CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH __CFBundleIdentifier 2>/dev/null || true

NOW=$(date +%s); PAST=$((NOW-3600)); FUT=$((NOW+3600))
STATE="$HOME/.claude/aria-statusline-state-cli-uuid-1.json"
run() { printf '{"session_id":"%s"}' "$1" | sh "$HOOK"; }   # real PATH (jq), HOME isolated

# (a) 5h over threshold, window NOT reset -> alerts
cat > "$STATE" <<JSON
{"five_hour_pct":95,"five_hour_resets_at":$FUT,"seven_day_pct":10,"context_pct":10,"session_id":"${SP}-a","written_at":"x"}
JSON
out=$(run "${SP}-a"); printf '%s' "$out" | grep -q "5-hour" || fail "(a) expected 5h alert; got: $out"

# (b) 5h over threshold but window already reset (now>resets_at) -> NO 5h alert
cat > "$STATE" <<JSON
{"five_hour_pct":95,"five_hour_resets_at":$PAST,"seven_day_pct":10,"context_pct":10,"session_id":"${SP}-b","written_at":"x"}
JSON
out=$(run "${SP}-b"); printf '%s' "$out" | grep -q "5-hour" && fail "(b) stale 5h must NOT alert; got: $out"

# (c) context over threshold, session matches -> context alert
cat > "$STATE" <<JSON
{"five_hour_pct":10,"five_hour_resets_at":$FUT,"context_pct":95,"session_id":"${SP}-c","written_at":"x"}
JSON
out=$(run "${SP}-c"); printf '%s' "$out" | grep -qi "context" || fail "(c) expected context alert; got: $out"

# (d) context over threshold but DIFFERENT session -> NO context alert
out=$(run "${SP}-d"); printf '%s' "$out" | grep -qi "context" && fail "(d) cross-session context must NOT alert; got: $out"

# (e) context null (post-/compact) -> NO context alert
cat > "$STATE" <<JSON
{"five_hour_pct":10,"five_hour_resets_at":$FUT,"context_pct":null,"session_id":"${SP}-e","written_at":"x"}
JSON
out=$(run "${SP}-e"); printf '%s' "$out" | grep -qi "context" && fail "(e) null context must NOT alert; got: $out"

echo "PASS statusline-inject"
