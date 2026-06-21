#!/bin/sh
# autonomy-posture.sh — Rule 35 presence + autonomy-gated SessionStart directive.
# Drives session-start-check.sh via KT_CONFIG stub + captured stdout (picker-gating.sh technique).
set -e
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DIR/plugin-claude-code/bin/session-start-check.sh"
WR="$DIR/plugin-claude-code/template/rules/working-rules.md"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

# --- A: Rule 35 exists with the decision-routing content ---
grep -qiE '^### 35\.|Rule 35' "$WR" && ok "A Rule 35 present" || bad "A Rule 35" "not in working-rules.md"
grep -qiE 'decision budget|investigate before asking|investigate first' "$WR" && ok "A decision-budget framing" || bad "A framing" "no decision-budget/investigate-first language"
grep -qiE 'no gainable visibility|gainable visibility|explicit approval' "$WR" && ok "A ask-only-on clause" || bad "A ask-clause" "no no-gainable-visibility / explicit-approval clause"
grep -qiE 'Rules? 13|13/14/18|13, 14' "$WR" && ok "A build-philosophy tie (13/14/18)" || bad "A 13/14/18 tie" "no reference to build-philosophy rules"

# --- B/C: autonomy-gated directive (drive the hook via KT_CONFIG stub + captured stdout) ---
TMP=$(mktemp -d); KN="$TMP/kn"; mkdir -p "$KN/logs"
# seed audit log so the hook doesn't early-exit on first-run welcome before the autonomy block
printf -- '- **Date:** 2026-06-21 (seeded for test)\n' > "$KN/logs/knowledge-audit-log.md"
mkcfg() { # $1 = autonomy value (or "omit")
  _cfg="$TMP/cfg-$1.md"
  {
    printf -- '---\nknowledge_folder: %s\nknowledge_root: %s\nconfigured: true\nactive_knowledge_surfacing: false\n' "$KN" "$KN"
    [ "$1" != "omit" ] && printf 'autonomy: %s\n' "$1"
    printf -- '---\n'
  } > "$_cfg"
  printf '%s' "$_cfg"
}
run() { printf '%s' '{"session_id":"auttest"}' | (cd "$TMP" && HOME="$TMP" KT_CONFIG="$1" sh "$HOOK" 2>/dev/null) || true; }

out=$(run "$(mkcfg default)")
echo "$out" | grep -qiE 'decision budget|decide .*forks yourself|investigate before asking|DECISION ROUTING' && bad "B1 default-silent" "autonomy directive emitted at default" || ok "B1 default injects nothing"
out=$(run "$(mkcfg omit)")
echo "$out" | grep -qiE 'decision budget|decide .*forks yourself|DECISION ROUTING' && bad "B2 omit-silent" "autonomy directive emitted when key absent" || ok "B2 omitted key injects nothing"
out=$(run "$(mkcfg balanced)")
echo "$out" | grep -qiE 'investigate first|DECISION ROUTING \(balanced\)' && ok "C1 balanced directive present" || bad "C1 balanced" "no balanced directive"
out=$(run "$(mkcfg autonomous)")
echo "$out" | grep -qiE 'stop .*only|no gainable visibility|ungranted|explicit approval' && ok "C2 autonomous stop-clause" || bad "C2 stop-clause" "no stop-only clause"
echo "$out" | grep -qiE 'Rules? 13|13/14/18' && ok "C2 autonomous 13/14/18 reference" || bad "C2 13/14/18" "no build-philosophy reference"
rm -rf "$TMP"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
