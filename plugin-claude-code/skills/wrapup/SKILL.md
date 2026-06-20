---
description: "Close out a session cleanly when the work is done — no passoff intended. Reviews session work, updates PROGRESS.md / CLAUDE.md / memory, commits changes, captures session knowledge via /extract, and confirms everything is wrapped up, captured, and documented. Use when the task is complete and nothing needs to carry into a next session — not for passing work off to a future session or coworker. Triggers: '/wrapup', '/wrapup auto', '/wrapup snap', 'wrap up', 'wrap it up', \"I'm done\", 'close out', 'finish session', 'end session', 'saying goodbye'. Auto mode applies implicit-yes on all gates and runs silently. Snap mode runs like auto but archives the transcript via /snapshot for later extraction instead of running /extract now — use when context is high. (Code port — ADR-094.)"
argument-hint: "[auto|snap]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# /wrapup — Session Close-Out

Close out the current session cleanly: review what got done, update project tracking files, commit changes, capture session knowledge, and confirm everything is documented. This is the "I'm done" skill — no next-session opener is produced. For passoff (future-you or a coworker), use `/handoff` instead.

**Three modes:**

- **Default (`/wrapup`)** — Per-step gated review. Each tracked surface (session summary, PROGRESS, CLAUDE.md, memory, commit, /extract prompt) prompts for explicit confirmation before writing.
- **`auto` (`/wrapup auto`)** — Implicit-yes on all gates. Run silently. Apply all drafts and chain `/extract` without confirmation. Emit final report only. Use when the session is short and unambiguous, or when you've already authorized a combined-go (`yes to all`, `yes to all with extract`).
- **`snap` (`/wrapup snap`)** — Like `auto`, but archives the raw transcript via `/snapshot` for later extraction **instead of** running `/extract` now. Use when context is high: you still get the full silent close-out + commit, but defer the expensive, compaction-risky knowledge synthesis to a later session (or the next `/audit-knowledge` digest pass, which reads the snapshot automatically).

**`snap` is `auto` plus one swap.** Everywhere a step below says "If `mode = auto` (or `snap`)", `snap` follows auto's behavior exactly — implicit-yes, silent, apply all drafts, no per-step prompts. The single difference is the capture step (Step 8): `snap` runs `/snapshot` (archive the transcript for later) while `auto` runs `/extract` (synthesize now). Nothing else differs.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/wrapup` resolves to this skill — aria-knowledge (Code) is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. The Cowork variant is namespaced-only: `/aria-cowork:wrapup`.

**Before Step 0:** Check that the `Bash` tool is available in this session. If `Bash` is NOT available (you are running in Claude Cowork or another non-Code runtime), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/wrapup` from a non-Code runtime.**
>
> This variant runs `git status` / `git commit` via Bash, which isn't available here. For the Cowork-native variant (emits a copy-paste commit message instead, skips ADR-005 tracked-artifacts check), use `/aria-cowork:wrapup`.
>
> **Use `/aria-cowork:wrapup` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `aria-cowork:wrapup` with the same arguments the user provided to this invocation. Do not proceed with this skill's steps; the cowork variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-knowledge) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto` or `mode = snap`** per ADR-094 §Part 3. Auto/snap's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — they trust that the user invoked the correct variant, and this gate enforces that precondition. All other auto/snap-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args. (`snap` especially depends on Bash — its `/snapshot` capture step runs `save-transcript.sh` — so the gate is load-bearing for snap.)

If `Bash` is available, proceed to Step 0.

## Step 0: Resolve Config and Parse Mode

Read `~/.claude/aria-knowledge.local.md` and extract `knowledge_folder`. If the file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Parse the argument:
- No arg, or arg is empty → `mode = gated` (default)
- Arg matches `auto` (case-insensitive) → `mode = auto`
- Arg matches `snap` (case-insensitive) → `mode = snap`
- Any other arg → stop: "Unknown argument '{arg}'. Use '/wrapup', '/wrapup auto', or '/wrapup snap'."

Use `{knowledge_folder}` as the base path for all file operations in subsequent steps.

## Step 1: Identify Project Context

Detect the active project by scanning the working directory for project markers:

1. Search upward from cwd for `PROGRESS.md` and `CLAUDE.md` files
2. Also check for `CODEMAP.md` (indicates a mapped codebase)
3. Check for project-level memory files in `~/.claude/projects/` matching the current path

**Multi-project-root disambiguation (required for correct SESSION.md placement):** if the upward search resolves to a *multi-project/workspace root* — e.g. `~/Projects`, or any directory whose `CLAUDE.md` indexes multiple child projects rather than describing one project, and which has no project-specific `PROGRESS.md` — do NOT treat that root as the project (writing `SESSION.md` there would be wrong). Instead infer the active project from **this session's actual work**: the files edited, the repos committed to, or the project the user named. Use that project's own root (its nearest `CLAUDE.md`/`PROGRESS.md`) for every per-project write, especially `SESSION.md`. This mirrors the SessionStart re-entry instruction's "which project" signal. If the session genuinely spans no single project, skip the SESSION.md write (Step 6.5) and note it.

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

**If `mode = auto` (or `snap`):** skip the prompt and proceed with the drafted summary as-is.

**Otherwise (gated mode):** Ask: "Does this summary look right? (yes / edit)"

If the user wants to edit, incorporate their corrections before proceeding.

## Step 3: Update PROGRESS.md

If a PROGRESS.md exists for this project:

1. Read the current PROGRESS.md
2. Check if a session entry already exists for today's work (the user or a previous /wrapup may have already added one)
3. If no entry exists, draft a new session entry using the project's existing format (match the heading style, content structure, and level of detail of previous entries)
4. Show the draft to the user

**If `mode = auto` (or `snap`):** append the drafted entry without prompting (equivalent to **yes**).

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

**If `mode = auto` (or `snap`):** apply the drafted CLAUDE.md updates without prompting (equivalent to **yes**). If no updates are needed, note that in the final report and move on.

**Otherwise (gated mode):** Ask: "Update CLAUDE.md with these changes? (yes / edit / skip)"

If no updates are needed, say so and move on. Don't force updates for the sake of updating.

## Step 5: Update Memory

Check if project memory files (in `~/.claude/projects/` for the current project path) need updating:

1. Read the relevant `project_*.md` memory file(s)
2. Compare against the session summary — is the memory's "Current State" still accurate?
3. If the memory is stale, draft an update

**If `mode = auto` (or `snap`):** apply the drafted memory update without prompting (equivalent to **yes**). If no memory file exists or no update is needed, note that in the final report and move on.

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

**If `mode = auto` (or `snap`):** stage all changes (per-file, not `git add -A` — exclude anything that looks like a secret or unrelated work-in-progress), draft a conventional commit message from the session work, and commit without prompting. Skip the message-confirmation step. Still **local commit only — never push.**

**Otherwise (gated mode):** Ask: "Want to commit these changes? (yes / no / select files)"

- **yes** — stage all changes, draft a conventional commit message based on the session work, show it for confirmation, then commit
- **no** — skip committing
- **select files** — let the user specify which files to stage, then proceed with commit

If no uncommitted changes exist, say "No uncommitted changes" and move on.

**Important:** Do not push to remote. Only commit locally. If the user wants to push, they can do so separately. This applies to both modes.

## Step 6.5: Write SESSION.md (wrapup state)

Skip this step entirely unless `session_state: true` in `~/.claude/aria-knowledge.local.md` (the config you read in Step 0). When enabled:

Write `{project_root}/SESSION.md` (project root from Step 1) as a **wrapup-state** snapshot, following the contract at `aria-atlas/docs/TEMPLATE_SESSION.md`. **Full rewrite** (wrapup is an authoritative close). This is a deliberate exception to the "don't create files" rule — create it if absent.

**Consume on clean close (multi-session ledger):** a `/wrapup` is a clean close, not a handoff — it adds NO `## Prior sessions` entry for the wrapped session itself (there is no next-session prompt to retain). If the existing SESSION.md has a `## Prior sessions` block, source `bin/lib-session-state.sh` and call `kt_ss_ledger_prune "{project_root}"` to drop any entries a resume already marked `consumed`. Unconsumed prior handoffs survive — wrapping up one session never silently discards another's pending pickup.

**Gitignore it, never commit it:** SESSION.md is ephemeral per-session state (atlas reads it from disk; PROGRESS.md is the durable log). If `{project_root}` is a git repo and its `.gitignore` doesn't already ignore `SESSION.md`, append a `SESSION.md` line to `{project_root}/.gitignore`. **Never `git add` SESSION.md** — it is intentionally untracked, so it must not appear in the Step 6 commit.

Header fields:
- `lastEvent: wrapup`
- `at:` current UTC — `date -u +%Y-%m-%dT%H:%M:%SZ`
- `currentFocus:` one line from the Step 2 summary (where the project stands)
- `nextAction:` one line, or `complete` for a clean close with nothing pending
- `branch:` / `headCommit:` from `git -C {project_root} rev-parse --abbrev-ref HEAD` and `git -C {project_root} rev-parse --short HEAD` (omit both if not a git repo)
- `by:` the `author_tag` config value (omit if unset)
- `sessionId:` omit unless known

Body:
- `## Where we left off` — 2-4 sentences from the Step 2 summary
- `## Next session pickup` — 2-4 sentences
- `## Next session prompt` — **leave the fenced block empty** (wrapup carries no opener; that's what distinguishes it from `/handoff`)

**If `mode = auto` (or `snap`):** write without prompting. **Otherwise (gated):** show the drafted file and ask "Write SESSION.md (wrapup state)? (yes / edit / skip)".

## Step 7: Verify Wrapup Readiness

Run through a checklist and report status:

```
## Wrapup Checklist

- [x/!/ ] PROGRESS.md — [updated / already current / not found / skipped]
- [x/!/ ] CLAUDE.md — [current / updated / not found / skipped]
- [x/!/ ] Memory — [updated / already current / not found / skipped]
- [x/!/ ] Git — [committed / no changes / uncommitted changes (user skipped)]
- [x/!/ ] SESSION.md — [written: wrapup / skipped (session_state off) / not applicable]
- [x/!/ ] Tracked artifacts — [all fresh / N stale (consider /codemap update or /stitch verify) / not checked]
```

**Tracked artifacts check (added v2.16.1):** if active project detected (from Step 1's identification), stat `{project_root}/CODEMAP.md` and `{project_root}/STITCH.md` against `codemap_staleness_threshold_days` / `stitch_staleness_threshold_days` from config (defaults 14 / 30). Report status with `x` (fresh), `!` (stale), or blank (not checked). Don't block on staleness — surface for next-session awareness.

If any item shows a gap (uncommitted changes skipped, PROGRESS.md not updated), flag it — but don't block. The user may have good reasons to defer.

## Step 8: Capture Session Knowledge

**If `mode = snap`:** Do NOT run `/extract`. Instead invoke the `/snapshot` skill to archive the raw transcript to `intake/pre-compact-captures/` for later extraction. This is snap mode's defining difference: capture is deferred, not synthesized now. Like auto, this always runs — there is no skip path. The snapshot is the deferred-extraction handoff: a later `/extract`, or the next `/audit-knowledge` digest pass (which reads `intake/pre-compact-captures/` automatically), synthesizes knowledge from it when context isn't a constraint. Use snap when context is high and running `/extract` now would risk compaction mid-synthesis. (`/snapshot` requires Bash, which the Step-0 runtime gate already guaranteed.)

**If `mode = auto`:** ALWAYS invoke the `/extract` skill. No judgment-skip allowed — even if the session feels short, conversational, or seems to have nothing new to extract, run `/extract` anyway. The model running this step must not pre-judge whether extraction is worthwhile; `/extract` has its own dedup logic (per its Rules section: "Never ask for confirmation — scan and dump") that correctly handles the "nothing to add" case by reporting `No uncaptured knowledge found`. The wrapup skill must not make that judgment on `/extract`'s behalf. Auto mode's "implicit-yes on all gates" rule converts to **"extract always runs"** here — there is no skip path in auto mode.

**Otherwise (gated mode):** Ask: "Run /extract to capture session knowledge before ending? (yes / no)"

- **yes** — invoke the /extract skill. Once the user has said yes, the same "always run" rule applies — do not subsequently skip based on session-content judgment. /extract handles its own dedup; the user authorized the run.
- **no** — skip

## Step 9: Report

Output a brief closing summary:

```
## Session Wrapup Complete

[1-2 lines: what was updated]

[If mode = snap: **Knowledge capture:** transcript snapshotted to intake/pre-compact-captures/ for later extraction (run /extract in a fresh session, or let the next /audit-knowledge digest pass synthesize it). /extract was NOT run this session.]

**Next session pickup:** Read [path to PROGRESS.md or CLAUDE.md]
```

Use the heading **`Session Wrapup Complete`** for `/wrapup` runs — distinct from `/handoff`'s **`Session Handoff Complete`** heading. The two skills have distinct intents per the v2.19.0 intent split (wrapup = close-out with no passoff; handoff = passoff package with next-session opener) and their closing-report headings should reflect that.

## Rules

- **Confirm before writing in gated mode** — every file modification (PROGRESS.md, CLAUDE.md, memory, git commit) requires explicit user approval; show the proposed change first. In `auto` mode, the explicit user approval comes from the `/wrapup auto` invocation itself (or a combined-go signal like `yes to all`) and per-step prompts are skipped.
- **Match existing format** — when adding entries to PROGRESS.md, match the heading style, date format, and content structure of existing entries. Don't impose a new format.
- **Don't invent work** — the session summary should reflect what actually happened in the conversation, not what might have happened. If the conversation is short or unclear, say so.
- **Git safety** — never force push, never amend, never push to remote. Local commits only. Stage specific files, not `git add -A` (avoid capturing sensitive files).
- **Skip gracefully** — if a file doesn't exist (no PROGRESS.md, no CLAUDE.md, no memory), skip that step and note it. Don't create files that don't already exist as part of the project's conventions.
- **SESSION.md is the one create-exception.** Unlike PROGRESS.md/CLAUDE.md/memory (skip-gracefully if absent), SESSION.md is *always written* when `session_state` is on — created at the project root if it doesn't exist. It's a new convention that must bootstrap. This is the only file /wrapup creates rather than skips.
- **Delegate extraction** — /wrapup prompts for /extract but does not perform extraction itself. The /extract skill has its own deduplication and formatting logic.
- **`snap` defers, never drops, capture.** In snap mode /wrapup runs `/snapshot` instead of `/extract` — it must always run the snapshot (no skip path, same as auto's "extract always runs" invariant). The raw transcript is preserved so a later /extract or /audit-knowledge digest can synthesize it; snap never means "skip knowledge capture," only "capture cheaply now, synthesize later." snap is otherwise byte-for-byte auto behavior (silent, implicit-yes, local commit only, never push).
- **One passoff per session** — if the user runs /wrapup again in the same session, check what was already done and skip completed steps. Don't duplicate entries.
