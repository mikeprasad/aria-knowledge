# shellcheck shell=sh
# test-content-dirs.sh — KT_CONTENT_DIRS is one constant, present with no config file.
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

out=$(KT_CONFIG=/nonexistent sh -c ". $ROOT/scripts/config.sh; printf %s \"\$KT_CONTENT_DIRS\"" 2>/dev/null || :)
assert_eq "content dirs constant" "approaches references projects rules guides decisions" "$out"

# I3: /setup describes the fetch gate's real scope — the six curated dirs plus memory dirs, not the
# whole knowledge folder (intake/ and logs/ are deliberately not scanned).
for cd_f in "$ROOT/skills/setup/SKILL.md" "$ROOT/../plugin-openai-codex/skills/setup/SKILL.md"; do
  cd_line="$(grep -F -- '**External-fetch gate (`external_fetch_gate`):**' "$cd_f" 2>/dev/null || :)"
  cd_p="$(basename "$(dirname "$(dirname "$(dirname "$cd_f")")")")"
  assert_eq "setup[$cd_p] fetch-gate line names the curated dirs" yes \
    "$(printf '%s' "$cd_line" | grep -qF -- '(`approaches`, `references`, `projects`, `rules`, `guides`, `decisions`) or your memory dirs' && echo yes || echo no)"
  assert_eq "setup[$cd_p] fetch-gate line drops 'knowledge folder or memory dirs'" no \
    "$(printf '%s' "$cd_line" | grep -qF -- 'your knowledge folder or memory dirs already cover' && echo yes || echo no)"
done
