#!/bin/sh
# session-ledger-resolution.sh — the session dedup ledger must be resolved BY SESSION ID, never by
# mtime.
#
# Why this suite exists: /prospect and /retrospect instructed
#   `ls -t /tmp/aria-active-* 2>/dev/null | head -1`
# to "find the current session's ledger". That returns the most recently modified ledger on the
# MACHINE. Measured 2026-09-11 during a live /prospect: 71 ledgers present, 4 modified within the
# preceding 20 minutes, this session had NONE, and the command returned another live session's.
# The filter's job is to DROP paths, so a foreign ledger drops files never surfaced to this session
# — a gate whose purpose is loading knowledge silently declines to load it, with no error.
#
# ⛔ This is a CENSUS ratchet, not a behavioural test. Skill bodies are prose; nothing executes
# them, so no test can observe the fixed instruction being FOLLOWED. What this proves is that the
# retired idiom is absent and stays absent across every carrying port. The claim that the
# replacement works rests on a separate measurement (CLAUDE_CODE_SESSION_ID matching this session's
# id exactly, with a firing negative control), recorded in the plan's D1.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$SCRIPT_DIR/../pm-helpers.sh"

RETIRED='ls -t /tmp/aria-active'

# ---------------------------------------------------------------------------
# A. No port may carry the retired mtime-guessing idiom.
#
# ⛔ The walk must include `.mdc`, NOT just `*.md`. The defect that scoped this fix one port short
# was an extension filter: a census run with `--include='*.md' --include='*.sh' --include='*.py'`
# reported "plugin-cursor-template has ZERO occurrences" as a measured fact. Cursor's rules are
# .mdc and it carries FOUR. An assertion carrying the same filter inherits the same blind spot.
# ⛔ CHANGELOG.md is excluded BY DESIGN — it is a dated record of what shipped, and back-dating a
# record is a worse defect than a stale-looking line.
# ---------------------------------------------------------------------------
_A_SEEN=0
_A_BAD=""
for _port in "$ROOT"/plugin-*; do
  [ -d "$_port" ] || continue
  _pd=$(basename "$_port")
  # Does this port CARRY the subject at all? A port with no ledger block is not a subject, and
  # counting it would inflate the anti-vacuity floor into meaninglessness.
  grep -rlq 'aria-active' "$_port" 2>/dev/null || continue
  _A_SEEN=$((_A_SEEN + 1))
  _hits=$(grep -rl "$RETIRED" "$_port" 2>/dev/null | grep -v 'CHANGELOG' | tr '\n' ' ')
  [ -n "$_hits" ] && _A_BAD="$_A_BAD $_pd"
done
if [ -n "$_A_BAD" ]; then
  PM_FAIL=$((PM_FAIL+1))
  printf '  FAIL: A retired mtime-guessing idiom still present\n    ports:%s\n' "$_A_BAD"
else
  PM_PASS=$((PM_PASS+1)); printf '  ok: A no port carries "%s"\n' "$RETIRED"
fi

# ⛔ ANTI-VACUITY. Without this, the loop passes having examined NOTHING — a renamed plugin
# directory, a moved port, or a port that lost its surfacing block all yield _A_SEEN=0 and a clean
# run. The floor is the FIVE ports carrying the ledger block as of 2026-09-11 (claude-code,
# antigravity, claude-cowork, openai-codex, cursor-template); it is a >= so a NEW port joining does
# not redden it. ⚠ The floor was 4 in the first draft of the plan, which is exactly the undercount
# the extension filter produced — cursor IS a subject.
[ "$_A_SEEN" -ge 5 ] \
  && { PM_PASS=$((PM_PASS+1)); printf '  ok: B port coverage: %d carrying ports examined\n' "$_A_SEEN"; } \
  || { PM_FAIL=$((PM_FAIL+1)); printf '  FAIL: B port coverage\n    only %d carrying port(s) examined (want >= 5) — too few subjects for check A to mean anything\n' "$_A_SEEN"; }

# ---------------------------------------------------------------------------
# C. The replacement must name the session id, and the Claude ports must name the measured
#    variable. Guards against "fixing" this by deleting the ledger step outright.
# ---------------------------------------------------------------------------
_C_SEEN=0
_C_BAD=""
for _f in "$ROOT"/plugin-claude-code/skills/prospect/SKILL.md \
          "$ROOT"/plugin-claude-code/skills/retrospect/SKILL.md; do
  [ -f "$_f" ] || continue
  _C_SEEN=$((_C_SEEN + 1))
  grep -qF 'CLAUDE_CODE_SESSION_ID' "$_f" || _C_BAD="$_C_BAD ${_f#$ROOT/}"
done
if [ "$_C_SEEN" -lt 2 ]; then
  PM_FAIL=$((PM_FAIL+1)); printf '  FAIL: C subject files\n    only %d of 2 canonical skill bodies found\n' "$_C_SEEN"
elif [ -n "$_C_BAD" ]; then
  PM_FAIL=$((PM_FAIL+1)); printf '  FAIL: C canonical body does not name CLAUDE_CODE_SESSION_ID\n    files:%s\n' "$_C_BAD"
else
  PM_PASS=$((PM_PASS+1)); printf '  ok: C canonical bodies name CLAUDE_CODE_SESSION_ID (%d files)\n' "$_C_SEEN"
fi

# ---------------------------------------------------------------------------
# D. ⛔ Do NOT name the host-app variable. Measured 2026-09-11: CLAUDE_CODE_HOST_SESSION_ID is the
#    DESKTOP HOST session and carries a `local_` prefix, so it matches no ledger filename. A body
#    naming it would resolve a path that never exists — silently unfiltered forever, which looks
#    like a working fix.
# ---------------------------------------------------------------------------
_D_BAD=$(grep -rl 'CLAUDE_CODE_HOST_SESSION_ID' "$ROOT"/plugin-* 2>/dev/null | tr '\n' ' ')
[ -z "$_D_BAD" ] \
  && { PM_PASS=$((PM_PASS+1)); printf '  ok: D no port names the host-app session variable\n'; } \
  || { PM_FAIL=$((PM_FAIL+1)); printf '  FAIL: D a port names CLAUDE_CODE_HOST_SESSION_ID (host session, local_ prefix, matches no ledger)\n    files: %s\n' "$_D_BAD"; }

# ---------------------------------------------------------------------------
# E. Structure survives. Each carrying body must still have BOTH ledger sites — Step 0.5 item 7
#    ("Ledger filter") and item 11e ("Ledger dedup").
#    ⛔ Counting occurrences of the NEW form cannot detect a deleted block: a body with one site
#    removed still reports "no retired idiom". Assert the surviving structure, not just absence.
# ---------------------------------------------------------------------------
_E_SEEN=0
_E_BAD=""
for _f in "$ROOT"/plugin-claude-code/skills/prospect/SKILL.md \
          "$ROOT"/plugin-claude-code/skills/retrospect/SKILL.md \
          "$ROOT"/plugin-antigravity/skills/prospect/SKILL.md \
          "$ROOT"/plugin-antigravity/skills/retrospect/SKILL.md \
          "$ROOT"/plugin-openai-codex/skills/prospect/SKILL.md \
          "$ROOT"/plugin-openai-codex/skills/retrospect/SKILL.md; do
  [ -f "$_f" ] || continue
  _E_SEEN=$((_E_SEEN + 1))
  _n=$(grep -c 'Ledger filter\|Ledger dedup' "$_f")
  [ "$_n" -ge 2 ] || _E_BAD="$_E_BAD ${_f#$ROOT/}($_n)"
done
if [ "$_E_SEEN" -lt 6 ]; then
  PM_FAIL=$((PM_FAIL+1)); printf '  FAIL: E subject files\n    only %d of 6 two-site bodies found\n' "$_E_SEEN"
elif [ -n "$_E_BAD" ]; then
  PM_FAIL=$((PM_FAIL+1)); printf '  FAIL: E a body lost a ledger site\n    files:%s\n' "$_E_BAD"
else
  PM_PASS=$((PM_PASS+1)); printf '  ok: E both ledger sites survive in all %d two-site bodies\n' "$_E_SEEN"
fi

# ---------------------------------------------------------------------------
# F. Cowork's bespoke in-memory fallback survives. Its runtime has no hook layer to populate the
#    ledger and its sandbox may restrict /tmp, so that fallback is the ONLY dedup it has — a
#    find/replace tuned to canonical's wording would mangle it.
# ---------------------------------------------------------------------------
_cw="$ROOT/plugin-claude-cowork/skills/prospect/SKILL.md"
if [ ! -f "$_cw" ]; then
  PM_FAIL=$((PM_FAIL+1)); printf '  FAIL: F cowork prospect body not found\n'
elif grep -qF 'in-memory' "$_cw"; then
  PM_PASS=$((PM_PASS+1)); printf '  ok: F cowork in-memory dedup fallback survives\n'
else
  PM_FAIL=$((PM_FAIL+1)); printf '  FAIL: F cowork lost its in-memory dedup fallback — that is its only dedup\n'
fi

# ---------------------------------------------------------------------------
# G. The SessionStart directive must not emit a literal ${session_id} the model cannot expand.
# ---------------------------------------------------------------------------
_ss="$ROOT/plugin-claude-code/bin/session-start-check.sh"
if [ ! -f "$_ss" ]; then
  PM_FAIL=$((PM_FAIL+1)); printf '  FAIL: G session-start-check.sh not found\n'
elif grep -qF 'aria-active-\${session_id}' "$_ss"; then
  PM_FAIL=$((PM_FAIL+1)); printf '  FAIL: G directive still emits a literal ${session_id} the reader cannot expand\n'
else
  PM_PASS=$((PM_PASS+1)); printf '  ok: G directive names a resolvable ledger path\n'
fi

pm_summary
exit "$PM_FAIL"
