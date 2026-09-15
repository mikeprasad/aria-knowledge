#!/bin/sh
# statusline-meter.sh — aria-knowledge context + usage meter for the Claude Code status line.
#
# Reads the Claude Code status-line JSON payload on stdin and prints a single
# line: model name, a context-window progress bar, and (for Pro/Max plan
# sessions) the rolling 5-hour and 7-day usage percentages.
#
# Wired up by the /statusline skill, which copies this script to a stable path
# (~/.claude/aria-statusline-meter.sh) and points settings.json -> statusLine at
# the absolute copy. Re-run /statusline after a plugin update to refresh the copy.
#
# Design constraints (match the bin/ hook convention):
#   - POSIX sh, jq-preferred with a graceful no-jq degrade.
#   - NEVER emit an error or non-zero-on-the-screen: a broken status line is
#     worse than a sparse one. Every field is guarded; missing data is omitted.
#   - rate_limits.* is absent for API-key users and before the first API
#     response of a session — that segment simply doesn't render.
#
# Status-line JSON fields consumed (verified against code.claude.com/docs/statusline):
#   .model.display_name
#   .context_window.used_percentage          (input-only %, may be a float)
#   .rate_limits.five_hour.used_percentage   (Pro/Max only, after 1st response)
#   .rate_limits.five_hour.resets_at         (unix epoch seconds)
#   .rate_limits.seven_day.used_percentage   (Pro/Max only)
#   .rate_limits.seven_day.resets_at         (unix epoch seconds)
#   .effort.level                            (low|medium|high|xhigh|max; absent
#                                             when the model has no effort param)

input=$(cat)
[ -z "$input" ] && { printf 'Claude'; exit 0; }

# --- ANSI helpers (status line supports ANSI; degrade to plain if unsupported) ---
ESC=$(printf '\033')
DIM="${ESC}[2m"; RESET="${ESC}[0m"
GREEN="${ESC}[32m"; YELLOW="${ESC}[33m"; RED="${ESC}[31m"; CYAN="${ESC}[36m"

# color_for PCT -> echoes an ANSI color by threshold (<60 green, <85 yellow, else red)
color_for() {
  _p=$1
  if [ "$_p" -lt 60 ]; then printf '%s' "$GREEN"
  elif [ "$_p" -lt 85 ]; then printf '%s' "$YELLOW"
  else printf '%s' "$RED"; fi
}

# round_int FLOAT -> integer string clamped 0..100, or empty if non-numeric
round_int() {
  case "$1" in
    ''|null) return ;;
    *[!0-9.]*) return ;;
  esac
  awk -v v="$1" 'BEGIN { printf "%d", (v < 0 ? 0 : (v > 100 ? 100 : v)) + 0.5 }' 2>/dev/null
}

# bar PCT WIDTH -> a filled/empty block bar
bar() {
  _pct=$1; _w=${2:-10}
  _fill=$(( _pct * _w / 100 ))
  [ "$_fill" -lt 0 ] && _fill=0
  [ "$_fill" -gt "$_w" ] && _fill="$_w"
  _empty=$(( _w - _fill ))
  _out=""
  _i=0; while [ "$_i" -lt "$_fill" ]; do _out="${_out}█"; _i=$(( _i + 1 )); done
  _i=0; while [ "$_i" -lt "$_empty" ]; do _out="${_out}░"; _i=$(( _i + 1 )); done
  printf '%b' "$_out"
}

# reset_clock EPOCH -> "7am" / "7:10am" local 12-hour time, or empty.
# Formats with portable %I:%M%p then normalizes (no BSD/GNU no-pad or lowercase
# meridiem specifier exists): drop the leading zero, drop ":00" on the hour,
# lowercase AM/PM.
reset_clock() {
  case "$1" in ''|null|*[!0-9]*) return ;; esac
  _c=$(date -r "$1" '+%I:%M%p' 2>/dev/null || date -d "@$1" '+%I:%M%p' 2>/dev/null)
  [ -z "$_c" ] && return
  printf '%s' "$_c" | sed -E 's/^0//; s/:00//; s/AM/am/; s/PM/pm/'
}

# reset_when EPOCH -> "Fri 7am" / "Fri 1:30pm" local (weekday + reset_clock time).
reset_when() {
  _t=$(reset_clock "$1")
  [ -z "$_t" ] && return
  _wd=$(date -r "$1" +%a 2>/dev/null || date -d "@$1" +%a 2>/dev/null)
  [ -z "$_wd" ] && { printf '%s' "$_t"; return; }
  printf '%s %s' "$_wd" "$_t"
}

# >>> kt_resolve_account — KEEP BYTE-IDENTICAL with the statusline-meter.sh inline mirror
# Resolves the session's account key for usage-snapshot scoping. POSIX sh, no awk
# intervals (macOS awk lacks them). Echoes TAB-separated "<key>\t<runtime>\t<email>";
# runtime in {cli, desktop, desktop-unknown}. $1 = session id (falls back to env).
kt_resolve_account() {
  _kra_sid="${1:-${CLAUDE_CODE_SESSION_ID:-}}"
  _kra_cl="$HOME/Library/Application Support/Claude"
  _kra_acct=""; _kra_org=""

  # Tier 1: env-only PATH parse of local-agent-mode-sessions/<acct>/<org>
  _kra_oifs=$IFS; IFS=:
  for _kra_p in $PATH; do
    case "$_kra_p" in
      */local-agent-mode-sessions/*)
        _kra_seg=${_kra_p#*local-agent-mode-sessions/}
        _kra_a=${_kra_seg%%/*}
        _kra_r=${_kra_seg#*/}; _kra_b=${_kra_r%%/*}
        case "$_kra_a" in skills-plugin|'') continue ;; esac
        _kra_acct=$_kra_a; _kra_org=$_kra_b; break ;;
    esac
  done
  IFS=$_kra_oifs
  if [ -n "$_kra_acct" ] && [ -d "$_kra_cl/claude-code-sessions/$_kra_acct/$_kra_org" ]; then
    printf '%s\tdesktop\t' "$_kra_acct"; return 0
  fi

  # Desktop-hosting signal (positive, false-positive-safe)
  _kra_desktop=0
  case "${CLAUDE_CODE_ENTRYPOINT:-}" in claude-desktop) _kra_desktop=1 ;; esac
  case "${CLAUDE_CODE_EXECPATH:-}" in *claude-code-vm*|*/Claude/claude-code/*) _kra_desktop=1 ;; esac
  case "${__CFBundleIdentifier:-}" in *claudefordesktop*) _kra_desktop=1 ;; esac

  # Tier 2: authoritative FS lookup by session id — gated on Desktop signal
  if [ "$_kra_desktop" = 1 ] && [ -n "$_kra_sid" ] && [ -d "$_kra_cl/claude-code-sessions" ]; then
    _kra_hit=$(grep -rl "$_kra_sid" "$_kra_cl/claude-code-sessions" 2>/dev/null | head -1)
    if [ -n "$_kra_hit" ]; then
      _kra_acct=$(basename "$(dirname "$(dirname "$_kra_hit")")")
      printf '%s\tdesktop\t' "$_kra_acct"; return 0
    fi
  fi

  # Tier 3: Desktop but unresolved -> degrade (never assert an account)
  if [ "$_kra_desktop" = 1 ]; then
    printf 'desktop-unknown\tdesktop-unknown\t'; return 0
  fi

  # Tier 4: CLI / VS Code / API-key -> ~/.claude.json (v2.24.2 behavior, unchanged)
  _kra_uuid=""; _kra_email=""
  if command -v jq >/dev/null 2>&1 && [ -f "$HOME/.claude.json" ]; then
    _kra_uuid=$(jq -r '.oauthAccount.accountUuid // empty' "$HOME/.claude.json" 2>/dev/null)
    _kra_email=$(jq -r '.oauthAccount.emailAddress // empty' "$HOME/.claude.json" 2>/dev/null)
  fi
  printf '%s\tcli\t%s' "${_kra_uuid:-default}" "$_kra_email"
}
# <<< kt_resolve_account

model=""; ctx=""; five=""; five_reset=""; week=""; week_reset=""; acct_email=""; acct_uuid=""; runtime=""; sid=""; eff=""

if command -v jq >/dev/null 2>&1; then
  model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
  eff=$(printf '%s' "$input" | jq -r '.effort.level // empty' 2>/dev/null)
  ctx=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
  five=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
  five_reset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
  week=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
  week_reset=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)
  # Account identity via the shared runtime-aware resolver (inlined mirror above) —
  # correct under both the CLI and Claude-Desktop-hosted runtimes. The resolver
  # returns a non-empty email ONLY on the CLI tier, so the email segment renders
  # only when ~/.claude.json is the real session account.
  sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
  _resolved=$(kt_resolve_account "$sid")
  acct_uuid=$(printf '%s' "$_resolved" | cut -f1)
  runtime=$(printf '%s' "$_resolved" | cut -f2)
  acct_email=$(printf '%s' "$_resolved" | cut -f3)
else
  # No-jq degrade: model name only (reliable to extract); the meter needs jq.
  model=$(printf '%s' "$input" \
    | sed -n 's/.*"display_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

[ -z "$model" ] && model="Claude"

# Trim Claude Code's verbose "(1M context)" suffix down to "(1M)".
case "$model" in
  *" context)") model="${model% context)})" ;;
esac

# Compact reasoning-effort suffix after the model name: L·M·H·XH·MX
# (e.g. "Opus 4.8 (1M) H" at /effort high). .effort.level is absent when the
# current model doesn't support the effort parameter — then no suffix renders.
eff_letter=""
case "$eff" in
  low)    eff_letter="L" ;;
  medium) eff_letter="M" ;;
  high)   eff_letter="H" ;;
  xhigh)  eff_letter="XH" ;;
  max)    eff_letter="MX" ;;
esac
# Display-only: keep $model bare (the state snapshot below records the raw name).
model_disp="$model"
[ -n "$eff_letter" ] && model_disp="${model} ${eff_letter}"

# --- assemble segments ---
out="${CYAN}${model_disp}${RESET}"

ctx_i=$(round_int "$ctx")
if [ -n "$ctx_i" ]; then
  c=$(color_for "$ctx_i")
  out="${out} ${DIM}│${RESET} ${c}$(bar "$ctx_i" 10) ${ctx_i}%${RESET} ${DIM}ctx${RESET}"
fi

five_i=$(round_int "$five")
if [ -n "$five_i" ]; then
  c=$(color_for "$five_i")
  seg="${c}5h ${five_i}%${RESET}"
  clk=$(reset_clock "$five_reset")
  [ -n "$clk" ] && seg="${seg} ${DIM}↺${clk}${RESET}"
  out="${out} ${DIM}│${RESET} ${seg}"
fi

week_i=$(round_int "$week")
if [ -n "$week_i" ]; then
  c=$(color_for "$week_i")
  seg="${c}7d ${week_i}%${RESET}"
  dy=$(reset_when "$week_reset")
  [ -n "$dy" ] && seg="${seg} ${DIM}↺${dy}${RESET}"
  out="${out} ${DIM}│${RESET} ${seg}"
fi

# Account email — LAST segment so a width-truncated status line only ever clips
# the email, never the usage data. Omitted for API-key users (no oauthAccount).
if [ -n "$acct_email" ]; then
  out="${out} ${DIM}│ ${acct_email}${RESET}"
fi

# --- persist a snapshot so the session's agent (and the usage-alert hook) can
# read current usage on demand. Atomic (temp + mv), fully error-suppressed, and
# jq-gated so it never delays or breaks rendering. Only written when jq parsed
# real usage values; the no-jq degrade path leaves no stale file behind.
if command -v jq >/dev/null 2>&1; then
  # Per-account file: keyed by accountUuid so concurrent/alternating accounts
  # never clobber each other's usage (the usage-alert hook reads the file for the
  # session's own account). Falls back to "default" for API-key users.
  _key="${acct_uuid:-default}"
  _state="$HOME/.claude/aria-statusline-state-${_key}.json"
  _tmp="$HOME/.claude/.aria-statusline-state.$$.tmp"
  _at=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  # Preserve the ACCOUNT-scoped usage windows when THIS payload carries none.
  # rate_limits is absent until a session's first API response, so a whole-file rewrite
  # here erased the account's 5h/7d for every concurrent session on it — and the usage
  # alert then could not fire on the first prompt of a fresh session. ADR 098 rejected
  # "single file + account-tag guard" because "two active sessions interleaving renders
  # flap the file, so a session can miss its OWN real alert"; per-account keying closed
  # the cross-account case and left the same-account case live. This closes it.
  #
  # SCOPE PARTITION (asserted by AC14 against a hand-written literal — a guard that
  # iterated this list could not see a field being dropped FROM it):
  #   render-scoped, always THIS render: written_at model runtime session_id
  #                                      account_email account_uuid context_pct
  #   account-scoped, preserved:         five_hour_pct five_hour_resets_at
  #                                      seven_day_pct seven_day_resets_at
  #
  # ⛔ SNAPSHOT-ONLY variables. Never preserve into five_i/week_i/five_reset/week_reset —
  # those already rendered the 5h/7d segments above, and a preserved value there would
  # DISPLAY a stale window on a fresh session ("a wrong status line is worse than a
  # sparse one"). Guarded by AC4b.
  # ⛔ Per WINDOW, as a pair — never field-by-field. A payload can carry a percentage with
  # no resets_at (a real, tested shape), and field-wise defaulting would pair a fresh
  # percentage with a stale reset, making the consumer's _expired() judge the wrong window.
  # Fails soft by construction: absent / empty / truncated / non-JSON prior file -> jq exits
  # non-zero printing nothing -> all four read empty -> today's write-whole behaviour, and the
  # render never aborts. Measured 2026-09-16 over 7 inputs; a well-formed file with no usage
  # keys yields three bare tabs (all empty), and an explicit null preserves only the other pair.
  # `cut` deliberately has no -s: the filter emits exactly three tabs or nothing at all, so the
  # tab-free branch where cut would return the whole line is UNREACHABLE. Do not "harden" it.
  # NOT atomic across concurrent sessions, and that is accepted: if a peer writes a fresher
  # value between this read and this write, usage goes stale by at most one render
  # (refreshInterval 30s) — strictly better than the pre-fix behaviour, which ERASED it.
  # Do not add locking.
  _prev=$(jq -r '[(.five_hour_pct//""),(.five_hour_resets_at//""),(.seven_day_pct//""),(.seven_day_resets_at//"")]|@tsv' "$_state" 2>/dev/null)
  _snap_five="$five_i"; _snap_five_reset="$five_reset"
  _snap_week="$week_i"; _snap_week_reset="$week_reset"
  if [ -z "$_snap_five" ]; then
    _snap_five=$(printf '%s' "$_prev" | cut -f1)
    _snap_five_reset=$(printf '%s' "$_prev" | cut -f2)
  fi
  if [ -z "$_snap_week" ]; then
    _snap_week=$(printf '%s' "$_prev" | cut -f3)
    _snap_week_reset=$(printf '%s' "$_prev" | cut -f4)
  fi
  if jq -n --arg model "$model" --arg ctx "$ctx_i" --arg five "$_snap_five" \
        --arg five_reset "$_snap_five_reset" --arg seven "$_snap_week" --arg at "$_at" \
        --arg acct_email "$acct_email" --arg acct_uuid "$acct_uuid" \
        --arg seven_reset "$_snap_week_reset" --arg runtime "$runtime" --arg sid "$sid" \
        '{written_at:$at, model:$model}
          + (if $runtime != "" then {runtime:$runtime} else {} end)
          + (if $sid != "" then {session_id:$sid} else {} end)
          + (if $acct_email != "" then {account_email:$acct_email} else {} end)
          + (if $acct_uuid  != "" then {account_uuid:$acct_uuid} else {} end)
          + (if $ctx != "" then {context_pct:($ctx|tonumber)} else {} end)
          + (if $five != "" then {five_hour_pct:($five|tonumber)} else {} end)
          + (if $five_reset != "" then {five_hour_resets_at:($five_reset|tonumber)} else {} end)
          + (if $seven != "" then {seven_day_pct:($seven|tonumber)} else {} end)
          + (if $seven_reset != "" then {seven_day_resets_at:($seven_reset|tonumber)} else {} end)' \
        > "$_tmp" 2>/dev/null; then
    mv -f "$_tmp" "$_state" 2>/dev/null
  fi
  rm -f "$_tmp" 2>/dev/null
fi

printf '%b' "$out"
