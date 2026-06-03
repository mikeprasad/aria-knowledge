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

# reset_clock EPOCH -> "HH:MM" local time, or empty if unparseable
reset_clock() {
  case "$1" in ''|null|*[!0-9]*) return ;; esac
  date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M 2>/dev/null
}

model=""; ctx=""; five=""; five_reset=""; week=""

if command -v jq >/dev/null 2>&1; then
  model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
  ctx=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
  five=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
  five_reset=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
  week=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
else
  # No-jq degrade: model name only (reliable to extract); the meter needs jq.
  model=$(printf '%s' "$input" \
    | sed -n 's/.*"display_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
fi

[ -z "$model" ] && model="Claude"

# --- assemble segments ---
out="${CYAN}${model}${RESET}"

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
  out="${out} ${DIM}│${RESET} ${c}7d ${week_i}%${RESET}"
fi

printf '%b' "$out"
