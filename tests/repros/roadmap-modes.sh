#!/bin/sh
# roadmap-modes.sh — asserts /roadmap SKILL.md documents the 3 modes, the
# committed-ROADMAP.md persist + source-stamp staleness (render-then-offer),
# the Feature|Band|Status grid + buildable-only-in-Next-with-evidence rule,
# the projects_list resolver (read-only, unknown-tag-lists), graceful mtime-only
# degradation, the hand-authored no-clobber + notify guard, and the write-only-
# ROADMAP.md invariant. Claude-executed prose; this checks the contract, not runtime.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SK="$REPO_ROOT/plugin-claude-code/skills/roadmap/SKILL.md"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

[ -f "$SK" ] && ok "A roadmap SKILL.md exists" || bad "A exists" "no roadmap/SKILL.md"

# B: three modes documented
grep -qiE 'nearest' "$SK"        && ok "B nearest mode"        || bad "B nearest" "not documented"
grep -qiE 'projects_list' "$SK"  && ok "B named mode (projects_list)" || bad "B named" "not documented"
grep -qiF '/roadmap refresh' "$SK" && ok "B refresh mode"      || bad "B refresh" "not documented"

# C: resolver — read-only on roster, unknown tag lists tags, no fuzzy
grep -qiE 'read-only on .?projects_list' "$SK" && ok "C read-only on projects_list" || bad "C ro-roster" "guard not documented"
grep -qiE 'unknown tag' "$SK" && ok "C unknown-tag handling" || bad "C unknown-tag" "not documented"
grep -qiE 'no fuzzy' "$SK" && ok "C no fuzzy match" || bad "C no-fuzzy" "not documented"

# D: the grid — Feature|Band|Status header + band tokens + status glyphs
grep -qF '| Feature | Band | Status |' "$SK" && ok "D Feature|Band|Status header" || bad "D header" "grid header not documented"
for b in Shipped Current Next Later; do
  grep -qF "$b" "$SK" && ok "D band token: $b" || bad "D band $b" "not documented"
done
grep -qiE 'done|in-progress|blocked|buildable' "$SK" && ok "D status vocabulary" || bad "D status" "not documented"

# E: buildable is the only inference — Next-only + evidence + overridable
grep -qiE 'no blocker found' "$SK" && ok "E buildable = no blocker found" || bad "E buildable-rule" "not documented"
grep -qiE 'override' "$SK" && ok "E buildable overridable" || bad "E override" "not documented"
grep -qiE 'cite' "$SK" && ok "E blocked cites its phrase" || bad "E cite" "blocker-citation not documented"

# F: staleness — source-stamp, render-then-offer, mtime-only degradation
grep -qiF 'synthesized_at' "$SK" && ok "F synthesized_at stamp" || bad "F stamp" "not documented"
grep -qiE 'synthesized_from_commit' "$SK" && ok "F commit stamp" || bad "F commit-stamp" "not documented"
grep -qiE 'render the persisted grid, then|render-then-offer' "$SK" && ok "F render-then-offer" || bad "F render-then-offer" "not documented"
grep -qiF 'mtime-only' "$SK" && ok "F mtime-only degradation" || bad "F degrade" "not documented"

# G: persist constraints — committed, write-only-ROADMAP.md, never auto-commit, hand-authored guard
grep -qiE 'committed' "$SK" && ok "G ROADMAP.md committed" || bad "G committed" "not documented"
grep -qiE 'never auto-commit|leaves committing to the user' "$SK" && ok "G never auto-commits" || bad "G no-auto-commit" "not documented"
grep -qiE 'hand-authored' "$SK" && ok "G hand-authored guard" || bad "G hand-authored" "not documented"
grep -qiE 'notify' "$SK" && ok "G notify on hand-authored" || bad "G notify" "not documented"

# H: write-only-ROADMAP.md invariant — Write present but constrained in prose
tools=$(grep -m1 '^allowed-tools:' "$SK")
echo "$tools" | grep -qE '\bWrite\b' && ok "H Write present (persist skill)" || bad "H Write" "persist needs Write: $tools"
echo "$tools" | grep -qE '\bBash\b' && ok "H Bash present (git staleness)" || bad "H Bash" "staleness needs Bash: $tools"
grep -qiE 'writes? (only )?.?ROADMAP\.md' "$SK" && ok "H write scoped to ROADMAP.md" || bad "H write-scope" "write-scope not documented"

# I: boundaries — not /recap, not /aria-assist, not aria-atlas
grep -qiE 'not .?/recap|not `?/recap' "$SK" && ok "I distinct from /recap" || bad "I recap" "boundary not documented"
grep -qiE 'aria-assist' "$SK" && ok "I escalation/boundary /aria-assist" || bad "I aria-assist" "not documented"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
