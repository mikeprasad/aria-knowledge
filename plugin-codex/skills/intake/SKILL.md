---
description: "Bulk import knowledge from files, directories, or URLs into the intake backlogs. Use when user says '/intake', 'intake from', 'import knowledge from', 'scan this file for knowledge', 'extract from these docs', 'onboard this project'. Unlike /extract (current conversation) or /clip (single item), /intake scans external sources in bulk and previews findings before staging."
argument-hint: "<path|directory|glob|url> [path2] [path3]"
allowed-tools: Read, Glob, Grep, Write, Edit, WebFetch, Bash
---

# /intake — Bulk Knowledge Import

Scan files, directories, or URLs for knowledge-worthy content and stage findings to backlogs after user review.

## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md` and extract `knowledge_folder`. If the file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Use `{knowledge_folder}` as the base path for all file operations in subsequent steps.

## Step 1: Parse Sources

The user provides one or more sources as arguments. Each source can be:

- **File path** — a single file (e.g., `./docs/architecture.md`, `ss/CLAUDE.md`)
- **Directory** — scan all `.md` files recursively (e.g., `./docs/`, `ss/`)
- **Glob pattern** — match specific files (e.g., `ss/**/*.md`, `./notes/*.txt`)
- **URL** — fetch and scan web content (e.g., `https://docs.example.com/api`)

For each source:
1. Verify it exists (for paths) or is reachable (for URLs)
2. Report what was found: "Found N files to scan" or "Fetched URL: [title]"
3. If a directory, list the files that will be scanned and ask for confirmation before proceeding (directories could contain hundreds of files)

**Limits:**
- Max 20 files per invocation (suggest splitting into multiple runs for larger sets)
- For URLs, fetch via WebFetch and extract content — do NOT copy full page content (respect copyright). Extract a summary and key points only.

If no argument is provided, ask: "What would you like to intake? Provide a file path, directory, glob pattern, or URL."

## Step 2: Read Content

For each source file or URL:
1. Read the content
2. Note the source path/URL for attribution
3. If the file is very large (>500 lines), scan in chunks — read the first 100 lines, last 50 lines, and any section headers to identify knowledge-dense areas, then read those areas selectively

For directories, process files in alphabetical order.

For multi-file sources (directory or glob), issue Read calls for all files in a single parallel tool-use block. Content scanning in Step 3 runs in the main thread after reads complete. Exception: URL sources are fetched individually via WebFetch since each request is a network operation.

## Step 3: Scan for Knowledge

Review each source for the same five categories as `/extract`:

### Insights
- Technical observations, patterns, architectural descriptions
- Non-obvious behaviors or gotchas documented in the source
- Lessons learned or retrospective notes

### Decisions
- Architectural or design choices with rationale
- Technology selections, approach decisions
- Constraints or trade-offs documented in the source

### Feedback / Conventions
- Coding conventions, style rules, workflow preferences
- Team agreements or process documentation
- "Do this, not that" patterns

### Project Context
- Status information, roadmaps, milestone descriptions
- Team structure, ownership, dependency maps
- Integration points or external system documentation

### References
- URLs, tools, services, API endpoints mentioned
- External documentation pointers
- Vendor or third-party integration details

**Be selective** — not every paragraph is knowledge. Focus on content that would help future sessions: patterns, decisions, constraints, and non-obvious information. Skip boilerplate, auto-generated content, and implementation details that are better found by reading the code directly.

## Step 4: Deduplicate

Issue Read calls for the three backlog files AND `{knowledge_folder}` scan targets in a single parallel tool-use block. Dedup comparison runs in the main thread after reads complete.

For each finding, check against:
1. Existing entries in `{knowledge_folder}/intake/insights-backlog.md`
2. Existing entries in `{knowledge_folder}/intake/decisions-backlog.md`
3. Existing entries in `{knowledge_folder}/intake/extraction-backlog.md`
4. CLAUDE.md files in the current working directory
5. Existing knowledge files in `{knowledge_folder}/`

**Skip anything already captured.** Note skipped items in the preview.

## Step 5: Preview Findings

Present all findings grouped by category **before staging anything**:

```
## Intake Preview

**Sources scanned:** N files from [path/URL summary]
**Findings:** N items (N insights, N decisions, N feedback, N project, N references)
**Skipped:** N duplicates

### Insights (N)
1. [brief description] — from [source file]
2. [brief description] — from [source file]

### Decisions (N)
1. [brief description] — from [source file]

### Feedback / Conventions (N)
1. [brief description] — from [source file]

### Project Context (N)
1. [brief description] — from [source file]

### References (N)
1. [brief description] — from [source file]

Stage all to backlogs? (all / numbers to exclude / none)
```

## Step 6: Stage Approved Items

Based on user response:
- **"all"** — append everything to the appropriate backlogs
- **Numbers to exclude** (e.g., "exclude 3, 7") — stage everything except the specified items
- **"none"** — abort, stage nothing

Route each approved item to the appropriate backlog file using the same format as `/extract`:

### Insights → `{knowledge_folder}/intake/insights-backlog.md`
```markdown
### YYYY-MM-DD — [project or "intake"] — Imported from [source filename]
- Insight bullet 1
- Insight bullet 2
```

### Decisions → `{knowledge_folder}/intake/decisions-backlog.md`
```markdown
### YYYY-MM-DD — [project or "intake"] — Imported from [source filename]
**Decision:** What was decided
**Why:** Rationale (if documented in source)
**Alternatives considered:** (if documented in source, otherwise omit)
```

### Feedback, Project Context, References → `{knowledge_folder}/intake/extraction-backlog.md`
```markdown
### YYYY-MM-DD — [type: feedback|project|reference] — Imported from [source filename]
**Content:** What was captured
**Source:** [file path or URL]
```

## Step 7: Report

```
## Intake Complete

- **Sources:** N files scanned
- **Insights:** N staged
- **Decisions:** N staged
- **Feedback:** N staged
- **Project context:** N staged
- **References:** N staged
- **Skipped:** N duplicates, N excluded by user

Knowledge staged in backlogs for next /audit-knowledge to review and promote.
```

## Rules

- **Always preview before staging** — unlike `/extract`, intake operates on content the user may not have reviewed. Show findings first.
- **Attribute sources** — every staged item includes the source file path or URL so the audit process knows where it came from.
- **Respect copyright** — for URLs, capture summaries and key points, never full page content. The URL itself is the reference.
- **Don't over-extract** — a 500-line architecture doc might yield 3-5 knowledge items, not 50. Extract the patterns and decisions, not every detail.
- **Project attribution** — if the source path indicates a project (e.g., `ss/`, `cs/`, `df/`), tag the entries with that project. Otherwise use "intake" or "cross".
- **Large directories need confirmation** — if a directory scan finds >10 files, list them and ask before proceeding. The user may want to narrow the scope.
- **One intake, one scope** — don't mix sources from different projects in a single intake. If the user provides paths from multiple projects, process each project's sources as a separate group with its own attribution.
