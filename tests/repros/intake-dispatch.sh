#!/bin/sh
# intake-dispatch.sh — asserts /intake SKILL.md documents an unambiguous mode-detection
# order, that /audit-knowledge gained a clippings review step, that the 3 consolidated
# skills are retired from the active skills dir, and that no dangling references remain.
# Skill dispatch is Claude-executed prose, so these assert the SKILL.md DOCUMENTS the
# contract unambiguously — not runtime adherence (dogfood ceiling).
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SK="$REPO_ROOT/plugin-claude-code/skills/intake/SKILL.md"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

# --- A: the five mode keywords/defaults are documented in /intake ---
for kw in "extract" "doc" "thread" "clip-whole" "bulk"; do
  grep -qiF "$kw" "$SK" && ok "A mode documented: $kw" || bad "A mode $kw" "not in intake/SKILL.md"
done

# --- B: keyword precedence — extract must be checked BEFORE the bare-url clip rule ---
ex_ln=$(grep -niE 'first arg .?== .?.?extract|first arg.*extract' "$SK" | head -1 | cut -d: -f1)
url_ln=$(grep -niE 'single arg .*url|\^https' "$SK" | head -1 | cut -d: -f1)
if [ -n "$ex_ln" ] && [ -n "$url_ln" ] && [ "$ex_ln" -lt "$url_ln" ]; then
  ok "B extract keyword precedes bare-url clip rule"
else
  bad "B precedence" "extract($ex_ln) not before url($url_ln)"
fi

# --- C: clip-whole writes to intake/clippings/ ---
grep -qF 'intake/clippings/' "$SK" && ok "C clip target documented" || bad "C clip target" "no intake/clippings/ in intake"

# --- D: audit-knowledge documents a clippings review step ---
AK="$REPO_ROOT/plugin-claude-code/skills/audit-knowledge/SKILL.md"
grep -qiE '^## Step 2f|Review Clippings' "$AK" && ok "D audit Step 2f present" || bad "D Step 2f" "audit-knowledge has no clippings review step"
grep -qF 'intake/clippings/' "$AK" && ok "D audit scans intake/clippings/" || bad "D 2f scan" "intake/clippings/ not in audit-knowledge"

# --- E: the 3 consolidated skills are retired from the ACTIVE skills dir ---
SKILLS="$REPO_ROOT/plugin-claude-code/skills"
for s in clip clip-thread extract-doc; do
  [ -d "$SKILLS/$s" ] && bad "E retired $s" "still in active skills/" || ok "E retired: $s absent from active skills"
done

# --- F: no dangling references to retired skills in shipped non-archive files ---
SHIP="$REPO_ROOT/plugin-claude-code"
hits=$(grep -rlE '/clip-thread|/extract-doc|\bclip-thread\b|\bextract-doc\b' "$SHIP" "$REPO_ROOT/README.md" 2>/dev/null | grep -v '/.archived/' || true)
[ -z "$hits" ] && ok "F no dangling clip-thread/extract-doc refs" || bad "F dangling refs" "$(printf '%s' "$hits" | tr '\n' ' ')"
cliphits=$(grep -rlE '/clip\b' "$SHIP/skills" 2>/dev/null | grep -v '/.archived/' | grep -v '/intake/' || true)
[ -z "$cliphits" ] && ok "F no dangling /clip refs" || bad "F dangling /clip" "$(printf '%s' "$cliphits" | tr '\n' ' ')"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
