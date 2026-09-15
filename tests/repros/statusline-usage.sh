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

# Pin the runtime to CLI/default: drop Claude-Desktop hosting signals so the shared
# account resolver (config.sh kt_resolve_account, used by the meter + inject hook)
# deterministically takes the CLI tier and keys the snapshot "default" — regardless
# of whether this repro runs inside a Desktop-hosted session (where those env vars
# are present). PATH is left intact so jq stays reachable; the isolated HOME makes
# any inherited local-agent-mode-sessions PATH entry fail Tier-1 validation.
unset CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH __CFBundleIdentifier 2>/dev/null || true

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

# ---- 2026-09-16: ACCOUNT-scoped usage survives a render carrying no rate_limits ----
# Claude Code omits rate_limits until a session's first API response, so a whole-file
# snapshot rewrite erases the ACCOUNT's 5h/7d for every concurrent session on it — and the
# usage alert then cannot fire on the first prompt of a fresh session, which is the moment
# it matters most. Design + rejected alternatives:
#   docs/superpowers/specs/2026-09-16-statusline-snapshot-preservation-design.md
# ⛔ PLACEMENT IS LOAD-BEARING: these MUST stay above the inject section's snap(), which
# rewrites $SNAP wholesale. An assertion below it proves nothing — the suite already
# executed this defect at the NORST case above and still reported 35 pass / 0 fail.
# Isolated HOME so the shared-$SNAP cases above cannot mask the result, and so the
# "no prior snapshot" case is genuine.
H3="$TMP/home3"; mkdir -p "$H3/.claude"
P_SNAP="$H3/.claude/aria-statusline-state-default.json"
P_FULL='{"session_id":"P-old","model":{"display_name":"Opus 5"},"context_window":{"used_percentage":40},"rate_limits":{"five_hour":{"used_percentage":88,"resets_at":1900000000},"seven_day":{"used_percentage":12,"resets_at":1900000002}}}'
P_NORL='{"session_id":"P-new","model":{"display_name":"Opus 5"},"context_window":{"used_percentage":7}}'

# AC6 — first-ever render, no prior snapshot
printf '%s' "$P_FULL" | HOME="$H3" sh "$METER" >/dev/null
if [ -f "$P_SNAP" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: AC6 first render writes a snapshot\n'; fi
assert_contains "AC6: first render carries five_hour_pct 88" "$(cat "$P_SNAP" 2>/dev/null)" '"five_hour_pct": 88'

# AC1/AC2 — the account-scoped windows survive; AC4/AC5 — render-scoped fields are THIS render's;
# AC4b — and the stale value must NOT reach the status line (M3's control).
OUT=$(printf '%s' "$P_NORL" | HOME="$H3" sh "$METER" | strip_ansi)
assert_contains "AC1: five_hour_pct survives a no-rate_limits render"  "$(cat "$P_SNAP" 2>/dev/null)" '"five_hour_pct": 88'
assert_contains "AC1: five_hour_resets_at survives as a PAIR"          "$(cat "$P_SNAP" 2>/dev/null)" '"five_hour_resets_at": 1900000000'
assert_contains "AC2: seven_day_pct survives"                          "$(cat "$P_SNAP" 2>/dev/null)" '"seven_day_pct": 12'
assert_contains "AC2: seven_day_resets_at survives as a PAIR"          "$(cat "$P_SNAP" 2>/dev/null)" '"seven_day_resets_at": 1900000002'
assert_contains "AC4: session_id is the CURRENT render's"              "$(cat "$P_SNAP" 2>/dev/null)" '"session_id": "P-new"'
assert_contains "AC5: context_pct is the CURRENT render's"             "$(cat "$P_SNAP" 2>/dev/null)" '"context_pct": 7'
assert_absent  "AC4b: no-rate_limits render shows no 5h segment"       "$OUT" "5h"
assert_absent  "AC4b: no-rate_limits render shows no 7d segment"       "$OUT" "7d"

# AC2b — the window is preserved as a PAIR, never field-by-field. A payload may carry a
# percentage with NO resets_at (a real shape — see the NORST case above). Field-wise defaulting
# would pair this fresh percentage with the PREVIOUS reset, and the consumer's _expired() would
# then judge a window whose reset belongs to a different reading. Control for mutation M2.
P_NORST='{"session_id":"P-norst","model":{"display_name":"Opus 5"},"rate_limits":{"five_hour":{"used_percentage":55}}}'
printf '%s' "$P_NORST" | HOME="$H3" sh "$METER" >/dev/null
assert_contains "AC2b: percentage is this render's"            "$(cat "$P_SNAP" 2>/dev/null)" '"five_hour_pct": 55'
v=$(jq -r '.five_hour_resets_at // "ABSENT"' "$P_SNAP" 2>/dev/null)
if [ "$v" = "ABSENT" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: AC2b five_hour_resets_at must NOT be preserved beside a fresh pct; got %s\n' "$v"; fi

# AC3 — a render WITH rate_limits still OVERWRITES: preservation must not become preserve-always
P_NEW='{"session_id":"P-new2","model":{"display_name":"Opus 5"},"rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1900000009}}}'
printf '%s' "$P_NEW" | HOME="$H3" sh "$METER" >/dev/null
assert_contains "AC3: a render WITH rate_limits overwrites five_hour_pct" "$(cat "$P_SNAP" 2>/dev/null)" '"five_hour_pct": 12'

# AC5b — post-/compact: no context measurement -> context_pct stays ABSENT (existing contract,
# tests/repros/statusline-meter.sh:32). A blanket non-empty merge would break this, which is why
# the fix partitions by scope instead (spec D1b, rejecting ADR 036's mergeNonEmpty wholesale).
v=$(jq -r '.context_pct // "ABSENT"' "$P_SNAP" 2>/dev/null)
if [ "$v" = "ABSENT" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: AC5b context_pct should be ABSENT post-/compact; got %s\n' "$v"; fi

# AC13 — the prior-snapshot read is a read of a file OTHER SESSIONS WRITE, so it must tolerate
# every state a concurrent writer can leave behind and degrade to write-whole. The meter's prime
# directive is that a broken status line is worse than a sparse one: it must never abort.
# NOTE the exit-code capture: the meter is the LAST stage of the pipeline, so $? is ITS status.
# Piping it through strip_ansi first would make $? sed's, and the check would assert nothing.
for _case in absent empty truncated nonjson; do
  H4="$TMP/home4-$_case"; mkdir -p "$H4/.claude"
  S4="$H4/.claude/aria-statusline-state-default.json"
  case "$_case" in
    absent)    rm -f "$S4" ;;
    empty)     : > "$S4" ;;
    truncated) printf '%s' '{"five_hour_pct":' > "$S4" ;;
    nonjson)   printf '%s' 'not json at all'   > "$S4" ;;
  esac
  # ⛔ The `if` is load-bearing, not style. This file runs `set -e`, and the meter is the LAST
  # stage of this pipeline — so a meter that genuinely exits non-zero would KILL THE SUITE here
  # before the assertion below could report it, leaving AC13 green and structurally unable to
  # fail for its own stated reason. Found by mutation M5 on 2026-09-16, which produced 14
  # unrelated failures and none of AC13's. An `if` condition is exempt from `set -e`.
  if printf '%s' "$P_NORL" | HOME="$H4" sh "$METER" > "$TMP/ac13.out" 2>/dev/null; then E4=0; else E4=$?; fi
  O4=$(strip_ansi < "$TMP/ac13.out")
  if [ "$E4" -eq 0 ] && [ -n "$O4" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: AC13 (%s) meter must render and exit 0; exit=%s out=[%s]\n' "$_case" "$E4" "$O4"; fi
  assert_contains "AC13 ($_case): degrades to write-whole" "$(cat "$S4" 2>/dev/null)" '"model": "Opus 5"'
done

# AC14 — every key the meter can emit belongs to exactly ONE scope partition. The expected set is
# a HAND-WRITTEN literal transcribed from the jq filter in statusline-meter.sh, deliberately NOT
# derived from the script: a guard whose parameter source IS its mutation target cannot see a
# field being dropped from that source — the mutation shortens the test instead of failing it
# (guard-scoped-to-the-wrong-unit, 2026-08-28 cue). Dropping a field from the meter's partition
# must redden THIS assertion.
AC14_RENDER='account_email account_uuid context_pct model runtime session_id written_at'
AC14_ACCOUNT='five_hour_pct five_hour_resets_at seven_day_pct seven_day_resets_at'
AC14_EXPECT=$(printf '%s %s' "$AC14_RENDER" "$AC14_ACCOUNT" | tr ' ' '\n' | sort | tr '\n' ' ')
H5="$TMP/home5"; mkdir -p "$H5/.claude"
printf '%s' '{"oauthAccount":{"accountUuid":"AC14-UUID","emailAddress":"ac14@x.test"}}' > "$H5/.claude.json"
printf '%s' "$P_FULL" | HOME="$H5" sh "$METER" >/dev/null
AC14_ACTUAL=$(jq -r 'keys|.[]' "$H5/.claude/aria-statusline-state-AC14-UUID.json" 2>/dev/null | sort | tr '\n' ' ')
if [ "$AC14_ACTUAL" = "$AC14_EXPECT" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: AC14 emitted keys != hand-written partition\n  expect: %s\n  actual: %s\n' "$AC14_EXPECT" "$AC14_ACTUAL"; fi

# ---------- usage-threshold-inject.sh ----------
cfg() { cat > "$1" <<EOF
---
knowledge_folder: $TMP/kn
usage_alert_threshold: $2
---
EOF
mkdir -p "$TMP/kn"; }

# state: ctx / 5h / 7d driven per case. session_id matches the ${SP}-a queries below
# so the inject hook's per-session context guard trusts the snapshot's context_pct
# (the meter stamps session_id as of v2.24.3).
snap() { cat > "$SNAP" <<EOF
{"written_at":"2026-06-03T17:00:00Z","model":"Opus 4.8","session_id":"${SP}-a","context_pct":$1,"five_hour_pct":$2,"five_hour_resets_at":1900000000,"seven_day_pct":$3}
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

# ---- AC8 (2026-09-16) — THE OUTCOME CRITERION, and the only one that fails for the
# user-visible reason: on the FIRST PROMPT of a fresh session whose ACCOUNT is over threshold,
# the hook must alert. Pre-fix this was silent — the fresh session's first render carries no
# rate_limits, which erased the account's 5h before the hook ever read it. Every other AC here
# is a mechanism check; this one is the behaviour Mike would notice.
H6="$TMP/home6"; mkdir -p "$H6/.claude"
cfg "$TMP/ac8.md" 80
# an established session on this account leaves it at 91%
printf '%s' '{"session_id":"AC8-established","model":{"display_name":"Opus 5"},"rate_limits":{"five_hour":{"used_percentage":91,"resets_at":1900000000}}}' \
  | HOME="$H6" sh "$METER" >/dev/null
# a FRESH session renders first, BEFORE its first API response -> payload carries no rate_limits
printf '%s' '{"session_id":"'"${SP}"'-ac8","model":{"display_name":"Opus 5"},"context_window":{"used_percentage":5}}' \
  | HOME="$H6" sh "$METER" >/dev/null
# ...and that fresh session's first prompt must still see the account's real 5h.
# KT_CONFIG is mandatory: with no config file the threshold resolves EMPTY and the hook exits
# silently, which would make this case pass-by-silence in the wrong direction.
OUT=$(printf '%s' '{"session_id":"'"${SP}"'-ac8"}' | HOME="$H6" KT_CONFIG="$TMP/ac8.md" sh "$INJECT")
assert_contains "AC8: a fresh session's first prompt alerts on the account's 5h" "$OUT" "5-hour plan usage at 91%"

printf '%d pass, %d fail\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
