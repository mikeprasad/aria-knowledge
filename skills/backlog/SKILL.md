---
name: backlog
description: >
  View and manage pending backlog items. Use when user says "/backlog", "/aria-cowork:backlog", "/backlog insights", "/backlog clear", "what's pending", "show backlogs", "check backlog status".
argument-hint: "[insights|decisions|extraction|rules] [clear [type] [date]]"
---

# /backlog — Backlog Viewer & Manager

View pending items across all four backlogs, or manage entries.

## Step 0: Resolve config

The default knowledge folder is `~/Projects/knowledge/` (expand `~` to your home directory's absolute path). Read `<knowledge_folder>/aria-config.md` and extract `knowledge_folder`. If `aria-config.md` doesn't exist, stop: *"aria-cowork is not configured. Run `/aria-setup` to get started."*

Set backlog paths (absolute paths from knowledge_folder):
- `<knowledge_folder>/intake/insights-backlog.md`
- `<knowledge_folder>/intake/decisions-backlog.md`
- `<knowledge_folder>/intake/extraction-backlog.md`
- `<knowledge_folder>/intake/rules-backlog.md`

## Step 1: Parse argument

- **No argument:** go to Step 2 (overview).
- **`insights`**, **`decisions`**, **`extraction`**, or **`rules`:** go to Step 3 (detail view).
- **`clear [type] [date]`:** go to Step 4 (clear entries).

## Step 2: Overview mode

Read all four backlog files. For each, count the number of `### YYYY-MM-DD` entries after the `---` separator and find the most recent date. **If any backlog file is missing**, show *"missing — run `/aria-setup` to repair"* instead of a count for that file.

Output:

```
## Pending Backlogs
- Insights: N entries (latest: YYYY-MM-DD)
- Decisions: N entries (latest: YYYY-MM-DD)
- Extraction: N entries (latest: YYYY-MM-DD)
- Rules: N entries (latest: YYYY-MM-DD)
```

If a backlog has no entries (or contains only placeholder text like *"(No pending insights)"* or *"(No pending rules)"*), show 0 entries.

## Step 3: Detail view

Read the requested backlog file. Output all entries after the `---` separator.

If no entries: *"No pending [type] items."*

## Step 4: Clear entries

**Arguments:** `clear [type] [date]`
- `type`: `insights`, `decisions`, `extraction`, or `rules`
- `date`: YYYY-MM-DD — remove entries on or before this date

**Validate the date argument before proceeding:**
- Must match `YYYY-MM-DD` format. If not: *"Invalid date format. Use YYYY-MM-DD (e.g., 2026-04-30)."*
- Must not be in the future. If it is: *"Cannot clear future-dated entries. Today is [today's date]. Did you mean [suggestion]?"*
- If more than 30 entries would be cleared, add a warning: *"This will clear N entries — that's a large batch. Are you sure?"*

Before clearing, show what will be archived:

> *"This will archive N entries from `[type]-backlog.md` dated on or before [date]:*
> *- [date] — [brief context from each entry]*
>
> *Entries move to `<knowledge_folder>/archive/backlog-cleared-{type}-{YYYY-MM-DD-HHmmss}.md`. Proceed? (y/n)"*

If user confirms, apply the **archive-then-remove pattern** (v0.3.0+ — parity with aria-knowledge v2.15.2):

1. Create `<knowledge_folder>/archive/` if it doesn't exist.
2. Write archive file at `<knowledge_folder>/archive/backlog-cleared-{type}-{YYYY-MM-DD-HHmmss}.md` with this shape:

   ```markdown
   ---
   archived_at: YYYY-MM-DDTHH:MM:SS
   source_backlog: intake/{type}-backlog.md
   cleared_through_date: YYYY-MM-DD
   entry_count: N
   reason: /backlog clear user-invoked
   plugin_version: aria-cowork@0.3.0
   ---

   # Archived {type} backlog entries — cleared {YYYY-MM-DD}

   The following N entries were cleared from `intake/{type}-backlog.md` on {YYYY-MM-DDTHH:MM:SS} via `/aria-cowork:backlog clear {type} {date}`. They are preserved here for recovery if needed.

   ---

   ### YYYY-MM-DD — [entry 1 title]
   [full body of entry 1]

   ### YYYY-MM-DD — [entry 2 title]
   [full body of entry 2]

   ...
   ```

   Copy the full body of each matching `### YYYY-MM-DD` entry (from the entry header down to the next `###` heading or end of file) into the archive file.

3. After the archive is written, remove the matching entries from `intake/{type}-backlog.md`. If all entries are removed, replace with the placeholder text (e.g., *"(No pending insights)"*).

4. Report: *"Archived N entries to `archive/backlog-cleared-{type}-{YYYY-MM-DD-HHmmss}.md`. Source backlog updated."*

**Never delete (v0.3.0+):** Backlog entries are NEVER `rm`'d during clear. The archive-then-remove pattern moves user-authored content to the archive surface (full body preserved, not just a ledger) before removing from the live backlog. The "Don't delete — archive" rule is preserved on-disk, no git history dependency. See `template/archive/README.md` for the cross-plugin archive-cohort conventions.

**User override (explicit, v0.3.0+):** If the user explicitly approves or asks for a bare deletion that skips the archive (phrases like *"delete without archiving"*, *"really delete these entries"*, *"don't archive this clear"*), the destructive operation is permitted. The default safety floor remains archive-then-remove; this override exists for cases where the user has explicit reason to skip preservation (e.g., backlog entries contain sensitive content they want untraceable, or they're clearing test/spam entries that don't deserve archive space). **Before honoring an override, surface the entry count + the date range that would have been archived** and confirm. User-approved bare deletes are one-off — a subsequent `/aria-cowork:backlog clear` invocation defaults back to archive-then-remove.

If user declines: *"No entries cleared."*

## Rules

- **Use Cowork's native I/O** — never invoke a Filesystem MCP connector (per ADR-003).
- **Don't auto-clear** — clearing is destructive; always require explicit user confirmation.
- **Don't delete — archive (v0.3.0+)** — the default disposition for `/backlog clear` is archive-then-remove, never bare delete. The on-disk archive surface is the canonical preservation, not git history. See `template/archive/README.md` for the universal archive-cohort conventions shared with aria-knowledge.
- **User-override is one-off** — explicit bare-delete requests apply per-invocation only and require surface-before-confirm. Subsequent invocations default back to archive-then-remove.
