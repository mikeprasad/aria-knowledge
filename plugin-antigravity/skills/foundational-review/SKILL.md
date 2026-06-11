---
name: foundational-review
description: "Run the foundational review chain on a project BEFORE an irreversible decision (version freeze, format/schema/spec tag, public API or repo flip, major re-scope, or a 'should we keep building this' moment). Verdict-led foundational review (sections A–F + premises + irreversibility inventory) → design spec (D-decisions + gates) → cold-executable plan (owner routing) → composed /prospect with amendments applied in place → commit + paste-ready executor kickoff. Optional --extend runs the system-design extension loop. REQUIRES an irreversible-decision anchor — no decision named → redirect to /prospect (plan pre-mortem) or /readiness-audit (surface audit). Triggers: '/foundational-review <scope-root>', '/foundational-review <scope-root> --decision \"<the irreversible decision>\"', '/foundational-review <scope-root> --extend', 'foundational review', 'review this at the foundations', 'is this the right thing built the right way'."
---

# /foundational-review — "Is this the right thing, built the right way?"

Run a repeatable, model-agnostic review of a project at the FOUNDATIONS — problem–solution fit, architecture soundness, product coherence — and convert the findings into a prospect-hardened, cold-executable plan with owner routing. This is the productized form of the foundational review chain (the canonical process doc this skill reads at Step 1).

This skill is **orchestration + artifact templates only**. The substance — the A–F review questions, the operating rules, the failure-mode library, the pairing contract — lives in the canonical process doc, which Step 1 reads in full. Do not reproduce that doc's content from memory; read it live every run so the chain evolves in one place.

**What this is NOT** (the process doc opens with this — internalize it):
- **Not a code review** — code review asks "are these changes correct?" on a diff. This asks "should this shape exist?" on a decision.
- **Not a readiness audit** — `/readiness-audit` checks a surface against a checklist and produces a findings list. This produces a VERDICT resting on named PREMISES plus the full execution handoff. Siblings, not substitutes (see the pairing contract in the Step 1 doc and Step 0's pairing check).
- **Not a retrospective** — `/retrospect` validates shipped work backward. This judges a standing architecture/product forward, before an expensive-to-undo step.

## When to use

Run it before any IRREVERSIBLE decision — the anchor:
- A version freeze or stable-contract claim
- A format / schema / spec tag (e.g., a `v1.0` spec freeze)
- A public API surface or a repo public-flip
- A major re-scope, pivot, or "should we keep building this at all" moment

**No irreversible decision named → do not run this chain.** Redirect:
- A plan that's about to execute → `/prospect`
- A surface to check clean/legal/consistent for shipping → `/readiness-audit`
- Already-shipped work to validate backward → `/retrospect`

## Step 0: Invocation Block

Parse `<scope-root>` (first positional), `--decision "<text>"`, and `--extend`. Then assemble the invocation block. If args are thin, collect interactively — **one ask at a time**:

```
Invocation:
  Scope root:           <path — the project/workspace under review>
  Read-first:           <docs to read before judging: CLAUDE.md, PROGRESS.md, specs, prior audits>
  THE irreversible decision:  <the single expensive-to-undo step this review gates — REQUIRED>
  Section-F inputs:     <strategy/positioning/licensing docs; mark CONFIDENTIAL ones>
  Constraints:          <read-only repos, build rules, no-push, team-owned repos needing tickets>
  Reviewer model:       <highest-ceiling available; see Model Routing below>
  Extend?:              <yes if --extend — runs the system-design extension loop after Step 6>
```

**Hard gate — the decision anchor.** If no irreversible decision can be named (the `--decision` arg is absent AND the user can't state one when asked), STOP and redirect:

> This chain is decision-anchored — it needs one expensive-to-undo step to anchor the verdict and the irreversibility inventory. You haven't named one. Did you mean:
>   1) `/prospect <plan>` — pre-mortem a plan that's about to execute
>   2) `/readiness-audit <scope-root> --for "<event>"` — audit a surface for ship-readiness
>   3) I'll name the irreversible decision now: <reply with it>

Do not invent a decision to keep the chain running.

**Pairing check.** If THE irreversible decision is a SHIP / FREEZE / PUBLIC-FLIP, the canonical pairing rule says run BOTH the audit (for the surface) and the chain (for the decision). Ask:

> This decision is a ship/freeze/flip. The pairing contract recommends running `/readiness-audit` first (cheaper, produces the evidence base the review can lean on). Run `/readiness-audit <scope-root> --for "<event>"` now, then resume this chain? (`y` / `n` / `already-have-one`)

On `y`, invoke `/readiness-audit` via the `Skill` tool, then resume at Step 1 with the audit as admissible evidence (per the composition contract — the review re-derives every inherited claim, never trusts the audit's attributions/counts without a fresh sweep).

### Model Routing

- **Reviewer = the highest-ceiling model available** (escalate to the top tier only when the decision is extreme-stakes; the default top model otherwise). The ceiling is spent on alternatives steelmanning (§A), portfolio/product judgment (§F), and the irreversibility inventory. **The default model can run the full chain** — it compensates with stricter evidence-sourcing in the /prospect passes.
- **Executor = the default model by default.** Every plan task (Step 4) carries `OWNER: <default model>` unless its *execution* needs extreme judgment — justify any top-tier owner in one line, or it's rewritten to the default.
- **Gate owner = the human.** Anything needing sign-off becomes a named gate `G-A..` in the spec (Step 3), never an inline assumption.
- **Effort ladder (when the reviewer is the top-tier model):** default `xhigh` for every substantive review — these passes are semi-agentic (read files, trace seams) and `xhigh` is built for that read-trace-reason loop; it also matches *why* you escalated to the ceiling. Use `high` only for light surfaces (small/on-hold/PRD-only projects). Reserve `max` for the single hardest correctness-dominated pass (e.g. auth-across-tenancy, ledger/tax invariants) — elsewhere it over-deliberates without adding signal. Running the top model at plain `high` is the worst-value point: if `high` feels like enough, the default model at `high` would have sufficed.

## Step 1: Load the Canonical Process & Survey

1. **Load the canonical chain.** Read the canonical process doc, preferring a user copy when present:
   - If `<knowledge_root>/approaches/foundational-review-chain.md` exists (resolve `<knowledge_root>` from `~/.gemini/antigravity/aria-knowledge.local.md`), read THAT — a user may keep a richer, project-specific copy there.
   - Otherwise read the plugin-bundled copy at `${CLAUDE_PLUGIN_ROOT}/skills/foundational-review/foundational-review-chain.md` (always present).

   It carries the operating rules, the A–F questions, the artifact conventions, the failure-mode library, and the pairing/extension specs. Hold it in context — every later step references it by section rather than restating it.
2. **Load the failure-mode libraries** (mirrors /prospect Step 2): `<knowledge_root>/rules/retrospect-patterns.md`, and `<knowledge_root>/rules/prospect-patterns.md` + `<knowledge_root>/projects/<tag>/{retrospect,prospect}-patterns.md` if they exist for the detected project.
3. **Survey the tree.** Read the read-first docs, then walk the actual source tree. **READ BEFORE JUDGING** (operating rule 1): every load-bearing claim is cited as `file:line`, verified THIS session — never asserted from memory, docs, or prior-session summaries.
4. **Bound the scope** (operating rule 2): state in-scope and out-of-scope explicitly; fence sibling workstreams by reference. For a multi-repo family, **group by coupling mechanism**: shared-runtime repos → review as ONE super-project (hub-out from the shared dependency, ~20% grounding / ~80% on the seams); protocol- or file-contract repos → review each side standalone + review the *contract* once from the producer side; a vendored copy → not a review seam at all. The same portfolio can contain all three.
5. **Run empirical probes** read-only (`git log`, `grep`, file-existence). **VERIFY FORMATS, NOT JUST LOCATIONS** (operating rule 6): any later plan step that parses/renames/sweeps is preceded by an enumeration sweep at planning time.

## Step 2: Findings Document

Write `<scope-root>/FABLE-REVIEW-<YYYY-MM-DD>.md` (keep the reviewer-named filename for provenance even when the default model runs it; state the actual model in the header). Structure:

```
# Foundational Review — <project> — <YYYY-MM-DD>
Reviewer model: <actual model>   |   THE irreversible decision: <text>

## Verdict
<foundationally-sound | sound-with-changes | re-scope | reconsider>
+ the single most important reason (one sentence).

## Premises
| ID | Premise the verdict rests on | If it changes… |
|----|------------------------------|----------------|
| P1 | …                            | …              |

## A. Problem–Solution Fit
Steelman 2–3 alternative framings (include "do nothing / minimal" and "kill / fold elsewhere");
for each: wins, costs, verdict + PRESERVED rationale (why-rejected stays answerable).

## B. Foundational Correctness
Name each weak premise being patched around + the fix-at-base.

## C. Built Right
Data model · abstraction layers (flag any beyond ~3 that don't earn their cost) · coupling/seams ·
testing & validation · characteristic failure modes (especially SILENT ones).

## D. Gaps
Smallest set of missing capabilities that makes it "v-next worthy." Assign existing owners; don't re-own.

## E. Over-build
What exists that the use case doesn't justify. Cut = archive-with-pointer or policy-freeze, not deletion.
Includes DOC decay (stale plans, falsified bug reports a cold executor would burn time on).

## F. Product / Portfolio Coherence
Boundaries (free/premium, public/private) · monetization/positioning · family coherence · licensing/IP posture.

## Irreversibility Inventory
| What becomes expensive after the tag | Why | Precision the handoff needs |

## Uncertainty Flags
Predictions ≠ findings — say which is which.
```

**Scale to the finding:** one change → findings + a short plan; large review → findings + several specs + plans. A re-scope/reconsider verdict's spec/plan may be a wind-down or pivot plan — that's a valid output.

## Step 3: Design Spec(s)

Per substantive change, write `docs/superpowers/specs/<date>-<topic>-design.md` (use the project's existing `docs/superpowers/` convention):

```
## Decisions
D1: what · why · smallest version · rejected alternatives (with preserved rationale)
…
## Gates
G-A: decision needed · what it blocks · default-if-unanswered (or "hard gate, no default")
…
## Non-goals
## Sibling-workstream fencing
"<sibling plan> owns <X> — not duplicated here."
```

Minor items stay as plan rows; only substantive changes get a spec.

## Step 4: Plan(s)

Per spec, write `docs/superpowers/plans/<date>-<topic>.md`. Tasks must be COLD-EXECUTABLE with no access to the reviewer's reasoning:
- Exact paths, supplied code/content, commands + expected output, acceptance criteria, dependency sequence.
- `OWNER:` per task (default executor; justify any top-tier owner in one line).
- An **execution-notes preamble**: build rules, restore steps, no-push, named-path commits, known-baseline counts (test counts, file counts).
- **Team-owned repos:** the unit of execution is a tracker ticket (Product + Technical Intake), NOT a code edit.

## Step 5: Compose /prospect

Run `/prospect` on each plan (file scope) via the `Skill` tool:

> Use the `Skill` tool to invoke `prospect` with `file <plan-path>`.

Then **APPLY verdict-changing amendments IN PLACE** — don't just score the plan. Validated runs' /prospect passes falsified *format* assumptions (line-anchored tokens that were `var()` indirections; hex colors that were RGB triplets; a 4-file rename that was a 14-file surface). After amending, stamp the verdict + amendment list into the plan header. The prospect log lands in `<knowledge_root>/logs/prospect/` via the composed skill — do not duplicate that routing here.

## Step 6: Failure-Mode Self-Check, Commit & Kickoff

**Pre-commit self-check (mandatory).** Run the plan(s) against the "Failure modes this process has already caught" list in the Step 1 process doc — this is the chain's equivalent of /prospect's pattern check. At minimum confirm:
- `fix-without-call-site-audit` — no rename/sweep step written only from the sites the review happened to verify
- Un-sourced FORMAT assumptions — every parse/rename/sweep preceded by an enumeration sweep
- Misattributed file claims inherited from a sibling audit — re-derived by sweep, never inherited
- "Verification" runs that mutate build artifacts — every test-build step carries an explicit RESTORE + `git diff --stat` check
- Plan/idea-dump decay — no stale/falsified backlog items inside the plan
- History rewriting in mechanical sweeps — live-vs-historical surfaces split before any `sed`

**Commit** the artifacts (named paths, no push — pushing is the owner's separate gate per operating rule 8). If `Bash`/`git` is unavailable, emit copy-paste commit messages instead.

**Kickoff.** End with a paste-ready executor kickoff:

```
## Executor Kickoff
Plan(s):        <path(s)>
Task order:     <#1 → #2 → …, note dependency gates>
Owner routing:  <default executor; any top-tier tasks + one-line justification>
Definition of done: <observable signals>
Open gates:     <G-A.. that must be answered before/at which task>
Report back:    <what to surface on completion>
```

## Step 7 (optional): Extension Loop  `--extend`

Run only when the owner wants the deeper "is the SYSTEM itself good engineering?" layer. Follow the process doc's "extension loop" section:
1. **System-design assessment** appended to the findings doc (§11-style): novelty ranked by defensibility; honest weaknesses; abstraction-architecture verdict; ranked improvement ladder; assessment uncertainties (mark untested claims benchmarkable). Look for ONE unifying critique — a single lens explaining all improvements signals the analysis converged.
2. **Durable capture** — the unifying critique → a canonical pattern file (`projects/<tag>/patterns/` or `approaches/`); session arc → project memory + memory index. Reuse `/extract` routing rather than duplicating it.
3. **Second chain** — improvement ladder → roadmap SPEC (waves W0 enforce-existing · W1 evidence probes each with a NAMED FALSIFICATION OUTCOME · W2 architecture evolutions gated on W1) → `/prospect` → wave-executable PLAN → `/prospect` → commit. Probes-before-architecture is the spine.

## Step 8: Outputs & Intake

- **Findings:** `<scope-root>/FABLE-REVIEW-<YYYY-MM-DD>.md`
- **Specs/plans:** the project's `docs/superpowers/{specs,plans}/`
- **Prospect logs:** via the composed `/prospect` (Step 5), in `<knowledge_root>/logs/prospect/`
- **Extension captures:** via `/extract` (Step 7), if `--extend`
- **Aria intake:** suggest backlog entries (insights / decisions / approaches) per the standard intake confirmation flow — suggest, user reviews, write on approval.

## Step 9: Validation Gates

Before declaring the chain complete, verify:
1. **Decision anchor present?** THE irreversible decision is named in the findings header. (If absent, the chain should have redirected at Step 0.)
2. **Read-before-judging honored?** Every load-bearing claim in the findings cites `file:line` verified this session.
3. **Verdict from the fixed vocabulary?** One of foundationally-sound · sound-with-changes · re-scope · reconsider, with its single most-important reason.
4. **Premises table present** with "if it changes" for each.
5. **Sections A–F all answered** (or marked N/A with reason) + irreversibility inventory + uncertainty flags.
6. **Specs carry D-decisions + gates;** plans are cold-executable with OWNER per task + execution-notes preamble.
7. **/prospect composed on every plan,** amendments applied IN PLACE, verdict stamped into the plan header.
8. **Pre-commit failure-mode self-check ran** against the process doc's list.
9. **Artifacts committed (named paths, no push);** kickoff emitted.
10. **Pairing honored** — if the decision was a ship/freeze/flip, either a `/readiness-audit` was run/referenced or the user explicitly declined.

If any check fails, self-correct once; if it can't be closed (e.g., a gate is unanswered), surface the gap explicitly rather than silently skipping.
