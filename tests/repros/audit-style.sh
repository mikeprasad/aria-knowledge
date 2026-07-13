#!/bin/sh
# audit-style.sh — /audit style SKILL.md documents: the 5-step pipeline, the receipts gate
# (>=2 distinct sessions + dated verbatim quotes, fail-closed), all 3 layers, source-rejection
# of aria's own artifacts, the over-cap prompt, write-confinement, preview-first, and the
# Rule 36 mutation guard. Dogfood ceiling — asserts the DOCUMENTED contract.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SK="$REPO_ROOT/plugin-claude-code/skills/audit-style/SKILL.md"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
[ -f "$SK" ] || { bad "exists" "no audit-style/SKILL.md"; printf "\n0 passed, 1 failed\n"; exit 1; }
# A: receipts gate — the load-bearing contract
grep -qiE '2 (distinct|different) session|>= ?2 session|two distinct session' "$SK" && ok "gate: >=2 sessions" || bad "gate sessions" "no >=2-session rule"
grep -qiE 'verbatim' "$SK" && ok "gate: verbatim quotes" || bad "gate verbatim" "no verbatim requirement"
grep -qiE 'dropped, not|fail.?closed|discard' "$SK" && ok "gate: fail-closed" || bad "gate fail-closed" "no drop-not-soften rule"
# B: all three layers named
for L in "definition of done" "rejection" "debug" "design" "writing" "voice"; do
  grep -qiF "$L" "$SK" && ok "layer cue: $L" || bad "layer $L" "layer not covered"
done
# C: source rejection (no feedback loop)
grep -qiE 'reject.*(command|artifact)|never.*(CLAUDE|MEMORY|feedback_)|not.*evidence' "$SK" && ok "source-rejection documented" || bad "source-reject" "aria-artifact rejection missing"
grep -qF "extract-user-prose.py" "$SK" && ok "cites reference filter" || bad "filter cite" "does not cite extract-user-prose.py"
# D: safety — write confinement + no direct feedback write
grep -qF "rules-backlog.md" "$SK" && ok "writes rules-backlog" || bad "write target" "no rules-backlog target"
grep -qiE 'never.*write.*feedback_|not.*feedback_\*|human-gated' "$SK" && ok "no direct feedback write" || bad "no-feedback-write" "confinement not stated"
# E: over-cap prompt (recent/all/window/cancel)
for opt in recent all window cancel; do
  grep -qiF "$opt" "$SK" && ok "over-cap opt: $opt" || bad "over-cap $opt" "option not documented"
done
# F: preview-first
grep -qiE 'preview|nothing written yet|dry-?run' "$SK" && ok "preview-first documented" || bad "preview" "no preview gate"
# G: opt-in / never cadence-fired
grep -qiE 'opt-in|never.*(cadence|SessionStart)|explicit' "$SK" && ok "opt-in documented" || bad "opt-in" "not stated"
# H: Rule 36 mutation marker — the gate is documented such that its removal is detectable
grep -qiE 'Rule 36|fail for the right reason|removing the .*(gate|guard)' "$SK" && ok "Rule 36 guard referenced" || bad "rule36" "no fail-for-right-reason note"
printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
