#!/bin/sh
# state-dir-hooks-reminders.sh — 2.58.0 private state dir, Task 3 (spec D3, D4).
#
# The reminder families move from /tmp into <base>/aria-knowledge-<uid> (lib-state-key.sh): the
# bash-cd, codemap and task-context cooldowns, the usage warn bands, the SESSION.md in-progress cache
# and Cursor's hook debug log. With no state directory (D3) the reminders and the usage alert emit
# NOTHING (with no cooldown they would repeat on every call), the in-progress mark still happens
# (once: a second edit leaves SESSION.md byte-identical), and the debug log is not written at all.
#
# Ports: C claude-code scripts/ · X codex bin/ · U cursor scripts/aria/ · G antigravity bin/ (built
# from C). Each arm runs on every port that has the hook. "Broken" state = a regular file at the
# state name.
#
# No run touches the real /tmp. Every hook runs from a scratch COPY of its port directory in which
# the literal "/tmp/" is rewritten to a scratch stand-in ($ST), so the pre-2.58.0 code (whose names
# are literal /tmp paths) writes there instead. Q8 is the census that keeps that substitution honest:
# it fails if any shipped hook still names one of these families under a literal /tmp/.
#   Q1 cooldowns_no_state_emit_nothing          Q5 cooldown_names_in_state_dir
#   Q2 usage_no_state_emit_nothing              Q6 fifo_at_state_name_is_no_state (bounded)
#   Q3 inprogress_no_state_marks_anyway         Q7 old_location_plants_ignored
#   Q4 debug_log_no_state_writes_nothing        Q8 no_literal_tmp_names (census, with a control)
# Arms labelled GUARD prove the arm beside them can fail (the input really reaches the hook's
# reminder, or its state). Q3's no-state arm and Q6's post-edit arm are guards on d399d8e as well:
# there the cache sits in /tmp and the mark already happens once.

DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2] got [$3]"; fi; }

R=$(mktemp -d "${TMPDIR:-/tmp}/aria-sdhr.XXXXXX") || exit 1
R=$(cd "$R" && pwd)
trap 'chmod -R u+rwx "$R" 2>/dev/null; rm -rf "$R"' EXIT
UIDN=$(id -u)
GOOD="$R/base"; SD="$GOOD/aria-knowledge-$UIDN"
BROKEN="$R/broken"
ST="$R/slashtmp"
mkdir -p "$GOOD" "$BROKEN" "$R/home/.claude" "$R/tmp" "$ST" "$R/ports" "$R/bin-date"
: > "$BROKEN/aria-knowledge-$UIDN"
# The state dir exists up front, so a plant can be made in it before any hook has run.
mkdir -m 700 "$SD"
unset XDG_RUNTIME_DIR KT_HOOK_DEBUG_LOG CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH __CFBundleIdentifier
export HOME="$R/home" TMPDIR="$R/tmp" KT_TMP_SWEEP_ROOT="$ST" KT_EDIT_INTENT_FILE="$R/intent.json"

# Scratch port copies, "/tmp/" → "$ST/" in their top-level shell scripts.
for _pc in C:plugin-claude-code/scripts X:plugin-openai-codex/bin U:plugin-cursor-template/scripts/aria \
           G:plugin-antigravity/bin; do
  _t=${_pc%%:*}; _p=${_pc#*:}
  cp -R "$DIR/$_p" "$R/ports/$_t"
  for _f in "$R/ports/$_t"/*.sh; do
    sed "s|/tmp/|$ST/|g" "$_f" > "$_f.new" && mv "$_f.new" "$_f"
  done
done
PT="$R/ports"

# A date shim: `date -u …` prints $Q_DATE when it is set, so a second SESSION.md mark is visible as a
# changed `at:` line regardless of how fast the run is.
REAL_DATE=$(command -v date)
cat > "$R/bin-date/date" <<SHIM
#!/bin/sh
if [ "\$1" = -u ] && [ -n "\${Q_DATE:-}" ]; then printf '%s\n' "\$Q_DATE"; exit 0; fi
exec "$REAL_DATE" "\$@"
SHIM
chmod +x "$R/bin-date/date"

# Fixtures: a knowledge folder with an index, and a project with a fresh CODEMAP (so bash-cd and
# task-context surface it as a tracked artifact) and a PROGRESS.md (so it is a SESSION.md root).
KF="$R/kf"; P="$R/w/fxproj"
mkdir -p "$KF" "$P"
printf '# Index\n\n## Tag Index\n' > "$KF/index.md"
printf '# CODEMAP\n\n## Directory\n' > "$P/CODEMAP.md"
printf '# p\n' > "$P/PROGRESS.md"; printf 'x\n' > "$P/a.txt"
CFG="$R/cfg.md"
printf -- '---\nknowledge_folder: %s\nprojects_enabled: true\nprojects_list: fx:fxproj\nactive_knowledge_surfacing: false\nusage_alert_threshold: 80\nsession_state: true\n---\n' "$KF" > "$CFG"
export KT_CONFIG="$CFG"
NOW=$(date +%s); FUT=$((NOW + 3600))
# The usage snapshot, at both the claude-code and the antigravity path.
mkdir -p "$HOME/.gemini/antigravity"
printf '{"five_hour_pct":95,"five_hour_resets_at":%s,"seven_day_pct":10,"context_pct":10,"session_id":"none","written_at":"x"}\n' \
  "$FUT" > "$HOME/.claude/aria-statusline-state-default.json"
cp "$HOME/.claude/aria-statusline-state-default.json" "$HOME/.gemini/antigravity/"
PKEY=$(printf '%s' "$P" | tr '/' '_')

# hrun SECS BASE HOOK [ENV=…] — runs HOOK (a path) under state base BASE from cwd $P with stdin
# $R/in, bounded; sets HOUT, HRC and HR=ok|hung. On a hang every FIFO under $R is opened read-write
# (that never blocks), which releases a reader stuck on it, and the run is killed.
hrun() {
  _hs=$1; _hb=$2; _hh=$3; shift 3
  (cd "$P" && exec env KT_STATE_BASE="$_hb" "$@" sh "$_hh" < "$R/in" > "$R/out" 2>/dev/null) &
  _hp=$!; _hi=0; HR=ok
  while kill -0 "$_hp" 2>/dev/null; do
    _hi=$((_hi + 1))
    if [ "$_hi" -gt $((_hs * 20)) ]; then
      HR=hung
      for _hf in $(find "$R" -type p 2>/dev/null); do exec 9<>"$_hf"; exec 9>&-; done
      kill "$_hp" 2>/dev/null
      break
    fi
    sleep 0.05
  done
  wait "$_hp" 2>/dev/null; HRC=$?
  HOUT=$(cat "$R/out")
}
# in_KIND SID — the hook input for one family.
in_bashcd()   { printf '{"command":"cd %s","session_id":"%s"}' "$P" "$1" > "$R/in"; }
in_codemap()  { printf '{"path":"%s","session_id":"%s"}' "$P" "$1" > "$R/in"; }
in_context()  { printf '{"session_id":"%s","task_subject":"s","task_description":"d"}' "$1" > "$R/in"; }
in_usage()    { printf '{"session_id":"%s"}' "$1" > "$R/in"; }
in_edit()     { printf '{"session_id":"%s","file_path":"%s"}' "$1" "$P/a.txt" > "$R/in"; }
# name_KIND SID — the state name each family keeps.
name_bashcd()  { echo "aria-bashcd-$1-$PKEY"; }
name_codemap() { echo "aria-codemap-$1-$PKEY"; }
name_context() { echo "aria-context-$1"; }
name_usage()   { echo "aria-usage-warn-$1"; }
hook_of() {
  case $1 in bashcd) echo bash-cd-check.sh ;; codemap) echo pre-explore-codemap-check.sh ;;
    context) echo task-context-check.sh ;; usage) echo usage-threshold-inject.sh ;; esac
}
ports_of() {
  case $1 in bashcd|codemap) echo "C X U G" ;; context) echo "C X U" ;; usage) echo "C G" ;; esac
}
nonempty() { [ -n "$1" ] && echo 1 || echo 0; }
fresh_session() {
  printf -- '---\nlastEvent: wrapup\nat: 2026-01-01T00:00:00Z\nsessionId: old\n---\n\n# body\n' > "$P/SESSION.md"
}
first_le() { awk 'NR > 1 && $0 == "---" { exit } /^lastEvent:/ { sub(/^lastEvent: */, ""); print; exit }' "$P/SESSION.md"; }

# --- Q1 / Q2 — no state directory: the reminders and the usage alert emit nothing ----------------
for k in bashcd codemap context usage; do
  for t in $(ports_of $k); do
    sid="q1$k$t"; "in_$k" "$sid"
    hrun 10 "$BROKEN" "$PT/$t/$(hook_of $k)"; o1=$HOUT; h1=$HR
    hrun 10 "$BROKEN" "$PT/$t/$(hook_of $k)"; o2=$HOUT
    q=Q1; [ $k = usage ] && q=Q2
    check "$q ${k}_no_state_emit_nothing[$t]: first|second|bounded" "0|0|ok" "$(nonempty "$o1")|$(nonempty "$o2")|$h1"
  done
done

# --- Q3 — no state directory: the in-progress mark happens anyway, and only once ----------------
for t in C U G; do
  sid="q3$t"; in_edit "$sid"; fresh_session
  hrun 10 "$BROKEN" "$PT/$t/post-edit-check.sh" PATH="$R/bin-date:$PATH" Q_DATE=2026-11-01T00:00:01Z
  cp "$P/SESSION.md" "$R/s1"
  hrun 10 "$BROKEN" "$PT/$t/post-edit-check.sh" PATH="$R/bin-date:$PATH" Q_DATE=2026-11-01T00:00:02Z
  check "Q3 inprogress_no_state_marks_anyway[$t]: first edit marks (lastEvent|at)" \
    "in-progress|1" "$(awk '/^lastEvent:/{sub(/^lastEvent: */,"");print;exit}' "$R/s1")|$(grep -c '^at: 2026-11-01T00:00:01Z$' "$R/s1")"
  check "Q3 inprogress_no_state_marks_anyway[$t]: second edit leaves SESSION.md byte-identical" \
    "same" "$(cmp -s "$R/s1" "$P/SESSION.md" && echo same || echo changed)"
done

# --- Q4 — no state directory: the Cursor debug log is written nowhere -----------------------------
mkdir -p "$KF/intake"
printf '{"session_id":"q4","filePath":"%s"}' "$P/a.txt" > "$R/in"
for s in pre-edit-check.sh post-edit-check.sh record-edit-intent.sh capture-task-boundary.sh; do
  hrun 10 "$BROKEN" "$PT/U/$s"
done
check "Q4 debug_log_no_state_writes_nothing: aria-hook-debug.log files under the scratch roots" "0" \
  "$(find "$R" -name 'aria-hook-debug.log' 2>/dev/null | grep -c .)"
Q4NOTE=$(find "$KF/intake/task-boundary-captures" -type f 2>/dev/null | head -1)
check "Q4 debug_log_no_state: the boundary note says the state directory is unavailable" "1" \
  "$( [ -n "$Q4NOTE" ] && grep -q '(state directory unavailable)' "$Q4NOTE" && echo 1 || echo 0)"
rm -rf "$KF/intake"

# --- Q5 — healthy state: the names land in the state dir and the cooldown holds ------------------
for k in bashcd codemap context usage; do
  for t in $(ports_of $k); do
    sid="q5$k$t"; "in_$k" "$sid"
    hrun 10 "$GOOD" "$PT/$t/$(hook_of $k)"; o1=$HOUT
    hrun 10 "$GOOD" "$PT/$t/$(hook_of $k)"; o2=$HOUT
    n="$SD/$("name_$k" "$sid")"
    check "Q5 GUARD ${k}[$t]: the first call reminds" "1" "$(nonempty "$o1")"
    check "Q5 ${k}_name_in_state_dir[$t]: regular file in the state dir|second call silent" "1|0" \
      "$( [ -f "$n" ] && [ ! -L "$n" ] && echo 1 || echo 0)|$(nonempty "$o2")"
  done
done
for t in C U G; do
  sid="q5e$t"; in_edit "$sid"; fresh_session
  hrun 10 "$GOOD" "$PT/$t/post-edit-check.sh"
  n="$SD/aria-session-inprogress-$sid"
  check "Q5 inprogress_name_in_state_dir[$t]: marked|cache in the state dir holds the root" "in-progress|1" \
    "$(first_le)|$(grep -cxF "$P" "$n" 2>/dev/null || echo 0)"
done
printf '{"session_id":"q5d","filePath":"%s"}' "$P/a.txt" > "$R/in"
hrun 10 "$GOOD" "$PT/U/post-edit-check.sh"
check "Q5 debug_log_in_state_dir[U]: regular log in the state dir|no other copy" "1|1" \
  "$( [ -f "$SD/aria-hook-debug.log" ] && [ -s "$SD/aria-hook-debug.log" ] && echo 1 || echo 0)|$(find "$R" -name 'aria-hook-debug.log' 2>/dev/null | grep -c .)"
mkdir -p "$KF/intake"; printf '{}' > "$R/in"; printf 'Q5-STATE-DIR-LINE\n' >> "$SD/aria-hook-debug.log"
hrun 10 "$GOOD" "$PT/U/capture-task-boundary.sh"
Q5NOTE=$(find "$KF/intake/task-boundary-captures" -type f 2>/dev/null | head -1)
check "Q5 debug_log_read[U]: the boundary note quotes the state-dir log" "1" \
  "$( [ -n "$Q5NOTE" ] && grep -q 'Q5-STATE-DIR-LINE' "$Q5NOTE" && echo 1 || echo 0)"
rm -rf "$KF/intake"

# --- Q6 — a FIFO at the state name is no state: bounded, reminders silent, mark still happens ----
for k in bashcd codemap context usage; do
  for t in $(ports_of $k); do
    sid="q6$k$t"; "in_$k" "$sid"; n="$SD/$("name_$k" "$sid")"; mkfifo "$n"
    hrun 5 "$GOOD" "$PT/$t/$(hook_of $k)"
    check "Q6 ${k}_fifo_is_no_state[$t]: bounded|silent|still a FIFO" "ok|0|1" \
      "$HR|$(nonempty "$HOUT")|$( [ -p "$n" ] && echo 1 || echo 0)"
  done
done
for t in C U G; do
  sid="q6e$t"; in_edit "$sid"; fresh_session; n="$SD/aria-session-inprogress-$sid"; mkfifo "$n"
  hrun 5 "$GOOD" "$PT/$t/post-edit-check.sh"
  check "Q6 GUARD inprogress_fifo[$t]: bounded|marked|still a FIFO" "ok|in-progress|1" \
    "$HR|$(first_le)|$( [ -p "$n" ] && echo 1 || echo 0)"
done
rm -f "$SD/aria-hook-debug.log"; mkfifo "$SD/aria-hook-debug.log"
printf '{"session_id":"q6d","filePath":"%s"}' "$P/a.txt" > "$R/in"
hrun 5 "$GOOD" "$PT/U/post-edit-check.sh"
check "Q6 debug_log_fifo[U]: bounded|still a FIFO" "ok|1" "$HR|$( [ -p "$SD/aria-hook-debug.log" ] && echo 1 || echo 0)"
rm -f "$SD/aria-hook-debug.log"

# --- Q7 — a cooldown planted at the OLD location is ignored ---------------------------------------
for k in bashcd codemap context usage; do
  for t in $(ports_of $k); do
    sid="q7$k$t"; "in_$k" "$sid"; n=$("name_$k" "$sid")
    printf '%s\n' "$NOW" > "$ST/$n"; printf '%s\n' "$NOW" > "$TMPDIR/$n"
    [ $k = usage ] && { printf 'context=95\nfive_hour=95\nseven_day=95\n' > "$ST/$n"; cp "$ST/$n" "$TMPDIR/$n"; }
    hrun 10 "$GOOD" "$PT/$t/$(hook_of $k)"
    check "Q7 ${k}_old_location_ignored[$t]: still reminds" "1" "$(nonempty "$HOUT")"
  done
done

# --- Q8 — census: no shipped hook names these families under a literal /tmp/ ---------------------
Q8PAT='/tmp/aria-(bashcd|codemap|context-|usage-warn|session-inprogress|hook-debug)'
q8scan() { grep -En "$Q8PAT" "$@" 2>/dev/null; }
printf 'COOLDOWN_FILE="/tmp/aria-bashcd-x"\nLOG=/tmp/aria-hook-debug.log\nok=/var/aria-bashcd-x\n' > "$R/q8control.sh"
check "Q8 control: the scanner reports exactly the 2 planted literals" "2" "$(q8scan "$R/q8control.sh" | grep -c .)"
Q8HITS=$(q8scan "$DIR"/plugin-claude-code/scripts/*.sh "$DIR"/plugin-openai-codex/bin/*.sh \
  "$DIR"/plugin-cursor-template/scripts/aria/*.sh "$DIR"/plugin-antigravity/bin/*.sh)
Q8N=$(ls "$DIR"/plugin-claude-code/scripts/*.sh "$DIR"/plugin-openai-codex/bin/*.sh \
  "$DIR"/plugin-cursor-template/scripts/aria/*.sh "$DIR"/plugin-antigravity/bin/*.sh 2>/dev/null | grep -c .)
check "Q8 no_literal_tmp_names: hits over $Q8N hook scripts" "0" "$(printf '%s' "$Q8HITS" | grep -c .)"
[ -n "$Q8HITS" ] && printf '%s\n' "$Q8HITS" | sed 's/^/      /'
[ "$Q8N" -gt 0 ] || bad "Q8 examined zero scripts" "a dead census is not a pass"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
