#!/bin/sh
# r22-tail-anchor.sh — the previous-edit anchor that guards tail mode (v2.57.3).
#
# In tail mode (the edit's own line not yet on disk) the window walk stops at the
# nearest Edit/Write ON DISK. If the previous edit has not landed either, that walk
# would reach the marker that authorised the previous edit — one marker authorising
# two edits (ADR 062). pre-edit-check.sh records every checked edit's tool_use_id in
# ${TMPDIR}/aria-r22-lastedit-<session><agent suffix>; in tail mode, a recorded
# anchor that is not on disk yields the loud "could not verify" instead of a verdict.
#
# Fixtures derive from tests/fixtures/transcript-cc21280-real-base.jsonl (real
# 2.1.280 lines). The target is toolu_fx_3; the previous edit is toolu_fx_1.
#
# Run from any directory; resolves its own paths.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/plugin-claude-code/scripts/pre-edit-check.sh"
BASE="$REPO_ROOT/tests/fixtures/transcript-cc21280-real-base.jsonl"

export TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
export ARIA_R22_FLUSH_WAIT_MS=300
W="$TMPDIR/work"; mkdir -p "$W"

PASS=0
FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

# carrier.jsonl: the Bash call (toolu_fx_2) carries a heredoc marker.
BASE="$BASE" OUT="$W/carrier.jsonl" python3 - <<'PY'
import json, os
out = []
for l in open(os.environ["BASE"]):
    if not l.strip(): continue
    e = json.loads(l)
    if e.get("type") == "assistant":
        for b in e["message"]["content"]:
            if b.get("type") == "tool_use" and b["id"] == "toolu_fx_2":
                b["input"]["command"] = "cat <<'R22'\n[Rule 22] Low Impact — anchor probe\nR22"
    out.append(json.dumps(e, ensure_ascii=False))
open(os.environ["OUT"], "w").write("\n".join(out) + "\n")
PY
# *_tail: the target's own line (the last line) not yet written.
head -n $(($(wc -l < "$W/carrier.jsonl") - 1)) "$W/carrier.jsonl" > "$W/carrier_tail.jsonl"
head -n $(($(wc -l < "$BASE") - 1)) "$BASE" > "$W/plain_tail.jsonl"

anchor() { printf '%s' "$2" > "$TMPDIR/aria-r22-lastedit-$1"; }   # anchor <key> <id>
run() {  # run <session> <fixture> [agent_id]
  if [ -n "${3:-}" ]; then
    printf '{"session_id":"%s","agent_id":"%s","file_path":"/tmp/t.txt","transcript_path":"%s","tool_use_id":"toolu_fx_3"}' "$1" "$3" "$2"
  else
    printf '{"session_id":"%s","file_path":"/tmp/t.txt","transcript_path":"%s","tool_use_id":"toolu_fx_3"}' "$1" "$2"
  fi | sh "$HOOK" 2>&1
}
verdict() {
  if printf '%s' "$1" | grep -q '"permissionDecision":"deny"'; then echo deny
  elif printf '%s' "$1" | grep -q 'could not verify'; then echo unknown
  else echo allow; fi
}

# T1: every check records its own tool_use_id as the next edit's anchor.
run t1 "$W/plain_tail.jsonl" >/dev/null
a=$(cat "$TMPDIR/aria-r22-lastedit-t1" 2>/dev/null || true)
[ "$a" = "toolu_fx_3" ] && ok "T1-anchor-written" || bad "T1-anchor-written" "anchor=[$a]"

# T2: anchor on disk -> the normal tail verdict (no marker after fx_1 -> deny).
anchor t2 toolu_fx_1
v=$(verdict "$(run t2 "$W/plain_tail.jsonl")")
[ "$v" = "deny" ] && ok "T2-anchor-on-disk-normal" || bad "T2-anchor-on-disk-normal" "got $v"

# T3: anchor NOT on disk -> loud unknown, never the allow that the carrier
# (which would belong to the unflushed previous edit) would otherwise give.
anchor t3 toolu_fx_9
v=$(verdict "$(run t3 "$W/carrier_tail.jsonl")")
[ "$v" = "unknown" ] && ok "T3-anchor-unflushed-unknown" || bad "T3-anchor-unflushed-unknown" "got $v"

# T4: an anchor equal to this edit's own id is not a previous edit.
anchor t4 toolu_fx_3
v=$(verdict "$(run t4 "$W/carrier_tail.jsonl")")
[ "$v" = "allow" ] && ok "T4-anchor-is-self-ignored" || bad "T4-anchor-is-self-ignored" "got $v"

# T5: the parent's anchor is never consulted for a subagent edit.
anchor t5 toolu_fx_9
v=$(verdict "$(run t5 "$W/carrier_tail.jsonl" sub1)")
[ "$v" = "allow" ] && ok "T5-anchor-per-agent" || bad "T5-anchor-per-agent" "got $v"

# T6: the precise path (own line found) ignores the anchor.
anchor t6 toolu_fx_9
v=$(verdict "$(run t6 "$BASE")")
[ "$v" = "deny" ] && ok "T6-precise-path-ignores-anchor" || bad "T6-precise-path-ignores-anchor" "got $v"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
