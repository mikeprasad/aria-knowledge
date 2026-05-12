---
description: "View and manage pending backlog items. Use when user says '/backlog', '/backlog insights', '/backlog clear', 'what's pending', 'show backlogs', 'check backlog status'."
argument-hint: "[insights|decisions|extraction|rules] [clear [type] [date]]"
allowed-tools: Read, Edit, Write, Grep
---

# /backlog — Backlog Viewer & Manager

View pending items across all four backlogs, or manage entries.

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

If user declines: "No entries cleared."
