# `/retrospect` Skill — Design Spec

**Status:** Draft for review
**Date:** 2026-05-03
**Author:** Mike Prasad (with Claude)
**Plugin:** `aria-knowledge`
**Skill folder:** `plugin-claude-code/skills/retrospect/`

---

## 1. Motivation

When a release ships and the underlying problem isn't actually closed — or new complications appear — the failure mode is rarely a single bad fix. It's a *bundle* of changes where some were necessary, some addressed a misdiagnosed cause, and some over-engineered a working code path. Without a structured retrospective, the next instinct is to ship another speculative fix, repeating the loop.

The `/retrospect` skill makes a structured retrospective the default response to a failed/partial release, and treats *post-deploy reality* (not pre-merge code review) as the primary source of truth.

### Design constraints

- **Don't duplicate baseline diff review.** The skill *adds layers* (validation enforcement, simpler-alternative test, maintenance-cost projection, re-diagnosis, process retrospective, failure-mode pattern detection, next-step evidence ask). It assumes Claude can read a diff already.
- **Validation is non-negotiable.** No fix is marked effective without explicit, named evidence. Unvalidated fixes are flagged prominently, not quietly counted.
- **The skill is a feedback loop, not a report.** Failed fixes become evidence for re-diagnosis. The output ends with what to *measure next*, not another speculative fix.
- **Process patterns are reusable.** A failure mode identified in one retrospective ("ship-without-bundle-verification") becomes a check that runs against every future retrospective.

---

## 2. Scope & Invocation

### Primary scope: per-push / per-release range

A *bundle of commits tied to one shipping intent* — typically a push, tag-to-tag range, or PR. This is the headline mode because it matches the "release shipped, didn't close the bug" scenario directly and gives the skill access to post-deploy outcome data.

### Secondary modes (inherit the same checklist with degraded inputs)

- **Per-commit** — single commit; the skill warns that "Necessary?" and "Validated?" judgments are weaker without a coherent shipping intent.
- **Per-session** — every file Claude touched in the current conversation; useful in-flight to catch over-engineering before it ships. No production validation is possible: all fixes are marked 🚫 **unvalidatable** and actions resolve to HOLD-PENDING-DEPLOY (a per-session-only action variant) rather than HOLD-PENDING-EVIDENCE. The skill warns that conclusions are advisory only until shipped.

### Invocation paths

1. **Slash command (primary):** `/retrospect [scope-args]`
   - `/retrospect` — auto-detects last push on current branch
   - `/retrospect --range <ref1>..<ref2>` — explicit commit range
   - `/retrospect --pr <num>` — GitHub PR range
   - `/retrospect --session` — files touched this session
   - `/retrospect --commit <hash>` — single commit

2. **Soft suggestion (Claude-side judgment):** When the user's message in the current session contains regression cues *and* the current session has shipped recent fixes, Claude offers `/retrospect` rather than starting another fix. Cues include (non-exhaustive):
   - "still broken," "still happening," "didn't fix"
   - "regression," "same outcome," "reproducing again"
   - sharing a test session log/transcript that indicates failure
   - "review what you did," "audit the changes"

   The offer is *always* an offer ("Before I propose another fix, want me to run `/retrospect` on the last release?"), never auto-execution.

---

## 3. Inputs & Anchors

The skill needs three inputs to produce a valid retrospective. Missing inputs are *requested explicitly* — not silently substituted.

| Input | Source | Required? | Fallback |
|---|---|---|---|
| **Stated goal** | User narration ("the release was supposed to fix X"); falls back to commit messages / PR description | Required | If absent, skill asks |
| **Linear ticket(s)** | Auto-detected from commit messages (`DEV-123`, `SUP-45`) via regex; pulled via Linear MCP for Product/Technical Intake + comments | Optional, enriching | If MCP unavailable, skill notes "ticket context unavailable" |
| **Post-deploy outcome** | User narration per fix, OR structured prompt ("for each fix, what's the post-ship evidence: ✅ closed, ⚠ partial, ❌ failed, ❓ untested?") | Required for all non-session-scoped retrospectives | If user can't supply, skill marks all fixes ❓ and recommends instrumentation |

The skill **prints the anchor block at the start of every retrospective** so verdicts can be traced to their inputs:

```
Anchor:
  Goal:    [stated goal]
  Range:   [commit range, e.g. v0.4.2..HEAD, 12 commits, 38 files]
  Tickets: [LINEAR-123 (Acceptance: …), LINEAR-456 (...)]
  Outcome: [user-supplied per-fix status table]
```

---

## 4. The 10-Section Retrospective Structure

Each retrospective produces a markdown report with these sections, in order. Sections that don't apply to the current scope (e.g., #2 bundle-verification on a session-scoped retrospective) are emitted with a one-line "N/A: [reason]."

### 4.1. Section 1 — Anchor & Inputs

The block from §3 above.

### 4.2. Section 2 — Bundle-Verification Gate

For each non-trivial fix, confirm the deployed bundle contains the fix's code. This is a **precondition for validation** (§5). Acceptable evidence:

- Unique in-bundle marker (a string, function name, or comment that can be `curl | grep`'d in the deployed asset)
- Deploy log + bundle hash matching the commit's CI artifact
- Source-map verification

If verification cannot be confirmed, the fix is marked 🤷 **Bundle-unverified** and **no validation status is assigned in §4.3**. The skill blocks "Action: Keep" until bundle verification is supplied.

### 4.3. Section 3 — Per-Fix Verdict Table

Preserve the baseline tag taxonomy (✅, ⚠ partial, ⚠ over-engineered, ⚠ theory-wrong, ⚠ counterproductive) and add five new fields (four required, one optional):

| Field | Description |
|---|---|
| **Status tag** | One of the verdict tags above |
| **Necessary?** | YES / NO / UNCLEAR — with one-sentence reason |
| **Complications introduced** | Concrete list, or "None" |
| **Minimal alternative** *(new, required)* | "The smallest version of this change that would have addressed the goal." Forces Rule 13. If the actual fix is the minimal version, write "This is the minimal version." |
| **Maintenance cost** *(new, required)* | "What future contributors must now know / maintain because of this change." A new abstraction layer, a new file to keep in sync, a new convention to remember. Forces Rule 12 / Rule 14. |
| **Rule cite** *(new, optional)* | If a complication maps to a Universal Rule overstep, cite it (e.g., "violates Rule 14 — abstraction beyond purposeful layers") |
| **Validated?** *(new, required)* | One of the 5 statuses (or 🤷 precondition gate) defined in §5 |
| **Action** *(new, required)* | One of: KEEP / REVERT / REDO-MINIMAL / FOLLOWUP-TICKET / HOLD-PENDING-EVIDENCE / HOLD-PENDING-DEPLOY (per-session mode only) |

Render as a horizontal-rule-separated block per fix (matching the baseline output format Mike prefers), not a wide table.

### 4.4. Section 4 — Failure-Mode Pattern Check

Run the bundle against the failure-mode pattern library (§6). **Detection is Claude judgment-based in v1**, not regex/grep automation: Claude reads each pattern's detection cues and assesses whether the bundle, commit messages, or session transcript exhibits them. Automated cue matching is out of scope for v1 — see §11.

Each pattern hit is reported as:

```
[PATTERN] <pattern-name> (source: rules/retrospect-patterns.md)
  Evidence: <what in the bundle/transcript triggered the hit>
  Reference: <link to pattern definition>
```

If no patterns hit, emit "No catalogued failure-mode patterns detected. (See §9 — Process retrospective — for novel patterns.)"

### 4.5. Section 5 — Cross-Change Tally

Raw counts only in v1. No interpretation. Examples:

```
Tally:
  Fixes shipped:                    6
  Validated (✅):                    2
  Partially validated (⚠):           0
  Invalidated (❌):                  0
  Unvalidated (❓):                  3
  Unvalidatable (🚫):                0
  Bundle-unverified (🤷):            1
  Theory-driven refactors:          3
  Required by Linear acceptance:    2
  Discovered-during-process:        4
```

Interpretation of these counts is left to §6 (Re-frame), §7 (Re-diagnosis), and §9 (Process retrospective).

### 4.6. Section 6 — Re-frame Check

Given the outcomes, three questions in order:

1. **Is the original problem statement still right?** Or did the bundle reveal that the bug Mike originally reported is a different bug than the bundle was aimed at?
2. **Was the bug correctly scoped?** (Single bug vs. multiple bugs presenting as one.)
3. **Is the user-reproducible scenario still the right test?** Or has the testing surface drifted?

If the answer to #1 is "no," the rest of the retrospective is treated as evidence for the *correct* problem statement, and the action verdict (§8) leans toward holding all "speculative" fixes pending re-diagnosis.

### 4.7. Section 7 — Re-diagnosis

Given the outcome data, list the **surviving hypotheses** for the actual root cause. For each:

```
Hypothesis: <one-line statement>
  Evidence FOR:    <observations consistent with this hypothesis>
  Evidence AGAINST: <observations inconsistent>
  Confidence:      LOW / MEDIUM / HIGH
  To confirm:      <specific signal to look for — feeds §10>
```

Discarded hypotheses (proven wrong by the bundle's outcomes) are listed separately under "Hypotheses ruled out by this retrospective" with a one-line reason — this is *learning*, not waste.

### 4.8. Section 8 — Action Verdict

Per fix, one of:

- **KEEP** — fix is validated and minimal. No action needed.
- **REVERT** — fix is invalidated, over-engineered, or counterproductive. Provide the revert command.
- **REDO-MINIMAL** — fix targeted a real gap but in an over-engineered way; revert + reapply with the minimal alternative from §3.
- **FOLLOWUP-TICKET** — fix is partially valid but a follow-up issue is needed (write Linear ticket draft).
- **HOLD-PENDING-EVIDENCE** — fix may be load-bearing but needs validation evidence first; do not revert and do not deploy further fixes until §10 is satisfied.

**Hard rule:** A fix cannot reach KEEP unless its Validated? status is ✅ or ⚠ partial. ❓ / 🚫 / 🤷 force HOLD-PENDING-EVIDENCE.

End with an **Overall recommendation** (1–3 sentences).

### 4.9. Section 9 — Process Retrospective

What the prior decision-making should have done differently. Format:

```
What I did:        <observed behavior>
What I should have done: <better behavior>
Trigger condition: <how to detect this situation in the future>
```

If a behavior matches an existing pattern in the library (§6), this section cites it. If a behavior is *novel*, the skill prompts: "Add this to the pattern library? (canonical / project-specific / no)" — see §10 for the write-back flow.

### 4.10. Section 10 — Next-Step Evidence Ask

The skill's anti-speculation barrier. After §7 (re-diagnosis) lists surviving hypotheses, this section names the **specific instrumentation, query, log, or measurement** needed before another fix is shipped.

Examples:

```
To confirm Hypothesis A (stale shadow flush):
  - Add console.log in flushShadowIfPresent showing the shadow payload pre-flush
  - Inspect localStorage for cs-builder-shadow-* keys after logout
  - Network tab: capture PUT body during active session AND post-reopen

To confirm Hypothesis B (buildPayload mid-logout race):
  - console.log in attemptSave's buildPayload showing all 5 store states
  - Add a unique [SXX-DIAG] marker so Mike can confirm the new code is in the bundle
```

The skill **explicitly states**: *"Do not ship another speculative fix until at least one item in this section is satisfied. If a new fix is proposed without new evidence, this skill should be re-run."*

---

## 5. Validation Status Taxonomy

The status assigned per fix in §4.3:

| Status | Definition | Required sub-tag | Skill behavior |
|---|---|---|---|
| ✅ **Validated** | Evidence shows the fix achieved its stated goal in the deployed state | **Evidence type** (log event / reproduction-then-fix-verified / production instrumentation / deployed-state check). "Code review confirmed" is **not** validation. | Counted as effective. Eligible for KEEP. |
| ⚠ **Partially validated** | Evidence shows the fix changed something, but didn't fully close the bug | **Sub-tag**: "closed-part-of-target" or "closed-different-bug" | Flagged. Forces §6 re-frame consideration. Eligible for KEEP or REDO-MINIMAL. |
| ❌ **Invalidated** | Evidence shows the fix did NOT close the bug, or introduced a regression | **Sub-tag**: "didn't-fix" or "introduced-regression" | Flagged hard. REVERT default. Feeds §7 re-diagnosis. |
| ❓ **Unvalidated — evidence requestable** | No evidence yet, but the skill can describe the specific test/check that would validate | (none) | Skill *asks* for that evidence before finalizing. Forces HOLD-PENDING-EVIDENCE. |
| 🚫 **Unvalidatable** | Cannot be validated from current vantage point (requires production traffic, edge case not yet reproduced) | (none) | Flagged with the *blocking unknown* named explicitly. Forces HOLD-PENDING-EVIDENCE. |

### Precondition gate

🤷 **Bundle-unverified** — couldn't confirm the deployed code contains the fix. From the retrospective's Principle 3: "I never checked that my deploys actually contained my code." If a fix is bundle-unverified, *no validation status is assigned in §4.3* — the skill blocks and asks for verification first.

---

## 6. Failure-Mode Pattern Library

A catalogued, growing list of process failure patterns the skill checks against in §4.4.

### File layout (two-tier)

| Tier | Path | Loaded when | Contents |
|---|---|---|---|
| Canonical (agnostic) | `knowledge/rules/retrospect-patterns.md` | Always | Patterns that generalize across projects: speculative-fix loop, bundle-unverification, phrase tells, theory-from-shape-not-path, etc. |
| Project-specific | `knowledge/projects/<proj>/retrospect-patterns.md` | When the retrospective's range is detected as project-scoped | Patterns specific to that project's stack, deploy pipeline, or domain (e.g., CS-specific Apify-paywall pattern, SS-specific bundle-vs-server schema-drift pattern) |

### Pattern entry format

```
## <pattern-name>

**Tier:** canonical | project-specific (<project>)
**First identified:** <date> in <retrospective-source>
**One-line summary:** <description>

### Detection cues
- <textual cue 1>
- <code/structural cue 2>
- <commit-message cue 3>

### Why it's a problem
<2-3 sentences explaining the failure mode>

### Counter-discipline
<the behavior that prevents it>

### References
- [retrospective:<date>:<topic>] — first occurrence
- [retrospective:<date>:<topic>] — recurrence
```

### Seeding patterns from real retrospective evidence

The skill is initialized with canonical patterns derived from a real CS retrospective. **Sanitization note:** because aria-knowledge ships as a public repo, seeded pattern entries must be scrubbed of project-specific identifiers (session names, internal URLs, ticket numbers, user names) before they land in `plugin-claude-code/template/rules/retrospect-patterns.md`. Pattern names and descriptions stay generic; concrete examples that reference proprietary detail go in project-specific pattern files (`knowledge/projects/<proj>/retrospect-patterns.md`), which are not committed to the public template.

Initial canonical patterns:

1. **diagnose-from-shape-not-path** — building theories from data shape rather than tracing the code path the user's reproducer hits
2. **fix-bundling** — shipping multiple fixes per deploy, making attribution impossible when the bug reproduces
3. **bundle-unverification** — assuming "deploy succeeded → code running" without an in-bundle marker
4. **speculative-iteration** — shipping ≥2 fixes for the same bug without instrumentation between them
5. **judgment-confused-with-evidence** — treating "consistent with all evidence" as "right"
6. **phrase-tell-consistent-with-evidence** — the literal phrase "consistent with all evidence" / "the data is consistent with X" appearing in commit messages or session transcripts as a yellow flag
7. **pattern-matched-from-memory** — invoking a remembered failure mode without tracing the actual current code path
8. **pushback-as-cue** — when the user pushes back ("review and validate"), the right response is "yes, let's audit" — not "let me try one more thing"
9. **user-not-recruited** — fix-from-a-distance when asking the user to inspect their browser/state would be faster

### Write-back flow (§9 → library)

When §9 (Process retrospective) identifies a *novel* pattern not in the library, the skill prompts the user:

> "Identified a new failure-mode pattern: `<pattern-name>`. Add to:
>   1) Canonical (`knowledge/rules/retrospect-patterns.md`) — applies project-agnostic
>   2) Project-specific (`knowledge/projects/<proj>/retrospect-patterns.md`)
>   3) No — surface in this report only
> Choose: "

If the user chooses 1 or 2, the skill writes the new entry per the format above, with the current retrospective as the "first identified" reference.

---

## 7. Output Format & Destinations

### Format

A single markdown document with the 10 sections in §4. Section headings use the `### N. <title>` format (matching the rest of the aria-knowledge plugin).

### Destinations

| Destination | Default | Configurable | Notes |
|---|---|---|---|
| Terminal | Always | No | Full report rendered in chat. |
| `knowledge/logs/retrospect/<date>-<topic>.md` | Yes | Yes | Persistent retrospective record. Topic auto-derived from goal/tickets. |
| Aria intake (insights/decisions/approaches) | Yes | Yes | Standard aria intake flow per `feedback_intake_dual_purpose`. Skill suggests entries, user confirms before write. |
| Linear comment on referenced ticket(s) | No | Yes (`--linear` flag) | Posts a *summary* (not the full report) to each referenced ticket. Requires explicit per-invocation flag. |

The persistent log location (`knowledge/logs/retrospect/`) is new and created on first use. It sits alongside the existing aria knowledge structure without disturbing it.

---

## 8. Soft-Suggest Trigger (Claude-Side Judgment)

The skill's `SKILL.md` includes instructions for Claude to monitor user messages for regression-report cues. When detected *and* the current session has shipped recent fixes (commits in the last hour or since the last `/retrospect`), Claude offers:

> "It sounds like the last release didn't fully close the bug. Before I propose another fix, want me to run `/retrospect` on the change set first? That'll force a validation check + re-diagnosis pass before we ship anything new."

Cue detection is *judgment*, not regex. The skill instructs Claude to weight the strength of the cue against the cost of asking — when the cue is faint, just acknowledge and proceed; when the cue is clear, offer.

The skill *never* auto-executes `/retrospect` from a cue. It always asks.

---

## 9. Plugin File Layout

```
plugin-claude-code/skills/retrospect/
  SKILL.md                         # Skill instructions (Claude-readable)
  references/
    layered-structure.md           # Detail on the 10 sections, with examples
    validation-taxonomy.md         # Detail on §5 (status + sub-tags)
    pattern-library-format.md      # Detail on §6 entry format + seeding
    soft-suggest-cues.md           # Cue list and judgment guidance
  templates/
    retrospect-report.md           # Skeleton output template
    pattern-entry.md               # Template for new pattern library entries

plugin-claude-code/template/rules/
  retrospect-patterns.md           # Canonical pattern library (seeded with 9 patterns from §6)

plugin-claude-code/template/projects/<proj>/
  retrospect-patterns.md           # Created lazily when first project-specific pattern is added

plugin-claude-code/template/logs/retrospect/   # Created on first /retrospect invocation
```

The `template/` directory is the aria-knowledge plugin's standard pattern for files that get copied into a user's `knowledge/` folder during `/setup` — so the canonical pattern library ships as a template and is installed alongside other knowledge assets.

A new slash command at `commands/retrospect.md` invokes the skill with the user's args.

---

## 10. Knowledge Intake Integration

After producing the retrospective, the skill runs aria's standard intake flow per `feedback_intake_dual_purpose`. Likely intake categories from a typical retrospective:

- **Insights** — observations like "fix #N's theory was wrong because [evidence]"
- **Decisions** — "Reverted fix #N; reapplied minimal version" with rationale
- **Approaches** — instrumentation patterns that worked (e.g., "[S60-DIAG-FIX5] marker pattern")
- **Working rules** — if §9 identified a behavior worth a Universal Rule, the skill suggests it (Mike approves before persisting per `feedback_review_learnings_before_saving` / Rule 23)

Pattern library write-backs (§6) happen *separately* from intake — they go to `rules/retrospect-patterns.md` directly, not through general intake.

Project-specific intake goes to `knowledge/projects/<proj>/`; agnostic intake goes to the shared knowledge tree.

---

## 11. Out of Scope (v1)

Deferred to v2 with explicit reasoning:

- **Cross-change pattern *interpretation*** (e.g., "3 of 6 are theory-driven refactors → systemic over-engineering signal"). v1 emits raw counts in §4.5; interpretation requires usage data to know which patterns are real signal vs. noise.
- **Automated pattern cue matching.** v1 detection is Claude judgment-based (§4.4). A v2 enhancement could add regex/AST-based cue matching for textual tells like the "consistent with all evidence" phrase, with judgment still primary for structural cues.
- **Auto-trigger on git push events.** v1 is slash-command + soft-suggest only. Hook-based auto-trigger added once we know which release events deserve auto-prompting.
- **Linear ticket auto-creation for FOLLOWUP-TICKET actions.** v1 emits a draft; user creates the ticket. v2 can offer auto-creation via Linear MCP.
- **Multi-bundle/series retrospectives** (looking at a string of releases for trend analysis). v1 handles one bundle at a time.
- **Self-running retrospectives on Claude's own behavior across sessions.** §9 (process retrospective) is bundled-fix-scoped in v1; broader self-audit is a different skill.

---

## 12. Success Criteria for v1

The skill is working if, in real use:

1. After every release that surfaces a regression, `/retrospect` (or its soft-suggest offer) fires *before* a new fix is shipped.
2. Every per-fix verdict carries a Validated? status with named evidence — never a quiet "looks good."
3. At least one pattern from the canonical library catches a fit on the first non-trivial retrospective run on real CS/SS work.
4. The "next-step evidence ask" (§4.10) blocks at least one speculative fix that would otherwise have shipped.
5. The pattern library accumulates ≥3 new entries (canonical or project-specific) in the first month of use.

---

## 13. Open Questions

These are explicitly *not* blockers for v1 — flagging them so they can be revisited if they cause friction:

- **Q1:** Should the skill have a "lite mode" (`/retrospect --lite`) for tiny scope (1-2 commits) that skips §6 (re-frame) and §7 (re-diagnosis) and only runs the per-fix verdict + pattern check? Pro: lower friction. Con: encourages skipping the highest-leverage layers. **Default v1: no lite mode.** Revisit if usage shows the full version is too heavy for small scopes.
- **Q2:** When a retrospective concludes that the original bug was misdiagnosed (§6 says "problem statement is wrong"), should the skill auto-write a corrected problem statement to a designated location? **Default v1: report it in §6 only; manual intake.** Auto-write is too aggressive without seeing how often this happens.
- **Q3:** Should pattern hits trigger a check *across past retrospectives* (e.g., "this pattern has fired 4 times in the last 30 days → consider escalating to a Universal Rule")? **Default v1: no — log to file, manual review.** Auto-escalation belongs in v2 once we have signal data.
