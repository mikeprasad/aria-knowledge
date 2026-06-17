# Cowork `/interview` Parity — Design

**Date:** 2026-06-18
**Scope:** Bring `plugin-claude-cowork/` to parity with canonical `plugin-claude-code/` v2.31.0.
**Author:** Claude (with Mike)

## Problem

Canonical aria-knowledge shipped the `/interview` skill in v2.31.0 — a 3-mode knowledge-elicitation skill (`project` / `knowledge` / `deep-dive`). The Cowork port (`plugin-claude-cowork/`, currently v1.3.0) does not have it. The canonical skill's own Runtime Gate explicitly flags this: *"v1 ships Code-only — there is no Cowork variant of `/interview` yet (documented port follow-on)."* This spec covers that follow-on.

## What "parity" actually requires (ground-truth findings)

Investigation (drift-checker + two parallel agents + ADR cross-check) established:

1. **The drift-checker output is mostly stale-ledger noise.** `PORT-LEDGER.json` records cowork as v1.2.0; it is actually v1.3.0. The 6 "drifted" skills (handoff, wrapup, intake, prospect, retrospect, audit-knowledge) are all **intentional cowork adaptations** (ADR-005/008/013/094, Q-4 Option B) — no missing behavior. The 2 "missing" skills (config-audit, knowledge-audit) are **aliases v1.3.0 deliberately removed**.
2. **Four apparent "portable gaps" are permanent exclusions.** `/codemap`, `/stitch`, `/distill`, `/audit-share` are excluded by **ADR-005** ("the original 5 exclusions stand unchanged"), each with a documented revisit-condition. Porting them would reverse a deliberate scope decision — out of scope.
3. **The one genuine gap is `/interview`.**

## Design

### 1. Port `/interview` (cowork-adapted)

Create `plugin-claude-cowork/skills/interview/SKILL.md`, adapted from canonical per the established cowork porting pattern (ADR-013 schema-identical outputs; ADR-094 namespacing; ADR-008 path reachability):

- **Runtime Gate flip (ADR-094):** Replace the canonical "this is the Code variant / no Cowork variant yet" gate with the cowork-side gate — this *is* the Cowork variant; namespaced as `/aria-cowork:interview`; bare `/interview` resolves to plugin-claude-code when both ports load.
- **Bash → cowork fallbacks:** The only hard Bash dependency is Step 0 (config read). Replace with cowork's documented pattern: try to read `~/.claude/aria-knowledge.local.md`; on failure, ask the user to paste their knowledge-folder path (the canonical gate already anticipates this). `allowed-tools` drops `Bash`.
- **Grounding ingestion (Step 2):** Read/Glob/Grep/WebFetch are all available in Cowork — keep as-is. For artifacts outside Cowork's attached-folder reach (ADR-008), fall back to user-paste, consistent with sibling cowork skills.
- **Steps 1, 3, 4, 5, 6 (mode/cadence/interview/confirm/stage):** Pure dialogue + Write — port faithfully. Output paths (`intake/projects/`, `intake/interviews/`) and templates are **byte-identical** to canonical per ADR-013.
- **Manual-review invariant preserved:** staged, never auto-promoted.

### 2. Cap management (binding constraint)

Cowork enforces a **9000-char hard cap** on summed SKILL.md descriptions (empirical install-fail at 9233; `release.sh` preflight gates it: warn >8500, fail >9000). Current total = **8538 chars → 462 headroom**.

**Decision (Mike, 2026-06-18): reuse canonical's trims where they help.** Finding: they **don't** — canonical's v2.30.1 trim was overwhelmingly the parenthetical swap (`(Claude Code variant — …; see ADR-094.)` → `(Code port — ADR-094.)`), and cowork **already** uses an even terser parenthetical (`(Cowork variant — namespaced-only.)`). Cowork's `foundational-review`/`readiness-audit` descriptions are already trimmed *harder* than canonical's post-v2.30.1 form. So there is no carry-over slack.

**Therefore:** write the cowork `/interview` description as a tight routing signal in the **~300–380 char** range (canonical's is ~1100 — far too long). Reference proof: cowork's `foundational-review` description (~280 chars) and `readiness-audit` (~260 chars) successfully carry 3-mode/multi-stage skills' routing signal at that length. If the summed total still crosses the 8500 warn, trim the least-load-bearing existing cowork description(s) — but the gate is `release.sh`'s preflight count, **not** a hand count.

### 3. Refresh the stale ledger

After the skill lands, regenerate `PORT-LEDGER.json` via `bin/check-port-drift.sh --update` so the drift-checker reports truthfully (records cowork at its new version + fresh per-surface hashes, clearing the v1.2.0-vs-v1.3.0 noise and the removed-alias "missing" flags).

### 4. Version bump + release artifacts

- Bump `plugin-claude-cowork/.claude-plugin/plugin.json` v1.3.0 → **v1.4.0** (new skill = minor).
- CHANGELOG.md entry: parity with canonical v2.31.0; the `/interview` cowork adaptation; cap note.
- `./release.sh` produces `aria-cowork-1.4.0.plugin` — its aggregate-description preflight is the cap gate.
- Update the cowork CLAUDE.md skill count (26 → 27 distinct) + the canonical CLAUDE.md "Cowork Port" footer.

## Out of scope (explicit)

- Re-porting the ADR-005 exclusions (`/codemap`, `/stitch`, `/distill`, `/audit-share`) — permanent exclusions by design.
- The canonical v2.30.0 Code-only changes (Rule 22 circuit breaker, release gates, PORT-LEDGER tooling) — hooks + Code-side, N/A to skills-only Cowork.
- The `/handoff` model-recommendation rubric — pre-existing tracked-drift, not this pass.

## Testing / validation

- `release.sh` aggregate-description preflight passes (summed < 9000; ideally < 8500 warn).
- `release.sh` expected-skills smoke list updated to include `interview`.
- `bin/check-port-drift.sh` post-`--update` shows cowork `interview` = `ok` and no spurious drifted/missing.
- Manual read-through: cowork `/interview` Runtime Gate is cowork-side; no Bash/git in the body; output paths + templates byte-match canonical.
