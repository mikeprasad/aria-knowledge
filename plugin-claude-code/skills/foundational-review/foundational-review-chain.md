<!-- plugin-bundled canonical process doc for /foundational-review + /readiness-audit.
     This is the genericized, public copy the skills read at runtime. A user may keep a
     richer, project-specific copy at <knowledge_root>/approaches/foundational-review-chain.md;
     when present, the skills prefer that one. Keep both in sync on substance — genericization
     only swaps illustrative project labels for generic phrasing, never changes a discipline. -->
---
tags: [review, audit, architecture, planning, process, prospect, routing, approach, cross]
---

# Foundational Review Chain — "Is this the right thing, built the right way?"

A repeatable, model-agnostic process for reviewing a project at the FOUNDATIONS — problem–solution fit, architecture soundness, product coherence — and converting the findings into a prospect-hardened, cold-executable plan with owner routing. Validated across multiple full runs (a portable design-token format project re-scoped at the product level; a CSS framework reviewed for a v1.0 freeze).

## What this is NOT (read first)

- **Not a code review.** Code review asks "are these changes correct?" on a diff. This asks "should this shape exist?" on a decision.
- **Not a compliance/readiness audit.** An audit checks a surface against a checklist and produces a findings list. This produces a VERDICT resting on named PREMISES, plus the full execution handoff. The two are siblings, not substitutes — a freeze decision often runs both on the same day, fenced against each other.
- **Not a retrospective.** A retrospective validates shipped work backward. This judges a standing architecture/product forward, before an expensive-to-undo step.

**When to run it:** before any IRREVERSIBLE decision — a version freeze, a format/schema/spec tag, a public API or repo flip, a major re-scope, a "should we keep building this at all" moment. The irreversible decision is the anchor; without one, run a plan pre-mortem or a plain readiness audit instead.

## Roles and model routing

- **Reviewer = the highest-ceiling model available** (escalate to the top tier only when the decision is extreme-stakes; otherwise the default top model). The ceiling is spent on: alternatives steelmanning (§A), portfolio/product judgment (§F), and the irreversibility inventory. Everything else in the chain is discipline, not ceiling — **the default model can run the full chain**; it should compensate with stricter evidence-sourcing in the prospect passes.
- **Executor = the default model by default:** every plan task carries `OWNER: <default model>` unless its *execution* (not its review) needs extreme judgment — justify any top-tier owner in one line; can't justify in one line → it's the default. Reserve the reviewer model as CONTINGENCY for named failure branches (e.g., "if probe X fails → reviewer-model design pass," gated).
- **Owner = gate owner.** Anything needing human sign-off becomes a named gate (G-A, G-B, …) in the spec — never an inline assumption.

## Operating rules (non-negotiable)

1. **READ BEFORE JUDGING.** Survey the actual tree first. Every load-bearing claim cited as `file:line`, verified THIS session — never asserted from memory, docs, or prior-session summaries. (Real runs falsified multiple agent claims and a plan's bug report only by direct checks.)
2. **BOUND THE SCOPE FIRST.** State in-scope and out-of-scope explicitly, especially across multi-repo workspaces. Fence sibling workstreams ("the audit's plan owns release hygiene — not duplicated here"). A review of everything is a review of nothing.
3. **NAME THE IRREVERSIBLE DECISIONS.** Build an explicit freeze/irreversibility inventory (what becomes expensive after the tag). This is where the ceiling goes and where the handoff must be most precise.
4. **PRESERVE ELIMINATION RATIONALE.** Every rejected alternative gets wins/costs/why-rejected recorded IN the artifact — "why didn't we do X?" must stay answerable months later (decision-trail rule).
5. **FLAG UNCERTAINTY** as a dedicated section. Predictions ≠ findings; say which is which.
6. **VERIFY FORMATS, NOT JUST LOCATIONS.** Real prospect passes falsified *format* assumptions (line-anchored tokens that were `var()` indirections; hex colors that were RGB triplets; a 4-file rename that was a 14-file surface incl. a JS bundle and history docs). Any plan step that parses/renames/sweeps MUST be preceded by an enumeration sweep at planning time.
7. **CONFIDENTIAL inputs** (e.g., invention disclosures) are read for context, never reproduced in any artifact.
8. **Commit local, named paths, push held.** The chain's artifacts commit as they complete; pushing is the owner's separate gate.

## The review questions (Sections A–F, answered explicitly, evidence-cited)

- **A. PROBLEM–SOLUTION FIT.** Is the current shape the right thing for the job? Steelman 2–3 alternative framings (include "do nothing / minimal version" and "kill / fold elsewhere"); for each: wins, costs, verdict + preserved rationale.
- **B. FOUNDATIONAL CORRECTNESS.** Sound at the base, or patching a weak premise? Name each weak premise being patched around and the fix-at-base.
- **C. BUILT RIGHT.** Within the approach: data model, abstraction layers (flag any beyond ~3 that don't earn their cost), coupling/seams, testing & validation strategy, characteristic failure modes (especially SILENT ones).
- **D. GAPS.** The smallest set of missing capabilities that makes it "v-next worthy." Assign existing owners where they exist — don't re-own work another plan already owns.
- **E. OVER-BUILD.** What exists that the use case doesn't justify. Cut = archive-with-pointer or policy-freeze, not deletion (archive-don't-delete rule). Includes DOC decay (stale plans, falsified bug reports a cold executor would burn time on).
- **F. PRODUCT / PORTFOLIO COHERENCE.** Boundaries (free/premium, public/private), monetization/positioning soundness, family coherence across sibling projects, licensing/IP posture. This is where "adapt the product or adapt the use case — or kill" gets answered honestly.

## The chain (deliverables, in order)

```
0. INVOCATION   project block: scope root · read-first list · THE irreversible decision ·
                section-F inputs (strategy docs) · constraints (read-only repos, build rules)
1. SURVEY       read-first docs + source tree + empirical probes; verify every claim live
2. FINDINGS     <scope-root>/FABLE-REVIEW-<YYYY-MM-DD>.md (or AUDIT-<date>-foundational-review.md):
                VERDICT (foundationally-sound | sound-with-changes | re-scope | reconsider,
                + the single most important reason) · PREMISES table (P1.. with "if it changes")
                · sections A–F · irreversibility inventory table · uncertainty flags
3. DESIGN SPEC  docs/superpowers/specs/<date>-<topic>-design.md per substantive change:
                numbered decisions D1..Dn (each: what, why, smallest version, rejected
                alternatives) · GATES G-A.. (decision, what it blocks, default-if-any)
                · non-goals · sibling-workstream fencing
4. PLAN         docs/superpowers/plans/<date>-<topic>.md: N tasks COLD-EXECUTABLE with no
                access to the reviewer's reasoning — exact paths, supplied code/content,
                commands + expected output, acceptance criteria, dependency sequence,
                OWNER per task, execution-notes preamble (build rules, restore
                steps, no-push, named-path commits, known-baseline counts).
                Team-owned repos: the unit of execution is a tracker ticket
                (Product + Technical Intake), not a code edit.
5. /PROSPECT    on the plan (file scope). APPLY verdict-changing amendments IN PLACE
                (don't just score), stamp the verdict + amendment list into the plan
                header, write the log to <knowledge_root>/logs/prospect/.
6. COMMIT + KICKOFF  commit artifacts (named paths, no push); end with a paste-ready
                executor kickoff: plan path(s), task order, definition of done,
                what to report back.
```

**Scale the chain to the finding.** One change → findings + a short plan. Large review → findings + several specs + plans. Minor items stay as plan rows; only substantive changes get a spec. Verdict = re-scope/reconsider → the spec/plan may be a wind-down or pivot plan; that's a valid chain output.

## The extension loop (optional second pass)

Run when the owner wants the deeper "is the SYSTEM itself good engineering?" layer on top of the freeze/ship question:

1. **System-design assessment** appended to the findings doc (§11-style): novelty ranked by defensibility vs the field; honest weaknesses; abstraction-architecture verdict (decision-surfaces count, layer ownership); a ranked improvement ladder; assessment uncertainties (untested claims marked benchmarkable). Look for ONE unifying critique — a single lens that explains all the improvements is a sign the analysis converged (one real run's was *authored-discipline-vs-executable-mechanism*).
2. **Durable capture**: the unifying critique → a canonical pattern file in knowledge (`projects/<tag>/patterns/` or `approaches/`); session arc → project memory + memory index.
3. **Second chain**: improvement ladder → roadmap SPEC (decisions in waves: W0 enforce-existing-claims · W1 evidence probes, each with a NAMED FALSIFICATION OUTCOME · W2 architecture evolutions gated on W1 evidence) → /prospect → wave-executable PLAN → /prospect → commit. Probes-before-architecture is the spine: every Wave-2 commitment must have a Wave-1 spike that can kill it cheaply.

## Artifact conventions

- Findings: `<scope-root>/FABLE-REVIEW-<YYYY-MM-DD>.md` (reviewer-named for provenance even when the default model runs it: keep the filename, state the actual model in the header).
- Specs/plans: the project's existing `docs/superpowers/{specs,plans}/` convention.
- Prospect logs: `<knowledge_root>/logs/prospect/<date>-file-<slug>.md` with standard frontmatter.
- Verdict taxonomy (fixed vocabulary): **foundationally-sound · sound-with-changes · re-scope · reconsider**.
- Gates: `G-A..` (review chain) / `M-G1..` or chain-prefixed (extension chain). Every gate row: decision needed, what it blocks, default-if-unanswered (or "hard gate, no default").

## Failure modes this process has already caught (check against them every run)

- `fix-without-call-site-audit` — rename/sweep steps written from the sites the review happened to verify (fired in real prospect passes).
- Un-sourced FORMAT assumptions — see operating rule 6.
- Misattributed file claims inherited from sibling audits — re-derive by sweep at planning time, never inherit.
- "Verification" runs that mutate build artifacts (an agent "verified a build" by running it and overwrote a generated source file) — every test-build step carries an explicit RESTORE + `git diff --stat` check.
- Plan/idea-dump decay — stale or falsified backlog items inside the release plan an executor would act on.
- History rewriting in mechanical sweeps — split live-vs-historical surfaces before any `sed` (archive-don't-delete).

## Companion format: the readiness audit — paired, not merged

The checklist-against-a-surface audit stays its OWN format — it recurs, needs no irreversible-decision anchor, and answers "is it clean/legal/consistent to ship," not "should this shape exist." Its structure: context + locked decisions up top · **tiered findings** (Tier 0 blockers / High / Medium / Low-hygiene) each with an Evidence column verified that session · **agent-claim corrections** as an explicit decision trail · conceptual observations (no code change proposed) · **phased remediation plan** · end-to-end verification recipe.

**Pairing rule:** when the chain's irreversible decision is a SHIP / FREEZE / PUBLIC-FLIP, run BOTH — audit for the surface, chain for the decision. The composition contract:

1. **Audit feeds the review** — its verified findings are admissible evidence; its locked decisions become review premises.
2. **The review re-derives inherited claims it leans on** — never trust the audit's file attributions or counts without a fresh sweep (a real review corrected an inherited file misattribution and a mis-scoped variable claim).
3. **One owner per remediation item** — the audit's phases keep their items; the chain's plan fences them out by reference ("the audit's Phase 2 owns H1–H7 — not duplicated here") and only adds tasks the audit's frame can't see (architecture-freeze risks, validation experiments).
4. **Gates unify** — gates from both land in ONE gate table (the chain's spec), so nothing ships on a gate answered in only one document.
5. **Order:** audit first when both are fresh (cheaper, produces the evidence base); chain's plan sequences relative to the audit's phases explicitly.

## Related

- `<knowledge_root>/rules/working-rules.md` — foundational design, the decision framework, archive-don't-delete, verify-current-docs
- The model-routing heuristic — default to the standard top model; escalate to the highest tier only at extreme difficulty / wide solution space / asymmetric cost-of-wrong
- `/prospect`, `/retrospect` — the validation passes this chain composes
- `/readiness-audit` — the recurring surface-audit sibling (the "Companion format" above)
