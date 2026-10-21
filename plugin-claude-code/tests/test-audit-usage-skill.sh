# shellcheck shell=sh
# test-audit-usage-skill.sh — the /audit usage skill body leads with errors caught,
# consumes the new metric keys, and no longer reads the verdict rate as plan quality.
AU_DIR="$(cd "$(dirname "$0")" && pwd)"
AU_PLUGIN="$(cd "$AU_DIR/.." && pwd)"
AU_SKILL="$AU_PLUGIN/skills/audit-usage/SKILL.md"
AU_REPO="$(cd "$AU_PLUGIN/.." && pwd)"

au_has() { grep -qF -- "$1" "$AU_SKILL" && echo yes || echo no; }

for k in FIXED_COST_BYTES PROSPECT_YIELD RETRO_BUNDLE GATE_MODEL GATE_EFFORT USER_RULES_DIGEST_BYTES; do
  assert_eq "audit-usage skill names $k" yes "$(au_has "$k")"
done
assert_eq "audit-usage skill states the verdict-rate caveat" yes "$(au_has 'not plan quality')"
assert_eq "audit-usage skill calls a partial fixed cost a lower bound" yes "$(au_has 'lower bound')"
assert_eq "audit-usage skill drops the verdict-trend permission" no "$(au_has 'Never assert "improving over time" unless')"
assert_eq "audit-usage skill keeps the 10-logs-per-month gate" yes "$(au_has '≥10')"

AU_NOW="$(sed -n '/^description:/p' "$AU_SKILL")"
AU_BASE="$(cd "$AU_REPO" && git show origin/main:plugin-claude-code/skills/audit-usage/SKILL.md 2>/dev/null | sed -n '/^description:/p')"
assert_eq "audit-usage description line is non-empty" yes "$([ -n "$AU_NOW" ] && echo yes || echo no)"
assert_eq "audit-usage description line is byte-identical to origin/main" "$AU_BASE" "$AU_NOW"
