---
description: "Run a structured retrospective on a shipped commit range. Per-fix validation enforcement, simpler-alternative discipline, re-diagnosis, action verdicts, and a growing failure-mode pattern library. Trigger: '/retrospect', '/retrospect --range <ref1>..<ref2>', '/retrospect --pr <num>', '/retrospect --session', '/retrospect --commit <hash>'."
argument-hint: "[--range <ref1>..<ref2>] [--pr <num>] [--session] [--commit <hash>] [--linear]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# /retrospect — Release retrospective with validation enforcement

Run a structured retrospective on a shipped commit range (or single commit, or current session). Produces a 10-section markdown report with per-fix verdicts, validation status, action recommendations, and re-diagnosis when fixes failed. Writes findings to `knowledge/logs/retrospect/` and runs aria's standard intake. Source spec: `docs/specs/2026-05-03-retrospect-skill-design.md`.

## When to use

- After a release ships and the bug is partially or fully unresolved
- When the user reports a regression and a recent change set could be the cause
- Before proposing another fix to a bug that's already been "fixed" once
- As a soft-suggested response to user pushback ("review what you did," "are these changes necessary")

## Step 0: Inputs & Mode Detection

Parse the invocation arguments. Five modes:

| Mode | Trigger | Bundle source |
|---|---|---|
| **Auto-range** (default) | `/retrospect` (no args) | Last push on current branch — `git log @{push}..HEAD` if upstream is set, else `git log -10` and ask user to confirm range |
| **Explicit range** | `/retrospect --range <ref1>..<ref2>` | `git log <ref1>..<ref2>` |
| **PR** | `/retrospect --pr <num>` | `gh pr view <num> --json commits` then resolve to commit SHAs |
| **Session** | `/retrospect --session` | Files Claude has touched in the current conversation (read from session state, not git) |
| **Commit** | `/retrospect --commit <hash>` | Single commit |

The optional `--linear` flag (any mode) appends a summary post to referenced Linear tickets at the end of the retrospective. Off by default.

After mode detection, gather:

1. **Goal** — Ask the user: "What was this release/range supposed to fix? (One sentence is fine.)" If they don't reply, fall back to commit message subjects + PR description.
2. **Tickets** — Scan commit messages with regex `\b([A-Z]{2,}-\d+)\b` for Linear-style ticket IDs. If any are found AND Linear MCP is available, fetch each ticket's Product/Technical Intake + recent comments. If Linear MCP is unavailable, note "ticket context unavailable" but continue.
3. **Post-deploy outcome** — Ask the user: "For each fix, what's the post-ship evidence? (✅ closed / ⚠ partial / ❌ failed / ❓ untested)" Show the per-commit list and accept inline replies. If user can't supply evidence for any fix, mark those ❓ and note that §10 will recommend instrumentation.

If mode is `--session`, skip post-deploy outcome (no production yet) and tag all fixes 🚫 unvalidatable; their actions will resolve to HOLD-PENDING-DEPLOY.

## Step 1: Print the Anchor Block

Before producing any verdict, emit the anchor so the rest of the report can be traced to inputs:

```
Anchor:
  Goal:    <stated goal>
  Mode:    <auto-range | range | pr | session | commit>
  Range:   <commit range descriptor, e.g. v0.4.2..HEAD, 12 commits, 38 files>
  Tickets: <LINEAR-123 (Acceptance: ...), LINEAR-456 (...) | (none) | (unavailable)>
  Outcome: <user-supplied per-fix status table | (untested) | (per-session — no deploy)>
```

## Step 2: Load Pattern Libraries

Read the canonical pattern library at `~/knowledge/rules/retrospect-patterns.md` (resolved per `~/.claude/aria-knowledge.local.md` `knowledge_root`).

If the bundle is detected to belong to a known project (commits include paths under a configured `projects_list[<tag>].project_root`), additionally read `~/knowledge/projects/<tag>/retrospect-patterns.md` if it exists.

Hold both pattern lists in context for use in §4.4 (Failure-Mode Pattern Check). Do not run pattern detection yet — this step is just loading.

## Step 3: Enumerate Fixes

For the loaded bundle, enumerate each *fix*. A fix is one of:
- A commit whose message describes a fix or change (`fix:`, `feat:`, `refactor:`, etc.)
- A logical sub-change within a multi-concern commit (rare; usually 1 commit = 1 fix)

Number them `#1, #2, …` in commit order. For each fix, capture:
- Short SHA
- Subject line
- Files touched (path list)
- LOC added/deleted

If `--session` mode, enumerate by file-touch sets that resolve a single concern (Claude's judgment from session context).

## Step 4: Produce the 10-Section Retrospective Report

Render a markdown document with the 10 sections below in order. Each section heading uses `### N. <title>` format. Sections that don't apply to the current scope are emitted with a one-line "N/A: <reason>" — never silently skipped.

### 4.1. Section 1 — Anchor & Inputs

Re-emit the anchor block from Step 1, verbatim, as Section 1 of the report. This makes the report self-contained when read outside the chat.

### 4.2. Section 2 — Bundle-Verification Gate

For each fix from Step 3, ask: was the deployed bundle confirmed to contain this fix's code?

Acceptable evidence:
- Unique in-bundle marker present in the deployed asset (e.g., a string the user can `curl https://<deployed-url>/<bundle> | grep <marker>`)
- Deploy log + bundle hash matching the commit's CI artifact
- Source-map verification

If verification cannot be confirmed for a fix, mark it 🤷 **Bundle-unverified** in this section. Bundle-unverified fixes do NOT receive a Validated? status in §4.3 — instead, they're flagged here and their action defaults to HOLD-PENDING-VERIFICATION.

If the mode is `--session`, this section emits "N/A: per-session mode (no deploy yet)."

### 4.3. Section 3 — Per-Fix Verdict

For each fix from Step 3 that passed §4.2 (bundle verified or session mode), emit a horizontal-rule-separated block with these fields. Mirror the formatting style of the baseline review tag taxonomy (✅, ⚠ partial, ⚠ over-engineered, ⚠ theory-wrong, ⚠ counterproductive).

Required fields:
- **Status tag** — one of ✅ / ⚠ partial / ⚠ over-engineered / ⚠ theory-wrong / ⚠ counterproductive
- **Necessary?** — YES / NO / UNCLEAR with one-sentence reason
- **Complications introduced** — concrete list, or "None"
- **Minimal alternative** — "the smallest version of this change that would have addressed the goal." If the actual fix is the minimal version, write "This is the minimal version." Forces Rule 13.
- **Maintenance cost** — "what future contributors must now know / maintain because of this change." Forces Rule 12 / Rule 14.
- **Validated?** — one of the 5 statuses from Step 5 (or 🤷 if §4.2 flagged it)
- **Action** — one of: KEEP / REVERT / REDO-MINIMAL / FOLLOWUP-TICKET / HOLD-PENDING-EVIDENCE / HOLD-PENDING-DEPLOY (session mode only) / HOLD-PENDING-VERIFICATION (bundle-unverified only)

Optional field:
- **Rule cite** — if a complication maps to a Universal Rule overstep, cite it inline (e.g., "violates Rule 14 — abstraction beyond purposeful layers")

Render each fix as a block, not a wide table:

```
Fix #N: <subject> (<short-sha>)
Status:                <tag>
Necessary?:            <YES/NO/UNCLEAR> — <reason>
Complications:         <list or None>
Minimal alternative:   <description>
Maintenance cost:      <description>
Validated?:            <status>
Action:                <action>
Rule cite (optional):  <rule>
────────────────────────────────────────
```

**Hard rule:** A fix's Action cannot be KEEP unless its Validated? status is ✅ or ⚠ partial. ❓ / 🚫 / 🤷 force HOLD-PENDING-EVIDENCE / HOLD-PENDING-DEPLOY / HOLD-PENDING-VERIFICATION respectively.

### 4.4. Section 4 — Failure-Mode Pattern Check

Run the bundle against both pattern libraries loaded in Step 2 (canonical + project-specific if applicable). Detection is judgment-based — read each pattern's "Detection cues" and assess whether the bundle, commit messages, or session transcript exhibits them.

For each pattern hit, emit:

```
[PATTERN] <pattern-name> (source: rules/retrospect-patterns.md | projects/<proj>/retrospect-patterns.md)
  Evidence: <what in the bundle/transcript triggered the hit>
  Counter-discipline: <one-line reminder of the pattern's counter-discipline>
```

If no patterns hit, emit: "No catalogued failure-mode patterns detected. (See §9 for novel patterns.)"

### 4.5. Section 5 — Cross-Change Tally

Emit raw counts only — no interpretation in v1.

```
Tally:
  Fixes shipped:                    <N>
  Validated (✅):                    <N>
  Partially validated (⚠):           <N>
  Invalidated (❌):                  <N>
  Unvalidated (❓):                  <N>
  Unvalidatable (🚫):                <N>
  Bundle-unverified (🤷):            <N>
  Theory-driven refactors:          <N>
  Required by Linear acceptance:    <N>
  Discovered-during-process:        <N>
  Pattern hits this run:            <N>
```

A "theory-driven refactor" is a fix that rewrote working code based on a hypothesis rather than a confirmed bug location. Discovered-during-process means the fix addresses a bug found while working on something else (not the original goal).

Interpretation of these counts is left to §4.6, §4.7, and §4.9.

### 4.6. Section 6 — Re-frame Check

Three questions, in order. Answer each in 1–2 sentences with the supporting evidence.

1. **Is the original problem statement still right?** Or did the bundle reveal that the user-reported bug is a different bug than the bundle was aimed at?
2. **Was the bug correctly scoped?** Single bug, or multiple bugs presenting as one?
3. **Is the user-reproducible scenario still the right test?** Or has the testing surface drifted?

If the answer to #1 is "no," explicitly note: "Re-frame triggered. Hold all fixes targeting the *previous* problem statement pending re-diagnosis (§4.7)."

### 4.7. Section 7 — Re-diagnosis

List the **surviving hypotheses** for the actual root cause (only run this section if any fix was ❌ Invalidated or ⚠ partial, OR §4.6 triggered re-frame). For each hypothesis:

```
Hypothesis: <one-line statement>
  Evidence FOR:    <observations consistent with this hypothesis>
  Evidence AGAINST: <observations inconsistent>
  Confidence:      LOW / MEDIUM / HIGH
  To confirm:      <specific signal to look for — feeds §4.10>
```

Discarded hypotheses (ones the bundle's outcomes proved wrong) are listed separately under "Hypotheses ruled out by this retrospective" with one-line reasons. This is *learning*, not waste.

If all fixes are ✅ validated and §4.6 didn't trigger, this section emits "N/A: all fixes validated."

### 4.8. Section 8 — Action Verdict

Per fix, the action determined in §4.3. Render as a clear list:

```
Action verdict:
  Fix #1: <ACTION>  — <one-line reason>
  Fix #2: <ACTION>  — <one-line reason>
  ...
```

For REVERT actions, provide the exact `git revert <sha>` command. For REDO-MINIMAL actions, provide the minimal alternative diff (from §4.3). For FOLLOWUP-TICKET actions, draft a Linear ticket title + Product/Technical Intake skeleton.

End with an **Overall recommendation** in 1–3 sentences.

### 4.9. Section 9 — Process Retrospective

What the prior decision-making should have done differently. Format per item:

```
What I did:               <observed behavior>
What I should have done:  <better behavior>
Trigger condition:        <how to detect this situation in the future>
Pattern reference:        <pattern-name from library | (novel)>
```

If a behavior matches an existing pattern in the library, cite it. If a behavior is *novel* (not in either pattern library), prompt the user:

> "Identified a new failure-mode pattern: `<pattern-name>`. Add to:
>   1) Canonical (`rules/retrospect-patterns.md`) — applies project-agnostic
>   2) Project-specific (`projects/<proj>/retrospect-patterns.md`)
>   3) No — surface in this report only
> Choose: "

If user chooses 1 or 2, append a new entry to the corresponding file using the format defined in `rules/retrospect-patterns.md` ("Pattern entry format" section). The new entry's "First identified" field is today's date and the current retrospective's filename.

### 4.10. Section 10 — Next-Step Evidence Ask

Anti-speculation barrier. After §4.7 lists surviving hypotheses, this section names the **specific instrumentation, query, log, or measurement** needed before another fix is shipped. Format:

```
To confirm Hypothesis A (<short label>):
  - <specific instrumentation step 1>
  - <specific instrumentation step 2>
  - <add a unique [<TAG>-DIAG] marker so deployment verification is possible>

To confirm Hypothesis B (<short label>):
  - ...
```

End the section with this verbatim warning:

> **Do not ship another speculative fix until at least one item in this section is satisfied. If a new fix is proposed without new evidence, re-run `/retrospect`.**

## Step 5: Validation Status Taxonomy (reference)

When assigning Validated? in §4.3, choose one of the 5 statuses below. Bundle-unverified (🤷) is a precondition gate handled in §4.2, not a status.

| Status | Definition | Required sub-tag (in report) |
|---|---|---|
| ✅ **Validated** | Evidence shows the fix achieved its stated goal in the deployed state | **Evidence type**: log event \| reproduction-then-fix-verified \| production instrumentation \| deployed-state check. "Code review confirmed" is **not** validation. |
| ⚠ **Partially validated** | Evidence shows the fix changed something, but didn't fully close the bug | **Sub-tag**: `closed-part-of-target` \| `closed-different-bug` |
| ❌ **Invalidated** | Evidence shows the fix did NOT close the bug, or introduced a regression | **Sub-tag**: `didnt-fix` \| `introduced-regression` |
| ❓ **Unvalidated — evidence requestable** | No evidence yet, but the skill can describe the specific test/check that would validate | (none) |
| 🚫 **Unvalidatable** | Cannot be validated from current vantage point (requires production traffic, edge case not yet reproduced) | (none) |

When emitting a Validated? value, always include the required sub-tag where applicable. Examples:

- `Validated?: ✅ Validated (log event: apify_schema_mismatch confirmed absent post-deploy)`
- `Validated?: ⚠ Partially validated (closed-part-of-target: rehost cap raised but profile-image source still missing)`
- `Validated?: ❌ Invalidated (didnt-fix: bug reproduces on test #3)`
- `Validated?: ❓ Unvalidated — evidence requestable: needs <specific check>`
- `Validated?: 🚫 Unvalidatable: requires production traffic to surface`

## Step 6: Write Outputs

After Step 4 produces the report, write outputs to the configured destinations:

### Always
- Render the full report to terminal (chat).

### Default (configurable in `~/.claude/aria-knowledge.local.md` under `retrospect:` block — to be added when needed)
- **Persistent log:** Write the full report to `~/knowledge/logs/retrospect/<YYYY-MM-DD>-<slug>.md` where `<slug>` is derived from the goal or referenced ticket(s). Resolve `~/knowledge/` from the configured `knowledge_root`. Create the `logs/retrospect/` subfolder lazily on first use.
- **Aria intake:** Suggest entries for the four backlogs based on the report content:
  - Insights → observations like "fix #N's theory was wrong because <evidence>"
  - Decisions → "Reverted fix #N; reapplied minimal version" with rationale
  - Approaches → instrumentation patterns that worked (e.g., "[<TAG>-DIAG] marker pattern for bundle verification")
  - Working rules → if §4.9 identified a behavior that should become a Universal Rule, suggest it (do not persist without user approval per Rule 23)

  Project-scoped intake goes to `projects/<proj>/`; agnostic intake goes to the shared knowledge tree. Follow the standard aria intake confirmation flow (suggest, user reviews, write on approval).

### Opt-in
- **Linear comment:** Only when invoked with `--linear`. Post a *summary* (the Overall recommendation from §4.8 + the action verdict list) to each Linear ticket detected in commit messages. Use Linear MCP `save_comment`. Never post the full report — too much detail for the ticket.

### Pattern library write-backs
If §4.9 produced a novel pattern and the user approved adding it, the pattern entry is written to either:
- `~/knowledge/rules/retrospect-patterns.md` (canonical), or
- `~/knowledge/projects/<proj>/retrospect-patterns.md` (project-specific)

Pattern write-backs are *separate* from intake — they go directly to the patterns file, not through backlog review.

## Step 7: Soft-Suggest Trigger Logic (Claude-side judgment)

When the skill is *not* directly invoked, Claude monitors user messages for cues that suggest a retrospective is warranted. When detected AND the current session has shipped recent fixes (commits in the last hour or since the last `/retrospect`), Claude offers — never auto-executes — `/retrospect`.

Cues (non-exhaustive, judgment-based):

- "still broken," "still happening," "didn't fix," "no change"
- "regression," "same outcome," "reproducing again," "same bug"
- The user shares a test session log, transcript, or repro evidence that indicates failure
- Audit-shaped requests: "review what you did," "audit the changes," "are these necessary," "what did you change"

Standard offer (paraphrase as appropriate):

> "It sounds like the last release didn't fully close the bug. Before I propose another fix, want me to run `/retrospect` on the change set first? That'll force a validation check + re-diagnosis pass before we ship anything new."

Cue weight is judgment, not regex. When the cue is faint, just acknowledge and proceed. When the cue is clear, offer. Never auto-execute from a cue — always ask.

This logic also fires the `pushback-as-cue` pattern (see `rules/retrospect-patterns.md`) — they share the same trigger surface.

## Step 8: Validation Gates

Before finalizing the retrospective, verify:

1. **Anchor printed?** §4.1 must contain Goal, Mode, Range, Tickets, Outcome lines.
2. **Bundle-verification gate run?** §4.2 must address every fix from Step 3.
3. **Per-fix verdicts complete?** Every fix has all required fields (Status, Necessary?, Complications, Minimal alternative, Maintenance cost, Validated?, Action). Missing field = incomplete report.
4. **Validation hard rule respected?** No fix has Action: KEEP unless Validated? is ✅ or ⚠ partial. Verify before emitting.
5. **Pattern check ran?** §4.4 must reference both pattern libraries (canonical + project-specific if applicable).
6. **Tally consistent?** Counts in §4.5 must match the per-fix data in §4.3.
7. **Hypotheses present when needed?** §4.7 is required if any fix was ❌ Invalidated, ⚠ partial, or §4.6 triggered re-frame.
8. **Action verdict complete?** §4.8 must have an action for every fix in §4.3.
9. **Next-step evidence ask present when needed?** §4.10 is required if §4.7 produced any hypothesis.
10. **Outputs written?** Confirm the persistent log was written to disk and intake suggestions were surfaced.

If any check fails, self-correct once. If self-correction can't close the gap (e.g., the user must supply evidence), surface the gap explicitly in the report rather than silently skipping.
