#!/bin/sh
# ➜ SUPERSEDED 2026-08-27 by a LIVE replacement: ../pre-bash-write-check.sh, which keeps this
#   guard's measured SCOPE unchanged and replaces only its METHOD — targets are now RESOLVED
#   (heredoc bodies stripped, shlex operator-aware tokenizing, per-statement extraction, temp
#   exemption applied to the resolved path) instead of matched in the command string, which closes
#   BOTH failure directions below with one mechanism. Design:
#   docs/superpowers/specs/2026-08-27-bash-write-target-resolution.md
#   ⚠ The verdict below is STILL CORRECT and is deliberately not softened — it is the reason the
#   replacement exists. This line records the state, not a reprieve for the method.
#
# ⛔ RETIRED 2026-08-26 — UNREGISTERED. Kept per Rule 6 as the record of a method
# that was provably wrong, not as code to restore.
#
# It warned when a Bash command mutated a file in place, bypassing the Rule 22
# gate. The intent was sound; the method was not. Both failure directions come from
# the same root: it decided from the COMMAND STRING instead of resolving the actual
# mutation TARGET.
#
#   FALSE NEGATIVE — line 34 (now below) exempts when the command string MENTIONS a
#   temp or scratchpad path. So `cp f /tmp/bak && sed -i ... f` is silent, and that
#   is backup-then-mutate: the careful pattern this project's own discipline
#   mandates. Doing the safe thing disarmed the check, which also means its measured
#   0.674% fire rate is an UNDERESTIMATE — the corpus cannot have counted what the
#   hook was blind to.
#
#   FALSE POSITIVE — the idiom match is unanchored, so any command that merely
#   QUOTES an idiom trips it. Observed: a `git commit` whose message quoted `sed -i`
#   as an example was flagged as an in-place mutation.
#
# Why not fixed instead: resolving the real target needs a shell-command parser
# (redirections, quoting, compound statements, heredocs), and this project's
# standing rule is that a real false positive means KILL the guard rather than tune
# it. Ruled by Mike, 2026-08-26: "if it is wrong then don't use it."
#
# The two Bash hooks that remain are correct for the opposite reason — bash-cd-check.sh
# RESOLVES the `cd` target before judging, and pre-commit-preflight-check.sh uses an
# anchored ERE whose accepted residual is documented at the pattern.
# pre-bash-write-check.sh — PreToolUse:Bash hook.
#
# Warns when a shell command MUTATES A FILE IN PLACE, because that routes around
# the Edit/Write tools and therefore around the Rule 22 pre-edit gate: the change
# lands with no scope assessment recorded, and the enforcement that exists for
# every other structural edit simply does not fire.
#
# WARN-ONLY BY DESIGN. This hook never denies. A false positive would interfere
# with legitimate shell work in every session, which is worse than the lapse it
# catches. Escalating to deny would need a fresh measurement.
#
# SCOPE — in-place mutation only, NOT file creation. That distinction is measured,
# not assumed: across 25,508 real Bash calls, `cat > newfile` is overwhelmingly a
# throwaway probe or diagnostic harness (legitimate, frequent), while `sed -i` and
# `.write_text()` on a tracked file are the actual lapse. The narrowed rule fires
# on 0.674% of calls, roughly 1 in 148.
#
# Also exempt, both measured as benign:
#   - temp / scratchpad paths          (11.4% of all calls)
#   - appends to .md / .json backlogs  (1.27% of all calls)
#
# Fail-open on anything unparseable.

INPUT=$(cat)
# printf '%s', NOT echo -- `echo` in sh interprets backslash escapes, so JSON's
# \n becomes a real newline, the value splits across lines, and this single-line
# grep silently matches nothing. Heredoc commands are routinely multi-line.
COMMAND=$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//')
[ -z "$COMMAND" ] && exit 0

# Temp and scratchpad writes are legitimate by construction.
case "$COMMAND" in
  */tmp/*|*scratchpad*|*/var/folders/*) exit 0 ;;
esac

IDIOM=""
case "$COMMAND" in
  *sed\ -i*)        IDIOM="sed -i" ;;
  *.write_text\(*)  IDIOM="Path.write_text()" ;;
  *write_text\ \(*) IDIOM="Path.write_text()" ;;
esac

# Append-redirect into a source file. Markdown and JSON are deliberately absent:
# appending to a backlog or a log is normal and was measured as always benign.
if [ -z "$IDIOM" ]; then
  if echo "$COMMAND" | grep -qE '>>[[:space:]]*[^[:space:]]+\.(py|ts|tsx|js|jsx|sh|swift|kt|java|rb|go|rs)([[:space:]]|$)'; then
    IDIOM="an append-redirect into a source file"
  fi
fi

[ -z "$IDIOM" ] && exit 0

# Record it. The hook is warn-only by design, so a warning the model ignores would leave no
# trace at all -- and an ignored gate is exactly the failure mode this guard exists to catch.
# One append at detect time (no analysis, no blocking) lets /wrapup and /handoff report the
# bypasses afterwards. Mirrors the aria-r22-denies-<session_id> pattern in pre-edit-check.sh.
# Best-effort: if the session id cannot be resolved, skip the ledger and still warn.
_bw_sid=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"$//')
if [ -n "$_bw_sid" ]; then
  printf '%s\t%s\n' "$IDIOM" "$(printf '%s' "$COMMAND" | cut -c1-120)" \
    >> "${TMPDIR:-/tmp}/aria-r22-bypass-$_bw_sid" 2>/dev/null || true
fi

MSG="ARIA: this command uses $IDIOM to modify a file in place. A structural edit made through the shell bypasses the Edit and Write tools, and therefore the Rule 22 pre-edit gate -- the change lands with no scope assessment recorded. Use Edit or Write instead. If this is genuinely not a structural edit (a generated artifact, a disposable probe, a log), go ahead and say why."

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$MSG"
