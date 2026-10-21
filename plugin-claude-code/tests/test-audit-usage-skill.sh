# shellcheck shell=sh
# test-audit-usage-skill.sh — the /audit usage skill body leads with errors caught,
# consumes the new metric keys, and no longer reads the verdict rate as plan quality.
# The description line's limits are guarded by tests/repros/claude-ai-upload-limits.sh.
AU_DIR="$(cd "$(dirname "$0")" && pwd)"
AU_PLUGIN="$(cd "$AU_DIR/.." && pwd)"
AU_SKILL="$AU_PLUGIN/skills/audit-usage/SKILL.md"
AU_CODEX="$AU_PLUGIN/../plugin-openai-codex/skills/audit-usage/SKILL.md"

au_has() { grep -qF -- "$1" "$AU_SKILL" && echo yes || echo no; }

for k in FIXED_COST_BYTES PROSPECT_YIELD RETRO_BUNDLE GATE_MODEL GATE_EFFORT USER_RULES_DIGEST_BYTES; do
  assert_eq "audit-usage skill names $k" yes "$(au_has "$k")"
done
assert_eq "audit-usage skill states the verdict-rate caveat" yes "$(au_has 'not plan quality')"
assert_eq "audit-usage skill calls a partial fixed cost a lower bound" yes "$(au_has 'lower bound')"
assert_eq "audit-usage skill drops the verdict-trend permission" no "$(au_has 'Never assert "improving over time" unless')"
assert_eq "audit-usage skill keeps the 10-logs-per-month gate" yes "$(au_has '≥10')"

AU_NOW="$(sed -n '/^description:/p' "$AU_SKILL")"
assert_eq "audit-usage description line is non-empty" yes "$([ -n "$AU_NOW" ] && echo yes || echo no)"

# Final-review fixes, asserted on the canonical skill AND the hand-synced codex copy.
for au_f in "$AU_SKILL" "$AU_CODEX"; do
  au_p="$(basename "$(dirname "$(dirname "$(dirname "$au_f")")")")"
  au_in() { grep -qF -- "$1" "$au_f" && echo yes || echo no; }
  # M1: the settled share is unconditional; the addressable share only when the split exists.
  assert_eq "audit-usage[$au_p] settled share always reported" yes "$(au_in 'the **settled share** `(cand−nm)/cand` always')"
  assert_eq "audit-usage[$au_p] addressable share gated on nm_cap + nm_struct" yes "$(au_in 'Only when `nm_cap + nm_struct` > 0')"
  assert_eq "audit-usage[$au_p] addressable share carries the mixed-population caveat" yes "$(au_in 'the population is mixed')"
  assert_eq "audit-usage[$au_p] old split condition removed" no "$(au_in 'when the split is non-zero')"
  # T4-b: yield runs is its own population.
  assert_eq "audit-usage[$au_p] runs can be fewer than PROSPECT_TOTAL" yes "$(au_in 'can be fewer than `PROSPECT_TOTAL`')"
  # M2: no division by zero.
  assert_eq "audit-usage[$au_p] runs = 0 says so instead of a rate" yes "$(au_in 'no logs carry an Evidence-Sourcing Pass yet')"
  # M3: the corrected audit keys reach the user.
  assert_eq "audit-usage[$au_p] surfaces AUDIT_PASSES" yes "$(au_in 'AUDIT_PASSES')"
  assert_eq "audit-usage[$au_p] surfaces AUDIT_DATED_ENTRIES" yes "$(au_in 'AUDIT_DATED_ENTRIES')"
done
