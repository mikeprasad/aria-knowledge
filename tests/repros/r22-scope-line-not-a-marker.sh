#!/bin/sh
# r22-scope-line-not-a-marker.sh — v2.54.2: the POST-edit scope line does not
# satisfy the PRE-edit Rule 22 gate.
#
# Why (measured live 2026-09-25, 2.54.1 installed): a doc-updater Write with no
# assessment was ALLOWED because the line above it was the subagent's answer to the
# previous edit's scope check, "[Rule 22 · Scope] PASS — …". Every matcher accepted
# "[Rule 22 · <anything>]". The framework (change-decision-framework.md:247) names
# "· Scope" as the post-edit line and ADR 036 requires an assessment BEFORE every
# edit. Post-edit forms censused in local transcripts: Scope, scope, SCOPE,
# "Scope check", "Scope-check". "Scoped change" is a different word and still counts.
#
# Old code, declared before running: SC1 x6 RED · SC2 x5 green · SC3-scope RED ·
# SC3-lowimpact green · SC4-scope RED · SC4-lowimpact green.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/plugin-claude-code/bin/pre-edit-check.sh"
REC="$REPO_ROOT/plugin-claude-code/bin/pre-bash-r22-carrier.sh"
BASE="$REPO_ROOT/tests/fixtures/transcript-cc21280-real-base.jsonl"

export TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
W="$TMPDIR/work"; mkdir -p "$W"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
export ARIA_R22_FLUSH_WAIT_MS=300

# text <name> <marker> — real bytes; the block just before the target becomes a
# visible-text block holding <marker>.
text() {
  python3 - "$BASE" "$W/$1.jsonl" "$2" <<'PY'
import json, sys
L = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
i = max(n for n, e in enumerate(L) if e.get("type") == "assistant"
        and any(b.get("id") == "toolu_fx_3" for b in e["message"]["content"]))
L[i-1]["message"]["content"] = [{"type": "text", "text": sys.argv[3]}]
open(sys.argv[2], "w").write("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in L))
PY
}
# bashcmd <name> <command> — real bytes; the Bash tool_use in the window gets <command>.
bashcmd() {
  python3 - "$BASE" "$W/$1.jsonl" "$2" <<'PY'
import json, sys
L = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for e in L:
    for b in (e.get("message") or {}).get("content") or []:
        if isinstance(b, dict) and b.get("id") == "toolu_fx_2":
            b["input"]["command"] = sys.argv[3]
open(sys.argv[2], "w").write("".join(json.dumps(e, ensure_ascii=False) + "\n" for e in L))
PY
}
edit_in() {  # edit_in <transcript>
  python3 -c '
import json, sys
print(json.dumps({"session_id": "sc-sess", "transcript_path": sys.argv[1], "cwd": "/tmp",
  "hook_event_name": "PreToolUse", "tool_name": "Write",
  "tool_input": {"file_path": "/tmp/t.txt", "content": "x"}, "tool_use_id": "toolu_fx_3"},
  separators=(",", ":")))' "$1"
}
verdict() {
  rm -f "$TMPDIR"/aria-r22-denies-* 2>/dev/null
  out=$(edit_in "$1" | sh "$HOOK" 2>&1)
  if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then echo deny
  elif printf '%s' "$out" | grep -q 'could not verify'; then echo unknown
  else echo allow; fi
}

# SC1 — each post-edit form, alone above the edit, must be DENIED.
n=0
for form in "Scope] PASS — only target changed" " Scope] PASS — double space" "scope] PASS — x" "SCOPE] FAIL — x" "Scope check] PASS — x" "Scope-check] PASS — x"; do
  n=$((n + 1)); text "sc1_$n" "[Rule 22 · $form"
  v=$(verdict "$W/sc1_$n.jsonl")
  [ "$v" = "deny" ] && ok "SC1-$n post-edit form denied ([Rule 22 · ${form%%]*}])" || bad "SC1-$n post-edit form denied ([Rule 22 · ${form%%]*}])" "got $v"
done

# SC2 — each pre-edit form still ALLOWS.
n=0
for m in "[Rule 22] Low Impact — probe" "[Rule 22 · Planning] notes.md" "[Rule 22 · Batch 1/2] a.md" "[Rule 22 · Implementation] a.sh — one line" "[Rule 22 · Scoped change] a.sh"; do
  n=$((n + 1)); text "sc2_$n" "$m"
  v=$(verdict "$W/sc2_$n.jsonl")
  [ "$v" = "allow" ] && ok "SC2-$n pre-edit form allowed (${m%%]*}])" || bad "SC2-$n pre-edit form allowed (${m%%]*}])" "got $v"
done

# SC3 — the line-start channel in a prior Bash input.
bashcmd sc3_scope "cat <<'R22'
[Rule 22 · Scope] PASS — previous edit held
R22"
v=$(verdict "$W/sc3_scope.jsonl")
[ "$v" = "deny" ] && ok "SC3-scope-line-in-bash-input-denied" || bad "SC3-scope-line-in-bash-input-denied" "got $v"
bashcmd sc3_low "cat <<'R22'
[Rule 22] Low Impact — probe change
R22"
v=$(verdict "$W/sc3_low.jsonl")
[ "$v" = "allow" ] && ok "SC3-assessment-in-bash-input-allowed" || bad "SC3-assessment-in-bash-input-allowed" "got $v"

# SC4 — the recorder writes no carrier for a Scope-only heredoc.
rec() {  # rec <sid> <command>
  python3 -c '
import json, sys
print(json.dumps({"session_id": sys.argv[1], "prompt_id": "P1", "transcript_path": "/tmp/t.jsonl",
  "hook_event_name": "PreToolUse", "tool_name": "Bash",
  "tool_input": {"command": sys.argv[2], "description": "probe"}, "tool_use_id": "toolu_b"},
  separators=(",", ":")))' "$1" "$2" | sh "$REC" >/dev/null 2>&1 || true
}
rec SC4a "cat <<'R22'
[Rule 22 · Scope] PASS — x
R22"
[ ! -e "$TMPDIR/aria-r22-carrier-SC4a" ] && ok "SC4-scope-heredoc-records-no-carrier" || bad "SC4-scope-heredoc-records-no-carrier" "carrier written"
rec SC4b "cat <<'R22'
[Rule 22] Low Impact — x
R22"
[ -f "$TMPDIR/aria-r22-carrier-SC4b" ] && ok "SC4-assessment-heredoc-records-carrier" || bad "SC4-assessment-heredoc-records-carrier" "no carrier"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
