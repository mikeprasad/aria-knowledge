---
description: "Show knowledge base health metrics — file counts, backlog depth, audit status, codemap dates, tag stats, and coverage gaps. Use when user says '/stats', 'knowledge stats', 'how is my knowledge base', 'show stats', 'knowledge health', 'dashboard'."
argument-hint: ""
allowed-tools: Read, Glob, Grep
---

# /stats — Knowledge Base Health

Read-only dashboard showing the current state of the knowledge repository.

## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md` and extract `knowledge_folder`. If the file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Use `{knowledge_folder}` as the base path for all operations.

## Step 1: Count Promoted Files

Count `.md` files (excluding README.md) in each promoted folder:

- `{knowledge_folder}/rules/*.md`
- `{knowledge_folder}/approaches/*.md`
- `{knowledge_folder}/decisions/*.md`
- `{knowledge_folder}/guides/**/*.md` (recursive — guides may have subdirectories)
- `{knowledge_folder}/references/*.md`
- `{knowledge_folder}/archive/*.md`

Record counts per category and total.

## Step 2: Count Backlog Items

For each backlog file, count the number of `### ` (h3) entries below the `---` separator:

- `{knowledge_folder}/intake/insights-backlog.md`
- `{knowledge_folder}/intake/decisions-backlog.md`
- `{knowledge_folder}/intake/extraction-backlog.md`
- `{knowledge_folder}/intake/rules-backlog.md`

Also count `.md` files in `{knowledge_folder}/intake/pre-compact-captures/`.

Also count `.md` files in `{knowledge_folder}/intake/clippings/` (unreviewed clippings).

## Step 3: Read Audit Dates

Extract the `**Date:**` from:
- `{knowledge_folder}/logs/knowledge-audit-log.md`
- `{knowledge_folder}/logs/config-audit-log.md`
- The `/setup on` date from `~/.claude/aria-knowledge.local.md`

Calculate days since each. If a date is "(no audits yet)" or missing, note "never."

## Step 3a: Check Codemap Dates

Use Glob to find CODEMAP.md files under cwd (up to 2 levels deep). Try these patterns:
- `CODEMAP.md` (depth 0)
- `*/CODEMAP.md` (depth 1)
- `*/*/CODEMAP.md` (depth 2)

For each file found:
1. Read the first 10 lines
2. Parse the `Last updated` date from the header. Expected pattern: `> Last updated: YYYY-MM-DD | Sections: N | Features: M`
3. Calculate days-since from today's date

If the header is missing or unparseable, show `(no date)` for that entry.

If no CODEMAP.md files are found under cwd, the section still renders with a single line noting absence.

**Presentation-only.** This step does not classify stale/current or run git-activity checks. Staleness classification with file-change detection belongs to `/audit-knowledge` Step 5d — `/stats` just surfaces the raw date so the user can decide whether to run the audit.

## Step 4: Index Health (if index.md exists)

If `{knowledge_folder}/index.md` exists, read it and extract:
- **Known tags count:** count lines in `## Known Tags` section
- **Top tags:** from `## Tag Index`, count files listed under each `### tag` header, sort by count, show top 5
- **Stale files:** read `## Stale Files` section, count entries
- **Untagged files:** read `## Untagged Files` section, count entries

If `index.md` doesn't exist, note: "No index — run /index to build."

## Step 5: Coverage Gaps

Check which promoted folders have zero `.md` files (excluding README.md):
- If `approaches/` is empty: note it
- If `decisions/` is empty: note it
- If `guides/` is empty: note it
- If `references/` is empty: note it

These suggest areas where knowledge capture hasn't started yet.

## Step 6: Present

Output in this format:

**Output policy:** emit every section defined in the format below with all fields, even when counts are zero. Zero counts are meaningful data points — "Pending insights: 0" confirms the backlog is clear, "Stale files: 0" confirms the index is current. Do not collapse the dashboard into prose or shorten sections for brevity — the structured format is the skill's value, enabling trend comparison across runs. The Index Health and Coverage Gaps sections have explicit conditional branches embedded in the template; all other sections are always-emit.

```
## Knowledge Stats

### Repository
- Promoted files: N total
  - Rules: N
  - Approaches: N
  - Decisions: N
  - Guides: N
  - References: N
- Archived: N

### Intake
- Pending insights: N
- Pending decisions: N
- Pending extractions: N
- Pending rules: N
- Unreviewed clippings: N
- Pre-compact captures: N

### Audit Status
- Knowledge audit: [YYYY-MM-DD (N days ago) | never]
- Config audit: [YYYY-MM-DD (N days ago) | never]
- Last /setup: [YYYY-MM-DD (N days ago)]

### Codemap Status
[If codemaps exist, one line per file:]
- <relative-path>: updated YYYY-MM-DD (N days ago)
[If no codemaps found:]
- No CODEMAP.md found under cwd

### Index Health
[If index exists:]
- Known tags: N
- Top tags: tag1 (N files), tag2 (N files), tag3 (N files), tag4 (N files), tag5 (N files)
- Untagged files: N
- Stale files: N
[If no index:]
- No index built yet — run /index

### Coverage Gaps
[List empty categories, or "All categories have content."]
```

## Rules

- **Read-only** — this skill never modifies files
- **Fast** — just counting and date parsing, no heavy analysis
- **No recommendations** — just present the data. The user decides what to act on.
