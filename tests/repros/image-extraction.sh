#!/bin/sh
# image-extraction.sh — Step 2f handles image clippings (vision-read → transcribe → graduate) + git-mv per-file-tracked fix.
# Static-content assertions over the code-port audit-knowledge skill, scoped to the Step 2f block.
set -e
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
AK="$DIR/plugin-claude-code/skills/audit-knowledge/SKILL.md"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

# Scope all checks to the Step 2f block.
S2F=$(awk '/^## Step 2f/,/^## Step 3/' "$AK")

# --- A: scan + sub-flow cover the 5 raster image extensions ---
printf '%s' "$S2F" | grep -qE '\.png.*\.jpg.*\.jpeg.*\.gif.*\.webp' && ok "A image extensions (png/jpg/jpeg/gif/webp)" || bad "A extensions" "5 raster exts not listed in Step 2f"

# --- B: image sub-flow present (vision-read → transcribe → tier decision → graduate → ledger) ---
printf '%s' "$S2F" | grep -qi 'Vision-read' && ok "B vision-read step" || bad "B vision-read" "no Vision-read step in Step 2f"
printf '%s' "$S2F" | grep -qi 'Transcribe' && ok "B transcribe step" || bad "B transcribe" "no Transcribe step"
printf '%s' "$S2F" | grep -qi 'Tier decision' && ok "B per-image tier decision" || bad "B tier" "no per-image faithful-twin vs distilled tier decision"
printf '%s' "$S2F" | grep -qi 'graduated (image' && ok "B image ledger disposition" || bad "B ledger" "no 'graduated (image' ledger entry"
printf '%s' "$S2F" | grep -qi 'image, source only' && ok "B no-content image path" || bad "B no-content" "no 'image, source only' path"

# --- C: per-file-tracked git mv guard (shared fix; applies to .md + images) ---
printf '%s' "$S2F" | grep -qi 'git ls-files --error-unmatch' && ok "C per-file-tracked git mv guard" || bad "C git mv guard" "no git ls-files --error-unmatch move rule"

# --- D: image cost guard ---
printf '%s' "$S2F" | grep -qi 'more than 5 images' && ok "D >5-image cost guard" || bad "D cost guard" "no >5-image vision-read cost guard"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
