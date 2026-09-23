#!/bin/sh
# r22-tool-input-marker-and-flush.sh — Claude Code 2.1.280 regression (v2.53.3).
#
# Two measured defects in the Claude Code branch of pre-edit-check.sh:
#
#   A1. Claude Code 2.1.280 persists most assistant text blocks as a
#       PARAPHRASED thinking block with no [Rule 22] token — even a text block
#       holding only the marker. So a real, visible marker was denied. The
#       marker is now also accepted at the START OF A LINE inside a string
#       input of a non-Edit/Write tool_use in the same window (tool_use inputs
#       are persisted verbatim). Recommended carrier: a Bash heredoc
#         cat <<'R22'
#         [Rule 22] Low Impact — ...
#         R22
#
#   C.  The hook usually starts ~10 ms after its own tool_use is created, before
#       that line is flushed, so it could not locate itself and fail-opened on
#       most edits. It now re-reads the transcript for a bounded wait
#       (ARIA_R22_FLUSH_WAIT_MS, default 1500).
#
# Every variant is derived from tests/fixtures/transcript-cc21280-real-base.jsonl,
# which is REAL 2.1.280 transcript lines (values sanitized, keys/nesting/line
# splits untouched) — hand-authored fixtures would test the hook against a
# belief about the format, not the format.
#
# Run from any directory; resolves its own paths.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/plugin-claude-code/bin/pre-edit-check.sh"
BASE="$REPO_ROOT/tests/fixtures/transcript-cc21280-real-base.jsonl"
TARGET="toolu_fx_3"

export TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
WORK="$TMPDIR/work"; mkdir -p "$WORK"

PASS=0
FAIL=0
CARRIER="cat <<'R22'
[Rule 22] Low Impact — probe change (test only) / Change — x / Solutions — y / Execute — z
R22"

# variant <name> <mode> [value] — writes $WORK/<name>.jsonl derived from BASE.
#   plain            real bytes as-is (Bash input carries no marker)
#   bash_cmd V       set the Bash tool_use (toolu_fx_2) command to V
#   bash_desc V      set the Bash tool_use description to V
#   target_content V set the target Write's content to V
#   carrier_before_boundary   insert a carrier Bash BEFORE the prior Write (toolu_fx_1)
#   text_marker      replace the thinking line before the target with a text block holding the marker
variant() {
  VNAME="$1" VMODE="$2" VVAL="${3:-}" BASE="$BASE" OUT="$WORK/$1.jsonl" CARRIER="$CARRIER" python3 - <<'PY'
import json, os, copy
mode, val = os.environ["VMODE"], os.environ["VVAL"]
lines = [json.loads(l) for l in open(os.environ["BASE"]) if l.strip()]
def tool(e):
    if e.get("type") != "assistant": return None
    for b in e["message"]["content"]:
        if b.get("type") == "tool_use": return b
    return None
out = []
for i, e in enumerate(lines):
    t = tool(e)
    if mode == "bash_cmd" and t and t["id"] == "toolu_fx_2":
        t["input"]["command"] = val
    if mode == "bash_desc" and t and t["id"] == "toolu_fx_2":
        t["input"]["description"] = val
    if mode == "target_content" and t and t["id"] == "toolu_fx_3":
        t["input"]["content"] = val
    if mode == "notebook_carrier" and t and t["id"] == "toolu_fx_2":
        # a content-carrying tool INSIDE the window whose cell text starts with the marker
        t["name"] = "NotebookEdit"
        t["input"] = {"notebook_path": "/tmp/n.ipynb", "new_source": "[Rule 22] Low Impact — notebook cell content\nprint(1)"}
    if mode == "carrier_before_boundary" and t and t["id"] == "toolu_fx_1":
        bash = copy.deepcopy(next(x for x in lines if tool(x) and tool(x)["id"] == "toolu_fx_2"))
        tool(bash)["id"] = "toolu_fx_carrier"
        tool(bash)["input"]["command"] = os.environ["CARRIER"]
        out.append(bash)
    out.append(e)
if mode == "text_marker":
    # the thinking block immediately before the target tool_use
    idx = max(i for i, e in enumerate(out) if tool(e) and tool(e)["id"] == "toolu_fx_3")
    th = out[idx - 1]
    th["message"]["content"] = [{"type": "text", "text": "[Rule 22] Low Impact — probe / Change — x / Solutions — y / Execute — z"}]
open(os.environ["OUT"], "w").write("\n".join(json.dumps(e, ensure_ascii=False) for e in out) + "\n")
PY
}

run_hook() {  # run_hook <fixture> [extra env assignment]
  printf '{"session_id":"r22-fx-%s","file_path":"/tmp/test.txt","transcript_path":"%s","tool_use_id":"%s"}' \
    "$(basename "$1" .jsonl)" "$1" "$TARGET" | sh "$HOOK" 2>&1
}

verdict_of() {
  if printf '%s' "$1" | grep -q '"permissionDecision":"deny"'; then echo deny
  elif printf '%s' "$1" | grep -q 'could not verify this edit'; then echo unknown
  elif printf '%s' "$1" | grep -q 'DEGRADED'; then echo degraded
  else echo allow; fi
}

check() {  # check <case> <expect> <fixture>
  out=$(run_hook "$3"); got=$(verdict_of "$out")
  if [ "$got" = "$2" ]; then printf "PASS  %s (expected=%s)\n" "$1" "$2"; PASS=$((PASS + 1))
  else printf "FAIL  %s (expected=%s got=%s)\n      output: %s\n" "$1" "$2" "$got" "$out"; FAIL=$((FAIL + 1)); fi
}

now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }

# --- A1: tool-input marker channel ------------------------------------------
variant plain plain
variant carrier bash_cmd "$CARRIER"
variant desc bash_desc "[Rule 22] Low Impact — probe via description"
variant self target_content "[Rule 22] Low Impact — the edit tries to authorise itself
body"
variant grep bash_cmd "grep -n '[Rule 22] Low Impact' notes.md"
variant before carrier_before_boundary
variant text text_marker
variant notebook notebook_carrier

check "G0-real-2.1.280-no-marker-denies"          deny  "$WORK/plain.jsonl"
check "G1-heredoc-carrier-allows"                 allow "$WORK/carrier.jsonl"
check "G1b-bash-description-carrier-allows"       allow "$WORK/desc.jsonl"
check "G2-marker-in-target-edit-content-denies"   deny  "$WORK/self.jsonl"
check "G2b-content-tool-in-window-denies"         deny  "$WORK/notebook.jsonl"
check "G3-mid-line-mention-denies"                deny  "$WORK/grep.jsonl"
check "G4-carrier-before-prior-edit-denies"       deny  "$WORK/before.jsonl"
check "G5-text-block-marker-still-allows"         allow "$WORK/text.jsonl"

# --- C: flush race -----------------------------------------------------------
# The target tool_use line (last line) is absent when the hook starts and is
# appended ~300 ms later, as the harness does. Two-sided: compliant -> allow,
# non-compliant -> deny. Either proves a real verdict instead of "unknown".
late() {  # late <name> <source-fixture>
  head -n $(($(wc -l < "$2") - 1)) "$2" > "$WORK/$1.jsonl"
  tail -n 1 "$2" > "$WORK/$1.last"
}
late late_ok  "$WORK/carrier.jsonl"
late late_bad "$WORK/plain.jsonl"
late never    "$WORK/carrier.jsonl"

( sleep 0.3; cat "$WORK/late_ok.last" >> "$WORK/late_ok.jsonl" ) &
check "H1-late-flush-compliant-allows"            allow "$WORK/late_ok.jsonl"
wait
( sleep 0.3; cat "$WORK/late_bad.last" >> "$WORK/late_bad.jsonl" ) &
check "H1b-late-flush-noncompliant-denies"        deny  "$WORK/late_bad.jsonl"
wait

# Never appears: still a LOUD fail-open after the wait (never a silent allow,
# never a deny). No absolute timing bound here on purpose: a ">= cap" lower bound
# was measured PASSING on the pre-poll hook at load average ~60 (interpreter
# startup alone took 359 ms), so it could not tell "waited" from "slow machine".
# H3 below is what proves the wait happened.
timed() {  # timed <cap_ms> -> sets T_OUT, T_EL
  t0=$(now_ms); T_OUT=$(ARIA_R22_FLUSH_WAIT_MS=$1 run_hook "$WORK/never.jsonl"); T_EL=$(( $(now_ms) - t0 ))
}
timed 400; got=$(verdict_of "$T_OUT"); el400=$T_EL
if [ "$got" = "unknown" ]; then
  printf "PASS  H2-never-flushed-failopen-loud (unknown, %d ms)\n" "$el400"; PASS=$((PASS + 1))
else
  printf "FAIL  H2-never-flushed-failopen-loud (got=%s; want unknown)\n      output: %s\n" "$got" "$T_OUT"; FAIL=$((FAIL + 1))
fi
# The cap is honoured and bounds the wait. DIFFERENTIAL on purpose: an absolute
# ceiling flaked under load (interpreter startup varies with the machine), and a
# looser one could not tell an honoured 400 ms cap from an ignored 1500 default.
# Startup cancels in the difference; an ignored override gives a difference ~0.
timed 1200; el1200=$T_EL; d=$((el1200 - el400))
# Threshold 400 = midway between an ignored override (~0 ± startup noise,
# measured ~180 ms at load average ~60) and an honoured one (~800).
if [ "$d" -ge 400 ]; then
  printf "PASS  H3-cap-honoured-differential (1200 ms cap took %d ms longer than 400 ms cap)\n" "$d"; PASS=$((PASS + 1))
else
  printf "FAIL  H3-cap-honoured-differential (difference %d ms; want >=400)\n" "$d"; FAIL=$((FAIL + 1))
fi

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
