# Local-Reference Gate Before External Fetch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `bin/pre-external-fetch-check.sh` — a PreToolUse hook that denies the first `WebFetch`/`WebSearch` per session per surface when a recorded local reference covers it, names the paths, and passes on retry.

**Architecture:** One POSIX-sh hook registered on `WebFetch|WebSearch`. It extracts a *surface key* from the tool input (a registrable domain from a URL, or dictionary-filtered stems from a prose query), greps two local stores for that key, and denies once — writing its cooldown *before* denying so a failed write can never wedge the session. A deny-rate circuit breaker mirrors `pre-edit-check.sh`'s v2.30.0 mechanism. Every failure path exits 0.

**Tech Stack:** POSIX `sh`, `/usr/bin/grep` (BSD + GNU compatible), `awk`, `sed`. No `jq` (the repo's hook layer deliberately avoids it). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-09-local-reference-before-external-fetch-design.md` (prospected, PROCEED-WITH-CHANGES; C1/C2/C3 folded in).
**Prospect:** `knowledge/logs/prospect/2026-08-09-file-local-reference-before-external-fetch.md`

## Global Constraints

- **POSIX `sh` only.** Every `bin/*.sh` script runs under `sh`. No bashisms (`[[`, arrays, `local`).
- **`printf '%s'`, never `echo`,** when handling JSON payload text. `echo` interprets backslash escapes, so the `\n` in a JSON string becomes a real newline, the value splits across lines, and single-line `grep -o` silently matches nothing — a silent fail-open in exactly the case the guard exists for. Rationale recorded verbatim in `bin/pre-cron-check.sh:22-26`.
- **`/usr/bin/grep`, never bare `grep`.** The workspace `grep` is a ugrep wrapper that honours `.gitignore` and silently skips embedded repos.
- **`LC_ALL=C` on every `sort`.** `sort -rn` over this corpus dies with `Illegal byte sequence` without it.
- **Fail open on every unexpected condition.** Unparseable input, missing config, absent folder, non-zero grep, failed cooldown write, exceeded runtime budget → `exit 0`, no output.
- **Config idiom, copied exactly** from `bin/config.sh:75-94`:
  `KT_X=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^x:' | sed 's/^x: *//')`
- **Test idiom:** `tests/helpers.sh` provides `assert_eq MSG EXPECTED ACTUAL`. Fixture configs are injected via the `KT_CONFIG` env var. Substring checks use a local `_has` helper. Pattern: `tests/test-r22-planning-paths.sh`.
- **Ports:** `plugin-claude-code` only. Record codex/cursor/antigravity/cowork as tracked-drift in `PORT-LEDGER.json`.
- **Gate B (skill-discovery byte budget)** is currently 19,362 / 19,968. This work adds **no skill frontmatter**, so the budget is unaffected — confirm via `./release.sh`, do not assume.

---

## File Structure

| File | Responsibility |
|---|---|
| `plugin-claude-code/bin/pre-external-fetch-check.sh` | **Create.** The whole hook: key extraction, two-store lookup, cap, cooldown, breaker, deny. Single file — it is one decision with one output, and splitting it would put the fail-open paths in a different file from the denial they protect. |
| `plugin-claude-code/bin/config.sh` | **Modify.** Add the two `KT_EXTERNAL_FETCH_*` parses alongside the existing block. |
| `plugin-claude-code/.claude-plugin/plugin.json` | **Modify.** Register the hook; bump version. |
| `plugin-claude-code/tests/test-external-fetch-gate.sh` | **Create.** AC1–AC13. |
| `plugin-claude-code/CONFIG.md` | **Modify.** Document both keys. |
| `plugin-claude-code/skills/setup/SKILL.md` | **Modify.** Offer both keys in Advanced Options — v2.44.1's lesson was a wizard that *wrote and validated* keys it never *offered*. |
| `PORT-LEDGER.json` | **Modify.** Record tracked-drift. |

---

## Task 1: Config keys

**Files:**
- Modify: `plugin-claude-code/bin/config.sh` (append to the parse block ending ~line 94)
- Test: `plugin-claude-code/tests/test-external-fetch-gate.sh` (create)

**Interfaces:**
- Produces: `$KT_EXTERNAL_FETCH_GATE` (`on`|`off`, default `off`), `$KT_EXTERNAL_FETCH_MAX_HITS` (integer, default `8`). Task 2 reads both.

- [ ] **Step 1: Write the failing test**

Create `plugin-claude-code/tests/test-external-fetch-gate.sh`:

```sh
# shellcheck shell=sh
# test-external-fetch-gate.sh — the local-reference gate before an external fetch
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$ROOT/bin/pre-external-fetch-check.sh"

EF_TMP="${APM_TMP:-/tmp}/ef-gate"; rm -rf "$EF_TMP"; mkdir -p "$EF_TMP"

# 1 if stdout contains needle, else 0
ef_has() { case "$2" in *"$1"*) echo 1 ;; *) echo 0 ;; esac; }

# --- [1] config parsing -----------------------------------------------------
EF_CFG_ON="$EF_TMP/config-on.md"
printf '%s\n' '---' "knowledge_folder: $EF_TMP/kf" \
  'external_fetch_gate: on' 'external_fetch_max_hits: 8' '---' > "$EF_CFG_ON"

out=$(KT_CONFIG="$EF_CFG_ON" sh -c ". $ROOT/bin/config.sh; printf '%s|%s' \
  \"\$KT_EXTERNAL_FETCH_GATE\" \"\$KT_EXTERNAL_FETCH_MAX_HITS\"")
assert_eq "config parses gate + max_hits" "on|8" "$out"

# --- [2] defaults when keys absent -----------------------------------------
EF_CFG_BARE="$EF_TMP/config-bare.md"
printf '%s\n' '---' "knowledge_folder: $EF_TMP/kf" '---' > "$EF_CFG_BARE"

out=$(KT_CONFIG="$EF_CFG_BARE" sh -c ". $ROOT/bin/config.sh; printf '%s|%s' \
  \"\$KT_EXTERNAL_FETCH_GATE\" \"\$KT_EXTERNAL_FETCH_MAX_HITS\"")
assert_eq "absent keys -> off|8 (ships default-off)" "off|8" "$out"
```

- [ ] **Step 2: Run it and confirm it fails**

```bash
(cd ~/Projects/aria/aria-knowledge/plugin-claude-code && sh tests/run.sh 2>&1 | tail -20)
```

Expected: both assertions FAIL — actual is `|` (both variables empty/unset).

- [ ] **Step 3: Add the parses to `config.sh`**

Immediately after the `KT_SESSION_START_PROJECT_PICKER` line in the same block:

```sh
  KT_EXTERNAL_FETCH_GATE=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^external_fetch_gate:' | sed 's/^external_fetch_gate: *//')
  KT_EXTERNAL_FETCH_MAX_HITS=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^external_fetch_max_hits:' | sed 's/^external_fetch_max_hits: *//')
```

Then, after that block closes (where other defaults are applied), add:

```sh
[ -z "$KT_EXTERNAL_FETCH_GATE" ] && KT_EXTERNAL_FETCH_GATE=off
[ -z "$KT_EXTERNAL_FETCH_MAX_HITS" ] && KT_EXTERNAL_FETCH_MAX_HITS=8
```

- [ ] **Step 4: Run the test and confirm it passes**

```bash
(cd ~/Projects/aria/aria-knowledge/plugin-claude-code && sh tests/run.sh 2>&1 | tail -20)
```

Expected: both PASS, no regression in the other suites.

- [ ] **Step 5: Commit**

```bash
(cd ~/Projects/aria/aria-knowledge && git add plugin-claude-code/bin/config.sh plugin-claude-code/tests/test-external-fetch-gate.sh && git commit -m "feat(aria): parse external_fetch_gate + external_fetch_max_hits config keys")
```

---

## Task 2: Hook core — key extraction, lookup, cap, deny

**Files:**
- Create: `plugin-claude-code/bin/pre-external-fetch-check.sh`
- Test: `plugin-claude-code/tests/test-external-fetch-gate.sh` (append)

**Interfaces:**
- Consumes: `$KT_EXTERNAL_FETCH_GATE`, `$KT_EXTERNAL_FETCH_MAX_HITS`, `$KT_KNOWLEDGE_FOLDER` from Task 1's `config.sh`.
- Produces: the script file itself. Task 3 inserts the cooldown/breaker/budget logic into named regions of it; Task 4 registers it.

- [ ] **Step 1: Write the failing tests (AC1, AC3, AC4, AC5, AC6, AC7, AC8, AC9)**

Append to `tests/test-external-fetch-gate.sh`:

```sh
# --- fixture corpus ---------------------------------------------------------
# kf/ = a fake knowledge folder. One file mentions atlassian.com + bitbucket.org.
# 12 files mention ambient.example so the cap can be exercised.
mkdir -p "$EF_TMP/kf/projects/cs/references" "$EF_TMP/kf/archive"
printf 'auth notes: use x-bitbucket-api-token-auth against bitbucket.org; REST is atlassian.com\n' \
  > "$EF_TMP/kf/projects/cs/references/staging-bitbucket-auth.md"
printf 'archived: atlassian.com everywhere\n' > "$EF_TMP/kf/archive/old.md"   # must be EXCLUDED
# D2 (plan prospect) — a THIRD covered surface. The breaker needs 3 denials on
# 3 DISTINCT registrable domains; with only atlassian.com + bitbucket.org the
# counter can never reach its threshold. See AC12.
printf 'render deploy notes: render.com dashboard + service ids\n' \
  > "$EF_TMP/kf/projects/cs/references/render-deploy.md"
i=1; while [ "$i" -le 12 ]; do
  printf 'mentions ambient.example\n' > "$EF_TMP/kf/note-$i.md"; i=$((i+1))
done

EF_CFG="$EF_TMP/config-live.md"
printf '%s\n' '---' "knowledge_folder: $EF_TMP/kf" \
  'external_fetch_gate: on' 'external_fetch_max_hits: 8' '---' > "$EF_CFG"

# ef_fetch <url> <session_id> [cfg] -> stdout
ef_fetch() {
  printf '{"url":"%s","session_id":"%s"}' "$1" "$2" \
    | KT_CONFIG="${3:-$EF_CFG}" ARIA_EF_MEMDIR="$EF_TMP/nomem" sh "$HOOK"
}
# ef_search <query> <session_id> [cfg] -> stdout
ef_search() {
  printf '{"query":"%s","session_id":"%s"}' "$1" "$2" \
    | KT_CONFIG="${3:-$EF_CFG}" ARIA_EF_MEMDIR="$EF_TMP/nomem" sh "$HOOK"
}
ef_reset() { rm -f "${TMPDIR:-/tmp}"/aria-extfetch-* 2>/dev/null; }

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

# [AC8] malformed payload / missing config -> exit 0, NO OUTPUT (not merely exit 0)
ef_reset
out=$(printf 'not json at all' | KT_CONFIG="$EF_CFG" sh "$HOOK"); rc=$?
assert_eq "AC8 malformed payload -> exit 0" "0" "$rc"
assert_eq "AC8 malformed payload -> empty stdout" "1" "$([ -z "$out" ] && echo 1 || echo 0)"
out=$(ef_fetch "https://support.atlassian.com/x" s8 /nonexistent-config)
assert_eq "AC8 missing config -> empty stdout" "1" "$([ -z "$out" ] && echo 1 || echo 0)"

# [AC9] emits permissionDecision, never systemMessage
ef_reset
out=$(ef_fetch "https://support.atlassian.com/x" s9)
assert_eq "AC9 uses permissionDecisionReason" "1" "$(ef_has 'permissionDecisionReason' "$out")"
assert_eq "AC9 does NOT use systemMessage" "0" "$(ef_has 'systemMessage' "$out")"

# [archive excluded] the archived file must never be the reason a host is covered
ef_reset
out=$(ef_fetch "https://support.atlassian.com/x" s10)
assert_eq "archive/ excluded from the reason" "0" "$(ef_has 'archive/old.md' "$out")"
```

- [ ] **Step 2: Run and confirm they fail**

```bash
(cd ~/Projects/aria/aria-knowledge/plugin-claude-code && sh tests/run.sh 2>&1 | tail -30)
```

Expected: every new assertion FAILs — the hook file does not exist, so `sh "$HOOK"` errors and stdout is empty. **Note AC3/AC4/AC5/AC7/AC8 will PASS vacuously** (empty stdout from a missing file). That is the tautology trap this repo has hit twice. Do not treat them as green until Step 4 — their real proof is that they stay green while AC1/AC6 flip from red to green.

- [ ] **Step 3: Write the hook**

Create `plugin-claude-code/bin/pre-external-fetch-check.sh`:

```sh
#!/bin/sh
# pre-external-fetch-check.sh — PreToolUse hook for WebFetch|WebSearch
#
# Denies the FIRST external fetch per session per surface when a recorded local
# reference already covers that surface, naming the matched paths. The retry
# passes. The point is to surface what is already written down at the moment of
# the fetch — not to prevent fetching.
#
# Scope: coverage, not currency. "A local note exists" is not "the note is true."
#
# Fail-open on everything: unparseable input, missing config, absent folder,
# grep failure, a failed cooldown write, or exceeding the runtime budget.
# A gate that cannot read its own input must never block.

INPUT=$(cat)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

[ "$KT_EXTERNAL_FETCH_GATE" = "on" ] || exit 0
[ -n "$KT_KNOWLEDGE_FOLDER" ] || exit 0
[ -d "$KT_KNOWLEDGE_FOLDER" ] || exit 0

# --- extract the surface key ------------------------------------------------
# printf '%s' not echo: echo expands the \n inside JSON strings, splitting the
# value across lines so the single-line grep below matches nothing.
URL=$(printf '%s' "$INPUT"   | grep -o '"url":"[^"]*"'   | head -1 | sed 's/.*"url":"//;s/"$//')
QUERY=$(printf '%s' "$INPUT" | grep -o '"query":"[^"]*"' | head -1 | sed 's/.*"query":"//;s/"$//')

# Ordinary English words that are also domain stems in a real corpus. Matching
# these against prose is pure noise (measured: `index` fires on "postgres index
# bloat"). Inline rather than a data file: bin/ holds only .sh, template/ is the
# user-copied knowledge skeleton, and there is no data/ convention to follow.
EF_STOPWORDS=" common session index key space field head body size style text card gate
medium message parent schema template run seen secondary subscription material local
brand daily example archive extend icon input meta ory prism python render segment
universe wallet the and for how what where when with from this that your api docs doc
help support cloud "

# D1 (plan prospect) — normalise before matching. The literal above is written
# across several lines for readability, and `case "$EF_STOPWORDS" in *" $w "*`
# cannot match a word with a NEWLINE on one side instead of a space. Measured:
# in a two-line list, the word after the break leaks through unfiltered. Roughly
# 8 of ~60 entries would silently stop filtering, and AC5 cannot see it because
# its probe word sits mid-line. Collapse all whitespace to single spaces once.
EF_STOPWORDS=" $(printf '%s' "$EF_STOPWORDS" | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//') "

EF_KEY=""       # cooldown key: stable across a retry
EF_PATTERN=""   # ERE handed to grep

if [ -n "$URL" ]; then
  HOST=$(printf '%s' "$URL" | sed 's|^[a-zA-Z][a-zA-Z0-9+.-]*://||; s|[/?#].*$||; s|:[0-9]*$||')
  EF_KEY=$(printf '%s' "$HOST" | awk -F. '{ if (NF>=2) print $(NF-1)"."$NF; else print $0 }')
  [ -n "$EF_KEY" ] && EF_PATTERN=$(printf '%s' "$EF_KEY" | sed 's/\./\\./g')
elif [ -n "$QUERY" ]; then
  # Longest-first (most specific), capped at 4 so the alternation stays bounded.
  # Sorted afterwards so the cooldown key is stable across a retry — without the
  # sort, a different ordering mints a new key and the "one-shot" gate never clears.
  EF_WORDS=$(printf '%s' "$QUERY" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '\n' \
    | awk 'length($0) >= 4' \
    | while read -r w; do
        case "$EF_STOPWORDS" in *" $w "*) ;; *) printf '%s\n' "$w" ;; esac
      done \
    | awk '{ print length, $0 }' | LC_ALL=C sort -rn | cut -d' ' -f2- | head -4 \
    | LC_ALL=C sort)
  if [ -n "$EF_WORDS" ]; then
    EF_KEY=$(printf '%s' "$EF_WORDS" | tr '\n' '_' | sed 's/_$//')
    EF_ALT=$(printf '%s' "$EF_WORDS" | tr '\n' '|' | sed 's/|$//')
    EF_PATTERN="($EF_ALT)\\.[a-z]"
  fi
fi

[ -n "$EF_KEY" ] || exit 0
[ -n "$EF_PATTERN" ] || exit 0

# Sanitise for use in a filename.
EF_KEY=$(printf '%s' "$EF_KEY" | tr -cs 'a-z0-9._-' '-')

# --- look up local coverage -------------------------------------------------
# /usr/bin/grep, never bare grep: the workspace grep is a ugrep wrapper that
# honours .gitignore and silently skips embedded repos.
# -l (stop at first match per file), never -o (measured 3x slower).
EF_MEMDIR="${ARIA_EF_MEMDIR:-$HOME/.claude/projects}"

EF_HITS=$(
  {
    /usr/bin/grep -rlE --include='*.md' --exclude-dir=archive \
      "$EF_PATTERN" "$KT_KNOWLEDGE_FOLDER" 2>/dev/null
    for d in "$EF_MEMDIR"/*/memory; do
      [ -d "$d" ] || continue
      /usr/bin/grep -rlE "$EF_PATTERN" "$d" 2>/dev/null
    done
  } | LC_ALL=C sort -u
)

[ -n "$EF_HITS" ] || exit 0

EF_COUNT=$(printf '%s\n' "$EF_HITS" | grep -c .)

# Ambient-surface cap. A host mentioned everywhere carries no signal; surfacing
# 76 files trains the reader to dismiss the hook, which is worse than silence.
case "$KT_EXTERNAL_FETCH_MAX_HITS" in ''|*[!0-9]*) KT_EXTERNAL_FETCH_MAX_HITS=8 ;; esac
[ "$EF_COUNT" -gt "$KT_EXTERNAL_FETCH_MAX_HITS" ] && exit 0

# --- one-shot gate ----------------------------------------------------------
SESSION_ID=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/.*"session_id":"//;s/"$//')
[ -z "$SESSION_ID" ] && SESSION_ID="$$"

COOLDOWN_FILE="${TMPDIR:-/tmp}/aria-extfetch-${SESSION_ID}-${EF_KEY}"
[ -f "$COOLDOWN_FILE" ] && exit 0

# >>> TASK-3 INSERTION POINT A: circuit-breaker check <<<

# C1 — the cooldown write is a PRECONDITION of denying, not a consequence.
# pre-explore-codemap-check.sh:66 writes its cooldown unchecked, which is safe
# there because that hook is ADVISORY. Here a failed write means:
#   deny -> retry -> cooldown still absent -> deny -> ... (unbounded)
# So: write first, verify, and allow the fetch if it did not land.
date +%s > "$COOLDOWN_FILE" 2>/dev/null
[ -f "$COOLDOWN_FILE" ] || exit 0

# >>> TASK-3 INSERTION POINT B: breaker increment <<<

EF_LIST=$(printf '%s\n' "$EF_HITS" | sed 's/^/  /' | tr '\n' ' ')

REASON="A recorded local reference already covers this surface (${EF_KEY}). Read these before fetching externally: ${EF_LIST}. Then fetch only what they do not answer — they may be stale, and coverage is not currency. This fires once per surface per session; the retry will pass."
REASON=$(kt_json_escape "$REASON")

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$REASON"
```

- [ ] **Step 4: Run the tests and confirm they pass**

```bash
(cd ~/Projects/aria/aria-knowledge/plugin-claude-code && sh tests/run.sh 2>&1 | tail -30)
```

Expected: AC1 and AC6 flip red→green; AC3/AC4/AC5/AC7/AC8/AC9 green. If any of the negative controls went red, the hook is over-firing — fix before proceeding.

- [ ] **Step 5: Prove the negative controls are not tautologies**

They passed in Step 2 with no hook at all, so they have not yet been shown to mean anything. Temporarily neuter the cap by editing the comparison to `-gt 99999`, re-run, and confirm **AC4 goes RED**. Restore, re-run, confirm green.

```bash
(cd ~/Projects/aria/aria-knowledge/plugin-claude-code && sh tests/run.sh 2>&1 | grep -i 'ac4')
```

Expected: RED while neutered, green after restoring. Repeat for AC5 by removing `index` from `EF_STOPWORDS` — AC5 must go RED.

- [ ] **Step 6: Commit**

```bash
(cd ~/Projects/aria/aria-knowledge && git add plugin-claude-code/bin/pre-external-fetch-check.sh plugin-claude-code/tests/test-external-fetch-gate.sh && git commit -m "feat(aria): pre-external-fetch-check hook — surface local references before an external fetch")
```

---

## Task 3: Safety layer — C1 verified, C2 breaker, C3 runtime budget

**Files:**
- Modify: `plugin-claude-code/bin/pre-external-fetch-check.sh` (insertion points A and B)
- Test: `plugin-claude-code/tests/test-external-fetch-gate.sh` (append)

**Interfaces:**
- Consumes: the script from Task 2, specifically the two marked insertion points and `$SESSION_ID`.
- Produces: no new symbols. Behaviour only.

This task exists because the prospect falsified two assumptions in the spec. Its assertions are the ones that prove the hook cannot wedge a session.

- [ ] **Step 1: Write the failing tests (AC2, AC11, AC12, AC13)**

Append to `tests/test-external-fetch-gate.sh`:

```sh
# --- [AC2] the retry passes (one-shot, not permanent) -----------------------
ef_reset
out1=$(ef_fetch "https://support.atlassian.com/x" s20)
out2=$(ef_fetch "https://support.atlassian.com/x" s20)
assert_eq "AC2 first call denies" "1" "$(ef_has '"permissionDecision":"deny"' "$out1")"
assert_eq "AC2 retry passes (empty stdout)" "1" "$([ -z "$out2" ] && echo 1 || echo 0)"

# same surface reached by a DIFFERENT url must share the cooldown key
out3=$(ef_fetch "https://developer.atlassian.com/other" s20)
assert_eq "AC2 same registrable domain shares the cooldown" "1" "$([ -z "$out3" ] && echo 1 || echo 0)"

# prose key is order-stable, so its retry clears too
ef_reset
p1=$(ef_search "bitbucket api token scopes" s21)
p2=$(ef_search "scopes token api bitbucket" s21)
assert_eq "AC2 prose first call denies" "1" "$(ef_has '"permissionDecision":"deny"' "$p1")"
assert_eq "AC2 reordered prose shares the cooldown" "1" "$([ -z "$p2" ] && echo 1 || echo 0)"

# --- [AC11] C1 — unwritable cooldown must ALLOW, not deny -------------------
ef_reset
out=$(printf '{"url":"%s","session_id":"%s"}' "https://support.atlassian.com/x" s22 \
  | KT_CONFIG="$EF_CFG" ARIA_EF_MEMDIR="$EF_TMP/nomem" TMPDIR=/nonexistent-dir-xyz sh "$HOOK")
assert_eq "AC11 unwritable cooldown -> empty stdout (allow)" "1" "$([ -z "$out" ] && echo 1 || echo 0)"

# --- [AC5b] D1 — a stopword adjacent to a newline in the literal still filters
ef_reset
out=$(ef_search "local brand universe wallet" s26)
assert_eq "AC5b line-boundary stopwords still filter" "1" "$([ -z "$out" ] && echo 1 || echo 0)"

# --- [AC12] C2 — breaker trips after 3 consecutive denials ------------------
# D2 (plan prospect): each denial MUST use a distinct registrable domain.
# The original fixture used support.atlassian.com and atlassian.com as two of
# the three — they collapse to ONE key, so only 2 denials occurred, the breaker
# never reached its threshold, and the "4th call is not denied" assertion passed
# via the COOLDOWN instead. Green for the wrong reason, on the safety mechanism.
ef_reset
rm -f "${TMPDIR:-/tmp}/aria-extfetch-denies-s23" 2>/dev/null
d1=$(ef_fetch "https://support.atlassian.com/a" s23)   # atlassian.com
d2=$(ef_fetch "https://bitbucket.org/b"         s23)   # bitbucket.org
d3=$(ef_fetch "https://render.com/c"            s23)   # render.com
assert_eq "AC12 denial 1" "1" "$(ef_has '"permissionDecision":"deny"' "$d1")"
assert_eq "AC12 denial 2" "1" "$(ef_has '"permissionDecision":"deny"' "$d2")"
assert_eq "AC12 denial 3" "1" "$(ef_has '"permissionDecision":"deny"' "$d3")"

# Assert on the breaker's OWN state, not on an outcome the cooldown can also
# produce. This is the instrument that cannot be satisfied by the wrong mechanism.
assert_eq "AC12 counter reached 3" "3" \
  "$(cat "${TMPDIR:-/tmp}/aria-extfetch-denies-s23" 2>/dev/null)"

# 4th call: a covered surface with NO cooldown of its own, so only the tripped
# breaker can explain an allow. Clear the per-surface cooldowns but keep the counter.
rm -f "${TMPDIR:-/tmp}"/aria-extfetch-s23-* 2>/dev/null
d4=$(ef_fetch "https://support.atlassian.com/d" s23)
assert_eq "AC12 4th call NOT denied — breaker, not cooldown" "0" "$(ef_has '"permissionDecision":"deny"' "$d4")"

# an allowed fetch resets the counter, restoring enforcement
ef_reset
rm -f "${TMPDIR:-/tmp}/aria-extfetch-denies-s24" 2>/dev/null
ef_fetch "https://support.atlassian.com/a" s24 >/dev/null   # atlassian.com  deny 1
ef_fetch "https://bitbucket.org/b"         s24 >/dev/null   # bitbucket.org  deny 2
ef_fetch "https://nothing-here.example/z"  s24 >/dev/null   # uncovered -> allow, RESETS
assert_eq "AC12 allowed fetch cleared the counter" "1" \
  "$([ ! -f "${TMPDIR:-/tmp}/aria-extfetch-denies-s24" ] && echo 1 || echo 0)"
r1=$(ef_fetch "https://render.com/c" s24)                   # 3rd distinct surface
assert_eq "AC12 enforcement restored after reset" "1" "$(ef_has '"permissionDecision":"deny"' "$r1")"

# --- [AC13] C3 — over-budget yields a silent pass ---------------------------
# D3: the variable is ARIA_EF_BUDGET_S (seconds). Using the old _MS name here
# would leave the env var unread, the default budget in force, and AC13 passing
# for no reason — the same wrong-instrument failure as D2.
ef_reset
out=$(printf '{"url":"%s","session_id":"%s"}' "https://support.atlassian.com/x" s25 \
  | KT_CONFIG="$EF_CFG" ARIA_EF_MEMDIR="$EF_TMP/nomem" ARIA_EF_BUDGET_S=0 sh "$HOOK")
assert_eq "AC13 zero budget -> empty stdout (allow)" "1" "$([ -z "$out" ] && echo 1 || echo 0)"

# AC13 is a silence assertion, so it can pass for the wrong reason. Positive
# control: the SAME call with a normal budget must still deny, proving the
# empty stdout above came from the budget and not from a broken invocation.
ef_reset
out=$(printf '{"url":"%s","session_id":"%s"}' "https://support.atlassian.com/x" s25b \
  | KT_CONFIG="$EF_CFG" ARIA_EF_MEMDIR="$EF_TMP/nomem" ARIA_EF_BUDGET_S=60 sh "$HOOK")
assert_eq "AC13 control: same call denies under a normal budget" "1" "$(ef_has '"permissionDecision":"deny"' "$out")"
```

- [ ] **Step 2: Run and confirm the new ones fail**

```bash
(cd ~/Projects/aria/aria-knowledge/plugin-claude-code && sh tests/run.sh 2>&1 | tail -30)
```

Expected: AC12's "4th call is NOT denied" FAILs (no breaker yet). AC13 FAILs (no budget yet). AC2 and AC11 should already pass from Task 2's C1 write-then-verify — **if AC11 passes, confirm it is not vacuous** by temporarily reverting the `[ -f "$COOLDOWN_FILE" ] || exit 0` line and watching it go RED.

- [ ] **Step 3: Add the runtime budget (C3)**

Immediately after the `. "$SCRIPT_DIR/config.sh"` line, add:

```sh
# C3 — bound our own runtime rather than relying on undocumented PreToolUse
# timeout semantics. Budget is checked after the (bounded) lookup work; over
# budget we allow, because a slow gate must never become a blocking gate.
#
# D3 (plan prospect): the unit is SECONDS, not milliseconds. `date +%s` has
# whole-second resolution, so a name like BUDGET_MS would promise a precision
# the mechanism does not have — every sub-second value except 0 is unreachable,
# and a later reader would tune a number that cannot move.
EF_BUDGET_S="${ARIA_EF_BUDGET_S:-4}"
EF_START=$(date +%s)
```

And immediately before the `# --- one-shot gate` section, add:

```sh
EF_ELAPSED=$(( $(date +%s) - EF_START ))
[ "$EF_ELAPSED" -ge "$EF_BUDGET_S" ] && exit 0
```

- [ ] **Step 4: Add the circuit breaker (C2)**

At **insertion point A** (before the cooldown write), replace the marker with:

```sh
# C2 — deny-rate circuit breaker, mirroring pre-edit-check.sh's v2.30.0
# mechanism. Three consecutive denials with no intervening allowed fetch
# degrade to allow-with-warning. C1 fixes the one deadlock cause we know;
# this closes the class, including causes not yet enumerated.
EF_DENY_FILE="${TMPDIR:-/tmp}/aria-extfetch-denies-${SESSION_ID}"
EF_DENIES=0
[ -f "$EF_DENY_FILE" ] && EF_DENIES=$(cat "$EF_DENY_FILE" 2>/dev/null)
case "$EF_DENIES" in ''|*[!0-9]*) EF_DENIES=0 ;; esac
if [ "$EF_DENIES" -ge 3 ]; then
  exit 0
fi
```

At **insertion point B** (after the verified cooldown write), replace the marker with:

```sh
printf '%s' "$(( EF_DENIES + 1 ))" > "$EF_DENY_FILE" 2>/dev/null
```

And in the allow path — immediately after the `[ -n "$EF_HITS" ] || exit 0` line and also after the cap check — reset the counter. Add a single helper near the top instead of duplicating:

```sh
ef_allow() {
  _sid=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/.*"session_id":"//;s/"$//')
  [ -z "$_sid" ] && _sid="$$"
  rm -f "${TMPDIR:-/tmp}/aria-extfetch-denies-${_sid}" 2>/dev/null
  exit 0
}
```

then change `[ -n "$EF_HITS" ] || exit 0` to `[ -n "$EF_HITS" ] || ef_allow` and the cap line's `&& exit 0` to `&& ef_allow`.

- [ ] **Step 5: Run and confirm all pass**

```bash
(cd ~/Projects/aria/aria-knowledge/plugin-claude-code && sh tests/run.sh 2>&1 | tail -30)
```

Expected: AC2, AC11, AC12, AC13 green; AC1–AC10 unchanged.

- [ ] **Step 6: Mutation-check the breaker**

A breaker that never trips and a breaker that always trips both look green on a suite that only checks one direction. Change `-ge 3` to `-ge 99` and confirm **AC12's 4th-call assertion goes RED**. Restore and confirm green.

- [ ] **Step 7: Commit**

```bash
(cd ~/Projects/aria/aria-knowledge && git add plugin-claude-code/bin/pre-external-fetch-check.sh plugin-claude-code/tests/test-external-fetch-gate.sh && git commit -m "feat(aria): external-fetch gate safety layer — verified cooldown, deny-rate breaker, self-bounded runtime")
```

---

## Task 4: Registration, `/setup` wiring, docs, version

**Files:**
- Modify: `plugin-claude-code/.claude-plugin/plugin.json` (hooks block + `version`)
- Modify: `plugin-claude-code/CONFIG.md`
- Modify: `plugin-claude-code/skills/setup/SKILL.md`
- Modify: `PORT-LEDGER.json`

**Interfaces:**
- Consumes: the hook from Tasks 2–3.
- Produces: a registered, user-configurable, released feature.

- [ ] **Step 1: Register the hook**

In `.claude-plugin/plugin.json`, add to the `PreToolUse` array (a new object, sibling to the `Glob|Grep` entry):

```json
{
  "matcher": "WebFetch|WebSearch",
  "hooks": [
    {
      "type": "command",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/bin/pre-external-fetch-check.sh",
      "timeout": 5
    }
  ]
}
```

- [ ] **Step 2: Bump the version**

Minor bump — a new config-key capability every user inherits via the `/setup` diff, matching the `v2.35.0` `autonomy` and `v2.39.0` `planning_paths` precedents. `2.44.1` → `2.45.0`.

- [ ] **Step 3: Document both keys in `CONFIG.md`**

```markdown
### `external_fetch_gate`

`on` | `off` (default `off`)

When `on`, the first `WebFetch`/`WebSearch` per session that targets a surface
your knowledge folder or memory dir already covers is denied once, naming the
matched files. The retry passes. Coverage is keyed on the URL's registrable
domain, or on vendor-like words in a search query.

It is an interrupt, not a verification — it cannot confirm you read the file.

### `external_fetch_max_hits`

integer (default `8`)

Above this many matching files the surface is treated as ambient and the gate
stays silent. A host mentioned in 76 files carries no signal.
```

- [ ] **Step 4: Offer both keys in `/setup` Advanced Options**

Add both to the Advanced Options bundle. **This step is not optional bookkeeping:** v2.44.1's root cause was a wizard that wrote and validated `preflight_gate` keys it had never *offered*, so a Step 7e sweep later flagged them as missing from live config. Writing without offering reproduces that defect exactly.

- [ ] **Step 5: Record tracked-drift**

```bash
(cd ~/Projects/aria/aria-knowledge && bash plugin-claude-code/bin/check-port-drift.sh --update)
```

- [ ] **Step 6: Run the release gates**

```bash
(cd ~/Projects/aria/aria-knowledge && ./release.sh 2>&1 | tail -30)
```

Expected: Gate A all suites pass; Gate B reports a byte count **unchanged from 19,362** (no skill frontmatter added) and under 19,968; Gate C report-only.

- [ ] **Step 7: Live smoke — the recorded failure must now be caught**

Enable the key in the real config, then fetch the URL from the original incident and confirm the denial names `staging-postgres-mcp-and-bitbucket-auth.md`. This is the one check that proves the feature addresses the case it was built for; a green suite over fixtures does not.

- [ ] **Step 8: Commit**

```bash
(cd ~/Projects/aria/aria-knowledge && git add plugin-claude-code/.claude-plugin/plugin.json plugin-claude-code/CONFIG.md plugin-claude-code/skills/setup/SKILL.md PORT-LEDGER.json && git commit -m "feat(aria): register the external-fetch gate, wire /setup, bump to 2.45.0")
```

---

## Self-Review

**Spec coverage.** §4.1 registration → T4S1. §4.2 key extraction → T2S3. §4.3 lookup → T2S3. §4.4 cap → T2S3 + AC4. §4.5 one-shot gate → T2S3 + AC2. §4.6 fail-open → AC8/AC11/AC13. §4.6a C1 → T2S3 + AC11. §4.6b C2 → T3S4 + AC12. §4.6c C3 → T3S3 + AC13. §4.7 config → T1 + T4S3/S4. §4.8 stopwords → `EF_STOPWORDS`. §5 exclusions → no `context7` matcher; only `archive` excluded. §7 distribution → T4S2/S5/S6. AC1–AC13 all have a named assertion.

**Placeholder scan.** No TBDs. Every code step carries runnable code. Insertion points are explicit markers in Task 2's source, consumed by name in Task 3.

**Type consistency.** `EF_KEY`, `EF_PATTERN`, `EF_HITS`, `EF_COUNT`, `EF_DENY_FILE`, `EF_BUDGET_MS`, `ef_allow` are spelled identically across Tasks 2 and 3. `KT_EXTERNAL_FETCH_GATE` / `KT_EXTERNAL_FETCH_MAX_HITS` match Task 1's definitions and `CONFIG.md`'s key names (`external_fetch_gate`, `external_fetch_max_hits`).

## Plan prospect — 2026-08-09

Log: `knowledge/logs/prospect/2026-08-09-plan-local-reference-before-external-fetch.md`
Verdict: **PROCEED-WITH-CHANGES.** Structure, sequencing and task grain sound;
three concrete code defects found and folded in above.

| # | Finding | Resolution |
|---|---|---|
| P1 | `kt_json_escape` availability — the residual this plan flagged itself | **✅ RESOLVED.** Defined at `bin/config.sh:11`; the script sources `config.sh` before use. The deny path emits valid JSON. |
| P2 | The multi-line `EF_STOPWORDS` literal cannot match a word with a **newline** on one side. ~8 of ~60 entries silently stop filtering, and **AC5 cannot see it** (its probe word sits mid-line). | **D1 folded** — normalise whitespace once before matching, plus new **AC5b** probing words that sit at line boundaries. |
| P3 | **AC12 would report the circuit breaker working while the breaker never ran.** Two of its three denials (`support.atlassian.com`, `atlassian.com`) collapse to one registrable domain, so the counter reached 2, never 3 — and the "4th call is not denied" assertion passed via the **cooldown** instead. | **D2 folded** — a third covered surface in the fixture, three distinct domains, and a direct assertion on the breaker's own counter file, which the cooldown cannot satisfy. |
| P4 | `ARIA_EF_BUDGET_MS` promised millisecond precision over `date +%s`, which is whole seconds. Every sub-second value except `0` was unreachable. | **D3 folded** — renamed to `ARIA_EF_BUDGET_S`, AC13 updated to the new name, plus a positive control so its silence cannot pass for the wrong reason. |

**Worth carrying forward:** the plan's own mutation step (T3S6 — *"change `-ge 3`
to `-ge 99`, confirm AC12 goes RED"*) was correctly specified and **would have
caught P3**. The check was right; the fixture beneath it was wrong. A mutation
check only proves what its fixture can reach.

**Process finding.** The fixture corpus was designed for one purpose (the cap and
the two key types) and reused for another (the breaker) without re-deriving what
the second purpose required. Trigger condition for next time: *any assertion
added to an existing fixture, especially one testing a threshold or a counter —
check the fixture can actually reach the state under test, and prefer asserting
on the mechanism's own state over an outcome two mechanisms can produce.*

## Amendment considered and REJECTED — 2026-08-10

After `bitbucket` was promoted to a known tag, the tag matcher began ranking the
correct file first for both recorded queries. On that basis a plan amendment was
proposed: **try `kt_index_match` first, fall back to host-grep only when it
returns nothing.**

**Measured before folding. Falsified.** Six realistic external doc URLs:

| URL | Tags matched | Result |
|---|---|---|
| `sendgrid.com/docs/api-reference/mail-send` | `api` `reference` | 5 files, **none about sendgrid** |
| `docs.github.com/en/rest/security` | `github` `rest` `security` | 5 files, top hits CDN bot detection + CS entitlement leaks |
| `developer.mozilla.org/.../CSS/grid` | `css` `web` | 5 files, top hit magic-link email delivery |
| `twilio.com/docs/messaging/api` | — | 0 ✓ correct |
| `cloud.google.com/run/docs/...` | — | 0 ✓ correct |
| `support.atlassian.com/bitbucket-cloud/...` | `api` `bitbucket` `tokens` | right file first ✓ |

**4 of 6 return a confident 5-file result and 3 of those are entirely wrong.**
The amendment's fallback condition was "returns nothing" — but the failure mode
is **"returns 5 confident wrong files,"** which *preempts* the fallback. Folding
it would have re-enshrined the exact defect §3.1 of the spec ruled out, with the
generic-tag homonym problem now firing on most external doc URLs.

**Root cause of the bad recommendation:** it generalised from one query that
worked *because its tag had just been promoted in the same session*. A
one-sample generalisation about retrieval quality, drawn from the sample most
likely to succeed.

⇒ **The plan is unchanged.** Host-grep stays the primary and only lookup: it is
precise by construction (it searches for the domain string itself), needs no tag
curation, and covers the memory dir, which `index.md` does not. `kt_index_match`
was also rejected as an *additive* enricher — its precision without a specific
vendor tag is poor enough that adding its output to a denial would dilute the
paths that matter.
