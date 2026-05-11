---
description: "Express end-of-session handoff. Same coverage as /wrapup (review work, update PROGRESS/CLAUDE/memory, commit, run /extract, verify continuity) but compresses six confirmation gates into a single combined-go review — or skips review entirely with `auto`. Always emits a paste-ready next-session opener at the end. Use when ending a session and the work is clear enough to confirm in one pass. Trigger: '/handoff', '/handoff auto', 'hand it off', 'handoff and extract', 'wrap and prompt'."
argument-hint: "[auto]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# /handoff — Express Session Handoff

Same end-of-session coverage as `/wrapup` (review work → update PROGRESS.md / CLAUDE.md / memory → commit → run `/extract` → verify continuity) compressed into a single combined-go review. Emits a paste-ready next-session opener at the end.

**Two modes:**

- **Default (`/handoff`)** — Generate ALL drafts (session summary, PROGRESS entry, CLAUDE.md edits, memory updates, commit message, next-session prompt) into one scroll, ask once for combined-go, then apply atomically. Per-item edits allowed.
- **`auto` (`/handoff auto`)** — Implicit-yes on all gates. Run silently. Apply all drafts without confirmation. Emit final report only. Use when the session is short and unambiguous.

**Coverage matches /wrapup.** Differences are interaction model + the always-on next-session-prompt emission.

## Step 0: Resolve Config and Parse Mode

Read `~/.claude/aria-knowledge.local.md` and extract `knowledge_folder`. If missing, stop: "aria-knowledge is not configured. Run /setup to get started."

Parse the argument:
- No arg, or arg is empty → `mode = combined-go` (default)
- Arg matches `auto` (case-insensitive) → `mode = auto`
- Any other arg → stop: "Unknown argument '{arg}'. Use '/handoff' or '/handoff auto'."

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

**Skip this step entirely if `mode = auto`.**

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

Apply approved drafts in order. For `auto` mode, this runs immediately after Step 3 with no review gate.

1. **3a:** Append the PROGRESS.md entry (or merge into today's existing entry)
2. **3b:** Edit CLAUDE.md per the diffs
3. **3c:** Edit memory file(s) per the diffs
4. **3d:** For each git repo:
   - Stage the listed files (specific paths, never `git add -A`)
   - Commit with the drafted message
   - **Never push.** This applies in both modes regardless of how the repo is hosted.

If any step fails (e.g., commit hook rejects), surface the failure inline and stop — do not silently continue.

## Step 6: Run /extract

Invoke `/extract` programmatically. `/extract` is already non-interactive by design (per its Rules section: "Never ask for confirmation — scan and dump"), so no user prompt is needed in either mode. Capture its summary report for inclusion in Step 8.

## Step 7: Verify Handoff Readiness

Run the same checklist `/wrapup` Step 7 uses:

```
## Handoff Checklist

- PROGRESS.md — [updated / already current / not found / skipped]
- CLAUDE.md — [current / updated / not found / skipped]
- Memory — [updated / already current / not found / skipped]
- Git — [committed N file(s) / no changes / uncommitted (skipped)]
- /extract — [N items captured / nothing new]
- Next-session opener — [emitted below]
```

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
- **Always emit the next-session opener.** Even when nothing else changed (no PROGRESS update, no commit, no memory edit), the opener is the headline deliverable.
- **`auto` mode applies everything without confirmation.** The user explicitly opted into that risk by typing `auto`. Do not introduce confirmation gates in auto mode — that defeats the purpose.
- **Combined-go preserves verification.** Default mode shows all drafts in one scroll before applying. Per-section `edit` / `skip` keeps the per-item escape hatch.
- **Never push, in either mode.** Local commits only. If the user wants to push, they do it separately.
- **Stage specific files, not `git add -A`.** Avoid capturing sensitive files (.env, credentials) that happen to be untracked.
- **Match existing formats** — when appending to PROGRESS.md or editing CLAUDE.md, match the heading style, date format, and structure of existing entries. Don't impose a new format.
- **Skip gracefully** — if a file doesn't exist (no PROGRESS.md, no CLAUDE.md, no memory), skip that step and note it. Don't create files that aren't already part of the project's conventions.
- **Don't invent work** — the session synthesis must reflect what actually happened in the conversation. If the session is short or unclear, say so in the synthesis rather than padding.
- **Delegate extraction** — /handoff calls /extract for capture; it does not duplicate /extract's dedup or routing logic.
- **One handoff per session** — if the user runs /handoff again in the same session, check what was already done in the prior run and skip completed work. Don't duplicate PROGRESS entries or commits.
