---
description: "End-of-session handoff. Reviews session work, updates PROGRESS.md and CLAUDE.md if needed, prompts for commit, verifies next session can pick up cleanly, and prompts for /extract. Use when ending a session, wrapping up work, saying goodbye, or when user says '/wrapup', 'wrap up', 'end session', 'hand off', 'wrap it up'."
argument-hint: ""
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# /wrapup — Session Handoff

Review the current session's work, update project tracking files, prompt for commit and knowledge extraction, and verify a new session can pick up where this one left off.

## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md` and extract `knowledge_folder`. If the file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Use `{knowledge_folder}` as the base path for all file operations in subsequent steps.

## Step 1: Identify Project Context

Detect the active project by scanning the working directory for project markers:

1. Search upward from cwd for `PROGRESS.md` and `CLAUDE.md` files
2. Also check for `CODEMAP.md` (indicates a mapped codebase)
3. Check for project-level memory files in `~/.claude/projects/` matching the current path

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

Ask: "Does this summary look right? (yes / edit)"

If the user wants to edit, incorporate their corrections before proceeding.

## Step 3: Update PROGRESS.md

If a PROGRESS.md exists for this project:

1. Read the current PROGRESS.md
2. Check if a session entry already exists for today's work (the user or a previous /wrapup may have already added one)
3. If no entry exists, draft a new session entry using the project's existing format (match the heading style, content structure, and level of detail of previous entries)
4. Show the draft to the user

Ask: "Add this session entry to PROGRESS.md? (yes / edit / skip)"

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

Ask: "Update CLAUDE.md with these changes? (yes / edit / skip)"

If no updates are needed, say so and move on. Don't force updates for the sake of updating.

## Step 5: Update Memory

Check if project memory files (in `~/.claude/projects/` for the current project path) need updating:

1. Read the relevant `project_*.md` memory file(s)
2. Compare against the session summary — is the memory's "Current State" still accurate?
3. If the memory is stale, draft an update

Ask: "Update project memory? (yes / edit / skip)"

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

Ask: "Want to commit these changes? (yes / no / select files)"

- **yes** — stage all changes, draft a conventional commit message based on the session work, show it for confirmation, then commit
- **no** — skip committing
- **select files** — let the user specify which files to stage, then proceed with commit

If no uncommitted changes exist, say "No uncommitted changes" and move on.

**Important:** Do not push to remote. Only commit locally. If the user wants to push, they can do so separately.

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

Ask: "Run /extract to capture session knowledge before ending? (yes / no)"

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

- **Always confirm before writing** — every file modification (PROGRESS.md, CLAUDE.md, memory, git commit) requires explicit user approval. Show the proposed change first.
- **Match existing format** — when adding entries to PROGRESS.md, match the heading style, date format, and content structure of existing entries. Don't impose a new format.
- **Don't invent work** — the session summary should reflect what actually happened in the conversation, not what might have happened. If the conversation is short or unclear, say so.
- **Git safety** — never force push, never amend, never push to remote. Local commits only. Stage specific files, not `git add -A` (avoid capturing sensitive files).
- **Skip gracefully** — if a file doesn't exist (no PROGRESS.md, no CLAUDE.md, no memory), skip that step and note it. Don't create files that don't already exist as part of the project's conventions.
- **Delegate extraction** — /wrapup prompts for /extract but does not perform extraction itself. The /extract skill has its own deduplication and formatting logic.
- **One passoff per session** — if the user runs /wrapup again in the same session, check what was already done and skip completed steps. Don't duplicate entries.
