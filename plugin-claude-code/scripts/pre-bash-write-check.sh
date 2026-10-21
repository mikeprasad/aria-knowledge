#!/bin/sh
# pre-bash-write-check.sh — PreToolUse:Bash hook. [BWCHK-PRE]
#
# Warns when a shell command MUTATES A FILE IN PLACE, because that routes around the Edit/Write
# tools and therefore around the Rule 22 pre-edit gate: the change lands with no scope assessment
# recorded, and the enforcement that exists for every other structural edit simply does not fire.
#
# RESTORED in v2.48.1. v2.48.0 removed the previous implementation and affirmed its intent in the
# same entry — "the intent was sound; the method decided from the COMMAND STRING instead of
# resolving the mutation TARGET." Target resolution now lives in pre-bash-write-resolve.py, and
# closes both of the retired guard's failure directions with one mechanism. See
# docs/superpowers/specs/2026-08-27-bash-write-target-resolution.md.
#
# ⛔ WARN-ONLY, AND THAT IS NOT A COMPROMISE. This hook never denies; it exits 0 unconditionally.
# A blocking version of this idea was measured to produce three distinct false-positive classes,
# one of which denied VALID [Rule 22] markers three times before its breaker opened. Warn-only
# removes all three by construction: no ledger of prior calls (so no cross-session attribution),
# no transcript parsing (so no marker verdict to get wrong), and no denial to be wrong about.
# Escalating to deny would need a fresh measurement, exactly as the retired guard's header said.

INPUT=$(cat)

# ---- CHEAP PRE-FILTER -------------------------------------------------------------------------
# ⛔ THE INVARIANT: the pre-filter may only ever cause a cheap EXIT. It may NEVER cause a warning.
# Every warning must originate in the resolver. A pre-filter is necessarily string-based, which is
# the very method that retired the previous guard -- so under this invariant a pre-filter false
# POSITIVE costs one wasted python3 spawn and nothing else, and a false NEGATIVE is the
# pre-existing blind spot rather than a new one. Do NOT "improve" this by letting it emit.
# Control: AC11 in tests/repros/bash-write-target-resolution.sh drives a command that trips this
# filter and resolves to no target, and asserts SILENCE.
#
# ⚑ Matched against the RAW INPUT with a builtin `case`, deliberately. An earlier draft extracted
# the command with `grep` first -- an EXTERNAL binary before the interpreter gate below, which
# would make AC8 (PATH stripped) exit at the wrong branch and pass for the wrong reason. Matching
# the whole payload is strictly wider than matching the command, and wider is safe here because
# this filter can only ever cause an exit. The resolver parses the JSON properly.
#
# ⚑ SCOPE IS ENCODED IN TWO LAYERS, and this is the surprising half. Widening the RESOLVER alone
# does nothing observable, because anything this filter does not list never reaches it. Measured:
# a mutation adding `>` to the resolver's scope SURVIVED the whole suite until `>` was added here
# too. Failure mode is safe (silence, never a false warning), but it is silent -- so if you widen
# scope, widen BOTH, and if a scope change appears to have no effect, look here first.
case "$INPUT" in
  *sed*|*perl*|*awk*|*'>>'*) : ;;
  *) exit 0 ;;
esac

# ---- INTERPRETER GATE -------------------------------------------------------------------------
# ⛔ Everything above this point is SHELL BUILTINS ONLY (`cat` into a variable, `case`), and this
# check must come before ANY external command. AC8 tests the missing-interpreter path by stripping
# PATH; if the wrapper reached for a binary first, that test would break the wrapper instead of
# exercising this branch -- passing, but for the wrong reason.
command -v python3 >/dev/null 2>&1 || exit 0

RESOLVER="$(dirname "$0")/pre-bash-write-resolve.py"
[ -f "$RESOLVER" ] || exit 0

TARGETS=$(printf '%s' "$INPUT" | python3 "$RESOLVER" 2>/dev/null)
[ -z "$TARGETS" ] && exit 0

# ---- RECORD -----------------------------------------------------------------------------------
# Warn-only means a warning the model ignores would otherwise leave no trace at all -- and an
# ignored gate is exactly the failure mode this guard exists to catch. One append at detect time
# lets /wrapup and /handoff report the bypasses afterwards.
# ⚑ Keyed by session id IN THE FILENAME, mirroring pre-edit-check.sh's aria-r22-denies-<sid>. That
# makes cross-session attribution UNREPRESENTABLE rather than filtered -- the failure mode that
# did the most damage in the blocking experiment this hook deliberately does not repeat.
# ⚑ Whitespace-tolerant on purpose. The archived hook assumed COMPACT JSON (`"session_id":"x"`),
# which is what the harness emits today -- but a pretty-printed payload would silently produce an
# empty id, and the only symptom would be a ledger that quietly stops recording. A guard whose
# failure mode is silence must not depend on an unstated formatting assumption. AC9 drives the
# SPACED form deliberately, so this tolerance is proven rather than asserted.
_bw_sid=$(printf '%s' "$INPUT" | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"//;s/"$//')
if [ -n "$_bw_sid" ]; then
  printf '%s\n' "$TARGETS" | while IFS= read -r _t; do
    [ -n "$_t" ] && printf '%s\n' "$_t" >> "${TMPDIR:-/tmp}/aria-r22-bypass-$_bw_sid" 2>/dev/null || true
  done
fi

# ---- WARN -----------------------------------------------------------------------------------
# additionalContext is the channel that reaches model context without blocking. Verified in
# service: 14 hooks in this plugin emit it, including bash-cd-check.sh on this same PreToolUse
# event and this same Bash matcher.
LIST=$(printf '%s' "$TARGETS" | tr '\n' ' ')
MSG="ARIA: this command modifies a file in place: ${LIST}. A structural edit made through the shell bypasses the Edit and Write tools, and therefore the Rule 22 pre-edit gate -- the change lands with no scope assessment recorded. Use Edit or Write instead. If this is genuinely not a structural edit (a generated artifact, a disposable probe, a log), go ahead and say why."

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$MSG"
exit 0
