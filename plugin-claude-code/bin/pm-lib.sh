# shellcheck shell=sh
# pm-lib.sh — pure helpers for the aria-assist morning PM assistant. No side effects.
# Sourced by pm-collect.sh / pm-notify.sh / pm-mode.sh / pm-morning-run.sh and the repro tests.

apm_now_epoch() { printf '%s' "${ARIA_PM_NOW_EPOCH:-$(date +%s)}"; }

# apm_days_since EPOCH -> whole days between EPOCH and now (floor, min 0)
apm_days_since() {
  _n=$(apm_now_epoch); _d=$(( (_n - $1) / 86400 ))
  [ "$_d" -lt 0 ] && _d=0; printf '%s' "$_d"
}

# apm_date_to_epoch YYYY-MM-DD -> UTC midnight epoch (BSD date; GNU fallback)
apm_date_to_epoch() {
  date -j -u -f "%Y-%m-%d %H:%M:%S" "$1 00:00:00" +%s 2>/dev/null \
    || date -u -d "$1 00:00:00" +%s 2>/dev/null
}

# apm_expand_tilde PATH -> leading ~ replaced with $HOME
apm_expand_tilde() { case "$1" in "~"/*) printf '%s' "$HOME${1#\~}" ;; *) printf '%s' "$1" ;; esac; }

# pm_cfg KEY DEFAULT -> value of `KEY:` in the $KT_CONFIG YAML frontmatter, or DEFAULT.
# Mirrors config.sh's frontmatter idiom exactly (sed range between --- markers, grep, strip).
# Requires KT_CONFIG to be set (config.sh sets it). Replaces the old jq-based apm_cfg.
pm_cfg() {
  [ -n "${KT_CONFIG:-}" ] && [ -f "$KT_CONFIG" ] || { printf '%s' "$2"; return; }
  _v=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" 2>/dev/null | grep "^$1:" | head -1 | sed "s/^$1: *//")
  [ -n "$_v" ] && printf '%s' "$_v" || printf '%s' "$2"
}

# apm_tier RECENCY_DAYS SESSION_STATE OVERRIDE ACTIVE_MAX WARM_MAX -> ACTIVE|WARM|DORMANT
apm_tier() {
  _rec="$1"; _st="$2"; _ov="$3"; _amax="$4"; _wmax="$5"
  case "$_ov" in ACTIVE|WARM|DORMANT) printf '%s' "$_ov"; return ;; esac
  case "$_st" in in-progress|handoff) printf 'ACTIVE'; return ;; esac
  case "$_rec" in ''|*[!0-9]*) printf 'DORMANT'; return ;; esac
  if [ "$_rec" -le "$_amax" ]; then printf 'ACTIVE'
  elif [ "$_rec" -le "$_wmax" ]; then printf 'WARM'
  else printf 'DORMANT'; fi
}

# apm_git_last_epoch DIR -> epoch of last commit, or empty
apm_git_last_epoch() { git -C "$1" log -1 --format=%ct 2>/dev/null; }

# apm_session_state DIR -> in-progress|handoff|wrapup|"" (SESSION.md `lastEvent:`; legacy state/status fallback)
apm_session_state() {
  [ -f "$1/SESSION.md" ] || return 0
  _v=$(grep -m1 -iE '^[[:space:]]*lastEvent:' "$1/SESSION.md" 2>/dev/null \
        | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*$//' | tr 'A-Z' 'a-z')
  [ -n "$_v" ] || _v=$(grep -m1 -iE '^[[:space:]]*(state|status):' "$1/SESSION.md" 2>/dev/null \
        | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*$//' | tr 'A-Z' 'a-z')
  printf '%s' "$_v"
}

# apm_session_next DIR -> SESSION.md `nextAction:` value, or ""
apm_session_next() {
  [ -f "$1/SESSION.md" ] || return 0
  grep -m1 -iE '^[[:space:]]*nextAction:' "$1/SESSION.md" 2>/dev/null \
    | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]*$//'
}

# apm_progress_last_epoch DIR -> epoch of newest YYYY-MM-DD in PROGRESS.md, or empty
apm_progress_last_epoch() {
  [ -f "$1/PROGRESS.md" ] || return 0
  _d=$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$1/PROGRESS.md" 2>/dev/null | sort -r | head -1)
  [ -n "$_d" ] && apm_date_to_epoch "$_d"
}

# apm_recency_days DIR -> smallest day-delta across git / progress signals, or empty
apm_recency_days() {
  _best=""
  for _e in "$(apm_git_last_epoch "$1")" "$(apm_progress_last_epoch "$1")"; do
    [ -n "$_e" ] || continue
    _d=$(apm_days_since "$_e")
    { [ -z "$_best" ] || [ "$_d" -lt "$_best" ]; } && _best="$_d"
  done
  printf '%s' "$_best"
}

# apm_decide_mode OUTDIR -> "review" if a <24h review exists that's unreviewed since last stamp, else "generate"
apm_decide_mode() {
  _dir="$1"
  _newest=$(ls -t "$_dir"/[0-9]*.md 2>/dev/null | head -1)
  [ -n "$_newest" ] || { printf 'generate'; return; }
  _mtime=$(stat -f %m "$_newest" 2>/dev/null || stat -c %Y "$_newest" 2>/dev/null)
  case "$_mtime" in ''|*[!0-9]*) printf 'generate'; return ;; esac
  [ $(( $(apm_now_epoch) - _mtime )) -lt 86400 ] || { printf 'generate'; return; }
  _lastrev=0
  [ -f "$_dir/.last-reviewed" ] && _lastrev=$(cat "$_dir/.last-reviewed" 2>/dev/null)
  case "$_lastrev" in ''|*[!0-9]*) _lastrev=0 ;; esac
  if [ "$_mtime" -gt "$_lastrev" ]; then printf 'review'; else printf 'generate'; fi
}

# apm_mark_reviewed OUTDIR -> stamp the current time as "last reviewed"
apm_mark_reviewed() { printf '%s' "$(apm_now_epoch)" > "$1/.last-reviewed"; }

# apm_checkpoint_backlog DIR -> commit a TRACKED + dirty IDEAS-BACKLOG.md (named-path, never -A)
# so a subsequent light-write append lands isolated and reversible. No-op for non-repos,
# missing/untracked/clean backlogs. Echoes "checkpointed DIR" only when it commits. Always returns 0.
apm_checkpoint_backlog() {
  _d="$1"
  git -C "$_d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  git -C "$_d" ls-files --error-unmatch IDEAS-BACKLOG.md >/dev/null 2>&1 || return 0
  if git -C "$_d" diff --quiet HEAD -- IDEAS-BACKLOG.md 2>/dev/null; then return 0; fi
  git -C "$_d" add IDEAS-BACKLOG.md 2>/dev/null \
    && git -C "$_d" commit -q -m "chore(aria-pm): checkpoint IDEAS-BACKLOG before morning auto-append" 2>/dev/null \
    && echo "checkpointed $_d"
  return 0
}
