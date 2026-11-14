#!/bin/sh
# state-dir-missing-lib.sh — 2.58.0 Task 7 fix round 1: a missing lib-state-key.sh is "no state" (spec
# D3), never a crash and never a fail-open. Sourcing a missing file aborts sh with exit 1 even under
# `2>/dev/null || true` (measured on macOS /bin/sh), and `[ -f lib ] || exit 0` in front of a deny
# skips the deny. So every hook sources the lib only `if [ -f … ]`, and with it absent its kt_* calls
# fail and the caller takes its existing no-state path.
#
# Each port's scripts are copied to a scratch dir WITHOUT lib-state-key.sh and run for real:
#   L1 [C]   pre-edit, no [Rule 22] marker → still DENIES (valid JSON, exit 0); with a marker → allows
#            (so the deny is the gate, not a broken hook); lib-present control denies the same input
#   L2 [H]   Antigravity's pre-edit wrapper decides exactly as it does WITH the lib, marker or not.
#            (⚠ That decision is "allow" either way: the wrapper maps the canonical's exit code, and the
#            canonical denies with JSON + exit 0. Pre-existing, reported; on b8e1679 the missing lib made
#            it deny everything by accident, because `. missing` exits 1.)
#   L3 [U]   Cursor pre-edit (advisory) prints the same Rule 22 reminder as with the lib
#   L4       post-edit (C, U), record-edit-intent and capture-task-boundary (U): exit 0, output valid
#   L5       session-start (C, U, X): exit 0, valid JSON, state_dir=none ledger=none; C names the reason
#   L6       aria-state.sh path (C U X G): exit 1, stderr exactly "aria-state: lib-state-key.sh missing"
#   L7       preflight (C U X) at preflight_gate: deny still DENIES an unmarked code commit
#   L8       no "command not found" (or any "lib-state-key") text on any missing-lib run's stderr
#   L9       no stray file: nothing named aria-* in the working dir, no /aria-*, the state base untouched
# Red on b8e1679: L1 (exit 1, no JSON), L2 (marker case: deny vs allow), L4–L7 (abort), L8, part of L5.

DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2] got [$3]"; fi; }
has() { case $1 in *"$2"*) echo 1 ;; *) echo 0 ;; esac; }

command -v jq >/dev/null 2>&1 || { echo "SKIP  state-dir-missing-lib: jq is required"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP  state-dir-missing-lib: git is required"; exit 0; }

R=$(mktemp -d "${TMPDIR:-/tmp}/aria-nolib.XXXXXX") || exit 1
R=$(cd "$R" && pwd)
trap 'chmod -R u+rwx "$R" 2>/dev/null; rm -rf "$R"' EXIT
chmod -N "$R" 2>/dev/null || :
if command -v setfacl >/dev/null 2>&1; then setfacl -b "$R" 2>/dev/null || :; fi
UIDN=$(id -u)
NB="$R/nolib-base"; LB="$R/lib-base"; CWD="$R/cwd"; ERRS="$R/errs"
mkdir -p "$NB" "$LB" "$CWD" "$ERRS" "$R/home/.claude" "$R/home/.gemini/antigravity" "$R/tmp" "$R/sweep" "$R/w"
: > "$R/home/.gemini/antigravity/.aria-probe-fired"   # skip Antigravity's one-shot first-run probe
unset XDG_RUNTIME_DIR KT_HOOK_DEBUG_LOG ARIA_HOOK_DEBUG_LOG CLAUDE_CODE_SESSION_ID CODEX_THREAD_ID \
  CLAUDE_SESSION_ID CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH __CFBundleIdentifier KT_SURFACE_CACHE_DIR
export HOME="$R/home" TMPDIR="$R/tmp" KT_TMP_SWEEP_ROOT="$R/sweep" KT_EDIT_INTENT_FILE="$R/intent.json"
export ARIA_R22_FLUSH_WAIT_MS=300
KF="$R/kf"; mkdir -p "$KF/logs"
printf -- '- **Date:** 2026-11-01 — audit\n' > "$KF/logs/knowledge-audit-log.md"
printf -- '- **Date:** 2026-11-01 — audit\n' > "$KF/logs/config-audit-log.md"
CFG="$R/cfg.md"
# session_state: true so post-edit reaches its session-state block, where it sources the lib.
printf -- '---\nknowledge_folder: %s\npreflight_gate: deny\nsession_state: true\n---\n' "$KF" > "$CFG"
export KT_CONFIG="$CFG"

# The copies. C = claude-code scripts, U = cursor scripts/aria, X = codex bin, G = the Antigravity
# plugin root (the wrapper finds bin/ through CLAUDE_PLUGIN_ROOT).
cp -R "$DIR/plugin-claude-code/scripts" "$R/c"; rm -f "$R/c/lib-state-key.sh"
cp -R "$DIR/plugin-cursor-template/scripts/aria" "$R/u"; rm -f "$R/u/lib-state-key.sh"
cp -R "$DIR/plugin-openai-codex/bin" "$R/x"; rm -f "$R/x/lib-state-key.sh"
cp -R "$DIR/plugin-antigravity" "$R/g"; rm -f "$R/g/bin/lib-state-key.sh"
C="$DIR/plugin-claude-code/scripts"

# nolib NAME CMD... — a missing-lib run: stdin $R/in, cwd $CWD, state base $NB; stdout $R/out, rc $R/rc,
# stderr kept per run for L8.
nolib() { _n=$1; shift; (cd "$CWD" && KT_STATE_BASE="$NB" "$@" < "$R/in" > "$R/out" 2>"$ERRS/$_n"); echo $? > "$R/rc"; }
withlib() { (cd "$CWD" && KT_STATE_BASE="$LB" "$@" < "$R/in" > "$R/lout" 2>/dev/null); }
json_ok() { [ ! -s "$1" ] && echo 1 && return; jq -e . "$1" >/dev/null 2>&1 && echo 1 || echo 0; }
denies() { grep -q '"permissionDecision":"deny"' "$1" && echo 1 || echo 0; }

# --- L1 [C] pre-edit ------------------------------------------------------------------------------------
BASE_T="$DIR/tests/fixtures/transcript-cc21280-real-base.jsonl"
BASE="$BASE_T" OUT="$R/marker.jsonl" python3 - <<'PY'
import json, os
out = []
for l in open(os.environ["BASE"]):
    if not l.strip(): continue
    e = json.loads(l)
    if e.get("type") == "assistant":
        for b in e["message"]["content"]:
            if b.get("type") == "tool_use" and b["id"] == "toolu_fx_2":
                b["input"]["command"] = "cat <<'R22'\n[Rule 22] Low Impact — missing-lib probe\nR22"
    out.append(json.dumps(e, ensure_ascii=False))
open(os.environ["OUT"], "w").write("\n".join(out) + "\n")
PY
pe_in() { printf '{"session_id":"nl1","file_path":"%s/w/t.txt","transcript_path":"%s","tool_use_id":"toolu_fx_3"}' "$R" "$1" > "$R/in"; }
pe_in "$BASE_T"; withlib sh "$C/pre-edit-check.sh"; _ctl=$(denies "$R/lout")
pe_in "$BASE_T"; nolib pe-c sh "$R/c/pre-edit-check.sh"
check "L1 [C] pre-edit, no marker: lib control denies | no lib: denies, exit 0, valid JSON" "1|1|0|1" \
  "$_ctl|$(denies "$R/out")|$(cat "$R/rc")|$(json_ok "$R/out")"
pe_in "$R/marker.jsonl"; nolib pe-c-marker sh "$R/c/pre-edit-check.sh"
check "L1 [C] pre-edit, carrier marker, no lib: allowed (the deny above is the gate, not a broken hook)" "0|0" \
  "$(denies "$R/out")|$(cat "$R/rc")"

# --- L2 [H] Antigravity pre-edit wrapper ---------------------------------------------------------------
printf '%s\n' '{"type":"USER_INPUT","content":"edit the file","source":"USER_EXPLICIT","status":"DONE","step_index":1}' \
  '{"type":"PLANNER_RESPONSE","content":"I will edit it.","source":"MODEL","status":"DONE","step_index":2,"tool_calls":[{"name":"write_to_file"}]}' > "$R/ag.jsonl"
printf '%s\n' '{"type":"USER_INPUT","content":"edit the file","source":"USER_EXPLICIT","status":"DONE","step_index":1}' \
  '{"type":"PLANNER_RESPONSE","content":"[Rule 22] Low Impact — probe","source":"MODEL","status":"DONE","step_index":2,"tool_calls":[{"name":"write_to_file"}]}' > "$R/ag-marker.jsonl"
for t in ag ag-marker; do
  jq -cn --arg t "$R/$t.jsonl" --arg f "$R/w/f.txt" '{conversationId:"nl2",workspacePaths:["/x"],transcriptPath:$t,
    artifactDirectoryPath:"/x/art",stepIdx:2,toolCall:{name:"write_to_file",args:{TargetFile:$f,CodeContent:"x"}}}' > "$R/in"
  withlib env CLAUDE_PLUGIN_ROOT="$DIR/plugin-antigravity" bash "$DIR/plugin-antigravity/bin/antigravity/pre-edit-aria.sh"
  _ld=$(jq -r '.decision // empty' "$R/lout" 2>/dev/null)
  nolib "pe-h-$t" env CLAUDE_PLUGIN_ROOT="$R/g" bash "$R/g/bin/antigravity/pre-edit-aria.sh"
  check "L2 [H] pre-edit wrapper ($t): no lib decides as with the lib | exit 0 | valid JSON" "$_ld|0|1" \
    "$(jq -r '.decision // empty' "$R/out" 2>/dev/null)|$(cat "$R/rc")|$(json_ok "$R/out")"
done

# --- L3 [U] Cursor pre-edit (advisory) -----------------------------------------------------------------
printf '{"conversation_id":"nl3","file_path":"%s/w/f.txt"}' "$R" > "$R/in"
withlib sh "$DIR/plugin-cursor-template/scripts/aria/pre-edit-check.sh"
nolib pe-u sh "$R/u/pre-edit-check.sh"
check "L3 [U] pre-edit reminder: exit 0 | same output as with the lib | carries the Rule 22 reminder" "0|1|1" \
  "$(cat "$R/rc")|$(cmp -s "$R/out" "$R/lout" && echo 1 || echo 0)|$(has "$(cat "$R/out")" 'Rule 22 reminder')"

# --- L4 post-edit and the other Cursor hooks ------------------------------------------------------------
mkdir -p "$R/w/proj"; : > "$R/w/proj/CLAUDE.md"; : > "$R/w/proj/f.txt"
printf '{"session_id":"nl4","tool_name":"Edit","tool_input":{"file_path":"%s/w/proj/f.txt"},"transcript_path":"%s"}' "$R" "$BASE_T" > "$R/in"
nolib post-c sh "$R/c/post-edit-check.sh"
check "L4 [C] post-edit: exit 0 | valid JSON | the project is still marked in progress (D3: mark anyway)" "0|1|1" \
  "$(cat "$R/rc")|$(json_ok "$R/out")|$(grep -q '^lastEvent: in-progress' "$R/w/proj/SESSION.md" 2>/dev/null && echo 1 || echo 0)"
printf '{"conversation_id":"nl4u","file_path":"%s/w/proj/f.txt"}' "$R" > "$R/in"
nolib post-u sh "$R/u/post-edit-check.sh"
check "L4 [U] post-edit: exit 0 | valid JSON" "0|1" "$(cat "$R/rc")|$(json_ok "$R/out")"
printf '{"conversation_id":"nl4u"}' > "$R/in"
nolib intent-u sh "$R/u/record-edit-intent.sh" "$R/w/proj/f.txt" rule22-low
check "L4 [U] record-edit-intent: exit 0" "0" "$(cat "$R/rc")"
printf '{"conversation_id":"nl4u","status":"completed"}' > "$R/in"
nolib stop-u sh "$R/u/capture-task-boundary.sh"
check "L4 [U] capture-task-boundary: exit 0 | valid JSON" "0|1" "$(cat "$R/rc")|$(json_ok "$R/out")"

# --- L5 session-start -----------------------------------------------------------------------------------
printf '{"session_id":"nl5","source":"startup"}' > "$R/in"
nolib ss-c sh "$R/c/session-start-check.sh"
_ctx=$(jq -r '.hookSpecificOutput.additionalContext // empty' "$R/out" 2>/dev/null)
_sys=$(jq -r '.systemMessage // empty' "$R/out" 2>/dev/null)
check "L5 [C] session-start: exit 0 | valid JSON | state_dir=none ledger=none | the human is told why" "0|1|1|1" \
  "$(cat "$R/rc")|$(json_ok "$R/out")|$(has "$_ctx" 'state_dir=none ledger=none.')|$(has "$_sys" 'state directory unavailable (lib-state-key.sh missing)')"
printf '{"session_id":"nl5x","source":"startup"}' > "$R/in"
nolib ss-x sh "$R/x/session-start-check.sh"
check "L5 [X] session-start: exit 0 | state_dir=none ledger=none" "0|1" "$(cat "$R/rc")|$(has "$(cat "$R/out")" 'state_dir=none ledger=none.')"
printf '{"conversation_id":"nl5u","hook_event_name":"sessionStart"}' > "$R/in"
nolib ss-u sh "$R/u/session-start-check.sh"
check "L5 [U] session-start: exit 0 | state_dir=none ledger=none" "0|1" "$(cat "$R/rc")|$(has "$(cat "$R/out")" 'state_dir=none ledger=none.')"

# --- L6 aria-state.sh ------------------------------------------------------------------------------------
: > "$R/in"
for p in c u x g; do
  case $p in g) _cli="$R/g/bin/aria-state.sh" ;; *) _cli="$R/$p/aria-state.sh" ;; esac
  nolib "cli-$p" sh "$_cli" path aria-x
  check "L6 [$p] aria-state.sh path, no lib: exit 1 | the one-line message | nothing on stdout" \
    "1|aria-state: lib-state-key.sh missing|0" "$(cat "$R/rc")|$(cat "$ERRS/cli-$p")|$(wc -c < "$R/out" | tr -d ' ')"
  : > "$ERRS/cli-$p"   # its stderr is the expected message, not noise for L8
done
(cd "$CWD" && KT_STATE_BASE="$LB" sh "$C/aria-state.sh" path aria-x > "$R/lout" 2>/dev/null); _lrc=$?
check "L6 control: with the lib, aria-state.sh path prints the state path" "0|$LB/aria-knowledge-$UIDN/aria-x" "$_lrc|$(cat "$R/lout")"

# --- L7 preflight at preflight_gate: deny -----------------------------------------------------------------
CODE="$R/code"; mkdir -p "$CODE"; git -C "$CODE" init -q . 2>/dev/null
git -C "$CODE" config user.email t@t.t; git -C "$CODE" config user.name t
echo code > "$CODE/app.py"; git -C "$CODE" add . 2>/dev/null
for p in c u x; do
  case $p in u) _sk=conversation_id ;; *) _sk=session_id ;; esac
  printf '{"%s":"nl7%s","tool_input":{"command":"cd %s && git commit -m x"}}' "$_sk" "$p" "$CODE" > "$R/in"
  nolib "pf-$p" sh "$R/$p/pre-commit-preflight-check.sh"
  check "L7 [$p] preflight, no lib, unmarked code commit at gate=deny: still answered with deny | exit 0" "1|0" \
    "$(has "$(cat "$R/out")" '"deny"')|$(cat "$R/rc")"
done

# --- L8 / L9 -------------------------------------------------------------------------------------------
# Scoped to the state library's own names. (Cursor's session-start also prints
# `kt_resolve_account: command not found` — Cursor's config.sh has no such function, with or without
# this lib; pre-existing, reported, not this arm's subject.)
_noise=$(grep -l -E 'kt_(state_[a-z]+|session_key[a-z_]*|agent_suffix)|lib-state-key' "$ERRS"/* 2>/dev/null | sed 's|.*/||' | tr '\n' ' ')
check "L8 no state-library 'command not found' (or lib-state-key) text on any missing-lib run's stderr" "" "$_noise"
check "L9 no stray file: nothing named aria-* in the working dir | no /aria-* | the state base untouched" "0|0|0" \
  "$(find "$CWD" -name 'aria-*' 2>/dev/null | grep -c .)|$(ls -d /aria-* 2>/dev/null | grep -c .)|$(ls -A "$NB" | grep -c .)"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
