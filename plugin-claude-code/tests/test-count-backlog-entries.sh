# shellcheck shell=sh
# test-count-backlog-entries.sh — scripts/count-backlog-entries.sh over a fixture knowledge folder.
# Every arm has a case that must count AND a case that must not, so a guard that is removed or
# widened turns this red (each was mutation-checked when written, 2026-09-29).
CB_BIN="$(cd "$(dirname "$0")/../scripts" && pwd)/count-backlog-entries.sh"
CB_KF="${TMPDIR:-/tmp}/aria-cb-$$/knowledge"
mkdir -p "$CB_KF/intake" "$CB_KF/logs"
printf '# Log\n\n## Last Audit\n- **Date:** 2026-09-20 (**Nth pass**)\n' > "$CB_KF/logs/knowledge-audit-log.md"

cat > "$CB_KF/intake/insights-backlog.md" <<'EOF'
# Insights Backlog

### 2026-01-01 — x — above the first separator: header prose, never counted

---

<!-- Cleared 2026-09-20 (Nth pass): single-line comment -->
<!--
## 2026-09-28 — x — inside a multi-line comment: never counted
### 2026-09-28 — x — also inside it
-->

### 2026-09-28 — x — canonical entry
body

---

## 2026-09-28 — x — h2 entry: a heading followed by content
- bullet one

## 2026-09-28 — x — group header: empty body, children are their own blocks

#### 2026-09-28 — x — unmarked, after the cutoff: SUSPECT
body

#### 2026-09-28 — x — marked [PROMOTED 2026-09-28 (Nth) → references/y.md]
body

#### 2026-09-28 — x — undated marker form [SUPERSEDED by approaches/z.md]
body

#### 2026-09-20 — x — unmarked, ON the cutoff date: SUSPECT (clock skew makes the date inclusive)
body

#### 2026-09-01 — x — unmarked, before the cutoff: history
body

#### 2026-09-28 — x — [type: feedback] lowercase bracket is not a marker: SUSPECT
**Content:** a body token [DRAFT clause] must not count as a marker either

#### An undated demoted heading: never windowed
body
EOF

cat > "$CB_KF/intake/decisions-backlog.md" <<'EOF'
# Decisions Backlog
---
### 2026-09-28 — x — second canonical entry
EOF
printf '# Extraction Backlog\n---\n' > "$CB_KF/intake/extraction-backlog.md"
# rules-backlog.md deliberately absent

CB_OUT="$(sh "$CB_BIN" "$CB_KF")"
cb_line() { printf '%s\n' "$CB_OUT" | grep "^$1:" | head -1; }

assert_eq "count-backlog: insights arms" \
  "insights: canonical=1 h2=1 h4suspect=3 live=5" "$(cb_line insights)"
assert_eq "count-backlog: decisions canonical" \
  "decisions: canonical=1 h2=0 h4suspect=0 live=1" "$(cb_line decisions)"
assert_eq "count-backlog: separator-only file is zero" \
  "extraction: canonical=0 h2=0 h4suspect=0 live=0" "$(cb_line extraction)"
assert_eq "count-backlog: missing file named, not an error" "rules: missing" "$(cb_line rules)"
assert_eq "count-backlog: TOTAL line" \
  "TOTAL: canonical=2 h2=1 h4suspect=3 live=6 cutoff=2026-09-20" "$(cb_line TOTAL)"
assert_eq "count-backlog: --total" "6" "$(sh "$CB_BIN" "$CB_KF" --total)"
assert_eq "count-backlog: --list names every non-### live block" "4" \
  "$(sh "$CB_BIN" "$CB_KF" --list | grep -c ': h[24]-')"
assert_eq "count-backlog: --list carries file:line" "yes" \
  "$(sh "$CB_BIN" "$CB_KF" --list | grep -q 'insights-backlog.md:[0-9][0-9]*: h2-entry: ## 2026-09-28 — x — h2 entry' && echo yes || echo no)"

# No audit log (fresh install): the suspect arm is OFF, the other arms are unaffected.
mv "$CB_KF/logs/knowledge-audit-log.md" "$CB_KF/logs/moved.md"
assert_eq "count-backlog: no audit log turns the suspect arm off" \
  "TOTAL: canonical=2 h2=1 h4suspect=0 live=3 cutoff=none" \
  "$(sh "$CB_BIN" "$CB_KF" | grep '^TOTAL:')"
mv "$CB_KF/logs/moved.md" "$CB_KF/logs/knowledge-audit-log.md"

# run.sh sources this under `set -eu`, so a bare non-zero exit would abort the whole suite.
CB_RC=0; sh "$CB_BIN" "/nonexistent-aria-cb-$$" >/dev/null 2>&1 || CB_RC=$?
assert_eq "count-backlog: missing knowledge folder exits 2" "2" "$CB_RC"
CB_RC=0; sh "$CB_BIN" "$CB_KF" --bogus >/dev/null 2>&1 || CB_RC=$?
assert_eq "count-backlog: unknown mode exits 2" "2" "$CB_RC"

# --- session-start-check.sh consumes the counter (the audit TRIGGER) ---
# Until 2026-09-29 no test covered the hook's count or its prompt text at all. Threshold 3,
# cadence huge so only the entry-count tier can fire. ⚠ The hook also prunes /tmp aria-active-*
# files older than a day, exactly as every real session start does.
CB_HK="${TMPDIR:-/tmp}/aria-cb-$$/hook"
mkdir -p "$CB_HK/intake" "$CB_HK/logs"
printf '# Log\n\n## Last Audit\n- **Date:** 2026-09-20 (pass)\n' > "$CB_HK/logs/knowledge-audit-log.md"
printf -- '---\nknowledge_folder: %s\naudit_trigger_threshold: 3\naudit_cadence_knowledge: 99999\naudit_cadence_config: 99999\n---\n' \
  "$CB_HK" > "${TMPDIR:-/tmp}/aria-cb-$$/config.md"
printf '# I\n---\n### 2026-09-28 — x — one\n## 2026-09-28 — x — h2 entry\n- body\n#### 2026-09-28 — x — unmarked suspect\n' \
  > "$CB_HK/intake/insights-backlog.md"
# rules-backlog: the hook counted three backlogs until 2026-09-29 while the audit skill counted four.
printf '# R\n---\n### 2026-09-28 — x — a rule candidate\n' > "$CB_HK/intake/rules-backlog.md"
cb_hook() { KT_CONFIG="${TMPDIR:-/tmp}/aria-cb-$$/config.md" sh "$1/session-start-check.sh" 2>/dev/null; }
CB_BINDIR="$(dirname "$CB_BIN")"

assert_eq "session-start: counts every live shape across all four backlogs, names the off-level ones" "yes" \
  "$(cb_hook "$CB_BINDIR" | grep -q 'Knowledge audit suggested — 4 entries (2 not at ### level) ready for review' && echo yes || echo no)"

printf '# R\n---\n### a\n### b\n### c\n' > "$CB_HK/intake/rules-backlog.md"
printf '# I\n---\n' > "$CB_HK/intake/insights-backlog.md"
assert_eq "session-start: canonical-only backlog carries no off-level note" "yes" \
  "$(cb_hook "$CB_BINDIR" | grep -q 'Knowledge audit suggested — 3 entries ready for review' && echo yes || echo no)"

# The hook repeats the INSIGHT CAPTURE directive inside a DOUBLE-QUOTED sh string. Backticks there
# are command substitution: the first draft of this contract rendered as "each as one  heading",
# silently, exit 0. Assert the RENDERED output — a grep of the source file passes over that.
assert_eq "session-start: INSIGHT CAPTURE heading contract survives rendering" "yes" \
  "$(cb_hook "$CB_BINDIR" | grep -qF "each as one '### YYYY-MM-DD — <project> — <title>' heading" && echo yes || echo no)"

# Counter missing (a port or partial install): falls back to 0 — no count prompt, hook still runs.
CB_BROKEN="${TMPDIR:-/tmp}/aria-cb-$$/bin-broken"
cp -R "$CB_BINDIR" "$CB_BROKEN" && rm -f "$CB_BROKEN/count-backlog-entries.sh"
CB_HOUT="$(cb_hook "$CB_BROKEN")"
assert_eq "session-start: missing counter reads as 0, no count prompt" "no" \
  "$(printf '%s' "$CB_HOUT" | grep -q 'Knowledge audit suggested' && echo yes || echo no)"
assert_eq "session-start: missing counter still emits the hook payload" "yes" \
  "$(printf '%s' "$CB_HOUT" | grep -q 'systemMessage' && echo yes || echo no)"

rm -rf "${TMPDIR:-/tmp}/aria-cb-$$"
