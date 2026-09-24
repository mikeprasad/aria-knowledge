#!/bin/sh
# r22-subagent-transcript.sh — v2.54.1: inside a subagent, read the subagent's OWN
# transcript, and key the deny-rate breaker per agent.
#
# Why (measured live 2026-09-24, CC 2.1.280): a subagent's hook receives the PARENT
# session's transcript_path, which never contains the subagent's calls — those are
# only in <dir>/<session_id>/subagents/agent-<agent_id>.jsonl, written per response.
# So every subagent edit without a recorded carrier waited the full cap and failed
# open (41,171 ms for a doc-updater Write). Subagents also share the parent's
# session_id, so their denials counted toward the PARENT's breaker.
#
# Fixture: real subagent bytes from that session, scrubbed (tests/fixtures/
# subagent-cc21280-real.jsonl): user prompt, thinking, Write, visible-text marker,
# tool_result. Parent file: the main-thread base fixture, which lacks the target.
#
# Old code, declared before running: S1 RED (fails open: "could not verify") ·
# S2 RED (fails open instead of denying) · S3 green · S5 green · S6a RED (the parent
# inherits the subagent's three denials and degrades).
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/plugin-claude-code/bin/pre-edit-check.sh"
BASE="$REPO_ROOT/tests/fixtures/transcript-cc21280-real-base.jsonl"
SUBFX="$REPO_ROOT/tests/fixtures/subagent-cc21280-real.jsonl"
SUBT="toolu_sub_1"

export TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

SID="sub-sess-1"
TX="$TMPDIR/tx"; mkdir -p "$TX/$SID/subagents"
PARENT="$TX/$SID.jsonl"
cp "$BASE" "$PARENT"                                   # main thread; no $SUBT in it
cp "$SUBFX" "$TX/$SID/subagents/agent-a1f.jsonl"       # subagent a1f, marker present
# nomark: the same subagent bytes with the visible-text marker turned into thinking.
python3 - "$SUBFX" "$TMPDIR/nomark.jsonl" <<'PY'
import json, sys
out = []
for l in open(sys.argv[1]):
    e = json.loads(l)
    c = (e.get("message") or {}).get("content")
    if isinstance(c, list):
        e["message"]["content"] = [{"type": "thinking", "thinking": "x", "signature": "sig"}
                                   if b.get("type") == "text" else b for b in c]
    out.append(json.dumps(e, separators=(",", ":")))
open(sys.argv[2], "w").write("\n".join(out) + "\n")
PY
grep -q '\[Rule 22' "$TMPDIR/nomark.jsonl" && { echo "fixture error: nomark still has a marker"; exit 2; }
mkdir -p "$TX/$SID/subagents"; cp "$TMPDIR/nomark.jsonl" "$TX/$SID/subagents/agent-b2e.jsonl"

edit_in() {  # edit_in <sid> <agent_id|-> <transcript> <tool_use_id>
  python3 -c '
import json, sys
d = {"session_id": sys.argv[1], "transcript_path": sys.argv[3], "cwd": "/tmp",
     "hook_event_name": "PreToolUse", "tool_name": "Write",
     "tool_input": {"file_path": "/tmp/scratch.txt", "content": "x"}, "tool_use_id": sys.argv[4]}
if sys.argv[2] != "-": d["agent_id"] = sys.argv[2]; d["agent_type"] = "doc-updater"
print(json.dumps(d, separators=(",", ":")))' "$@"
}
verdict() {  # verdict <edit stdin> -> allow|deny|unknown|degraded
  out=$(printf '%s' "$1" | sh "$HOOK" 2>&1)
  if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then echo deny
  elif printf '%s' "$out" | grep -q 'could not verify'; then echo unknown
  elif printf '%s' "$out" | grep -q 'DEGRADED'; then echo degraded
  else echo allow; fi
}
export ARIA_R22_FLUSH_WAIT_MS=3000

# S1 — the subagent's own transcript has the marker: allow, without failing open.
v=$(verdict "$(edit_in "$SID" a1f "$PARENT" "$SUBT")")
[ "$v" = "allow" ] && ok "S1-subagent-marker-allows" || bad "S1-subagent-marker-allows" "got $v"

# S2 — the subagent's own transcript has no marker: deny.
v=$(verdict "$(edit_in "$SID" b2e "$PARENT" "$SUBT")")
[ "$v" = "deny" ] && ok "S2-subagent-no-marker-denies" || bad "S2-subagent-no-marker-denies" "got $v"

# S3 — agent_id present but no subagent file: fall back to transcript_path unchanged.
v=$(verdict "$(edit_in "$SID" c3d "$SUBFX" "$SUBT")")
[ "$v" = "allow" ] && ok "S3-missing-subagent-file-falls-back" || bad "S3-missing-subagent-file-falls-back" "got $v"

# S5 — a hostile agent_id must not steer the read. UNSANITISED, "x/../../../decoy"
# makes "subagents/agent-x/../../../decoy.jsonl", which walks OUT of subagents/ to
# tx/decoy.jsonl — a file holding the target AND a marker (would allow). SANITISED it
# becomes "x......decoy", whose file does not exist, so the hook falls back to
# transcript_path — target, no marker — deny.
# The subagent path is derived from transcript_path, so the traversal directory must
# sit beside THIS case's transcript_path (s5.jsonl), not beside $PARENT — built the
# other way the mutation had nothing to reach and S5 passed without sanitising.
cp "$TMPDIR/nomark.jsonl" "$TX/s5.jsonl"
mkdir -p "$TX/s5/subagents/agent-x"
cp "$SUBFX" "$TX/decoy.jsonl"
v=$(verdict "$(edit_in "$SID" "x/../../../decoy" "$TX/s5.jsonl" "$SUBT")")
[ "$v" = "deny" ] && ok "S5-hostile-agent-id-cannot-steer-read" || bad "S5-hostile-agent-id-cannot-steer-read" "got $v"

# S6a — breaker per agent. The agent's denials come from transcript_path itself
# (no subagent file for agent d4c), so they deny on old code too and this case
# measures ONLY the breaker key. Three denials degrade the agent's 4th edit; the
# parent, in the same session, must still be denied.
SID2="sub-sess-2"
for n in 1 2 3; do verdict "$(edit_in "$SID2" d4c "$TMPDIR/nomark.jsonl" "$SUBT")" >/dev/null; done
v4=$(verdict "$(edit_in "$SID2" d4c "$TMPDIR/nomark.jsonl" "$SUBT")")
vp=$(verdict "$(edit_in "$SID2" - "$TMPDIR/nomark.jsonl" "$SUBT")")
if [ "$v4" = "degraded" ] && [ "$vp" = "deny" ] && [ -f "$TMPDIR/aria-r22-denies-$SID2.agent-d4c" ]; then
  ok "S6a-agent-breaker-does-not-open-parents"
else
  bad "S6a-agent-breaker-does-not-open-parents" "agent 4th=$v4 parent=$vp files: $(ls "$TMPDIR" | grep denies | tr '\n' ' ')"
fi

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
