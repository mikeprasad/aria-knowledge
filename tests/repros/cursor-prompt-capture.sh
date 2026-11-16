#!/bin/sh
# cursor-prompt-capture.sh — tests for the Cursor capture hooks (spec D3, plan Task 3).
#
# beforeSubmitPrompt → scripts/aria/prompt-capture-check.sh ranks the prompt in code and
# stores a pending pair (injection text + the relative paths it names) for this
# conversation_id + generation_id. postToolUse → scripts/aria/prompt-context-inject.sh
# emits it once as {"additional_context": …}, then records the paths in the session
# ledger. Nothing the model composes reaches a shell.
#
# Pending pair: <state dir>/aria-cursor-pending-<conv>=<gen>.text / .paths (the private state dir,
# lib-state-key.sh; here under a scratch KT_STATE_BASE)
# (`=` cannot occur in an accepted id, so the conversation part is unambiguous).
#
# Run under sh or bash only. CURSOR_CAPTURE / CURSOR_INJECT override the hook paths
# (used for mutation checks).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TPL="$REPO_ROOT/plugin-cursor-template"
CAP="${CURSOR_CAPTURE:-$TPL/scripts/aria/prompt-capture-check.sh}"
INJ="${CURSOR_INJECT:-$TPL/scripts/aria/prompt-context-inject.sh}"
FIX="$SCRIPT_DIR/fixtures/surfacing"

PASS=0
FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/aria-cursor-capture-test.XXXXXX") || exit 1
RUN_ID="cpc$$x$(od -An -N4 -tx4 /dev/urandom 2>/dev/null | tr -d ' ')"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/tmp" "$SCRATCH/home" "$SCRATCH/sb"
TMPDIR="$SCRATCH/tmp"; export TMPDIR
unset XDG_RUNTIME_DIR
# Every name these hooks keep lives in the private state dir (2.58.0). CACHE is that dir, made
# here (mode 700, as the resolver requires) so an arm can plant in it before a hook runs.
KT_STATE_BASE="$SCRATCH/sb"; export KT_STATE_BASE
CACHE="$KT_STATE_BASE/aria-knowledge-$(id -u)"; mkdir -m 700 "$CACHE"
HOOKLOG="$CACHE/aria-surface-hook.log"

# --- knowledge folder: the fixture index + files whose bodies carry a sentinel ---
KF="$SCRATCH/kf"; mkdir -p "$KF"
cp "$FIX/index.md" "$KF/index.md"
for p in projects/proj-a/hooks.md references/webhook-basics.md projects/proj-b/deposits.md \
         projects/proj-b/crew-notes.md projects/proj-b/estimates.md; do
  mkdir -p "$KF/${p%/*}"; printf 'BODY-SENTINEL-%s\n' "$p" > "$KF/$p"
done

# --- scratch Cursor workspace: a git repo holding .cursor/aria-knowledge.local.md ---
REPO="$SCRATCH/repo"; mkdir -p "$REPO/.cursor"
(cd "$REPO" && git init -q .) >/dev/null 2>&1
cat > "$REPO/.cursor/aria-knowledge.local.md" <<CFG
---
knowledge_folder: $KF
active_knowledge_surfacing: true
projects_enabled: true
projects_list: proj-a:proj-a,proj-b:proj-b,proj-c:proj-c
---
CFG

P_PAY="how do we handle payments for proj-b deposits"
P_HOOK="webhooks retry for proj-a hooks"

pend() { printf '%s/aria-cursor-pending-%s=%s' "$CACHE" "$1" "$2"; }
ledger() { printf '%s/aria-active-%s' "$CACHE" "$1"; }
payload() { # CONV GEN PROMPT [VERSION]
  jq -cn --arg c "$1" --arg g "$2" --arg p "$3" --arg v "${4:-1.7.2}" \
    '{conversation_id:$c, generation_id:$g, prompt:$p, cursor_version:$v,
      hook_event_name:"beforeSubmitPrompt", attachments:[]}'
}
# hook SCRIPT — runs a hook the way Cursor does (bash, cwd = workspace root), stdin from
# $SCRATCH/in, stdout → $SCRATCH/out, exit code → hook_rc. KT_CONFIG/KT_ROOT cleared so
# the hook must derive them itself.
hook() {
  (cd "$REPO" && HOME="$SCRATCH/home" KT_CONFIG= KT_ROOT= bash "$1" < "$SCRATCH/in" > "$SCRATCH/out" 2>/dev/null)
  hook_rc=$?
}
cap()  { payload "$@" > "$SCRATCH/in"; hook "$CAP"; }
inj()  { jq -cn --arg c "$1" --arg g "$2" \
           '{conversation_id:$c, generation_id:$g, hook_event_name:"postToolUse", tool_name:"Read",
             tool_input:{}, tool_output:"{}", tool_use_id:"t1", cwd:"/x", duration:1}' > "$SCRATCH/in"
         hook "$INJ"; }
out()  { cat "$SCRATCH/out" 2>/dev/null; }
ctx()  { jq -r '.additional_context // empty' "$SCRATCH/out" 2>/dev/null; }
CONT='{"continue":true}'

# --- capture_always_continues ---------------------------------------------------
r=""
for kind in valid malformed empty object array closed; do
  case $kind in
    valid)     payload "${RUN_ID}A" g1 "$P_PAY" > "$SCRATCH/in" ;;
    malformed) printf 'not json {' > "$SCRATCH/in" ;;
    empty)     : > "$SCRATCH/in" ;;
    object)    printf '{}' > "$SCRATCH/in" ;;
    array)     printf '[1,2]' > "$SCRATCH/in" ;;
  esac
  if [ "$kind" = closed ]; then
    (cd "$REPO" && HOME="$SCRATCH/home" KT_CONFIG= KT_ROOT= bash "$CAP" <&- > "$SCRATCH/out" 2>/dev/null); hook_rc=$?
  else
    hook "$CAP"
  fi
  [ "$(out)" = "$CONT" ] && [ "$hook_rc" -eq 0 ] || r="$r $kind(rc=$hook_rc out='$(out)')"
done
if [ -z "$r" ]; then ok "capture_always_continues"; else bad "capture_always_continues" "$r"; fi

# --- capture_does_not_touch_ledger ----------------------------------------------
C="${RUN_ID}L"
cap "$C" g1 "$P_PAY"
a1=$( [ -e "$(ledger "$C")" ] && echo present || echo absent )
printf 'references/seed.md\n' > "$(ledger "$C")"; seed=$(cksum < "$(ledger "$C")")
cap "$C" g2 "$P_PAY"
a2=$(cksum < "$(ledger "$C")")
if [ "$a1" = absent ] && [ "$a2" = "$seed" ] && [ -f "$(pend "$C" g2).text" ]; then
  ok "capture_does_not_touch_ledger"
else
  bad "capture_does_not_touch_ledger" "no-ledger case: $a1; seeded unchanged: $( [ "$a2" = "$seed" ] && echo yes || echo no ); pending g2: $( [ -f "$(pend "$C" g2).text" ] && echo yes || echo no )"
fi

# --- inject_once_per_generation -------------------------------------------------
C="${RUN_ID}G"
cap "$C" g1 "$P_PAY"; inj "$C" g1; c1=$(ctx)
inj "$C" g1; o1b=$(out)
cap "$C" g2 "$P_HOOK"; inj "$C" g2; c2=$(ctx)
# Two prompts before any tool call: the newer generation's pending wins, the older one
# is gone (that generation can no longer receive a postToolUse).
D="${RUN_ID}H"
cap "$D" g3 "$P_PAY"; cap "$D" g4 "$P_HOOK"
inj "$D" g3; o3=$(out)
inj "$D" g4; c4=$(ctx)
case "$c1" in "ARIA ACTIVE — "*"$KF/projects/proj-b/deposits.md"*) e1=1 ;; *) e1=0 ;; esac
case "$c2" in "ARIA ACTIVE — "*"$KF/projects/proj-a/hooks.md"*) e2=1 ;; *) e2=0 ;; esac
case "$c4" in "ARIA ACTIVE — "*"$KF/projects/proj-a/hooks.md"*) e4=1 ;; *) e4=0 ;; esac
if [ "$e1" = 1 ] && [ "$o1b" = "{}" ] && [ "$e2" = 1 ] && [ "$c1" != "$c2" ] \
   && [ "$o3" = "{}" ] && [ "$e4" = 1 ] && [ ! -e "$(pend "$C" g1).text" ] && [ ! -e "$(pend "$C" g2).text" ]; then
  ok "inject_once_per_generation"
else
  bad "inject_once_per_generation" "g1=$e1 g1-again='$o1b' g2=$e2 distinct=$( [ "$c1" != "$c2" ] && echo y || echo n) older-g3='$o3' newer-g4=$e4"
fi

# --- inject_paths_only ------------------------------------------------------------
C="${RUN_ID}P"
cap "$C" g1 "$P_PAY"; inj "$C" g1; c=$(ctx)
keys=$(jq -c 'keys' "$SCRATCH/out" 2>/dev/null)
nonpath=$(printf '%s\n' "$c" | sed 1d | grep -vc '^- /')
case "$c" in *BODY-SENTINEL*|*" — "*"Deposit handling"*) leak=1 ;; *) leak=0 ;; esac
if [ "$keys" = '["additional_context"]' ] && [ -n "$c" ] && [ "${#c}" -lt 10000 ] \
   && [ "$nonpath" -eq 0 ] && [ "$leak" -eq 0 ]; then
  ok "inject_paths_only"
else
  bad "inject_paths_only" "keys=$keys len=${#c} non-path lines=$nonpath body/description leak=$leak"
fi

# --- inject_commits_only_delivered -------------------------------------------------
# Emission fails two ways a host can produce: stdout closed, and a reader that has gone
# away (broken pipe — made deterministic: the reader closes its end and signals before
# the hook starts). Each must leave the ledger untouched and the pending text in place
# (no orphaned claim), so the next tool call can still deliver it.
C="${RUN_ID}D"
cap "$C" g1 "$P_PAY"
jq -cn --arg c "$C" '{conversation_id:$c, generation_id:"g1", hook_event_name:"postToolUse"}' > "$SCRATCH/in"
(cd "$REPO" && HOME="$SCRATCH/home" KT_CONFIG= KT_ROOT= bash "$INJ" < "$SCRATCH/in" >&- 2>/dev/null)
l1=$( [ -e "$(ledger "$C")" ] && echo present || echo absent )
p1=$( [ -f "$(pend "$C" g1).text" ] && echo kept || echo gone )
rm -f "$SCRATCH/closed"
{ while [ ! -e "$SCRATCH/closed" ]; do sleep 0.05; done
  cd "$REPO" && HOME="$SCRATCH/home" KT_CONFIG= KT_ROOT= bash "$INJ" < "$SCRATCH/in" 2>/dev/null; } \
  | { exec 0<&-; : > "$SCRATCH/closed"; sleep 1; }
l2=$( [ -e "$(ledger "$C")" ] && echo present || echo absent )
p2=$( [ -f "$(pend "$C" g1).text" ] && echo kept || echo gone )
orphans=$(ls "$CACHE" | grep -c '\.claim\.')
# A capture with stdout closed: whatever it stores holds no hook JSON (a failed stdout
# write must not be flushed into the pending file).
payload "$C" gx "$P_PAY" > "$SCRATCH/in"
(cd "$REPO" && HOME="$SCRATCH/home" KT_CONFIG= KT_ROOT= bash "$CAP" < "$SCRATCH/in" >&- 2>/dev/null)
p3=$( grep -c "continue" "$(pend "$C" gx).text" 2>/dev/null || true )
p3s=$( [ -e "$(pend "$C" gx).text" ] && echo y || echo n )
leak=$(grep -c '{"' "$HOOKLOG" 2>/dev/null)
cap "$C" g1 "$P_PAY"; inj "$C" g1; c=$(ctx)
want=$(printf '%s\n' "$c" | sed -n "s|^- $KF/||p" | tr '\n' '|')
got=$( { tr "\n" "|" < "$(ledger "$C")"; } 2>/dev/null)
if [ "$l1" = absent ] && [ "$p1" = kept ] && [ "$l2" = absent ] && [ "$p2" = kept ] \
   && [ "$orphans" -eq 0 ] && [ "${p3:-0}" -eq 0 ] && [ "$p3s" = y ] && [ "${leak:-0}" -eq 0 ] \
   && [ -n "$want" ] && [ "$got" = "$want" ]; then
  ok "inject_commits_only_delivered"
else
  bad "inject_commits_only_delivered" "closed stdout: ledger $l1, pending $p1; broken pipe: ledger $l2, pending $p2, orphan claims $orphans; closed-stdout capture: continue-bytes ${p3:-0} stored=$p3s; hook JSON in debug log: ${leak:-0}; after delivery ledger='$got' want='$want'"
fi

# --- stale_pending_pruned ------------------------------------------------------------
old=$(date -v-2d +%Y%m%d%H%M 2>/dev/null || date -d '2 days ago' +%Y%m%d%H%M 2>/dev/null)
C="${RUN_ID}S"
for f in "$(pend "${RUN_ID}Q" gq).text" "$(pend "${RUN_ID}Q" gq).paths" \
         "$(pend "${RUN_ID}F" gf).text" "$(pend "${RUN_ID}F" gf).paths" \
         "$(pend "$C" gold).text" "$(pend "$C" gold).paths" "$CACHE/unrelated-old.txt"; do
  printf 'x\n' > "$f"
done
touch -t "$old" "$(pend "${RUN_ID}Q" gq).text" "$(pend "${RUN_ID}Q" gq).paths" "$CACHE/unrelated-old.txt"
# The 24 h prune runs at most once an hour; earlier arms already ran it, so make it due
# (the stamp's mtime is when the next prune may run).
STAMP="$CACHE/aria-cursor-prune.stamp"
[ -e "$STAMP" ] && touch -t "$old" "$STAMP"
cap "$C" gnew "$P_PAY"
s_stale=$( [ -e "$(pend "${RUN_ID}Q" gq).text" ] || [ -e "$(pend "${RUN_ID}Q" gq).paths" ] && echo kept || echo gone )
s_fresh=$( [ -e "$(pend "${RUN_ID}F" gf).text" ] && [ -e "$(pend "${RUN_ID}F" gf).paths" ] && echo kept || echo gone )
s_same=$( [ -e "$(pend "$C" gold).text" ] || [ -e "$(pend "$C" gold).paths" ] && echo kept || echo gone )
s_unrel=$( [ -e "$CACHE/unrelated-old.txt" ] && echo kept || echo gone )
s_new=$( [ -e "$(pend "$C" gnew).text" ] && echo present || echo absent )
# Throttle: a second fired capture inside the hour does not prune; once due, it does.
printf 'x\n' > "$(pend "${RUN_ID}R" gr).text"; touch -t "$old" "$(pend "${RUN_ID}R" gr).text"
cap "${RUN_ID}T" g1 "$P_PAY"
s_thr=$( [ -e "$(pend "${RUN_ID}R" gr).text" ] && echo kept || echo gone )
touch -t "$old" "$STAMP" 2>/dev/null
cap "${RUN_ID}T" g2 "$P_PAY"
s_due=$( [ -e "$(pend "${RUN_ID}R" gr).text" ] && echo kept || echo gone )
if [ -n "$old" ] && [ "$s_stale" = gone ] && [ "$s_fresh" = kept ] && [ "$s_same" = gone ] \
   && [ "$s_unrel" = kept ] && [ "$s_new" = present ] && [ "$s_thr" = kept ] && [ "$s_due" = gone ]; then
  ok "stale_pending_pruned"
else
  bad "stale_pending_pruned" "stale-other=$s_stale fresh-other=$s_fresh same-conv-older=$s_same unrelated=$s_unrel new=$s_new within-hour=$s_thr once-due=$s_due"
fi

# --- cursor_version_logged -----------------------------------------------------------
n0=$( { wc -l < "$HOOKLOG"; } 2>/dev/null || echo 0)
cap "${RUN_ID}V" g1 "$P_PAY" "9.9.9-test"
n1=$( { wc -l < "$HOOKLOG"; } 2>/dev/null || echo 0)
# A hostile version string is reduced to one plain token on one log line.
cap "${RUN_ID}V" g2 "$P_PAY" "$(printf '1.0;$(touch %s/vmark)\nINJECTED' "$SCRATCH")"
n2=$( { wc -l < "$HOOKLOG"; } 2>/dev/null || echo 0)
if grep -q ' cursor capture cursor_version=9\.9\.9-test$' "$HOOKLOG" 2>/dev/null \
   && [ $((n1 - n0)) -eq 1 ] && [ $((n2 - n1)) -eq 1 ] && ! grep -q '^INJECTED' "$HOOKLOG" \
   && [ ! -e "$SCRATCH/vmark" ]; then
  ok "cursor_version_logged"
else
  bad "cursor_version_logged" "lines +$((n1 - n0)) then +$((n2 - n1)); log tail: $(tail -2 "$HOOKLOG" 2>/dev/null | tr '\n' '|')"
fi

# --- conversation_id_rejected (2.58.0) ------------------------------------------------
# An id outside [A-Za-z0-9._-]+ names NOTHING (kt_session_key, lib-state-key.sh): no context, and no
# file under the raw, stripped or path-split form. It used to be stripped to x..y, which is not
# injective (two conversations could share one ledger).
cap "${RUN_ID}x/../y" "g1" "$P_PAY"
inj "${RUN_ID}x/../y" "g1"; c=$(ctx)
named=$(ls "$CACHE" 2>/dev/null | grep -c "${RUN_ID}x")
if [ -z "$c" ] && [ "$named" = 0 ] && [ ! -e "$CACHE/y" ] \
   && grep -q 'conversation-id-rejected' "$HOOKLOG" 2>/dev/null; then
  ok "conversation_id_rejected"
else
  bad "conversation_id_rejected" "ctx=$( [ -n "$c" ] && echo y || echo n) files naming the id=$named y=$( [ -e "$CACHE/y" ] && echo y || echo n) logged=$(grep -c 'conversation-id-rejected' "$HOOKLOG" 2>/dev/null)"
fi

# --- capture_silent_without_jq --------------------------------------------------------
FARM="$SCRATCH/farm"; mkdir -p "$FARM"
for d in /usr/bin /bin /usr/sbin /sbin; do
  for b in "$d"/*; do
    n=${b##*/}
    [ "$n" = jq ] && continue
    [ -e "$FARM/$n" ] || ln -s "$b" "$FARM/$n" 2>/dev/null
  done
done
C="${RUN_ID}J"
payload "$C" g1 "$P_PAY" > "$SCRATCH/in"
n0=$(grep -c 'jq-missing' "$HOOKLOG" 2>/dev/null)
(cd "$REPO" && PATH="$FARM" HOME="$SCRATCH/home" KT_CONFIG= KT_ROOT= bash "$CAP" < "$SCRATCH/in" > "$SCRATCH/out" 2>/dev/null); hook_rc=$?
n1=$(grep -c 'jq-missing' "$HOOKLOG" 2>/dev/null)
if [ "$(out)" = "$CONT" ] && [ "$hook_rc" -eq 0 ] && [ $((n1 - n0)) -eq 1 ] \
   && [ ! -e "$(pend "$C" g1).text" ] && ! (PATH="$FARM"; command -v jq >/dev/null 2>&1); then
  ok "capture_silent_without_jq"
else
  bad "capture_silent_without_jq" "rc=$hook_rc out='$(out)' jq-missing lines +$((n1 - n0)) pending=$( [ -e "$(pend "$C" g1).text" ] && echo y || echo n)"
fi

# --- root_from_workspace_roots -----------------------------------------------------------
# The repo root comes from workspace_roots[0] when it names a directory holding .cursor/;
# git is only the fallback. With no git on PATH and a cwd outside any repo, a valid root
# still captures. A root without .cursor/ must be rejected and fall back to git: with git
# on PATH and cwd in the repo it still captures (an unchecked root would find no config).
GFARM="$SCRATCH/gfarm"; mkdir -p "$GFARM"
for d in /usr/bin /bin /usr/sbin /sbin; do
  for b in "$d"/*; do
    n=${b##*/}
    [ "$n" = git ] && continue
    [ -e "$GFARM/$n" ] || ln -s "$b" "$GFARM/$n" 2>/dev/null
  done
done
NOCUR="$SCRATCH/nocursor"; mkdir -p "$NOCUR"
wr_cap() { # CONV GEN ROOT MODE(nogit|git)
  jq -cn --arg c "$1" --arg g "$2" --arg p "$P_PAY" --arg r "$3" \
    '{conversation_id:$c, generation_id:$g, prompt:$p, cursor_version:"1.7.2", workspace_roots:[$r]}' > "$SCRATCH/in"
  if [ "$4" = nogit ]; then
    (cd "$SCRATCH/tmp" && PATH="$GFARM" HOME="$SCRATCH/home" KT_CONFIG= KT_ROOT= bash "$CAP" < "$SCRATCH/in" > "$SCRATCH/out" 2>/dev/null)
  else
    (cd "$REPO" && HOME="$SCRATCH/home" KT_CONFIG= KT_ROOT= bash "$CAP" < "$SCRATCH/in" > "$SCRATCH/out" 2>/dev/null)
  fi
}
wr_cap "${RUN_ID}W" g1 "$REPO" nogit
w1=$( [ -e "$(pend "${RUN_ID}W" g1).text" ] && echo stored || echo none ); w1o=$(out)
wr_cap "${RUN_ID}W" g2 "$NOCUR" git
w2=$( [ -e "$(pend "${RUN_ID}W" g2).text" ] && echo stored || echo none )
if [ "$w1" = stored ] && [ "$w1o" = "$CONT" ] && [ "$w2" = stored ] \
   && ! (PATH="$GFARM"; command -v git >/dev/null 2>&1); then
  ok "root_from_workspace_roots"
else
  bad "root_from_workspace_roots" "valid root: $w1 (out '$w1o'); root without .cursor/ (git fallback): $w2"
fi

# --- version_logged_once -------------------------------------------------------------------
cap "${RUN_ID}O" g1 "$P_PAY" "8.8.8-once"
cap "${RUN_ID}O" g2 "$P_PAY" "8.8.8-once"
vo=$(grep -c 'cursor_version=8\.8\.8-once$' "$HOOKLOG" 2>/dev/null)
if [ "${vo:-0}" -eq 1 ]; then ok "version_logged_once"; else bad "version_logged_once" "logged ${vo:-0} times"; fi

# --- capture_missing_index_silent (D6) ------------------------------------------------------
# A config whose knowledge folder has no index: the prompt still continues, the debug log
# says no-index, and no pair is stored.
REPO2="$SCRATCH/repo2"; mkdir -p "$REPO2/.cursor" "$SCRATCH/kf-noindex"
printf -- '---\nknowledge_folder: %s\nactive_knowledge_surfacing: true\n---\n' "$SCRATCH/kf-noindex" \
  > "$REPO2/.cursor/aria-knowledge.local.md"
n0=$(grep -c ' cursor surface no-index$' "$HOOKLOG" 2>/dev/null)
jq -cn --arg c "${RUN_ID}N" --arg p "$P_PAY" --arg r "$REPO2" \
  '{conversation_id:$c, generation_id:"g1", prompt:$p, cursor_version:"1.7.2", workspace_roots:[$r]}' > "$SCRATCH/in"
hook "$CAP"
n1=$(grep -c ' cursor surface no-index$' "$HOOKLOG" 2>/dev/null)
if [ "$(out)" = "$CONT" ] && [ $((n1 - n0)) -eq 1 ] && [ ! -e "$(pend "${RUN_ID}N" g1).text" ] \
   && [ ! -e "$(pend "${RUN_ID}N" g1).paths" ]; then
  ok "capture_missing_index_silent"
else
  bad "capture_missing_index_silent" "out='$(out)' no-index lines +$((n1 - n0)) pair=$( [ -e "$(pend "${RUN_ID}N" g1).text" ] && echo y || echo n)"
fi

# --- inject_failures_keep_pair (D6) ---------------------------------------------------------
# A pending pair exists; postToolUse input that cannot be read (malformed, empty, no jq)
# must print {}, record nothing, and leave the pair for the next tool call.
C="${RUN_ID}K"
cap "$C" g1 "$P_PAY"
r=""
for kind in malformed empty nojq; do
  case $kind in
    malformed) printf 'not json {' > "$SCRATCH/in" ;;
    empty)     : > "$SCRATCH/in" ;;
    nojq)      jq -cn --arg c "$C" '{conversation_id:$c, generation_id:"g1"}' > "$SCRATCH/in" ;;
  esac
  if [ "$kind" = nojq ]; then
    (cd "$REPO" && PATH="$FARM" HOME="$SCRATCH/home" KT_CONFIG= KT_ROOT= bash "$INJ" < "$SCRATCH/in" > "$SCRATCH/out" 2>/dev/null)
  else
    hook "$INJ"
  fi
  [ "$(out)" = "{}" ] && [ ! -e "$(ledger "$C")" ] && [ -f "$(pend "$C" g1).text" ] \
    && [ -f "$(pend "$C" g1).paths" ] || r="$r $kind(out='$(out)' ledger=$( [ -e "$(ledger "$C")" ] && echo y || echo n) pair=$( [ -f "$(pend "$C" g1).text" ] && echo y || echo n))"
done
if [ -z "$r" ]; then ok "inject_failures_keep_pair"; else bad "inject_failures_keep_pair" "$r"; fi

# --- newer_capture_spares_inflight_claim (m1) -----------------------------------------------
# An inject for g1 that has claimed its text (renamed to .claim.<pid>) is still delivering;
# a capture for g2 in the same conversation must not delete the claim under it.
C="${RUN_ID}M"
printf 'in flight\n' > "$(pend "$C" g1).text.claim.4242"
cap "$C" g2 "$P_PAY"
if [ -f "$(pend "$C" g1).text.claim.4242" ] && [ -f "$(pend "$C" g2).text" ]; then
  ok "newer_capture_spares_inflight_claim"
else
  bad "newer_capture_spares_inflight_claim" "claim=$( [ -f "$(pend "$C" g1).text.claim.4242" ] && echo kept || echo gone) new pair=$( [ -f "$(pend "$C" g2).text" ] && echo y || echo n)"
fi

# --- claim_restored_only_with_paths (m1) ----------------------------------------------------
# A failed emit puts the claim back only if its .paths still exists (a newer capture may have
# replaced the pair); otherwise the claim is deleted, never restored as a text with no paths.
C="${RUN_ID}Z"
cap "$C" g1 "$P_PAY"; rm -f "$(pend "$C" g1).paths"
jq -cn --arg c "$C" '{conversation_id:$c, generation_id:"g1"}' > "$SCRATCH/in"
(cd "$REPO" && HOME="$SCRATCH/home" KT_CONFIG= KT_ROOT= bash "$INJ" < "$SCRATCH/in" >&- 2>/dev/null)
zt=$( [ -e "$(pend "$C" g1).text" ] && echo restored || echo none )
zc=$(ls "$CACHE" | grep -c "^aria-cursor-pending-${C}=g1\.text\.claim\.")
if [ "$zt" = none ] && [ "$zc" -eq 0 ] && [ ! -e "$(ledger "$C")" ]; then
  ok "claim_restored_only_with_paths"
else
  bad "claim_restored_only_with_paths" "text=$zt claims left=$zc ledger=$( [ -e "$(ledger "$C")" ] && echo y || echo n)"
fi

# --- capture_lib_missing_logged (m2) --------------------------------------------------------
# Only lib-prompt-surface.sh is missing; the inline log line goes through the shared safe create
# in lib-tracked-artifacts.sh (spec §5), and the log is named in the state dir through
# lib-state-key.sh (2.58.0), so both libs sit beside the hook as they do on install.
NOLIB="$SCRATCH/nolib"; mkdir -p "$NOLIB"; cp "$CAP" "$NOLIB/prompt-capture-check.sh"
cp "$(dirname "$CAP")/lib-tracked-artifacts.sh" "$(dirname "$CAP")/lib-state-key.sh" "$NOLIB/"
payload "${RUN_ID}B" g1 "$P_PAY" > "$SCRATCH/in"
n0=$(grep -c ' cursor capture lib-missing$' "$HOOKLOG" 2>/dev/null)
hook "$NOLIB/prompt-capture-check.sh"
n1=$(grep -c ' cursor capture lib-missing$' "$HOOKLOG" 2>/dev/null)
if [ "$(out)" = "$CONT" ] && [ $((n1 - n0)) -eq 1 ]; then
  ok "capture_lib_missing_logged"
else
  bad "capture_lib_missing_logged" "out='$(out)' lib-missing lines +$((n1 - n0))"
fi
# --- capture_no_libs_writes_nothing ---------------------------------------------------------
# Neither lib: no safe create is available, so nothing is written (fail safe) and the hook's
# output is unchanged.
NOLIB2="$SCRATCH/nolib2"; mkdir -p "$NOLIB2"; cp "$CAP" "$NOLIB2/prompt-capture-check.sh"
n0=$(grep -c ' cursor capture lib-missing$' "$HOOKLOG" 2>/dev/null)
hook "$NOLIB2/prompt-capture-check.sh"
n1=$(grep -c ' cursor capture lib-missing$' "$HOOKLOG" 2>/dev/null)
if [ "$(out)" = "$CONT" ] && [ $((n1 - n0)) -eq 0 ]; then
  ok "capture_no_libs_writes_nothing"
else
  bad "capture_no_libs_writes_nothing" "out='$(out)' lib-missing lines +$((n1 - n0))"
fi

# --- prune_removes_orphan_tmp (m3) ----------------------------------------------------------
# A capture killed between mktemp and mv leaves .aria-cursor-pending.XXXXXX; the 24 h prune
# removes those too (a fresh one is left alone: it may be a write in progress).
printf 'x\n' > "$CACHE/.aria-cursor-pending.OLDxyz"; touch -t "$old" "$CACHE/.aria-cursor-pending.OLDxyz"
printf 'x\n' > "$CACHE/.aria-cursor-pending.NEWxyz"
touch -t "$old" "$STAMP" 2>/dev/null
cap "${RUN_ID}P2" g1 "$P_PAY"
po=$( [ -e "$CACHE/.aria-cursor-pending.OLDxyz" ] && echo kept || echo gone )
pn=$( [ -e "$CACHE/.aria-cursor-pending.NEWxyz" ] && echo kept || echo gone )
if [ "$po" = gone ] && [ "$pn" = kept ]; then
  ok "prune_removes_orphan_tmp"
else
  bad "prune_removes_orphan_tmp" "old orphan=$po fresh=$pn"
fi

# --- hooks_json_registered -------------------------------------------------------------
HJ="$TPL/.cursor/hooks.json"
b=$(jq -r '[.hooks.beforeSubmitPrompt[]?.command] | index("bash scripts/aria/prompt-capture-check.sh") != null' "$HJ" 2>/dev/null)
p=$(jq -r '[.hooks.postToolUse[]?.command] | index("bash scripts/aria/prompt-context-inject.sh") != null' "$HJ" 2>/dev/null)
if [ "$b" = true ] && [ "$p" = true ] && [ -f "$TPL/scripts/aria/prompt-capture-check.sh" ] \
   && [ -f "$TPL/scripts/aria/prompt-context-inject.sh" ]; then
  ok "hooks_json_registered"
else
  bad "hooks_json_registered" "beforeSubmitPrompt=$b postToolUse=$p"
fi

# --- every arm reported ------------------------------------------------------------------
EXPECTED=19
if [ $((PASS + FAIL)) -eq "$EXPECTED" ]; then ok "every_arm_reported"; else bad "every_arm_reported" "$((PASS + FAIL)) of $EXPECTED"; fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
