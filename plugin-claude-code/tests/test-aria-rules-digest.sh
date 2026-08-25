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
