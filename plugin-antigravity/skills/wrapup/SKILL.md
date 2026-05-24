---
description: "Close out a session cleanly when the work is done — no passoff intended. Reviews session work, updates PROGRESS.md / CLAUDE.md / memory, commits changes, captures session knowledge via /extract, and confirms everything is wrapped up, captured, and documented. Use when the task is complete and nothing needs to carry into a next session. For passoff to future-you (e.g. context is high, need to restart) or a coworker, use /handoff instead. Triggers: '/wrapup', '/wrapup auto', 'wrap up', 'wrap it up', \"I'm done\", 'close out', 'finish session', 'end session', 'saying goodbye'. Auto mode applies implicit-yes on all gates and runs silently."
---

# /wrapup — Session Close-Out

Close out the current session cleanly: review what got done, update project tracking files, commit changes, capture session knowledge, and confirm everything is documented. This is the "I'm done" skill — no next-session opener is produced. For passoff (future-you or a coworker), use `/handoff` instead.

**Two modes:**

- **Default (`/wrapup`)** — Per-step gated review. Each tracked surface (session summary, PROGRESS, CLAUDE.md, memory, commit, /extract prompt) prompts for explicit confirmation before writing.
- **`auto` (`/wrapup auto`)** — Implicit-yes on all gates. Run silently. Apply all drafts and chain `/extract` without confirmation. Emit final report only. Use when the session is short and unambiguous, or when you've already authorized a combined-go (`yes to all`, `yes to all with extract`).

## Step 0: Resolve Config and Parse Mode

Read `~/.gemini/antigravity/aria-knowledge.local.md` and extract `knowledge_folder`. If the file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Parse the argument:
- No arg, or arg is empty → `mode = gated` (default)
- Arg matches `auto` (case-insensitive) → `mode = auto`
- Any other arg → stop: "Unknown argument '{arg}'. Use '/wrapup' or '/wrapup auto'."

Use `{knowledge_folder}` as the base path for all file operations in subsequent steps.

## Step 1: Identify Project Context

Detect the active project by scanning the working directory for project markers:

1. Search upward from cwd for `PROGRESS.md` and `CLAUDE.md` files
2. Also check for `CODEMAP.md` (indicates a mapped codebase)
3. Check for project-level memory files in `~/.gemini/antigravity/transcripts/` matching the current path

Record:
- **Project root** — the directory containing PROGRESS.md and/or CLAUDE.md
- **PROGRESS.md path** — if it exists
- **CLAUDE.md path(s)** — root-level and any subfolder-level ones relevant to the session
- **Memory files** — any `project_*.md` files in the Claude memory directory for this project path
- **Git repos** — run `git status` in any git repositories within the project to detect uncommitted changes

If no PROGRESS.md or CLAUDE.md is found, note this — the session may be in a project that doesn't use these conventions. Continue with the steps that are applicable.

## Step 2: Review Session Work

Summarize what was accomplished in this session:

1. **Files changed** — list files created, modified, or deleted during this session (from conversation context, not git — git may include changes from before this session)
2. **Key decisions** — architectural choices, design decisions, approach selections made during the session
3. **Current state** — what's working, what's in progress, what's blocked
4. **Next steps** — what the user indicated should happen next, or what logically follows

Present this summary to the user:

```
## Session Summary

**Project:** [project name/path]
**Focus:** [1-line description of session goal]

**Work completed:**
- [bullet list of what was done]

**Decisions made:**
- [bullet list of key decisions]

**Next steps:**
- [what follows from here]
```

**If `mode = auto`:** skip the prompt and proceed with the drafted summary as-is.

**Otherwise (gated mode):** Ask: "Does this summary look right? (yes / edit)"

If the user wants to edit, incorporate their corrections before proceeding.

## Step 3: Update PROGRESS.md

If a PROGRESS.md exists for this project:

1. Read the current PROGRESS.md
2. Check if a session entry already exists for today's work (the user or a previous /wrapup may have already added one)
3. If no entry exists, draft a new session entry using the project's existing format (match the heading style, content structure, and level of detail of previous entries)
4. Show the draft to the user

**If `mode = auto`:** append the drafted entry without prompting (equivalent to **yes**).

**Otherwise (gated mode):** Ask: "Add this session entry to PROGRESS.md? (yes / edit / skip)"

- **yes** — append the entry
- **edit** — let the user modify, then append
- **skip** — leave PROGRESS.md as-is

If PROGRESS.md doesn't exist, skip this step and note it in the final report.

## Step 4: Check CLAUDE.md Currency

If a CLAUDE.md exists for this project:

1. Read the CLAUDE.md
2. Check if anything from this session contradicts, outdates, or is missing from it — examples:
   - New conventions established that aren't documented
   - File paths or structures that changed
   - Known issues that were resolved or new ones discovered
   - Tool/integration changes
3. If updates are needed, show the proposed changes

**If `mode = auto`:** apply the drafted CLAUDE.md updates without prompting (equivalent to **yes**). If no updates are needed, note that in the final report and move on.

**Otherwise (gated mode):** Ask: "Update CLAUDE.md with these changes? (yes / edit / skip)"

If no updates are needed, say so and move on. Don't force updates for the sake of updating.

## Step 5: Update Memory

Check if project memory files (in `~/.gemini/antigravity/transcripts/` for the current project path) need updating:

1. Read the relevant `project_*.md` memory file(s)
2. Compare against the session summary — is the memory's "Current State" still accurate?
3. If the memory is stale, draft an update

**If `mode = auto`:** apply the drafted memory update without prompting (equivalent to **yes**). If no memory file exists or no update is needed, note that in the final report and move on.

**Otherwise (gated mode):** Ask: "Update project memory? (yes / edit / skip)"

If no memory file exists or no update is needed, skip and note it.

## Step 6: Commit Prompt

For each git repository detected in Step 1:

1. Run `git status` to check for uncommitted changes
2. If there are changes, show a summary:
   ```
   **Uncommitted changes in [repo path]:**
   - [N] modified files
   - [N] new files
   - [N] deleted files
   [list the file names]
   ```

**If `mode = auto`:** stage all changes (per-file, not `git add -A` — exclude anything that looks like a secret or unrelated work-in-progress), draft a conventional commit message from the session work, and commit without prompting. Skip the message-confirmation step. Still **local commit only — never push.**

**Otherwise (gated mode):** Ask: "Want to commit these changes? (yes / no / select files)"

- **yes** — stage all changes, draft a conventional commit message based on the session work, show it for confirmation, then commit
- **no** — skip committing
- **select files** — let the user specify which files to stage, then proceed with commit

If no uncommitted changes exist, say "No uncommitted changes" and move on.

**Important:** Do not push to remote. Only commit locally. If the user wants to push, they can do so separately. This applies to both modes.

## Step 7: Verify Handoff Readiness

Run through a checklist and report status:

```
## Handoff Checklist

- [x/!/ ] PROGRESS.md — [updated / already current / not found / skipped]
- [x/!/ ] CLAUDE.md — [current / updated / not found / skipped]
- [x/!/ ] Memory — [updated / already current / not found / skipped]
- [x/!/ ] Git — [committed / no changes / uncommitted changes (user skipped)]
- [x/!/ ] Tracked artifacts — [all fresh / N stale (consider /codemap update or /stitch verify) / not checked]
```

**Tracked artifacts check (added v2.16.1):** if active project detected (from Step 1's identification), stat `{project_root}/CODEMAP.md` and `{project_root}/STITCH.md` against `codemap_staleness_threshold_days` / `stitch_staleness_threshold_days` from config (defaults 14 / 30). Report status with `x` (fresh), `!` (stale), or blank (not checked). Don't block on staleness — surface for next-session awareness.

If any item shows a gap (uncommitted changes skipped, PROGRESS.md not updated), flag it — but don't block. The user may have good reasons to defer.

## Step 8: Prompt Extract

**If `mode = auto`:** invoke the `/extract` skill without prompting. It handles its own config resolution and execution. (Captures session knowledge so the close-out is fully documented.)

**Otherwise (gated mode):** Ask: "Run /extract to capture session knowledge before ending? (yes / no)"

- **yes** — invoke the /extract skill (it handles its own config resolution and execution)
- **no** — skip

## Step 9: Report

Output a brief closing summary:

```
## Session Handoff Complete

[1-2 lines: what was updated]

**Next session pickup:** Read [path to PROGRESS.md or CLAUDE.md]
```

## Rules

- **Confirm before writing in gated mode** — every file modification (PROGRESS.md, CLAUDE.md, memory, git commit) requires explicit user approval; show the proposed change first. In `auto` mode, the explicit user approval comes from the `/wrapup auto` invocation itself (or a combined-go signal like `yes to all`) and per-step prompts are skipped.
- **Match existing format** — when adding entries to PROGRESS.md, match the heading style, date format, and content structure of existing entries. Don't impose a new format.
- **Don't invent work** — the session summary should reflect what actually happened in the conversation, not what might have happened. If the conversation is short or unclear, say so.
- **Git safety** — never force push, never amend, never push to remote. Local commits only. Stage specific files, not `git add -A` (avoid capturing sensitive files).
- **Skip gracefully** — if a file doesn't exist (no PROGRESS.md, no CLAUDE.md, no memory), skip that step and note it. Don't create files that don't already exist as part of the project's conventions.
- **Delegate extraction** — /wrapup prompts for /extract but does not perform extraction itself. The /extract skill has its own deduplication and formatting logic.
- **One passoff per session** — if the user runs /wrapup again in the same session, check what was already done and skip completed steps. Don't duplicate entries.
