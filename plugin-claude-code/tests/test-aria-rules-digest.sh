# shellcheck shell=sh
# test-aria-rules-digest.sh — drift gate for the always-on working-rules digest.
#
# The digest (rules/aria-rules.md) is loaded into every session's context. It must
# cover every rule in the canonical source, and it must be checked by NUMBER SET,
# not by count: plugin-antigravity's digest carried "34 working rules" while its
# source had 38, and a count comparison would have matched a stale total for four
# rules straight.
#
# SOURCE OF TRUTH is the plugin's own template. Never a user's installed copy —
# the maintainer's differs from the template by a personal unpromoted annotation,
# and both have exactly 38 rules, so a count check cannot catch a wrong source.

APM_ROOT="$(cd "$DIR/.." && pwd)"
SRC="$APM_ROOT/template/rules/working-rules.md"
DIGEST="$APM_ROOT/rules/aria-rules.md"

# Rule numbers present in the canonical source, sorted, comma-joined.
src_nums=$(grep '^### [0-9]' "$SRC" 2>/dev/null | sed 's/^### \([0-9]*\)\..*/\1/' | sort -n | tr '\n' ',')
# Rule numbers claimed by the digest.
dig_nums=$(grep -o '^- \*\*Rule [0-9]*' "$DIGEST" 2>/dev/null | sed 's/^- \*\*Rule //' | sort -n | tr '\n' ',')

# Positive control FIRST. Without it, the coverage assertion below is satisfied by
# two empty strings and passes while measuring nothing — a green test proving the
# source path is wrong.
assert_eq "source rule parse is non-empty" "yes" \
  "$([ -n "$src_nums" ] && echo yes || echo no)"

assert_eq "digest covers every working rule by number" "$src_nums" "$dig_nums"

# The digest is a summary, not a replacement — it must route to the full text.
assert_eq "digest points at the full rules file" "yes" \
  "$(grep -q 'rules/working-rules.md' "$DIGEST" 2>/dev/null && echo yes || echo no)"

# The digest must not carry a hardcoded rule total. That literal is exactly how
# antigravity's "34" survived four new rules.
assert_eq "digest hardcodes no rule total" "no" \
  "$(grep -qE 'enforces [0-9]+ working rules|[0-9]+ working rules' "$DIGEST" 2>/dev/null && echo yes || echo no)"

# ---------------------------------------------------------------------------
# session-start-rules.sh — the model-directed channel
# ---------------------------------------------------------------------------
# Fixture defined ONCE here and reused by every later block. The hook must never
# run against the developer's real config, or the suite is environment-dependent.
# KT_CONFIG is overridable (config.sh:5); knowledge_folder must be absolute and
# must exist, or config.sh sets KT_CONFIGURED=false and the hook exits silently.
CFG="$APM_TMP/aria-cfg.md"
KF="$APM_TMP/kf"; mkdir -p "$KF/rules"
printf -- '---\nknowledge_folder: %s\n---\n' "$KF" > "$CFG"

HOOK="$APM_ROOT/bin/session-start-rules.sh"

# ⛔ EVERY hook invocation in this file MUST set HOME. The hook writes the
# user-scope rules files under $HOME/.claude/rules/, so a test that inherits the
# real HOME mutates the developer's own configuration — measured: an early version
# of this suite created a 20,623 B ~/.claude/rules/aria-rules.md on a plain test
# run, installing unreviewed prose into a live config.
APM_HOME="$APM_TMP/apm-home"; mkdir -p "$APM_HOME/.claude"

# Snapshot the REAL user config so the guard at the end of this file can prove the
# suite did not touch it. Recorded as existence + size + mtime rather than
# "absent", because once this feature ships the developer legitimately HAS these
# files and an absence assertion would be wrong for everyone who installed it.
APM_REAL_HOME="$HOME"
apm_real_rules_state() {
  for f in "$APM_REAL_HOME"/.claude/rules/aria-rules.md \
           "$APM_REAL_HOME"/.claude/rules/aria-user-rules.md; do
    if [ -f "$f" ]; then printf '%s:%s:%s\n' "$f" "$(wc -c < "$f" | tr -d ' ')" "$(ls -l "$f" | awk '{print $6,$7,$8}')"
    else printf '%s:absent\n' "$f"; fi
  done
}
APM_REAL_BEFORE=$(apm_real_rules_state)
OUT="$APM_TMP/ssr-out.json"
: > "$OUT"
# run.sh uses `set -eu` and SOURCES each test, so a bare failing invocation
# aborts the entire suite with no summary — which reads as "no output" rather
# than as a red test. An if-condition suspends set -e for the command.
if HOME="$APM_HOME" KT_CONFIG="$CFG" sh "$HOOK" > "$OUT" 2>/dev/null; then rc=0; else rc=$?; fi

assert_eq "hook exits 0" "0" "$rc"
assert_eq "emits additionalContext" "yes" \
  "$(grep -q 'additionalContext' "$OUT" 2>/dev/null && echo yes || echo no)"
assert_eq "does NOT emit systemMessage" "no" \
  "$(grep -q 'systemMessage' "$OUT" 2>/dev/null && echo yes || echo no)"
assert_eq "payload is valid JSON" "yes" \
  "$(jq -e . "$OUT" >/dev/null 2>&1 && echo yes || echo no)"
assert_eq "payload carries a digest rule line" "yes" \
  "$(jq -r '.hookSpecificOutput.additionalContext' "$OUT" 2>/dev/null | grep -q 'Rule 13' && echo yes || echo no)"
assert_eq "payload carries RULE 22 ORDERING" "yes" \
  "$(jq -r '.hookSpecificOutput.additionalContext' "$OUT" 2>/dev/null | grep -q 'RULE 22 ORDERING' && echo yes || echo no)"

# Structure preservation. config.sh's kt_json_escape ends with `tr '\n' ' '` — it
# STRIPS newlines, which is correct for the single-paragraph directives it was
# written for and wrong for a 38-line document. Assert on the DECODED value, not
# the raw file: grepping raw JSON for a literal backslash-n passes on an
# escaped-but-broken payload. Decoding is what proves a consumer sees structure.
SSR_LINES=$(jq -r '.hookSpecificOutput.additionalContext' "$OUT" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "digest structure survives escaping" "yes" \
  "$([ "${SSR_LINES:-0}" -gt 20 ] && echo yes || echo no)"

# Zero U-rules must emit no index — the brand-new-user case, pinned against
# regression. The fixture's knowledge folder has no user-rules.md at all.
assert_eq "no U-rule index when user-rules.md is absent" "no" \
  "$(jq -r '.hookSpecificOutput.additionalContext' "$OUT" 2>/dev/null | grep -q 'STANDING USER RULES' && echo yes || echo no)"

# ---------------------------------------------------------------------------
# Unit 2 — opt-in directives, gated
# ---------------------------------------------------------------------------
# Each block is asserted in BOTH directions. A present-only assertion passes
# against an ungated block, which is the vacuous form this suite exists to avoid.
U2OUT="$APM_TMP/u2.json"
run_hook_with() { # $1 = extra config lines
  printf -- '---\nknowledge_folder: %s\n%s\n---\n' "$KF" "$1" > "$CFG"
  : > "$U2OUT"
  if HOME="$APM_HOME" KT_CONFIG="$CFG" sh "$HOOK" > "$U2OUT" 2>/dev/null; then :; else :; fi
}
u2_has() { jq -r '.hookSpecificOutput.additionalContext' "$U2OUT" 2>/dev/null | grep -q "$1" && echo yes || echo no; }

digest_has() { grep -qF "$1" "$DIGEST" && echo yes || echo no; }

# ⛔ THE GATING GUARANTEE CHANGED SHAPE, AND THAT IS A REAL TRADE, NOT A BUG.
# Before the file/hook split the shell DECIDED: a directive gated off simply was
# not emitted, and the assertions below proved it by its absence. Now the file
# carries every variant unconditionally and states each condition, and the hook
# emits only the resolved values — so the model, not the shell, does the gating.
# Enforcement moved from mechanical to instructed. That is inherent to delivering
# through a static file (a file written once cannot vary by config), and it is the
# cost side of the trade that buys full delivery and subagent reach.
#
# ⚠ So the old assertions cannot simply be re-pointed: "directive absent from the
# emission" is now TRUE FOR EVERY CONFIG, because no directive is ever emitted.
# They would pass forever, for the wrong reason — the tautology class this suite
# exists to catch. Each is replaced by the two halves that are still falsifiable:
#   (1) the FILE carries every variant, so the model has something to select from;
#   (2) the EMISSION reports the value, so the model can tell which one applies.
# Neither half alone is sufficient and both can fail independently.

assert_eq "digest carries the balanced DECISION ROUTING variant" "yes" \
  "$(digest_has 'DECISION ROUTING (balanced)')"
assert_eq "digest carries the autonomous DECISION ROUTING variant" "yes" \
  "$(digest_has 'DECISION ROUTING (autonomous)')"
assert_eq "digest states the default-autonomy case explicitly" "yes" \
  "$(digest_has 'no routing directive applies')"

run_hook_with "autonomy: default"
assert_eq "config line reports autonomy=default" "yes" "$(u2_has 'autonomy=default')"
run_hook_with "autonomy: balanced"
assert_eq "config line reports autonomy=balanced" "yes" "$(u2_has 'autonomy=balanced')"
assert_eq "config line does not report a stale autonomy" "no" "$(u2_has 'autonomy=autonomous')"
run_hook_with "autonomy: autonomous"
assert_eq "config line reports autonomy=autonomous" "yes" "$(u2_has 'autonomy=autonomous')"

assert_eq "digest carries the SESSION STATE directive" "yes" "$(digest_has 'SESSION STATE —')"
run_hook_with "session_state: false"
assert_eq "config line reports session_state=false" "yes" "$(u2_has 'session_state=false')"
run_hook_with "session_state: true"
assert_eq "config line reports session_state=true" "yes" "$(u2_has 'session_state=true')"

# SUPERSEDED by the Task 7 ruling, kept as a record rather than deleted.
#
# This originally asserted the TASK BUDGET long variant must NEVER appear here,
# because it instructed the model to gate stopping and wrap-up decisions on
# usage figures. That was the right assertion under the then-current plan, which
# left the variant untouched at its source. The ruling changed: the variant is
# now REWORKED and delivered, keeping the snapshot for answering a usage
# question while removing the directive to decide from it.
#
# The invariant that actually matters is asserted below, at the Unit 1 block —
# the delivered text must not tell the model to decide from usage. Asserting
# absence of the snapshot PATH would now fail for the right behaviour.

# The stateful Unit-2 blocks must NOT be copied here.
#
# The tracked-artifacts block records to the session ledger. Multiple callers of
# kt_artifact_record_ledger are the DESIGN — three hooks already do it, on
# different triggers, and kt_artifact_filter_ledger dedups before each records.
# The hazard is specific to putting it in a SECOND SessionStart hook: both would
# fire at the same trigger, the first to run would record the paths, and the
# second would filter them out and emit nothing. Which channel receives the
# directive would then depend on hook execution order — silently, with no error.
#
# The CODEMAP block is a separate reason: ~70 lines of staleness logic that would
# drift between two copies.
#
# Both stay in session-start-check.sh until the single-emitter collapse (spec §8).
assert_eq "new hook stays out of the ledger" "no" \
  "$(grep -q 'kt_artifact_record_ledger' "$APM_ROOT/bin/session-start-rules.sh" 2>/dev/null && echo yes || echo no)"
assert_eq "new hook does not duplicate CODEMAP staleness logic" "no" \
  "$(grep -q 'CODEMAP Found' "$APM_ROOT/bin/session-start-rules.sh" 2>/dev/null && echo yes || echo no)"

# ---------------------------------------------------------------------------
# Compaction — an always-on rule stops being always-on when context is wiped
# ---------------------------------------------------------------------------
printf -- '---\nknowledge_folder: %s\n---\n' "$KF" > "$CFG"
PCOUT="$APM_TMP/pc.json"
: > "$PCOUT"
if printf '{"session_id":"test-sess"}' | KT_CONFIG="$CFG" sh "$APM_ROOT/bin/post-compact-check.sh" > "$PCOUT" 2>/dev/null; then :; else :; fi

assert_eq "post-compact emits valid JSON" "yes" \
  "$(jq -e . "$PCOUT" >/dev/null 2>&1 && echo yes || echo no)"
assert_eq "post-compact re-injects the digest" "yes" \
  "$(jq -r '.hookSpecificOutput.additionalContext' "$PCOUT" 2>/dev/null | grep -q 'Rule 13' && echo yes || echo no)"
# Same structure hazard as the SessionStart payload: post-compact-check.sh also
# uses kt_json_escape, which strips newlines.
PC_LINES=$(jq -r '.hookSpecificOutput.additionalContext' "$PCOUT" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "post-compact digest keeps its structure" "yes" \
  "$([ "${PC_LINES:-0}" -gt 20 ] && echo yes || echo no)"

# The multiline escape must live in ONE place. Duplicating it into a second
# hook is the drift hazard refused for the CODEMAP block; it belongs in
# config.sh as a new shared helper, leaving kt_json_escape untouched.
assert_eq "multiline escape is defined exactly once" "1" \
  "$(grep -rl '^kt_json_escape_multiline()' "$APM_ROOT/bin" 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "multiline escape lives in config.sh (shared, not per-hook)" "yes" \
  "$(grep -q '^kt_json_escape_multiline()' "$APM_ROOT/bin/config.sh" 2>/dev/null && echo yes || echo no)"
# The existing helper must NOT be changed — four other hooks depend on its
# newline-stripping behaviour. This asserts the tr stage is still present.
assert_eq "shared kt_json_escape still strips newlines (unchanged)" "yes" \
  "$(sed -n '/^kt_json_escape()/,/^}/p' "$APM_ROOT/bin/config.sh" | grep -qF "tr '" && echo yes || echo no)"

# ---------------------------------------------------------------------------
# /setup — the rules pointer offer (structural; runtime behaviour is a skill
# instruction, not code, so these assert the instruction says the right thing)
# ---------------------------------------------------------------------------
SETUP="$APM_ROOT/skills/setup/SKILL.md"
assert_eq "setup offers a rules pointer" "yes" \
  "$(grep -q 'Step 7f: Rules Pointer' "$SETUP" 2>/dev/null && echo yes || echo no)"
assert_eq "rules pointer defaults to NO" "yes" \
  "$(grep -q 'Rules Pointer (optional, default NO)' "$SETUP" 2>/dev/null && echo yes || echo no)"
assert_eq "rules pointer uses ls-files, not check-ignore" "yes" \
  "$(sed -n '/## Step 7f/,/## Step 8/p' "$SETUP" | grep -q 'ls-files --error-unmatch' && echo yes || echo no)"
# The ADR this narrows must not silently contradict itself (Rule 21).
assert_eq "the deferral ADR carries its amendment" "yes" \
  "$(grep -q 'Amended 2026-08-26 — narrowed, not reversed' "$SETUP" 2>/dev/null && echo yes || echo no)"

# ---------------------------------------------------------------------------
# index.md — ship the skeleton, and gate on tag CONTENT rather than existence
# ---------------------------------------------------------------------------
# These are coupled on purpose. Shipping the template alone would make the old
# `[ -f index.md ]` gate pass on day one and spend ~223 tok/session describing a
# matching procedure that cannot match anything until tags exist.
assert_eq "template ships an index.md skeleton" "yes" \
  "$([ -f "$APM_ROOT/template/index.md" ] && echo yes || echo no)"
assert_eq "template index has a Tag Index heading" "yes" \
  "$(grep -q '^## Tag Index' "$APM_ROOT/template/index.md" 2>/dev/null && echo yes || echo no)"
assert_eq "template index has zero tag sections" "0" \
  "$(grep -c '^### ' "$APM_ROOT/template/index.md" 2>/dev/null | tr -d ' ')"

IDXF="$KF/index.md"
printf -- '---\nknowledge_folder: %s\n---\n' "$KF" > "$CFG"

# ⚠ Same shape change as DECISION ROUTING above: the shell no longer gates this,
# so both of the old arms ("absent with zero tags" / "present with a tag") are now
# emission-independent and would pass for the wrong reason. The tag-content
# condition still exists — it moved into the file's stated conditional, where the
# MODEL evaluates it against the index it is told to read. What stays falsifiable
# is that the file names the condition precisely enough to be evaluated.
rm -f "$IDXF"
assert_eq "digest carries the ACTIVE CONTEXT directive" "yes" \
  "$(digest_has 'ARIA ACTIVE CONTEXT —')"
assert_eq "digest states the tag-content condition, not mere existence" "yes" \
  "$(digest_has 'holds at least one `### ` tag header')"
assert_eq "digest names the active_surfacing key the condition reads" "yes" \
  "$(digest_has 'When `active_surfacing` is `true`')"

# audit-knowledge must warn when its rebuild produces a tagless index, because
# after the gate change that silently keeps active surfacing switched off.
assert_eq "audit-knowledge notes a zero-tag rebuild" "yes" \
  "$(grep -q 'Active knowledge surfacing stays off until' "$APM_ROOT/skills/audit-knowledge/SKILL.md" 2>/dev/null && echo yes || echo no)"
assert_eq "setup populates the index" "yes" \
  "$(grep -q 'Step 7g: Populate the Knowledge Index' "$SETUP" 2>/dev/null && echo yes || echo no)"

# ---------------------------------------------------------------------------
# Unit 1 completeness + the TASK BUDGET rework
# ---------------------------------------------------------------------------
printf -- '---\nknowledge_folder: %s\n---\n' "$KF" > "$CFG"

# ⛔ These assert the DIGEST, not an emission, and the reason is not just the split.
# The old versions passed only because their FAKEHOME happened to be fresh on the
# first invocation and therefore took the transitional arm; the second invocation
# found the file the first had written and took the steady-state arm, which emits
# no directive text at all. So they were order-dependent — reordering the file
# would have broken them, and the breakage would have read as a regression in the
# hook. Asserting the digest removes the ordering variable entirely.
assert_eq "digest carries TASK BUDGET" "yes" "$(digest_has 'TASK BUDGET —')"
assert_eq "digest carries INSIGHT CAPTURE" "yes" "$(digest_has 'INSIGHT CAPTURE —')"
assert_eq "digest carries MEMORY PATHWAY" "yes" "$(digest_has 'MEMORY PATHWAY —')"

# Latent defects that only became visible once the channel was actually read.
# Both are absence assertions over a file that demonstrably has content, so
# neither can pass by the payload being empty.
assert_eq "INSIGHT CAPTURE renders a star, not an escape sequence" "no" \
  "$(digest_has 'xe2\x98')"
assert_eq "MEMORY PATHWAY does not route to the archived /clip" "no" \
  "$(grep -qF '/clip)' "$DIGEST" && echo yes || echo no)"

# BOTH TASK BUDGET variants must be present, because the model — not the shell —
# now picks between them from the stated condition. Under the old design only one
# could ever be emitted, so "both present" was not even expressible.
assert_eq "digest carries the SHORT TASK BUDGET variant" "yes" \
  "$(digest_has 'assume depletion')"
assert_eq "digest carries the LONG TASK BUDGET variant" "yes" \
  "$(digest_has 'aria-statusline-state')"
assert_eq "digest states the statusline condition for choosing between them" "yes" \
  "$(digest_has 'If a usage snapshot exists')"

# The Task 7 rework, still load-bearing: the long variant must NOT tell the model
# to gate stopping or wrap-up on usage figures, and must say the decision is the
# user's. Delivering the pre-rework text verbatim would CAUSE a behaviour the
# maintainer has repeatedly corrected.
assert_eq "long variant does not gate stopping on usage" "no" \
  "$(digest_has 'judging whether to keep going')"
assert_eq "long variant says the decision is the user's" "yes" \
  "$(digest_has 'that decision is the user')"

# The defective text must not survive in the old hook either — leaving it there
# keeps a corrected behaviour one channel-flip away from returning.
assert_eq "old hook no longer carries the harmful directive" "no" \
  "$(grep -q 'judging whether to keep going' "$APM_ROOT/bin/session-start-check.sh" && echo yes || echo no)"

# auto_capture=false must suppress INSIGHT CAPTURE (both directions).
run_hook_with "auto_capture: false"
assert_eq "INSIGHT CAPTURE suppressed when auto_capture is false" "no" "$(u2_has 'INSIGHT CAPTURE')"

# ---------------------------------------------------------------------------
# /setup discoverability (structural — skill instructions, not code)
# ---------------------------------------------------------------------------
assert_eq "setup reports which features are off" "yes" \
  "$(grep -q 'Step 7h: Report What Is Off' "$SETUP" 2>/dev/null && echo yes || echo no)"
assert_eq "the off-report changes no defaults" "yes" \
  "$(sed -n '/## Step 7h/,/## Step 8/p' "$SETUP" | grep -q 'Changes no defaults' && echo yes || echo no)"
assert_eq "advanced options note the settings now have effect" "yes" \
  "$(grep -q 'These now have a visible effect' "$SETUP" 2>/dev/null && echo yes || echo no)"

# AC11 — pins existing behaviour: /setup must keep writing all five session and
# project keys. Finding this already true is the expected result; it guards
# against a later edit dropping one from the Step 6 block.
for k in projects_enabled auto_load_project_context session_start_project_picker session_state autonomy; do
  assert_eq "setup writes ${k}" "yes" \
    "$(grep -q "^${k}: \[" "$SETUP" 2>/dev/null && echo yes || echo no)"
done

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# lib-user-rules.sh — the extracted U-rule index builder
# ---------------------------------------------------------------------------
# The extraction was validated at the time by a byte-identity oracle against the
# pre-extraction hook. That oracle CANNOT survive the commit — the thing it
# compared against stops existing — so these assert the durable property instead:
# the contract each tier must satisfy. Mutation-checked (changing the join
# separator killed the original oracle).

UR_LIB="$APM_ROOT/bin/lib-user-rules.sh"
assert_eq "lib-user-rules.sh exists" "yes" "$([ -f "$UR_LIB" ] && echo yes || echo no)"

# Driver: sets KT_KNOWLEDGE_FOLDER, sources the lib, prints the block verbatim.
# Printed with printf %s so the leading/trailing newlines survive into the file.
# $2 optionally pins KT_USER_RULES_MAX so the tier boundary is driven directly
# rather than inferred from "enough rules to exceed the default" — a fixture that
# has to out-grow a 20,000-char bound is slow, and it silently stops testing the
# boundary the day the default moves.
ur_block() {
  KT_KNOWLEDGE_FOLDER="$1" KT_USER_RULES_MAX="${2:-}" sh -c '
    KT_KNOWLEDGE_FOLDER="$KT_KNOWLEDGE_FOLDER"
    [ -n "$KT_USER_RULES_MAX" ] || unset KT_USER_RULES_MAX
    . "$1"
    kt_user_rules_block
    printf "%s" "$KT_USER_RULES_BLOCK"
  ' _ "$UR_LIB"
}

# --- tier 1: inline index ---
# Header form is the canonical one the real corpus uses: '### U<n>. <title>'.
# Each rule gets a body paragraph AND an '**Origin:' block, so the fixture exercises
# both the summary extraction and the provenance skip rather than only the happy path.
URK="$APM_TMP/ur-inline"; mkdir -p "$URK/rules"
i=1; while [ "$i" -le 5 ]; do
  printf '### U%s. a short title\n\nThe body of rule %s, which is the sentence the digest should carry.\n\n**Origin:** 2026-01-01 — provenance that must NOT be summarised.\n\n' \
    "$i" "$i" >> "$URK/rules/user-rules.md"; i=$((i+1))
done
UB=$(ur_block "$URK")
assert_eq "U-rules inline tier names the count" "yes" \
  "$(printf '%s' "$UB" | grep -q 'STANDING USER RULES (5,' && echo yes || echo no)"
assert_eq "U-rules digest renders one line per rule" "5" \
  "$(printf '%s\n' "$UB" | grep -c '^- \*\*U')"
assert_eq "U-rules digest carries each rule's summary, not just its title" "yes" \
  "$(printf '%s' "$UB" | grep -q 'U1 — a short title\*\* — The body of rule 1' && echo yes || echo no)"
# The provenance block records how a rule came to exist, not what it asks of you.
# Without this, a rule whose body is only an Origin block would summarise as its own
# changelog — plausible-looking output that is the wrong content entirely.
assert_eq "U-rules digest skips the Origin provenance block" "no" \
  "$(printf '%s' "$UB" | grep -q 'provenance that must NOT be summarised' && echo yes || echo no)"
assert_eq "U-rules inline tier is NOT the pointer variant" "no" \
  "$(printf '%s' "$UB" | grep -q 'too many to index inline' && echo yes || echo no)"

# --- the concatenation contract ---
# The block carries its own leading AND trailing newline, because the inline
# version it replaced was written as  MESSAGES="${MESSAGES}\n<text>\n".  A
# refactor that trims either one runs the directives together with no error and
# no failing assertion anywhere else — which is exactly why it is pinned here.
UB_RAW=$(ur_block "$URK" | od -c | head -1)
assert_eq "U-rules block opens with a newline" "yes" \
  "$(ur_block "$URK" | head -c 1 | od -An -c | tr -d ' ' | grep -q '\\n' && echo yes || echo no)"
assert_eq "U-rules block closes with a newline" "yes" \
  "$(ur_block "$URK" | tail -c 1 | od -An -c | tr -d ' ' | grep -q '\\n' && echo yes || echo no)"

# --- tier 2: overflow pointer, above 3000 chars of joined titles ---
UBO=$(ur_block "$URK" 100)
assert_eq "U-rules overflow tier fires above KT_USER_RULES_MAX" "yes" \
  "$(printf '%s' "$UBO" | grep -q 'too many to summarise inline' && echo yes || echo no)"
assert_eq "U-rules overflow tier still names the count" "yes" \
  "$(printf '%s' "$UBO" | grep -q 'STANDING USER RULES — 5 of' && echo yes || echo no)"
# Same corpus, default threshold: the digest must fire. Without this pair the
# overflow assertion above would pass just as well against a lib that ALWAYS
# returns the pointer — the tier boundary is only tested by driving both sides.
assert_eq "U-rules same corpus under the default threshold gives the digest" "no" \
  "$(printf '%s' "$(ur_block "$URK")" | grep -q 'too many to summarise inline' && echo yes || echo no)"

# --- the two zero cases: inject NOTHING, which is correct for a new user ---
URZ="$APM_TMP/ur-zero"; mkdir -p "$URZ/rules"
printf '# User rules\n\nprose, no headers\n' > "$URZ/rules/user-rules.md"
assert_eq "U-rules with zero headers emits nothing" "" "$(ur_block "$URZ")"
URN="$APM_TMP/ur-nofile"; mkdir -p "$URN/rules"
assert_eq "U-rules with no file emits nothing" "" "$(ur_block "$URN")"

# ---------------------------------------------------------------------------
# THE TWO ARMS — no flag day
# ---------------------------------------------------------------------------
# The hook branches on whether the user-scope digest existed BEFORE it ran, because
# §10.6 measured that the instruction-file set is snapshotted at session start: a
# file this hook writes is not delivered until the NEXT session. So the first
# session after install must still receive everything through the emission.
#
# ⛔ Both arms are required and the transitional one is the load-bearing half. An
# earlier version of this hook tested presence AFTER the ensure step, which made
# the transitional arm unreachable whenever the write succeeded — measured, that
# session emitted 270 characters and 0 of 38 rules. A steady-state-only test is
# green against exactly that defect.
ARMH="$APM_TMP/arm-home"; rm -rf "$ARMH"; mkdir -p "$ARMH/.claude"
ARMKF="$APM_TMP/arm-kf"; mkdir -p "$ARMKF/rules"
printf '### U1. an arm-fixture rule\n\nThe body of the arm-fixture rule.\n' > "$ARMKF/rules/user-rules.md"
ARMCFG="$APM_TMP/arm-cfg.md"
printf -- '---\nknowledge_folder: %s\nautonomy: autonomous\nsession_state: true\n---\n' "$ARMKF" > "$ARMCFG"
arm_run() { HOME="$ARMH" KT_CONFIG="$ARMCFG" sh "$HOOK" 2>/dev/null \
  | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null; }

ARM1=$(arm_run)   # file absent at snapshot -> transitional
ARM2=$(arm_run)   # file now present        -> steady state

# ⚠ Standalone case, NOT nested in $( ). A case pattern's `)` is ambiguous with
# the command-substitution terminator, so the inline form mis-parses and the
# assertion fails while the payload is in fact correct — verified: the emission
# does begin with these bytes.
case "$ARM1" in
  "ARIA WORKING RULES"*) ARM1_LEADS=yes ;;
  *) ARM1_LEADS=no ;;
esac
assert_eq "arm 1 leads with the rules digest" "yes" "$ARM1_LEADS"
# ⚠ Derived HERE, not borrowed from the DELIVERY GUARD block below — that block
# defines its needle later in the file, so referencing it from here would compare
# against an EMPTY string, and `grep -qF ''` matches anything. Positive control
# first, for the same reason.
ARM_LAST_RULE=$(grep -o '^- \*\*Rule [0-9]* — [^*]*\*\*' "$DIGEST" 2>/dev/null \
  | tail -1 | sed 's/^- \*\*//; s/\*\*$//')
assert_eq "arm-block last-rule needle parses non-empty" "yes" \
  "$([ -n "$ARM_LAST_RULE" ] && echo yes || echo no)"
assert_eq "arm 1 delivers the LAST rule title" "yes" \
  "$(printf '%s' "$ARM1" | grep -qF "$ARM_LAST_RULE" && echo yes || echo no)"
assert_eq "arm 1 delivers a standing directive" "yes" \
  "$(printf '%s' "$ARM1" | grep -qF 'RULE 22 ORDERING —' && echo yes || echo no)"
assert_eq "arm 1 delivers the user's own rules" "yes" \
  "$(printf '%s' "$ARM1" | grep -qF 'an arm-fixture rule' && echo yes || echo no)"
assert_eq "arm 1 carries the config line" "yes" \
  "$(printf '%s' "$ARM1" | grep -qF 'ARIA CONFIG —' && echo yes || echo no)"

assert_eq "arm 2 does not duplicate the digest" "no" \
  "$(printf '%s' "$ARM2" | grep -qF 'RULE 22 ORDERING —' && echo yes || echo no)"
assert_eq "arm 2 still carries the config line" "yes" \
  "$(printf '%s' "$ARM2" | grep -qF 'ARIA CONFIG —' && echo yes || echo no)"
assert_eq "arm 2 is far smaller than arm 1" "yes" \
  "$([ "$(printf '%s' "$ARM2" | wc -c)" -lt "$(( $(printf '%s' "$ARM1" | wc -c) / 10 ))" ] && echo yes || echo no)"

# The ensure step must have produced BOTH files, or the file channel — the whole
# point of the split, and the only channel that reaches subagents — is empty.
assert_eq "ensure step wrote the digest to user scope" "yes" \
  "$([ -f "$ARMH/.claude/rules/aria-rules.md" ] && echo yes || echo no)"
assert_eq "ensure step wrote the user-rule digest to user scope" "yes" \
  "$([ -f "$ARMH/.claude/rules/aria-user-rules.md" ] && echo yes || echo no)"
assert_eq "installed digest matches the bundled one byte for byte" "yes" \
  "$(cmp -s "$DIGEST" "$ARMH/.claude/rules/aria-rules.md" && echo yes || echo no)"
assert_eq "installed user-rule digest carries the user's rule" "yes" \
  "$(grep -qF 'an arm-fixture rule' "$ARMH/.claude/rules/aria-user-rules.md" && echo yes || echo no)"

# ---------------------------------------------------------------------------
# THE SUITE MUST NOT TOUCH THE DEVELOPER'S OWN CONFIG
# ---------------------------------------------------------------------------
# This hook WRITES to $HOME/.claude/rules/. Measured: before every invocation in
# this file set a fixture HOME, a plain test run created a 20,623 B
# ~/.claude/rules/aria-rules.md in the maintainer's live config — installing
# unreviewed prose that every future session would then load.
#
# Compared as existence+size+mtime rather than asserting absence, because once
# this ships the developer legitimately HAS these files.
assert_eq "the suite left the real ~/.claude/rules untouched" "$APM_REAL_BEFORE" \
  "$(apm_real_rules_state)"

# DELIVERY GUARD — the payload must ARRIVE, not merely be emitted
# ---------------------------------------------------------------------------
# Added 2026-08-26 (spec 2.6 and 7/AC1, both amended the same day).
#
# Every assertion above this line inspects the hook's STDOUT. That is exactly why
# this file stayed green through 42 sessions in which the harness discarded 90% of
# the payload before it reached model context: emission was never the failure,
# delivery was. Two assertions above look like coverage and are not — one greps
# "Rule 13", the other "RULE 22 ORDERING" which sits ~14k characters in. Both are
# present in the emission. Neither reaches context.
#
# PROXY, named as one, because an unlabelled proxy becomes a claim. These measure
# what the hook EMITS. The real outcome test is AC1 — classify a fresh session's
# hook_additional_context record and confirm the LAST rule title survived. This
# suite never sees a transcript and cannot run it.
#
# The ceiling is a downward-only RATCHET, not a target. Read out of cli 2.1.245:
#   threshold = min(tool.maxResultSizeChars, ceiling)
# with a per-tool override map behind the server gate "tengu_velvet_ibis". The
# real cap is therefore PER-TOOL and REMOTELY MUTABLE, so no payload may be sized
# against it and locating it exactly would not make a hook design safe. The goal
# is 3,321 ch — the only size measured to cross this channel intact. Lower this
# baseline as the file/hook split lands. NEVER raise it.
#
# ⚠ 20,322 -> 20,311 on 2026-08-26 is a CHANGE OF MEASURING UNIT, NOT a smaller
# payload. Nothing about the emission changed. The old figure counted the real
# home path (/Users/mikeprasad, 17 ch) literally because only $kf was normalised;
# the new one substitutes the 6-char <HOME> token, so 20,322 - 17 + 6 = 20,311.
# Do not read the drop as progress, and do not "restore" 20,322.
#
# It is now DETERMINISTIC across machines, which it was not before. Proven by
# construction rather than asserted: at home/kf path lengths of 67, 99 and 116 the
# RAW length moves (20,561 / 20,689 / 20,757) while the normalised length is
# 20,311 in all three.
# ⛔ RE-SCOPED 2026-08-26. This was a downward-only ratchet on the emission's SIZE.
# That is a PROXY, and this arc's own audit falsified it: the harness delivers the
# first K5=2000 characters, so what reaches the model is unchanged whether the
# payload is 20,311 or 26,144 — measured, 2 of 38 rules arrive in both cases. The
# number moved and the outcome did not, which is the definition of a proxy that has
# stopped tracking its subject.
#
# ⛔ It is NOT raised to accommodate growth — that is the creep this guard existed to
# stop. It is REPLACED by an assertion on the outcome it was standing in for: does the
# rules digest still LEAD the payload, so that the delivered prefix is rules rather
# than a directive? That is testable today and survives the file/hook split, where the
# hook's arm becomes a one-session transitional courtesy that is truncated regardless.
#
# What remains below is a RUNAWAY CATCH, not a delivery guarantee. It exists to fail
# if something inlines a whole file — a mature user-rules.md is 66 KB — and is set
# above the split's expected end state (~33 KB: digest + directives + U-rule digest).
# Do not read it as a budget, and do not tighten it into one: a tight bound here would
# again gate ruled capability changes on a number that does not track delivery.
ARIA_EMIT_RUNAWAY=40000

# The needle: the LAST rule title, derived from the digest, never hardcoded — a
# literal would keep passing after rule 39 is added, which is the same failure
# mode as antigravity's hardcoded "34".
LAST_RULE_TITLE=$(grep -o '^- \*\*Rule [0-9]* — [^*]*\*\*' "$DIGEST" 2>/dev/null \
  | tail -1 | sed 's/^- \*\*//; s/\*\*$//')

# Positive control FIRST. An empty needle makes every grep below match, so
# without this the whole guard is satisfied by a broken extraction.
assert_eq "last-rule-title needle parses non-empty" "yes" \
  "$([ -n "$LAST_RULE_TITLE" ] && echo yes || echo no)"

# WORST-CASE fixture: every conditional block on at once. Built from the in-repo
# template plus synthesised U-rules — never the developer's real knowledge folder,
# which would make the ceiling environment-dependent. 40 headers keeps the inlined
# index under the hook's own 3000-ch branch point, so the LONG (larger) U-rule
# variant fires rather than the count-only one.
KFW="$APM_TMP/kfw"; mkdir -p "$KFW/rules"
: > "$KFW/rules/user-rules.md"
urn=1
while [ "$urn" -le 40 ]; do
  printf '### U%s — a representative user rule title of realistic length\n' "$urn" \
    >> "$KFW/rules/user-rules.md"
  urn=$((urn+1))
done
printf '# Index\n\n## Tag Index\n\n### aria\n- a.md\n\n### cs\n- b.md\n' > "$KFW/index.md"
# The fixture must own $HOME too, not just the knowledge folder. session-start-rules.sh:83
# branches on `ls "$HOME"/.claude/aria-statusline-state-*.json`, so on a machine without the
# status-line meter the SHORT TASK BUDGET variant fires and the worst case is 403 ch smaller —
# measured 20,322 with a real home vs 19,919 with an empty one. A ratchet that moves with the
# developer's machine is not a ratchet. Own home + a stub snapshot pins the LONG variant.
# ⚠ A DEDICATED home, deliberately not the $FAKEHOME above: that one only gains its stub at
# line ~249, so reusing it would make this fixture's variant depend on assertion ORDER.
HOMEW="$APM_TMP/homew"; mkdir -p "$HOMEW/.claude"
: > "$HOMEW/.claude/aria-statusline-state-worst.json"
CFGW="$APM_TMP/aria-cfg-worst.md"
printf -- '---\nknowledge_folder: %s\nautonomy: autonomous\nsession_state: true\n---\n' \
  "$KFW" > "$CFGW"
OUTW="$APM_TMP/ssr-worst.json"
: > "$OUTW"
if HOME="$HOMEW" KT_CONFIG="$CFGW" sh "$HOOK" > "$OUTW" 2>/dev/null; then :; else :; fi
PW=$(jq -r '.hookSpecificOutput.additionalContext' "$OUTW" 2>/dev/null || echo '')

# Prove the fixture is actually maximal. Without this the size assertion below
# passes trivially on a fixture that emitted half the blocks.
assert_eq "worst-case fixture fires the LONG U-rule variant" "no" \
  "$(printf '%s' "$PW" | grep -q 'too many to index inline' && echo yes || echo no)"
# Sibling of the line above, and it was missing. A maximality proof must cover EVERY branch
# that changes size, or the ceiling bounds a payload never shown to be maximal — the U-rule
# branch was proven and the TASK BUDGET branch was not, which is
# `feedback_guard_scoped_to_the_wrong_unit` inside the guard written to prevent that class.
# The SHORT variant's opening phrase must be ABSENT; the block-presence loop below proves the
# block is there at all, so absence-of-short plus presence-of-block pins the LONG variant.
# ⛔ RETIRED — and the reason is worth keeping, because it looks like a regression.
# This asserted the fixture selected the LONG TASK BUDGET variant, which mattered
# while the HOOK chose between the two: the choice moved the payload by 403 chars
# and made the ceiling machine-dependent. The hook no longer emits TASK BUDGET at
# all — the digest carries BOTH variants and the model picks from a stated
# condition — so there is no selection left to prove maximal, and the emission
# now legitimately contains the short variant's text too.
# Its replacement is "digest carries the SHORT/LONG TASK BUDGET variant" above.
# ⚠ The fixture's own HOME control is KEPT and is now load-bearing for a different
# reason than it was written for: the hook WRITES under $HOME/.claude/rules/, so an
# uncontrolled HOME mutates the developer's live config.
for blk in 'RULE 22 ORDERING' 'DECISION ROUTING' 'SESSION STATE' 'TASK BUDGET' 'ARIA ACTIVE CONTEXT' 'STANDING USER RULES'; do
  assert_eq "worst-case fixture carries ${blk}" "yes" \
    "$(printf '%s' "$PW" | grep -qF "$blk" && echo yes || echo no)"
done

# The two assertions that are the point of this block.
# Length must be PATH- and LOCALE-normalised, or the ceiling is not measuring the
# payload. The payload interpolates the knowledge-folder path 3 times, so a raw
# count moves with the temp-dir path length: measured 21,074 at a 144-char path
# vs 20,942 at 100 (exactly 3x the 44-char difference). The FIRST version of this
# guard used a raw count and SURVIVED its own mutation, because mktemp's path
# happened to put the total under the ceiling. `wc -m` is no good either — under
# LC_ALL=C it counts bytes (20,942 vs 20,322). jq's literal string split is both
# path-independent and locale-independent.
# ⚠ TWO paths must be normalised, not one. The LONG TASK BUDGET variant interpolates ${HOME}
# into its TEXT, so the payload grows one char per char of home-directory path: measured
# 20,374 at a 69-char home vs 20,407 at 102 — exactly the 33-char difference, and exactly the
# same class of bug the $kf normalisation already fixes. Normalising only $kf left the ceiling
# a function of the developer's username length.
PW_CH=$(jq -r --arg kf "$KFW" --arg hm "$HOMEW" \
  '.hookSpecificOutput.additionalContext
   | (. / $kf | join("<KF>"))
   | (. / $hm | join("<HOME>"))
   | length' \
  "$OUTW" 2>/dev/null || echo 0)
assert_eq "worst-case emission stays under the runaway catch" "yes" \
  "$([ "${PW_CH:-0}" -le "$ARIA_EMIT_RUNAWAY" ] && echo yes || echo no)"

# THE ORDERING ASSERTION — what the size ceiling was standing in for.
# The harness delivers the first K5=2000 characters and discards the rest, so the
# only property that decides what the model receives is WHICH BLOCK LEADS. If a
# directive is ever prepended ahead of the digest, the payload's size will not move
# and every size-based check stays green while the delivered prefix silently stops
# being rules. Derived from the digest, never hardcoded.
FIRST_RULE_TITLE=$(grep -o '^- \*\*Rule [0-9]* — [^*]*\*\*' "$DIGEST" 2>/dev/null \
  | head -1 | sed 's/^- \*\*//; s/\*\*$//')
assert_eq "first-rule-title needle parses non-empty" "yes" \
  "$([ -n "$FIRST_RULE_TITLE" ] && echo yes || echo no)"
PW_DELIVERED=$(printf '%s' "$PW" | cut -c1-2000)
# ⚠ BEGINS-WITH, not contains — and the difference is not pedantry. The first version
# of this assertion used `grep -qF 'ARIA WORKING RULES'` and SURVIVED its mutation: a
# directive prepended ahead of the digest displaces it by only ~60 chars, so it still
# appears inside the 2000-char window and a contains-check stays green. That is the
# same vacuity as the size ceiling this block replaced, reproduced in its replacement.
# Anchoring to the start is what makes it fail for the reason it exists.
case "$PW" in
  "ARIA WORKING RULES"*) PW_LEADS=yes ;;
  *) PW_LEADS=no ;;
esac
assert_eq "the delivered prefix leads with the rules digest" "yes" "$PW_LEADS"
assert_eq "the delivered prefix reaches the first rule" "yes" \
  "$(printf '%s' "$PW_DELIVERED" | grep -qF "$FIRST_RULE_TITLE" && echo yes || echo no)"
assert_eq "worst-case emission carries the LAST rule title" "yes" \
  "$(printf '%s' "$PW" | grep -qF "$LAST_RULE_TITLE" && echo yes || echo no)"

# And the minimal path, which is what most installs actually emit.
assert_eq "minimal emission carries the LAST rule title" "yes" \
  "$(jq -r '.hookSpecificOutput.additionalContext' "$OUT" 2>/dev/null | grep -qF "$LAST_RULE_TITLE" && echo yes || echo no)"
