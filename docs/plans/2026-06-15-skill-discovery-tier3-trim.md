# Plan — Skill-Discovery Surface Trim, Tier 3 (trigger-synonym + mode-desc)

**Date:** 2026-06-15
**Scope root:** `aria-knowledge/plugin-claude-code/skills/`
**Goal:** Recover the remaining ~200–400 tok toward the original ~700–900 tok target (v2.30.1 already took ~480) by pruning trigger-synonym redundancy and compressing mode-semantics narration in the heaviest remaining descriptions (`handoff` 1018B, `wrapup` 810B, possibly `prospect`/`retrospect` 672/670B).
**Why now:** Optional follow-on to v2.30.1. Flagged at the time as higher-risk: these bytes are MORE dispatch-relevant than Tier 1/2's signposting + internal-mechanism narration.

## Principle (same as v2.30.1)

Descriptions exist for dispatch. BUT — unlike Tier 1 (signpost) and Tier 2 (internal mechanism documented in-body), Tier 3 targets bytes that *may be doing dispatch work*: trigger synonyms feed the NL router's match surface, and mode-semantics help route `/handoff brief` vs `/handoff snap`. So Tier 3 is NOT a free relocation — it's a genuine trade of bytes for dispatch-recall.

## Step 1 — Prune trigger-synonym lists (handoff 10→~5, wrapup 9→~5)

**Observed:** `handoff` lists 10 trigger phrases, `wrapup` lists 9. Several are near-synonyms: handoff has `'hand it off'`, `'handoff and extract'`, `'context is full, restart this'`, `'pass off to next session'`, `'wrap and prompt'`; wrapup has `'wrap up'`, `'wrap it up'`, `"I'm done"`, `'close out'`, `'finish session'`, `'end session'`, `'saying goodbye'`.

**Change:** Drop the lowest-distinctiveness synonyms, keeping the slash-form(s) + 3–4 semantically-distinct natural phrases.

**Risk:** ❓ Unsupported — NO measured data on trigger-count → dispatch reliability exists in the corpus. The NL router *probably* generalizes, but "probably" is not evidence. COUNTER-PRECEDENT: the v2.30.0-codex alias removal deliberately PRESERVED slash-forms in trigger lists ("muscle memory is preserved") — a documented bias toward keeping trigger coverage.

## Step 2 — Compress mode-semantics narration (handoff, wrapup)

**Observed:** `handoff` spends ~3 sentences explaining what `auto`/`brief`/`snap` each do; `wrapup` similarly for `auto`/`snap`. ADR-103 (snap mode) + ADR-092 (wrapup-vs-handoff audience split) made these descriptions intentionally rich.

**Change:** Compress mode explanations to a terse form (e.g. "modes: auto (silent), brief (coworker prose), snap (snapshot instead of extract)").

**Risk:** ⚠ Theory-driven — mode-routing IS dispatch-relevant (the description is how Claude picks `/handoff brief` from "brief a coworker"). Compressing too far could degrade mode selection. Bodies DO document modes fully, but the *dispatch decision* happens from the description.

## Out of scope

- prospect/retrospect descriptions (already lean at ~670B; Triggers there are 7 and distinct).
- Any skill under ~600B.

## Verification

1. `release.sh` Gate B passes (will, trivially — we're shrinking).
2. Byte recount — target additional ~200–400 tok off.
3. **Dispatch smoke (the hard one):** for each pruned trigger phrase REMOVED, confirm a *kept* phrase covers the same intent. For mode compression, confirm each mode is still named + distinguishable in the description.

## Rollback

Single commit, descriptions-only, `git revert`.

## Honest pre-mortem note

This tier may not clear `/prospect`. The bytes here are closer to load-bearing than Tier 1/2's were. If the pre-mortem says the dispatch-recall risk isn't worth ~200–400 tok, KILL or SHRINK is the right call — v2.30.1 already captured the safe majority.
