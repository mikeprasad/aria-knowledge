---
name: stats
description: >
  Show knowledge base health metrics — file counts, backlog depth, audit status, tag stats, and coverage gaps. Use when user says "/stats", "/aria-cowork:stats", "knowledge stats", "how is my knowledge base", "show stats", "knowledge health", "dashboard".
---

# /stats — Knowledge Base Health

Read-only dashboard showing the current state of the knowledge repository.

## Step 0: Resolve config

The default knowledge folder is `~/Projects/knowledge/` (expand `~` to your home directory's absolute path). Read `<knowledge_folder>/aria-config.md` and extract `knowledge_folder` and `last_setup_date`. If `aria-config.md` doesn't exist, stop: *"aria-cowork is not configured. Run `/aria-setup` to get started."*

Use `<knowledge_folder>` for all file operations during this session.

## Step 1: Count promoted files

Count `.md` files (excluding README.md) in each promoted folder:

- `<knowledge_folder>/rules/*.md`
- `<knowledge_folder>/approaches/*.md`
- `<knowledge_folder>/decisions/*.md`
- `<knowledge_folder>/guides/**/*.md` (recursive — guides may have subdirectories)
- `<knowledge_folder>/references/*.md`
- `<knowledge_folder>/archive/*.md`

Record counts per category and total.

## Step 2: Count backlog items

For each backlog file, count the number of `### ` (h3) entries below the `---` separator:

- `<knowledge_folder>/intake/insights-backlog.md`
- `<knowledge_folder>/intake/decisions-backlog.md`
- `<knowledge_folder>/intake/extraction-backlog.md`
- `<knowledge_folder>/intake/rules-backlog.md`

Also count `.md` files in `<knowledge_folder>/intake/clippings/` (unreviewed clippings).

## Step 3: Read audit dates

Extract the `**Date:**` from:
- `<knowledge_folder>/logs/knowledge-audit-log.md` (created by `/audit-knowledge` in v0.2.0+; may not exist yet in Phase 1)
- `<knowledge_folder>/logs/config-audit-log.md` (same — v0.2.0+)
- `last_setup_date` field from `<knowledge_folder>/aria-config.md`

Calculate days since each. If a date is missing or *"never"*, note *"never"*.

## Step 4: Index health (if index.md exists)

If `<knowledge_folder>/index.md` exists, read it and extract:
- **Known tags count:** count lines in `## Known Tags` section.
- **Top tags:** from `## Tag Index`, count files listed under each `### tag` header, sort by count, show top 5.
- **Stale files:** read `## Stale Files` section, count entries.
- **Untagged files:** read `## Untagged Files` section, count entries.
- **Semantic-hints coverage (added v0.3.0 — parity with aria-knowledge v2.16.0):** count files declaring `semantic-hints:` frontmatter / total promoted files; report as `N of M (P%)`. Always emit (zero coverage = `0 of M (0%)`) to track adoption over time. Source: scan promoted-folder files (same set as Step 1) for the `semantic-hints:` field; matches `/aria-cowork:index`'s Semantic Hints Index input.

If `index.md` doesn't exist, note: *"No index — run `/aria-cowork:index` to build."*

## Step 5: Coverage gaps

Check which promoted folders have zero `.md` files (excluding README.md):
- If `approaches/` is empty: note it.
- If `decisions/` is empty: note it.
- If `guides/` is empty: note it.
- If `references/` is empty: note it.

These suggest areas where knowledge capture hasn't started yet.

## Step 6: Present

**Output policy:** emit every section defined in the format below with all fields, even when counts are zero. Zero counts are meaningful data points — *"Pending insights: 0"* confirms the backlog is clear, *"Stale files: 0"* confirms the index is current. Do not collapse the dashboard into prose or shorten sections for brevity. The Index Health and Coverage Gaps sections have explicit conditional branches embedded in the template; all other sections are always-emit.

```markdown
## Knowledge Stats (aria-cowork view)

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

### Audit Status
- Knowledge audit: [YYYY-MM-DD (N days ago) | never]  *(populated when /audit-knowledge ships in v0.2.0)*
- Config audit: [YYYY-MM-DD (N days ago) | never]  *(populated when /audit-config ships in v0.2.0)*
- Last /aria-setup: YYYY-MM-DD (N days ago)

### Index Health
[If index exists:]
- Known tags: N
- Top tags: tag1 (N files), tag2 (N files), tag3 (N files), tag4 (N files), tag5 (N files)
- Untagged files: N
- Stale files: N
- Semantic-hints coverage: N of M files (P%)
[If no index:]
- No index built yet — run /aria-cowork:index

### Coverage Gaps
[List empty categories, or "All categories have content."]
```

## Phase 1 notes

- **No `/audit-knowledge` or `/audit-config` skills in v0.1.0** — those land in v0.2.0. The "Audit Status" section will show *"never"* until then. That's expected.
- **No `/codemap` integration** — codemap is Code-only per [ADR-005](../../../knowledge/projects/aria-cowork/decisions/005-code-only-skills-excluded.md). The codemap-status section from aria-knowledge's stats is intentionally absent.

## Rules

- **Read-only** — this skill never modifies files.
- **Fast** — just counting and date parsing, no heavy analysis.
- **No recommendations** — just present the data. The user decides what to act on.
- **Use Cowork's native I/O** — never invoke a Filesystem MCP connector (per ADR-003).
