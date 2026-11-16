#!/bin/sh
# state-dir-sweeps.sh — 2.58.0 spec D6 + gate amendment G1-3: the private state dir is swept, and for
# 2.58.0 only the old shared /tmp and $TMPDIR names are swept too (LEGACY-TMP-SWEEP-2.58).
#
# Every sweeping script — claude-code (C), codex (X) and cursor (U) session-start-check.sh, and
# Antigravity's pre-invocation-aria.sh (H, responsibility 2) — is run for real, from the repo tree,
# against planted files. Antigravity's generated bin/ has no session-start-check.sh (build.sh skips it:
# the SessionStart work is H's responsibility 2), so there are four sweeping files, not five.
#
#   W_legacy_<name> [P]   a legacy name planted 2 days old in the sweep root is removed by port P
#   W_fresh [P]           the same names planted fresh are kept (-mmin +1440)
#   W_unrelated [P]       an old file matching no listed name is kept (incl. an aria- name not listed)
#   W_depth [P]           an old file one level down, inside an old matching directory, is kept
#   W_nofollow [P]        a link with a listed name pointing outside the root never reaches its target
#   W_indir [P]           in the state dir: an old file removed; a fresh file, an old subdirectory's
#                         file and an old link kept; an old file beside the state dir kept
#   W_marker              exactly the 4 sweeping files carry LEGACY-TMP-SWEEP-2.58, one begin and one
#                         end each, begin first
#   W_shape [file]        each block has exactly 2 finds — root ${KT_TMP_SWEEP_ROOT:-/tmp}/ and root
#                         ${KT_TMP_SWEEP_ROOT:-${TMPDIR:-/tmp}}/ — each -maxdepth 1, -user "$(id -u)",
#                         -mmin +1440, -exec rm -f {} +, never -L/-H/-follow, naming exactly the listed
#                         set (an extra name is over-deletion in the user's real /tmp)
#   N_nolib_<hook>        a hook whose lib-state-key.sh is missing exits 0 with no output (run from a
#                         copy of the port's scripts without the lib); each has a positive control that
#                         the same input with the lib present reaches the state dir
#   N_guard [file]        the four hooks the brief names, in every port that has them, test for the lib
#                         before their first source of it
#
# The user-scoping (-user) cannot be exercised here: a foreign-owned file needs a second uid. W_shape
# pins it textually instead. Everything runs inside one scratch dir under $TMPDIR (HOME, TMPDIR,
# KT_STATE_BASE, KT_TMP_SWEEP_ROOT), so no run reads or writes the real /tmp, the real $TMPDIR, the
# real state dir or ~/.claude/rules.

DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2] got [$3]"; fi; }

command -v jq >/dev/null 2>&1 || { echo "SKIP  state-dir-sweeps: jq is required"; exit 0; }

R=$(mktemp -d "${TMPDIR:-/tmp}/aria-sweeps.XXXXXX") || exit 1
R=$(cd "$R" && pwd)
trap 'chmod -R u+rwx "$R" 2>/dev/null; rm -rf "$R"' EXIT
# The resolver refuses a state dir that carries an ACL (it would let another user in). A scratch dir
# can INHERIT one from its parent, and then every hook goes silent for a reason unrelated to the test.
# Strip it from the scratch root, and from each state dir made below, so an inherited ACL cannot.
strip_acl() {
  chmod -N "$1" 2>/dev/null || :
  if command -v setfacl >/dev/null 2>&1; then setfacl -b "$1" 2>/dev/null || :; fi
}
strip_acl "$R"
UIDN=$(id -u)
BASE="$R/base"; SD="$BASE/aria-knowledge-$UIDN"; SW="$R/sweep"; OUT="$R/outside"
mkdir -p "$BASE" "$SW" "$OUT" "$R/home/.claude" "$R/home/.gemini/antigravity" "$R/tmp"
unset XDG_RUNTIME_DIR KT_HOOK_DEBUG_LOG CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID CLAUDE_SESSION_ID \
  CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH __CFBundleIdentifier KT_SURFACE_CACHE_DIR
export HOME="$R/home" TMPDIR="$R/tmp" KT_TMP_SWEEP_ROOT="$SW" KT_STATE_BASE="$BASE"
KF="$R/kf"; P="$R/w/proj"
mkdir -p "$KF/logs" "$P"
printf -- '- **Date:** 2026-11-01 — audit\n' > "$KF/logs/knowledge-audit-log.md"
printf -- '- **Date:** 2026-11-01 — audit\n' > "$KF/logs/config-audit-log.md"
CFG="$R/cfg.md"
printf -- '---\nknowledge_folder: %s\n---\n' "$KF" > "$CFG"
export KT_CONFIG="$CFG"

C="$DIR/plugin-claude-code/scripts"
X="$DIR/plugin-openai-codex/bin"
U="$DIR/plugin-cursor-template/scripts/aria"
H="$DIR/plugin-antigravity/bin/antigravity/pre-invocation-aria.sh"

# The legacy names, one example per sweep pattern, plus the shapes measured lying around on a real
# machine (Codex test leaks named session-tmp*, carrier temps, per-agent lastedit files).
ROOT1_NAMES='aria-active-t7 aria-active-session-tmpt7ab aria-session-inprogress-t7
aria-session-inprogress-codex-session-tmpt7 aria-bashcd-t7_w_proj aria-codemap-t7_w_proj
aria-codex-codemap-t7-ab12 aria-context-t7 aria-context-session-tmpt7 aria-usage-warn-t7
aria-hook-debug.log aria-digest-t7 .aria-new.t7'
ROOT2_NAMES='aria-r22-lastedit-t7 aria-r22-lastedit-t7.agent-a1 aria-r22-carrier-t7
aria-r22-carrier-t7.tmp.12 aria-r22-denies-t7 aria-r22-bypass-t7 aria-extfetch-t7-example.com
aria-extfetch-denies-t7 aria-preflight-t7 aria-preflight-denies-t7 aria-preflight-skipped-t7
aria-preflight-repo-t7 aria-surface-123.tsv aria-surface-hook.log aria-prompt-config.123.cache
aria-cursor-t7 aria-ag-surfaced-t7 aria-ag-logged-t7 .aria-ag-model.t7 .aria-ag-new.t7'
OLD=202001010000

old() { : > "$1"; touch -t "$OLD" "$1"; }
# aged FILE SECONDS — a file whose mtime is SECONDS in the past (BSD date -r, else GNU date -d).
aged() {
  _t=$(( $(date +%s) - $2 ))
  _s=$(date -r "$_t" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$_t" +%Y%m%d%H%M.%S)
  : > "$1"; touch -t "$_s" "$1"
}
D2=172800; D31=2678400
# D10 (2026-11-15): the state dir splits retention. PROOF names keep 30 days, CHURN names 24 hours.
PROOF_NAMES='aria-preflight-s1 aria-preflight-skipped-s1 aria-preflight-repo-123 aria-r22-bypass-s1 aria-active-s1 aria-ag-surfaced-s1'
CHURN_NAMES='aria-preflight-denies-s1 aria-r22-denies-s1 aria-codemap-s1'

# plant — the sweep root (old + fresh copies, controls) and the state dir.
plant() {
  rm -rf "$SW" "$OUT" "$SD" "$BASE/outside-old"
  mkdir -p "$SW" "$OUT/dir"
  for n in $ROOT1_NAMES $ROOT2_NAMES; do
    old "$SW/$n"
    [ "$n" = aria-hook-debug.log ] || : > "$SW/${n}F"
  done
  old "$SW/unrelated-old"; old "$SW/aria-unlisted-old"; old "$SW/aria-match-filtered.ABC123"
  mkdir "$SW/aria-active-dir"; old "$SW/aria-active-dir/aria-active-inner"; touch -t "$OLD" "$SW/aria-active-dir"
  old "$OUT/target"; ln -s "$OUT/target" "$SW/aria-active-link"; touch -h -t "$OLD" "$SW/aria-active-link" 2>/dev/null
  old "$OUT/dir/aria-r22-x"; ln -s "$OUT/dir" "$SW/aria-r22-linkdir"; touch -h -t "$OLD" "$SW/aria-r22-linkdir" 2>/dev/null
  mkdir -m 700 "$SD"; strip_acl "$SD"
  old "$SD/aria-codemap-indir-old"; : > "$SD/aria-active-indir-new"
  for n in $PROOF_NAMES $CHURN_NAMES; do aged "$SD/${n}.d2" $D2; aged "$SD/${n}.d31" $D31; done
  : > "$SD/aria-active-fresh"; : > "$SD/aria-codemap-fresh"
  mkdir "$SD/aria-active-dir31"; aged "$SD/aria-active-dir31/inner" $D31; touch -t "$OLD" "$SD/aria-active-dir31"
  mkdir "$SD/olddir"; old "$SD/olddir/inner"; touch -t "$OLD" "$SD/olddir"
  old "$OUT/target2"; ln -s "$OUT/target2" "$SD/oldlink"; touch -h -t "$OLD" "$SD/oldlink" 2>/dev/null
  old "$BASE/outside-old"
}

# verify PORT — every arm for one run.
verify() {
  _p=$1
  for n in $ROOT1_NAMES $ROOT2_NAMES; do
    check "W_legacy_$n [$_p]: the old file is removed" "gone" "$([ -e "$SW/$n" ] || [ -L "$SW/$n" ] && echo kept || echo gone)"
  done
  _fk=""
  for n in $ROOT1_NAMES $ROOT2_NAMES; do
    [ "$n" = aria-hook-debug.log ] && continue
    [ -e "$SW/${n}F" ] || _fk="$_fk ${n}F"
  done
  check "W_fresh [$_p]: every fresh copy is kept (removed:$_fk)" "" "$_fk"
  check "W_unrelated [$_p]: unrelated-old|aria-unlisted-old|aria-match-filtered kept" "1|1|1" \
    "$([ -e "$SW/unrelated-old" ] && echo 1 || echo 0)|$([ -e "$SW/aria-unlisted-old" ] && echo 1 || echo 0)|$([ -e "$SW/aria-match-filtered.ABC123" ] && echo 1 || echo 0)"
  check "W_depth [$_p]: a file inside an old matching directory is kept" "1" "$([ -e "$SW/aria-active-dir/aria-active-inner" ] && echo 1 || echo 0)"
  check "W_nofollow [$_p]: a link's target (file, and a file in a linked dir) is kept" "1|1" \
    "$([ -e "$OUT/target" ] && echo 1 || echo 0)|$([ -e "$OUT/dir/aria-r22-x" ] && echo 1 || echo 0)"
  # D10 (2026-11-15): proof names keep 30 days. This arm kept its intent (old in-dir files go) but plants
  # a CHURN name; a proof name at the same age is removed by the 31-day arm below, not here.
  check "W_indir [$_p]: old removed|fresh kept|subdir file kept|old link kept|beside the dir kept" "0|1|1|1|1" \
    "$([ -e "$SD/aria-codemap-indir-old" ] && echo 1 || echo 0)|$([ -e "$SD/aria-active-indir-new" ] && echo 1 || echo 0)|$([ -e "$SD/olddir/inner" ] && echo 1 || echo 0)|$([ -L "$SD/oldlink" ] && echo 1 || echo 0)|$([ -e "$BASE/outside-old" ] && echo 1 || echo 0)"
}

# verify_d10 PORT — split retention in the state dir, one result per (name, age).
verify_d10() {
  _p=$1; _k=""; _r=""; _f=""
  for n in $PROOF_NAMES; do
    [ -e "$SD/${n}.d2" ] || _k="$_k ${n}@2d"
    [ -e "$SD/${n}.d31" ] && _r="$_r ${n}@31d"
  done
  for n in $CHURN_NAMES; do
    [ -e "$SD/${n}.d2" ] && _f="$_f ${n}@2d"
    [ -e "$SD/${n}.d31" ] && _f="$_f ${n}@31d"
  done
  check "W_proof2d [$_p]: every proof name at 2 days is kept (removed:$_k)" "" "$_k"
  check "W_proof31d [$_p]: every proof name at 31 days is removed (kept:$_r)" "" "$_r"
  check "W_churn2d [$_p]: every churn name at 2 and 31 days is removed, aria-preflight-denies-* included (kept:$_f)" "" "$_f"
  # Catches OVER-deletion (an ungrouped proof list, a dropped age test) — not an outer-grouping error (that is W_proof31d / W_indir).
  # The third value guards a dropped -maxdepth/-mindepth: `inner` is an old file with a non-proof (churn)
  # name inside a directory, so only a find that descends reaches and removes it. It does NOT guard -type f
  # (rm -f never removes a directory, so the directory itself survives with or without it; links are W_indir's).
  check "W_fresh_sd [$_p]: a fresh proof file|a fresh churn file|an old churn-named file inside a subdirectory kept (depth bound)" "1|1|1" \
    "$([ -e "$SD/aria-active-fresh" ] && echo 1 || echo 0)|$([ -e "$SD/aria-codemap-fresh" ] && echo 1 || echo 0)|$([ -e "$SD/aria-active-dir31/inner" ] && echo 1 || echo 0)"
}

runp() { (cd "$P" && "$@" < "$R/in" > "$R/out" 2>"$R/err"); }

plant; printf '{"session_id":"t7c","source":"startup"}' > "$R/in"; runp sh "$C/session-start-check.sh"; verify C; verify_d10 C
plant; printf '{"session_id":"t7x","source":"startup"}' > "$R/in"; runp sh "$X/session-start-check.sh"; verify X; verify_d10 X
plant; printf '{"conversation_id":"t7u","hook_event_name":"sessionStart"}' > "$R/in"; runp sh "$U/session-start-check.sh"; verify U; verify_d10 U
plant
cp "$DIR/plugin-antigravity/tests/fixtures/transcript-user-input.jsonl" "$R/t.jsonl"
jq -cn --arg t "$R/t.jsonl" --arg w "$P" --arg a "$R/art" '{conversationId:"t7h", workspacePaths:[$w],
  transcriptPath:$t, artifactDirectoryPath:$a, invocationNum:0, initialNumSteps:5}' > "$R/in"
runp bash "$H"; verify H; verify_d10 H

# --- W_marker / W_shape -----------------------------------------------------------------------------
MARKED=$(cd "$DIR" && grep -rl 'LEGACY-TMP-SWEEP-2\.58' plugin-* 2>/dev/null | grep -v '/tests/' | grep -v '/\.archived/' | sort | tr '\n' ' ')
check "W_marker: exactly the 4 sweeping files carry the marker" \
  "plugin-antigravity/bin/antigravity/pre-invocation-aria.sh plugin-claude-code/scripts/session-start-check.sh plugin-cursor-template/scripts/aria/session-start-check.sh plugin-openai-codex/bin/session-start-check.sh " "$MARKED"
R1_WANT=$(printf '%s\n' 'aria-active-*' 'aria-session-inprogress-*' 'aria-bashcd-*' 'aria-codemap-*' \
  'aria-codex-codemap-*' 'aria-context-*' 'aria-usage-warn-*' 'aria-hook-debug.log' 'aria-digest-*' '.aria-new.*' | sort | tr '\n' ' ')
R2_WANT=$(printf '%s\n' 'aria-r22-*' 'aria-extfetch*' 'aria-preflight*' 'aria-surface-*' 'aria-prompt-config.*' \
  'aria-cursor-*' 'aria-ag-*' '.aria-ag-*' '.aria-new.*' | sort | tr '\n' ' ')
for f in $MARKED; do
  _b=$(grep -c 'LEGACY-TMP-SWEEP-2\.58 begin' "$DIR/$f"); _e=$(grep -c 'LEGACY-TMP-SWEEP-2\.58 end' "$DIR/$f")
  _bl=$(grep -n 'LEGACY-TMP-SWEEP-2\.58 begin' "$DIR/$f" | head -1 | cut -d: -f1)
  _el=$(grep -n 'LEGACY-TMP-SWEEP-2\.58 end' "$DIR/$f" | head -1 | cut -d: -f1)
  check "W_marker [$f]: one begin, one end, begin first" "1|1|1" "$_b|$_e|$([ "${_bl:-0}" -lt "${_el:-0}" ] && echo 1 || echo 0)"
  # The block's code, comments dropped and continuation lines joined: one line per find.
  _finds=$(awk '/LEGACY-TMP-SWEEP-2\.58 begin/ { on = 1; next } /LEGACY-TMP-SWEEP-2\.58 end/ { on = 0 }
    on && !/^[ \t]*#/ { s = $0; if (sub(/\\[ \t]*$/, "", s)) { buf = buf s; next } print buf s; buf = "" }' "$DIR/$f" | grep 'find ')
  _n=$(printf '%s\n' "$_finds" | grep -c 'find ')
  _r1=$(printf '%s\n' "$_finds" | grep -c 'find "${KT_TMP_SWEEP_ROOT:-/tmp}/" ')
  _r2=$(printf '%s\n' "$_finds" | grep -c 'find "${KT_TMP_SWEEP_ROOT:-${TMPDIR:-/tmp}}/" ')
  _bad=$(printf '%s\n' "$_finds" | awk '
    index($0, "-maxdepth 1 ") == 0 || index($0, "-user \"$(id -u)\" ") == 0 || index($0, "-mmin +1440 ") == 0 \
      || index($0, "-exec rm -f {} +") == 0 || $0 ~ /(^|[ \t])-(L|H|follow)([ \t]|$)/ { c++ } END { print c + 0 }')
  names() { printf '%s\n' "$_finds" | grep "$1" | grep -o "\-name '[^']*'" | sed "s/-name '//;s/'$//" | sort | tr '\n' ' '; }
  check "W_shape [$f]: 2 finds|one per root|each maxdepth 1, -user uid, -mmin +1440, rm -f, no link-follow" \
    "2|1|1|0" "$_n|$_r1|$_r2|$_bad"
  check "W_shape [$f]: the /tmp root names exactly the listed set" "$R1_WANT" "$(names 'KT_TMP_SWEEP_ROOT:-/tmp}/')"
  check "W_shape [$f]: the \$TMPDIR root names exactly the listed set" "$R2_WANT" "$(names 'TMPDIR:-/tmp}}/')"
done

# --- W_census (D10) ---------------------------------------------------------------------------------
# The state dir's find is written once, in lib-state-key.sh (kt_state_sweep). A sweeping script that
# carries its own copy would keep the flat 24 h retention and silently erase the proof names. The
# positive control: the library itself must carry exactly one, or this census is reading nothing.
_needle='find "$KT_STATE_DIR/"'
_inline=""
for f in plugin-claude-code/scripts/session-start-check.sh plugin-openai-codex/bin/session-start-check.sh \
  plugin-cursor-template/scripts/aria/session-start-check.sh plugin-antigravity/bin/antigravity/pre-invocation-aria.sh; do
  grep -qF "$_needle" "$DIR/$f" && _inline="$_inline $f"
done
check "W_census: no sweeping script carries an inline in-dir find (carrying:$_inline)" "" "$_inline"
check "W_census control: lib-state-key.sh carries exactly one" "1" "$(grep -cF "$_needle" "$DIR/plugin-claude-code/scripts/lib-state-key.sh")"
_calls=""
for f in plugin-claude-code/scripts/session-start-check.sh plugin-openai-codex/bin/session-start-check.sh \
  plugin-cursor-template/scripts/aria/session-start-check.sh plugin-antigravity/bin/antigravity/pre-invocation-aria.sh; do
  grep -qE '^[^#]*kt_state_sweep' "$DIR/$f" || _calls="$_calls $f"
done
check "W_census: every sweeping script calls kt_state_sweep (not calling:$_calls)" "" "$_calls"

# --- N_nolib / N_guard ------------------------------------------------------------------------------
# A copy of the claude-code scripts without lib-state-key.sh. Sourcing a missing file aborts sh with
# exit 1 even under `2>/dev/null || true` (measured on macOS /bin/sh), so only a [ -f ] test before the
# source keeps the hook silent.
NL="$R/nolib"; cp -R "$C" "$NL"; rm -f "$NL/lib-state-key.sh"
# usage-threshold-inject.sh: the statusline-inject.sh fixture (an account, a snapshot over threshold).
printf '%s\n' '{"oauthAccount":{"accountUuid":"t7-uuid","emailAddress":"a@example.com"}}' > "$HOME/.claude.json"
printf -- '---\nusage_alert_threshold: 80\n---\n' > "$R/cfg-usage.md"
printf '{"five_hour_pct":95,"five_hour_resets_at":%s,"seven_day_pct":10,"context_pct":10,"session_id":"t7n","written_at":"x"}\n' \
  "$(( $(date +%s) + 3600 ))" > "$HOME/.claude/aria-statusline-state-t7-uuid.json"
printf '{"session_id":"t7n"}' > "$R/in"
rm -rf "$SD"; mkdir -m 700 "$SD"; strip_acl "$SD"
runp env KT_CONFIG="$R/cfg-usage.md" sh "$C/usage-threshold-inject.sh"; _ctl=$(grep -c '5-hour' "$R/out")
rm -rf "$SD"; mkdir -m 700 "$SD"; strip_acl "$SD"
runp env KT_CONFIG="$R/cfg-usage.md" sh "$NL/usage-threshold-inject.sh"; _rc=$?
check "N_nolib_usage-threshold-inject: control alerts|no lib: rc 0, no stdout, no stderr" "1|0|0|0" \
  "$_ctl|$_rc|$(wc -c < "$R/out" | tr -d ' ')|$(wc -c < "$R/err" | tr -d ' ')"
# prompt-context-check.sh: empty stdin is logged to the state dir's surfacing log (the control).
: > "$R/in"
rm -rf "$SD"; mkdir -m 700 "$SD"; strip_acl "$SD"
runp sh "$C/prompt-context-check.sh"; _ctl=$(ls -A "$SD" | grep -c .)
rm -rf "$SD"; mkdir -m 700 "$SD"; strip_acl "$SD"
runp sh "$NL/prompt-context-check.sh"; _rc=$?
check "N_nolib_prompt-context-check: control reaches the state dir|no lib: rc 0, no stdout, no stderr, state untouched" \
  "1|0|0|0|0" "$([ "$_ctl" -gt 0 ] && echo 1 || echo 0)|$_rc|$(wc -c < "$R/out" | tr -d ' ')|$(wc -c < "$R/err" | tr -d ' ')|$(ls -A "$SD" | grep -c .)"
# N_guard — the four hooks named for this fix, in every port that has them: a [ -f …lib-state-key.sh ]
# test sits before the first line that sources the lib.
for f in $(cd "$DIR" && ls plugin-claude-code/scripts/bash-cd-check.sh plugin-claude-code/scripts/pre-explore-codemap-check.sh \
  plugin-claude-code/scripts/task-context-check.sh plugin-claude-code/scripts/usage-threshold-inject.sh \
  plugin-claude-code/scripts/prompt-context-check.sh \
  plugin-openai-codex/bin/bash-cd-check.sh plugin-openai-codex/bin/pre-explore-codemap-check.sh plugin-openai-codex/bin/task-context-check.sh \
  plugin-cursor-template/scripts/aria/bash-cd-check.sh plugin-cursor-template/scripts/aria/pre-explore-codemap-check.sh \
  plugin-cursor-template/scripts/aria/task-context-check.sh \
  plugin-antigravity/bin/bash-cd-check.sh plugin-antigravity/bin/pre-explore-codemap-check.sh plugin-antigravity/bin/usage-threshold-inject.sh 2>/dev/null); do
  _g=$(awk '/^[ \t]*#/ { next }
    /\[ -f "\$SCRIPT_DIR\/lib-state-key\.sh" \]/ && !g { g = NR }
    /^[ \t]*\. "\$SCRIPT_DIR\/lib-state-key\.sh"/ && !s { s = NR }
    END { print (g && s && g < s) ? 1 : 0 }' "$DIR/$f")
  check "N_guard [$f]: the lib is tested for before it is sourced" "1" "$_g"
done

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
