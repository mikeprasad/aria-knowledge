#!/bin/sh
# wrapup-demotes-before-rewrite.sh — /wrapup must DEMOTE a prior unconsumed handoff into the ledger
# BEFORE its full rewrite, the way /handoff step 3f already does.
#
# THE DEFECT THIS GUARDS (measured 2026-08-26). /handoff 3f runs kt_ss_ledger_add + prune, THEN
# rewrites. /wrapup performed the same full rewrite calling ONLY the prune — and kt_ss_ledger_prune
# (lib-session-state.sh) drops only entries already marked "· consumed", so against an empty ledger
# it is a no-op. The rewrite then replaced "## Where we left off" / "## Next session pickup" /
# "## Next session prompt", which is exactly where /handoff writes a pickup.
#   => handoff -> wrapup DESTROYED the prior session's handoff. handoff -> handoff was always safe.
# Live instance: proj-a 2026-08-26, session affe189f's handoff, 8 minutes old.
#
# ⛔ THE ASSERTIONS ARE TWO-SIDED ON PURPOSE. This guards a CONTRACT SHARED BY TWO SKILLS, so it
# checks /handoff still carries 3f as well. A guard that watched only /wrapup would go green if
# someone removed the demote from /handoff instead — the same invariant, broken from the other end.
#
# (Dogfood ceiling — asserts the SKILL.md DOCUMENTS the contract, not runtime behaviour.)
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WRAP="$REPO_ROOT/plugin-claude-code/skills/wrapup/SKILL.md"
HAND="$REPO_ROOT/plugin-claude-code/skills/handoff/SKILL.md"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

[ -f "$WRAP" ] || { bad "exists" "no wrapup/SKILL.md"; printf "\n0 passed, 1 failed\n"; exit 1; }
[ -f "$HAND" ] || { bad "exists" "no handoff/SKILL.md"; printf "\n0 passed, 1 failed\n"; exit 1; }

# ── FLOOR ────────────────────────────────────────────────────────────────────────────────────────
# ⛔ WITHOUT THIS EVERY ASSERTION BELOW IS VACUOUS. The checks below slice each skill by heading; a
# reformat or rename makes the slice EMPTY, and grepping an empty string finds nothing — so the
# suite would pass having examined no text at all. Same shape as the bug being fixed: silence
# reading as success.
WSEC=$(awk '/^## Step 6.5/,/^## Step 7/' "$WRAP")
HSEC=$(awk '/^5\. \*\*3f:/,/^$/' "$HAND")
[ "$(printf '%s' "$WSEC" | wc -c)" -gt 400 ] \
  && ok "floor: wrapup Step 6.5 located ($(printf '%s' "$WSEC" | wc -l | tr -d ' ') lines)" \
  || bad "floor: wrapup Step 6.5" "section not found or too short — every check below would be vacuous"
[ "$(printf '%s' "$HSEC" | wc -c)" -gt 200 ] \
  && ok "floor: handoff 3f located" \
  || bad "floor: handoff 3f" "section not found — the two-sided check below would be vacuous"

# ── A: /wrapup demotes, and demotes BEFORE the rewrite ───────────────────────────────────────────
printf '%s' "$WSEC" | grep -qF "kt_ss_ledger_add" \
  && ok "A1 wrapup names kt_ss_ledger_add" \
  || bad "A1 demote call" "wrapup Step 6.5 never calls kt_ss_ledger_add — a full rewrite will destroy a prior handoff"

# Ordering, not mere presence — and the ordering word must sit between the CALL and the WRITE, on
# the same line as the call.
# ⛔ THE FIRST VERSION OF THIS CHECK WAS DEAD. It carried a third alternative,
# 'demote.*(then|before).*(write|rewrite)', which matches this section's own HEADING
# ("Demote before you rewrite") — text a mutation reordering the numbered step never touches. So a
# version that performed the rewrite FIRST and demoted afterwards PASSED. A heading states intent;
# only the numbered step states the sequence, and a guard satisfied by either is scoped to the wrong
# unit — the same defect class this fix exists to close, one level down.
printf '%s' "$WSEC" | grep -qiE 'ledger_add.*(then|before).*(write|rewrite)' \
  && ok "A1b demote is ordered BEFORE the rewrite" \
  || bad "A1b ordering" "the demote is mentioned but not ordered before the rewrite — presence is not sequence"

# ── B: conditioned on someone ELSE's entry ───────────────────────────────────────────────────────
printf '%s' "$WSEC" | grep -qiE 'different or absent .?sessionId|different .?sessionId' \
  && ok "B  demote is conditioned on a different/absent sessionId" \
  || bad "B  sessionId guard" "unconditional demote would demote the session's OWN entry"

# ── C: the in-progress exception survives the port ───────────────────────────────────────────────
printf '%s' "$WSEC" | grep -qiE 'in-progress' \
  && ok "C  in-progress marker exception carried across" \
  || bad "C  in-progress" "an in-progress marker is a live session's breadcrumb carrying no prompt — demoting it stores an empty entry"

# ── D: the false assurance is gone ───────────────────────────────────────────────────────────────
# ⛔ THIS IS THE ONE THAT MATTERED MOST. The old text asserted "Unconsumed handoffs survive at full
# fidelity" without qualification — TRUE of entries already in the ledger, FALSE of a handoff in the
# active body, which is where /handoff writes it. A missing capability is a gap; a sentence that
# CERTIFIES the unsafe path talks a careful reader out of the caution that would have saved the file.
# ⚠ ASSERTS THE EXACT OLD SENTENCE IS GONE, not that a qualifier appears "somewhere near".
# The first version of this check looked for /ledger|demote|body/ ANYWHERE in the 38-line section
# and therefore PASSED against the unfixed file — unrelated text satisfied it. A qualification that
# is merely co-present is not a qualification; it has to be attached to the claim. Absence of the
# exact string is the one form that cannot be satisfied by accident.
printf '%s' "$WSEC" | grep -qF "Unconsumed handoffs survive at full fidelity — wrapping up one session never silently discards" \
  && bad "D  false assurance" "the unqualified survival claim is present — it is TRUE of ledger entries and FALSE of a handoff in the active body, so it certifies the unsafe path" \
  || ok "D  unqualified survival claim absent"

# ── E: two-sided — /handoff still carries 3f ─────────────────────────────────────────────────────
printf '%s' "$HSEC" | grep -qF "kt_ss_ledger_add" \
  && ok "E  handoff 3f still demotes" \
  || bad "E  handoff 3f" "the demote was removed from /handoff — same invariant, broken from the other end"

# ── F: the runtime-drift note is recorded where a reader will see it ─────────────────────────────
printf '%s' "$WSEC" | grep -qiE 'antigravity|codex' \
  && ok "F  tracked drift named in-file" \
  || bad "F  drift note" "antigravity/codex carry the same gap and nothing in the file says so"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
