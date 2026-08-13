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
# PROSE-WORD trap. The v2.45.0 query branch built `(word)\.[a-z]` — the URL
# branch's domain shape — so a common English word in a FILENAME reference was
# enough to deny. This file gives that pattern something to hit, so the AC6
# negative below fails for the right reason if the domain-shape ever returns.
# Without it the assertion is green whether or not the fix exists (measured
# 2026-08-14: the real corpus matched `guidelines.m` 7x and nothing else).
printf 'trap: see guidelines.md and screening.md — prose-word-as-domain leak trap\n' \
  > "$EF_TMP/kf/trap-prose-filename.md"

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

# [AC6] prose query naming a covered DOMAIN -> denied once.
# The contract narrowed in 2.45.1: a query gates only on a domain it actually
# names. A bare vendor WORD no longer denies (see AC6b) — that produced the
# prose false-positive class this fixture's trap-prose-filename.md guards.
ef_reset
out=$(ef_search "bitbucket.org api token scopes" s6)
assert_eq "AC6 prose naming a domain -> deny" "1" "$(ef_has '"permissionDecision":"deny"' "$out")"
assert_eq "AC6 prose deny names the path" "1" "$(ef_has 'staging-bitbucket-auth.md' "$out")"

# [AC6b] 2.45.1 — a bare-prose query with NO domain must NEVER deny.
# This is the reported bug: `(word)\.[a-z]` matched a common English word inside
# a FILENAME. trap-prose-filename.md holds `guidelines.md` + `screening.md`, so
# reinstating any prose-word pattern reddens this instead of passing quietly.
ef_reset
out=$(ef_search "cervical cancer screening guidelines cytology participation" s27)
assert_eq "AC6b prose without a domain -> empty stdout" "1" "$([ -z "$out" ] && echo 1 || echo 0)"

# [AC6c] 2.45.1 — a domain-shaped prose word must not satisfy the TLD list.
# A generic `\.[a-z]{2,}` would match "screening.the"; the explicit allowlist is
# what makes a match mean "domain". `.md` is not a TLD.
ef_reset
out=$(ef_search "read guidelines.md then screening.md" s28)
assert_eq "AC6c filename extension is not a TLD -> empty stdout" "1" "$([ -z "$out" ] && echo 1 || echo 0)"

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

# ---------------------------------------------------------------------------
# Task 3 — safety layer
# ---------------------------------------------------------------------------

# [AC2] the retry passes — one-shot, not permanent
ef_reset
out1=$(ef_fetch "https://support.atlassian.com/x" s20)
out2=$(ef_fetch "https://support.atlassian.com/x" s20)
assert_eq "AC2 first call denies" "1" "$(ef_has '"permissionDecision":"deny"' "$out1")"
assert_eq "AC2 retry passes (empty stdout)" "1" "$([ -z "$out2" ] && echo 1 || echo 0)"

# a DIFFERENT url on the same registrable domain shares the cooldown
out3=$(ef_fetch "https://developer.atlassian.com/other" s20)
assert_eq "AC2 same registrable domain shares the cooldown" "1" "$([ -z "$out3" ] && echo 1 || echo 0)"

# 2.45.1 — a REPHRASED query about the same domain shares the cooldown.
# This replaces an order-stability check on the old four-longest-words key, which
# after the domain fix would have passed vacuously: with prose never gated, both
# calls return empty whether or not a cooldown exists. Keying on the domain is
# what makes the reason text's "the retry will pass" true — the old key was the
# words themselves, so REPHRASING minted a new key and denied again, which is
# why one real denial became three.
ef_reset
p1=$(ef_search "bitbucket.org api token scopes" s21)
p2=$(ef_search "how do i authenticate against bitbucket.org with a token" s21)
assert_eq "AC2 prose first call denies" "1" "$(ef_has '"permissionDecision":"deny"' "$p1")"
assert_eq "AC2 rephrased same-domain query shares the cooldown" "1" "$([ -z "$p2" ] && echo 1 || echo 0)"

# and a URL on that domain shares it too — one key per registrable domain,
# regardless of which branch derived it
p3=$(ef_fetch "https://bitbucket.org/some/repo" s21)
assert_eq "AC2 URL on the same domain shares the prose cooldown" "1" "$([ -z "$p3" ] && echo 1 || echo 0)"

# [AC11] C1 — an unwritable cooldown must ALLOW, never deny
ef_reset
out=$(printf '{"url":"%s","session_id":"%s"}' "https://support.atlassian.com/x" s22 \
  | KT_CONFIG="$EF_CFG" ARIA_EF_MEMDIR="$EF_TMP/nomem" TMPDIR=/nonexistent-dir-xyz sh "$HOOK" 2>/dev/null || :)
assert_eq "AC11 unwritable cooldown -> empty stdout (allow)" "1" "$([ -z "$out" ] && echo 1 || echo 0)"

# [AC12] C2 — breaker trips after 3 consecutive denials.
# Each denial MUST use a distinct registrable domain: support.atlassian.com and
# atlassian.com collapse to ONE key, so a fixture reusing them reaches only 2
# denials and the "4th not denied" assertion then passes via the COOLDOWN.
ef_reset
rm -f "${TMPDIR:-/tmp}/aria-extfetch-denies-s23" 2>/dev/null || :
d1=$(ef_fetch "https://support.atlassian.com/a" s23)   # atlassian.com
d2=$(ef_fetch "https://bitbucket.org/b"         s23)   # bitbucket.org
d3=$(ef_fetch "https://render.com/c"            s23)   # render.com
assert_eq "AC12 denial 1" "1" "$(ef_has '"permissionDecision":"deny"' "$d1")"
assert_eq "AC12 denial 2" "1" "$(ef_has '"permissionDecision":"deny"' "$d2")"
assert_eq "AC12 denial 3" "1" "$(ef_has '"permissionDecision":"deny"' "$d3")"

# Assert on the breaker's OWN state — an instrument the cooldown cannot satisfy.
assert_eq "AC12 counter reached 3" "3" \
  "$(cat "${TMPDIR:-/tmp}/aria-extfetch-denies-s23" 2>/dev/null || echo MISSING)"

# 4th call: clear the per-surface cooldowns but KEEP the counter, so only a
# tripped breaker can explain an allow. Note the glob excludes the denies file.
rm -f "${TMPDIR:-/tmp}"/aria-extfetch-s23-* 2>/dev/null || :
d4=$(ef_fetch "https://support.atlassian.com/d" s23)
assert_eq "AC12 4th call NOT denied — breaker, not cooldown" "0" "$(ef_has '"permissionDecision":"deny"' "$d4")"

# an allowed fetch resets the counter, restoring enforcement
ef_reset
rm -f "${TMPDIR:-/tmp}/aria-extfetch-denies-s24" 2>/dev/null || :
ef_fetch "https://support.atlassian.com/a" s24 >/dev/null   # deny 1
ef_fetch "https://bitbucket.org/b"         s24 >/dev/null   # deny 2
ef_fetch "https://nothing-here.example/z"  s24 >/dev/null   # uncovered -> allow, RESETS
assert_eq "AC12 allowed fetch cleared the counter" "1" \
  "$([ ! -f "${TMPDIR:-/tmp}/aria-extfetch-denies-s24" ] && echo 1 || echo 0)"
r1=$(ef_fetch "https://render.com/c" s24)
assert_eq "AC12 enforcement restored after reset" "1" "$(ef_has '"permissionDecision":"deny"' "$r1")"

# [AC13] C3 — over-budget yields a silent pass
ef_reset
out=$(printf '{"url":"%s","session_id":"%s"}' "https://support.atlassian.com/x" s25 \
  | KT_CONFIG="$EF_CFG" ARIA_EF_MEMDIR="$EF_TMP/nomem" ARIA_EF_BUDGET_S=0 sh "$HOOK" 2>/dev/null || :)
assert_eq "AC13 zero budget -> empty stdout (allow)" "1" "$([ -z "$out" ] && echo 1 || echo 0)"

# AC13 is a silence assertion, so it can pass for the wrong reason. Positive
# control: the SAME call under a normal budget must still deny.
ef_reset
out=$(printf '{"url":"%s","session_id":"%s"}' "https://support.atlassian.com/x" s25b \
  | KT_CONFIG="$EF_CFG" ARIA_EF_MEMDIR="$EF_TMP/nomem" ARIA_EF_BUDGET_S=60 sh "$HOOK" 2>/dev/null || :)
assert_eq "AC13 control: same call denies under a normal budget" "1" "$(ef_has '"permissionDecision":"deny"' "$out")"
