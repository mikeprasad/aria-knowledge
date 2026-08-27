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
# HCLAUSE — added 2026-08-27. HSEC covers ONLY handoff's step-3f summary line, so the handoff GATE and
# the handoff CLAUSE (its two D1 edit sites) were guarded by NOTHING: measured, 3 of the 4 D1 sites had
# no assertion at all, and AC2 ("all four sites are changed") was therefore false as written. Boundaries
# are two distinctive line-starts inside 3f's body, both read from the file rather than assumed.
HCLAUSE=$(awk '/^\*\*Multi-session ledger/,/^THEN write the new active header/' "$HAND")
[ "$(printf '%s' "$WSEC" | wc -c)" -gt 400 ] \
  && ok "floor: wrapup Step 6.5 located ($(printf '%s' "$WSEC" | wc -l | tr -d ' ') lines)" \
  || bad "floor: wrapup Step 6.5" "section not found or too short — every check below would be vacuous"
[ "$(printf '%s' "$HSEC" | wc -c)" -gt 200 ] \
  && ok "floor: handoff 3f located" \
  || bad "floor: handoff 3f" "section not found — the two-sided check below would be vacuous"
[ "$(printf '%s' "$HCLAUSE" | wc -c)" -gt 400 ] \
  && ok "floor: handoff ledger clause located ($(printf '%s' "$HCLAUSE" | wc -l | tr -d ' ') lines)" \
  || bad "floor: handoff ledger clause" "slice empty or too short — H1/H2 below would examine no text at all"

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

# ── C: the in-progress rule is CONDITIONED, not blanket ──────────────────────────────────────────
# ⛔ THE PREVIOUS VERSION OF THIS CHECK WAS `grep -qiE 'in-progress'` — the STRING alone — and it could
# not fail for the right reason in either direction. The rule it guarded was FALSE (see D1 in
# docs/superpowers/specs/2026-08-27-session-ledger-integrity.md): kt_ss_mark_inprogress rewrites only
# front-matter and passes the body through, so such a marker routinely carries a full prompt, and
# "never demote it" destroyed live pickups. Both the false rule and its correction contain the word
# "in-progress", so the old check passed either way — and had the corrected wording dropped the
# hyphenated form, it would have FAILED while its own message asserted the false premise. A guard whose
# two outcomes are both misleading is not a guard.
#
# ⛔ THE FORBIDDEN STRING IS ASSERTED ABSENT, NOT PARAPHRASED. Absence of an exact string is the one
# form that cannot be satisfied by accident — the same reasoning D below is built on. The substring is
# shared by BOTH skills (wrapup: "…so the ledger entry would be empty"; handoff: "…so a ledger entry
# for it would be empty"), so one literal covers both sites.
#
# ⚠ DO NOT quote that retired sentence in either SKILL.md, not even to explain that it was wrong —
# pattern `own-comment-enters-the-text-its-guard-reads`. Describe the retired claim instead. This
# comment is safe because the guard reads the SKILL.md files, never this file.
_R22_RETIRED='it carries no prompt, so'
printf '%s' "$WSEC" | grep -qF "$_R22_RETIRED" \
  && bad "C1 retired rationale" "wrapup still carries the false in-progress rationale — kt_ss_mark_inprogress preserves the body, so such a marker DOES carry a prompt and demoting it is required" \
  || ok "C1 wrapup: retired in-progress rationale absent"
printf '%s' "$WSEC" | grep -qiE 'non-empty prompt' \
  && ok "C2 wrapup: demote is conditioned on a non-empty prompt block" \
  || bad "C2 wrapup condition" "Step 6.5 never names the non-empty-prompt condition, so the in-progress rule is still blanket"

# ── C3: the positive gate no longer keys on `handoff` ALONE (AC2) ─────────────────────────────────
# ⛔ Editing only the clause is a PROVEN no-op: the gate decides whether an in-progress entry ever
# reaches the demote path at all. This is the assertion that makes AC2 real.
printf '%s' "$WSEC" | grep -qF 'holds an unconsumed `handoff` entry' \
  && bad "C3 wrapup gate" "the gate still keys on an unconsumed \`handoff\` entry, so an in-progress marker never reaches the demote path — fixing the clause alone changes nothing" \
  || ok "C3 wrapup: gate no longer keys on \`handoff\` alone"

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

# ── H: /handoff carries the SAME two D1 fixes (sites 2 and 3) ─────────────────────────────────────
# ⛔ WITHOUT THESE, AC2 IS FALSE. /handoff holds two of the four D1 edit sites — the ledger GATE and the
# clause — and neither is inside HSEC, so before 2026-08-27 they were guarded by nothing. The invariant
# is shared by two skills, so it must be checked in both: a guard on one file goes green while the other
# still destroys live pickups (exactly the two-sided reasoning assertion E already applies to the demote).
printf '%s' "$HCLAUSE" | grep -qF "$_R22_RETIRED" \
  && bad "H1 retired rationale" "handoff still carries the false in-progress rationale — the same claim, in the other skill" \
  || ok "H1 handoff: retired in-progress rationale absent"
printf '%s' "$HCLAUSE" | grep -qF 'has `lastEvent: handoff` and its' \
  && bad "H2 handoff gate" "the handoff gate still keys on \`lastEvent: handoff\`, so an in-progress marker carrying a real prompt is never demoted" \
  || ok "H2 handoff: gate no longer keys on \`lastEvent: handoff\` alone"

# ── F: the runtime-drift note is recorded where a reader will see it ─────────────────────────────
printf '%s' "$WSEC" | grep -qiE 'antigravity|codex' \
  && ok "F  tracked drift named in-file" \
  || bad "F  drift note" "antigravity/codex carry the same gap and nothing in the file says so"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
