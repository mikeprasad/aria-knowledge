---
name: handoff
description: 'Generate a passoff package — for future-you (context is high, need to restart) or a coworker (via brief mode). Default + auto emit a paste-ready next-session opener plus PROGRESS/CLAUDE/memory updates, a commit message, and "/aria-cowork:extract"; brief mode emits an 80-150 word coworker prose brief only; snap = auto but defers /extract via a snapshot (context high). For done-with-no-passoff, use "/aria-cowork:wrapup". Triggers — "/aria-cowork:handoff", "/aria-cowork:handoff auto", "/aria-cowork:handoff brief", "hand it off", "pass off to next session", "brief a coworker on this". (Cowork variant — namespaced-only.)'
argument-hint: '[auto|brief|snap]'
---

# /handoff — Express Session Handoff (cowork variant)

Four modes covering two distinct handoff shapes:

- **Next-session handoff** (default + `auto` + `snap`) — Same end-of-session coverage as `/aria-cowork:wrapup` (review work → update PROGRESS.md / CLAUDE.md / memory → emit commit message → run `/extract` → verify continuity) compressed into a single combined-go review. Always emits a paste-ready next-session opener at the end. (`snap` is the auto variant that snapshots for later extraction instead of running /extract now — see the mode list below.)
- **Coworker brief** (`brief`) — Produces a copy/paste prose block (Slack/email-ready) summarizing the session for another person. Does NOT update PROGRESS/CLAUDE/memory, does NOT emit a commit message, does NOT run /extract. Output-only — paste it and you're done.

**Cowork variant of aria-knowledge's `/handoff`.** Behavior is byte-aligned where Cowork's runtime permits; three divergences shared with `/aria-cowork:wrapup`:

- **Git commit step generates a copy-paste message instead of running git directly** (Q-4 Option B — Cowork has no shell access for `git status` / `git commit`). Same shape as `/aria-cowork:wrapup` Step 6.
- **Memory file updates limited to files in the attached knowledge folder.** aria-knowledge reads `~/.claude/projects/.../memory/`; Cowork's persistent-grant model can't reach that path.
- **Tracked artifacts check (CODEMAP/STITCH staleness) skipped per ADR-005.** Step 7's checklist row about tracked artifacts is omitted in cowork.

Brief mode template (`/handoff brief`) imports from aria-knowledge v2.17.0 schema — same 80-150 word coworker-brief format, same `[coworker]` literal placeholder convention, same 4 section headers (What happened / Key decisions / What's next / Where to pick up). Schema-identical regardless of which plugin generated it.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Cowork variant — namespaced-only. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/handoff` resolves to aria-knowledge's variant — Code is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. To reach this skill, use the namespaced form: `/aria-cowork:handoff`. Do NOT match bare `/handoff` — that belongs to aria-knowledge.

**Before Step 0:** Check whether the `Bash` tool is available in this session. If `Bash` IS available (you are running in Claude Code or another runtime with shell access), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-cowork's `/handoff` from a runtime with shell access.**
>
> This variant emits a copy-paste commit message because Cowork has no shell access — but you appear to be running in Claude Code, where `git status` / `git commit` would work directly. The runtime-appropriate variant is `/handoff` (the aria-knowledge canonical), which runs git directly.
>
> **Use `/handoff` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `handoff` (the bare-slash canonical, which routes to aria-knowledge when both ports are loaded) with the same arguments the user provided to this invocation. Do not proceed with this skill's steps; the aria-knowledge variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-cowork) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto` or `mode = snap`** per ADR-094 §Part 3. Auto/snap's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — they trust that the user invoked the correct variant, and this gate enforces that precondition. All other auto/snap-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args.

If `Bash` is NOT available (normal Cowork runtime), proceed to Step 0.

**Four modes:**

- **Default (`/handoff`)** — Generate ALL drafts (session summary, PROGRESS entry, CLAUDE.md edits, memory updates, commit message, next-session prompt) into one scroll, ask once for combined-go, then apply atomically. Per-item edits allowed.
- **`auto` (`/handoff auto`)** — Implicit-yes on all gates. Run silently. Apply all drafts without confirmation. Emit final report only. Use when the session is short and unambiguous.
- **`brief` (`/handoff brief`)** — Generate a coworker-facing prose brief (80-150 words, copy/paste-ready). Skips PROGRESS/CLAUDE/memory/commit/extract entirely. Emits the brief as the only artifact.
- **`snap` (`/handoff snap`)** — Like `auto` (silent, apply all drafts, emit the next-session opener), but archives the conversation via `/aria-cowork:snapshot` for later extraction **instead of** running `/aria-cowork:extract` now. Use when context is high: you still get the full handoff package + opener + commit message, but defer the expensive, compaction-risky knowledge synthesis to a later session (or the next `/aria-cowork:audit-knowledge` digest pass).

**Coverage matches `/aria-cowork:wrapup`** for default + auto + snap modes. Brief mode is a different shape — handoff to a person, not to a session.

**`snap` is `auto` plus one swap.** snap follows auto's behavior exactly (silent, implicit-yes, apply all drafts, emit the opener) — wherever a step below applies to `auto`, it applies identically to `snap`. The single difference is the capture step (Step 6): `snap` runs `/aria-cowork:snapshot` (archive for later) while `auto` runs `/aria-cowork:extract` (synthesize now). Nothing else differs. (snap is NOT brief — it produces the full next-session package, not a coworker prose block.)

## Step 0: Resolve Config and Parse Mode

Read `<knowledge_folder>/aria-config.md` and extract `knowledge_folder`. If missing, stop: "aria-knowledge is not configured. Run /aria-setup to get started."

Parse the argument:
- No arg, or arg is empty → `mode = combined-go` (default)
- Arg matches `auto` (case-insensitive) → `mode = auto`
- Arg matches `brief` (case-insensitive) → `mode = brief`
- Arg matches `snap` (case-insensitive) → `mode = snap`
- Any other arg → stop: "Unknown argument '{arg}'. Use '/handoff', '/handoff auto', '/handoff brief', or '/handoff snap'."

Use `{knowledge_folder}` as the base path for all file operations.

## Step 1: Identify Project Context

Same logic as `/wrapup` Step 1 — detect:
- **Project root** — directory containing PROGRESS.md and/or CLAUDE.md (search upward from cwd)
- **PROGRESS.md path** — if exists
- **CLAUDE.md path(s)** — root + relevant subfolder
- **Memory files** — any `project_*.md` files in `~/.claude/projects/` matching the current path
- **Git repos** — note them in the session summary; **Cowork can't run `git status`** so detection is conversation-context based (e.g., "user mentioned files edited in the cs repo")

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
For each git repository with conversation-detected file changes: draft a conventional-commit message based on the session synthesis. List specific files to stage (NOT `git add -A`). Skip repos with no detected changes. **Cowork emits the message as a copy-paste block in Step 5 — does NOT shell out to git.**

### 3e: Next-session opener (the always-on artifact)
Build a fenced block intended for paste into the next session. Format:

```
{project-marker}
Resume {project-name} from {YYYY-MM-DD} handoff.

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

## Step 4: Single Combined-Go Review (default mode only)

**Skip this step entirely if `mode = auto` or `mode = snap`.** (Both run silently with implicit-yes — no review gate.)

In default mode, present all drafts together in one scroll under clear section headers, then ask **once**:

```
## Handoff Review — combined-go

[3a: PROGRESS.md entry draft]
[3b: CLAUDE.md updates draft, or "no changes needed"]
[3c: Memory updates draft, or "no changes needed"]
[3d: Commit messages + staged file lists per repo, or "no uncommitted changes"]
[3e: Next-session opener]

---

**Apply all of the above?**
- `yes` — apply all drafts, run /extract, emit final report
- `edit {section}` — let user revise a specific section before applying (3a, 3b, 3c, 3d, or 3e)
- `skip {section}` — apply everything except the named section
- `abort` — apply nothing, exit cleanly
```

Wait for explicit response. Allow multiple `edit` / `skip` directives in sequence (re-show the scroll after each revision). The final action is `yes` or `abort`.

## Step 5: Apply Drafts

Apply approved drafts in order. For `auto` and `snap` modes, this runs immediately after Step 3 with no review gate.

1. **3a:** Append the PROGRESS.md entry (or merge into today's existing entry)
2. **3b:** Edit CLAUDE.md per the diffs
3. **3c:** Edit memory file(s) per the diffs
4. **3d:** For each git repo: **emit a copy-paste commit-command block for the user to run in their terminal** (cowork has no shell access — Q-4 Option B). Do NOT attempt to shell `git`. Format:

   ```
   ## Commit message — copy/paste to run in your terminal

   Files to stage:
     git add path/to/file1.md path/to/file2.md

   Commit:
     git commit -m "type(scope): description

     Body lines here."
   ```

   - **Never push.** Push is always an explicit user action from their terminal.
   - **Never `git add -A`.** The emitted block lists specific files only.

If a non-git step fails (e.g., file write error on PROGRESS.md), surface the failure inline and stop — do not silently continue. Commit-message emission can't fail (it's just text output).

## Step 6: Capture Session Knowledge

**If `mode = snap`:** Do NOT run `/aria-cowork:extract`. Instead invoke the `/aria-cowork:snapshot` skill to archive the conversation to `intake/pre-compact-captures/` for later extraction. This is snap mode's defining difference: capture is deferred, not synthesized now. Like auto's "extract always runs" invariant, the snapshot ALWAYS runs — there is no skip path. The snapshot is the deferred-extraction handoff: a later `/aria-cowork:extract`, or the next `/aria-cowork:audit-knowledge` digest pass (which reads `intake/pre-compact-captures/` automatically), synthesizes knowledge from it when context isn't a constraint. Capture `/aria-cowork:snapshot`'s output (the snapshot path) for inclusion in Step 8. Use snap when context is high and running `/aria-cowork:extract` now would risk compaction mid-synthesis. (Cowork's `/snapshot` uses 3-path source acquisition — no shell access needed.)

**Otherwise (default + `auto` modes):** ALWAYS invoke `/aria-cowork:extract` programmatically. This applies to default mode (after the user has approved the combined-go review in Step 4) AND `auto` mode unconditionally. No judgment-skip allowed — even if the session feels short, conversational, or seems to have nothing new to extract, run `/aria-cowork:extract` anyway. The handoff skill must not pre-judge whether extraction is worthwhile; `/extract` has its own dedup logic (per its Rules section: "Never ask for confirmation — scan and dump") that correctly handles the "nothing to add" case by reporting `No uncaptured knowledge found`. Auto mode's "implicit-yes on all gates" rule converts to **"extract always runs"** here — there is no skip path. Capture `/extract`'s summary report for inclusion in Step 8.

(Brief mode never reaches Step 6 — it exits at Step 2B before any handoff side-effects, per the Rules section.)

## Step 7: Verify Handoff Readiness

Run the same checklist `/wrapup` Step 7 uses:

```
## Handoff Checklist

- PROGRESS.md — [updated / already current / not found / skipped]
- CLAUDE.md — [current / updated / not found / skipped]
- Memory — [updated / already current / not found / skipped]
- Git — [commit message emitted / no changes detected / skipped]
- /extract — [run / nothing new / deferred: snapshotted for later extraction (snap mode)]
- Next-session opener — [emitted below]
```

**Tracked artifacts check — SKIPPED in cowork per ADR-005 + D5:** aria-knowledge's `/handoff` Step 7 stats `CODEMAP.md` + `STITCH.md` against staleness thresholds and surfaces them in the checklist. Cowork excludes `/codemap` + `/stitch` skills (per ADR-005), so no tracked artifacts to check. The checklist row is omitted entirely (replaced above with the cowork-relevant Git commit-message + /extract rows).

Flag any gaps but don't block — the user may have skipped sections intentionally.

## Step 8: Final Report

Emit the closing report. **The next-session opener is the headline artifact** — surface it prominently and inside a code fence so it copies cleanly.

```
## Handoff Complete — {default | auto | snap} mode

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
- **Always emit the next-session opener (default + auto + snap modes; not brief).** In default + auto + snap, even when nothing else changed (no PROGRESS update, no commit, no memory edit), the opener is the headline deliverable. Brief mode emits the coworker brief instead — different artifact, different audience.
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
- **Delegate extraction** — /handoff calls /extract for capture in default + auto modes; it does not duplicate /extract's dedup or routing logic. Brief mode skips /extract entirely. Snap mode calls /aria-cowork:snapshot instead of /extract (see below).
- **`snap` defers, never drops, capture.** In snap mode Step 6 runs `/aria-cowork:snapshot` instead of `/aria-cowork:extract` — the snapshot ALWAYS runs (no skip path, same as auto's "extract always runs" invariant). The conversation is preserved so a later /extract or /audit-knowledge digest can synthesize it; snap never means "skip knowledge capture," only "capture cheaply now, synthesize later." snap is otherwise byte-for-byte auto behavior: silent, implicit-yes, emit the next-session opener, commit-message-only (never runs git). snap is NOT brief — it produces the full next-session package, not a coworker prose block, and unlike brief it DOES update PROGRESS/CLAUDE/memory and emit a commit message.
- **One handoff per session** — if the user runs /handoff again in the same session, check what was already done in the prior run and skip completed work. Don't duplicate PROGRESS entries or commits. Multiple `/handoff brief` runs are fine (each produces a fresh brief reflecting current state).
