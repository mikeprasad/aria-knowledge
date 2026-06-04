#!/bin/sh
# usage-threshold-inject.sh — UserPromptSubmit hook for aria-knowledge.
#
# Injects a short usage warning into the model's context when context-window,
# 5-hour, or 7-day usage crosses the configured alert threshold
# (usage_alert_threshold, default 80). The numbers come from the snapshot the
# status-line meter persists per account to ~/.gemini/antigravity/aria-statusline-state-<accountUuid>.json
# (the account is resolved from ~/.gemini/antigravity.json so we never read another account's usage).
#
# Default consumption is ON-DEMAND (the agent reads the snapshot when it matters,
# per the SessionStart TASK BUDGET guardrail). This hook is the additive
# threshold trigger: silent until a metric hits the line, then it speaks.
#
# Silent no-op (exit 0, no output) when ANY of:
#   - the meter isn't installed / hasn't rendered yet (no state file)
#   - jq is unavailable
#   - usage_alert_threshold is `off` or out of 1..100
#   - no metric has entered a HIGHER alert band than already warned this session
#
# Anti-spam: alerts are gated by 5-point bands tracked per session in
# /tmp/aria-usage-warn-<session_id>. A metric warns once on entering a band,
# again only on a higher band (80 -> 85 -> 90), and is rearmed when it drops
# back below threshold (e.g. after /compact or a 5-hour-window reset).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

command -v jq >/dev/null 2>&1 || exit 0

# Read the snapshot for the CURRENTLY logged-in account. The meter writes one
# file per account (keyed by accountUuid from ~/.gemini/antigravity.json) so an alternating /
# concurrent second account never makes us alert on the wrong account's usage.
ACCT_KEY="default"
if [ -f "$HOME/.gemini/antigravity.json" ]; then
  _u=$(jq -r '.oauthAccount.accountUuid // empty' "$HOME/.gemini/antigravity.json" 2>/dev/null)
  [ -n "$_u" ] && ACCT_KEY="$_u"
fi
STATE="$HOME/.gemini/antigravity/aria-statusline-state-${ACCT_KEY}.json"
[ -f "$STATE" ] || exit 0

# Threshold from config (KT_USAGE_ALERT_THRESHOLD; default 80). `off`/non-numeric
# /out-of-range all mean "injection disabled — on-demand only".
THRESH="$KT_USAGE_ALERT_THRESHOLD"
case "$THRESH" in
  ''|*[!0-9]*) exit 0 ;;
esac
[ "$THRESH" -lt 1 ] && exit 0
[ "$THRESH" -gt 100 ] && exit 0

INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SID" ] && SID="default"
WARNFILE="/tmp/aria-usage-warn-${SID}"

ctx=$(jq -r '.context_pct // empty' "$STATE" 2>/dev/null)
five=$(jq -r '.five_hour_pct // empty' "$STATE" 2>/dev/null)
five_reset=$(jq -r '.five_hour_resets_at // empty' "$STATE" 2>/dev/null)
seven=$(jq -r '.seven_day_pct // empty' "$STATE" 2>/dev/null)

# band PCT -> floor-to-5 if >= threshold, else 0 (no alert)
band() {
  case "$1" in ''|*[!0-9]*) echo 0; return ;; esac
  if [ "$1" -lt "$THRESH" ]; then echo 0; else echo $(( $1 / 5 * 5 )); fi
}

# prev_band METRIC -> last warned band recorded in WARNFILE (0 if none)
prev_band() {
  [ -f "$WARNFILE" ] || { echo 0; return; }
  _v=$(grep "^$1=" "$WARNFILE" 2>/dev/null | head -1 | sed "s/^$1=//")
  case "$_v" in ''|*[!0-9]*) echo 0 ;; *) echo "$_v" ;; esac
}

reset_clock() {
  case "$1" in ''|null|*[!0-9]*) return ;; esac
  date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M 2>/dev/null
}

cb=$(band "$ctx"); fb=$(band "$five"); sb=$(band "$seven")
ALERTS=""

if [ "$cb" -gt 0 ] && [ "$cb" -gt "$(prev_band context)" ]; then
  ALERTS="${ALERTS}context window at ${ctx}% — consider finishing the current atomic task and running /handoff (or compacting) before it fills. "
fi
if [ "$fb" -gt 0 ] && [ "$fb" -gt "$(prev_band five_hour)" ]; then
  _clk=$(reset_clock "$five_reset"); _rc=""; [ -n "$_clk" ] && _rc=" (5-hour window resets ${_clk})"
  ALERTS="${ALERTS}5-hour plan usage at ${five}%${_rc}. "
fi
if [ "$sb" -gt 0 ] && [ "$sb" -gt "$(prev_band seven_day)" ]; then
  ALERTS="${ALERTS}7-day plan usage at ${seven}%. "
fi

# Persist current bands (always — this both records new warnings and rearms a
# metric that dropped back below threshold, since its band is now 0).
printf 'context=%s\nfive_hour=%s\nseven_day=%s\n' "$cb" "$fb" "$sb" > "$WARNFILE" 2>/dev/null

[ -z "$ALERTS" ] && exit 0

MSG="ARIA usage alert (threshold ${THRESH}%): ${ALERTS}Full current snapshot: ${STATE}."
ESC=$(kt_json_escape "$MSG")
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}' "$ESC"
exit 0
