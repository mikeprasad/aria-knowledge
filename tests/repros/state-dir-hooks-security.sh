#!/bin/sh
# state-dir-hooks-security.sh — 2.58.0 private state dir, Task 2 (spec D2, D3, D4).
#
# The security state families move from ${TMPDIR:-/tmp} into <base>/aria-knowledge-<uid>
# (lib-state-key.sh): the Rule 22 breaker, carrier and last-edit anchor, the preflight breaker and
# markers, the Rule 22 bypass ledger, and the external-fetch cooldown and breaker. Three live holes
# close with it: a FIFO planted at the preflight breaker name hung the commit hook; a planted Rule 22
# breaker counter switched Rule 22 to DEGRADED (allow); a planted carrier record carrying the turn's
# prompt_id authorised an edit. With no state directory (D3) a gate never degrades into allowing:
# the Rule 22 breaker cannot count and never trips (an unmarked edit is still DENIED), the preflight
# breaker never trips, the fetch gate allows (it is advisory), and the bypass / skipped recordings
# are skipped.
#
# Ports: C claude-code scripts/ · X codex bin/ · U cursor scripts/aria/ · G antigravity bin/ (built
# from C). Each arm runs on every port that has the hook. "Broken" state = a regular file at the
# state name. Old-location plants go in the scratch TMPDIR, which is kept OUTSIDE the state base so a
# listing of one can never see the other. Every hook run is bounded (background + kill).
#   S1 r22_no_state_unmarked_edit_denied_x4     S6 preflight_old_location_fifo_no_hang
#   S2 r22_old_location_counter_ignored         S7 extfetch_no_state_allows
#   S3 r22_old_location_carrier_ignored         S8 markers_no_state_write_nothing
#   S4 r22_no_state_tail_mode                   S9 names_land_in_state_dir
#   S5 preflight_no_state_breaker_never_trips
# Arms named "control" are GUARDS: they prove the arm beside them can fail (the input really reaches
# the state path). They are red on 5a28f60 too, because there the state lives in TMPDIR.

DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2] got [$3]"; fi; }

R=$(mktemp -d "${TMPDIR:-/tmp}/aria-sdhs.XXXXXX") || exit 1
# The bash-write resolver treats a target under a temp dir as scratch and never fires, so the bypass
# arms edit a file in a work dir inside the repo (as hook-markers-safe-create.sh does).
WORK=$(mktemp -d "$DIR/tests/.sdhs-work.XXXXXX") || exit 1
trap 'chmod -R u+rwx "$R" 2>/dev/null; rm -rf "$R" "$WORK"' EXIT
UIDN=$(id -u)
GOOD="$R/base"; SD="$GOOD/aria-knowledge-$UIDN"
BROKEN="$R/broken"
mkdir -p "$GOOD" "$BROKEN" "$R/home" "$R/tmp" "$R/slashtmp" "$R/nomem"
: > "$BROKEN/aria-knowledge-$UIDN"
unset XDG_RUNTIME_DIR
export HOME="$R/home" TMPDIR="$R/tmp" KT_TMP_SWEEP_ROOT="$R/slashtmp"
export ARIA_R22_FLUSH_WAIT_MS=300 ARIA_EF_MEMDIR="$R/nomem" ARIA_EF_CURSOR_MEMDIR="$R/nomem"
printf 'x\n' > "$WORK/f"

C=plugin-claude-code/scripts; X=plugin-openai-codex/bin; U=plugin-cursor-template/scripts/aria
G=plugin-antigravity/bin
FX="$DIR/tests/fixtures"
NC="$FX/transcript-split-noncompliant.jsonl"; NCID=toolu_test_noncompliant
CP="$FX/transcript-split-compliant.jsonl";   CPID=toolu_test_compliant

# A staged code file, so the preflight hook reaches its gate.
REPO="$R/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q . 2>/dev/null; git -C "$REPO" config user.email t@t.t; git -C "$REPO" config user.name t
printf 'code\n' > "$REPO/app.py"; git -C "$REPO" add . 2>/dev/null
REPO_TOP=$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)
REPO_HASH=$(printf '%s' "$REPO_TOP" | cksum | cut -d' ' -f1)
printf -- '---\nknowledge_folder: %s\npreflight_gate: deny\n---\n' "$R/kf" > "$R/pf-deny.md"
printf -- '---\nknowledge_folder: %s\npreflight_gate: warn\n---\n' "$R/kf" > "$R/pf-warn.md"
# A knowledge folder whose curated dir names three domains, so the fetch gate has hits to deny on.
mkdir -p "$R/kf/references"
printf 'notes on alpha.example and beta.example and gamma.example\n' > "$R/kf/references/ef.md"
printf -- '---\nknowledge_folder: %s\nexternal_fetch_gate: on\nexternal_fetch_max_hits: 8\n---\n' "$R/kf" > "$R/ef-on.md"
: > "$R/none.md"

# hrun SECS BASE HOOK [ENV=…] — runs HOOK under state base BASE with stdin $R/in, bounded; sets
# HOUT (stdout), HRC (exit) and HR=ok|hung. On a hang every FIFO under $R is opened read-write (that
# never blocks), which releases a reader stuck on it, and the run is killed.
hrun() {
  _hs=$1; _hb=$2; _hh=$3; shift 3
  env KT_STATE_BASE="$_hb" "$@" sh "$DIR/$_hh" < "$R/in" > "$R/out" 2>/dev/null &
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
has() { case "$2" in *"$1"*) echo 1 ;; *) echo 0 ;; esac; }
# Rule 22 verdict of the last pre-edit run.
r22v() {
  if [ "$(has '"permissionDecision":"deny"' "$HOUT")" = 1 ]; then echo deny
  elif [ "$(has DEGRADED "$HOUT")" = 1 ]; then echo degraded
  elif [ "$(has 'could not verify' "$HOUT")" = 1 ]; then echo unknown
  elif [ -z "$HOUT" ]; then echo allow
  else echo other; fi
}
# lst DIR — a stable listing (names, types) of everything under DIR.
lst() { (cd "$1" 2>/dev/null && find . -exec ls -ldn {} + 2>/dev/null | awk '{print $1, $NF}' | LC_ALL=C sort); }
fresh_tmp() { rm -rf "$TMPDIR"; mkdir -p "$TMPDIR"; }
edit_in() {  # SID TRANSCRIPT TOOL_USE_ID [PROMPT_ID]
  if [ -n "${4:-}" ]; then
    printf '{"file_path":"/tmp/test.txt","session_id":"%s","transcript_path":"%s","tool_use_id":"%s","prompt_id":"%s"}' "$1" "$2" "$3" "$4" > "$R/in"
  else
    printf '{"file_path":"/tmp/test.txt","session_id":"%s","transcript_path":"%s","tool_use_id":"%s"}' "$1" "$2" "$3" > "$R/in"
  fi
}
commit_in() { printf '{"session_id":"%s","tool_input":{"command":"cd %s && git commit -m x"}}' "$1" "$REPO" > "$R/in"; }
fetch_in()  { printf '{"url":"%s","session_id":"%s"}' "$1" "$2" > "$R/in"; }
bypass_in() {
  python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]},"session_id":sys.argv[2]}))' \
    "sed -i '' s/a/b/ $WORK/f" "$1" > "$R/in"
}
carrier_in() {  # SID PROMPT_ID
  python3 -c 'import json,sys
print(json.dumps({"session_id":sys.argv[1],"prompt_id":sys.argv[2],"transcript_path":"/tmp/t.jsonl","cwd":"/tmp",
  "hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"toolu_bash_x",
  "tool_input":{"command":"cat <<'"'"'R22'"'"'\n[Rule 22] Low Impact — probe (test only)\nR22","description":"probe"}},
  separators=(",",":")))' "$1" "$2" > "$R/in"
}

# --- S1 r22_no_state_unmarked_edit_denied_x4 (C G) --------------------------------------------
for P in C G; do
  eval "PD=\$$P"; fresh_tmp; v=""; dg=0
  for n in 1 2 3 4; do
    edit_in "s1$P" "$NC" "$NCID"; hrun 10 "$BROKEN" "$PD/pre-edit-check.sh" KT_CONFIG="$R/none.md"
    v="$v$(r22v) "; dg=$((dg + $(has DEGRADED "$HOUT")))
  done
  check "S1 r22_no_state_unmarked_edit_denied_x4 [$P]: four denials, never DEGRADED" \
    "deny deny deny deny |0" "$v|$dg"
done

# --- S2 r22_old_location_counter_ignored (C G) ------------------------------------------------
for P in C G; do
  eval "PD=\$$P"; fresh_tmp; rm -rf "$SD"
  printf '9' > "$TMPDIR/aria-r22-denies-s2$P"
  edit_in "s2$P" "$NC" "$NCID"; hrun 10 "$GOOD" "$PD/pre-edit-check.sh" KT_CONFIG="$R/none.md"
  check "S2 r22_old_location_counter_ignored [$P]: a 9 planted in TMPDIR → still denied" "deny" "$(r22v)"
  # control: the same counter in the state dir trips the breaker — the arm above can see DEGRADED.
  mkdir -p -m 700 "$SD"; printf '9' > "$SD/aria-r22-denies-s2c$P"
  edit_in "s2c$P" "$NC" "$NCID"; hrun 10 "$GOOD" "$PD/pre-edit-check.sh" KT_CONFIG="$R/none.md"
  check "S2 control [$P]: a 9 in the state dir → DEGRADED" "degraded" "$(r22v)"
done

# --- S3 r22_old_location_carrier_ignored (C G) ------------------------------------------------
for P in C G; do
  eval "PD=\$$P"; fresh_tmp; rm -rf "$SD"
  printf '{"prompt_id":"p-s3%s","tool_use_id":"x","recorded_at":1}' "$P" > "$TMPDIR/aria-r22-carrier-s3$P"
  edit_in "s3$P" "$NC" "$NCID" "p-s3$P"; hrun 10 "$GOOD" "$PD/pre-edit-check.sh" KT_CONFIG="$R/none.md"
  check "S3 r22_old_location_carrier_ignored [$P]: a carrier planted in TMPDIR → denied" "deny" "$(r22v)"
  # control: the same record in the state dir authorises — the arm above can see an allow.
  mkdir -p -m 700 "$SD"
  printf '{"prompt_id":"p-s3c%s","tool_use_id":"x","recorded_at":1}' "$P" > "$SD/aria-r22-carrier-s3c$P"
  edit_in "s3c$P" "$NC" "$NCID" "p-s3c$P"; hrun 10 "$GOOD" "$PD/pre-edit-check.sh" KT_CONFIG="$R/none.md"
  check "S3 control [$P]: the same record in the state dir → allowed" "allow" "$(r22v)"
done

# --- S4 r22_no_state_tail_mode (carrier C; pre-edit C G) --------------------------------------
fresh_tmp
b_tmp=$(lst "$TMPDIR"); b_brk=$(lst "$BROKEN"); b_sl=$(lst "$R/slashtmp")
carrier_in s4 p-s4; hrun 10 "$BROKEN" "$C/pre-bash-r22-carrier.sh"
check "S4 r22_no_state_tail_mode [C carrier]: exit 0, bounded, TMPDIR|base|/tmp scratch unchanged" \
  "0|ok|1|1|1" "$HRC|$HR|$([ "$(lst "$TMPDIR")" = "$b_tmp" ] && echo 1 || echo 0)|$([ "$(lst "$BROKEN")" = "$b_brk" ] && echo 1 || echo 0)|$([ "$(lst "$R/slashtmp")" = "$b_sl" ] && echo 1 || echo 0)"
# control: with a state dir the same input IS recorded there — the input really is a carrier.
rm -rf "$SD"; carrier_in s4c p-s4c; hrun 10 "$GOOD" "$C/pre-bash-r22-carrier.sh"
check "S4 control [C carrier]: healthy state → the record is in the state dir" "1" \
  "$([ -f "$SD/aria-r22-carrier-s4c" ] && echo 1 || echo 0)"
for P in C G; do
  eval "PD=\$$P"
  edit_in "s4$P" "$CP" "$CPID" "p-s4"; hrun 10 "$BROKEN" "$PD/pre-edit-check.sh" KT_CONFIG="$R/none.md"
  check "S4 r22_no_state_tail_mode [$P pre-edit]: marker in the transcript, no state → allowed" "allow" "$(r22v)"
done

# --- S5 preflight_no_state_breaker_never_trips (C X U G) --------------------------------------
for P in C X U G; do
  eval "PD=\$$P"; fresh_tmp; outs=""; nd=0; ng=0
  for n in 1 2 3 4 5; do
    commit_in "s5$P"; hrun 10 "$BROKEN" "$PD/pre-commit-preflight-check.sh" KT_CONFIG="$R/pf-deny.md"
    printf '%s\n' "$HOUT" >> "$R/s5-$P"
    nd=$((nd + $(has '"deny"' "$HOUT"))); ng=$((ng + $(has DEGRADED "$HOUT")))
  done
  check "S5 preflight_no_state_breaker_never_trips [$P]: distinct responses|denials|degraded" "1|5|0" \
    "$(LC_ALL=C sort -u "$R/s5-$P" | grep -c .)|$nd|$ng"
done

# --- S6 preflight_old_location_fifo_no_hang (C X U G) -----------------------------------------
for P in C X U G; do
  eval "PD=\$$P"; fresh_tmp; rm -rf "$SD"
  mkfifo "$TMPDIR/aria-preflight-denies-s6$P"
  commit_in "s6$P"; hrun 2 "$GOOD" "$PD/pre-commit-preflight-check.sh" KT_CONFIG="$R/pf-deny.md"
  check "S6 preflight_old_location_fifo_no_hang [$P]: FIFO in TMPDIR → returns within 2 s, denies" \
    "ok|1" "$HR|$(has '"deny"' "$HOUT")"
done

# --- S7 extfetch_no_state_allows (C X U G) ----------------------------------------------------
for P in C X U G; do
  eval "PD=\$$P"; fresh_tmp; dn=0; rcs=""
  for u in https://alpha.example/a https://beta.example/b https://gamma.example/c; do
    fetch_in "$u" "s7$P"; hrun 10 "$BROKEN" "$PD/pre-external-fetch-check.sh" KT_CONFIG="$R/ef-on.md"
    dn=$((dn + $(has '"deny"' "$HOUT"))); rcs="$rcs$HRC "
  done
  check "S7 extfetch_no_state_allows [$P]: three covered fetches, no state → denials|exits" "0|0 0 0 " "$dn|$rcs"
  # control: with a state dir the first of them IS denied — the corpus really covers it.
  rm -rf "$SD"; fetch_in https://alpha.example/a "s7c$P"
  hrun 10 "$GOOD" "$PD/pre-external-fetch-check.sh" KT_CONFIG="$R/ef-on.md"
  check "S7 control [$P]: healthy state → the covered fetch is denied" "1" "$(has '"deny"' "$HOUT")"
done

# --- S8 markers_no_state_write_nothing (bypass C X U; preflight-skipped C X U G) --------------
fresh_tmp
b_tmp=$(lst "$TMPDIR"); b_brk=$(lst "$BROKEN"); b_sl=$(lst "$R/slashtmp")
for P in C X U; do
  eval "PD=\$$P"; bypass_in "s8$P"; hrun 10 "$BROKEN" "$PD/pre-bash-write-check.sh" KT_CONFIG="$R/none.md"
  check "S8 [$P bypass]: the warning is still emitted" "1" "$(has 'modifies a file in place' "$HOUT")"
done
for P in C X U G; do
  eval "PD=\$$P"; commit_in "s8$P"; hrun 10 "$BROKEN" "$PD/pre-commit-preflight-check.sh" KT_CONFIG="$R/pf-warn.md"
  check "S8 [$P preflight-skipped]: the warning is still emitted" "1" "$(has 'PREFLIGHT: no preflight' "$HOUT")"
done
check "S8 markers_no_state_write_nothing: TMPDIR|base|/tmp scratch listings unchanged" "1|1|1" \
  "$([ "$(lst "$TMPDIR")" = "$b_tmp" ] && echo 1 || echo 0)|$([ "$(lst "$BROKEN")" = "$b_brk" ] && echo 1 || echo 0)|$([ "$(lst "$R/slashtmp")" = "$b_sl" ] && echo 1 || echo 0)"
# control: with a state dir both recordings land there — the hooks really reach the write.
rm -rf "$SD"
for P in C X U; do
  eval "PD=\$$P"; bypass_in "s8c$P"; hrun 10 "$GOOD" "$PD/pre-bash-write-check.sh" KT_CONFIG="$R/none.md"
  check "S8 control [$P bypass]: healthy state → recorded in the state dir" "1" \
    "$([ -s "$SD/aria-r22-bypass-s8c$P" ] && echo 1 || echo 0)"
done
for P in C X U G; do
  eval "PD=\$$P"; commit_in "s8c$P"; hrun 10 "$GOOD" "$PD/pre-commit-preflight-check.sh" KT_CONFIG="$R/pf-warn.md"
  check "S8 control [$P preflight-skipped]: healthy state → recorded in the state dir" "1" \
    "$([ -s "$SD/aria-preflight-skipped-s8c$P" ] && echo 1 || echo 0)"
done

# --- S9 names_land_in_state_dir ----------------------------------------------------------------
nowhere_in_tmp() { find "$TMPDIR" -name "$1" 2>/dev/null | grep -c .; }
for P in C G; do
  eval "PD=\$$P"; fresh_tmp; rm -rf "$SD"
  edit_in "s9$P" "$NC" "$NCID"; hrun 10 "$GOOD" "$PD/pre-edit-check.sh" KT_CONFIG="$R/none.md"
  check "S9 names_land_in_state_dir [$P r22]: denied|counter in state dir|none in TMPDIR" "deny|1|0" \
    "$(r22v)|$(cat "$SD/aria-r22-denies-s9$P" 2>/dev/null)|$(nowhere_in_tmp 'aria-r22-*')"
done
for P in C X U G; do
  eval "PD=\$$P"; fresh_tmp; rm -rf "$SD"
  fetch_in https://alpha.example/a "s9$P"; hrun 10 "$GOOD" "$PD/pre-external-fetch-check.sh" KT_CONFIG="$R/ef-on.md"
  check "S9 names_land_in_state_dir [$P fetch]: denied|counter|cooldown in state dir|none in TMPDIR" "1|1|1|0" \
    "$(has '"deny"' "$HOUT")|$(cat "$SD/aria-extfetch-denies-s9$P" 2>/dev/null)|$([ -f "$SD/aria-extfetch-s9$P-alpha.example" ] && echo 1 || echo 0)|$(nowhere_in_tmp 'aria-extfetch*')"
done
for P in C X U G; do
  eval "PD=\$$P"; fresh_tmp; rm -rf "$SD"
  commit_in "s9$P"; hrun 10 "$GOOD" "$PD/pre-commit-preflight-check.sh" KT_CONFIG="$R/pf-deny.md"
  check "S9 names_land_in_state_dir [$P preflight]: denied|counter in state dir|none in TMPDIR" "1|1|0" \
    "$(has '"deny"' "$HOUT")|$(cat "$SD/aria-preflight-denies-s9$P" 2>/dev/null)|$(nowhere_in_tmp 'aria-preflight*')"
  # A marker written at <state dir>/aria-preflight-<sid> satisfies the gate …
  mkdir -p -m 700 "$SD"; printf 't\tPASS\tfixture\n' > "$SD/aria-preflight-s9m$P"
  commit_in "s9m$P"; hrun 10 "$GOOD" "$PD/pre-commit-preflight-check.sh" KT_CONFIG="$R/pf-deny.md"
  check "S9 [$P preflight]: a marker in the state dir satisfies the commit gate" "0|" "$(has '"deny"' "$HOUT")|$HOUT"
  # … and the same marker at the old TMPDIR location does not.
  printf 't\tPASS\tfixture\n' > "$TMPDIR/aria-preflight-s9o$P"
  commit_in "s9o$P"; hrun 10 "$GOOD" "$PD/pre-commit-preflight-check.sh" KT_CONFIG="$R/pf-deny.md"
  check "S9 [$P preflight]: a marker at the old TMPDIR location is ignored" "1" "$(has '"deny"' "$HOUT")"
done
# Codex only: its per-repo marker lives in the state dir too.
fresh_tmp; rm -rf "$SD"; mkdir -p -m 700 "$SD"
printf 't\tPASS\tfixture\n' > "$SD/aria-preflight-repo-$REPO_HASH"
commit_in s9rX; hrun 10 "$GOOD" "$X/pre-commit-preflight-check.sh" KT_CONFIG="$R/pf-deny.md"
check "S9 [X preflight]: a repo marker in the state dir satisfies the commit gate" "0|" "$(has '"deny"' "$HOUT")|$HOUT"
rm -f "$SD/aria-preflight-repo-$REPO_HASH"
printf 't\tPASS\tfixture\n' > "$TMPDIR/aria-preflight-repo-$REPO_HASH"
commit_in s9roX; hrun 10 "$GOOD" "$X/pre-commit-preflight-check.sh" KT_CONFIG="$R/pf-deny.md"
check "S9 [X preflight]: a repo marker at the old TMPDIR location is ignored" "1" "$(has '"deny"' "$HOUT")"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
