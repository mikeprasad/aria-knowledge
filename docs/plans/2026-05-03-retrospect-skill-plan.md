# `/retrospect` Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `/retrospect` skill in the aria-knowledge plugin that runs structured retrospectives on shipped commits/releases, enforcing per-fix validation, simpler-alternative discipline, re-diagnosis, and a growing failure-mode pattern library.

**Architecture:** Single-file `SKILL.md` (matches aria convention) under `plugin/skills/retrospect/`. Canonical seeded failure-mode pattern library at `plugin/template/rules/retrospect-patterns.md` (registered as plugin-managed). Per-project patterns at `knowledge/projects/<proj>/retrospect-patterns.md` (user-owned). Output destinations: terminal (always), `knowledge/logs/retrospect/<date>-<topic>.md` (default), aria intake (default), Linear comment (opt-in). Follows aria's existing skill-as-slash-command pattern (`/retrospect` → `plugin/skills/retrospect/SKILL.md`).

**Tech Stack:** Markdown (skill instructions), bash (no new hook scripts in v1), aria-knowledge plugin conventions.

**Source spec:** `docs/specs/2026-05-03-retrospect-skill-design.md`

**Reference files (read these before starting any task):**
- `docs/specs/2026-05-03-retrospect-skill-design.md` — the full design spec, source of truth for content
- `plugin/skills/distill/SKILL.md` — example of a complex aria skill with YAML frontmatter and numbered Steps (similar shape to retrospect)
- `plugin/skills/audit-knowledge/SKILL.md` — example of aria's longest skill (62 KB); shows how aria handles skills with many phases
- `plugin/skills/setup/SKILL.md` — defines plugin-managed vs. user-owned templates; you will modify lines around 65 and 105
- `CHANGELOG.md` — for the changelog entry format
- `plugin/.claude-plugin/plugin.json` — version field
- `.claude-plugin/marketplace.json` — version field (auto-synced via release.sh per `feedback_auto_sync_over_fail_ask`)

**Versioning:** Patch bump 2.13.4 → 2.13.5 per `feedback_aria_versioning_patch_for_new_skill` (new isolated skill = patch in aria's policy). Confirm with Mike if uncertain.

**Public-repo constraint:** aria-knowledge ships publicly. All content created in this plan must be free of project-specific identifiers, internal URLs, ticket numbers, user names, and proprietary terms.

---

## Task 1: Create the seeded canonical failure-mode pattern library

**Files:**
- Create: `plugin/template/rules/retrospect-patterns.md`

**Why this task is first:** The pattern library is referenced by the skill (Step 4.4 in `SKILL.md`). Creating it first means the skill can reference an existing file. It's also the most sanitization-sensitive file (public repo), so doing it standalone makes review easier.

- [ ] **Step 1: Create the file with header + 9 seeded canonical patterns**

Write the complete file content below to `plugin/template/rules/retrospect-patterns.md`. All 9 patterns are derived from the spec's §6 "Seeding patterns" list. Sanitization is already applied — pattern names and detection cues use generic language; project-specific examples are explicitly omitted.

```markdown
<!-- plugin-managed: ARIA writes this file. Customize freely — your edits appear as diff prompts on plugin updates. -->

# Retrospect — Failure-Mode Pattern Library (Canonical)

This is the canonical, project-agnostic library of process failure patterns that the `/retrospect` skill checks for in every retrospective. New canonical patterns are added here over time as they emerge from real retrospectives. Project-specific patterns belong in `projects/<proj>/retrospect-patterns.md`.

## How patterns are used

When `/retrospect` runs, Claude reads each pattern's **detection cues** and judges whether the current bundle (commits, diffs, session transcript, deploy logs) exhibits them. Detection is judgment-based, not regex; in v2 some textual cues may be automated.

Each pattern hit is reported in the retrospective's §4.4 (Failure-Mode Pattern Check) section.

## Pattern entry format

Each pattern has the following structure:

- `## <pattern-name>` — kebab-case identifier
- `**Tier:**` canonical | project-specific (`<project>`)
- `**First identified:**` `<date>` in `<retrospective-source>`
- `**One-line summary:**` what the pattern is in one sentence
- `### Detection cues` — bulleted list of what to look for
- `### Why it's a problem` — 2–3 sentences on the failure mode
- `### Counter-discipline` — the behavior that prevents it
- `### References` — list of retrospectives where this pattern fired

---

## diagnose-from-shape-not-path

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** Building theories from the *shape* of observed data (DB pattern, log fingerprint, error frequency) rather than tracing the actual code path the user's reproducer hits.

### Detection cues
- Commit messages or session transcripts that justify a fix with phrases like "the data is consistent with X" or "this matches a Y pattern" without a concrete code-path trace
- Multiple fixes targeting the same observed symptom from different angles in one bundle (the spread itself is a tell that the cause was inferred, not located)
- Hypotheses that name a *category* of bug (race condition, stale cache, drift) but not a specific function or line

### Why it's a problem
Pattern matching from memory is faster than tracing, so it feels like progress. But shape-consistency is not causation: many distinct bugs produce identical data shapes. Shipping a fix on shape-only evidence leaves a non-trivial probability that the actual code path is untouched.

### Counter-discipline
Before writing a fix, articulate the *exact* line(s) of code believed to be wrong and the *exact* control-flow trace that reaches them in the user's reproducer. If the trace can't be articulated, instrument first (see `bundle-unverification` and `speculative-iteration` for related disciplines).

### References
- *(seeded — first canonical reference will be the retrospect skill's first real-use retrospective)*

---

## fix-bundling

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** Shipping multiple fixes per deploy, making attribution impossible when the bug reproduces.

### Detection cues
- A single deploy/release range containing 3+ fixes that target distinct hypotheses for the same user-facing bug
- Commit messages that bundle "fix A + fix B + improvement C" rather than one concern per commit
- No clear primary fix; the bundle relies on "one of these will work" reasoning

### Why it's a problem
When a bundle ships and the bug reproduces, you cannot tell which fix was load-bearing, which was harmless, and which made things worse. Rollback becomes coarse and re-diagnosis is muddied. The bundle also creates pressure to ship every fix at once, eliminating the deploy-per-bug feedback loop.

### Counter-discipline
One deploy per user-facing bug. Bonus fixes (typos, refactors, secondary issues) ship in their own deploys. Atomic commits get half the way there; deploy granularity gets the rest.

### References
- *(seeded)*

---

## bundle-unverification

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** Assuming "deploy succeeded → my code is running" without verifying the deployed bundle actually contains the fix.

### Detection cues
- No unique in-bundle marker (a string, function name, comment) added with the fix
- "Deploy succeeded" claimed solely from CI green or a deploy-platform OK message
- Browser-cached bundles or stale CDN edges not ruled out as a confounder when a fix appears not to work

### Why it's a problem
A successful deploy guarantees the artifact uploaded; it does not guarantee the user's session is running it. Cached bundles, stale workers, edge-cache lag, and source-map mismatches can all silently serve old code. Without a verifiable in-bundle marker, "this fix didn't work" and "this fix didn't ship" are indistinguishable.

### Counter-discipline
Add a unique marker to every non-trivial fix (e.g., a `[FIX-<id>]` console.log, a renamed function, a new exported constant). After deploy, confirm the marker is present in the served artifact (curl + grep, network-tab inspection, or source-map check) before treating "the bug still reproduces" as evidence about the fix.

### References
- *(seeded)*

---

## speculative-iteration

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** Shipping ≥2 fixes for the same bug without adding diagnostic instrumentation between them.

### Detection cues
- Two or more sequential commits/deploys that fix the same user-facing bug, with each one trying a different hypothesis
- No instrumentation commit between attempts (no console.log, no DB query, no measurement)
- The phrase "let me try X" or equivalent in session transcripts after the first failed fix

### Why it's a problem
After the first fix fails, the right move is to gather *new* evidence — not to ship another theory. Speculative iteration burns deploy cycles, user-test cycles, and trust, while preserving the original information deficit that produced the wrong fix in the first place. Each subsequent attempt has the same expected probability of success as the first.

### Counter-discipline
After a failed fix, the next deploy must be either (a) a revert + minimal-instrumentation deploy, or (b) an instrumentation-only deploy. No new fix ships until at least one new datum is in hand.

### References
- *(seeded)*

---

## judgment-confused-with-evidence

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** Treating "this hypothesis is consistent with all available evidence" as proof, when it is only a survival check.

### Detection cues
- Self-justifying language like "this is the most consistent with the data" or "all the evidence points to X"
- Confidence high, falsification test absent
- A theory that hasn't been actively challenged by trying to *disprove* it

### Why it's a problem
Multiple distinct hypotheses can be simultaneously consistent with the same evidence. "Survives the evidence" is the lowest bar a hypothesis must clear, not the highest. Mistaking it for "is true" leads directly to shipping speculative fixes confidently.

### Counter-discipline
For any hypothesis with high confidence, name the *specific signal* that would distinguish it from at least one alternative — and go gather that signal before acting. If you cannot name a discriminating signal, the hypothesis is not yet falsifiable in your current setup.

### References
- *(seeded)*

---

## phrase-tell-consistent-with-evidence

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** The literal phrase "consistent with all evidence" / "the data is consistent with X" is a high-leverage textual flag for `judgment-confused-with-evidence`.

### Detection cues
- Exact phrases in commit messages, session transcripts, or PR descriptions: "consistent with the data," "consistent with all evidence," "the data is consistent with," "matches a pattern of"
- Variants: "fits the pattern of," "looks like a [known issue type]"

### Why it's a problem
When this phrasing appears alongside a fix decision, the decision has typically been made on shape-evidence consistency rather than on direct code-path observation. The phrase is a reliable retrospective predictor of speculative fixing.

### Counter-discipline
When you notice the phrase forming in your own output, replace it with: "to confirm X, I'd need to see [specific signal]. Let's instrument for it." This converts a closure into a falsification test.

### References
- *(seeded)*

---

## pattern-matched-from-memory

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** Invoking a remembered failure mode (logout race, stale cache, etc.) without tracing the *current* code path to confirm the same mode applies.

### Detection cues
- Diagnostic language that references a *prior* incident or named bug class as evidence for the current diagnosis
- Fix design that mirrors a past fix structurally without a fresh trace of the current code

### Why it's a problem
The same symptom can appear in different code paths. A remembered failure mode is a hypothesis-generator, not a hypothesis-confirmer. Treating memory as evidence skips the trace and inherits the previous incident's blind spots.

### Counter-discipline
When a remembered pattern feels like a match, treat it as one candidate hypothesis among several. Add it to the §7 (Re-diagnosis) hypothesis list with explicit "Evidence FOR / AGAINST" — not as the working theory.

### References
- *(seeded)*

---

## pushback-as-cue

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** When the user pushes back ("review and validate," "audit the changes"), the right response is "yes, let's audit" — not "let me try one more thing."

### Detection cues
- User messages with audit cues ("review what you did," "are these changes necessary," "stop and look at this") followed by Claude proposing another fix
- Claude responses that frame pushback as a request for more diagnosis-by-Claude rather than a stop-signal

### Why it's a problem
Pushback is information: the user has detected that the speculative loop is unproductive and is offering an explicit course correction. Continuing to fix is overriding that signal with self-confidence.

### Counter-discipline
Treat audit-shaped pushback as a `/retrospect` invocation by default. Offer the retrospective; if the user declines, then return to fixing — but only with their explicit redirect.

### References
- *(seeded)*

---

## user-not-recruited

**Tier:** canonical
**First identified:** 2026-05-03 in retrospect-skill design
**One-line summary:** Diagnosing remotely from logs and code when asking the user to inspect their own browser/state would be faster.

### Detection cues
- Multiple speculative fixes for a state-related bug without ever asking the user to inspect their localStorage / IndexedDB / cookies / network panel / state-store contents
- Long internal hypothesis chains where a single 30-second user check would have falsified or confirmed the chain

### Why it's a problem
The user is at the keyboard with full access to runtime state. Claude is reading code from a thousand miles away (architecturally). For state-shape bugs, recruiting the user as a diagnostic collaborator is often the fastest path to ground truth.

### Counter-discipline
For any non-trivial state bug, before the second fix attempt, ask the user a specific check: "in DevTools, run `<exact code>` and tell me what it returns" or "show me localStorage keys matching `<pattern>`."

### References
- *(seeded)*
```

- [ ] **Step 2: Verify the file is well-formed**

Run: `wc -l plugin/template/rules/retrospect-patterns.md`
Expected: 100+ lines (≈150–200 with the headers and 9 patterns)

Run: `grep -c "^## " plugin/template/rules/retrospect-patterns.md`
Expected: At least 9 (one `## ` per pattern, plus `## How patterns are used` and `## Pattern entry format` — total 11)

- [ ] **Step 3: Sanitization spot-check**

Run: `grep -iE "S60|Nala|cs-builder|seersite|commonspace|mike|enrique|andrew|klinton|jude" plugin/template/rules/retrospect-patterns.md`
Expected: No matches. (The file must contain no project-specific identifiers per the public-repo constraint.)

If matches appear, edit the file to remove or genericize them before commit.

- [ ] **Step 4: Commit**

```bash
git add plugin/template/rules/retrospect-patterns.md
git commit -m "feat(retrospect): seed canonical failure-mode pattern library"
```

---

## Task 2: Create the `/retrospect` SKILL.md

**Files:**
- Create: `plugin/skills/retrospect/SKILL.md`

**Why this task ordering:** The pattern library (Task 1) is now in place, so the skill can reference it. The SKILL.md is the largest artifact and the heart of the feature.

**Reference materials for content (read before this task):**
- `docs/specs/2026-05-03-retrospect-skill-design.md` — sections 1–13 are the source content for the SKILL.md prose
- `plugin/skills/distill/SKILL.md` — for YAML frontmatter format and Step-numbering style

**Convention notes:**
- aria's SKILL.md files use YAML frontmatter with `description`, `argument-hint`, `allowed-tools` keys. Body uses `# /<command-name>` heading then numbered "Step N: …" sections.
- Step prose is *directive-style* (instructions to Claude), not narrative. Look at `plugin/skills/distill/SKILL.md` Step 0 onward for the voice.
- Content is dense; aria does not split skills into sub-files.

- [ ] **Step 1: Create the skill folder**

Run: `mkdir -p plugin/skills/retrospect`

- [ ] **Step 2: Write the SKILL.md frontmatter and Step 0 (Inputs & Mode Detection)**

Create `plugin/skills/retrospect/SKILL.md` with this opening content:

```markdown
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
```

- [ ] **Step 3: Append Step 4 (the 10-Section Retrospective)**

Append this content to the same `plugin/skills/retrospect/SKILL.md`. This is the bulk of the skill — the 10 retrospective sections, each with explicit instructions for what Claude must produce.

The content for each sub-step (4.1 through 4.10) maps directly to the corresponding spec section (§4.1 through §4.10 in `docs/specs/2026-05-03-retrospect-skill-design.md`). The skill must render *directives to Claude*, not narrative. For each sub-step below, the directive is written out fully — no placeholders.

```markdown
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
```

- [ ] **Step 4: Append Step 5 (Validation Status Taxonomy reference)**

Append this content to `plugin/skills/retrospect/SKILL.md`. This is the 5-status + 1-gate taxonomy used in §4.3 and §4.2.

```markdown
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
```

- [ ] **Step 5: Append Step 6 (Output Destinations)**

Append:

```markdown
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
```

- [ ] **Step 6: Append Step 7 (Soft-Suggest Trigger Logic) and Step 8 (Validation)**

Append:

```markdown
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
```

- [ ] **Step 7: Verify the SKILL.md is well-formed**

Run: `wc -l plugin/skills/retrospect/SKILL.md`
Expected: 350+ lines.

Run: `head -5 plugin/skills/retrospect/SKILL.md`
Expected: First line is `---` (start of YAML frontmatter), followed by `description:`, `argument-hint:`, `allowed-tools:`, `---`.

Run: `grep -c "^## Step " plugin/skills/retrospect/SKILL.md`
Expected: 9 (Steps 0 through 8).

Run: `grep -c "^### 4\." plugin/skills/retrospect/SKILL.md`
Expected: 10 (sub-sections 4.1 through 4.10).

- [ ] **Step 8: Sanitization spot-check**

Run: `grep -iE "S60|Nala|cs-builder|seersite|commonspace|enrique|andrew|klinton|jude" plugin/skills/retrospect/SKILL.md`
Expected: No matches. (Public-repo constraint.)

- [ ] **Step 9: Commit**

```bash
git add plugin/skills/retrospect/SKILL.md
git commit -m "feat(retrospect): add /retrospect skill with 10-section retrospective structure"
```

---

## Task 3: Register `retrospect-patterns.md` as a plugin-managed template

**Files:**
- Modify: `plugin/skills/setup/SKILL.md` (lines around 65 and 105 — the plugin-managed file lists)

**Why:** The seeded pattern library at `plugin/template/rules/retrospect-patterns.md` ships with the plugin and gets diffed on `/setup` runs. This means user-added patterns are preserved (presented as diff prompts) when the plugin updates the canonical library. Without this registration, `/setup` won't know to copy or diff the file.

- [ ] **Step 1: Read the current setup SKILL.md to confirm exact line content**

Run: `grep -n "Plugin-managed\|Files to diff" plugin/skills/setup/SKILL.md`
Note the exact text that needs updating. The two lines to modify:

- Line ~65: The educational note about plugin-managed files (`README.md`, `OVERVIEW.md`, `rules/working-rules.md`, `rules/change-decision-framework.md`, `rules/enforcement-mechanisms.md`)
- Line ~105: The diff-loop file list (`rules/working-rules.md`, `rules/change-decision-framework.md`, `rules/enforcement-mechanisms.md`, `README.md`, `OVERVIEW.md`, `projects/README.md`)

- [ ] **Step 2: Add `rules/retrospect-patterns.md` to the educational note**

Edit `plugin/skills/setup/SKILL.md`. Find the line containing `Plugin-managed` and the `rules/` entries, and add `rules/retrospect-patterns.md` to the list. The new file is *plugin-managed* (diffed) because users add their own patterns and we want clean upgrades.

Old:
```
**Plugin-managed** — `README.md`, `OVERVIEW.md`, `rules/working-rules.md`, `rules/change-decision-framework.md`, `rules/enforcement-mechanisms.md` (and `projects/README.md` when the project tier is enabled). These are diffed on every `/setup` run.
```

New:
```
**Plugin-managed** — `README.md`, `OVERVIEW.md`, `rules/working-rules.md`, `rules/change-decision-framework.md`, `rules/enforcement-mechanisms.md`, `rules/retrospect-patterns.md` (and `projects/README.md` when the project tier is enabled). These are diffed on every `/setup` run.
```

- [ ] **Step 3: Add `rules/retrospect-patterns.md` to the diff-loop list**

Same file. Find the "Files to diff" line.

Old:
```
**Files to diff:** `rules/working-rules.md`, `rules/change-decision-framework.md`, `rules/enforcement-mechanisms.md`, `README.md`, `OVERVIEW.md`, `projects/README.md` (plugin-managed if present)
```

New:
```
**Files to diff:** `rules/working-rules.md`, `rules/change-decision-framework.md`, `rules/enforcement-mechanisms.md`, `rules/retrospect-patterns.md`, `README.md`, `OVERVIEW.md`, `projects/README.md` (plugin-managed if present)
```

- [ ] **Step 4: Verify the edits**

Run: `grep -n "retrospect-patterns" plugin/skills/setup/SKILL.md`
Expected: 2 matches (one per edit).

- [ ] **Step 5: Commit**

```bash
git add plugin/skills/setup/SKILL.md
git commit -m "feat(setup): register retrospect-patterns.md as plugin-managed"
```

---

## Task 4: Update `help` skill with `/retrospect` listing

**Files:**
- Modify: `plugin/skills/help/SKILL.md`

**Why:** `/help` is the user's discovery surface for available commands. New skills must be listed there, otherwise users won't find `/retrospect`.

- [ ] **Step 1: Read the help SKILL.md to find the right section**

Run: `cat plugin/skills/help/SKILL.md | head -80`
Identify the structure used to list commands (usually grouped by category — e.g., "Knowledge management," "Audit," "Discipline").

- [ ] **Step 2: Add `/retrospect` to an appropriate group**

`/retrospect` belongs in the **discipline / audit** group (alongside `/extract`, `/audit-knowledge`, `/audit-config`). Add an entry following the existing format:

```
- `/retrospect` — Run a structured retrospective on a shipped commit range. Per-fix validation enforcement, simpler-alternative discipline, re-diagnosis, action verdicts, and a growing failure-mode pattern library. Args: `--range <ref1>..<ref2>`, `--pr <num>`, `--session`, `--commit <hash>`, `--linear`.
```

Match the surrounding entries' wording style (terse, action-first).

- [ ] **Step 3: Verify**

Run: `grep -n "retrospect" plugin/skills/help/SKILL.md`
Expected: 1 match.

- [ ] **Step 4: Commit**

```bash
git add plugin/skills/help/SKILL.md
git commit -m "docs(help): list /retrospect in help"
```

---

## Task 5: Update README.md skill listing

**Files:**
- Modify: `README.md` (project root, NOT `plugin/README.md`)

**Why:** README is the public-facing skill catalog. Same reason as Task 4, for the public-repo audience.

- [ ] **Step 1: Find the right section**

Run: `grep -n "^### \|^/" README.md | head -40`
Find the section listing slash commands by category. Typical sections include "Capture," "Audit," "Discovery," etc.

- [ ] **Step 2: Add `/retrospect` to an appropriate section**

Likely fits under an "Audit" or "Decision discipline" section alongside `/audit-knowledge`, `/audit-config`. Add:

```
- `/retrospect` — Run a structured retrospective on a shipped commit range. Enforces per-fix validation (no fix marked "shipped" without named evidence), surfaces simpler alternatives and maintenance cost per change, runs a failure-mode pattern check against a growing library, re-diagnoses when fixes failed, and produces an action verdict (revert / keep / redo / hold-for-evidence). Soft-suggested when the user reports a regression. Output saved to `logs/retrospect/`.
```

Match the surrounding entries' length and tone (one-paragraph, command-led).

- [ ] **Step 3: Verify**

Run: `grep -n "retrospect" README.md`
Expected: 1+ matches.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs(readme): list /retrospect in skill catalog"
```

---

## Task 6: Add CHANGELOG entry

**Files:**
- Modify: `CHANGELOG.md`

**Why:** ARIA's release flow expects a CHANGELOG entry per version (per `feedback_release_notes_distinct` and the existing CHANGELOG.md format).

- [ ] **Step 1: Open CHANGELOG.md and add a new entry above the most recent**

Open `CHANGELOG.md`. Find the line `## [2.13.4] - 2026-05-02`. Insert this new entry ABOVE it:

```markdown
## [2.13.5] - 2026-05-03

Patch release adding the `/retrospect` skill — a structured retrospective tool for shipped commit ranges with per-fix validation enforcement, simpler-alternative discipline, re-diagnosis when fixes failed, and a growing failure-mode pattern library.

### Added — `/retrospect` skill in `plugin/skills/retrospect/SKILL.md`

A new slash command that runs a 10-section retrospective on a shipped commit range, single commit, PR, or current session. The skill enforces a validation discipline: no fix is marked effective without explicit, named evidence (log event, reproduction-then-fix-verified, production instrumentation, or deployed-state check). Unvalidated fixes are flagged 🤷 Bundle-unverified or ❓ Unvalidated and cannot reach a KEEP action. Failed/partial fixes feed back into a re-diagnosis section that names surviving hypotheses and the specific instrumentation needed to discriminate between them — converting failed releases into evidence for the next attempt rather than another speculative fix.

The skill also runs a **failure-mode pattern check** against `rules/retrospect-patterns.md` (canonical) and `projects/<proj>/retrospect-patterns.md` (project-specific when applicable). Pattern hits surface named process failure modes (e.g., `diagnose-from-shape-not-path`, `bundle-unverification`, `speculative-iteration`, `phrase-tell-consistent-with-evidence`) so that recurring discipline gaps are visible across retrospectives. Novel patterns identified during a retrospective can be added to either library on user approval.

### Added — Canonical pattern library at `plugin/template/rules/retrospect-patterns.md`

Seeded with 9 canonical, project-agnostic failure-mode patterns derived from real retrospective evidence. Each entry includes detection cues, why-it's-a-problem, counter-discipline, and a references list. The file is registered as plugin-managed in `plugin/skills/setup/SKILL.md` — user-added patterns appear as diff prompts on plugin upgrades, never silently overwritten.

### Added — Plugin-managed registration in `plugin/skills/setup/SKILL.md`

`rules/retrospect-patterns.md` added to both the educational plugin-managed file list and the diff-loop file list, so `/setup` recognizes the new template.

### Added — `/retrospect` listing in `plugin/skills/help/SKILL.md` and `README.md`

Discoverability via `/help` and the public-facing skill catalog.

### Why this skill now

After shipping releases that produced multi-fix bundles where some fixes were necessary, some addressed misdiagnosed causes, and some over-engineered working code paths, the failure mode was clear: without a structured retrospective, the next instinct after a partial release is another speculative fix, repeating the loop. The `/retrospect` skill makes a structured retrospective the default response to a failed/partial release and treats post-deploy reality (not pre-merge code review) as the primary source of truth. Validation enforcement is the keystone — no fix is marked "shipped" without named evidence — and the failure-mode pattern library makes process learnings reusable across projects rather than re-discovered each retrospective.

### Soft-suggest trigger

The skill instructions include Claude-side judgment for offering `/retrospect` (never auto-executing) when the user's message contains regression cues ("still broken," "didn't fix," "review what you did," sharing test logs that show failure) and the current session has shipped recent fixes. Hook-based auto-trigger is deferred to v2 pending real-world calibration of which release events deserve auto-prompting.

### Out of scope (v1)

- Cross-change pattern *interpretation* (raw counts only)
- Automated pattern cue matching (judgment-based in v1)
- Auto-trigger on git push events
- Linear ticket auto-creation for FOLLOWUP-TICKET actions (drafts only in v1)
- Multi-bundle/series retrospectives

### Upgrade notes

- **Reinstall recommended** to pick up the new skill, the seeded canonical pattern library, and the setup registration.
- **No config migration** — no new hooks, no new top-level config keys. (A future `retrospect:` block in `~/.claude/aria-knowledge.local.md` will configure default destinations; v1 uses fixed defaults.)
- **No existing skill behavior changed** — `/retrospect` is purely additive.
```

- [ ] **Step 2: Verify**

Run: `head -10 CHANGELOG.md`
Expected: Top entry is `## [2.13.5] - 2026-05-03`.

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs(changelog): 2.13.5 — /retrospect skill"
```

---

## Task 7: Bump version in `plugin.json` (and confirm marketplace.json sync)

**Files:**
- Modify: `plugin/.claude-plugin/plugin.json`
- Modify (auto-synced via release.sh, but check): `.claude-plugin/marketplace.json`

**Why:** Version bumps are the source-of-truth change that signals a new release. Per `reference_aria_release_flow`, plugin.json is the source-of-truth and release.sh auto-syncs marketplace.json. Per `feedback_aria_versioning_patch_for_new_skill`, this is a patch bump (2.13.4 → 2.13.5).

- [ ] **Step 1: Bump plugin.json version**

Edit `plugin/.claude-plugin/plugin.json`. Change:

```json
"version": "2.13.4",
```

to:

```json
"version": "2.13.5",
```

- [ ] **Step 2: Update plugin description if needed**

Read the current description. If it doesn't already imply retrospective capability, append a brief mention. The description is shown to users in plugin discovery, so it should reflect the v2.13.5 capability. Suggested append (after the existing description, before "Includes Rule 22 enforcement hooks"):

> "...look up rules, build tag indexes, load knowledge by topic, clip URLs/snippets, snapshot session transcripts on demand, view knowledge base health stats, and **run structured retrospectives on shipped commit ranges with per-fix validation enforcement and a growing failure-mode pattern library**. Includes..."

If Mike prefers not to expand the description further (it's already long), leave it as-is and note in the PR.

- [ ] **Step 3: Sync marketplace.json (verify, do not edit if release.sh handles it)**

Run: `grep -n version .claude-plugin/marketplace.json`

If the version is still `2.13.4`, run release.sh — it auto-syncs per `reference_aria_release_flow`. Do not manually edit marketplace.json.

If the user prefers to do release.sh as a separate step (e.g., as part of release ceremony), leave marketplace.json at 2.13.4 for now and flag in the PR. Mike runs release.sh for the actual release.

- [ ] **Step 4: Verify plugin.json**

Run: `grep -n version plugin/.claude-plugin/plugin.json`
Expected: `"version": "2.13.5",`

- [ ] **Step 5: Commit**

```bash
git add plugin/.claude-plugin/plugin.json
git commit -m "chore(release): bump version to 2.13.5"
```

If marketplace.json was also edited (e.g., by release.sh), include it in the same commit:

```bash
git add plugin/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "chore(release): bump version to 2.13.5"
```

---

## Task 8: Manual verification — dry-run on a small bundle

**Why:** Before declaring the skill ready, exercise it end-to-end on a real (small) commit range. This catches missing instructions, ambiguous step language, and convention drift that won't show up from static review of the SKILL.md alone.

**Per `feedback_manual_verification_over_scheduled_agent`:** prefer manual exercise over automated agent runs for first verification.

- [ ] **Step 1: Reinstall the plugin locally**

Per `aria-knowledge/CLAUDE.md`'s "Development Workflow":

```bash
cp -R plugin/ ~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/
```

Restart Claude Code (or run `/setup` to pick up the new template file `rules/retrospect-patterns.md`).

- [ ] **Step 2: Pick a small test bundle**

Choose a 1–3 commit range from any project (could be a recent CS or aria-knowledge commit set with a clear shipping intent). Note the commit SHAs.

- [ ] **Step 3: Run `/retrospect --range <ref1>..<ref2>` in a fresh Claude Code session**

Observe whether the skill:
1. Prints the anchor block at the start (Step 1)
2. Asks for the goal and post-deploy outcome (Step 0)
3. Loads the canonical pattern library (Step 2)
4. Enumerates fixes (Step 3)
5. Produces a 10-section report (Step 4)
6. Validates the hard rules (Step 8)
7. Writes to `~/knowledge/logs/retrospect/<date>-<slug>.md`
8. Suggests intake entries

- [ ] **Step 4: Compare output to spec §4 expectations**

Open `docs/specs/2026-05-03-retrospect-skill-design.md` §4 and check that each of the 10 sub-sections appears in the actual output, in the right order, with the required fields.

Note any discrepancies. Common discrepancies and fixes:
- Section missing → add explicit instruction to that step in SKILL.md
- Required field missing in §4.3 verdict block → re-emphasize the field as required in Step 4.3 directives
- Anchor block missing → strengthen Step 1's wording
- Pattern check skipped when no patterns hit → ensure the "no patterns detected" fallback is in Step 4.4

- [ ] **Step 5: Note discrepancies and fix**

For each discrepancy found, edit `plugin/skills/retrospect/SKILL.md` to make the directive more explicit. Reinstall (Step 1). Re-run (Step 3). Iterate until the output matches the spec.

- [ ] **Step 6: Verification commit (only if SKILL.md edits were needed)**

```bash
git add plugin/skills/retrospect/SKILL.md
git commit -m "fix(retrospect): tighten directives based on first dry-run verification"
```

If no edits were needed, skip the commit.

---

## Task 9: Pre-release review pass

**Why:** Per `feedback_release_review_layers`, three review surfaces need a quick batch consistency check before push: pre-push batch consistency, cross-phase integration, user-facing docs audit. Catches drift introduced by independent task commits.

- [ ] **Step 1: Pre-push batch consistency**

Run: `git log --oneline 2.13.4..HEAD`
Expected: 7 commits (one per task that produced a commit), each with a `feat(retrospect)`, `feat(setup)`, `docs(...)`, or `chore(release)` prefix.

Confirm each commit's message accurately describes its scope and that no commit accidentally includes unrelated changes.

- [ ] **Step 2: Cross-phase integration audit**

Verify the chain holds end-to-end:
- `plugin.json` version is 2.13.5
- `CHANGELOG.md` has a 2.13.5 entry
- `plugin/skills/retrospect/SKILL.md` exists and references `rules/retrospect-patterns.md`
- `plugin/template/rules/retrospect-patterns.md` exists with 9 seeded patterns
- `plugin/skills/setup/SKILL.md` lists `rules/retrospect-patterns.md` in plugin-managed list (2 places)
- `plugin/skills/help/SKILL.md` lists `/retrospect`
- `README.md` lists `/retrospect`

Run: `grep -l retrospect plugin/skills/*/SKILL.md plugin/template/rules/retrospect-patterns.md README.md CHANGELOG.md plugin/.claude-plugin/plugin.json`
Expected: All seven files match.

- [ ] **Step 3: User-facing docs audit**

Confirm the public-repo content (README, CHANGELOG, SKILL.md, pattern library) contains no project-specific identifiers, internal URLs, ticket numbers, user names, or proprietary terms.

Run: `grep -riE "S60|Nala|cs-builder|seersite|commonspace|enrique|andrew|klinton|jude|@thecollab" README.md CHANGELOG.md plugin/skills/retrospect/ plugin/template/rules/retrospect-patterns.md`
Expected: No matches.

- [ ] **Step 4: Push (Mike's call — do not push without explicit approval)**

Per `feedback_ask_before_push_to_main` and `feedback_commit_vs_push_split_shared_repos`, do NOT push without Mike's explicit per-push approval. After all tasks are committed, surface to Mike:

> "All changes committed locally. Branch: <name>. 7 new commits. Ready for your review and push when you're ready. Want me to walk you through the diff first?"

Do not run `git push origin <branch>` until Mike says yes.

- [ ] **Step 5 (optional, Mike's call): Run release.sh for the actual release ceremony**

Per `reference_aria_release_flow`, release.sh handles the two-commit release pattern (release commit + back-to-dev commit), staging the zip, and running verification checks. This is Mike's call — release.sh execution should not be auto-run as part of the implementation plan.

---

## Spec Coverage Audit

This plan implements the design spec at `docs/specs/2026-05-03-retrospect-skill-design.md`. Mapping:

| Spec section | Plan task |
|---|---|
| §1 Motivation, §2 Scope & Invocation | Task 2, Step 2 (frontmatter + Step 0) |
| §3 Inputs & Anchors | Task 2, Step 2 (Step 0) and Step 3 (Step 1, Anchor block) |
| §4.1–§4.10 (10 retrospective sections) | Task 2, Step 3 (Step 4 with sub-sections 4.1–4.10) |
| §5 Validation Status Taxonomy | Task 2, Step 4 (Step 5 of SKILL.md) |
| §6 Failure-Mode Pattern Library | Task 1 (file creation), Task 2 Step 3 (§4.4 + §4.9 reference), Task 3 (setup registration) |
| §7 Output Format & Destinations | Task 2, Step 5 (Step 6 of SKILL.md) |
| §8 Soft-Suggest Trigger | Task 2, Step 6 (Step 7 of SKILL.md) |
| §9 Plugin File Layout | Task 1 (pattern lib), Task 2 (SKILL.md), Task 3 (setup registration) — note: spec proposed sub-folders (references/, templates/) which were dropped to match aria's single-SKILL.md convention |
| §10 Knowledge Intake Integration | Task 2, Step 5 (Step 6 of SKILL.md, Aria intake section) |
| §11 Out of Scope (v1) | Task 6 (CHANGELOG "Out of scope" section) |
| §12 Success Criteria for v1 | Task 8 (manual verification) — full criteria can only be confirmed after real usage |
| §13 Open Questions | Not implemented (deferred to post-v1) |

### Spec deviations made during planning

1. **Sub-folder structure dropped.** Spec proposed `references/` and `templates/` subfolders under `plugin/skills/retrospect/`. Plan inlines all content into a single `SKILL.md` to match aria's existing convention (every other skill is a single `SKILL.md`). Pattern library remains at `plugin/template/rules/retrospect-patterns.md` as designed.

2. **No new commands/ folder.** aria does not use a `commands/` folder; skill names function as slash commands directly. The slash command `/retrospect` is wired by the existence of `plugin/skills/retrospect/SKILL.md`.

3. **Versioning is patch, not minor.** Per `feedback_aria_versioning_patch_for_new_skill`, new isolated skill = patch bump. 2.13.4 → 2.13.5.

4. **HOLD-PENDING-VERIFICATION action added.** Spec defined HOLD-PENDING-EVIDENCE for ❓/🚫 fixes. During plan writing, the bundle-verification gate (§4.2) needed its own held-action label since "evidence" and "verification" are distinct concerns (evidence = does the fix work, verification = is the fix even running). Added HOLD-PENDING-VERIFICATION in Task 2 Step 3.

These deviations preserve all spec functional requirements; they only change *how* the requirements are organized in the plugin filesystem.

---

## Self-Review

**1. Spec coverage:** Every spec section maps to a task (see table above). The three deferred Open Questions (§13) are explicitly out of scope for v1 per the spec itself.

**2. Placeholder scan:** No "TBD," "TODO," "implement later," or generic "add error handling." All file content is provided inline. The pattern entries' "References" field uses *(seeded — first canonical reference will be the retrospect skill's first real-use retrospective)* which is intentional content (acknowledging that seed entries have no real-use reference yet), not a placeholder for future fill-in.

**3. Type/identifier consistency:** Identifier checks across tasks:
- File path `plugin/template/rules/retrospect-patterns.md` — used identically in Task 1 (creation), Task 2 Step 2 (reference in SKILL.md Step 2), Task 3 (registration)
- File path `plugin/skills/retrospect/SKILL.md` — used identically across Tasks 2, 8, 9
- Status taxonomy `✅ / ⚠ partial / ❌ / ❓ / 🚫` — used identically in Task 1 patterns, Task 2 Step 3 (§4.3 directives), Task 2 Step 4 (Step 5 reference)
- Action set `KEEP / REVERT / REDO-MINIMAL / FOLLOWUP-TICKET / HOLD-PENDING-EVIDENCE / HOLD-PENDING-DEPLOY / HOLD-PENDING-VERIFICATION` — emitted in Task 2 Step 3 §4.3, referenced in §4.8

**4. Public-repo sanitization:** Tasks 1, 2, 9 all include explicit grep-based sanitization checks. Pattern entries use generic language. CHANGELOG entry uses generic language ("releases that produced multi-fix bundles" — no project names, no SHAs, no internal terms).

No issues found requiring inline fixes.

---

## Execution Handoff

Plan complete and saved to `docs/plans/2026-05-03-retrospect-skill-plan.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Good for plans with this many tasks (9) and content-heavy file writes.

2. **Inline Execution** — Execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints. Lower overhead for small plans, but this plan is large enough that inline execution will use a lot of context.

Which approach?

Note: I have NOT committed the plan or spec to git. Per `feedback_ask_before_push_to_main`, I'll wait for your explicit approval before any commit on the public repo.
