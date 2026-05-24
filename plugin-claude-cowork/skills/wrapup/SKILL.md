---
name: wrapup
description: 'Close out cleanly when work is done — no passoff intended. updates PROGRESS / CLAUDE / memory in the attached knowledge folder, emits a commit message for you to run, runs "/aria-cowork:extract". For passoff (future-you or coworker), use "/aria-cowork:handoff" instead. Triggers — "/aria-cowork:wrapup", "/aria-cowork:wrapup auto", "wrap up", "I am done", "close out", "end session". Auto mode skips per-step gates. (Cowork variant — namespaced-only.)'
argument-hint: '[auto]'
---

# /wrapup — Session Close-Out (cowork variant)

Close out the current session cleanly: review what got done, update project tracking files, emit a commit message for you to run, capture session knowledge, and confirm everything is documented. This is the "I'm done" skill — no next-session opener is produced. For passoff (future-you in a new session, or a coworker), use `/aria-cowork:handoff` instead.

**Two modes:**

- **Default (`/wrapup`)** — Per-step gated review. Each tracked surface (session summary, PROGRESS, CLAUDE.md, memory, /extract prompt) prompts for explicit confirmation before writing. The commit-message step is informational only (always emits a copy-paste block — never runs git).
- **`auto` (`/wrapup auto`)** — Implicit-yes on all gates. Run silently. Apply all drafts and chain `/aria-cowork:extract` without confirmation. The commit-message copy-paste block still emits (Cowork has no shell access to commit directly). Emit final report only. Use when the session is short and unambiguous, or when you've already authorized a combined-go (`yes to all`, `yes to all with extract`).

**Cowork variant of aria-knowledge's `/wrapup`.** Behavior is byte-aligned where Cowork's runtime permits; three divergences:

- **Git commit step generates a copy-paste message instead of running git directly** (Q-4 Option B — Cowork has no shell access for `git status` / `git commit`).
- **Memory file updates limited to files in the attached knowledge folder.** aria-knowledge reads `~/.claude/projects/.../memory/`; Cowork's persistent-grant model can't reach that path.
- **Tracked artifacts check (CODEMAP/STITCH staleness) skipped per ADR-005.** aria-knowledge runs this in its Step 7; cowork omits.

Schema-identical outputs (PROGRESS.md entries, CLAUDE.md edits, commit message format) — only invocation and discovery paths differ.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Cowork variant — namespaced-only. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/wrapup` resolves to aria-knowledge's variant — Code is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. To reach this skill, use the namespaced form: `/aria-cowork:wrapup`. Do NOT match bare `/wrapup` — that belongs to aria-knowledge.

**Before Step 0:** Check whether the `Bash` tool is available in this session. If `Bash` IS available (you are running in Claude Code or another runtime with shell access), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-cowork's `/wrapup` from a runtime with shell access.**
>
> This variant emits a copy-paste commit message because Cowork has no shell access — but you appear to be in Claude Code, where `git status` / `git commit` would work directly. For the runtime-appropriate variant that runs git directly, use `/wrapup` (the aria-knowledge canonical).
>
> **Use `/wrapup` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `wrapup` (the bare-slash canonical, which routes to aria-knowledge when both ports are loaded) with the same arguments the user provided to this invocation. Do not proceed with this skill's steps; the aria-knowledge variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-cowork) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args.

If `Bash` is NOT available (normal Cowork runtime), proceed to Step 0.

## Step 0: Resolve config and parse mode

The default knowledge folder is `~/Projects/knowledge/` (expand `~` to your home directory's absolute path). Read `<knowledge_folder>/aria-config.md` and extract `knowledge_folder`. If `aria-config.md` doesn't exist, stop: *"aria-cowork is not configured. Run `/aria-setup` to get started."*

Parse the argument:
- No arg, or arg is empty → `mode = gated` (default)
- Arg matches `auto` (case-insensitive) → `mode = auto`
- Any other arg → stop: *"Unknown argument '{arg}'. Use `/wrapup` or `/wrapup auto`."*

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

**If `mode = auto`:** skip the prompt and proceed with the drafted summary as-is.

**Otherwise (gated mode):** Ask: *"Does this summary look right? (yes / edit)"*

If the user wants to edit, incorporate their corrections before proceeding.

## Step 3: Update PROGRESS.md

If a PROGRESS.md exists for this project:

1. Read the current PROGRESS.md
2. Check if a session entry already exists for today's work (the user or a previous `/wrapup` may have already added one)
3. If no entry exists, draft a new session entry using the project's existing format (match the heading style, content structure, and level of detail of previous entries)
4. Show the draft to the user

**If `mode = auto`:** append the drafted entry without prompting (equivalent to **yes**).

**Otherwise (gated mode):** Ask: *"Add this session entry to PROGRESS.md? (yes / edit / skip)"*

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

**If `mode = auto`:** apply the drafted CLAUDE.md updates without prompting (equivalent to **yes**). If the relevant CLAUDE.md is unreachable, emit the copy-paste block per the Cowork-specific note below — auto mode does not change reachability constraints. If no updates are needed, note that in the final report and move on.

**Otherwise (gated mode):** Ask: *"Update CLAUDE.md with these changes? (yes / edit / skip)"*

If no updates are needed, say so and move on. Don't force updates for the sake of updating.

**Cowork-specific note:** if the relevant CLAUDE.md lives in a repo Cowork can't reach (e.g., a private repo not attached to this session), generate the proposed edits as a copy-paste block for the user to apply themselves — same shape as Step 6's commit-message handling.

## Step 5: Update memory

Check if project memory files in the **reachable knowledge folder** need updating:

1. Read the relevant `project_*.md` memory file(s) under `<knowledge_folder>/`
2. Compare against the session summary — is the memory's *"Current State"* still accurate?
3. If the memory is stale, draft an update

**If `mode = auto`:** apply the drafted memory update without prompting (equivalent to **yes**). If no memory file exists in the reachable knowledge folder or no update is needed, note that in the final report and move on.

**Otherwise (gated mode):** Ask: *"Update project memory? (yes / edit / skip)"*

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

## Step 7: Verify wrapup readiness

Run through a checklist and report status:

```
## Wrapup Checklist

- PROGRESS.md — [updated / already current / not found / skipped]
- CLAUDE.md — [current / updated (in-place) / updated (copy-paste emitted) / not found / skipped]
- Memory — [updated / already current / not found (cowork can't reach) / skipped]
- Git — [commit message emitted / no changes / skipped]
- /extract — [run / skipped]
```

**Tracked artifacts check (CODEMAP/STITCH staleness):** SKIPPED in cowork per ADR-005. aria-knowledge runs this check in its Step 7; cowork omits because `/codemap` and `/stitch` are not ported. If you want tracked-artifact staleness reporting, run aria-knowledge's `/wrapup` from Claude Code.

If any item shows a gap (commit-message emitted but not yet run, PROGRESS.md not updated), flag it — but don't block. The user may have good reasons to defer.

## Step 8: Prompt extract

**If `mode = auto`:** ALWAYS invoke the `/aria-cowork:extract` skill. No judgment-skip allowed — even if the session feels short, conversational, or seems to have nothing new to extract, run `/aria-cowork:extract` anyway. The model running this step must not pre-judge whether extraction is worthwhile; `/extract` has its own dedup logic (per its Rules section: "Never ask for confirmation — scan and dump") that correctly handles the "nothing to add" case by reporting `No uncaptured knowledge found`. The wrapup skill must not make that judgment on `/extract`'s behalf. Auto mode's "implicit-yes on all gates" rule converts to **"extract always runs"** here — there is no skip path in auto mode.

**Otherwise (gated mode):** Ask: *"Run `/aria-cowork:extract` to capture session knowledge before ending? (yes / no)"*

- **yes** — invoke the `/aria-cowork:extract` skill. Once the user has said yes, the same "always run" rule applies — do not subsequently skip based on session-content judgment. /extract handles its own dedup; the user authorized the run.
- **no** — skip

## Step 9: Report

Output a brief closing summary:

```
## Session Wrapup Complete

[1-2 lines: what was updated]

**Next session pickup:** Read [path to PROGRESS.md or CLAUDE.md]
[If commit message was emitted but not yet run: "Reminder: commit message awaiting your terminal run."]
```

Use the heading **`Session Wrapup Complete`** for `/aria-cowork:wrapup` runs — distinct from `/aria-cowork:handoff`'s **`Session Handoff Complete`** heading. The two skills have distinct intents per the v1.1.0 intent split (wrapup = close-out with no passoff; handoff = passoff package) and their closing-report headings should reflect that.

## Rules

- **Confirm before writing in gated mode** — every file modification (PROGRESS.md, CLAUDE.md, memory) requires explicit user approval; show the proposed change first. In `auto` mode, the explicit user approval comes from the `/wrapup auto` invocation itself (or a combined-go signal like `yes to all`) and per-step prompts are skipped. The commit-message step is always informational (copy-paste block) regardless of mode — Cowork never runs git.
- **Match existing format** — when adding entries to PROGRESS.md, match the heading style, date format, and content structure of existing entries. Don't impose a new format.
- **Don't invent work** — the session summary should reflect what actually happened in the conversation, not what might have happened. If the conversation is short or unclear, say so.
- **Git is user-driven in Cowork** — cowork generates commit messages but never shells `git`. Push is always explicit by the user from their terminal. Never `git add -A` in the suggested commands (avoid capturing sensitive files); stage specific files only.
- **Skip gracefully** — if a file doesn't exist (no PROGRESS.md, no CLAUDE.md, no memory), skip that step and note it. Don't create files that don't already exist as part of the project's conventions.
- **Delegate extraction** — /wrapup prompts for `/aria-cowork:extract` but does not perform extraction itself. The /extract skill has its own deduplication and formatting logic.
- **One passoff per session** — if the user runs /wrapup again in the same session, check what was already done and skip completed steps. Don't duplicate entries.
- **Schema-identical PROGRESS.md output** — cowork's /wrapup writes PROGRESS.md entries in the same format as aria-knowledge's /wrapup. Mixed-source PROGRESS.md files (some entries from cowork, some from aria-knowledge) read uniformly.
- **Use Cowork's native I/O** — never invoke a Filesystem MCP connector (per ADR-003).
