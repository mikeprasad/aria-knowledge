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
OUT="$APM_TMP/ssr-out.json"
: > "$OUT"
# run.sh uses `set -eu` and SOURCES each test, so a bare failing invocation
# aborts the entire suite with no summary — which reads as "no output" rather
# than as a red test. An if-condition suspends set -e for the command.
if KT_CONFIG="$CFG" sh "$HOOK" > "$OUT" 2>/dev/null; then rc=0; else rc=$?; fi

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
  if KT_CONFIG="$CFG" sh "$HOOK" > "$U2OUT" 2>/dev/null; then :; else :; fi
}
u2_has() { jq -r '.hookSpecificOutput.additionalContext' "$U2OUT" 2>/dev/null | grep -q "$1" && echo yes || echo no; }

run_hook_with "autonomy: default"
assert_eq "DECISION ROUTING absent at autonomy=default" "no" "$(u2_has 'DECISION ROUTING')"
run_hook_with "autonomy: balanced"
assert_eq "DECISION ROUTING present at autonomy=balanced" "yes" "$(u2_has 'DECISION ROUTING (balanced)')"
run_hook_with "autonomy: autonomous"
assert_eq "DECISION ROUTING present at autonomy=autonomous" "yes" "$(u2_has 'DECISION ROUTING (autonomous)')"

run_hook_with "session_state: false"
assert_eq "SESSION STATE absent when off" "no" "$(u2_has 'SESSION STATE')"
run_hook_with "session_state: true"
assert_eq "SESSION STATE present when on" "yes" "$(u2_has 'SESSION STATE')"

# The TASK BUDGET long variant must never be migrated here. It instructs the
# model to gate stopping and wrap-up decisions on usage figures — a behaviour
# the maintainer has repeatedly corrected. Task 7 reworks it at its source.
assert_eq "TASK BUDGET long variant never migrated" "no" "$(u2_has 'aria-statusline-state')"

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

# Arm A — index exists, ZERO tag sections. Must NOT emit.
printf '# Knowledge Index\n\n## Tag Index\n\n_No tags yet._\n' > "$IDXF"
: > "$U2OUT"
if KT_CONFIG="$CFG" sh "$HOOK" > "$U2OUT" 2>/dev/null; then :; else :; fi
assert_eq "ACTIVE CONTEXT absent when index has zero tags" "no" "$(u2_has 'ARIA ACTIVE CONTEXT')"

# Arm B — same file, one tag section. Must emit. Both arms are required: a
# present-only assertion passes against the un-tightened `[ -f ]` gate.
printf '# Knowledge Index\n\n## Tag Index\n\n### sometag\n- a.md — x\n' > "$IDXF"
: > "$U2OUT"
if KT_CONFIG="$CFG" sh "$HOOK" > "$U2OUT" 2>/dev/null; then :; else :; fi
assert_eq "ACTIVE CONTEXT present when index has a tag" "yes" "$(u2_has 'ARIA ACTIVE CONTEXT')"
rm -f "$IDXF"

# audit-knowledge must warn when its rebuild produces a tagless index, because
# after the gate change that silently keeps active surfacing switched off.
assert_eq "audit-knowledge notes a zero-tag rebuild" "yes" \
  "$(grep -q 'Active knowledge surfacing stays off until' "$APM_ROOT/skills/audit-knowledge/SKILL.md" 2>/dev/null && echo yes || echo no)"
assert_eq "setup populates the index" "yes" \
  "$(grep -q 'Step 7g: Populate the Knowledge Index' "$SETUP" 2>/dev/null && echo yes || echo no)"
