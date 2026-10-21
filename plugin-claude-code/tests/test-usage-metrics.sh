# shellcheck shell=sh
# test-usage-metrics.sh — scripts/usage-metrics.sh over a fixture corpus
BIN="$(cd "$(dirname "$0")/../scripts" && pwd)"
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

# --- Task 3 (fetch-scope-effort plan, B): errors caught, real fixed cost, every pattern library ---
# HOME is isolated: the harness isolates TMPDIR, not HOME, and the script reads ~/.claude/rules.
UM_HOME="$UM_TMP/home"; mkdir -p "$UM_HOME/.claude/rules"
B="$UM_TMP/kfb"
mkdir -p "$B/logs/prospect" "$B/logs/retrospect" "$B/rules"
um() { HOME="$UM_HOME" KT_KNOWLEDGE_FOLDER="$B" KT_CONFIG="$UM_TMP/absent.md" sh "${1:-$BIN}/usage-metrics.sh"; }
getb() { printf '%s\n' "$OUTB" | grep "^$1 " | head -1 | sed "s/^$1 //"; }

# AC-B4. Prospect block form: cand 5 val 3 fals 1 nm 1 cap 0 struct 1 (May).
printf -- '---\ntype: prospect\nmodel: claude-opus-5-5[1m]\neffort: high\nsourcing_pass:\n  candidates: 5   # five\n  upgraded_validated: 3\n  upgraded_falsified: 1\n  no_movement: 1\n  no_movement_capability: 0\n  no_movement_structural: 1\noverall_verdict: PROCEED\n---\nbody\nsourcing_pass:\n  candidates: 99\n' > "$B/logs/prospect/2026-05-01-block.md"
# Inline form: cand 3 val 2 nm 1 (Jun); no model field.
printf -- '---\ntype: prospect\neffort: xhigh\nsourcing_pass: { candidates: 3, upgraded_validated: 2, no_movement: 1 }\noverall_verdict: HOLD\n---\n' > "$B/logs/prospect/2026-06-01-inline.md"
# Verdict-less log carrying a sourcing block: excluded from yield.
printf -- '---\ntype: prospect\nsourcing_pass:\n  candidates: 50\n---\n' > "$B/logs/prospect/2026-06-02-noverdict.md"
# F2/F3: a prospect log with a spaced model and spaced effort (no verdict, so not in yield).
printf -- '---\ntype: prospect\nmodel: claude-opus-5 (1M context)\neffort: very high\n---\n' > "$B/logs/prospect/2026-06-03-spaced.md"
# Retrospect nested (model/effort here must NOT feed GATE_*): bundle cand 4 / verified 3 / not 1 ; outcome cand 2 / valid 1 / partial 1 / invalid 0.
printf -- '---\ntype: retrospect\nmodel: claude-opus-5 (1M context)\neffort: high\nsourcing_pass:\n  bundle_marker:\n    candidates: 4\n    upgraded_verified: 3\n    upgraded_not_in_bundle: 1\n    no_movement: 0\n  outcome:\n    candidates: 2\n    upgraded_validated: 1\n    upgraded_partial: 1\n    upgraded_invalidated: 0\n    no_movement: 0\noverall_outcome: closed\n---\n' > "$B/logs/retrospect/2026-06-01-nested.md"

# AC-B2: 3 + 2 + 1 headings (one ###, one backticked); noise lines must not count.
printf '## alpha-one\n## beta-two\n### gamma-three\n# top-level-no\n## Not Kebab\n' > "$B/rules/retrospect-patterns.md"
printf '## delta-four\n## `epsilon-five`\n' > "$B/rules/prospect-patterns.md"
printf '### zeta-six\n' > "$B/rules/overbuild-patterns.md"
# AC-B3: ordinals 12th and 9th, three ## headings, two Date lines.
printf '# Log\n## Pass A\n## Pass B\n## Pass C\n**9th pass — x**\n- **Date:** 2026-01-01\n**12th pass — y**\n- **Date:** 2026-02-01\n' > "$B/logs/knowledge-audit-log.md"

OUTB="$(um)"
assert_eq "B4 prospect yield (runs cand val fals nm cap struct)" "2 8 5 1 2 0 1" "$(getb PROSPECT_YIELD)"
assert_eq "B4 prospect yield May" "2026-05 1 5 1 1" "$(printf '%s\n' "$OUTB" | grep '^PROSPECT_YIELD_MONTH 2026-05 ' | sed 's/^PROSPECT_YIELD_MONTH //')"
assert_eq "B4 prospect yield Jun" "2026-06 1 3 0 1" "$(printf '%s\n' "$OUTB" | grep '^PROSPECT_YIELD_MONTH 2026-06 ' | sed 's/^PROSPECT_YIELD_MONTH //')"
assert_eq "B4 retro bundle" "4 3 1" "$(getb RETRO_BUNDLE)"
assert_eq "B4 retro claims" "2 1 1 0" "$(getb RETRO_CLAIMS)"
assert_eq "gate model [1m] stripped" "1" "$(printf '%s\n' "$OUTB" | grep -c '^GATE_MODEL claude-opus-5-5 1$' | tr -d ' ')"
assert_eq "gate model internal space joined" "1" "$(printf '%s\n' "$OUTB" | grep -c '^GATE_MODEL claude-opus-5_(1M_context) 1$' | tr -d ' ')"
assert_eq "gate model absent" "1" "$(printf '%s\n' "$OUTB" | grep -c '^GATE_MODEL absent 2$' | tr -d ' ')"
assert_eq "gate effort high (prospect only; retro high excluded)" "1" "$(printf '%s\n' "$OUTB" | grep '^GATE_EFFORT high ' | sed 's/^GATE_EFFORT high //')"
assert_eq "F3 gate effort internal space joined" "1" "$(printf '%s\n' "$OUTB" | grep -c '^GATE_EFFORT very_high 1$' | tr -d ' ')"
assert_eq "F2 gate model total is prospect-only" "4" "$(printf '%s\n' "$OUTB" | grep '^GATE_MODEL ' | awk '{t+=$3} END{print t}')"
assert_eq "gate effort xhigh" "1" "$(printf '%s\n' "$OUTB" | grep '^GATE_EFFORT xhigh ' | sed 's/^GATE_EFFORT xhigh //')"
assert_eq "gate effort absent" "1" "$(printf '%s\n' "$OUTB" | grep '^GATE_EFFORT absent ' | sed 's/^GATE_EFFORT absent //')"
assert_eq "B2 pattern count 3+2+1" "6" "$(getb PATTERN_COUNT)"
assert_eq "B2 pattern lib retro" "3" "$(printf '%s\n' "$OUTB" | grep '^PATTERN_LIB retrospect-patterns.md ' | sed 's/^PATTERN_LIB retrospect-patterns.md //')"
assert_eq "B3 audit passes max ordinal" "12" "$(getb AUDIT_PASSES)"
assert_eq "B3 audit dated entries" "2" "$(getb AUDIT_DATED_ENTRIES)"
printf '# Log\n- **Date:** 2026-01-01\n- **Date:** 2026-02-01\n' > "$B/logs/knowledge-audit-log.md"
OUTB="$(um)"
assert_eq "B3 audit passes fallback to Date count" "2" "$(getb AUDIT_PASSES)"

# User-rules digest bytes (HOME-isolated): none -> 0, then a 250-byte file -> 250.
assert_eq "user rules digest absent" "0" "$(getb USER_RULES_DIGEST_BYTES)"
head -c 250 /dev/zero | tr '\0' 'u' > "$UM_HOME/.claude/rules/aria-user-rules.md"
OUTB="$(um)"
assert_eq "user rules digest 250" "250" "$(getb USER_RULES_DIGEST_BYTES)"
rm -f "$UM_HOME/.claude/rules/aria-user-rules.md"

# AC-B1: a copy of the plugin with a 1,000-byte rules digest beside the script.
PL="$UM_TMP/plug"; mkdir -p "$PL/scripts" "$PL/rules" "$PL/skills/s1"
cp "$BIN/usage-metrics.sh" "$BIN/config.sh" "$PL/scripts/"
printf -- '---\nname: s1\ndescription: hello world\n---\n' > "$PL/skills/s1/SKILL.md"
head -c 1000 /dev/zero | tr '\0' 'r' > "$PL/rules/aria-rules.md"
OUTB="$(um "$PL/scripts")"
sk="$(getb SKILL_DISCOVERY_BYTES)"
assert_eq "B1 rules digest bytes" "1000" "$(getb RULES_DIGEST_BYTES)"
assert_eq "B1 fixed cost = skills + digest" "$((sk+1000))" "$(getb FIXED_COST_BYTES)"
# F1: a user digest is opt-in and must NOT change the default fixed cost.
head -c 250 /dev/zero | tr '\0' 'u' > "$UM_HOME/.claude/rules/aria-user-rules.md"
OUTB="$(um "$PL/scripts")"
assert_eq "F1 fixed cost unchanged by user digest" "$((sk+1000))" "$(getb FIXED_COST_BYTES)"
assert_eq "F1 user digest still its own key" "250" "$(getb USER_RULES_DIGEST_BYTES)"
rm -f "$UM_HOME/.claude/rules/aria-user-rules.md"
rm -f "$PL/rules/aria-rules.md"
OUTB="$(um "$PL/scripts")"
assert_eq "B1 rules digest unmeasured" "unmeasured" "$(getb RULES_DIGEST_BYTES)"
assert_eq "B1 fixed cost partial" "$sk partial" "$(getb FIXED_COST_BYTES)"

# AC-C5 single-definition guard: the content-dir list lives only in config.sh — in the
# canonical scripts/ AND in every port copy (codex bin/, cursor scripts/aria/, antigravity bin/).
# Positive arm: each copy reads KT_CONTENT_DIRS, so a copy that drops the scan cannot pass.
C5_REPO="$(cd "$BIN/../.." && pwd)"
for c5_dir in "$BIN" "$C5_REPO/plugin-openai-codex/bin" "$C5_REPO/plugin-cursor-template/scripts/aria" "$C5_REPO/plugin-antigravity/bin"; do
  c5_p="${c5_dir#"$C5_REPO"/}"
  for g in usage-metrics.sh pre-external-fetch-check.sh; do
    [ -f "$c5_dir/$g" ] && ex=1 || ex=0
    assert_eq "C5 $c5_p/$g exists" "1" "$ex"
    assert_eq "C5 $c5_p/$g has no literal dir list" "0" "$(grep -c 'approaches references' "$c5_dir/$g" 2>/dev/null | tr -d ' ' || :)"
    assert_eq "C5 $c5_p/$g reads KT_CONTENT_DIRS" "yes" "$(grep -q 'KT_CONTENT_DIRS' "$c5_dir/$g" 2>/dev/null && echo yes || echo no)"
  done
done

rm -rf "$UM_TMP"
