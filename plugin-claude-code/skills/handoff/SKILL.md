---
description: "Generate a passoff package so the next reader can pick up cleanly — for future-you in a new session (typically when context is high and you need to restart) or for a coworker (via brief mode). Default + `auto` modes emit a paste-ready next-session opener as the headline artifact, alongside PROGRESS / CLAUDE / memory updates, commit, and /extract; `brief` mode emits an 80-150 word coworker-facing prose brief instead (Slack/email-ready, no file writes). Use when handing off — not when finishing for the day with nothing pending (closing out a finished session with no passoff is a different skill). Triggers: '/handoff', '/handoff auto', '/handoff brief', 'hand it off', 'handoff and extract', 'context is full, restart this', 'pass off to next session', 'brief a coworker on this', 'wrap and prompt'. (Claude Code variant — bare-slash canonical when both ports loaded; see ADR-094.)"
argument-hint: "[auto|brief]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# /handoff — Express Session Handoff

Generate a passoff package so the next reader can pick up cleanly. Two audiences:

- **Next-session handoff** (default + `auto`) — For future-you in a new session (typically when context is high and you need to restart). Synthesizes the session, applies PROGRESS.md / CLAUDE.md / memory updates, commits, runs `/extract`, and emits a **paste-ready next-session opener as the headline artifact**.
- **Coworker brief** (`brief`) — For another person. Produces a copy/paste prose block (Slack/email-ready) summarizing the session. Does NOT update PROGRESS/CLAUDE/memory, does NOT commit, does NOT run /extract. Output-only — paste it and you're done.

For "I'm done, close it out cleanly" with no passoff intent, use `/wrapup` instead.

**Three modes:**

- **Default (`/handoff`)** — Generate ALL drafts (session summary, PROGRESS entry, CLAUDE.md edits, memory updates, commit message, next-session prompt) into one scroll, ask once for combined-go, then apply atomically. Per-item edits allowed.
- **`auto` (`/handoff auto`)** — Implicit-yes on all gates. Run silently. Apply all drafts without confirmation. Emit final report only. Use when the session is short and unambiguous.
- **`brief` (`/handoff brief`)** — Generate a coworker-facing prose brief (80-150 words, copy/paste-ready). Skips PROGRESS/CLAUDE/memory/commit/extract entirely. Emits the brief as the only artifact.

**The next-session opener is the headline artifact** in default + auto modes — always produced, even when no other surface changed. That is what distinguishes `/handoff` from `/wrapup`. Brief mode is a different shape — handoff to a person, not to a session.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/handoff` resolves to this skill — aria-knowledge (Code) is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. The Cowork variant is namespaced-only: `/aria-cowork:handoff`.

**Before Step 0:** Check that the `Bash` tool is available in this session. If `Bash` is NOT available (you are running in Claude Cowork or another non-Code runtime), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/handoff` from a non-Code runtime.**
>
> This variant runs `git status` / `git commit` via Bash, which isn't available here. The runtime-appropriate variant is `/aria-cowork:handoff`, which emits a copy-paste commit message instead.
>
> **Use `/aria-cowork:handoff` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `aria-cowork:handoff` with the same arguments the user provided to this invocation (e.g., if invoked as `/handoff auto`, invoke the cowork variant with `args: "auto"`). Do not proceed with this skill's steps; the cowork variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-knowledge) variant anyway despite the runtime mismatch. The user has explicitly opted in; subsequent Bash failures are expected.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args; the user loses ~1 keystroke vs. fully silent auto.

If `Bash` is available, proceed to Step 0.

## Step 0: Resolve Config and Parse Mode

Read `~/.claude/aria-knowledge.local.md` and extract `knowledge_folder`. If missing, stop: "aria-knowledge is not configured. Run /setup to get started."

Parse the argument:
- No arg, or arg is empty → `mode = combined-go` (default)
- Arg matches `auto` (case-insensitive) → `mode = auto`
- Arg matches `brief` (case-insensitive) → `mode = brief`
- Any other arg → stop: "Unknown argument '{arg}'. Use '/handoff', '/handoff auto', or '/handoff brief'."

Use `{knowledge_folder}` as the base path for all file operations.

## Step 1: Identify Project Context

Same logic as `/wrapup` Step 1 — detect:
- **Project root** — directory containing PROGRESS.md and/or CLAUDE.md (search upward from cwd)
- **PROGRESS.md path** — if exists
- **CLAUDE.md path(s)** — root + relevant subfolder
- **Memory files** — any `project_*.md` files in `~/.claude/projects/` matching the current path
- **Git repos** — run `git status` in each git repository within the project to detect uncommitted changes

Additionally, determine the **project marker** for the next-session opener (Step 9):
- Match the working directory against the project codes documented in the user's root CLAUDE.md (e.g., `cs`, `ss`, `df`, `kn`, `ar`, `jp` if those conventions exist).
- If no SessionStart-hook project-code convention is detected, use the project's folder name as the marker.
- If no project is identifiable, use the literal `[no-project]` — the opener will still work, just without auto-routing.

If no PROGRESS.md or CLAUDE.md is found, note this — proceed with the steps that apply.

## Step 2: Synthesize Session Work (silent)

Build the session synthesis internally — do NOT print it yet:

1. **Files changed** — list files created/modified/deleted during this session (from conversation context, not git)
2. **Key decisions** — architectural choices, approach selections
3. **Current state** — what's working, in-progress, blocked
4. **Next steps** — what the user indicated should happen next, or what logically follows
5. **Open threads** — anything explicitly deferred or flagged for later

This synthesis feeds every subsequent step.

**Mode branch:** If `mode = brief`, jump to Step 2B (Brief Output) and stop there. Skip Steps 3-8 entirely. Otherwise continue to Step 3.

## Step 2B: Brief Output (brief mode only)

**Skip this step entirely if `mode != brief`.**

Brief mode produces a single copy/paste artifact — a coworker-facing prose brief. No PROGRESS update, no CLAUDE.md edit, no memory write, no commit, no /extract call. Just the prose, formatted for paste into Slack / email / chat.

### 2B.1: Build the brief from Step 2 synthesis

Compose an 80-150 word prose block following this template (cap at 200 words). Fill placeholders from the Step 2 synthesis; if a section has no relevant content for this session, omit the section line entirely (don't leave empty bullets).

```
Hey [coworker] —

Quick brief on {topic from synthesis} from {YYYY-MM-DD}:

**What happened:** {2-3 sentence summary drawn from synthesis "Current state" + "Files changed"}

**Key decisions:**
- {decision 1 from synthesis "Key decisions"}
- {decision 2}
- {decision 3 if relevant — cap at 4 bullets}

**What's next:** {1-2 sentences from synthesis "Next steps" + "Open threads"}

**Where to pick up:** {file path, PR link, ticket ref, or doc link — omit this whole line if N/A}

Let me know if you want me to walk through any of this.
```

Notes for filling the template:
- Keep `[coworker]` as a literal placeholder — user fills the name at paste time. Don't prompt for a name.
- Tone: warm-but-professional default. Write as if briefing a peer who shares context but wasn't in the room. Avoid corporate hedging and avoid forced casualness.
- "**What happened**" is the heaviest section — get the 2-3 sentence summary right. If the session was short or unclear, say so plainly rather than padding.
- "**Key decisions**" should be the genuinely-decided things, not options-still-on-the-table. 0 decisions is fine — if so, omit the section entirely.
- "**Where to pick up**" only appears if there's a concrete artifact reference (file, PR, ticket, doc URL). Otherwise omit the line.
- Stay under 200 words. Above that, the format breaks down and reads as a memo, not a brief.

### 2B.2: Emit the brief

Emit the brief inside a code fence so it copies cleanly. Format:

```
## Coworker Brief — {YYYY-MM-DD}

Paste this directly into Slack / email / chat:

```
{full brief from 2B.1}
```

That's it — no further handoff steps run in brief mode. If you also want to update PROGRESS.md, memory, or run /extract, invoke `/handoff` (default) or `/handoff auto` separately.
```

**Exit after emission.** Do not run any subsequent steps.

## Step 3: Draft All Updates (silent)

In parallel, draft every artifact this handoff might write. Do NOT apply anything yet.

### 3a: PROGRESS.md entry
If PROGRESS.md exists: draft a new session entry matching the existing format (heading style, date format, structure). If today's entry already exists, draft an *append-to-existing* delta instead of a duplicate entry.

### 3b: CLAUDE.md updates
If CLAUDE.md exists: check if anything from this session contradicts, outdates, or is missing from it. If updates are needed, draft the specific edits (show old → new diffs). If nothing needs updating, mark as `current` — do NOT force updates for the sake of updating.

### 3c: Memory updates
Check `~/.claude/projects/.../memory/project_*.md` files matching the current project path. Compare against the session synthesis. If memory is stale, draft an update (specific old → new lines). If no update needed, mark as `current`.

### 3d: Commit message(s)
For each git repository with uncommitted changes: draft a conventional-commit message based on the session synthesis. List specific files to stage (NOT `git add -A`). Skip repos with no changes.

### 3e: Next-session opener (the always-on artifact)
Build a fenced block intended for paste into the next session. Format:

```
{project-marker}
Resume {project-name} from {YYYY-MM-DD} handoff.

Suggested next session: {model · effort}
  ({one-line rationale grounded in the first action})

Read first:
- {PROGRESS.md path} (latest entry)
- {primary CLAUDE.md path}
- {any relevant memory file paths}

Where we left off:
- {1-3 bullets summarizing current state}

Open threads:
- {bulleted list from synthesis "Open threads"}

First action:
- {derived from synthesis "Next steps", phrased as an imperative}
```

The opener is always produced, even when the session was short or no other artifacts changed — it's the headline deliverable.

#### Choosing the `Suggested next session:` value

The recommendation is the current session's judgment about what the **next session's hardest first action** needs. Pick the rubric row matching that first action (from the Step 2 synthesis: `Next steps` + `Open threads` + `Current state`). Both axes descend together as one difficulty gradient, so the matched row doubles as the rationale skeleton.

| Next session's character | Recommend |
|---|---|
| Novel architecture · deeply ambiguous · high asymmetric failure cost · gnarly debugging | `Opus · xhigh` (`max` only if truly hard — session-only, may overthink) |
| Design + hard multi-step implementation, real ambiguity | `Opus · high` |
| Standard implementation with a clear-ish plan, moderate complexity | `Opus · medium` |
| Planning is the hard part, execution mechanical | `opusplan` |
| Well-specified implementation, moderate mechanical work | `Sonnet · high` |
| Routine mechanical execution (sweeps, renames, doc edits, plan already written) | `Sonnet · medium` |
| Trivial lookups / status checks | `Haiku` |

Rules for the line:
- **De-version.** Write only the model family (`Opus` / `Sonnet` / `Haiku`) — a bare family name means the **latest version** of that family. Never write a version number.
- **Always include a one-line rationale** on the indented line below, grounded in the first action.
- **Effort ladder:** `low · medium · high · xhigh · max` (Opus and Sonnet support effort; `Haiku` does **not** — emit `Haiku` with no `· effort` suffix). `opusplan` (Opus plans → Sonnet executes) is its own token, no effort suffix.
- **Uncertain / no strong signal → `Opus · high`**, rationale "general session, no strong signal."
- **Spans tiers → recommend the higher tier** and say so in the rationale.

This line is advisory — it does not set the model. The user selects via `/model` and `/effort`; a running next-session model uses the effort cue + a mismatch self-check.

### 3f: SESSION.md (handoff state)
Skip if `session_state` is not `true` in `~/.claude/aria-knowledge.local.md` (read in Step 0). When enabled, draft `{project_root}/SESSION.md` as a **handoff-state** snapshot per `aria-atlas/docs/TEMPLATE_SESSION.md` (full rewrite; create if absent — the one create-exception to the skip-gracefully rule):
- Header: `lastEvent: handoff`; `at:` current UTC (`date -u +%Y-%m-%dT%H:%M:%SZ`); `currentFocus:` one line; `nextAction:` the imperative first action from 3e; `branch:`/`headCommit:` from `git -C {project_root} rev-parse --abbrev-ref HEAD` / `... rev-parse --short HEAD` (omit if not a git repo); `by:` `author_tag` (omit if unset); `sessionId:` omit unless known.
- Body: `## Where we left off` + `## Next session pickup` (2-4 sentences each); `## Next session prompt` = **the 3e opener verbatim** inside the fenced block (it may contain nested ``` fences — preserve them).

The 3e opener is authored once and reused here — single source, no divergence between the closing report's opener and the SESSION.md prompt block.

**Gitignore it, never commit it:** SESSION.md is ephemeral per-session state (atlas reads from disk; PROGRESS.md is the durable log). If `{project_root}` is a git repo and `.gitignore` doesn't already ignore `SESSION.md`, append a `SESSION.md` line to `{project_root}/.gitignore`. **Never stage SESSION.md** — exclude it from the Step 5 / 3d commit.

## Step 4: Single Combined-Go Review (default mode only)

**Skip this step entirely if `mode = auto`.**

In default mode, present all drafts together in one scroll under clear section headers, then ask **once**:

```
## Handoff Review — combined-go

[3a: PROGRESS.md entry draft]
[3b: CLAUDE.md updates draft, or "no changes needed"]
[3c: Memory updates draft, or "no changes needed"]
[3d: Commit messages + staged file lists per repo, or "no uncommitted changes"]
[3e: Next-session opener]
[3f: SESSION.md (handoff state) draft, or "skipped — session_state off"]

---

**Apply all of the above?**
- `yes` — apply all drafts, run /extract, emit final report
- `edit {section}` — let user revise a specific section before applying (3a, 3b, 3c, 3d, 3e, or 3f)
- `skip {section}` — apply everything except the named section
- `abort` — apply nothing, exit cleanly
```

Wait for explicit response. Allow multiple `edit` / `skip` directives in sequence (re-show the scroll after each revision). The final action is `yes` or `abort`.

## Step 5: Apply Drafts

Apply approved drafts in order. For `auto` mode, this runs immediately after Step 3 with no review gate.

1. **3a:** Append the PROGRESS.md entry (or merge into today's existing entry)
2. **3b:** Edit CLAUDE.md per the diffs
3. **3c:** Edit memory file(s) per the diffs
4. **3d:** For each git repo:
   - Stage the listed files (specific paths, never `git add -A`)
   - Commit with the drafted message
   - **Never push.** This applies in both modes regardless of how the repo is hosted.
5. **3f:** Write `{project_root}/SESSION.md` (handoff state, full rewrite, create if absent). Skip if `session_state` is off or the user `skip`-ped 3f.

If any step fails (e.g., commit hook rejects), surface the failure inline and stop — do not silently continue.

## Step 6: Run /extract

ALWAYS invoke `/extract` programmatically. This applies to default mode (after the user has approved the combined-go review in Step 4) AND `auto` mode unconditionally. No judgment-skip allowed — even if the session feels short, conversational, or seems to have nothing new to extract, run `/extract` anyway. The handoff skill must not pre-judge whether extraction is worthwhile; `/extract` has its own dedup logic (per its Rules section: "Never ask for confirmation — scan and dump") that correctly handles the "nothing to add" case by reporting `No uncaptured knowledge found`. Auto mode's "implicit-yes on all gates" rule converts to **"extract always runs"** here — there is no skip path. Capture `/extract`'s summary report for inclusion in Step 8.

(Brief mode never reaches Step 6 — it exits at Step 2B before any handoff side-effects, per the Rules section.)

## Step 7: Verify Handoff Readiness

Run the same checklist `/wrapup` Step 7 uses:

```
## Handoff Checklist

- PROGRESS.md — [updated / already current / not found / skipped]
- CLAUDE.md — [current / updated / not found / skipped]
- Memory — [updated / already current / not found / skipped]
- Git — [committed N file(s) / no changes / uncommitted (skipped)]
- /extract — [N items captured / nothing new]
- SESSION.md — [written: handoff (prompt embedded) / skipped (session_state off)]
- Tracked artifacts — [all fresh / N stale (consider /codemap update or /stitch verify for {tags}) / not checked]
- Next-session opener — [emitted below]
```

**Tracked artifacts check (added v2.16.1):** if active project detected (from Step 1's identification), stat `{project_root}/CODEMAP.md` and `{project_root}/STITCH.md` against `codemap_staleness_threshold_days` / `stitch_staleness_threshold_days` from config (defaults 14 / 30). Report status. Don't block on staleness — surface for visibility so next session starts with awareness.

Flag any gaps but don't block — the user may have skipped sections intentionally.

## Step 8: Final Report

Emit the closing report. **The next-session opener is the headline artifact** — surface it prominently and inside a code fence so it copies cleanly.

```
## Handoff Complete — {default | auto} mode

[Handoff Checklist from Step 7]

[/extract summary, 1-2 lines]

---

### Next-session opener — paste this to resume

```
{full opener from Step 3e}
```

Read on resume: {primary CLAUDE.md path} for current state.
```

## Rules

- **/wrapup is the interactive default; /handoff is the express lane.** Don't deprecate or replace /wrapup. They serve different cadences.
- **Always emit the next-session opener (default + auto modes only).** In default + auto, even when nothing else changed (no PROGRESS update, no commit, no memory edit), the opener is the headline deliverable. Brief mode emits the coworker brief instead — different artifact, different audience.
- **The opener always carries a `Suggested next session:` line (default + auto modes only).** De-versioned model family (`Opus`/`Sonnet`/`Haiku`, never a version number) + effort level + a one-line rationale grounded in the first action. It is advisory, not model-setting. Brief mode does not carry it. See Step 3e's rubric for the row mapping.
- **`auto` mode applies everything without confirmation.** The user explicitly opted into that risk by typing `auto`. Do not introduce confirmation gates in auto mode — that defeats the purpose.
- **`brief` mode produces output only — no side effects.** No PROGRESS update, no CLAUDE.md edit, no memory write, no commit, no /extract. The brief is a copy/paste artifact for a person, not durable state. Users who want both a brief AND state updates run `/handoff brief` then `/handoff` (or `/handoff auto`) separately — two passes, two artifacts.
- **Brief mode keeps `[coworker]` as a literal placeholder.** Don't prompt the user for a recipient name. They'll fill it at paste time. This avoids friction and supports "send to multiple people" use cases.
- **Brief mode caps at 200 words.** Above that, the format breaks down and reads as a memo, not a brief. Target 80-150 words. Omit empty sections rather than padding.
- **Combined-go preserves verification.** Default mode shows all drafts in one scroll before applying. Per-section `edit` / `skip` keeps the per-item escape hatch.
- **Never push, in any mode.** Local commits only (and brief mode doesn't commit at all). If the user wants to push, they do it separately.
- **Stage specific files, not `git add -A`.** Avoid capturing sensitive files (.env, credentials) that happen to be untracked.
- **Match existing formats** — when appending to PROGRESS.md or editing CLAUDE.md, match the heading style, date format, and structure of existing entries. Don't impose a new format.
- **Skip gracefully** — if a file doesn't exist (no PROGRESS.md, no CLAUDE.md, no memory), skip that step and note it. Don't create files that aren't already part of the project's conventions.
- **Don't invent work** — the session synthesis must reflect what actually happened in the conversation. If the session is short or unclear, say so in the synthesis (default + auto) or in the brief's "What happened" line (brief) rather than padding.
- **Delegate extraction** — /handoff calls /extract for capture in default + auto modes; it does not duplicate /extract's dedup or routing logic. Brief mode skips /extract entirely.
- **One handoff per session** — if the user runs /handoff again in the same session, check what was already done in the prior run and skip completed work. Don't duplicate PROGRESS entries or commits. Multiple `/handoff brief` runs are fine (each produces a fresh brief reflecting current state).
