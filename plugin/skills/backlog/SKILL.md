---
description: "View and manage pending backlog items. Use when user says '/backlog', '/backlog insights', '/backlog clear', 'what's pending', 'show backlogs', 'check backlog status'."
argument-hint: "[insights|decisions|extraction|rules] [clear [type] [date]]"
allowed-tools: Read, Edit, Grep
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

Before clearing, show what will be removed:
> "This will remove N entries from [type]-backlog.md dated on or before [date]:
> - [date] — [brief context from each entry]
>
> Proceed? (y/n)"

If user confirms: remove the matching `### YYYY-MM-DD` entries and everything below them until the next `###` heading or end of file. If all entries are removed, replace with the placeholder text (e.g., "(No pending insights)").

If user declines: "No entries cleared."
