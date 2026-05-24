# Plan: Layer 5 Enforcement + Rule 22 Format Review

**Date:** 2026-04-18
**Status:** Draft — awaiting Mike review in a new session
**Scope:** Two linked workstreams targeting Rule 22 verbosity vs effectiveness
**Outcome this plan wants:** Decision on whether to spike Layer 5 + adopt the one low-risk format change

---

## Why this plan exists

ARIA v2.10.x Rule 22 enforcement is **advisory** (Layers 1–3: teach/foreground/recover). Hook messages have to persuade Claude into compliance because the hook cannot block. This creates a verbosity tax — every edit surfaces reminder text, named rationalizations, and doctrine pointers so the advisory layer carries weight. v2.10.2 named the text-hardening ceiling when an in-the-wild failure showed more words stopped buying compliance.

Layer 5 (filed in `intake/ideas-backlog.md`, 2026-04-18) proposes converting Rule 22 enforcement from advisory to structural — a PreToolUse hook that **blocks** Edit/Write when the preceding assistant text lacks a Rule 22 block. If buildable, it unlocks a cascade of verbosity reductions that the advisory layers currently have to carry.

Separately, the Rule 22 block format itself (LOW = 4 lines, HIGH = 8 lines) has been examined for efficiency without loss of effectiveness. This plan consolidates both analyses so the decision batch is coherent.

---

## Workstream A — Layer 5 feasibility spike

### Binary gate: transcript access

Investigation (2026-04-18) confirmed PreToolUse hooks receive a `transcript_path` in stdin JSON pointing to the session `.jsonl` file. Hooks can read backward to find the most recent assistant turn and scan for a Rule 22 block shape. Blocking mechanism: return `permissionDecision: "deny"` in a JSON payload (preferred over exit 2), which surfaces stderr to Claude for retry.

**Unresolved:** whether the `.jsonl` contains the **in-progress assistant turn** when PreToolUse fires. If the transcript only contains *completed* turns, the hook cannot see the text Claude just output in the current turn — which is the entire premise of Layer 5. The Claude Code docs do not specify this.

### The spike (~30 min)

**Goal:** binary answer to the in-progress turn question.

**Procedure:**

1. Write a throwaway PreToolUse hook in `aria/plugin-claude-code/bin/spike-transcript-dump.sh`:
   - Reads `transcript_path` from stdin JSON
   - Writes the last 20 lines of that file + timestamp to `/tmp/aria-spike-<timestamp>.log`
   - Returns success (exit 0, no blocking)
2. Register the hook in a test-only `.claude/settings.local.json` scoped to `Edit|Write`.
3. In a fresh Claude Code session, write a message with distinctive text ("SPIKE-MARKER-ABC123") followed by an Edit on a disposable file.
4. Inspect `/tmp/aria-spike-*.log`. Check:
   - Is "SPIKE-MARKER-ABC123" present in the dump?
   - Are preceding conversation turns present?
   - What's the JSONL entry shape for an in-progress assistant turn (partial? streaming chunks? fully buffered?)
5. Repeat for: (a) Edit in first message, (b) Edit after multi-line assistant prose, (c) Edit at end of long assistant turn.

**Outcomes:**
- **Greenlit:** preceding turn text is present and parseable → Layer 5 design is viable; proceed to detailed scoping (Workstream A2)
- **Blocked:** preceding turn text is absent or only present post-completion → Layer 5 as designed is not buildable; file findings in ideas-backlog and consider alternative mechanisms (UserPromptSubmit-based signaling, etc.)
- **Partial:** turn is present but in a form that requires non-trivial parsing → scope parser cost as part of A2

**Deliverable:** a short findings note committed to `aria/docs/specs/` with log excerpts + verdict. If greenlit, link to it from the ideas-backlog entry.

### Workstream A2 — Layer 5 design (contingent on spike greenlight)

Only proceed if the spike confirms feasibility. Three open design questions from the ideas-backlog remain:

1. **Block-shape regex calibration.** Must match `Low Impact —`, `High Impact —`, `Batch N/M —`, `Planning edit —` at line-start. Must NOT false-positive on prose that happens to contain "Low Impact" (e.g., doctrine files, chat about Rule 22 itself). Anchor strictly to line-start + em-dash separator + keyword after. Test corpus: 10 real session transcripts covering compliant + violating cases + meta-discussion cases.

2. **Skill-identity escape hatch.** ARIA's own skills (e.g., `/codemap` writing CODEMAP.md, `/audit-knowledge` writing intake files) legitimately produce Edits/Writes without Claude outputting Rule 22 blocks for internal machinery. Without an escape, Layer 5 blocks ARIA's own skills. Options:
   - (a) Env var marker (`ARIA_SKILL_EXEC=1`) that the skill sets before its Writes
   - (b) Detect skill context via stdin `session_id` + an in-flight skill registry
   - (c) Skip Layer 5 when the tool input path matches declared batch-manifest patterns
   - Recommend (a) as simplest; (c) as complement for batch ops.

3. **Retry UX.** After the hook blocks:
   - Does Claude Code retry transparently (Claude sees stderr as context, outputs block, re-invokes tool)?
   - Does Mike see a "tool call failed" error banner?
   - If the retry isn't silent, the verbosity win of Layer 5 is partially offset by error-banner noise.
   - Investigation: test with a `permissionDecision: "deny"` hook on a trivial edit and observe user-facing behavior.

**Target version:** v2.11.0 if all three resolve cleanly; otherwise phased rollout (regex + skill escape as v2.11.0, retry UX hardening as v2.11.1).

### Workstream A3 — Downstream verbosity reductions (after Layer 5 lands)

These are consequences of Layer 5, not independent work — but they're where the user-visible verbosity win actually appears. Cannot ship before Layer 5.

1. **Hook-injection text on pass → near-zero.** Today `pre-edit-check.sh` injects a multi-paragraph reminder on every non-exempt edit. After Layer 5, the hook either allows silently (block was there, Claude saw its own work) or denies tersely (block was missing, Claude gets a 1-line error). The paragraph-scale injection becomes obsolete. Target: `additionalContext` reduced to at most a single-line positive confirmation, or omitted entirely on pass.

2. **SessionStart reminder → pointer-only.** The Rule 22 doctrinal citation + named-rationalizations list exists in SessionStart because it's the only truly preventive layer under advisory enforcement. Once Layer 5 is preventive, SessionStart can shrink to a one-line pointer: `Rule 22 is enforced by PreToolUse. See rules/change-decision-framework.md.`

3. **Named-rationalization doctrine → archive, don't delete.** The doctrine text remains canonical reference (per Rule 6 archive-don't-delete), but is removed from hook/reminder surfaces. Still linked from the framework doc.

Estimated reduction: hook-injected text per session drops from ~200 lines (across 20 edits) to ~5 lines. SessionStart text drops from ~30 lines to ~2.

---

## Workstream B — Rule 22 block format review

### Findings

**LOW format (4 lines) is at or near floor.** Every slot carries a distinct enforcement role:
- Header → tier classification accountability
- Change → intake + criteria (compressed)
- Solutions → anti-premature-commitment gate (closes the "we already agreed" rationalization)
- Execute → scope declaration (post-edit validates against this)

Dropping any slot reopens a specific rationalization the v2.10.2 doctrine closed. No change recommended.

**HIGH format (8 lines) maps 1:1 to the 7 framework steps.** ADR 006 committed to full-format every-edit as anti-compression. Any structural reduction reopens that commitment and needs a new ADR, not a skill edit.

### Changes with slack

| Option | Change | Savings | Risk | ADR impact |
|---|---|---|---|---|
| **A** | Inline-flag `Validate` on HIGH — omit line on pass, emit only when flagging | 1 line per passing HIGH edit | Loses affirmative "I ran validate" signal | Low — interpret as presentation, not structural |
| B | Fold `Rank` into `Solutions` line: `Solutions — (a) [winner]; (b) [rejected: reason]` | 1 line per HIGH edit | Rank currently carries *why winner beats alternatives* — needs enforcement that winner-reasoning stays | Requires ADR update (step collapse) |
| C | Bare `Low Impact — description` header without reason | ~5 words per LOW edit | Loses the classification-accountability check | Requires ADR update |

**Recommendation:** Ship option A only, as a v2.10.x patch. Defer B and C — they need ADR reopening that isn't justified until Layer 5 lands and real data on format effectiveness is available.

### Changes without slack (do not ship)

- Dropping `Solutions` on LOW — reopens v2.10.2 rationalization
- Collapsing `Intake` + `Criteria` on HIGH — loses objective-basis discipline
- Removing header reason clauses — loses tier accountability

---

## Sequencing

Two parallel tracks; Track 1 gates Track 2.

### Track 1 — Layer 5 (multi-step, gated)

1. **Now:** spike the in-progress-turn question (A1, ~30 min)
2. **If greenlit:** design Workstream A2 (regex + skill escape + retry UX). Target v2.11.0.
3. **After Layer 5 ships:** execute A3 verbosity reductions. Target v2.11.1.
4. **If spike fails:** file alternative mechanism exploration in ideas-backlog; do not block Track 2.

### Track 2 — Format option A (small, independent)

1. Update `aria/plugin-claude-code/template/rules/change-decision-framework.md` HIGH Post-Edit Format (pass) to specify `Validate` as optional — only emit when flagging.
2. Update skill files that reference the HIGH format template (if any).
3. Bump to v2.10.5 (or bundle with the next patch release).
4. Monitor: does skipping `Validate` on pass correlate with more FLAG cases going uncaught? If yes, revert.

Track 2 can ship independently of Track 1. Small gain, low risk.

---

## Open decisions for Mike

These are the explicit decision points that need Mike's sign-off before moving forward. Answering these in the new session unblocks all downstream work.

1. **Run the Layer 5 spike?** Yes / No. If yes, greenlight ~30 min of throwaway-hook experimentation. If no, park the workstream.
2. **If spike greenlights: build Layer 5 as v2.11.0 target?** Yes / No / Needs more discussion. The three design questions (regex, skill escape, retry UX) each have low-risk defaults but benefit from explicit choice.
3. **Ship format option A (inline-flag Validate on HIGH pass)?** Yes / No / Needs more discussion. Independent of Layer 5; can be v2.10.5.
4. **Reopen ADR 006?** Not recommended in this plan. Only relevant if options B or C return for consideration after Layer 5 lands. Default: no.

---

## Cost estimates

| Item | Est. time | Risk |
|---|---|---|
| A1 spike | ~30 min | Low — throwaway hook |
| A2 Layer 5 design + build | ~4–6 hours | Medium — depends on spike findings |
| A3 verbosity reductions (after Layer 5) | ~1–2 hours | Low — deletion work |
| Track 2 option A | ~30 min | Low — doc + template edit |

---

## Non-goals / out of scope

- Reopening ADR 006 (full-format every-edit commitment) — not revisited unless Layer 5 surfaces data justifying it
- Layer 4 measurement hook — rejected 2026-04-18 on token-cost grounds; not revisited in this plan
- Minimal-tier impact level below LOW — separate idea in ideas-backlog, not bundled here
- Hook-format evolution for Opus 4.7 thinking — separate deferred item in ideas-backlog
- Changes to PostToolUse / scope-check output — this plan only addresses pre-edit format

---

## References

- `intake/ideas-backlog.md` — Layer 5 entry (2026-04-18), four design questions
- `knowledge/projects/aria/decisions/036-rule22-ordering-discipline.md` — shipped layer model
- `knowledge/projects/aria/decisions/006-full-rule22-format-every-edit.md` — anti-compression commitment
- `knowledge/projects/aria/decisions/021-rule22-ceremony-plan-a.md` — batch-manifest precedent
- `aria/plugin-claude-code/template/rules/change-decision-framework.md` — current format definitions
- `aria/plugin-claude-code/bin/pre-edit-check.sh` — hook whose injection text Track 1 would later reduce

---

## Pickup notes for a cold session

If you (Claude, new session) are reading this to pick up: start by reading this plan end-to-end, then `knowledge/projects/aria/decisions/036-rule22-ordering-discipline.md` for the layer model that Layer 5 extends. Don't re-derive the feasibility analysis — it's settled as of 2026-04-18 (transcript_path exists in PreToolUse stdin; in-progress turn inclusion is the open question). The first real action to take is the spike in Workstream A1 — everything else depends on its outcome.
