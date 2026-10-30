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
# session-start-check.sh — the model-directed channel (additionalContext)
# ---------------------------------------------------------------------------
# Fixture defined ONCE here and reused by every later block. The hook must never
# run against the developer's real config, or the suite is environment-dependent.
# KT_CONFIG is overridable (config.sh:5); knowledge_folder must be absolute and
# must exist, or config.sh sets KT_CONFIGURED=false and the hook exits silently.
CFG="$APM_TMP/aria-cfg.md"
KF="$APM_TMP/kf"; mkdir -p "$KF/rules"
printf -- '---\nknowledge_folder: %s\n---\n' "$KF" > "$CFG"

# The single SessionStart emitter (2026-10-25). It absorbed session-start-rules.sh, now under
# scripts/.archived/; its model payload is the additionalContext field asserted below.
HOOK="$APM_ROOT/scripts/session-start-check.sh"

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
if HOME="$APM_HOME" KT_CONFIG="$CFG" sh "$HOOK" </dev/null > "$OUT" 2>/dev/null; then rc=0; else rc=$?; fi

assert_eq "hook exits 0" "0" "$rc"
assert_eq "emits additionalContext" "yes" \
  "$(grep -q 'additionalContext' "$OUT" 2>/dev/null && echo yes || echo no)"
# The banner (systemMessage) may carry human nags; it must carry no model directive, because it
# never reaches the model. (Before 2026-10-25 this asserted the rules hook emitted no banner at all.)
assert_eq "banner carries no model directive" "no" \
  "$(jq -r '.systemMessage // ""' "$OUT" 2>/dev/null | grep -q 'RULE 22 ORDERING' && echo yes || echo no)"
assert_eq "payload is valid JSON" "yes" \
  "$(jq -e . "$OUT" >/dev/null 2>&1 && echo yes || echo no)"
# ⛔ RE-POINTED 2026-10-29 (spec 2026-10-29-rules-changed-notice). The first run on an empty
# HOME no longer inlines the digest: it installs the file and names it in an ARIA RULES notice.
# The rules are asserted where the model now reads them — the file — and the payload is asserted
# to name that file.
assert_eq "first-run payload names the installed digest" "yes" \
  "$(jq -r '.hookSpecificOutput.additionalContext' "$OUT" 2>/dev/null | grep '^ARIA RULES REFRESHED' | grep -qF "$APM_HOME/.claude/rules/aria-rules.md" && echo yes || echo no)"
assert_eq "the digest carries a rule line" "yes" \
  "$(grep -q 'Rule 13' "$DIGEST" && echo yes || echo no)"
assert_eq "the digest carries RULE 22 ORDERING" "yes" \
  "$(grep -q 'RULE 22 ORDERING' "$DIGEST" && echo yes || echo no)"

# Structure preservation. config.sh's kt_json_escape ends with `tr '\n' ' '` — it
# STRIPS newlines, which is correct for the single-paragraph directives it was
# written for and wrong for a 38-line document. Assert on the DECODED value, not
# the raw file: grepping raw JSON for a literal backslash-n passes on an
# escaped-but-broken payload. Decoding is what proves a consumer sees structure.
SSR_LINES=$(jq -r '.hookSpecificOutput.additionalContext' "$OUT" 2>/dev/null | wc -l | tr -d ' ')
# The escaping property still matters (the notice and the config line are separate lines), but
# the payload is now 2-3 lines, not a 38-line document — so assert the line break survives.
assert_eq "payload line structure survives escaping" "yes" \
  "$([ "${SSR_LINES:-0}" -ge 2 ] && echo yes || echo no)"

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
  if HOME="$APM_HOME" KT_CONFIG="$CFG" sh "$HOOK" </dev/null > "$U2OUT" 2>/dev/null; then :; else :; fi
}
u2_has() { jq -r '.hookSpecificOutput.additionalContext' "$U2OUT" 2>/dev/null | grep -q "$1" && echo yes || echo no; }

digest_has() { grep -qF "$1" "$DIGEST" && echo yes || echo no; }

# Session-start value lines (2026-10-25). The single emitter sends only VALUES
# (ARIA PROJECTS / ARIA PROJECT / ARIA CODEMAPS / ARIA USAGE); the behaviour for
# each lives here, keyed on the line having arrived. Before this, the picker,
# project-context, CODEMAP and passive-context directives existed only in the
# user-facing banner, which never reaches the model.
for _vl_needle in 'PROJECT PICKER —' '`ARIA PROJECTS`' 'PROJECT CONTEXT —' '`ARIA PROJECT`' \
                  'CODEMAP FIRST —' '`ARIA CODEMAPS`' '`ARIA USAGE`' 'ARIA CONTEXT —' \
                  'aria-active-$CLAUDE_CODE_SESSION_ID' 'never use `ls -t`'; do
  assert_eq "digest carries: $_vl_needle" "yes" "$(digest_has "$_vl_needle")"
done

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
# ⛔ RE-POINTED 2026-10-25 — the two guards here grepped session-start-rules.sh with 2>/dev/null and
# expected "no". Once that file was archived the grep failed, read "no", and both would have stayed
# green forever. The single emitter dissolves the race they guarded, so they now assert that shape:
# exactly one SessionStart command, and exactly one ledger-recording call site in it.
assert_eq "SessionStart registers exactly one command" "1" \
  "$(jq '[.hooks.SessionStart[].hooks[]] | length' "$APM_ROOT/.claude-plugin/plugin.json" 2>/dev/null)"
assert_eq "the single emitter records the tracked-artifacts ledger at one call site" "1" \
  "$(grep -c 'kt_artifact_record_ledger "' "$APM_ROOT/scripts/session-start-check.sh" 2>/dev/null)"

# ---------------------------------------------------------------------------
# Compaction — an always-on rule stops being always-on when context is wiped
# ---------------------------------------------------------------------------
# ⛔ RE-POINTED 2026-10-20. This block used to drive post-compact-check.sh and assert
# `jq -e .` on its output. That checked SYNTAX, and the harness rejects on SCHEMA:
# Claude Code's hookSpecificOutput union has no PreCompact or PostCompact variant
# (read from the 2.1.305 binary), and the docs say both events discard systemMessage.
# So every emission from either hook was rejected or dropped, and this block stayed
# green the whole time. The only channel that reaches the model after compaction is
# SessionStart with source "compact" — measured delivering mid-session (transcript
# de2876f6, 2026-10-08). The post-compact context now rides there, and these
# assertions drive that path.
CMP_SID="aria-test-compact-$$"
CMP_SID8=$(printf '%s' "$CMP_SID" | cut -c1-8)
CMP_KF="$APM_TMP/cmp-kf"; mkdir -p "$CMP_KF/rules" "$CMP_KF/intake/pre-compact-captures"
CMP_CFG="$APM_TMP/cmp-cfg.md"
printf -- '---\nknowledge_folder: %s\nactive_knowledge_surfacing: true\n---\n' "$CMP_KF" > "$CMP_CFG"
CMP_SNAP="$CMP_KF/intake/pre-compact-captures/2026-01-01_${CMP_SID8}.md"
printf 'transcript\n' > "$CMP_SNAP"
CMP_LEDGER="/tmp/aria-active-${CMP_SID}"
printf '%s\n' "$CMP_KF/approaches/example-approach.md" > "$CMP_LEDGER"
# Fixture HOME with the digest installed, because the pointer is emitted only when
# there is something to point AT.
CMP_HOME="$APM_TMP/cmp-home"; mkdir -p "$CMP_HOME/.claude/rules"
cp "$DIGEST" "$CMP_HOME/.claude/rules/aria-rules.md"
cmp_run() { # $1 = source, $2 = HOME, $3 = output file
  if printf '{"session_id":"%s","source":"%s"}' "$CMP_SID" "$1" \
    | HOME="$2" KT_CONFIG="$CMP_CFG" sh "$HOOK" > "$3" 2>/dev/null; then :; else :; fi
}
cmp_run compact "$CMP_HOME" "$APM_TMP/cmp-compact.json"
CMP_MSG=$(jq -r '.hookSpecificOutput.additionalContext' "$APM_TMP/cmp-compact.json" 2>/dev/null)

assert_eq "[CMP1] compact: output is a SessionStart hookSpecificOutput" "SessionStart" \
  "$(jq -r '.hookSpecificOutput.hookEventName' "$APM_TMP/cmp-compact.json" 2>/dev/null)"
# FIRST, not merely present: the hook channel delivers about the first 2,000
# characters, so the damage-preventing pointer must lead.
assert_eq "[CMP2] compact: the rules pointer is the first line" "yes" \
  "$(printf '%s\n' "$CMP_MSG" | head -1 | grep -q '^ARIA WORKING RULES — still in force after compaction' && echo yes || echo no)"
assert_eq "[CMP3] compact: points at the installed rules file and the user-rule digest" "yes" \
  "$(printf '%s' "$CMP_MSG" | grep -qF '.claude/rules/aria-rules.md' && printf '%s' "$CMP_MSG" | grep -qF 'aria-user-rules.md' && echo yes || echo no)"
assert_eq "[CMP4] compact: does NOT re-send the digest body" "no" \
  "$(printf '%s' "$CMP_MSG" | grep -q 'Rule 13' && echo yes || echo no)"
assert_eq "[CMP5] compact: re-surfaces the active-surfacing ledger" "yes" \
  "$(printf '%s' "$CMP_MSG" | grep -qF 'example-approach.md' && echo yes || echo no)"
assert_eq "[CMP6] compact: names THIS session's pre-compaction snapshot" "yes" \
  "$(printf '%s' "$CMP_MSG" | grep -qF "$CMP_SNAP" && echo yes || echo no)"
assert_eq "[CMP7] compact: the config line is still emitted" "yes" \
  "$(printf '%s' "$CMP_MSG" | grep -q '^ARIA CONFIG' && echo yes || echo no)"

# Negative arms. A compact block on every start would re-send post-compaction
# instructions into fresh sessions; a pointer with no installed file sends the reader
# to a missing path.
cmp_run startup "$CMP_HOME" "$APM_TMP/cmp-startup.json"
CMP_START=$(jq -r '.hookSpecificOutput.additionalContext' "$APM_TMP/cmp-startup.json" 2>/dev/null)
assert_eq "[CMP8] startup: positive control — the hook emitted" "yes" \
  "$(printf '%s' "$CMP_START" | grep -q '^ARIA CONFIG' && echo yes || echo no)"
assert_eq "[CMP9] startup: carries no post-compaction block" "no" \
  "$(printf '%s' "$CMP_START" | grep -qE 'after compaction|pre-compaction|example-approach' && echo yes || echo no)"
# The hook WRITES the digest before building the pointer, so an empty HOME does not
# produce a missing file. The real no-file case is a HOME where that write fails:
# here ~/.claude is a regular file, so ~/.claude/rules cannot be created.
CMP_RO="$APM_TMP/cmp-ro"; mkdir -p "$CMP_RO"; : > "$CMP_RO/.claude"
cmp_run compact "$CMP_RO" "$APM_TMP/cmp-ro.json"
assert_eq "[CMP10a] unwritable HOME: the digest really is absent (firing control)" "no" \
  "$([ -f "$CMP_RO/.claude/rules/aria-rules.md" ] && echo yes || echo no)"
assert_eq "[CMP10b] compact, no installed digest: no rules pointer" "no" \
  "$(jq -r '.hookSpecificOutput.additionalContext' "$APM_TMP/cmp-ro.json" 2>/dev/null | grep -q 'still in force after compaction' && echo yes || echo no)"
rm -f "$CMP_LEDGER"

# pre-compact-check.sh: the snapshot is its whole job. Anything it prints is rejected
# (hookSpecificOutput) or discarded (systemMessage), so it must print nothing — and
# must still write the snapshot, or the silence is a dead hook.
PRE_SID="aria-test-precompact-$$"
PRE_TX="$APM_TMP/pre-transcript.jsonl"; printf '{"type":"user"}\n' > "$PRE_TX"
PRE_OUT="$APM_TMP/pre-out.txt"
if printf '{"session_id":"%s","transcript_path":"%s"}' "$PRE_SID" "$PRE_TX" \
  | HOME="$CMP_HOME" KT_CONFIG="$CMP_CFG" sh "$APM_ROOT/scripts/pre-compact-check.sh" > "$PRE_OUT" 2>/dev/null; then :; else :; fi
assert_eq "[PRE1] pre-compact prints nothing" "0" "$(wc -c < "$PRE_OUT" | tr -d ' ')"
assert_eq "[PRE2] pre-compact still writes the snapshot" "yes" \
  "$(ls "$CMP_KF/intake/pre-compact-captures/"*"_$(printf '%s' "$PRE_SID" | cut -c1-8).md" >/dev/null 2>&1 && echo yes || echo no)"

# Class guard. Every hookEventName literal a registered script emits must equal the
# event it is registered under AND be an event the harness's hookSpecificOutput union
# accepts. ⚠ The accepted set is PINNED to Claude Code 2.1.305 (read from its
# binary); a harness that adds variants needs this list updated, and a live /compact
# remains the outcome test — a static list cannot see the live schema.
HSO_ACCEPTED=" PreToolUse UserPromptSubmit UserPromptExpansion SessionStart Setup PreModelSwitch PostModelSwitch PostToolUse PostToolUseFailure PostToolBatch Notification Stop SubagentStart SubagentStop PermissionRequest PermissionDenied Elicitation ElicitationResult CwdChanged FileChanged MessageDisplay WorktreeCreate "
HSO_BAD=""; HSO_SEEN=0
for pair in $(jq -r '.hooks | to_entries[] | .key as $e | .value[].hooks[].command | "\($e)=\(.)"' "$APM_ROOT/.claude-plugin/plugin.json" 2>/dev/null | sed 's#=.*/scripts/#=#; s#\.sh.*#.sh#' | tr ' ' '_'); do
  ev=${pair%%=*}; sc=${pair#*=}
  for emitted in $(grep -oE 'hookEventName[\\"]*:[\\"]*[A-Za-z]+' "$APM_ROOT/scripts/$sc" 2>/dev/null | sed -E 's/.*[^A-Za-z]([A-Za-z]+)$/\1/'); do
    HSO_SEEN=$((HSO_SEEN + 1))
    [ "$emitted" = "$ev" ] || HSO_BAD="$HSO_BAD $sc:emits-$emitted-registered-$ev"
    case "$HSO_ACCEPTED" in *" $emitted "*) ;; *) HSO_BAD="$HSO_BAD $sc:$emitted-not-accepted" ;; esac
  done
done
# Positive control: an empty plugin.json parse or a broken grep would leave the guard
# with nothing to check and a vacuous pass.
assert_eq "[HSO0] class guard examined the registered emissions" "yes" \
  "$([ "$HSO_SEEN" -ge 10 ] && echo yes || echo no)"
assert_eq "[HSO1] every registered hook emits only an accepted, matching hookEventName" "" "$HSO_BAD"

# The multiline escape must live in ONE place. Duplicating it into a second
# hook is the drift hazard refused for the CODEMAP block; it belongs in
# config.sh as a new shared helper, leaving kt_json_escape untouched.
assert_eq "multiline escape is defined exactly once" "1" \
  "$(grep -rl '^kt_json_escape_multiline()' "$APM_ROOT/scripts" 2>/dev/null | wc -l | tr -d ' ')"
assert_eq "multiline escape lives in config.sh (shared, not per-hook)" "yes" \
  "$(grep -q '^kt_json_escape_multiline()' "$APM_ROOT/scripts/config.sh" 2>/dev/null && echo yes || echo no)"
# The existing helper must NOT be changed — four other hooks depend on its
# newline-stripping behaviour. This asserts the tr stage is still present.
assert_eq "shared kt_json_escape still strips newlines (unchanged)" "yes" \
  "$(sed -n '/^kt_json_escape()/,/^}/p' "$APM_ROOT/scripts/config.sh" | grep -qF "tr '" && echo yes || echo no)"

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
# The heading contract (2026-09-29): without it sessions invent `## ` group headers and `####`
# children, both invisible to a `### ` count. See scripts/count-backlog-entries.sh.
assert_eq "INSIGHT CAPTURE states the ### entry-heading contract" "yes" \
  "$(digest_has '### YYYY-MM-DD — <project> — <title>')"
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
  "$(grep -q 'judging whether to keep going' "$APM_ROOT/scripts/session-start-check.sh" && echo yes || echo no)"

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

UR_LIB="$APM_ROOT/scripts/lib-user-rules.sh"
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
# The hook compares each user-scope rules file before and after it writes it, because §10.6
# measured that the instruction-file set is snapshotted at session start: a file this hook
# writes is not delivered until the NEXT session. ⛔ RE-POINTED 2026-10-29: the first session
# after install no longer receives the rules through the emission (a 35.3 KB inline payload
# reached the model as a ~2 KB preview). It receives a notice naming the files, and the guard
# below now asserts those named files hold the rules — the same 270-chars-0-rules defect fails it.
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
arm_run() { HOME="$ARMH" KT_CONFIG="$ARMCFG" sh "$HOOK" 2>/dev/null </dev/null \
  | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null; }

ARM1=$(arm_run)   # file absent at snapshot -> transitional
ARM2=$(arm_run)   # file now present        -> steady state

# ⚠ Standalone case, NOT nested in $( ). A case pattern's `)` is ambiguous with
# the command-substitution terminator, so the inline form mis-parses and the
# assertion fails while the payload is in fact correct — verified: the emission
# does begin with these bytes.
case "$ARM1" in
  "ARIA RULES REFRESHED"*) ARM1_LEADS=yes ;;
  *) ARM1_LEADS=no ;;
esac
assert_eq "arm 1 leads with the rules notice" "yes" "$ARM1_LEADS"
ARM1_NOTICE=$(printf '%s' "$ARM1" | grep '^ARIA RULES' | head -1)
ARM_D="$ARMH/.claude/rules/aria-rules.md"; ARM_U="$ARMH/.claude/rules/aria-user-rules.md"
assert_eq "arm 1 names the installed digest" "yes" \
  "$(printf '%s' "$ARM1_NOTICE" | grep -qF "$ARM_D" && echo yes || echo no)"
assert_eq "arm 1 names the installed user rules" "yes" \
  "$(printf '%s' "$ARM1_NOTICE" | grep -qF "$ARM_U" && echo yes || echo no)"
# ⚠ Derived HERE, not borrowed from the DELIVERY GUARD block below — that block
# defines its needle later in the file, so referencing it from here would compare
# against an EMPTY string, and `grep -qF ''` matches anything. Positive control
# first, for the same reason.
ARM_LAST_RULE=$(grep -o '^- \*\*Rule [0-9]* — [^*]*\*\*' "$DIGEST" 2>/dev/null \
  | tail -1 | sed 's/^- \*\*//; s/\*\*$//')
assert_eq "arm-block last-rule needle parses non-empty" "yes" \
  "$([ -n "$ARM_LAST_RULE" ] && echo yes || echo no)"
assert_eq "arm 1's named digest holds the LAST rule title" "yes" \
  "$(grep -qF "$ARM_LAST_RULE" "$ARM_D" 2>/dev/null && echo yes || echo no)"
assert_eq "arm 1's named digest holds a standing directive" "yes" \
  "$(grep -qF 'RULE 22 ORDERING —' "$ARM_D" 2>/dev/null && echo yes || echo no)"
assert_eq "arm 1's named user-rules file holds the user's own rules" "yes" \
  "$(grep -qF 'an arm-fixture rule' "$ARM_U" 2>/dev/null && echo yes || echo no)"
assert_eq "arm 1 carries the config line" "yes" \
  "$(printf '%s' "$ARM1" | grep -qF 'ARIA CONFIG —' && echo yes || echo no)"

assert_eq "arm 2 does not duplicate the digest" "no" \
  "$(printf '%s' "$ARM2" | grep -qF 'RULE 22 ORDERING —' && echo yes || echo no)"
assert_eq "arm 2 still carries the config line" "yes" \
  "$(printf '%s' "$ARM2" | grep -qF 'ARIA CONFIG —' && echo yes || echo no)"
assert_eq "arm 2 carries no rules notice (nothing changed)" "no" \
  "$(printf '%s' "$ARM2" | grep -q '^ARIA RULES' && echo yes || echo no)"

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
# home path (the maintainer's home path, 17 ch) literally because only $kf was normalised;
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
# ⛔ SUPERSEDED 2026-10-29 — the history above stays as the record. The hook no longer inlines
# the digest on any arm (spec 2026-10-29-rules-changed-notice), so the expected emission is a
# notice plus value lines, well under 2,000 characters. The catch is lowered to 4,000: a
# reintroduced inline digest is >= 23,568 characters and fails it loudly. Delivery is carried by
# the leads-with assertion below, not by size — a hard 2,000 ceiling would gate on the user's
# config size (plan-gate A1).
ARIA_EMIT_RUNAWAY=4000

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
# The fixture must own $HOME too, not just the knowledge folder. session-start-rules.sh:83 (then)
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
if HOME="$HOMEW" KT_CONFIG="$CFGW" sh "$HOOK" </dev/null > "$OUTW" 2>/dev/null; then :; else :; fi
PW=$(jq -r '.hookSpecificOutput.additionalContext' "$OUTW" 2>/dev/null || echo '')

# Prove the fixture is actually maximal. Without this the size assertion below
# passes trivially on a fixture that emitted half the blocks.
# Re-pointed 2026-10-29 to the user-rules file the hook installed, where the model reads it.
assert_eq "worst-case fixture fires the LONG U-rule variant" "no" \
  "$(grep -q 'too many to index inline' "$HOMEW/.claude/rules/aria-user-rules.md" 2>/dev/null && echo yes || echo no)"
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
# Re-pointed 2026-10-29: the blocks live in the files the notice names, not in the emission.
for blk in 'RULE 22 ORDERING' 'DECISION ROUTING' 'SESSION STATE' 'TASK BUDGET' 'ARIA ACTIVE CONTEXT'; do
  assert_eq "worst-case digest carries ${blk}" "yes" \
    "$(grep -qF "$blk" "$HOMEW/.claude/rules/aria-rules.md" 2>/dev/null && echo yes || echo no)"
done
assert_eq "worst-case user-rules file carries STANDING USER RULES" "yes" \
  "$(grep -qF 'STANDING USER RULES' "$HOMEW/.claude/rules/aria-user-rules.md" 2>/dev/null && echo yes || echo no)"

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
# ⛔ DELETED 2026-10-29: "the delivered prefix reaches the first rule". It built its prefix with
# `cut -c1-2000`, which truncates each LINE, not the payload, so on a multi-line payload the
# "prefix" was nearly the whole text and the check could never fail (reproduced: first rule at
# char 2,102 of 26,242, still "in the prefix"; a live first-install session reported it absent).
# Pattern: line-oriented-truncation-is-not-a-prefix. Nothing replaces it, because no rules are
# inlined any more; delivery is now the notice leading the payload.
case "$PW" in
  "ARIA RULES REFRESHED"*) PW_LEADS=yes ;;
  *) PW_LEADS=no ;;
esac
assert_eq "the delivered prefix leads with the rules notice" "yes" "$PW_LEADS"
assert_eq "worst-case notice names a digest holding the LAST rule title" "yes" \
  "$(printf '%s' "$PW" | grep '^ARIA RULES' | grep -qF "$HOMEW/.claude/rules/aria-rules.md" \
     && grep -qF "$LAST_RULE_TITLE" "$HOMEW/.claude/rules/aria-rules.md" && echo yes || echo no)"

# And the minimal path, which is what most installs actually emit.
assert_eq "minimal notice names a digest holding the LAST rule title" "yes" \
  "$(jq -r '.hookSpecificOutput.additionalContext' "$OUT" 2>/dev/null | grep '^ARIA RULES' | grep -qF "$APM_HOME/.claude/rules/aria-rules.md" \
     && grep -qF "$LAST_RULE_TITLE" "$APM_HOME/.claude/rules/aria-rules.md" && echo yes || echo no)"
