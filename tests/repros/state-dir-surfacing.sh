#!/bin/sh
# state-dir-surfacing.sh — 2.58.0 private state dir, Task 4 (spec D3, D4).
#
# The surfacing family moves into <base>/aria-knowledge-<uid> (lib-state-key.sh): the session ledger
# aria-active-<id>, the parsed-index cache aria-surface-<n>.tsv, the config-value cache
# aria-prompt-config.<n>.cache, the debug log aria-surface-hook.log and Cursor's pending pair. With no
# state directory (D3) every HOOK surfaces nothing and logs nothing (without the ledger the same files
# would be injected on every prompt); the aria-surface.sh CLI keeps no ledger and still ranks, uncached.
# KT_SURFACE_CACHE_DIR is retired: it is exported for the WHOLE run, and F4 requires that nothing is
# ever written there.
#
# Ports: C claude-code scripts/ · X codex bin/ · U cursor scripts/aria/ · G antigravity bin/ (built
# from C). Antigravity's hand-authored PreInvocation hook (H) is covered in
# plugin-antigravity/tests/test-pre-invocation-aria.bats. "Broken" state = a regular file at the
# state name.
#
# No run touches the real /tmp or TMPDIR: every hook runs from a scratch COPY of its port directory in
# which the literal "/tmp/" is rewritten to a scratch stand-in ($ST), and TMPDIR is a scratch dir, so
# the pre-2.58.0 code (literal /tmp ledgers, $TMPDIR caches) writes into the scratch tree instead.
#   F1 hooks_no_state_surface_nothing      F5 cli_ranks_without_state
#   F2 ledger_in_state_dir_dedupes         F6 lib_parity (cksum per set)
#   F3 caches_in_state_dir                 F7 nonfile_at_state_name (bounded, nothing moved inside)
#   F4 surface_cache_dir_retired           F8 old_location_plants_ignored
# Arms labelled GUARD pass on 7c26b87 by design (bash-cd and task-context already exit without a
# state dir there, the CLI already ranks, the copies were already identical, and the F7 guards are new
# code with nothing to fail against before it) — each exists to stop a regression and is not evidence
# that the change landed. F1's GUARD runs prove the same input DOES surface with a healthy state dir.

DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2] got [$3]"; fi; }

R=$(mktemp -d "${TMPDIR:-/tmp}/aria-sdsf.XXXXXX") || exit 1
R=$(cd "$R" && pwd)
trap 'chmod -R u+rwx "$R" 2>/dev/null; rm -rf "$R"' EXIT
UIDN=$(id -u)
GOOD="$R/base"; SD="$GOOD/aria-knowledge-$UIDN"
BROKEN="$R/broken"
ST="$R/slashtmp"
mkdir -p "$GOOD" "$BROKEN" "$R/home/.claude" "$R/tmp" "$ST" "$R/ports" "$R/scd"
: > "$BROKEN/aria-knowledge-$UIDN"
mkdir -m 700 "$SD"
unset XDG_RUNTIME_DIR KT_HOOK_DEBUG_LOG CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH __CFBundleIdentifier
# KT_SURFACE_CACHE_DIR is set for the whole run (F4): a retired variable must steer nothing.
export HOME="$R/home" TMPDIR="$R/tmp" KT_TMP_SWEEP_ROOT="$ST" KT_SURFACE_CACHE_DIR="$R/scd"

for _pc in C:plugin-claude-code/scripts X:plugin-openai-codex/bin U:plugin-cursor-template/scripts/aria \
           G:plugin-antigravity/bin; do
  _t=${_pc%%:*}; _p=${_pc#*:}
  cp -R "$DIR/$_p" "$R/ports/$_t"
  for _f in "$R/ports/$_t"/*.sh; do
    sed "s|/tmp/|$ST/|g" "$_f" > "$_f.new" && mv "$_f.new" "$_f"
  done
done
PT="$R/ports"

# Fixtures: the shared surfacing index (a prompt below fires on proj-b + payments), and a project with a
# fresh CODEMAP (tracked artifact for bash-cd, task-context and session start).
KF="$R/kf"; P="$R/w/fxproj"
mkdir -p "$KF" "$P"
cp "$DIR/tests/repros/fixtures/surfacing/index.md" "$KF/index.md"
printf '# CODEMAP\n\n## Directory\n' > "$P/CODEMAP.md"
CFG="$R/cfg.md"
printf -- '---\nknowledge_folder: %s\nactive_knowledge_surfacing: true\nprojects_enabled: true\nprojects_list: proj-a:proj-a,proj-b:proj-b,proj-c:proj-c,fx:fxproj\n---\n' "$KF" > "$CFG"
export KT_CONFIG="$CFG"
Q="add the roof job to the proj-b payments tab"
DEP="projects/proj-b/deposits.md"
CMSG="Loaded CODEMAP directory for fx"   # lib-tracked-artifacts.sh's active-mode instruction
printf '%s\n' "$Q" > "$R/query.md"

# hrun SECS BASE HOOK [ENV=…] — runs HOOK under state base BASE from cwd $P with stdin $R/in, bounded;
# sets HOUT, HRC and HR=ok|hung. On a hang every FIFO under $R is opened read-write (never blocks),
# which releases a reader stuck on it, and the run is killed.
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
in_prompt() { printf '{"session_id":"%s","prompt":"%s"}' "$1" "$Q" > "$R/in"; }
in_cap()    { printf '{"conversation_id":"%s","generation_id":"%s","prompt":"%s","workspace_roots":["%s"]}' "$1" "$2" "$Q" "$P" > "$R/in"; }
in_inj()    { printf '{"conversation_id":"%s","generation_id":"%s"}' "$1" "$2" > "$R/in"; }
in_bashcd() { printf '{"command":"cd %s","session_id":"%s"}' "$P" "$1" > "$R/in"; }
in_task()   { printf '{"session_id":"%s","task_subject":"%s","task_description":"d"}' "$1" "$Q" > "$R/in"; }
in_ss()     { printf '{"session_id":"%s","source":"%s"}' "$1" "${2:-startup}" > "$R/in"; }
has() { case $1 in *"$2"*) echo 1 ;; *) echo 0 ;; esac; }
nonempty() { [ -n "$1" ] && echo 1 || echo 0; }
# surfacing names outside the state dir anywhere in the scratch tree (the old locations)
strays() {
  find "$R" -path "$SD" -prune -o \( -name 'aria-active-*' -o -name 'aria-surface-*.tsv' \
    -o -name 'aria-surface-hook.log' -o -name 'aria-prompt-config.*' -o -name 'aria-cursor-*' \) -print 2>/dev/null \
    | grep -v "^$R/ports/" | grep -v "^$R/old-plants/" | wc -l | tr -d ' '
}
inline() { [ -f "$1" ] && grep -qxF -- "$2" "$1" && echo 1 || echo 0; }
hook_bashcd=bash-cd-check.sh; hook_task=task-context-check.sh; hook_ss=session-start-check.sh

# --- F1 — no state directory: every hook surfaces nothing --------------------------------------------
in_prompt f1c; hrun 10 "$BROKEN" "$PT/C/prompt-context-check.sh"
check "F1 hooks_no_state_surface_nothing[C prompt]: ARIA ACTIVE|bounded" "0|ok" "$(has "$HOUT" 'ARIA ACTIVE —')|$HR"
in_cap f1u g1; hrun 10 "$BROKEN" "$PT/U/prompt-capture-check.sh"
check "F1 hooks_no_state_surface_nothing[U capture]: pending files stored" "0" \
  "$(find "$R" -name 'aria-cursor-pending-f1u*' 2>/dev/null | grep -v "^$R/ports/" | wc -l | tr -d ' ')"
for t in C X U G; do
  in_bashcd "f1b$t"; hrun 10 "$BROKEN" "$PT/$t/$hook_bashcd"
  check "F1 hooks_no_state_surface_nothing[$t bash-cd] (GUARD): output" "0" "$(nonempty "$HOUT")"
done
for t in C X U; do
  in_task "f1t$t"; hrun 10 "$BROKEN" "$PT/$t/$hook_task"
  check "F1 hooks_no_state_surface_nothing[$t task-context] (GUARD): output" "0" "$(nonempty "$HOUT")"
done
# Session start: C only. X's and U's session-start-check.sh never read stdin (INPUT is never
# assigned, so their tracked-artifacts block cannot fire — a pre-existing defect C fixed on
# 2026-10-25); their moved ledger line is covered by the F9 census instead.
in_ss f1sC; hrun 20 "$BROKEN" "$PT/C/$hook_ss"
check "F1 hooks_no_state_surface_nothing[C session-start]: tracked-artifact instruction" "0" "$(has "$HOUT" "$CMSG")"
check "F1 hooks_no_state_surface_nothing: surfacing names written outside the state dir" "0" "$(strays)"
check "F1 hooks_no_state_surface_nothing (GUARD): nothing created beside the broken state name" "0" \
  "$(find "$BROKEN" -type f ! -name "aria-knowledge-$UIDN" 2>/dev/null | wc -l | tr -d ' ')"
# GUARD: the same inputs DO surface with a healthy state dir (the input reaches the hook).
in_prompt f1gc; hrun 10 "$GOOD" "$PT/C/prompt-context-check.sh"
check "F1 positive control (GUARD) [C prompt]: ARIA ACTIVE with a healthy state dir" "1" "$(has "$HOUT" 'ARIA ACTIVE —')"
# A pending pair planted at the OLD locations ($TMPDIR, and KT_SURFACE_CACHE_DIR, which pre-2.58.0 code
# read first) is never delivered without a state dir. Moved away afterwards, so F1/F4 see no strays.
mkdir -p "$R/old-plants/tmp" "$R/old-plants/scd"
for _od in "$R/tmp" "$R/scd"; do
  printf 'ARIA ACTIVE — planted\n' > "$_od/aria-cursor-pending-f1i=g1.text"; printf '%s\n' "$DEP" > "$_od/aria-cursor-pending-f1i=g1.paths"
done
in_inj f1i g1; hrun 10 "$BROKEN" "$PT/U/prompt-context-inject.sh"
check "F1 hooks_no_state_surface_nothing[U inject]: an old-location pair is not delivered" "{}" "$HOUT"
for _od in tmp scd; do
  mv "$R/$_od/aria-cursor-pending-f1i=g1".* "$R/old-plants/$_od/" 2>/dev/null
done

# --- F2 — healthy state: the ledger is in the state dir and dedupes ------------------------------------
in_prompt f2c; hrun 10 "$GOOD" "$PT/C/prompt-context-check.sh"; o1=$HOUT
hrun 10 "$GOOD" "$PT/C/prompt-context-check.sh"; o2=$HOUT
check "F2 ledger_in_state_dir_dedupes[C prompt]: first|ledger lists $DEP|second" "1|1|0" \
  "$(has "$o1" "$KF/$DEP")|$(inline "$SD/aria-active-f2c" "$DEP")|$(has "$o2" 'ARIA ACTIVE —')"
in_cap f2u g1; hrun 10 "$GOOD" "$PT/U/prompt-capture-check.sh"
pend=$( [ -f "$SD/aria-cursor-pending-f2u=g1.text" ] && echo 1 || echo 0 )
in_inj f2u g1; hrun 10 "$GOOD" "$PT/U/prompt-context-inject.sh"; oi=$HOUT
in_cap f2u g2; hrun 10 "$GOOD" "$PT/U/prompt-capture-check.sh"
pend2=$( [ -e "$SD/aria-cursor-pending-f2u=g2.text" ] && echo 1 || echo 0 )
check "F2 ledger_in_state_dir_dedupes[U capture+inject]: pending in dir|delivered|ledger|next turn pends" "1|1|1|0" \
  "$pend|$(has "$oi" "$DEP")|$(inline "$SD/aria-active-f2u" "$DEP")|$pend2"
for t in C X U G; do
  in_bashcd "f2b$t"; hrun 10 "$GOOD" "$PT/$t/$hook_bashcd"
  check "F2 ledger_in_state_dir_dedupes[$t bash-cd]: output|ledger lists CODEMAP" "1|1" \
    "$(nonempty "$HOUT")|$(inline "$SD/aria-active-f2b$t" "$P/CODEMAP.md")"
done
for t in C X U; do
  in_task "f2t$t"; hrun 10 "$GOOD" "$PT/$t/$hook_task"
  check "F2 ledger_in_state_dir_dedupes[$t task-context]: output|ledger lists $DEP" "1|1" \
    "$(nonempty "$HOUT")|$(inline "$SD/aria-active-f2t$t" "$DEP")"
done
in_ss f2sC; hrun 20 "$GOOD" "$PT/C/$hook_ss"; s1=$(has "$HOUT" "$CMSG")
hrun 20 "$GOOD" "$PT/C/$hook_ss"; s2=$(has "$HOUT" "$CMSG")
check "F2 ledger_in_state_dir_dedupes[C session-start]: instruction|ledger lists CODEMAP|second start" "1|1|0" \
  "$s1|$(inline "$SD/aria-active-f2sC" "$P/CODEMAP.md")|$s2"
# After compaction the ledger is re-surfaced from the state dir (C SessionStart compact, X PostCompact).
printf 'projects/proj-z/compact-probe.md\n' > "$SD/aria-active-f2pc"
in_ss f2pc compact; hrun 20 "$GOOD" "$PT/C/$hook_ss"
check "F2 compact_reads_state_dir_ledger[C]" "1" "$(has "$HOUT" 'projects/proj-z/compact-probe.md')"
printf '{"session_id":"f2pc"}' > "$R/in"; hrun 10 "$GOOD" "$PT/X/post-compact-check.sh"
check "F2 compact_reads_state_dir_ledger[X]" "1" "$(has "$HOUT" 'projects/proj-z/compact-probe.md')"

# --- F3 — caches and the debug log live in the state dir only ------------------------------------------
NK=$(printf '%s' "$KF/index.md" | cksum | cut -d' ' -f1)
: > "$R/in"; hrun 10 "$GOOD" "$PT/C/prompt-context-check.sh"     # empty stdin is logged (stdin-empty)
check "F3 caches_in_state_dir: tsv|prompt-config cache|hook log line" "1|1|1" \
  "$( [ -f "$SD/aria-surface-$NK.tsv" ] && echo 1 || echo 0)|$(ls "$SD"/aria-prompt-config.*.cache >/dev/null 2>&1 && echo 1 || echo 0)|$(grep -q 'claude-code input stdin-empty' "$SD/aria-surface-hook.log" 2>/dev/null && echo 1 || echo 0)"
check "F3 caches_in_state_dir: surfacing names outside the state dir" "0" "$(strays)"

# --- F5 — the CLI ranks without a state dir, and only caches inside one --------------------------------
KF2="$R/kf2"; mkdir -p "$KF2"; cp "$KF/index.md" "$KF2/index.md"
CFG2="$R/cfg2.md"
printf -- '---\nknowledge_folder: %s\nprojects_enabled: true\nprojects_list: proj-a:proj-a,proj-b:proj-b,proj-c:proj-c\n---\n' "$KF2" > "$CFG2"
NK2=$(printf '%s' "$KF2/index.md" | cksum | cut -d' ' -f1)
: > "$R/in"
for t in C X U G; do
  (cd "$P" && env KT_STATE_BASE="$BROKEN" KT_CONFIG="$CFG2" sh "$PT/$t/aria-surface.sh" --file "$R/query.md" > "$R/cli-b" 2>/dev/null); rb=$?
  nb=$(find "$R" -name "aria-surface-$NK2.tsv" 2>/dev/null | wc -l | tr -d ' ')
  (cd "$P" && env KT_STATE_BASE="$GOOD" KT_CONFIG="$CFG2" sh "$PT/$t/aria-surface.sh" --file "$R/query.md" > "$R/cli-g" 2>/dev/null)
  check "F5 cli_ranks_without_state[$t] (GUARD): exit 0|fired|same ranking" "0|1|1" \
    "$rb|$(grep -c '^tags: ' "$R/cli-b" | tr -d ' ')|$(cmp -s "$R/cli-b" "$R/cli-g" && echo 1 || echo 0)"
  check "F5b cli_cache_only_in_state_dir[$t]: no-state cache files|healthy cache in dir|elsewhere" "0|1|0" \
    "$nb|$( [ -f "$SD/aria-surface-$NK2.tsv" ] && echo 1 || echo 0)|$(find "$R" -path "$SD" -prune -o -name "aria-surface-$NK2.tsv" -print 2>/dev/null | wc -l | tr -d ' ')"
  rm -f "$SD/aria-surface-$NK2.tsv"
done

# --- F6 — library parity ------------------------------------------------------------------------------
for n in lib-prompt-surface.sh lib-index-match.sh lib-tracked-artifacts.sh aria-surface.sh; do
  sums=""; cnt=0
  for p in plugin-claude-code/scripts plugin-openai-codex/bin plugin-cursor-template/scripts/aria plugin-antigravity/bin; do
    [ -f "$DIR/$p/$n" ] || continue
    cnt=$((cnt + 1)); sums="$sums$(cksum < "$DIR/$p/$n" | cut -d' ' -f1)
"
  done
  want=4; [ "$n" = lib-prompt-surface.sh ] && want=3
  check "F6 lib_parity[$n] (GUARD): copies|distinct cksums" "$want|1" "$cnt|$(printf '%s' "$sums" | sort -u | grep -c .)"
done

# --- F7 — a non-file at a state name is no state: bounded, nothing moved inside ------------------------
PK=$(printf '%s' "$CFG" | cksum | cut -d' ' -f1)
rm -f "$SD/aria-prompt-config.$PK.cache" "$SD/aria-surface-$NK.tsv"
mkdir "$SD/aria-prompt-config.$PK.cache" "$SD/aria-surface-$NK.tsv"
in_prompt f7d; hrun 10 "$GOOD" "$PT/C/prompt-context-check.sh"
check "F7 nonfile_at_state_name (GUARD) [dir at both cache names]: surfaced|bounded|dirs still empty" "1|ok|0" \
  "$(has "$HOUT" "$KF/$DEP")|$HR|$(find "$SD/aria-prompt-config.$PK.cache" "$SD/aria-surface-$NK.tsv" -mindepth 1 | wc -l | tr -d ' ')"
rmdir "$SD/aria-prompt-config.$PK.cache" "$SD/aria-surface-$NK.tsv"
mkfifo "$SD/aria-prompt-config.$PK.cache" "$SD/aria-surface-$NK.tsv" "$SD/aria-active-f7f"
in_prompt f7f; hrun 5 "$GOOD" "$PT/C/prompt-context-check.sh"
check "F7 nonfile_at_state_name (GUARD) [FIFO at caches + ledger]: surfaced|bounded" "1|ok" "$(has "$HOUT" "$KF/$DEP")|$HR"
rm -f "$SD/aria-surface-hook.log"; mkfifo "$SD/aria-surface-hook.log"
: > "$R/in"; hrun 5 "$GOOD" "$PT/C/prompt-context-check.sh"
check "F7 nonfile_at_state_name (GUARD) [FIFO at the debug log]: bounded" "ok" "$HR"
rm -f "$SD/aria-prompt-config.$PK.cache" "$SD/aria-surface-$NK.tsv" "$SD/aria-active-f7f" "$SD/aria-surface-hook.log"
rm -f "$SD/aria-cursor-version.last"; mkdir "$SD/aria-cursor-version.last"
in_cap f7u g1; hrun 10 "$GOOD" "$PT/U/prompt-capture-check.sh"
check "F7 nonfile_at_state_name [U dir at version name]: pair stored in dir|bounded|dir still empty" "1|ok|0" \
  "$( [ -f "$SD/aria-cursor-pending-f7u=g1.text" ] && echo 1 || echo 0)|$HR|$(ls -A "$SD/aria-cursor-version.last" | grep -c .)"
rmdir "$SD/aria-cursor-version.last"

# --- F8 — a ledger planted at an old location never suppresses surfacing --------------------------------
printf '%s\n' "$DEP" > "$ST/aria-active-f8"; printf '%s\n' "$DEP" > "$R/tmp/aria-active-f8"
in_prompt f8; hrun 10 "$GOOD" "$PT/C/prompt-context-check.sh"
check "F8 old_location_plants_ignored[C prompt]: $DEP still surfaced" "1" "$(has "$HOUT" "$KF/$DEP")"
mv "$ST/aria-active-f8" "$R/old-plants/st-aria-active-f8"; mv "$R/tmp/aria-active-f8" "$R/old-plants/tmp-aria-active-f8"

# --- F9 — census: no shipped shell script names a surfacing state file at an old location -------------
# Code lines only (full-line comments exempt), every shell script of the four ports plus Antigravity's
# hand-authored hook. Forms: a literal /tmp/aria-active-, and KT_SURFACE_CACHE_DIR in any use. (The
# legacy /tmp sweeps match 'aria-active-*' under a variable root and are not this form.)
f9_scan() {
  for _f in "$@"; do
    awk -v f="$_f" '/^[[:space:]]*#/ { next } /\/tmp\/aria-active-|KT_SURFACE_CACHE_DIR/ { print f ":" NR }' "$_f"
  done
}
F9_FILES=$(ls "$DIR"/plugin-claude-code/scripts/*.sh "$DIR"/plugin-openai-codex/bin/*.sh \
  "$DIR"/plugin-cursor-template/scripts/aria/*.sh "$DIR"/plugin-antigravity/bin/*.sh \
  "$DIR"/plugin-antigravity/bin/antigravity/*.sh 2>/dev/null)
f9_n=$(printf '%s\n' "$F9_FILES" | grep -c .)
f9_hits=$(f9_scan $F9_FILES)
printf '# comment /tmp/aria-active-x\nLEDGER="/tmp/aria-active-$S"\nx=${KT_SURFACE_CACHE_DIR:-y}\n' > "$R/f9-control.sh"
check "F9 no_old_location_names: files examined > 50|control reports exactly 2" "1|2" \
  "$( [ "$f9_n" -gt 50 ] && echo 1 || echo 0)|$(f9_scan "$R/f9-control.sh" | grep -c .)"
check "F9 no_old_location_names: shipped hits" "" "$f9_hits"

# --- F4 — KT_SURFACE_CACHE_DIR (set for the whole run) received nothing ---------------------------------
check "F4 surface_cache_dir_retired: entries written to KT_SURFACE_CACHE_DIR" "0" "$(ls -A "$R/scd" | grep -c .)"
check "F4 surface_cache_dir_retired: surfacing names anywhere outside the state dir" "0" "$(strays)"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
