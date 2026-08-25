# shellcheck shell=sh
# test-aria-rules-digest.sh — drift gate for the always-on working-rules digest.
#
# The digest (rules/aria-rules.md) is loaded into every session's context. It must
# cover every rule in the canonical source, and it must be checked by NUMBER SET,
# not by count: plugin-antigravity's digest carried "34 working rules" while its
# source had 38, and a count comparison would have matched a stale total for four
# rules straight.
#
# SOURCE OF TRUTH is the plugin's own template. Never a user's installed copy —
# the maintainer's differs from the template by a personal unpromoted annotation,
# and both have exactly 38 rules, so a count check cannot catch a wrong source.

APM_ROOT="$(cd "$DIR/.." && pwd)"
SRC="$APM_ROOT/template/rules/working-rules.md"
DIGEST="$APM_ROOT/rules/aria-rules.md"

# Rule numbers present in the canonical source, sorted, comma-joined.
src_nums=$(grep '^### [0-9]' "$SRC" 2>/dev/null | sed 's/^### \([0-9]*\)\..*/\1/' | sort -n | tr '\n' ',')
# Rule numbers claimed by the digest.
dig_nums=$(grep -o '^- \*\*Rule [0-9]*' "$DIGEST" 2>/dev/null | sed 's/^- \*\*Rule //' | sort -n | tr '\n' ',')

# Positive control FIRST. Without it, the coverage assertion below is satisfied by
# two empty strings and passes while measuring nothing — a green test proving the
# source path is wrong.
assert_eq "source rule parse is non-empty" "yes" \
  "$([ -n "$src_nums" ] && echo yes || echo no)"

assert_eq "digest covers every working rule by number" "$src_nums" "$dig_nums"

# The digest is a summary, not a replacement — it must route to the full text.
assert_eq "digest points at the full rules file" "yes" \
  "$(grep -q 'rules/working-rules.md' "$DIGEST" 2>/dev/null && echo yes || echo no)"

# The digest must not carry a hardcoded rule total. That literal is exactly how
# antigravity's "34" survived four new rules.
assert_eq "digest hardcodes no rule total" "no" \
  "$(grep -qE 'enforces [0-9]+ working rules|[0-9]+ working rules' "$DIGEST" 2>/dev/null && echo yes || echo no)"

# ---------------------------------------------------------------------------
# session-start-rules.sh — the model-directed channel
# ---------------------------------------------------------------------------
# Fixture defined ONCE here and reused by every later block. The hook must never
# run against the developer's real config, or the suite is environment-dependent.
# KT_CONFIG is overridable (config.sh:5); knowledge_folder must be absolute and
# must exist, or config.sh sets KT_CONFIGURED=false and the hook exits silently.
CFG="$APM_TMP/aria-cfg.md"
KF="$APM_TMP/kf"; mkdir -p "$KF/rules"
printf -- '---\nknowledge_folder: %s\n---\n' "$KF" > "$CFG"

HOOK="$APM_ROOT/bin/session-start-rules.sh"
OUT="$APM_TMP/ssr-out.json"
: > "$OUT"
# run.sh uses `set -eu` and SOURCES each test, so a bare failing invocation
# aborts the entire suite with no summary — which reads as "no output" rather
# than as a red test. An if-condition suspends set -e for the command.
if KT_CONFIG="$CFG" sh "$HOOK" > "$OUT" 2>/dev/null; then rc=0; else rc=$?; fi

assert_eq "hook exits 0" "0" "$rc"
assert_eq "emits additionalContext" "yes" \
  "$(grep -q 'additionalContext' "$OUT" 2>/dev/null && echo yes || echo no)"
assert_eq "does NOT emit systemMessage" "no" \
  "$(grep -q 'systemMessage' "$OUT" 2>/dev/null && echo yes || echo no)"
assert_eq "payload is valid JSON" "yes" \
  "$(jq -e . "$OUT" >/dev/null 2>&1 && echo yes || echo no)"
assert_eq "payload carries a digest rule line" "yes" \
  "$(jq -r '.hookSpecificOutput.additionalContext' "$OUT" 2>/dev/null | grep -q 'Rule 13' && echo yes || echo no)"
assert_eq "payload carries RULE 22 ORDERING" "yes" \
  "$(jq -r '.hookSpecificOutput.additionalContext' "$OUT" 2>/dev/null | grep -q 'RULE 22 ORDERING' && echo yes || echo no)"

# Structure preservation. config.sh's kt_json_escape ends with `tr '\n' ' '` — it
# STRIPS newlines, which is correct for the single-paragraph directives it was
# written for and wrong for a 38-line document. Assert on the DECODED value, not
# the raw file: grepping raw JSON for a literal backslash-n passes on an
# escaped-but-broken payload. Decoding is what proves a consumer sees structure.
SSR_LINES=$(jq -r '.hookSpecificOutput.additionalContext' "$OUT" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "digest structure survives escaping" "yes" \
  "$([ "${SSR_LINES:-0}" -gt 20 ] && echo yes || echo no)"

# Zero U-rules must emit no index — the brand-new-user case, pinned against
# regression. The fixture's knowledge folder has no user-rules.md at all.
assert_eq "no U-rule index when user-rules.md is absent" "no" \
  "$(jq -r '.hookSpecificOutput.additionalContext' "$OUT" 2>/dev/null | grep -q 'STANDING USER RULES' && echo yes || echo no)"
