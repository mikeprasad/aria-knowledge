#!/bin/sh
# tests/repros/statusline-usage.sh — assertions for the status-line meter +
# usage-threshold-inject hook (the v2.23/[Unreleased] statusline feature).
#
# Locks the contracts the feature shipped without a regression guard:
#   - statusline-meter.sh: empty-input degrade, model-only, full-payload segment
#     rendering, float rounding, and the agent-readable state-snapshot write.
#   - usage-threshold-inject.sh: fires over threshold, stays silent below it,
#     band-gates repeat fires, and honours `off`. The threshold default (80) is
#     resolved by config.sh, so we drive it via KT_CONFIG like the sibling repros.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
METER="$ROOT/plugin-claude-code/bin/statusline-meter.sh"
INJECT="$ROOT/plugin-claude-code/bin/usage-threshold-inject.sh"
TMP=$(mktemp -d)
# usage-threshold-inject keys its anti-spam band file off session_id in /tmp
# (correct production behavior). Use a per-PID session prefix so repeated runs of
# this repro never inherit a prior run's recorded band, and clean them on exit.
SP="repro-$$"
trap 'rm -rf "$TMP"; rm -f /tmp/aria-usage-warn-${SP}-* 2>/dev/null' EXIT
PASS=0; FAIL=0
# ESC built at runtime: BSD sed (macOS) does not interpret a literal \033 escape
# in the pattern, so '\033\[...' is an inert no-op there. Inject the byte instead.
_ESC=$(printf '\033')
strip_ansi() { sed "s/${_ESC}\[[0-9;]*m//g"; }
assert_contains() { if printf '%s' "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: %s (got: %s)\n' "$1" "$2"; fi; }
assert_absent()   { if printf '%s' "$2" | grep -q "$3"; then FAIL=$((FAIL+1)); printf 'FAIL: %s (unexpectedly found: %s)\n' "$1" "$3"; else PASS=$((PASS+1)); fi; }
assert_empty()    { if [ -z "$2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: %s (got: %s)\n' "$1" "$2"; fi; }

# Isolated HOME so the meter's snapshot write + the hook's state read never touch
# the real ~/.claude.
H="$TMP/home"; mkdir -p "$H/.claude"

# ---------- statusline-meter.sh ----------
OUT=$(printf '' | HOME="$H" sh "$METER" | strip_ansi)
assert_contains "meter: empty input degrades to 'Claude'" "$OUT" "Claude"

OUT=$(printf '{"model":{"display_name":"Opus 4.8"}}' | HOME="$H" sh "$METER" | strip_ansi)
assert_contains "meter: model-only renders the model name" "$OUT" "Opus 4.8"
assert_absent  "meter: model-only renders no ctx segment"  "$OUT" "ctx"

FULL='{"model":{"display_name":"Opus 4.8"},"context_window":{"used_percentage":42.7},"rate_limits":{"five_hour":{"used_percentage":88,"resets_at":1900000000},"seven_day":{"used_percentage":12}}}'
OUT=$(printf '%s' "$FULL" | HOME="$H" sh "$METER" | strip_ansi)
assert_contains "meter: float ctx 42.7 rounds to 43%" "$OUT" "43%"
assert_contains "meter: renders ctx label"            "$OUT" "ctx"
assert_contains "meter: renders 5h segment"           "$OUT" "5h 88%"
assert_contains "meter: renders 7d segment"           "$OUT" "7d 12%"

# state snapshot — the only channel by which the agent can read its own usage.
# No ~/.claude.json in the test HOME, so the meter + hook resolve the account key
# to "default" and use the default-keyed file (per-account keying tested below).
SNAP="$H/.claude/aria-statusline-state-default.json"
if [ -f "$SNAP" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: meter writes a state snapshot\n'; fi
# jq -n pretty-prints (space after colon); match that form
assert_contains "meter: snapshot carries context_pct 43"   "$(cat "$SNAP" 2>/dev/null)" '"context_pct": 43'
assert_contains "meter: snapshot carries five_hour_pct 88" "$(cat "$SNAP" 2>/dev/null)" '"five_hour_pct": 88'

# ---- v2.24.1: model "(1M context)" trim + am/pm reset clocks ----
# TZ-pinned so the formatted clock is deterministic on any machine / CI.
# 1893502800 = 2030-01-01 13:00 UTC (Tue);  1893504600 = 13:30 UTC.
ONHOUR='{"model":{"display_name":"Opus 4.8 (1M context)"},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":1893502800},"seven_day":{"used_percentage":12,"resets_at":1893502800}}}'
OUT=$(printf '%s' "$ONHOUR" | HOME="$H" TZ=UTC sh "$METER" | strip_ansi)
assert_contains "meter: model '(1M context)' trims to '(1M)'"   "$OUT" "(1M)"
assert_absent  "meter: model drops the ' context' token"        "$OUT" "context"
assert_contains "meter: 5h reset renders am/pm"                 "$OUT" "5h 40% ↺1pm"
assert_absent  "meter: 5h on-the-hour drops :00"               "$OUT" "1:00pm"
assert_contains "meter: 7d reset renders weekday + am/pm"       "$OUT" "7d 12% ↺Tue 1pm"

HALF='{"model":{"display_name":"Opus 4.8 (1M context)"},"rate_limits":{"five_hour":{"used_percentage":40,"resets_at":1893504600},"seven_day":{"used_percentage":12,"resets_at":1893504600}}}'
OUT=$(printf '%s' "$HALF" | HOME="$H" TZ=UTC sh "$METER" | strip_ansi)
assert_contains "meter: 5h off-the-hour keeps minutes" "$OUT" "5h 40% ↺1:30pm"
assert_contains "meter: 7d off-the-hour keeps minutes" "$OUT" "7d 12% ↺Tue 1:30pm"

# 7d present but resets_at absent → percentage still renders, no reset arrow.
NORST='{"model":{"display_name":"Opus 4.8"},"rate_limits":{"seven_day":{"used_percentage":40}}}'
OUT=$(printf '%s' "$NORST" | HOME="$H" TZ=UTC sh "$METER" | strip_ansi)
assert_contains "meter: 7d w/o resets_at still renders percentage" "$OUT" "7d 40%"
assert_absent  "meter: 7d w/o resets_at renders no reset arrow"    "$OUT" "↺"

# ---------- usage-threshold-inject.sh ----------
cfg() { cat > "$1" <<EOF
---
knowledge_folder: $TMP/kn
usage_alert_threshold: $2
---
EOF
mkdir -p "$TMP/kn"; }

# state: ctx / 5h / 7d driven per case
snap() { cat > "$SNAP" <<EOF
{"written_at":"2026-06-03T17:00:00Z","model":"Opus 4.8","context_pct":$1,"five_hour_pct":$2,"five_hour_resets_at":1900000000,"seven_day_pct":$3}
EOF
}

cfg "$TMP/default.md" 80
snap 43 88 12
SID='{"session_id":"'"${SP}"'-a"}'
OUT=$(printf '%s' "$SID" | HOME="$H" KT_CONFIG="$TMP/default.md" sh "$INJECT")
assert_contains "inject: 5h@88 over 80 injects additionalContext" "$OUT" '"additionalContext"'
assert_contains "inject: alert names the 5-hour metric"           "$OUT" "5-hour plan usage at 88%"
assert_absent  "inject: ctx@43 below 80 raises no ctx alert"      "$OUT" "context window"

# band-gating: same band on the same session → silent
OUT=$(printf '%s' "$SID" | HOME="$H" KT_CONFIG="$TMP/default.md" sh "$INJECT")
assert_empty "inject: re-fire at same band is silent" "$OUT"

# escalation: ctx now crosses too → a fresh (higher) band fires the ctx alert
snap 90 88 12
OUT=$(printf '%s' "$SID" | HOME="$H" KT_CONFIG="$TMP/default.md" sh "$INJECT")
assert_contains "inject: ctx@90 enters a new band, alerts" "$OUT" "context window at 90%"

# off → silent regardless of usage
cfg "$TMP/off.md" off
snap 99 99 99
OUT=$(printf '%s' '{"session_id":"'"${SP}"'-b"}' | HOME="$H" KT_CONFIG="$TMP/off.md" sh "$INJECT")
assert_empty "inject: threshold=off is silent even at 99%" "$OUT"

# no state file → silent (meter not installed / not yet rendered)
rm -f "$SNAP"
OUT=$(printf '%s' '{"session_id":"'"${SP}"'-c"}' | HOME="$H" KT_CONFIG="$TMP/default.md" sh "$INJECT")
assert_empty "inject: no state snapshot is silent" "$OUT"

# ---- v2.24.2: per-account state files + account-email segment ----
# Separate HOME so the synthetic ~/.claude.json doesn't disturb the default-key
# cases above (which rely on no ~/.claude.json being present).
H2="$TMP/home2"; mkdir -p "$H2/.claude"

# Account A (the "other" account) at 100%. Switching account == rewriting
# ~/.claude.json, exactly as /login does.
printf '{"oauthAccount":{"accountUuid":"AAAA-1111","emailAddress":"work@x.com"}}' > "$H2/.claude.json"
OUT=$(printf '{"model":{"display_name":"Opus 4.8"},"rate_limits":{"five_hour":{"used_percentage":100,"resets_at":1900000000},"seven_day":{"used_percentage":40}}}' | HOME="$H2" sh "$METER" | strip_ansi)
assert_contains "meter: renders account email as last segment"      "$OUT" "work@x.com"
A_SNAP="$H2/.claude/aria-statusline-state-AAAA-1111.json"
if [ -f "$A_SNAP" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: meter writes per-account snapshot for A\n'; fi
assert_contains "meter: account snapshot carries account_email"     "$(cat "$A_SNAP" 2>/dev/null)" '"account_email": "work@x.com"'
assert_contains "meter: account snapshot carries five_hour_pct 100" "$(cat "$A_SNAP" 2>/dev/null)" '"five_hour_pct": 100'

# Switch to account B (fine, 12%).
printf '{"oauthAccount":{"accountUuid":"BBBB-2222","emailAddress":"me@y.com"}}' > "$H2/.claude.json"
OUT=$(printf '{"model":{"display_name":"Opus 4.8"},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1900000000},"seven_day":{"used_percentage":5}}}' | HOME="$H2" sh "$METER" | strip_ansi)
assert_contains "meter: switched account shows B's email" "$OUT" "me@y.com"
if [ -f "$H2/.claude/aria-statusline-state-BBBB-2222.json" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: meter writes per-account snapshot for B\n'; fi

# THE BUG: logged in as B (12%, fine), the hook must NOT fire account A's 100%.
cfg "$TMP/acct.md" 80
OUT=$(printf '%s' '{"session_id":"'"${SP}"'-acctB"}' | HOME="$H2" KT_CONFIG="$TMP/acct.md" sh "$INJECT")
assert_empty   "inject: as B (fine) does NOT fire other account A's 100%" "$OUT"

# Sanity: logged in as A (100%), the hook DOES fire its own alert.
printf '{"oauthAccount":{"accountUuid":"AAAA-1111","emailAddress":"work@x.com"}}' > "$H2/.claude.json"
OUT=$(printf '%s' '{"session_id":"'"${SP}"'-acctA"}' | HOME="$H2" KT_CONFIG="$TMP/acct.md" sh "$INJECT")
assert_contains "inject: as A (100%) fires its own alert" "$OUT" "5-hour plan usage at 100%"

# Degrade: no ~/.claude.json → no email segment (default-keyed snapshot path).
OUT=$(printf '{"model":{"display_name":"Opus 4.8"},"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":1900000000}}}' | HOME="$H" sh "$METER" | strip_ansi)
assert_absent  "meter: no ~/.claude.json renders no email segment" "$OUT" "@"

printf '%d pass, %d fail\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
