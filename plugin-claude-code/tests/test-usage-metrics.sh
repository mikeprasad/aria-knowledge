# shellcheck shell=sh
# test-usage-metrics.sh — bin/usage-metrics.sh over a fixture corpus
BIN="$(cd "$(dirname "$0")/../bin" && pwd)"
UM_TMP="${TMPDIR:-/tmp}/aria-um-$$"
KF="$UM_TMP/knowledge"
mkdir -p "$KF/logs/prospect" "$KF/logs/retrospect" "$KF/rules" \
         "$KF/approaches" "$KF/references" "$KF/guides" "$KF/decisions" "$KF/projects"

# --- Task 1: prospect + retrospect distributions ---
# 3 prospect logs: 2 PWC (one May, one Jun), 1 clean (Jun).
# Frontmatter key format (overall_verdict:/overall_outcome:) verified live 2026-07-19
# against the real 546/213-log corpus — anchored to source-of-truth, not invented.
printf 'overall_verdict: PROCEED-WITH-CHANGES\n' > "$KF/logs/prospect/2026-05-01-a.md"
printf 'overall_verdict: PROCEED-WITH-CHANGES\n' > "$KF/logs/prospect/2026-06-01-b.md"
printf 'overall_verdict: PROCEED\n'              > "$KF/logs/prospect/2026-06-02-c.md"
# 2 retrospect logs: 1 closed (with a KEEP verdict), 1 partial
printf 'overall_outcome: closed\n- fix ✅ KEEP\n' > "$KF/logs/retrospect/2026-06-01-x.md"
printf 'overall_outcome: partial\n'               > "$KF/logs/retrospect/2026-06-02-y.md"

OUT="$( KT_KNOWLEDGE_FOLDER="$KF" KT_CONFIG="$UM_TMP/absent.md" sh "$BIN/usage-metrics.sh" )"
get() { printf '%s\n' "$OUT" | grep "^$1 " | head -1 | sed "s/^$1 //"; }

assert_eq "prospect total"  "3" "$(get PROSPECT_TOTAL)"
assert_eq "prospect pwc"    "2" "$(get PROSPECT_PWC)"
assert_eq "prospect clean"  "1" "$(get PROSPECT_CLEAN)"
assert_eq "prospect hold"   "0" "$(get PROSPECT_HOLD)"
assert_eq "retro total"     "2" "$(get RETRO_TOTAL)"
assert_eq "retro closed"    "1" "$(get RETRO_CLOSED)"
assert_eq "retro verdict files" "1" "$(get RETRO_VERDICT_FILES)"

# --- Task 2: pattern count, corpus counts, cost surface ---
printf '## some-pattern-name\n## another-pattern-here\n' > "$KF/rules/retrospect-patterns.md"
printf 'x\n' > "$KF/approaches/a1.md"; printf 'x\n' > "$KF/approaches/a2.md"
printf 'x\n' > "$KF/references/r1.md"
printf '# Knowledge Audit Log\n## Pass 1\n## Pass 2\n' > "$KF/logs/knowledge-audit-log.md"

OUT2="$( KT_KNOWLEDGE_FOLDER="$KF" KT_CONFIG="$UM_TMP/absent.md" sh "$BIN/usage-metrics.sh" )"
get2() { printf '%s\n' "$OUT2" | grep "^$1 " | head -1 | sed "s/^$1 //"; }
assert_eq "pattern count"     "2" "$(get2 PATTERN_COUNT)"
assert_eq "corpus approaches"  "2" "$(get2 CORPUS_approaches)"
assert_eq "corpus references"  "1" "$(get2 CORPUS_references)"
# skill-discovery bytes must be a positive integer (stats the live plugin skills)
assert_eq "skill bytes positive" "1" "$( [ "$(get2 SKILL_DISCOVERY_BYTES)" -gt 0 ] 2>/dev/null && echo 1 || echo 0 )"

# --- Task 3: zero-corpus + missing-folder safety ---
ZF="$UM_TMP/empty"; mkdir -p "$ZF"
OUT3="$( KT_KNOWLEDGE_FOLDER="$ZF" KT_CONFIG="$UM_TMP/absent.md" sh "$BIN/usage-metrics.sh" )"
get3() { printf '%s\n' "$OUT3" | grep "^$1 " | head -1 | sed "s/^$1 //"; }
assert_eq "empty prospect total" "0" "$(get3 PROSPECT_TOTAL)"
assert_eq "empty retro total"    "0" "$(get3 RETRO_TOTAL)"
assert_eq "empty corpus total"   "0" "$(get3 CORPUS_TOTAL)"
# Missing knowledge_folder → single error line, exit 0 (skill handles the message)
OUT4="$( KT_KNOWLEDGE_FOLDER="$UM_TMP/does-not-exist" KT_CONFIG="$UM_TMP/absent.md" sh "$BIN/usage-metrics.sh" )"
assert_eq "missing kf error line" "1" "$(printf '%s\n' "$OUT4" | grep -c '^USAGE_METRICS_ERROR')"

rm -rf "$UM_TMP"
