---
description: "Bulk import knowledge from files, directories, or URLs into the intake backlogs, OR capture a single doc with structured 5-section template (doc mode). Use when user says '/intake', '/intake doc', 'intake from', 'import knowledge from', 'scan this file for knowledge', 'extract from these docs', 'onboard this project', 'capture a doc', 'doc-anchored intake', 'log notes on this doc'. Unlike /extract (current conversation) or /clip (single item), /intake scans external sources in bulk and previews findings before staging. Doc mode produces one structured entry under intake/docs/ with claims / worth-keeping / contested / action / reaction sections."
argument-hint: "[doc <url-or-title>] | <path|directory|glob|url> [path2] [path3]"
allowed-tools: Read, Glob, Grep, Write, Edit, WebFetch, Bash
---

# /intake — Bulk Knowledge Import + Doc-Anchored Capture

Two modes:

- **Bulk mode (default)** — Scan files, directories, or URLs for knowledge-worthy content and stage findings to the existing backlogs (insights / decisions / extraction). Multi-source, category-based, dedup-aware. Same surface as prior /intake versions.
- **Doc mode (`/intake doc`)** — Capture a single doc as a structured intake entry at `intake/docs/{YYYY-MM-DD}-{slug}.md` with a 5-section body: what the doc claims / worth keeping / contested or unclear / action implied / my reaction. For when you're reading something and want a thoughtful capture rather than a bulk scan.

## Step 0: Resolve Config + Mode Detection

Read `~/.claude/aria-knowledge.local.md` and extract `knowledge_folder`. If the file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Use `{knowledge_folder}` as the base path for all file operations in subsequent steps.

**Mode detection:** If the first argument matches `doc` (case-insensitive), this is a doc-mode capture. Set `mode = doc`; the remaining arguments (if any) are the source URL, file path, or title. Jump to "Doc Mode Steps" below. Otherwise set `mode = bulk` and proceed to Step 1.

---

## Doc Mode Steps (mode = doc only)

Doc mode runs steps D1 → D6 to completion and exits. **Do not** run any bulk-mode step (Step 1 onward) in doc mode.

### Step D1: Acquire Doc Source

The source can be a URL, file path, or just a title (when capturing notes on a doc you read elsewhere).

- **If args after `doc` contain a URL:** use as `source_url`; attempt WebFetch in D2 to extract title/author/content
- **If args after `doc` contain a file path:** use as `source_path`; Read in D2
- **If args after `doc` are plain text (no URL/path detected):** treat as `source_title`; no content fetch — user fills body manually in D3
- **If no args after `doc`:** prompt: "What doc are you capturing? Paste a URL, file path, or title."

### Step D2: Read or Note Doc Content

- **URL source:** WebFetch the URL. Extract title, author (if discoverable from byline/meta), and key content. Respect copyright — capture summary and key claims for downstream synthesis, not full page text.
- **File path source:** Read the file. If very large (>500 lines), use the same chunked-scan strategy as bulk mode (first 100, last 50, section headers, then targeted areas).
- **Title-only source:** No content fetch. User will fill body sections manually in D3.

Capture the following for D3:
- `source_title` (from page title, file frontmatter, or user-provided string)
- `source_url` (if URL; else omit)
- `source_author` (if discoverable; else omit per #28a-5)
- `captured_at` (current ISO 8601 timestamp)
- `read_at` (defaults to `captured_at` — D4 preview lets user adjust if they read the doc earlier)
- Summarized claims, candidate "worth keeping" items, and any contested or action-implied content noticed during the scan

### Step D3: Populate Template

1. Read `${CLAUDE_PLUGIN_ROOT}/template/intake/intake-doc.md` to load the body template.
2. Generate slug from `source_title`: lowercase, hyphenated, alphanumeric only, max ~60 chars. Example: `"The Bitter Lesson"` → `the-bitter-lesson`. If `source_title` is empty, use `doc-{HHMMSS}` as fallback.
3. Resolve target path: `{knowledge_folder}/intake/docs/{YYYY-MM-DD}-{slug}.md`. If file already exists at that path, append `-2`, `-3`, etc. to slug until unique.
4. Fill the frontmatter using captured fields from D2. Omit `source_url` if absent; omit `source_author` if absent. Always populate `captured_at`, `read_at`, `type: intake-doc`.
5. Suggest 2-5 tags based on doc topic (cross-check existing `index.md` tags to prefer canonical names; new tags are fine but flag them).
6. Suggest 2-4 `semantic-hints:` free-form phrases that match how a future query might reach this doc (per the convention in `template/README.md`).
7. Pre-fill body sections from the D2 scan:
   - **What the doc claims** — 2-4 sentence summary in your own words
   - **Worth keeping** — bullet list of insights/quotes/data points worth durable storage; aim for 2-6 bullets
   - **Contested or unclear** — populate if the scan surfaced anything debatable; leave empty (or omit the section) if nothing flagged
   - **Action implied** — populate if the doc suggests a decision or next step relevant to ongoing work; omit if N/A
   - **My reaction** — leave as a single-line placeholder (`{Your reaction — 1-3 sentences. This section is yours, not the doc's.}`) for the user to fill, since "reaction" is the user's voice not Claude's

### Step D4: Preview

Show the populated entry before writing. Format:

```
## Doc Intake Preview

**Target:** {knowledge_folder}/intake/docs/{YYYY-MM-DD}-{slug}.md

[full populated entry: frontmatter + body]

---

Save to intake/docs/?
- `yes` — write the file as shown
- `edit {section}` — revise a specific section (claims / keeping / contested / action / reaction / tags / hints / title / slug)
- `skip` — abort, write nothing
```

Wait for explicit response. Allow multiple `edit` directives in sequence (re-show preview after each revision).

### Step D5: Write

On `yes`, write the entry to `{knowledge_folder}/intake/docs/{YYYY-MM-DD}-{slug}.md`. Create the `intake/docs/` subfolder if it doesn't exist (this is the first doc-mode capture).

### Step D6: Report

```
## Doc Intake Complete

- **Source:** {source_title or source_url or "untitled"}
- **Path:** {knowledge_folder}/intake/docs/{YYYY-MM-DD}-{slug}.md
- **Tags:** {tag list}

Entry staged in intake/docs/ for next /audit-knowledge to review and promote.
```

**Exit after report.** Doc mode runs D1 → D6 only; bulk-mode steps (Step 1 onward) are not executed.

---

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

- **Always preview before staging** — unlike `/extract`, intake operates on content the user may not have reviewed. Show findings first. Applies to both bulk mode (Step 5 preview) and doc mode (Step D4 preview).
- **Attribute sources** — every staged item includes the source file path or URL so the audit process knows where it came from. Bulk mode adds source attribution per finding; doc mode captures `source_url`, `source_title`, `source_author` (when known) in frontmatter.
- **Respect copyright** — for URLs, capture summaries and key points, never full page content. The URL itself is the reference. Applies to both modes — doc mode's "What the doc claims" should be in your own words, not a verbatim excerpt.
- **Don't over-extract** — a 500-line architecture doc might yield 3-5 knowledge items, not 50. Extract the patterns and decisions, not every detail. In doc mode, "worth keeping" usually has 2-6 bullets, not 20.
- **Project attribution** — if the source path indicates a project (e.g., `ss/`, `cs/`, `df/`), tag the entries with that project. Otherwise use "intake" or "cross". Same rule for both modes.
- **Large directories need confirmation** — if a directory scan finds >10 files, list them and ask before proceeding. The user may want to narrow the scope. Bulk-mode only — doc mode is always single-source.
- **One intake, one scope** — don't mix sources from different projects in a single intake. If the user provides paths from multiple projects, process each project's sources as a separate group with its own attribution. Doc mode is inherently single-source so this rule applies only to bulk mode.
- **Doc mode: reaction is the user's voice** — pre-fill "What the doc claims" / "Worth keeping" / "Contested" / "Action" from your D2 scan. Leave "My reaction" as a single-line placeholder for the user to fill. Don't fabricate an opinion you don't actually hold.
- **Doc mode: lazy subfolder creation** — `intake/docs/` is created on first doc-mode capture, not bootstrapped on /setup. Doesn't exist until needed.
- **Doc mode: slug collisions** — if `{date}-{slug}.md` already exists, append `-2`, `-3`, etc. Don't overwrite. The audit process will dedup if the captures are about the same doc.
- **Doc mode: title-only captures are valid** — if the user doesn't have a URL or file, just a title, accept that. The 5-section body still has value as structured notes-while-reading.
