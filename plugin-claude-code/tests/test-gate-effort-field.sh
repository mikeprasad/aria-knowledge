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

# T7-c: the explanation is runtime-neutral — on Codex, Cursor or Antigravity nothing sets the
# variable, so the sentence must not claim it is set; the hand-synced codex copy is held to it too.
for ge_f in "$GE_PLUGIN/skills/prospect/SKILL.md" "$GE_PLUGIN/skills/retrospect/SKILL.md" \
            "$GE_PLUGIN/../plugin-openai-codex/skills/prospect/SKILL.md" "$GE_PLUGIN/../plugin-openai-codex/skills/retrospect/SKILL.md"; do
  ge_n="$(basename "$(dirname "$(dirname "$(dirname "$ge_f")")")")/$(basename "$(dirname "$ge_f")")"
  assert_eq "$ge_n effort sentence is runtime-neutral" yes \
    "$(grep -qiF -- 'where the runtime sets `$CLAUDE_EFFORT` (Claude Code does' "$ge_f" && echo yes || echo no)"
  assert_eq "$ge_n drops the unconditional Claude Code claim" no \
    "$(grep -qF -- '— Claude Code sets `$CLAUDE_EFFORT` in Bash subprocesses' "$ge_f" && echo yes || echo no)"
done
