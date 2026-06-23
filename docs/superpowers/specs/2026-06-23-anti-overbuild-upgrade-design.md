# Design: Anti-Over-Build Upgrade (simplification marker + over-build lens)

> Brainstormed 2026-06-23. Ports two patterns from the Ponytail project
> (github.com/DietrichGebert/ponytail, a YAGNI-for-agents tool) into aria-knowledge's
> existing rule + skill primitives. Chosen shape: **hybrid** — minimal footprint
> (fold into existing rules/skills, no new numbered rule, no new standalone skill)
> + an over-build *lens* wired into three review skills for on-demand and whole-repo reach.

## Problem

aria-knowledge already encodes the *philosophy* of minimal code (Rule 12 minimize-dependencies,
Rule 13 simplest-solution-wins, Rule 14 abstraction-diminishing-returns, Rule 28 write-only-as-much-as-needed).
But it has no **reflex** that makes an agent *act* on it before/while writing, and no **review surface**
that detects over-build after the fact. Two concrete gaps:

1. **No record of deliberate simplifications.** When an agent rightly takes the simpler path on
   non-trivial logic, the trade-off (what was simplified, the known limitation, the upgrade path) is
   lost — invisible to future readers and to any review. Rule 21 says "document decisions"; nothing
   operationalizes it for the specific decision *"I chose less."*
2. **No way to ask "is this over-built?"** Neither on a plan (forward), a diff (backward), nor a whole
   repo (sweep). The judgment exists only ad hoc.

Ponytail solves (1) with an inline `ponytail:` comment and (2) with `/ponytail-review` (diff) +
`/ponytail-audit` (repo). We port the *ideas*, not the tool, routing them through aria-knowledge's
existing decision-trail discipline and review harnesses.

## Decisions (locked during brainstorm 2026-06-23)

1. **Scope = hybrid.** Both patterns, minimal footprint, plus whole-repo reach via an existing audit skill — not two new standalone skills.
2. **Simplification marker = a clause on existing Rule 13**, NOT a new numbered rule. (Respects the documented bias against rule-count growth + Rule 28.)
3. **Over-build review = a `--lens=overbuild` MODE** added to existing `/prospect` (forward/plan) and `/retrospect` (backward/diff), plus an **over-build dimension** in `/readiness-audit` (whole-repo sweep). No new skill.
4. **Shared pattern definitions live in a NEW file** `template/rules/overbuild-patterns.md` (sibling to `retrospect-patterns.md`) — one source of truth all three skills read.
5. **Marker token = `aria:simplification`** — namespaced + greppable, distinct from generic `TODO`/`FIXME`.
6. **The lens is opt-in.** Bare `/prospect`, `/retrospect`, `/readiness-audit` are byte-for-byte unchanged in behavior; the lens activates only on the explicit flag/dimension. Zero ambient nagging.
7. **The marker and the lens form a closed loop** — the lens *respects* existing markers (a marked simplification is reported "resolved," never flagged), and flags *unmarked* simplifications as a smell.

## Surfaces this change touches

Four files, replicated across all 5 port templates (claude-code, codex, cursor, antigravity, cowork).

### Surface 1 — `working-rules.md` Rule 13 (the convention)

Append a clause to Rule 13 ("Simplest solution wins…"):

> **Mark deliberate simplifications.** When you choose a simpler solution over a more complete one on
> non-trivial logic, leave an inline marker recording the trade-off:
> `<comment> aria:simplification — <what was simplified> | limitation: <known gap> | upgrade: <path if the gap bites>`
> A simplification without its marker is an undocumented assumption (Rule 21, inline). The marker is what
> lets `/retrospect --lens=overbuild` tell a *chosen* simplification from an *accidental* gap.

No new rule number. Comment syntax adapts to the host language (`//`, `#`, `<!-- -->`).

### Surface 2 — `template/rules/overbuild-patterns.md` (NEW; the shared library)

Two parts, format mirroring `retrospect-patterns.md`:

- **The ladder** — the ordered rubric ported from Ponytail and adapted to aria vocabulary:
  `needed? → stdlib? → platform-native? → installed-dep? → one-line? → minimal-build`. Each rung
  cross-references the working rule it enforces (rung 1 → Rule 13 YAGNI; rung 4 → Rule 12; etc.).
- **A growing smell list** — named, greppable patterns, each with: name, signature, why-it's-a-smell,
  leaner alternative. Seeded with six:
  `speculative-abstraction`, `dependency-for-a-oneliner`, `config-knob-nobody-asked-for`,
  `premature-generalization`, `framework-for-a-function`, `unmarked-simplification`.
  Grows by accretion as the lenses surface new ones (same lifecycle as `retrospect-patterns.md`).

### Surface 3 — `skills/prospect/SKILL.md` (forward lens, on a plan)

Add `--lens=overbuild` modifier flag (Step 0 already parses modifier flags like `--linear-post`/`--no-source`).
When set: after the standard per-step pass, each planned step is checked against the ladder; a step that
fails a rung yields a SHRINK or KILL verdict (existing verdict vocabulary) citing the failed rung + the
concrete leaner alternative. A step whose simpler form can't be named is NOT flagged (no-name → no-finding,
matching prospect's existing discipline).

### Surface 4 — `skills/retrospect/SKILL.md` (backward lens, on a diff)

Add `--lens=overbuild` modifier flag. When set: scan the in-scope diff for `overbuild-patterns.md` smells
+ detect simplifications that *should* carry an `aria:simplification` marker but don't (`unmarked-simplification`).
A diff hunk already carrying a marker is reported "resolved (marked)", never flagged. Findings cite rung +
leaner alternative; unnameable → suppressed.

### Surface 5 — `skills/readiness-audit/SKILL.md` (whole-repo sweep)

Add an **over-build probe to the per-surface agent dispatch** (NOT a "checklist dimension" — verified
during /prospect 2026-06-23: readiness-audit has no static checklist; it dispatches Explore agents
per surface in parallel, then a controller re-verifies every load-bearing claim). The over-build probe
is one more read-only surface in that dispatch list, reading `overbuild-patterns.md` as its rubric.
This is the "audit Commonspace/Seersite for bloat" reach without a new skill. Each finding is
evidence-celled like the skill's other surface findings and feeds the phased remediation plan
(triage to phases, NOT a shipping list — per the skill's existing contract). Probe stays read-only
per the skill's guardrail (no build/run mutation).

## Components & data flow

```
agent writes code ──leaves──▶ aria:simplification marker (Rule 13 clause)
                                      │
overbuild-patterns.md ──read by──▶ /prospect --lens=overbuild  (plan, forward)
   (ladder + smells)   ──read by──▶ /retrospect --lens=overbuild (diff, backward) ──respects──▶ marker
                       ──read by──▶ /readiness-audit over-build dim (repo, sweep)
```

The marker is the metadata the backward lens consumes — closed loop: mark → detect-unmarked → mark-or-shrink.

## Noise control (the load-bearing risk)

Ponytail's own benchmark softened its claims because always-on over-build judgment over toy tasks
over-fired. Three guards:

1. **Opt-in only** — the lens never runs unless explicitly invoked. No ambient findings.
2. **Name-the-alternative-or-suppress** — every finding must cite the failed ladder rung AND the concrete
   leaner alternative. A finding that can't name the smaller version is dropped. (Reuses prospect's
   existing "name the smaller version or it's not a finding" discipline.)
3. **Marker-respect** — a documented simplification is never re-flagged.

## Multi-port propagation

The 4 files (1 new + 3 edits; Rule 13 edit is the 4th touched file) replicate across:
`plugin-claude-code/`, `plugin-openai-codex/`, `plugin-cursor-template/`, `plugin-antigravity/`,
`plugin-claude-cowork/` — via the existing `release.sh` / `release-*.sh` scripts. Codex/Cowork skill
variants may need the runtime-gate boilerplate the other skills already carry; the plan will enumerate
exact per-port paths. Pattern-lib path differs by port (`template/rules/` vs `knowledge/rules/` for cursor) —
plan must map this.

## Versioning

Minor bump (new capability, backward-compatible, no behavior change to existing invocations):
`2.35.x → 2.36.0`. CHANGELOG attribution per the repo's ADR-014 convention.

## Testing / validation

Follows existing `tests/` pattern:
- Fixture diff containing a known `dependency-for-a-oneliner` smell → assert `/retrospect --lens=overbuild` surfaces it.
- Fixture diff containing a hunk with an `aria:simplification` marker → assert it is NOT flagged (resolved).
- A plan fixture with an over-built step → assert `/prospect --lens=overbuild` yields SHRINK/KILL with a named alternative.
- Bare `/prospect` / `/retrospect` over the same fixtures → assert output is unchanged vs. pre-upgrade (opt-in guard).

## Open questions for /prospect

1. Is folding the marker into Rule 13 the right call, or does it deserve its own rule despite the bias against rule growth — i.e., is it discoverable enough buried in Rule 13?
2. `--lens=overbuild` as a modifier flag vs. a first-class scope — does the flag compose cleanly with existing scopes (`/prospect file <path> --lens=overbuild`)?
3. Does `/readiness-audit` gaining a code-bloat dimension blur its "is this clean/legal/consistent to ship for THIS event?" charter, or is bloat legitimately a readiness concern?
4. Marker token `aria:simplification` — collision risk with anything already greppable in the consumer repos (cs/ss/df)? Verify before locking.
5. Is six seed smells the right starting size, or does seeding too many invite false positives before the library is calibrated?
