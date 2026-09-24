#!/bin/sh
# r22-carrier-side-channel.sh — v2.54.0: record the Rule 22 carrier at its own
# PreToolUse, and keep the transcript as a fallback that waits for the response.
#
# Why: Claude Code writes a response to the transcript ALL AT ONCE when the model
# finishes streaming it, while each tool call's PreToolUse hook runs during
# streaming (measured 2026-09-24: 5 calls created +0.00..+2.93 s all reached disk
# at +3.06 s). An edit's hook therefore cannot read the marker above it until the
# model finishes the response. The carrier (a Bash call whose input has a
# line-start `[Rule 22]` marker) is now recorded by pre-bash-r22-carrier.sh the
# moment it runs, and pre-edit-check.sh consumes that record — one carrier, one
# edit (ADR 062), same session + agent + prompt_id. Visible-text markers still
# count through the transcript, which now waits up to 40 s (Bash-less subagents
# such as doc-updater have no other channel).
#
# Hook stdin field names follow code.claude.com/docs/en/hooks verbatim
# (session_id, prompt_id, transcript_path, tool_name, tool_input, tool_use_id,
# agent_id). They are NOT captured from a live hook — AC9 checks the real shape.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BIN="$REPO_ROOT/plugin-claude-code/bin"
HOOK="$BIN/pre-edit-check.sh"
REC="$BIN/pre-bash-r22-carrier.sh"
MANIFEST="$REPO_ROOT/plugin-claude-code/.claude-plugin/plugin.json"
BASE="$REPO_ROOT/tests/fixtures/transcript-cc21280-real-base.jsonl"
TARGET="toolu_fx_3"

export TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
W="$TMPDIR/work"; mkdir -p "$W"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }

# --- fixtures ----------------------------------------------------------------
# plain: real 2.1.280 bytes, no marker anywhere, target line present.
cp "$BASE" "$W/plain.jsonl"
# absent: same, target line missing (never flushed).
head -n $(($(wc -l < "$BASE") - 1)) "$BASE" > "$W/absent.jsonl"
# text: the thinking line before the target replaced by a visible-text marker; target
# line held back so a background writer can append it late.
python3 - "$BASE" "$W/text.jsonl" "$W/text.last" <<'PY'
import json, sys
L = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
i = max(n for n, e in enumerate(L) if e.get("type") == "assistant"
        and any(b.get("id") == "toolu_fx_3" for b in e["message"]["content"]))
L[i-1]["message"]["content"] = [{"type": "text", "text": "[Rule 22] Low Impact — probe / Change — x / Solutions — y / Execute — z"}]
open(sys.argv[2], "w").write("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in L[:i]))
open(sys.argv[3], "w").write(json.dumps(L[i], ensure_ascii=False) + "\n")
PY

# --- stdin builders (python, so every value is escaped correctly) --------------
bash_in() {  # bash_in <sid> <prompt_id|-> <agent_id|-> <command>
  python3 -c '
import json, sys
d = {"session_id": sys.argv[1], "transcript_path": "/tmp/t.jsonl", "cwd": "/tmp",
     "hook_event_name": "PreToolUse", "tool_name": "Bash",
     "tool_input": {"command": sys.argv[4], "description": "probe"}, "tool_use_id": "toolu_bash_x"}
if sys.argv[2] != "-": d["prompt_id"] = sys.argv[2]
if sys.argv[3] != "-": d["agent_id"] = sys.argv[3]; d["agent_type"] = "probe"
print(json.dumps(d, separators=(",", ":")))  # compact, as the live harness sends it' "$@"
}
edit_in() {  # edit_in <sid> <prompt_id|-> <agent_id|-> <transcript>
  python3 -c '
import json, sys
d = {"session_id": sys.argv[1], "transcript_path": sys.argv[4], "cwd": "/tmp",
     "hook_event_name": "PreToolUse", "tool_name": "Write",
     "tool_input": {"file_path": "/tmp/test.txt", "content": "x"}, "tool_use_id": "toolu_fx_3"}
if sys.argv[2] != "-": d["prompt_id"] = sys.argv[2]
if sys.argv[3] != "-": d["agent_id"] = sys.argv[3]; d["agent_type"] = "probe"
print(json.dumps(d, separators=(",", ":")))  # compact, as the live harness sends it' "$@"
}
# `|| true`: under `set -e` a missing or crashing recorder would otherwise ABORT the
# suite at the first call, hiding every case. It must surface as red cases instead.
record() { bash_in "$@" | sh "$REC" >/dev/null 2>&1 || true; }
verdict() {  # verdict <edit stdin> -> allow|deny|unknown|degraded
  out=$(printf '%s' "$1" | sh "$HOOK" 2>&1)
  if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then echo deny
  elif printf '%s' "$out" | grep -q 'could not verify'; then echo unknown
  elif printf '%s' "$out" | grep -q 'DEGRADED'; then echo degraded
  else echo allow; fi
}
state() { echo "$TMPDIR/aria-r22-carrier-$1"; }
CARRIER="cat <<'R22'
[Rule 22] Low Impact — probe change (test only)
R22"
export ARIA_R22_FLUSH_WAIT_MS=300   # consumer cases below never depend on the wait

# --- recorder -------------------------------------------------------------------
record S7 P7 - "$CARRIER"
if [ -f "$(state S7)" ] && grep -q '"P7"' "$(state S7)"; then ok "C1-carrier-recorded-with-prompt-id"; else bad "C1-carrier-recorded-with-prompt-id" "no state file or wrong prompt_id"; fi
record S8 P8 - "grep -n '[Rule 22] Low Impact' notes.md"
[ ! -e "$(state S8)" ] && ok "C2-mid-line-mention-not-recorded" || bad "C2-mid-line-mention-not-recorded" "state written"
record S9 P9 - "ls /tmp"
[ ! -e "$(state S9)" ] && ok "C3-no-marker-not-recorded" || bad "C3-no-marker-not-recorded" "state written"
record S10 P10 "a-b/c" "$CARRIER"
if [ -f "$(state S10).agent-a-bc" ] && [ ! -e "$(state S10)" ]; then ok "C4-agent-scoped-key"; else bad "C4-agent-scoped-key" "expected $(basename "$(state S10)").agent-a-bc only; have: $(ls "$TMPDIR" | grep S10 | tr '\n' ' ')"; fi
# `set +e` inside: bash in POSIX mode inherits errexit into $(...), which would kill
# the substitution before `echo rc=$?` can report the recorder's exit code.
o1=$(set +e; printf 'not json at all [Rule 22' | sh "$REC" 2>&1; echo "rc=$?")
o2=$(set +e; bash_in S11 P11 - "$CARRIER" | sh "$REC" 2>&1; echo "rc=$?")
if [ "$o1" = "rc=0" ] && [ "$o2" = "rc=0" ]; then ok "C11-recorder-silent-exit0"; else bad "C11-recorder-silent-exit0" "o1=[$o1] o2=[$o2]"; fi

# --- consumer -------------------------------------------------------------------
record S1 P1 - "$CARRIER"
t0=$(now_ms); v=$(ARIA_R22_FLUSH_WAIT_MS=5000 verdict "$(edit_in S1 P1 - "$W/absent.jsonl")"); el=$(( $(now_ms) - t0 ))
if [ "$v" = "allow" ] && [ "$el" -lt 2000 ]; then ok "C5-carrier-allows-without-transcript ($el ms)"; else bad "C5-carrier-allows-without-transcript" "got $v in $el ms (want allow < 2000 ms with the target line absent)"; fi
v=$(verdict "$(edit_in S1 P1 - "$W/plain.jsonl")")
[ "$v" = "deny" ] && ok "C6-one-carrier-one-edit" || bad "C6-one-carrier-one-edit" "second edit got $v"
record S2 P1 - "$CARRIER"
v=$(verdict "$(edit_in S2 P2 - "$W/plain.jsonl")")
if [ "$v" = "deny" ] && [ ! -e "$(state S2)" ]; then ok "C7-other-prompt-discarded"; else bad "C7-other-prompt-discarded" "got $v, state $( [ -e "$(state S2)" ] && echo kept || echo removed)"; fi
record S3 P1 AGX "$CARRIER"
v=$(verdict "$(edit_in S3 P1 - "$W/plain.jsonl")")
if [ "$v" = "deny" ] && [ -f "$(state S3).agent-AGX" ]; then ok "C8-subagent-carrier-not-parents"; else bad "C8-subagent-carrier-not-parents" "got $v, agent state $( [ -f "$(state S3).agent-AGX" ] && echo kept || echo gone)"; fi
# C8b is the other direction and guards the CONSUMER's key (C8 guards the recorder's):
# a carrier recorded on the main thread must not authorise an edit inside a subagent.
record S13 P1 - "$CARRIER"
v=$(verdict "$(edit_in S13 P1 AGY "$W/plain.jsonl")")
if [ "$v" = "deny" ] && [ -f "$(state S13)" ]; then ok "C8b-parent-carrier-not-subagents"; else bad "C8b-parent-carrier-not-subagents" "got $v, parent state $( [ -f "$(state S13)" ] && echo kept || echo gone)"; fi
record S4 P1 - "$CARRIER"
v=$(verdict "$(edit_in S5 P1 - "$W/plain.jsonl")")
if [ "$v" = "deny" ] && [ -f "$(state S4)" ]; then ok "C9-session-isolation"; else bad "C9-session-isolation" "got $v"; fi
record S6 P1 - "$CARRIER"
v=$(verdict "$(edit_in S6 - - "$W/plain.jsonl")")
if [ "$v" = "deny" ] && [ ! -e "$(state S6)" ]; then ok "C10-no-prompt-id-fails-closed"; else bad "C10-no-prompt-id-fails-closed" "got $v, state $( [ -e "$(state S6)" ] && echo kept || echo removed)"; fi

# --- fallback wait (env UNSET: the shipped default must outlast a streaming response)
cp "$W/text.jsonl" "$W/late.jsonl"
( sleep 2.5; cat "$W/text.last" >> "$W/late.jsonl" ) &
v=$(env -u ARIA_R22_FLUSH_WAIT_MS sh -c 'printf "%s" "$1" | sh "$2" 2>&1' _ "$(edit_in S12 P12 - "$W/late.jsonl")" "$HOOK")
wait
if printf '%s' "$v" | grep -q -E 'deny|could not verify|DEGRADED'; then bad "W1-text-marker-found-after-late-write" "output: $v"; else ok "W1-text-marker-found-after-late-write"; fi

# --- registration (structural) -------------------------------------------------
r1=$(python3 -c '
import json,sys
h=json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]
print(any(m.get("matcher")=="Bash" and any("pre-bash-r22-carrier.sh" in x.get("command","") for x in m["hooks"]) for m in h))' "$MANIFEST")
[ "$r1" = "True" ] && ok "R1-recorder-registered-on-Bash" || bad "R1-recorder-registered-on-Bash" "not in PreToolUse Bash hooks"
r2=$(python3 -c '
import json,sys
h=json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]
print([x.get("timeout") for m in h for x in m["hooks"] if "pre-edit-check.sh" in x.get("command","")])' "$MANIFEST")
[ "$r2" = "[45]" ] && ok "R2-pre-edit-timeout-45" || bad "R2-pre-edit-timeout-45" "timeouts=$r2"
cap=$(grep -o 'ARIA_R22_FLUSH_WAIT_MS", "[0-9]*"' "$HOOK" | grep -o '[0-9]*"$' | tr -d '"')
if [ -n "$cap" ] && [ "$cap" -ge 30000 ] && [ "$cap" -lt 45000 ]; then ok "R3-default-cap-under-timeout ($cap ms)"; else bad "R3-default-cap-under-timeout" "cap=[$cap]"; fi

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
