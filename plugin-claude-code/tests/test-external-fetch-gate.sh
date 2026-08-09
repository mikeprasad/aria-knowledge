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

# ---------------------------------------------------------------------------
# fixture corpus
#   - one file covering atlassian.com AND bitbucket.org (the recorded incident)
#   - one ARCHIVED file covering atlassian.com — must never be surfaced
#   - 12 files covering ambient.example — exercises the > max_hits cap
#   - a THIRD covered surface (render.com), required by AC12: the breaker needs
#     3 denials on 3 DISTINCT registrable domains to reach its threshold.
# ---------------------------------------------------------------------------
mkdir -p "$EF_TMP/kf/projects/cs/references" "$EF_TMP/kf/archive"
printf 'auth notes: use x-bitbucket-api-token-auth against bitbucket.org; REST is atlassian.com\n' \
  > "$EF_TMP/kf/projects/cs/references/staging-bitbucket-auth.md"
printf 'archived: atlassian.com everywhere\n' > "$EF_TMP/kf/archive/old.md"
printf 'render deploy notes: render.com dashboard + service ids\n' \
  > "$EF_TMP/kf/projects/cs/references/render-deploy.md"
i=1; while [ "$i" -le 12 ]; do
  printf 'mentions ambient.example\n' > "$EF_TMP/kf/note-$i.md"; i=$((i+1))
done
# Stopword TRAPS. AC5/AC5b assert that stopword stems never reach the grep, and
# without a corpus file those stems could match, the assertions pass whether or
# not the filter exists — measured: removing `index` from the stopword list left
# AC5 green. These files give a leaked stopword something to hit, so the guards
# can fail for the right reason.
printf 'trap: index.example must only match if the stopword filter LEAKED\n' \
  > "$EF_TMP/kf/trap-index.md"
printf 'trap: brand.example universe.example — line-boundary stopword leak trap\n' \
  > "$EF_TMP/kf/trap-boundary.md"

EF_CFG="$EF_TMP/config-live.md"
printf '%s\n' '---' "knowledge_folder: $EF_TMP/kf" \
  'external_fetch_gate: on' 'external_fetch_max_hits: 8' '---' > "$EF_CFG"

# ef_fetch <url> <session_id> [cfg] -> stdout
ef_fetch() {
  printf '{"url":"%s","session_id":"%s"}' "$1" "$2" \
    | KT_CONFIG="${3:-$EF_CFG}" ARIA_EF_MEMDIR="$EF_TMP/nomem" sh "$HOOK" 2>/dev/null || :
}
# ef_search <query> <session_id> [cfg] -> stdout
ef_search() {
  printf '{"query":"%s","session_id":"%s"}' "$1" "$2" \
    | KT_CONFIG="${3:-$EF_CFG}" ARIA_EF_MEMDIR="$EF_TMP/nomem" sh "$HOOK" 2>/dev/null || :
}
ef_reset() { rm -f "${TMPDIR:-/tmp}"/aria-extfetch-* 2>/dev/null || :; }

# [AC1] covered host -> denied once, reason names the matched path
ef_reset
out=$(ef_fetch "https://support.atlassian.com/bitbucket-cloud/docs/using-api-tokens/" s1)
assert_eq "AC1 covered host -> deny" "1" "$(ef_has '"permissionDecision":"deny"' "$out")"
assert_eq "AC1 deny names the matched path" "1" "$(ef_has 'staging-bitbucket-auth.md' "$out")"

# [AC3] uncovered host -> silent pass on the FIRST call (negative control)
ef_reset
out=$(ef_fetch "https://nothing-here.example/docs" s3)
assert_eq "AC3 uncovered host -> empty stdout" "1" "$([ -z "$out" ] && echo 1 || echo 0)"

# [AC4] ambient host (12 hits > max 8) -> silent pass (negative control)
ef_reset
out=$(ef_fetch "https://ambient.example/x" s4)
assert_eq "AC4 above cap -> empty stdout" "1" "$([ -z "$out" ] && echo 1 || echo 0)"

# [AC5] stopword stems must not fire (negative control)
ef_reset
out=$(ef_search "postgres index bloat vacuum full" s5)
assert_eq "AC5 stopword-only match -> empty stdout" "1" "$([ -z "$out" ] && echo 1 || echo 0)"

# [AC5b] D1 — a stopword adjacent to a newline in the literal still filters
ef_reset
out=$(ef_search "local brand universe wallet" s26)
assert_eq "AC5b line-boundary stopwords still filter" "1" "$([ -z "$out" ] && echo 1 || echo 0)"

# [AC6] prose query naming a covered surface -> denied once
ef_reset
out=$(ef_search "bitbucket api token scopes" s6)
assert_eq "AC6 prose vendor word -> deny" "1" "$(ef_has '"permissionDecision":"deny"' "$out")"
assert_eq "AC6 prose deny names the path" "1" "$(ef_has 'staging-bitbucket-auth.md' "$out")"

# [AC7] gate off (the shipped default) -> never denies (negative control)
EF_CFG_OFF="$EF_TMP/config-off.md"
printf '%s\n' '---' "knowledge_folder: $EF_TMP/kf" 'external_fetch_gate: off' '---' > "$EF_CFG_OFF"
ef_reset
out=$(ef_fetch "https://support.atlassian.com/x" s7 "$EF_CFG_OFF")
assert_eq "AC7 gate off -> empty stdout" "1" "$([ -z "$out" ] && echo 1 || echo 0)"

# [AC8] malformed payload / missing config -> exit 0 AND no output
ef_reset
out=$(printf 'not json at all' | KT_CONFIG="$EF_CFG" sh "$HOOK" 2>/dev/null || :)
assert_eq "AC8 malformed payload -> empty stdout" "1" "$([ -z "$out" ] && echo 1 || echo 0)"
out=$(ef_fetch "https://support.atlassian.com/x" s8 /nonexistent-config)
assert_eq "AC8 missing config -> empty stdout" "1" "$([ -z "$out" ] && echo 1 || echo 0)"

# [AC9] emits permissionDecision, never systemMessage
ef_reset
out=$(ef_fetch "https://support.atlassian.com/x" s9)
assert_eq "AC9 uses permissionDecisionReason" "1" "$(ef_has 'permissionDecisionReason' "$out")"
assert_eq "AC9 does NOT use systemMessage" "0" "$(ef_has 'systemMessage' "$out")"

# [archive] an archived file must never be the reason a host is covered
ef_reset
out=$(ef_fetch "https://support.atlassian.com/x" s10)
assert_eq "archive/ excluded from the reason" "0" "$(ef_has 'archive/old.md' "$out")"
