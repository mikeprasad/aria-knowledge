---
description: "View and manage pending backlog items. Use when user says '/backlog', '/backlog insights', '/backlog clear', 'what's pending', 'show backlogs', 'check backlog status'. (Claude Code variant — bare-slash canonical when both ports loaded; see ADR-094.)"
argument-hint: "[insights|decisions|extraction|rules] [clear [type] [date]]"
allowed-tools: Read, Edit, Write, Grep
---

# /backlog — Backlog Viewer & Manager

View pending items across all four backlogs, or manage entries.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/backlog` resolves to this skill — aria-knowledge (Code) is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. The Cowork variant is namespaced-only: `/aria-cowork:backlog`.

**Before Step 0:** Check that the `Bash` tool is available in this session. If `Bash` is NOT available (you are running in Claude Cowork or another non-Code runtime), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/backlog` from a non-Code runtime.**
>
> Behavior is largely the same in both runtimes; for the Cowork-native variant (reads backlogs from the attached knowledge folder rather than `~/.claude/aria-knowledge.local.md`), use `/aria-cowork:backlog`.
>
> **Use `/aria-cowork:backlog` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `aria-cowork:backlog` with the same arguments the user provided to this invocation. Do not proceed with this skill's steps; the cowork variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-knowledge) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args.

If `Bash` is available, proceed to Step 0.

## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md` and extract `knowledge_folder`. If the file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Set backlog paths:
- `{knowledge_folder}/intake/insights-backlog.md`
- `{knowledge_folder}/intake/decisions-backlog.md`
- `{knowledge_folder}/intake/extraction-backlog.md`
- `{knowledge_folder}/intake/rules-backlog.md`

## Step 1: Parse Argument

- **No argument:** go to Step 2 (overview)
- **`insights`**, **`decisions`**, **`extraction`**, or **`rules`:** go to Step 3 (detail view)
- **`clear [type] [date]`:** go to Step 4 (clear entries)

## Step 2: Overview Mode

Read all four backlog files. For each, count the number of `### YYYY-MM-DD` entries after the `---` separator and find the most recent date. **If any backlog file is missing**, show "missing — run /setup to repair" instead of a count for that file.

Output:
```
## Pending Backlogs
- Insights: N entries (latest: YYYY-MM-DD)
- Decisions: N entries (latest: YYYY-MM-DD)
- Extraction: N entries (latest: YYYY-MM-DD)
- Rules: N entries (latest: YYYY-MM-DD)
```

If a backlog has no entries (or contains only placeholder text like "(No pending insights)" or "(No pending rules)"), show 0 entries.

## Step 3: Detail View

Read the requested backlog file. Output all entries after the `---` separator.

If no entries: "No pending [type] items."

## Step 4: Clear Entries

**Arguments:** `clear [type] [date]`
- `type`: `insights`, `decisions`, `extraction`, or `rules`
- `date`: YYYY-MM-DD — remove entries on or before this date

**Validate the date argument before proceeding:**
- Must match `YYYY-MM-DD` format. If not: "Invalid date format. Use YYYY-MM-DD (e.g., 2025-03-15)."
- Must not be in the future. If it is: "Cannot clear future-dated entries. Today is [today's date]. Did you mean [suggestion]?"
- If more than 30 entries would be cleared, add a warning: "This will clear N entries — that's a large batch. Are you sure?"

Before clearing, show what will be archived:
> "This will archive N entries from [type]-backlog.md dated on or before [date]:
> - [date] — [brief context from each entry]
>
> Entries move to `{knowledge_folder}/archive/backlog-cleared-{type}-{YYYY-MM-DD-HHmmss}.md`. Proceed? (y/n)"

If user confirms, apply the **archive-then-remove pattern** (v2.15.2+):
1. Create `{knowledge_folder}/archive/` if it doesn't exist.
2. Write archive file at `{knowledge_folder}/archive/backlog-cleared-{type}-{YYYY-MM-DD-HHmmss}.md` with this shape:

   ```markdown
   ---
   archived_at: YYYY-MM-DDTHH:MM:SS
   source_backlog: intake/{type}-backlog.md
   cleared_through_date: YYYY-MM-DD
   entry_count: N
   reason: /backlog clear user-invoked
   ---

   # Archived {type} backlog entries — cleared {YYYY-MM-DD}

   The following N entries were cleared from `intake/{type}-backlog.md` on {YYYY-MM-DDTHH:MM:SS} via `/backlog clear {type} {date}`. They are preserved here for recovery if needed.

   ---

   ### YYYY-MM-DD — [entry 1 title]
   [full body of entry 1]

   ### YYYY-MM-DD — [entry 2 title]
   [full body of entry 2]

   ...
   ```

   Copy the full body of each matching `### YYYY-MM-DD` entry (from the entry header down to the next `###` heading or end of file) into the archive file.

3. After the archive is written, remove the matching entries from `intake/{type}-backlog.md`. If all entries are removed, replace with the placeholder text (e.g., "(No pending insights)").

4. Report: "Archived N entries to `archive/backlog-cleared-{type}-{YYYY-MM-DD-HHmmss}.md`. Source backlog updated."

**Never delete (v2.15.2+):** Backlog entries are NEVER `rm`'d during clear. The archive-then-remove pattern moves user-authored content to the archive surface (full body preserved, not just a ledger) before removing from the live backlog. Rule 6 ("Don't delete — archive") is preserved on-disk, no git history dependency.

**User override (explicit, v2.15.2+):** If the user explicitly approves or asks for a bare deletion that skips the archive (phrases like *"delete without archiving"*, *"really delete these entries"*, *"don't archive this clear"*), the destructive operation is permitted. The default safety floor remains archive-then-remove; this override exists for cases where the user has explicit reason to skip preservation (e.g., backlog entries contain sensitive content they want untraceable, or they're clearing test/spam entries that don't deserve archive space). **Before honoring an override, surface the entry count + the date range that would have been archived** and confirm. User-approved bare deletes are one-off — a subsequent `/backlog clear` invocation defaults back to archive-then-remove.

If user declines: "No entries cleared."
