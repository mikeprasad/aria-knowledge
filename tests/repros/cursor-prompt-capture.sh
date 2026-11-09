#!/bin/sh
# cursor-prompt-capture.sh — tests for the Cursor capture hooks (spec D3, plan Task 3).
#
# beforeSubmitPrompt → scripts/aria/prompt-capture-check.sh ranks the prompt in code and
# stores a pending pair (injection text + the relative paths it names) for this
# conversation_id + generation_id. postToolUse → scripts/aria/prompt-context-inject.sh
# emits it once as {"additional_context": …}, then records the paths in the session
# ledger. Nothing the model composes reaches a shell.
#
# Pending pair: $KT_SURFACE_CACHE_DIR/aria-cursor-pending-<conv>=<gen>.text / .paths
# (`=` cannot occur in a sanitised id, so the conversation part is unambiguous).
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
# The ledger path is fixed by contract (/tmp/aria-active-<id>), so every id carries RUN_ID.
RUN_ID="cpc$$x$(od -An -N4 -tx4 /dev/urandom 2>/dev/null | tr -d ' ')"
trap 'rm -rf "$SCRATCH"; rm -f /tmp/aria-active-"$RUN_ID"* 2>/dev/null' EXIT
mkdir -p "$SCRATCH/tmp" "$SCRATCH/home" "$SCRATCH/cache"
TMPDIR="$SCRATCH/tmp"; export TMPDIR
CACHE="$SCRATCH/cache"
KT_SURFACE_CACHE_DIR="$CACHE"; export KT_SURFACE_CACHE_DIR
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
ledger() { printf '/tmp/aria-active-%s' "$1"; }
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
cap "$C" gnew "$P_PAY"
s_stale=$( [ -e "$(pend "${RUN_ID}Q" gq).text" ] || [ -e "$(pend "${RUN_ID}Q" gq).paths" ] && echo kept || echo gone )
s_fresh=$( [ -e "$(pend "${RUN_ID}F" gf).text" ] && [ -e "$(pend "${RUN_ID}F" gf).paths" ] && echo kept || echo gone )
s_same=$( [ -e "$(pend "$C" gold).text" ] || [ -e "$(pend "$C" gold).paths" ] && echo kept || echo gone )
s_unrel=$( [ -e "$CACHE/unrelated-old.txt" ] && echo kept || echo gone )
s_new=$( [ -e "$(pend "$C" gnew).text" ] && echo present || echo absent )
if [ -n "$old" ] && [ "$s_stale" = gone ] && [ "$s_fresh" = kept ] && [ "$s_same" = gone ] \
   && [ "$s_unrel" = kept ] && [ "$s_new" = present ]; then
  ok "stale_pending_pruned"
else
  bad "stale_pending_pruned" "stale-other=$s_stale fresh-other=$s_fresh same-conv-older=$s_same unrelated=$s_unrel new=$s_new"
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

# --- conversation_id_sanitised -------------------------------------------------------
cap "${RUN_ID}x/../y" "g/../1" "$P_PAY"
inj "${RUN_ID}x/../y" "g/../1"; c=$(ctx)
if [ -n "$c" ] && [ -f "$(ledger "${RUN_ID}x..y")" ] && [ ! -e "$CACHE/y" ] \
   && [ ! -e "/tmp/aria-active-${RUN_ID}x" ] && [ ! -e "$(pend "${RUN_ID}x" g)" ]; then
  ok "conversation_id_sanitised"
else
  bad "conversation_id_sanitised" "ctx=$( [ -n "$c" ] && echo y || echo n) ledger x..y=$( [ -f "$(ledger "${RUN_ID}x..y")" ] && echo y || echo n)"
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
EXPECTED=10
if [ $((PASS + FAIL)) -eq "$EXPECTED" ]; then ok "every_arm_reported"; else bad "every_arm_reported" "$((PASS + FAIL)) of $EXPECTED"; fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
