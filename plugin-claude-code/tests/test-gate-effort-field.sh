# shellcheck shell=sh
# test-gate-effort-field.sh — /prospect and /retrospect record `effort:` from the
# harness variable, never from the model's own guess (self-reports disagreed with
# the harness record on 24% of 140 matched logs).
GE_DIR="$(cd "$(dirname "$0")" && pwd)"
GE_PLUGIN="$(cd "$GE_DIR/.." && pwd)"

for ge_skill in prospect retrospect; do
  ge_f="$GE_PLUGIN/skills/$ge_skill/SKILL.md"
  assert_eq "$ge_skill reads \${CLAUDE_EFFORT:-unrecorded}" yes \
    "$(grep -qF -- '${CLAUDE_EFFORT:-unrecorded}' "$ge_f" && echo yes || echo no)"
  assert_eq "$ge_skill says never infer" yes \
    "$(grep -qF -- 'never infer' "$ge_f" && echo yes || echo no)"
  assert_eq "$ge_skill drops the example effort list" no \
    "$(grep -qF -- 'e.g. xhigh | high | medium' "$ge_f" && echo yes || echo no)"
done
