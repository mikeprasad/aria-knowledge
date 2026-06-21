#!/bin/sh
# clippings-graduate.sh — clippings graduate to references/sources/ (Step 2f) + /index recursive + template README two-tier.
# Static-content assertions over the code-port skill files (no hook driving needed).
set -e
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
AK="$DIR/plugin-claude-code/skills/audit-knowledge/SKILL.md"
IDX="$DIR/plugin-claude-code/skills/index/SKILL.md"
RM="$DIR/plugin-claude-code/template/references/README.md"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

# Extract just the Step 2f block once for scoped checks.
S2F=$(awk '/^## Step 2f/,/^## Step 3/' "$AK")

# --- A: Step 2f graduates to references/sources/ + ledgers graduated ---
[ "$(printf '%s' "$S2F" | grep -c 'references/sources/')" -ge 3 ] && ok "A Step 2f names references/sources/ (>=3)" || bad "A sources" "references/sources/ < 3 in Step 2f"
[ "$(printf '%s' "$S2F" | grep -c 'disposition: graduated')" -ge 2 ] && ok "A ledger disposition graduated (>=2)" || bad "A graduated" "disposition: graduated < 2 in Step 2f"

# --- B: menu is Graduate (default) / Skip, no discard-the-source path ---
printf '%s' "$S2F" | grep -qiE 'Graduate.*default' && ok "B Graduate is default" || bad "B default" "no Graduate-default menu option"
printf '%s' "$S2F" | grep -qi 'Skip' && ok "B Skip option present" || bad "B Skip" "no Skip option"
printf '%s' "$S2F" | grep -qi 'ledger-clear' && bad "B no-discard" "old ledger-clear discard path still in Step 2f" || ok "B discard path removed"

# --- C: /index scans references/ recursively (indexes references/sources/) ---
grep -qiE 'references/.*recursive' "$IDX" && ok "C /index references/ recursive" || bad "C index" "references/ not annotated recursive in /index Step 1"

# --- D: template references/README documents the two tiers ---
grep -qi 'Two tiers' "$RM" && ok "D README Two tiers heading" || bad "D tiers" "no Two tiers section in template README"
grep -qi 'references/sources/' "$RM" && ok "D README names references/sources/" || bad "D README sources" "template README does not mention references/sources/"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
