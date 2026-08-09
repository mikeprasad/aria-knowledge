# shellcheck shell=sh
# test-external-fetch-gate.sh — the local-reference gate before an external fetch.
#
# Sourced by run.sh under `set -eu`, so every command substitution that captures
# a hook's stdout carries `|| :`. We assert on STDOUT, never on exit status, so
# the guard suppresses nothing we rely on.
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$ROOT/bin/pre-external-fetch-check.sh"

EF_TMP="${APM_TMP:-/tmp}/ef-gate"; rm -rf "$EF_TMP"; mkdir -p "$EF_TMP"

# 1 if stdout contains needle, else 0
ef_has() { case "$2" in *"$1"*) echo 1 ;; *) echo 0 ;; esac; }

# ---------------------------------------------------------------------------
# [1] config parsing — both keys read from frontmatter
# ---------------------------------------------------------------------------
EF_CFG_ON="$EF_TMP/config-on.md"
printf '%s\n' '---' "knowledge_folder: $EF_TMP/kf" \
  'external_fetch_gate: on' 'external_fetch_max_hits: 8' '---' > "$EF_CFG_ON"

out=$(KT_CONFIG="$EF_CFG_ON" sh -c ". $ROOT/bin/config.sh; printf '%s|%s' \
  \"\$KT_EXTERNAL_FETCH_GATE\" \"\$KT_EXTERNAL_FETCH_MAX_HITS\"" 2>/dev/null || :)
assert_eq "cfg parses gate + max_hits" "on|8" "$out"

# ---------------------------------------------------------------------------
# [2] defaults when the keys are absent — ships OFF
# The defaults block lives INSIDE `if [ -f "$KT_CONFIG" ]`, so this fixture must
# be a config that EXISTS and merely omits the keys — not a missing file.
# ---------------------------------------------------------------------------
EF_CFG_BARE="$EF_TMP/config-bare.md"
printf '%s\n' '---' "knowledge_folder: $EF_TMP/kf" '---' > "$EF_CFG_BARE"

out=$(KT_CONFIG="$EF_CFG_BARE" sh -c ". $ROOT/bin/config.sh; printf '%s|%s' \
  \"\$KT_EXTERNAL_FETCH_GATE\" \"\$KT_EXTERNAL_FETCH_MAX_HITS\"" 2>/dev/null || :)
assert_eq "cfg absent keys -> off|8 (ships default-off)" "off|8" "$out"
