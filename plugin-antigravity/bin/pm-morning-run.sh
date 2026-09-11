#!/bin/sh
set -eu
# pm-morning-run.sh — launchd entrypoint. Orchestrates collect -> claude(reason) -> notify.
# Code-only (needs Bash + launchd). Config via config.sh + pm_cfg.
#
# ⛔ THIS SCRIPT MUST NOT REPORT SUCCESS IT DID NOT ACHIEVE. [PM-OUTCOME-PRE]
# Fixed 2026-09-11 after a measured 94-CONSECUTIVE-DAY silent failure (2026-06-09 -> 2026-09-10):
# `command -v claude` fails inside launchd (the plist runs `/bin/sh -lc`, which reads
# /etc/profile + ~/.profile and NOT ~/.zshrc where ~/.local/bin is added), so CLAUDE_BIN took a
# single hardcoded fallback that does not exist on a normal install. The call was wrapped in
# `|| true`, the status was written with a hardcoded result:"ok", and a trailing unconditional
# `echo "pm-morning-run OK"` closed the run. The log showed 94 resolution failures and 94 OK
# lines — a perfect 1:1, i.e. the success signal could not fail for the right reason.
# The root cause was CONFLATING "the sequence reached the end" with "a review was produced".
# Plan: aria/docs/superpowers/plans/2026-09-11-pm-morning-run-honest-outcome.md
BIN="$(cd "$(dirname "$0")" && pwd)"
. "$BIN/config.sh"
. "$BIN/pm-lib.sh"
KT_KNOWLEDGE_FOLDER="${KT_KNOWLEDGE_FOLDER:-}"   # config.sh leaves it unset when unconfigured; keep set -u safe
FACTS="$HOME/.gemini/antigravity/aria-pm-facts.json"
OUTDIR=$(apm_expand_tilde "$(pm_cfg pm_digest_dir "$KT_KNOWLEDGE_FOLDER/pm-reviews")")
mkdir -p "$OUTDIR"

# Outcome accumulators. These are the ONLY inputs to the status write, the notification, and the
# exit code. Nothing below may print or stamp a success signal that does not consult them.
RESULT=ok
REASON=""
DIGEST_NAME=""

# D1 — resolve `claude` by probe chain + EXECUTABILITY test.
# ⛔ Do NOT collapse this to a single hardcoded fallback, and do NOT "simplify" it by prepending
# to PATH: both re-create the 94-day defect for any install layout the guess misses. The legacy
# ~/.claude/local/claude stays LAST, for back-compat with installs that do have it.
# ⚑ Completeness here is NOT safety-critical: with the honest reporting below, a missed location
# produces a failure notification on day one instead of three months of silence.
# ⚑ PM_CLAUDE_CANDIDATES exists so the fallback branch is TESTABLE. Unset in production, where it
# defaults to the list below. Same override-with-production-default idiom as config.sh's
# KT_CONFIG="${KT_CONFIG:-...}", which every pm-* repro suite already uses for isolation.
# Without it a sandboxed test cannot exercise this branch: the absolute candidates escape a temp
# HOME, so the suite resolved the machine's REAL claude and invoked it for real.
PM_CLAUDE_CANDIDATES="${PM_CLAUDE_CANDIDATES:-$HOME/.local/bin/claude:/opt/homebrew/bin/claude:/usr/local/bin/claude:$HOME/.gemini/antigravity/local/claude}"
CLAUDE_BIN=""
if _cb=$(command -v claude 2>/dev/null) && [ -x "$_cb" ]; then
  CLAUDE_BIN="$_cb"
else
  _oifs=$IFS; IFS=:
  for _cb in $PM_CLAUDE_CANDIDATES; do
    if [ -x "$_cb" ]; then CLAUDE_BIN="$_cb"; break; fi
  done
  IFS=$_oifs
fi

# 1. deterministic scan (shell side, NOT the LLM)
# ⛔ Steps 1 / 1b / 1c are DELIBERATELY best-effort (`|| true`). The job must always reach the
# status write, because aria-atlas degrades to nothing without the overlay file. The fix for the
# 94-day defect was to write an HONEST status, never to let `set -e` kill the run halfway.
sh "$BIN/pm-collect.sh" "$FACTS" || true

# 1b. ensure pm-reviews/ is gitignored in the knowledge folder, if it is a repo (PM digests are personal).
if git -C "$KT_KNOWLEDGE_FOLDER" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  _gi="$KT_KNOWLEDGE_FOLDER/.gitignore"
  grep -qxF 'pm-reviews/' "$_gi" 2>/dev/null || printf 'pm-reviews/\n' >> "$_gi"
fi

# 1c. checkpoint-before-write: when light-writes are on, isolate ARIA's upcoming appends by committing
# any dirty, TRACKED IDEAS-BACKLOG.md in each ACTIVE project first (named-path). Also ensure each ACTIVE
# project gitignores PM-REVIEW.md (personal; mirrors SESSION.md). The headless agent has no Bash.
if [ "$(pm_cfg pm_light_writes true)" = "true" ]; then
  jq -r '.projects[]|select(.tier=="ACTIVE").path' "$FACTS" 2>/dev/null | while IFS= read -r p; do
    pp=$(apm_expand_tilde "$p")
    apm_checkpoint_backlog "$pp" || true
    if git -C "$pp" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      grep -qxF 'PM-REVIEW.md' "$pp/.gitignore" 2>/dev/null || printf 'PM-REVIEW.md\n' >> "$pp/.gitignore"
    fi
  done
fi

# 2. LLM reasoning — Read/Edit/Write only (no Bash) so it can't hang on a permission prompt.
# ⛔ Keep --allowedTools as-is; a headless run with Bash can block on a permission prompt forever.
if [ -z "$CLAUDE_BIN" ]; then
  RESULT=error
  REASON="claude-not-resolved"
else
  # D3 — verify the ARTIFACT by MTIME, never by a computed filename.
  # ⛔ Do NOT check for a digest named with today's date. skills/aria-assist/SKILL.md:56 specifies
  # `<pm_digest_dir>/<YYYY-MM-DD>.md` and NEVER states a timezone (only `generated_at` is pinned
  # UTC). This job fires 08:30 local = the PREVIOUS UTC day in +09:00, so a headless producer
  # writing its LOCAL date would be sought at the UTC date and never found — reporting failure on
  # every SUCCESSFUL run. A marker + `find -newer` is basis-free: it survives the timezone
  # divergence and any future change to the filename convention.
  # ⚑ POSIX `-newer FILE`, deliberately not GNU `-newermt` (absent on macOS/BSD find).
  MARKER="$OUTDIR/.pm-run-start.$$"
  : > "$MARKER"
  if ! ( cd "$HOME/Projects" && "$CLAUDE_BIN" -p "/aria-assist generate" \
           --allowedTools "Read" "Edit" "Write" ); then
    RESULT=error
    REASON="claude-failed"
  fi
  _digest=$(find "$OUTDIR" -maxdepth 1 -type f -name '*.md' -newer "$MARKER" 2>/dev/null | head -1)
  rm -f "$MARKER"
  if [ -n "$_digest" ]; then
    DIGEST_NAME=${_digest##*/}; DIGEST_NAME=${DIGEST_NAME%.md}
  else
    # The exit code is not the observable — step 2 can exit 0 and write nothing. This is the
    # check that catches the real failure INDEPENDENT of its cause, and it is the arm that
    # would have fired on all 94 runs.
    RESULT=error
    [ -n "$REASON" ] || REASON="no-digest"
  fi
fi

# 3. notify — the notification must tell the truth. It is the only channel the user actually sees:
# aria-atlas's AssistScheduleCard renders schedule.enabled/time and lastRun.digest, and NEVER
# lastRun.result. ⛔ Never send .last-summary on a failed run: that is how an identical
# three-month-old summary was delivered 94 times.
if [ "$RESULT" = "ok" ]; then
  BODY="Morning review ready"
  [ -f "$OUTDIR/.last-summary" ] && BODY="$(cat "$OUTDIR/.last-summary")"
  sh "$BIN/pm-notify.sh" "Morning review ready" "$BODY" || true
else
  sh "$BIN/pm-notify.sh" "Morning review FAILED" "$REASON" || true
fi

# 4. record last-run status into the .aria-assist.json overlay (best-effort; atlas reads this).
# D4 — `at` is UNCONDITIONAL, `digest` is CONDITIONAL. That asymmetry is the did-it-run channel:
#   fresh `at` + old `digest` => the job ran and produced nothing
#   stale `at`                => the job never fired
# Collapsing both to conditional makes those two diagnoses indistinguishable.
# ⚑ apm_write_assist_status MERGES into lastRun, so omitting `digest` PRESERVES the prior value.
# `summary` is likewise only written on success, so a failure cannot republish a stale line.
_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [ "$RESULT" = "ok" ]; then
  _status=$(jq -n --arg at "$_now" --arg r "$RESULT" --arg d "$DIGEST_NAME" \
    --arg s "$(cat "$OUTDIR/.last-summary" 2>/dev/null || echo '')" \
    '{at:$at, result:$r, digest:$d, summary:$s}')
else
  _status=$(jq -n --arg at "$_now" --arg r "$RESULT" --arg rs "$REASON" \
    '{at:$at, result:$r, reason:$rs}')
fi
apm_write_assist_status lastRun "$_status" || true

# 5. terminal status + exit.
# ⛔ NOTHING MAY FOLLOW THIS BLOCK. The original defect was a trailing unconditional
# `echo "pm-morning-run OK"`, which becomes the status anything downstream reads
# (trailing-echo-masks-exit-code-like-a-pipe). The OK line must never print on a failed run, and
# the exit must be the last statement executed.
if [ "$RESULT" = "ok" ]; then
  echo "pm-morning-run OK $_now digest=$DIGEST_NAME"
  exit 0
fi
echo "pm-morning-run FAILED $_now reason=$REASON" >&2
exit 1
