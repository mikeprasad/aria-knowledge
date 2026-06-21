#!/bin/sh
# recap-modes.sh — asserts /recap SKILL.md documents the 5 modes, the pull resolution,
# the consistent What/Where/Status table, and the read-only (no-Write) invariant.
# Dispatch is Claude-executed prose; this checks the documented contract, not runtime.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SK="$REPO_ROOT/plugin-claude-code/skills/recap/SKILL.md"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

[ -f "$SK" ] && ok "A recap SKILL.md exists" || bad "A exists" "no recap/SKILL.md"

# B: all 5 modes documented
for m in "default" "arc" "commit" "push" "pull"; do
  grep -qiF "$m" "$SK" && ok "B mode documented: $m" || bad "B mode $m" "not in SKILL.md"
done

# C: pull resolution — ORIG_HEAD + reflog fallback + printed range
grep -qF 'ORIG_HEAD' "$SK" && ok "C pull uses ORIG_HEAD" || bad "C ORIG_HEAD" "not documented"
grep -qiE 'reflog' "$SK" && ok "C pull reflog fallback" || bad "C reflog" "no fallback documented"

# D: consistent output table
grep -qF '| What | Where | Status |' "$SK" && ok "D What/Where/Status table" || bad "D table" "schema not documented"

# E: read-only — allowed-tools has no Write/Edit, but has Bash
tools=$(grep -m1 '^allowed-tools:' "$SK")
echo "$tools" | grep -qE '\bWrite\b' && bad "E read-only" "allowed-tools includes Write: $tools" || ok "E no Write in allowed-tools"
echo "$tools" | grep -qE '\bEdit\b' && bad "E read-only" "allowed-tools includes Edit: $tools" || ok "E no Edit in allowed-tools"
echo "$tools" | grep -qE '\bBash\b' && ok "E Bash present (git modes)" || bad "E Bash" "git modes need Bash: $tools"

# F: never-judges — offers retrospect, doesn't run verdicts
grep -qiE 'retrospect' "$SK" && ok "F offers /retrospect (no verdicts itself)" || bad "F retrospect-offer" "no escalation offer"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
