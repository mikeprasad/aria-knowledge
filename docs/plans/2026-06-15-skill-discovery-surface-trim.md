# Plan — Skill-Discovery Surface Trim (Tier 1 + Tier 2)

**Date:** 2026-06-15
**Scope root:** `aria-knowledge/plugin-claude-code/skills/`
**Goal:** Reduce the per-session skill-discovery fixed cost (~4,364 tok at v2.30.0) by ~700–900 tok (~16–20%) **without removing any capability, trigger semantics, or cross-port enforcement.**
**Why now:** Skill-discovery is the single largest fixed cost and the part that grew v2.25→v2.30 (v2.29.0's two review skills). `value-analysis.md` flags it as a revision trigger; `release.sh ARIA_SKILL_BUDGET` (18,944) is the gate that will verify the result.

## Principle

A skill `description` exists for ONE job: **dispatch** (Claude's NL router picking the right skill). Bytes that don't aid that decision pay rent every session for value that belongs in the skill **body** (read only when the skill fires; off-budget). Strategy: keep what disambiguates, relocate what documents.

## Tier 1 — Trim the repeated ADR-094 parenthetical (~390–520 tok)

**Observed:** 24 skills carry the identical trailing `(Claude Code variant — bare-slash canonical when both ports loaded; see ADR-094.)` (~84 B each); `aria-assist` carries a scheduler-specific variant. Total ≈ 2,083 B / ~520 tok.

**Change:** Replace the long parenthetical with a short pointer `(Code port — ADR-094.)` (~22 B) on the 24 uniform skills. Leave `aria-assist`'s scheduler-specific variant as-is (it carries unique dispatch-relevant info — "full scheduler path").

**Why function is preserved:** the cross-port ownership rule is ENFORCED by the Runtime Gate in each skill BODY, not by the description text. A user never types "bare-slash canonical" to dispatch. The cowork port already uses a ~36-char short form, proving short is acceptable.

**Net:** 24 × (84−22) ≈ 1,488 B / ~370 tok. (Dropping entirely would save ~520 but loses the ADR pointer; keep the short pointer.)

## Tier 2 — Relocate mechanism-narration to bodies (~300–400 tok)

**Observed:** the heavy 6 (`readiness-audit` 1101B, `handoff` 1077B, `foundational-review` 1049B, `wrapup` 869B, `extract-doc` 781B, `intake` 752B) narrate internal `→` pipelines in the description (e.g. "explore → re-verify → tiered findings → remediation → verification recipe → gates").

**Change:** For `readiness-audit` and `foundational-review` (the two with explicit multi-arrow pipelines), compress the pipeline narration in the description to a one-clause summary and ensure the full pipeline is documented in the body (it already is — these skills transclude/describe their chain in-body). Keep: first sentence (what it does + when), the REQUIRES/contrast clauses (dispatch-disambiguating between the two siblings), and Triggers.

**Why function is preserved:** Claude doesn't need the internal pipeline to decide WHETHER to fire — only the intent + triggers. The pipeline matters once firing, where the body is read.

**Net:** ~250–320 B each on 2 skills ≈ ~300–400 tok. (handoff/wrapup are mostly mode-explanation + triggers, which ARE dispatch-relevant — leave them; do not over-trim.)

## Explicitly OUT of scope (deferred)

- Tier 3 trigger-synonym pruning (risk of reduced match recall).
- Touching handoff/wrapup mode descriptions (modes are dispatch-relevant).
- Re-syncing cursor/codex/antigravity/cowork ports (this lands Code-canonical; ports become tracked-drift, re-synced in a coordinated parity pass — matches every recent release's pattern).

## Verification

1. `release.sh` Gate B (`ARIA_SKILL_BUDGET`) passes with a lower live total.
2. Re-run the skill-discovery byte recount (doc's reproduction recipe) — confirm ~3,500 tok.
3. Spot-check dispatch: confirm each trimmed skill still has its first-sentence intent + triggers intact (the dispatch-load-bearing parts).
4. `bin/check-port-drift.sh` will flag the 24+2 edited files as Code-ahead drift — EXPECTED; record in ledger or note as tracked-drift.

## Rollback

Single-commit, descriptions-only. `git revert` restores verbatim. No body logic touched in Tier 1; Tier 2 body additions are additive.
