# shellcheck shell=sh
# test-audit-rules.sh — /audit rules sub-audit (W1) + audit verb migration (W2)
# T5a of docs/superpowers/plans/2026-08-27-audit-rules-and-verb-migration-plan.md.
# Shell-assertable half only: bin/check-rule-lead-bytes.sh behavior + text invariants.
# The judgment ACs (AC1/AC2/AC3/AC6) are dogfood acceptance (plan T5b), NOT suite greens.
# NOTE: sourced under run.sh's `set -eu` — every intended-nonzero exit is captured
# with the `RC=0; cmd || RC=$?` idiom, never `cmd; RC=$?`, which would abort the suite.
BIN="$(cd "$(dirname "$0")/../bin" && pwd)"
SKILLS="$(cd "$(dirname "$0")/../skills" && pwd)"
PCC="$(cd "$(dirname "$0")/.." && pwd)"
AR_TMP="${TMPDIR:-/tmp}/aria-ar-$$"
mkdir -p "$AR_TMP"

# ---------- AC4: check-rule-lead-bytes.sh measures BYTES, not chars ----------

# [AR1] a 200-byte ASCII lead passes
{
  printf '### U1. A fine rule\n\n'
  awk 'BEGIN{s="";for(i=0;i<20;i++)s=s "abcdefghi ";print substr(s,1,200)}'
  printf '\n\n**Why:** irrelevant.\n'
} > "$AR_TMP/ok.md"
RC=0; OUT="$(sh "$BIN/check-rule-lead-bytes.sh" "$AR_TMP/ok.md")" || RC=$?
assert_eq "[AR1] short ASCII lead exits 0" "0" "$RC"
assert_eq "[AR1b] reports OK with byte count" "OK U1 200 bytes" "$(printf '%s\n' "$OUT" | grep '^OK U1' | head -1)"

# [AR2] the discriminating arm: <240 CHARS but >240 BYTES (em-dashes are 3 bytes).
# 160 ASCII chars + 40 em-dashes = 200 chars, 160 + 120 = 280 bytes.
{
  printf '### U2. A multibyte lead\n\n'
  awk 'BEGIN{s="";for(i=0;i<16;i++)s=s "abcdefghi ";printf "%s",substr(s,1,160);for(i=0;i<40;i++)printf "\xe2\x80\x94";print ""}'
  printf '\n\nbody\n'
} > "$AR_TMP/multibyte.md"
RC=0; OUT="$(sh "$BIN/check-rule-lead-bytes.sh" "$AR_TMP/multibyte.md")" || RC=$?
assert_eq "[AR2] multibyte lead (<240 chars, >240 bytes) exits 1" "1" "$RC"
assert_eq "[AR2b] names the rule and byte size" "OVER U2 280 bytes (budget 240)" "$(printf '%s\n' "$OUT" | grep '^OVER U2' | head -1)"

# [AR3] a 250-byte ASCII lead fails plainly
{
  printf '### U3. A long rule\n\n'
  awk 'BEGIN{s="";for(i=0;i<25;i++)s=s "abcdefghi ";print substr(s,1,250)}'
  printf '\n'
} > "$AR_TMP/long.md"
RC=0; sh "$BIN/check-rule-lead-bytes.sh" "$AR_TMP/long.md" >/dev/null || RC=$?
assert_eq "[AR3] 250-byte ASCII lead exits 1" "1" "$RC"

# [AR4] multi-rule file: only the offender is flagged; bold markers stripped before measuring
{
  printf '### U4. Short one\n\nA tiny lead.\n\n'
  printf '### U5. Bold-inflated\n\n'
  awk 'BEGIN{s="";for(i=0;i<24;i++)s=s "abcdefghi ";printf "**%s**\n",substr(s,1,236)}'
  printf '\n'
} > "$AR_TMP/multi.md"
RC=0; OUT="$(sh "$BIN/check-rule-lead-bytes.sh" "$AR_TMP/multi.md")" || RC=$?
assert_eq "[AR4] bold markers stripped before measuring (exit 0)" "0" "$RC"
assert_eq "[AR4b] U5 measured at payload size" "OK U5 236 bytes" "$(printf '%s\n' "$OUT" | grep '^OK U5' | head -1)"

# [AR5] missing file → exit 2 (usage), not a silent pass
RC=0; sh "$BIN/check-rule-lead-bytes.sh" "$AR_TMP/definitely-absent.md" >/dev/null 2>&1 || RC=$?
assert_eq "[AR5] missing file exits 2" "2" "$RC"

# ---------- W1 skill text invariants ----------

ARSKILL="$SKILLS/audit-rules/SKILL.md"

# [AR6] AC5 — fail-closed disposition: the default writes no rule; approve is explicit
AR6=$(grep -c 'The default never writes a rule' "$ARSKILL" || true)
assert_eq "[AR6] default never writes a rule (stated)" "1" "$AR6"
AR6B=$(grep -c 'approve <labels>' "$ARSKILL" || true)
[ "$AR6B" -ge 1 ] && AR6B=yes || AR6B=no
assert_eq "[AR6b] approve names its candidates" "yes" "$AR6B"

# [AR7] Step 7 invokes the byte helper by name (PA4: prose arithmetic replaced by the instrument)
AR7=$(grep -c 'check-rule-lead-bytes.sh' "$ARSKILL" || true)
[ "$AR7" -ge 1 ] && AR7=yes || AR7=no
assert_eq "[AR7] Step 7 runs check-rule-lead-bytes.sh" "yes" "$AR7"

# [AR8] the digest regeneration goes through the sole sanctioned writer
AR8=$(grep -c 'session-start-rules.sh' "$ARSKILL" || true)
[ "$AR8" -ge 1 ] && AR8=yes || AR8=no
assert_eq "[AR8] regenerates via session-start-rules.sh" "yes" "$AR8"

# [AR9] runtime gate is a capability precondition, never a dead Cowork redirect
AR9=$(grep -c 'No Cowork counterpart' "$ARSKILL" || true)
[ "$AR9" -ge 1 ] && AR9=yes || AR9=no
assert_eq "[AR9] states no Cowork counterpart exists" "yes" "$AR9"
AR9C=$(grep -c 'aria-cowork:audit-rules' "$ARSKILL" || true)
assert_eq "[AR9b] never names a nonexistent namespaced variant" "0" "$AR9C"

# ---------- W2 dispatcher invariants (AC7, MC1, MC5) ----------

AUDIT="$SKILLS/audit/SKILL.md"

# [AR10] AC7 — grammar knows rules; MC1 — passthrough is explicit and verb-gated
AR10=$(grep -c '/audit rules \[args' "$AUDIT" || true)
[ "$AR10" -ge 1 ] && AR10=yes || AR10=no
assert_eq "[AR10] grammar has the rules verb with args" "yes" "$AR10"
AR10B=$(grep -c 'promote R1 R3' "$AUDIT" || true)
[ "$AR10B" -ge 1 ] && AR10B=yes || AR10B=no
assert_eq "[AR10b] passthrough example present" "yes" "$AR10B"
AR10C=$(grep -c 'after a recognized verb' "$AUDIT" || true)
[ "$AR10C" -ge 1 ] && AR10C=yes || AR10C=no
assert_eq "[AR10c] args only after a recognized verb" "yes" "$AR10C"

# [AR11] five legs in /audit all, and the fifth delegates to audit-rules
AR11=$(grep -c 'five sub-audits' "$AUDIT" || true)
[ "$AR11" -ge 1 ] && AR11=yes || AR11=no
assert_eq "[AR11] all runs five sub-audits" "yes" "$AR11"
AR11B=$(grep -c 'invoke `audit-rules`' "$AUDIT" || true)
[ "$AR11B" -ge 1 ] && AR11B=yes || AR11B=no
assert_eq "[AR11b] a leg invokes audit-rules" "yes" "$AR11B"

# [AR12] MC5 — the umbrella description absorbed the facet trigger vocabularies
DESC="$(awk '/^description:/{print; exit}' "$AUDIT")"
for phrase in "knowledge audit" "config audit" "audit my style" "audit my rules" "usage report"; do
  case "$DESC" in
    *"$phrase"*) got=yes ;;
    *)           got=MISSING ;;
  esac
  assert_eq "[AR12] umbrella description carries '$phrase'" "yes" "$got"
done

# [AR13] AC8 — no cadence/hook surface auto-fires audit-rules (opt-in invariant)
AR13C=$(grep -c 'audit-rules' "$BIN/session-start-check.sh" || true)
assert_eq "[AR13] session-start-check.sh never names audit-rules" "0" "$AR13C"

# ---------- MC2 — the permanent zero-hyphen ratchet ----------
# A live slash-leading hyphen COMMAND form is legal only on a line carrying the
# compat marker. Path forms (a word char / '.' / '/' / '-' / '_' before the slash,
# e.g. skills/audit-style/...) are NOT command forms and are excluded by the
# leading-context class. skills/.archived/ is historical record and excluded.
MC2_HITS=$(grep -rnE '(^|[^A-Za-z0-9_./-])/audit-(knowledge|config|style|usage|rules)' \
  "$PCC/skills" "$PCC/bin" "$PCC/template" "$PCC/rules" \
  "$PCC/CONFIG.md" "$PCC/QUICKSTART.md" "$PCC/README.md" 2>/dev/null \
  | grep -v '/.archived/' | grep -v '__pycache__' | grep -viE 'compat' | wc -l | tr -d ' ')
assert_eq "[AR14] MC2 ratchet: zero unadvertised hyphen command forms" "0" "$MC2_HITS"
# Positive control: the archived tombstones still carry the historical forms,
# proving the grep pattern can match at all (a zero without this is a dead instrument).
MC2_CTRL=$(grep -rlE '/audit-knowledge' "$PCC/skills/.archived" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "[AR14b] MC2 positive control fires on archived copies" "3" "$MC2_CTRL"

rm -rf "$AR_TMP"
