---
name: wrapup
description: >
  End-of-session handoff. Reviews session work, updates PROGRESS.md and CLAUDE.md if needed, generates a commit message for the user to run, verifies next session can pick up cleanly, and prompts for /extract. Use when ending a session, wrapping up work, saying goodbye, or when user says "/wrapup", "/aria-cowork:wrapup", "wrap up", "end session", "hand off", "wrap it up".
---

# /wrapup — Session Handoff (cowork variant)

Review the current session's work, update project tracking files, generate a commit message for the user to run, prompt for knowledge extraction, and verify a new session can pick up where this one left off.

**Cowork variant of aria-knowledge's `/wrapup`.** Behavior is byte-aligned where Cowork's runtime permits; three divergences:

- **Git commit step generates a copy-paste message instead of running git directly** (Q-4 Option B — Cowork has no shell access for `git status` / `git commit`).
- **Memory file updates limited to files in the attached knowledge folder.** aria-knowledge reads `~/.claude/projects/.../memory/`; Cowork's persistent-grant model can't reach that path.
- **Tracked artifacts check (CODEMAP/STITCH staleness) skipped per ADR-005.** aria-knowledge runs this in its Step 7; cowork omits.

Schema-identical outputs (PROGRESS.md entries, CLAUDE.md edits, commit message format) — only invocation and discovery paths differ.

## Step 0: Resolve config

The default knowledge folder is `~/Projects/knowledge/` (expand `~` to your home directory's absolute path). Read `<knowledge_folder>/aria-config.md` and extract `knowledge_folder`. If `aria-config.md` doesn't exist, stop: *"aria-cowork is not configured. Run `/aria-setup` to get started."*

Use `<knowledge_folder>` for all file operations during this session.

## Step 1: Identify project context

Detect the active project by scanning for project markers in the attached knowledge folder OR via explicit conversation-context signals:

1. Check the attached folder structure for `PROGRESS.md` and `CLAUDE.md` files
2. Also check for `CODEMAP.md` (indicates a mapped codebase)
3. Check for project memory files at `<knowledge_folder>/.../memory/` matching the current conversation's project context (Cowork can't reach `~/.claude/projects/.../memory/` directly — only memory files inside the granted knowledge folder are reachable)

Record:

- **Project root** — the directory containing PROGRESS.md and/or CLAUDE.md
- **PROGRESS.md path** — if it exists
- **CLAUDE.md path(s)** — root-level and any subfolder-level ones relevant to the session
- **Memory files** — any `project_*.md` files in the reachable memory directory for this project
- **Git repos** — note them in the session summary; Cowork can't run `git status` so detection is conversation-context based (e.g., "user mentioned they're working in the cs repo")

If no PROGRESS.md or CLAUDE.md is found, note this — the session may be in a project that doesn't use these conventions. Continue with the steps that are applicable.

## Step 2: Review session work

Summarize what was accomplished in this session:

1. **Work completed** — files reviewed, drafts written, decisions discussed, docs read
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

Ask: *"Does this summary look right? (yes / edit)"*

If the user wants to edit, incorporate their corrections before proceeding.

## Step 3: Update PROGRESS.md

If a PROGRESS.md exists for this project:

1. Read the current PROGRESS.md
2. Check if a session entry already exists for today's work (the user or a previous `/wrapup` may have already added one)
3. If no entry exists, draft a new session entry using the project's existing format (match the heading style, content structure, and level of detail of previous entries)
4. Show the draft to the user

Ask: *"Add this session entry to PROGRESS.md? (yes / edit / skip)"*

- **yes** — append the entry
- **edit** — let the user modify, then append
- **skip** — leave PROGRESS.md as-is

If PROGRESS.md doesn't exist, skip this step and note it in the final report.

**Schema-identical to aria-knowledge:** the PROGRESS.md entry format produced by cowork's /wrapup is byte-aligned with aria-knowledge's /wrapup output. A project's PROGRESS.md can have entries written by either plugin without format drift.

## Step 4: Check CLAUDE.md currency

If a CLAUDE.md exists for this project and is reachable through the attached knowledge folder:

1. Read the CLAUDE.md
2. Check if anything from this session contradicts, outdates, or is missing from it — examples:
   - New conventions established that aren't documented
   - File paths or structures that changed
   - Known issues that were resolved or new ones discovered
   - Tool/integration changes
3. If updates are needed, show the proposed changes

Ask: *"Update CLAUDE.md with these changes? (yes / edit / skip)"*

If no updates are needed, say so and move on. Don't force updates for the sake of updating.

**Cowork-specific note:** if the relevant CLAUDE.md lives in a repo Cowork can't reach (e.g., a private repo not attached to this session), generate the proposed edits as a copy-paste block for the user to apply themselves — same shape as Step 6's commit-message handling.

## Step 5: Update memory

Check if project memory files in the **reachable knowledge folder** need updating:

1. Read the relevant `project_*.md` memory file(s) under `<knowledge_folder>/`
2. Compare against the session summary — is the memory's *"Current State"* still accurate?
3. If the memory is stale, draft an update

Ask: *"Update project memory? (yes / edit / skip)"*

If no memory file exists or no update is needed, skip and note it.

**Cowork divergence:** aria-knowledge's /wrapup also reads `~/.claude/projects/.../memory/project_*.md` (Code's auto-memory location). Cowork's persistent-grant model can't reach `~/.claude/` per probe 12 — only memory files inside the attached knowledge folder are touched. If the project has memory at `~/.claude/projects/`, the user should run aria-knowledge's `/wrapup` from Claude Code OR move the memory files into the knowledge folder.

## Step 6: Commit prompt (cowork variant — generate message, don't run git)

For each git repository identified in Step 1:

1. If there are uncommitted changes (per conversation context — Cowork can't run `git status`), draft a conventional commit message based on the session work
2. Show the message + the specific files to stage (NOT `git add -A`)
3. Emit as a copy-paste block:

```
## Commit message — copy/paste to run in your terminal

Files to stage:
  git add path/to/file1.md path/to/file2.md path/to/file3.md

Commit:
  git commit -m "type(scope): description

  Body lines
  here."

(or use the heredoc form if the message is long — see your CLAUDE.md for repo conventions.)
```

Do NOT attempt to run git directly — Cowork has no shell access. The user runs the commands themselves in their terminal and confirms when done.

If the user has no git repo context for this session (e.g., the session was purely conversational with no file changes), say *"No commit needed — no file changes detected in this session."* and move on.

**Important:** Cowork never pushes either. The user pushes from their terminal after committing. Push is always an explicit user action.

## Step 7: Verify handoff readiness

Run through a checklist and report status:

```
## Handoff Checklist

- PROGRESS.md — [updated / already current / not found / skipped]
- CLAUDE.md — [current / updated (in-place) / updated (copy-paste emitted) / not found / skipped]
- Memory — [updated / already current / not found (cowork can't reach) / skipped]
- Git — [commit message emitted / no changes / skipped]
- /extract — [run / skipped]
```

**Tracked artifacts check (CODEMAP/STITCH staleness):** SKIPPED in cowork per ADR-005. aria-knowledge runs this check in its Step 7; cowork omits because `/codemap` and `/stitch` are not ported. If you want tracked-artifact staleness reporting, run aria-knowledge's `/wrapup` from Claude Code.

If any item shows a gap (commit-message emitted but not yet run, PROGRESS.md not updated), flag it — but don't block. The user may have good reasons to defer.

## Step 8: Prompt extract

Ask: *"Run `/aria-cowork:extract` to capture session knowledge before ending? (yes / no)"*

- **yes** — invoke the `/extract` skill (it handles its own config resolution and execution)
- **no** — skip

## Step 9: Report

Output a brief closing summary:

```
## Session Handoff Complete

[1-2 lines: what was updated]

**Next session pickup:** Read [path to PROGRESS.md or CLAUDE.md]
[If commit message was emitted but not yet run: "Reminder: commit message awaiting your terminal run."]
```

## Rules

- **Always confirm before writing** — every file modification (PROGRESS.md, CLAUDE.md, memory) requires explicit user approval. Show the proposed change first.
- **Match existing format** — when adding entries to PROGRESS.md, match the heading style, date format, and content structure of existing entries. Don't impose a new format.
- **Don't invent work** — the session summary should reflect what actually happened in the conversation, not what might have happened. If the conversation is short or unclear, say so.
- **Git is user-driven in Cowork** — cowork generates commit messages but never shells `git`. Push is always explicit by the user from their terminal. Never `git add -A` in the suggested commands (avoid capturing sensitive files); stage specific files only.
- **Skip gracefully** — if a file doesn't exist (no PROGRESS.md, no CLAUDE.md, no memory), skip that step and note it. Don't create files that don't already exist as part of the project's conventions.
- **Delegate extraction** — /wrapup prompts for `/aria-cowork:extract` but does not perform extraction itself. The /extract skill has its own deduplication and formatting logic.
- **One passoff per session** — if the user runs /wrapup again in the same session, check what was already done and skip completed steps. Don't duplicate entries.
- **Schema-identical PROGRESS.md output** — cowork's /wrapup writes PROGRESS.md entries in the same format as aria-knowledge's /wrapup. Mixed-source PROGRESS.md files (some entries from cowork, some from aria-knowledge) read uniformly.
- **Use Cowork's native I/O** — never invoke a Filesystem MCP connector (per ADR-003).
