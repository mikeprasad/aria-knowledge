---
description: "Run a structured pre-mortem on a plan or approach BEFORE execution. Per-step risk enforcement, active evidence-sourcing pass (autonomous lookups + targeted user-asks for anything that could become objective), simpler-alternative discipline, plan-formation diagnosis, action verdicts (PROCEED/SHRINK/SPLIT/DEFER/KILL), and a growing failure-mode pattern library. Triggers: '/prospect' (defaults to plan scope), '/prospect plan', '/prospect session', '/prospect todos', '/prospect file <path>', '/prospect linear <id>', '/prospect branch <name>'. Backward-compat flags (--plan, --linear, --branch, --todos, --session) still accepted. (Claude Code variant — bare-slash canonical when both ports loaded; see ADR-094.)"
argument-hint: "[<scope>] [<scope-arg>] [--linear-post] [--no-source]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, WebFetch, WebSearch
---

# /prospect — Plan pre-mortem with risk enforcement

Run a structured pre-mortem on a plan or approach that has been *created but not yet executed*. Forward-looking counterpart to `/retrospect`. Produces a 10-section markdown report with per-step verdicts, risk status, action recommendations, and process pre-mortem when the plan-formation itself was thin. Writes findings to `knowledge/logs/prospect/` and runs aria's standard intake.

The discipline this enforces: before the first edit lands, every planned step gets named, its evidence base examined, its smallest viable version identified, and its action gated on the strength of the underlying hypothesis. Mirrors `/retrospect`'s shape so the same review muscle works in both directions.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/prospect` resolves to this skill — aria-knowledge (Code) is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. The Cowork variant is namespaced-only: `/aria-cowork:prospect`.

**Before Step 0:** Check that the `Bash` tool is available in this session. If `Bash` is NOT available (you are running in Claude Cowork or another non-Code runtime), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/prospect` from a non-Code runtime.**
>
> Behavior is largely the same in both runtimes; for the Cowork-native variant (skips Step 11 CODEMAP/STITCH surfacing per ADR-005, uses in-memory dedup instead of `/tmp/` ledger), use `/aria-cowork:prospect`.
>
> **Use `/aria-cowork:prospect` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `aria-cowork:prospect` with the same arguments the user provided to this invocation. Do not proceed with this skill's steps; the cowork variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-knowledge) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args.

If `Bash` is available, proceed to Step 0.

## When to use

- After a multi-step plan is articulated (in chat, in TodoWrite, in a `.md` plan file) but no code has been written yet
- After `/brainstorming` concludes with an action plan
- After `/distill` produces a task spec that's about to be executed
- After a Linear ticket's Technical Intake is drafted and the implementer is about to begin
- Before kicking off a long autonomous run (e.g., `combined go`) on a non-trivial plan
- As a soft-suggested response to "let me implement…", "I'll just code it…", "ok ship it" when no validation exists yet

If code has already been written/committed (even in-session), use `/retrospect` instead — that pivots from forward-looking to backward-looking validation.

## Step 0: Inputs & Mode Detection

Parse the invocation arguments. The first positional argument is the **scope keyword**; subsequent positional arguments are scope-specific. Six scopes plus a no-args default:

| Scope | Trigger | Backward-compat flag (still accepted) | Plan source |
|---|---|---|---|
| **plan** (default) | `/prospect plan` or `/prospect` | (was the no-arg default) | Current conversation's articulated plan — combine the active TodoWrite list, the most recent assistant plan/approach message, and any in-session plan file Claude has written. If ambiguous, ask user "Which of these is the plan you want me to pre-mortem?" with a short list. |
| **session** | `/prospect session` | `--session` | Synonym for **plan**. Reserved for cases where the user wants to emphasize "everything articulated this conversation" rather than a single plan artifact. |
| **todos** | `/prospect todos` | `--todos` | Just the active TodoWrite list — a thin mode for quick checks |
| **file** | `/prospect file <path>` | `--plan <path>` | Read the markdown file at `<path>` as the plan |
| **linear** | `/prospect linear <id>` | `--linear <id>` | Read the ticket's Technical Intake (and Product Intake for goal context) via Linear MCP. If MCP unavailable, ask user to paste. |
| **branch** | `/prospect branch <name>` | `--branch <name>` | Uncommitted/unpushed local changes on the branch — `git diff <main-branch>...<name>` — treated as a plan-in-progress (NOT shipped yet) |

**Argument parsing rules:**
- If the first positional arg matches a scope keyword (case-insensitive), use it. Otherwise treat it as an arg to the default `plan` scope.
- Backward-compat flag forms (`--plan`, `--linear`, `--branch`, `--todos`, `--session`) remain accepted indefinitely. Both `/prospect linear LINEAR-123` and `/prospect --linear LINEAR-123` resolve identically.
- Modifier flags (apply to any scope): `--linear-post` (post the prospect verdict to detected Linear tickets at end), `--no-source` (skip Step 3.5's Evidence-Sourcing Pass).

After mode detection, gather:

1. **Goal** — Ask the user: "What is this plan supposed to accomplish? (One sentence is fine.)" If they don't reply, fall back to the plan's first heading or stated objective.
2. **Tickets** — Scan plan text/commits/branch name with regex `\b([A-Z]{2,}-\d+)\b` for Linear-style ticket IDs. If found AND Linear MCP is available, fetch each ticket's Product/Technical Intake + acceptance criteria to use as the goal-anchor in §4.6. If Linear MCP is unavailable, note "ticket context unavailable" but continue.
3. **Pre-execution evidence** — Ask the user: "For each step in this plan, do you have evidence the step is necessary and that the underlying assumption is correct? (✅ measured / ⚠ inferred / ❌ contradicted / ❓ untested)" Show the per-step list and accept inline replies. If user can't supply evidence for any step, mark those ❓ — those steps will resolve to DEFER unless §4.7 produces supporting hypothesis confidence.

If scope is `branch` (or invoked via `--branch`) and the diff is non-trivial (>50 LOC across >3 files), warn: "Branch already has substantive code — consider `/retrospect range main..HEAD` instead, which is calibrated for already-written changes." Continue if user confirms.

## Step 0.5: Active Knowledge Surfacing

If the user's config (`~/.claude/aria-knowledge.local.md`) has `active_knowledge_surfacing: true` (default as of v2.15.0), surface relevant tagged knowledge BEFORE Steps 1-3 so loaded files inform pattern selection and evidence sourcing. If the field is `false`, skip this step entirely (note `Active surfacing: disabled` in the Anchor block).

**Algorithm:**

1. **Build query.** Combine, separated by spaces: the Goal sentence from Step 0; the plan's first heading or the first 3 TodoWrite items; any detected Linear ticket IDs (e.g., `LINEAR-123`); the file basename if scope is `file`; the branch name if scope is `branch`.

2. **Read the index.** `Read` `<knowledge_folder>/index.md` (resolve `<knowledge_folder>` from the config's `knowledge_folder` field). Parse the `## Tag Index` section for `### tagname` headers — that's the matching vocabulary (~77 known tags as of v2.15.0). Ignore the `## Other Tags` section (freeform tier, intentionally excluded from auto-surfacing).

3. **Tokenize.** Lowercase the query, strip punctuation to spaces, dedupe to a word set.

4. **Match.** Exact word-vs-tag equality only — no substring, no fuzzy. Collect the set of matched tags.

5. **Threshold gate.** If fewer than 2 tags matched, note `Active surfacing: 0 matches (below threshold)` in the Anchor block and skip to Step 1. Single-tag matches are too noisy.

6. **Collect files.** Under each matched tag's `### tag` section, gather the `- path — description` lines. Dedupe by path. Cap at top-5 by first-appearance order.

7. **Ledger filter (best-effort).** Run `ls -t /tmp/aria-active-* 2>/dev/null | head -1` via Bash to find the current session's ledger (the most recently modified file matching that pattern). If found, read it and drop any matched paths already listed there — they were surfaced by an earlier hook/skill in this session. If no ledger exists, proceed unfiltered.

8. **Read matched files.** For each remaining path (up to 5), `Read` the full file into context.

9. **Summarize.** Before Step 1's Anchor Block, emit a 3-line surfacing block:

    ```
    Active Knowledge Surfacing:
      Tags matched: <tag1> <tag2> ...
      Files loaded: <N> (<file1>, <file2>, ...)
      Relevance: <one sentence per file: why this informs the prospect>
    ```

10. **Carry-forward.** These loaded files become input to Step 2 (Load Pattern Libraries — past prospects/retros tagged with the same topic may already catalog the relevant patterns) and Step 3.5 (Evidence-Sourcing Pass — they may already validate or falsify assumptions in the plan, converting ⚠/❓ to ✅/❌ before the verdict round).

11. **Tracked artifacts surfacing (added v2.16.1).** After Step 10's carry-forward, ALSO surface CODEMAP + STITCH for the plan's project. The shared lib at `${CLAUDE_PLUGIN_ROOT}/bin/lib-tracked-artifacts.sh` implements equivalent logic for hooks; this step inlines the algorithm for skill-context portability.

    a. **Detect project tag.** Try in order: `--group=<tag>` from Step 0 if provided → first Linear-ticket ID prefix that maps to a `projects_list` tag → first `projects_list[<tag>].path` whose `path` appears as substring in the plan source path (from Step 0 `Source:` field). If no detection, skip the rest of Step 11.

    b. **Resolve project root via Bash.** Parse `projects_list:` from `~/.claude/aria-knowledge.local.md` frontmatter (comma-separated `tag:path`). For the detected tag, compute `project_root = $HOME/Projects/<path>`. If directory doesn't exist, skip.

    c. **CODEMAP directory load** (if `{project_root}/CODEMAP.md` exists). Compute boundary via `awk '/^## [0-9]+\.|^---$/ && NR>5 {print NR; exit}' "{project_root}/CODEMAP.md"`; Read limit = `(end - 1)` (fallback 50 if awk empty). Compute `age = (today - mtime).days`; read `codemap_staleness_threshold_days` (default 14). If `age > 2*threshold`, refuse and emit `[refused — run /codemap update first]`. Else if `age > threshold`, annotate `[STALE — consider /codemap update]`. Else `fresh`. Unless refused: `Read {project_root}/CODEMAP.md offset=0 limit=<end-1>`.

    d. **STITCH load** (only if `{project_root}/STITCH.md` exists — multi-repo signal). Same staleness logic with `stitch_staleness_threshold_days` (default 30). Unless refused: `Read {project_root}/STITCH.md` (full file).

    e. **Ledger dedup.** Locate session ledger via `ls -t /tmp/aria-active-* 2>/dev/null | head -1`. Before loading in (c)/(d), grep ledger for each artifact path; if found, silent skip (already surfaced by earlier T-1/T-2/T-3 trigger) and emit `Tracked artifacts: (already loaded earlier this session for {tag})` in the surfacing block. After loading, append loaded paths to the ledger.

    f. **Output.** Extend the Step 9 surfacing block with a 4th line:
        ```
        Tracked artifacts: CODEMAP directory + STITCH for {tag} ({N} / {M} days fresh)
        ```
        Variants: `CODEMAP directory only` for single-repo (no STITCH); `(no CODEMAP for {tag})` if missing; `[STALE — consider /codemap update]` annotation; `(already loaded earlier this session)` if ledger-deduped; `(none — no project detected)` if (a) returned nothing.

    g. **Carry-forward.** The loaded artifacts become available to Steps 3+ — particularly Step 3 (Enumerate Steps; CODEMAP directory aids file-path resolution for plan steps) and Step 3.5 (Evidence-Sourcing Pass; CODEMAP sections can validate or falsify assumptions about codebase structure).

    Skip Step 11 entirely if `active_knowledge_surfacing: false` (already gated above).

## Step 1: Print the Anchor Block

Before producing any verdict, emit the anchor so the rest of the report can be traced to inputs:

```
Anchor:
  Goal:    <stated goal>
  Mode:    <plan | session | todos | file | linear | branch>
  Source:  <plan file path | TodoWrite snapshot | Linear-id | branch-name | session messages>
  Scope:   <step count, files-to-touch estimate, repos-affected>
  Tickets: <LINEAR-123 (Acceptance: ...), LINEAR-456 (...) | (none) | (unavailable)>
  Evidence: <user-supplied per-step evidence table | (untested)>
```

## Step 2: Load Pattern Libraries

Read the canonical pattern library at `~/knowledge/rules/retrospect-patterns.md` (resolved per `~/.claude/aria-knowledge.local.md` `knowledge_root`). The retrospect pattern library is intentionally shared — most failure-mode patterns (theory-driven refactor, scope creep, abstraction-first, etc.) apply forward as well as backward.

If a `~/knowledge/rules/prospect-patterns.md` file exists, also load that (forward-only patterns may emerge over time and be catalogued separately). Do not require it.

If the plan is detected to belong to a known project (file paths or ticket IDs match a configured `projects_list[<tag>].project_root`), additionally read `~/knowledge/projects/<tag>/retrospect-patterns.md` if it exists, and `~/knowledge/projects/<tag>/prospect-patterns.md` if it exists.

Hold all loaded pattern lists in context for use in §4.4 (Failure-Mode Pattern Check). Do not run pattern detection yet — this step is just loading.

## Step 3: Enumerate Steps & Preliminary Triage

For the loaded plan, enumerate each *step*. A step is one of:
- A numbered or bulleted action item in the plan
- A TodoWrite entry
- A discrete change in a Technical Intake's "How" section
- A logical sub-task implied by the plan even if not explicitly numbered

Number them `#1, #2, …` in execution order. For each step, capture:
- One-line description (verb + object, e.g., "Add `--branch` arg to /prospect")
- Files-to-touch (path list, best estimate from plan; "TBD" allowed)
- Estimated LOC range (S < 20, M 20-100, L > 100)
- Underlying assumption (one sentence — "this works because …")
- **Preliminary Risk?** — initial classification using Step 5's taxonomy (✅ / ⚠ / ❌ / ❓ / 🚫). This is a draft that Step 3.5 will attempt to upgrade; it is NOT the value emitted in §4.3.

If a step has no identifiable underlying assumption (it's pure execution, e.g., "rename file"), write "Mechanical — no hypothesis." Mechanical steps default to ✅ Pre-validated and skip Step 3.5.

After preliminary triage, list every step whose Preliminary Risk? is ⚠ Theory-driven, ❓ Unsupported, or 🚫 Unverifiable-yet — these are the *candidates* for Step 3.5's evidence-sourcing pass. ❌ Falsified steps skip Step 3.5 (they go directly to KILL in §4.3 unless the user contests the falsification).

## Step 3.5: Evidence-Sourcing Pass

For each candidate from Step 3 (every step with Preliminary Risk? of ⚠ / ❓ / 🚫), attempt to upgrade or falsify the risk by sourcing evidence. The goal: convert as many ⚠/❓/🚫 to ✅ or ❌ as possible *before* §4.3 emits final verdicts and §4.10 surfaces residual asks.

This step can be skipped with the `--no-source` flag (e.g., for a quick pass where the user just wants the structural review). When skipped, all Preliminary Risk? values pass through to §4.3 unchanged and §4.10 lists every gap as NOT-ATTEMPTED.

### 3.5.1: Generate the Evidence Question

For each candidate step, name the **single most decisive question** whose answer would upgrade the Risk? to ✅ Pre-validated or ❌ Falsified. Format:

```
Step #N: <description>
  Preliminary Risk?:  <⚠/❓/🚫 with sub-tag>
  Decisive question:  <one-line — "what would change this verdict?">
  Answer source:      AUTO-SOURCEABLE | USER-INPUT | MIXED
  Sourcing plan:      <one-line — what tool/lookup/ask will be used>
```

Source categorization:

| Category | Means | Examples |
|---|---|---|
| **AUTO-SOURCEABLE** | The skill can answer it itself with available tools | Codebase reads (Read/Grep/Glob), git log/diff/blame, public web docs (WebFetch/WebSearch), Bash probes (curl, gh, grep on logs), MCP queries that don't require new credentials (e.g., `supabase__list_tables`, `linear__get_issue` if MCP is connected) |
| **USER-INPUT** | Requires Mike's judgment, local-only knowledge, or a decision he hasn't made yet | Acceptance criteria interpretation, scope/priority calls, choosing between viable design options, info that lives only in his head (a conversation with a teammate, a constraint he hasn't documented) |
| **MIXED** | Auto-sourceable to narrow the option space, then user picks | "Grep finds 3 candidate canonical-nav definitions; ask user which is current" |

If a step has multiple decisive questions, list them as 3.5.1.a, 3.5.1.b, etc., and run each through 3.5.2 / 3.5.3 independently.

### 3.5.2: Auto-Source What's Accessible

For each AUTO-SOURCEABLE (or the auto-portion of MIXED) question, execute the sourcing plan and record findings. Permissible tools:

- **Codebase**: Read, Grep, Glob — for file content, references, structure
- **Version control**: Bash with `git log`, `git diff`, `git show`, `git blame`
- **Public web**: WebFetch (specific URL — library docs, official spec) and WebSearch (when the URL is unknown). Per Rule 33, prefer official sources over inferred ones; per Rule 27, verify identifiers/versions are still current
- **Local probes**: Bash for `curl`, `gh`, log-tail, file-existence checks
- **MCP queries** that don't require new credentials and that the user has already authorized in this session (Linear, Supabase, etc.). If a query would require new auth or interactive consent, demote to USER-INPUT instead

Record findings in this format:

```
Step #N — sourcing result:
  Question:           <repeat decisive question>
  Tool used:          <Read | Grep | WebFetch <url> | Bash <command> | mcp__<server>__<tool>>
  Finding:            <one-paragraph factual summary, with file:line citations or URL anchors>
  Verdict:            UPGRADED-TO-✅ | UPGRADED-TO-❌ | NO-MOVEMENT (still ⚠/❓/🚫) | INCONCLUSIVE
  New Risk?:          <new tag, or unchanged if NO-MOVEMENT>
```

Constraints:
- **Rule 33 — verify against current docs**: When sourcing third-party API/SDK behavior, read the official current docs (via WebFetch or `context7` MCP if loaded), not memory or analogy.
- **No credential reads** without explicit per-session permission (per `feedback_ask_before_credentials`). If a question requires reading `.env` or similar, demote to USER-INPUT.
- **No destructive probes** — read-only commands only. `git status`, `git log`, `curl GET`, `grep`, `find` are fine. No `rm`, `git reset`, `git push`, `gh pr merge`, etc.
- **Time-box per step**: if a single question consumes more than ~5 tool-call rounds without converging, mark INCONCLUSIVE and demote the residual to USER-INPUT.
- **Evidence quality bar**: a single corroborating source upgrades to ⚠ Theory-driven (with sub-tag `single-source-inferred`). Two independent sources are required to upgrade to ✅ Pre-validated. One contradicting authoritative source falsifies to ❌.

### 3.5.3: Surface USER-INPUT Asks

For each USER-INPUT question (and the user-portion of MIXED), pause the pre-mortem and surface the ask using the format below. Per `feedback_per_item_review_cadence`, default to ONE ask at a time unless the user requests batch. Per `feedback_hold_gate_steps`, this is a synchronous barrier — do not proceed until the user responds or explicitly chooses Skip.

Standard ask format:

```
[ASK #M of K] Step #N — <step description>

Why this matters:
  <one-line — what changes about Step #N's verdict if we know this>

What I tried autonomously (if MIXED):
  <one-line — e.g., "Grep'd /df-working/playground for canonical examples; found 3 candidates at <paths>. Need your call on which is current.">

Citations / context inline:
  <file:line excerpts, URL pulls, or quoted plan fragments — whatever the answer depends on>

Options:
  1) <option, with one-line consequence — e.g., "Use blueprint-loader.ts:645 (last touched 36c9a5f25). Step #N stays as planned, Risk? upgrades to ✅.">
  2) <option, with one-line consequence>
  3) Other — describe in reply
  4) Skip — leave Step #N at <preliminary risk>; it will DEFER in §4.10
```

Rules for the ask:
- Frame neutrally. No baked recommendation in the framing (per `feedback_neutral_option_framing`). A separate "Recommendation: <N> — <reason>" line is acceptable AFTER the options block, but not required, and never inside an option's text.
- Each ask requires its own explicit pick (per `feedback_per_question_explicit_pick`). Don't combine multiple decisive questions into one ask.
- "Skip" is always available and always defaults the step to DEFER. Per `feedback_no_self_fabricated_go_signals`, the skill never invents a decision the user didn't make.
- Bare-number replies pick that option (per `feedback_terse_numeric_answers`). "1" = option 1.

After the user responds, record:

```
Step #N — user-input result:
  Question:           <repeat>
  User pick:          <option N | "other: <user's text>" | "skip">
  Resulting Risk?:    <new tag, or unchanged if skip>
```

### 3.5.4: Pass Summary

When all candidates are processed, emit a one-block summary before moving to Step 4:

```
Evidence-Sourcing Pass complete.
  Candidates examined:        <N>
  Auto-sourced (✅ upgrade):   <N>
  Auto-sourced (❌ falsify):   <N>
  User-resolved (✅ upgrade):  <N>
  User-resolved (❌ falsify):  <N>
  No movement (still ⚠/❓/🚫): <N>
  Skipped by user:            <N>
  Skipped by --no-source:     <N>
  Tool calls used:            ~<N>
```

The post-pass Risk? values feed §4.3. The residual ⚠/❓/🚫 plus their attempt-status feed §4.10.

## Step 4: Produce the 10-Section Pre-Mortem Report

Render a markdown document with the 10 sections below in order. Each section heading uses `### N. <title>` format. Sections that don't apply to the current scope are emitted with a one-line "N/A: <reason>" — never silently skipped.

### 4.1. Section 1 — Anchor & Inputs

Re-emit the anchor block from Step 1, verbatim, as Section 1 of the report. This makes the report self-contained when read outside the chat.

### 4.2. Section 2 — Plan-Specificity Gate

For each step from Step 3, ask: is the step concrete enough that an implementer could execute it without further design decisions?

Acceptable evidence of concreteness:
- Specific file path(s) named (or a precise pattern that resolves to a small set)
- Specific function/section/component named
- Acceptance signal stated (test passes, log line emitted, screen renders, etc.)

If a step is still goal-stage ("improve performance," "clean up the auth flow," "make it work"), mark it 🌫 **Under-specified** in this section. Under-specified steps do NOT receive a Risk? status in §4.3 — instead, they're flagged here and their action defaults to DEFER-PENDING-DESIGN.

If the entire plan is under-specified, emit "STOP: plan is goal-stage. Run `/distill` to convert to executable spec, then re-run `/prospect`." and skip remaining sections.

### 4.3. Section 3 — Per-Step Verdict

For each step from Step 3 that passed §4.2 (concrete or partially concrete), emit a horizontal-rule-separated block with these fields. Mirror the formatting style of `/retrospect`'s per-fix verdict.

Required fields:
- **Concreteness tag** — one of ✅ specific / ⚠ partial / ⚠ scope-large / ⚠ assumption-stacked / ⚠ duplicates-existing
- **Necessary?** — YES / NO / UNCLEAR with one-sentence reason. Unnecessary steps map to KILL.
- **Smallest viable version** — "the smallest version of this step that would address the goal." If the step is already minimal, write "This is the minimal version." Forces Rule 13. If smaller version exists, the step's action defaults to SHRINK unless user has a stated reason for the larger scope.
- **Maintenance cost (if executed)** — "what future contributors must know / maintain because of this change." Forces Rule 12 / Rule 14.
- **Risk?** — one of the 5 statuses from Step 5 (or 🌫 if §4.2 flagged it under-specified). This is the **post-Step-3.5 final value**, not the preliminary classification from Step 3. If Step 3.5 upgraded or falsified the risk, that change is reflected here.
- **Action** — one of: PROCEED / SHRINK / SPLIT / DEFER / KILL / DEFER-PENDING-DESIGN (under-specified only)

Optional fields:
- **Evidence sourced** — when Step 3.5 produced a verdict-changing finding, summarize it in one line with citation. Example: "Auto-sourced via Read blueprint-loader.ts:645-662 — confirms canonical nav rule applies; upgraded ⚠→✅." If Step 3.5 produced no movement OR was skipped, omit this field.
- **Rule cite** — if a complication maps to a Universal Rule overstep, cite it inline (e.g., "violates Rule 14 — abstraction beyond purposeful layers")

Render each step as a block, not a wide table:

```
Step #N: <description>
Concreteness:        <tag>
Necessary?:          <YES/NO/UNCLEAR> — <reason>
Smallest version:    <description>
Maintenance cost:    <description>
Risk?:               <status>  (post-Step-3.5)
Evidence sourced (optional): <one-line with citation>
Action:              <action>
Rule cite (optional): <rule>
────────────────────────────────────────
```

**Hard rule:** A step's Action cannot be PROCEED unless its Risk? status is ✅ Pre-validated, OR ⚠ Theory-driven WITH an explicit one-line "Acceptable risk because: <reason>" appended to the Action line. ❌ Falsified → KILL. ❓ Unsupported → DEFER. 🚫 Unverifiable-yet → SHRINK (smallest version that produces evidence). 🌫 Under-specified → DEFER-PENDING-DESIGN.

The theory-driven carve-out exists because every plan is theory-driven by definition — you're imagining, not measuring. The carve-out forces the planner to *name the risk* rather than block all forward motion.

### 4.4. Section 4 — Failure-Mode Pattern Check

Run the plan against all loaded pattern libraries from Step 2. Detection is judgment-based — read each pattern's "Detection cues" and assess whether the plan, hypotheses, or session transcript exhibits them.

Patterns from `retrospect-patterns.md` apply forward in their *prospective* form. For example:
- "Theory-driven refactor" pattern → fires if a step rewrites working code based on a hypothesis about a problem location, not a confirmed observation
- "Scope creep" pattern → fires if the plan now spans more than the goal requires
- "Abstraction-first" pattern → fires if the plan introduces a new abstraction layer before establishing >2 concrete use cases
- "Pushback-as-cue" pattern → does not fire forward (it's a backward-looking cue), N/A

For each pattern hit, emit:

```
[PATTERN] <pattern-name> (source: rules/retrospect-patterns.md | rules/prospect-patterns.md | projects/<proj>/...)
  Evidence: <what in the plan/transcript triggered the hit>
  Counter-discipline: <one-line reminder of the pattern's counter-discipline>
```

If no patterns hit, emit: "No catalogued failure-mode patterns detected. (See §9 for novel patterns.)"

### 4.5. Section 5 — Cross-Step Tally

Emit raw counts only — no interpretation in v1.

```
Tally:
  Steps planned:                     <N>
  Pre-validated (✅):                 <N>   (post-Step-3.5)
  Theory-driven (⚠):                  <N>   (post-Step-3.5)
  Falsified (❌):                     <N>   (post-Step-3.5)
  Unsupported (❓):                   <N>   (post-Step-3.5)
  Unverifiable-yet (🚫):              <N>   (post-Step-3.5)
  Under-specified (🌫):               <N>
  Theory-driven refactors:           <N>
  Tied to Linear acceptance:         <N>
  Discovered-during-planning:        <N>
  Pattern hits this run:             <N>

Evidence-Sourcing Pass:
  Candidates examined:               <N>
  Auto-sourced (✅ upgrade):          <N>
  Auto-sourced (❌ falsify):          <N>
  User-resolved (✅ upgrade):         <N>
  User-resolved (❌ falsify):         <N>
  No movement:                       <N>
  Skipped by user:                   <N>
  Skipped by --no-source:            <N>
```

A "theory-driven refactor" is a step that proposes rewriting working code based on a hypothesis rather than a confirmed bug location or measurement. Discovered-during-planning means a step the plan added beyond the original goal (often surfaces scope creep).

Interpretation of these counts is left to §4.6, §4.7, and §4.9.

### 4.6. Section 6 — Frame Check

Three questions, in order. Answer each in 1–2 sentences with the supporting evidence.

1. **Is the problem statement right?** Does the plan target the user's actual problem, or has it drifted to an adjacent problem during planning?
2. **Is the bug/feature correctly scoped?** Single goal, or has the plan accreted multiple goals presenting as one?
3. **Is the success signal stated?** When the plan finishes, what observable evidence will indicate it worked? If you can't state it, you can't validate it after.

If the answer to #1 is "no," explicitly note: "Re-frame triggered. Hold all steps targeting the *drifted* problem statement pending re-frame discussion. Return to the original goal."

If the answer to #3 is "no," explicitly note: "No success signal stated. Add a measurable post-execution check before any step PROCEEDs."

### 4.7. Section 7 — Diagnosis Confidence

List the **driving hypotheses** behind the plan (only run this section if any step's *post-Step-3.5* Risk? is ⚠ Theory-driven, ❓ Unsupported, or §4.6 #1 triggered re-frame). For each hypothesis:

```
Hypothesis: <one-line statement of what the plan assumes is true>
  Used by steps: <#1, #3, #5>
  Evidence FOR:    <observations consistent with this hypothesis — INCLUDE Step 3.5 sourced findings with citations>
  Evidence AGAINST: <observations inconsistent — INCLUDE Step 3.5 sourced findings>
  Sourcing attempted: <YES (see Step 3.5 result for steps #N) | NO (auto-sourcing skipped or not categorized as auto-sourceable)>
  Confidence:      LOW / MEDIUM / HIGH
  To upgrade to ✅: <specific signal to look for — feeds §4.10>
```

Evidence FOR/AGAINST must integrate any findings from Step 3.5's sourcing pass. If Step 3.5 produced a finding that moved the step to ⚠ Theory-driven (e.g., `single-source-inferred` upgrade from ❓), cite that finding here as soft Evidence FOR. If Step 3.5 produced a contradicting finding that the user contested or overrode, note both perspectives.

Hypotheses that the plan-formation conversation OR Step 3.5 already ruled out (alternative explanations considered and discarded) are listed separately under "Hypotheses ruled out during planning or sourcing" with one-line reasons and source citations where applicable. This is *learning*, not waste — captures what was considered AND what evidence retired it.

If all steps are ✅ Pre-validated and §4.6 didn't trigger, this section emits "N/A: all steps pre-validated."

### 4.8. Section 8 — Action Verdict

Per step, the action determined in §4.3. Render as a clear list:

```
Action verdict:
  Step #1: <ACTION>  — <one-line reason>
  Step #2: <ACTION>  — <one-line reason>
  ...
```

For SHRINK actions, provide the exact smaller-scope description (from §4.3's "Smallest version"). For SPLIT actions, provide the proposed sub-step breakdown with a checkpoint between sub-steps. For DEFER actions, name the specific evidence/decision needed first. For KILL actions, give the one-line rationale and confirm there's no orphaned downstream step that depended on it.

End with an **Overall verdict** in 1–3 sentences: PROCEED / PROCEED-WITH-CHANGES / HOLD / KILL. PROCEED-WITH-CHANGES means at least one step requires SHRINK or SPLIT before any execution. HOLD means at least one step is DEFER and blocks downstream steps.

### 4.9. Section 9 — Process Pre-mortem

What the plan-formation process should have done differently. Format per item:

```
What planning produced:    <observed plan shape>
What it should produce:    <better plan shape>
Trigger condition:         <how to detect this situation in the future>
Pattern reference:         <pattern-name from library | (novel)>
```

Examples of plan-formation issues this section catches:
- Plan jumped to solution without stating the problem (skip Rule 22 step 1)
- Plan considered only one solution (skip Rule 22 step 4)
- Plan has steps with no acceptance signal (skip Rule 22 step 6)
- Plan exceeds the agreed scope (no-unsolicited-scope-reduction's reverse — silent scope expansion)
- Brainstorming was skipped before a creative-work plan
- /distill was skipped before a complex task plan

If a behavior matches an existing pattern in the library, cite it. If a behavior is *novel*, prompt the user:

> "Identified a new plan-formation failure pattern: `<pattern-name>`. Add to:
>   1) Canonical (`rules/prospect-patterns.md` — creates if missing) — applies project-agnostic
>   2) Project-specific (`projects/<proj>/prospect-patterns.md`)
>   3) No — surface in this report only
> Choose: "

If user chooses 1 or 2, append a new entry to the corresponding file using the same "Pattern entry format" defined in `rules/retrospect-patterns.md`. The new entry's "First identified" field is today's date and the current prospect's filename.

### 4.10. Section 10 — Pre-Execution Evidence Ask (Residual)

Anti-speculation barrier. This section lists ONLY the **residual** evidence asks — the questions Step 3.5 either could not source autonomously, the user deferred, or were not attempted. Items resolved during Step 3.5 (✅ upgrades or ❌ falsifications) DO NOT appear here — they're recorded in §4.3 (`Evidence sourced` field), §4.7 (Evidence FOR/AGAINST), and §4.5 (Evidence-Sourcing Pass tally).

For each remaining ⚠/❓/🚫 step, emit the residual ask with its **attempt-status**:

```
Before Step #N can PROCEED (Hypothesis A: <short label>):
  Attempt status:    NOT-ATTEMPTED | ATTEMPTED-FAILED | DEFERRED-BY-USER | SKIPPED-BY--no-source
  Why residual:      <one-line — e.g., "Auto-source attempted via WebFetch <url>; doc was 404. Demoted to USER-INPUT.">
  What's needed:     - <specific check 1 — file read, log query, schema inspection, decision required, etc.>
                     - <specific check 2>
                     - <add a unique [<TAG>-PRE] marker in the planned change so post-execution validation is possible>
  Who can resolve:   <USER | AUTOMATED-RETRY-LATER | EXTERNAL-PARTY <name>>
```

Attempt-status meanings:
- **NOT-ATTEMPTED** — Step 3.5 did not generate a sourcing plan for this question (rare; usually means a misclassified candidate)
- **ATTEMPTED-FAILED** — Step 3.5 ran tools but the answer wasn't found / source was unreachable / two corroborating sources couldn't be obtained
- **DEFERRED-BY-USER** — Step 3.5 surfaced a USER-INPUT ask and the user picked "Skip"
- **SKIPPED-BY--no-source** — entire pass was skipped via the `--no-source` flag

If all steps are ✅ Pre-validated post-Step-3.5, emit: "N/A: all steps pre-validated (Step 3.5 closed all gaps). Proceed to execution."

If Step 3.5 was skipped via `--no-source`, prefix every entry with "(Sourcing pass skipped — re-run `/prospect` without `--no-source` to attempt autonomous resolution.)"

End the section with this verbatim warning when any DEFER or HOLD action exists:

> **Do not begin execution until at least one item in this section is satisfied for each DEFER step. If execution is started without new evidence, the eventual `/retrospect` will mark those steps unvalidated. Plan accordingly.**

## Step 5: Risk Status Taxonomy (reference)

When assigning Risk? in §4.3, choose one of the 5 statuses below. Under-specified (🌫) is a precondition gate handled in §4.2, not a status.

| Status | Definition | Required sub-tag (in report) |
|---|---|---|
| ✅ **Pre-validated** | Evidence already supports the planned step's underlying assumption | **Evidence type**: log/measurement \| reproduction-then-confirm \| code-read-and-traced \| existing-test-coverage. "Plausible argument" is **not** evidence. |
| ⚠ **Theory-driven** | Plan rests on a hypothesis that's reasonable but unmeasured | **Sub-tag**: `single-source-inferred` \| `analogous-system-reasoning` \| `documentation-claim-untested` |
| ❌ **Falsified** | Known evidence contradicts the planned step's assumption | **Sub-tag**: `prior-attempt-failed` \| `evidence-shows-otherwise` \| `documented-anti-pattern` |
| ❓ **Unsupported** | No evidence yet, but the skill can describe the specific check that would gather it | (none) |
| 🚫 **Unverifiable-yet** | Cannot be validated until execution begins (requires running the change to know) | (none) |

When emitting a Risk? value, always include the required sub-tag where applicable. Examples:

- `Risk?: ✅ Pre-validated (code-read-and-traced: blueprint-loader.ts:645-662 confirms canonical nav rule applies)`
- `Risk?: ⚠ Theory-driven (single-source-inferred: only one API route was inspected; assumption that all NDJSON routes share the shape is inferred)`
- `Risk?: ❌ Falsified (prior-attempt-failed: 2026-04-22 retrospect on this same approach showed it doesn't address the bug)`
- `Risk?: ❓ Unsupported: needs <specific check>`
- `Risk?: 🚫 Unverifiable-yet: requires running migration in staging to surface schema collision`

## Step 6: Write Outputs

After Step 4 produces the report, write outputs to the configured destinations:

### Always
- Render the full report to terminal (chat).

### Default
- **Persistent log:** Write the full report to `~/knowledge/logs/prospect/<YYYY-MM-DD>-<scope>-<slug>.md` where `<scope>` is the resolved scope keyword from Step 0 (`plan`, `session`, `todos`, `file`, `linear`, or `branch`) and `<slug>` is derived from the goal or referenced ticket(s). Resolve `~/knowledge/` from the configured `knowledge_root`. Create the `logs/prospect/` subfolder lazily on first use. Mirror retrospect's logging convention. Existing files written under the older `<YYYY-MM-DD>-<slug>.md` pattern are grandfathered (no rename).

  Prepend a structured YAML frontmatter block to the report before writing. Schema:

  ```yaml
  ---
  type: prospect
  date: <YYYY-MM-DD>
  scope: <plan | session | todos | file | linear | branch>
  goal: <one-line stated goal from §4.1 Anchor>
  tickets: [<LINEAR-123>, <LINEAR-456>]   # empty list if none
  steps_count: <N>
  sourcing_pass:
    candidates: <N>
    upgraded_validated: <N>
    upgraded_falsified: <N>
    no_movement: <N>
  patterns_hit: [<pattern-name-1>, <pattern-name-2>]   # from §4.4; empty list if none
  overall_verdict: <PROCEED | PROCEED-WITH-CHANGES | HOLD | KILL>   # from §4.8
  related: [<paths to overlapping prior runs — see below>]
  tags: [prospect, <scope>, <project-tag-if-detected>, <pattern-tag-if-applicable>]
  ---
  ```

  **`related` auto-detection (Q1.2=1, ticket-based):** Before writing, glob `~/knowledge/logs/prospect/*.md` AND `~/knowledge/logs/retrospect/*.md` for files whose frontmatter `tickets:` array shares at least one ticket ID with the current report's tickets. Record their paths (relative to `~/knowledge/`) in the `related:` array. If no tickets in the current report, leave `related:` empty. Only the most recent 10 are kept if many overlap (cap on bloat).

  **`tags:` field:** always includes `prospect` and the scope keyword. Add a project tag when the plan is detected to belong to a configured project (commits/files match a `projects_list[<tag>].project_root`). Add pattern-name tags for any §4.4 hits. These tags make the file discoverable via `/index` and `/context` (per Q1.3=1 — `/index` extends its scan to `logs/{prospect,retrospect}/`).
- **Aria intake:** Suggest entries for the four backlogs based on the report content:
  - Insights → observations like "step #N's hypothesis was thinly supported because <evidence>"
  - Decisions → "Pre-mortem moved step #N from PROCEED to SHRINK; smallest version is <X>" with rationale
  - Approaches → instrumentation patterns to use during execution (e.g., "[<TAG>-PRE] marker pattern for forward verification")
  - Working rules → if §4.9 identified a plan-formation behavior that should become a Universal Rule, suggest it (do not persist without user approval per Rule 23)

  Project-scoped intake goes to `projects/<proj>/`; agnostic intake goes to the shared knowledge tree. Follow the standard aria intake confirmation flow (suggest, user reviews, write on approval).

### Opt-in
- **Linear comment:** Only when invoked with `--linear-post`. Post the Overall verdict from §4.8 + the action verdict list to each Linear ticket detected. Use Linear MCP `save_comment`. Never post the full report — too much detail for the ticket.

### Pattern library write-backs
If §4.9 produced a novel pattern and the user approved adding it, the pattern entry is written to either:
- `~/knowledge/rules/prospect-patterns.md` (canonical — created if missing), or
- `~/knowledge/projects/<proj>/prospect-patterns.md` (project-specific — created if missing)

Pattern write-backs are *separate* from intake — they go directly to the patterns file, not through backlog review.

## Step 7: Soft-Suggest Trigger Logic (Claude-side judgment)

When the skill is *not* directly invoked, Claude monitors user messages and the conversation state for cues that suggest a pre-mortem is warranted. When detected AND the current session has produced a multi-step plan with no execution yet, Claude offers — never auto-executes — `/prospect`.

Cues (non-exhaustive, judgment-based):

- "let me implement…", "I'll just code it", "ok let's do it", "ship it", "going to start now"
- "combined go" or any compound execution authorization across a multi-step plan that hasn't been validated
- A long planning conversation has produced a coherent plan but no edits have happened yet
- Brainstorming concluded with an action plan
- /distill produced a task spec
- A Linear ticket's Technical Intake was just drafted and the user is about to begin
- The plan touches >3 files OR >1 repo OR has any step rated L (>100 LOC)
- The plan rewrites working code without naming a measured problem location

Standard offer (paraphrase as appropriate):

> "Before you start: this plan has <N> steps and at least one rests on an unmeasured hypothesis. Want me to run `/prospect` first? It'll force a per-step risk check + smallest-version pass before any code lands. Cheap insurance against a `/retrospect` later."

Cue weight is judgment, not regex. When the cue is faint, just acknowledge and proceed. When the cue is clear, offer. Never auto-execute from a cue — always ask.

This logic is the forward-looking twin of `/retrospect`'s `pushback-as-cue` pattern — they share the same trigger surface but fire at opposite ends of the development cycle.

## Step 8: Validation Gates

Before finalizing the pre-mortem, verify:

1. **Anchor printed?** §4.1 must contain Goal, Mode, Source, Scope, Tickets, Evidence lines.
2. **Plan-specificity gate run?** §4.2 must address every step from Step 3.
3. **Evidence-Sourcing Pass run (or explicitly skipped)?** Step 3.5 must have addressed every preliminary ⚠/❓/🚫 candidate from Step 3 — each must end with one of: UPGRADED-TO-✅ / UPGRADED-TO-❌ / NO-MOVEMENT / INCONCLUSIVE / DEFERRED-BY-USER / SKIPPED-BY--no-source. No silent skips. The pass summary (Step 3.5.4) must be emitted.
4. **Per-step verdicts complete?** Every step has all required fields (Concreteness, Necessary?, Smallest version, Maintenance cost, Risk?, Action). Risk? values reflect post-Step-3.5 state. Missing field = incomplete report.
5. **Risk hard rule respected?** No step has Action: PROCEED unless post-Step-3.5 Risk? is ✅ Pre-validated, OR ⚠ Theory-driven WITH explicit "Acceptable risk because: …" appended. Verify before emitting.
6. **Pattern check ran?** §4.4 must reference all loaded pattern libraries (canonical retrospect + canonical prospect if exists + project-specific if applicable).
7. **Tally consistent?** Counts in §4.5's risk-status block must match the per-step data in §4.3 (post-Step-3.5). Counts in §4.5's Evidence-Sourcing Pass block must match Step 3.5.4's summary.
8. **Hypotheses present when needed?** §4.7 is required if any step is post-Step-3.5 ⚠ Theory-driven, ❓ Unsupported, or §4.6 #1 triggered re-frame. Evidence FOR/AGAINST must integrate Step 3.5 findings where applicable.
9. **Action verdict complete?** §4.8 must have an action for every step in §4.3, plus an Overall verdict.
10. **Residual evidence asks correctly scoped?** §4.10 must list ONLY residual items (NOT-ATTEMPTED / ATTEMPTED-FAILED / DEFERRED-BY-USER / SKIPPED-BY--no-source). Items resolved by Step 3.5 (✅ upgrades or ❌ falsifications) must NOT appear in §4.10. Cross-check: every §4.10 entry's step must have post-Step-3.5 Risk? of ⚠/❓/🚫.
11. **Outputs written?** Confirm the persistent log was written to disk and intake suggestions were surfaced.

If any check fails, self-correct once. If self-correction can't close the gap (e.g., the user must supply evidence), surface the gap explicitly in the report rather than silently skipping.
