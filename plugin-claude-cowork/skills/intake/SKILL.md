---
name: intake
description: 'Bulk import knowledge from files, directories, URLs, or pasted content into the intake backlogs, OR capture a single doc with structured 5-section template (doc mode). Use when user says "/aria-cowork:intake", "/aria-cowork:intake doc", "intake from", "import knowledge from", "scan this file for knowledge", "extract from these docs", "onboard this. (Claude Cowork variant. Namespaced-only — bare /intake belongs to aria-knowledge per ADR-094.)'
argument-hint: '[doc <url-or-title>] | <path|directory|glob|url> [path2] [path3]'
---

# /intake — Bulk Knowledge Import + Doc-Anchored Capture

Two modes:

- **Bulk mode (default)** — Scan files, directories, or URLs for knowledge-worthy content and stage findings to the existing backlogs (insights / decisions / extraction). Multi-source, category-based, dedup-aware. Same surface as prior /intake versions.
- **Doc mode (`/intake doc`)** — Capture a single doc as a structured intake entry at `intake/docs/{YYYY-MM-DD}-{slug}.md` with a 5-section body: what the doc claims / worth keeping / contested or unclear / action implied / my reaction. For when you're reading something and want a thoughtful capture rather than a bulk scan.

Doc mode shipped in v0.3.0 (parity with aria-knowledge v2.17.0 — same `intake-doc.md` template, same `intake/docs/` subfolder convention, same body structure).

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Cowork variant — namespaced-only. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/intake` resolves to aria-knowledge's variant — Code is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. To reach this skill, use the namespaced form: `/aria-cowork:intake`. Do NOT match bare `/intake` — that belongs to aria-knowledge.

**Before Step 0:** Check whether the `Bash` tool is available in this session. If `Bash` IS available (you are running in Claude Code or another runtime with shell access), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-cowork's `/intake` from a runtime with shell access.**
>
> This variant uses persistent-grant attached-folder scans and ~~docs MCPs (typically only in Cowork) — but you appear to be in Claude Code, where local file scans via Bash + WebFetch ARE available and the aria-knowledge canonical uses them directly. For the Code-native variant, use `/intake` (the aria-knowledge canonical).
>
> **Use `/intake` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `intake` (the bare-slash canonical, which routes to aria-knowledge when both ports are loaded) with the same arguments the user provided to this invocation. Do not proceed with this skill's steps; the aria-knowledge variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-cowork) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args.

If `Bash` is NOT available (normal Cowork runtime), proceed to Step 0.

## Step 0: Resolve config + Mode detection

The default knowledge folder is `~/Projects/knowledge/` (expand `~` to your home directory's absolute path). Read `<knowledge_folder>/aria-config.md` and extract `knowledge_folder`. If `aria-config.md` doesn't exist, stop: *"aria-cowork is not configured. Run `/aria-setup` to get started."*

Use `<knowledge_folder>` for all file operations during this session. The absolute `knowledge_folder` from config is for reference (so aria-knowledge in Code reaches the same folder); during a Cowork session, the sandbox path resolves to the same files.

**Mode detection:** If the first argument matches `doc` (case-insensitive), this is a doc-mode capture. Set `mode = doc`; the remaining arguments (if any) are the source URL, file path, or title. Jump to "Doc Mode Steps" below. Otherwise set `mode = bulk` and proceed to Step 1.

---

## Doc Mode Steps (mode = doc only)

Doc mode runs steps D1 → D6 to completion and exits. **Do not** run any bulk-mode step (Step 1 onward) in doc mode.

### Step D1: Acquire doc source

The source can be a URL, file path, or just a title (when capturing notes on a doc you read elsewhere).

- **If args after `doc` contain a URL:** use as `source_url`; attempt WebFetch in D2 to extract title/author/content.
- **If args after `doc` contain a file path:** use as `source_path`; Read in D2.
- **If args after `doc` are plain text (no URL/path detected):** treat as `source_title`; no content fetch — user fills body manually in D3.
- **If no args after `doc`:** prompt: *"What doc are you capturing? Paste a URL, file path, or title."*

### Step D2: Read or note doc content

- **URL source:** WebFetch the URL. Extract title, author (if discoverable from byline/meta), and key content. Respect copyright — capture summary and key claims for downstream synthesis, not full page text.
- **File path source:** Read the file. If very large (>500 lines), use the same chunked-scan strategy as bulk mode (first 100, last 50, section headers, then targeted areas).
- **Title-only source:** No content fetch. User will fill body sections manually in D3.

Capture the following for D3:

- `source_title` (from page title, file frontmatter, or user-provided string)
- `source_url` (if URL; else omit)
- `source_author` (if discoverable; else omit per cowork v0.3.0 / aria-knowledge v2.17.0 frontmatter optional-fields rule)
- `captured_at` (current ISO 8601 timestamp)
- `read_at` (defaults to `captured_at` — D4 preview lets user adjust if they read the doc earlier)
- Summarized claims, candidate "worth keeping" items, and any contested or action-implied content noticed during the scan.

### Step D3: Populate template

1. Read `${CLAUDE_PLUGIN_ROOT}/template/intake/intake-doc.md` to load the body template (mirrors aria-knowledge's v2.17.0 template byte-faithfully).
2. Generate slug from `source_title`: lowercase, hyphenated, alphanumeric only, max ~60 chars. Example: *"The Bitter Lesson"* → `the-bitter-lesson`. If `source_title` is empty, use `doc-{HHMMSS}` as fallback.
3. Resolve target path: `<knowledge_folder>/intake/docs/{YYYY-MM-DD}-{slug}.md`. If file already exists at that path, append `-2`, `-3`, etc. to slug until unique.
4. Fill the frontmatter using captured fields from D2. Omit `source_url` if absent; omit `source_author` if absent. Always populate `captured_at`, `read_at`, `type: intake-doc`.
5. Suggest 2-5 tags based on doc topic (cross-check existing `index.md` tags to prefer canonical names; new tags are fine but flag them).
6. Suggest 2-4 `semantic-hints:` free-form phrases that match how a future query might reach this doc (per the convention in `template/README.md`).
7. Pre-fill body sections from the D2 scan:
   - **What the doc claims** — 2-4 sentence summary in your own words
   - **Worth keeping** — bullet list of insights/quotes/data points worth durable storage; aim for 2-6 bullets
   - **Contested or unclear** — populate if the scan surfaced anything debatable; leave empty (or omit the section) if nothing flagged
   - **Action implied** — populate if the doc suggests a decision or next step relevant to ongoing work; omit if N/A
   - **My reaction** — leave as a single-line placeholder (*"{Your reaction — 1-3 sentences. This section is yours, not the doc's.}"*) for the user to fill, since "reaction" is the user's voice not Claude's.

### Step D4: Preview

Show the populated entry before writing. Format:

```
## Doc Intake Preview

**Target:** <knowledge_folder>/intake/docs/{YYYY-MM-DD}-{slug}.md

[full populated entry: frontmatter + body]

---

Save to intake/docs/?
- `yes` — write the file as shown
- `edit {section}` — revise a specific section (claims / keeping / contested / action / reaction / tags / hints / title / slug)
- `skip` — abort, write nothing
```

Wait for explicit response. Allow multiple `edit` directives in sequence (re-show preview after each revision).

### Step D5: Write

On `yes`, write the entry to `<knowledge_folder>/intake/docs/{YYYY-MM-DD}-{slug}.md`. Create the `intake/docs/` subfolder if it doesn't exist (this is the first doc-mode capture).

### Step D6: Report

```
## Doc Intake Complete

- **Source:** {source_title or source_url or "untitled"}
- **Path:** <knowledge_folder>/intake/docs/{YYYY-MM-DD}-{slug}.md
- **Tags:** {tag list}

Entry staged in intake/docs/ for next /aria-cowork:audit-knowledge to review and promote.
```

**Exit after report.** Doc mode runs D1 → D6 only; bulk-mode steps (Step 1 onward) are not executed.

---

## Step 1: Parse sources

The user provides one or more sources as arguments. Each can be:

- **File path** — a single file (e.g., `./docs/architecture.md`)
- **Directory** — scan all `.md` files recursively
- **Glob pattern** — match specific files (e.g., `**/*.md`)
- **URL** — fetch and scan web content
- **Pasted content** — if no path/URL is provided and the user has pasted a long block, treat it as the source

For each source:
1. Verify it exists (for paths) or is reachable (for URLs).
2. Report what was found: *"Found N files to scan"* or *"Fetched URL: [title]"*.
3. If a directory, list the files that will be scanned and ask for confirmation before proceeding (directories could contain hundreds of files).

**Limits:**
- Max 20 files per invocation (suggest splitting larger sets).
- For URLs, fetch and extract content — do NOT copy full page content (respect copyright). Summary + key points only.
- For paths outside the user-attached folder: prompt to confirm read access. (Cowork plugins can only read paths within attached folders.)

If no source is provided: *"What would you like to intake? Provide a file path (within the attached folder), a URL, or paste content directly."*

## Step 2: Read content

For each source file or URL:
1. Read the content.
2. Note the source path/URL for attribution.
3. If the file is very large (>500 lines), scan in chunks — read the first 100 lines, last 50 lines, and any section headers to identify knowledge-dense areas, then read those areas selectively.

For directories, process files in alphabetical order.

For multi-file sources, read all files in a single batch when possible. URLs are fetched individually.

## Step 3: Scan for knowledge

Review each source for the same five categories `/extract` will use (when shipped in v0.2.0):

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

**Be selective** — not every paragraph is knowledge. Focus on patterns, decisions, constraints, and non-obvious information. Skip boilerplate, auto-generated content, and implementation details that are better found by reading the code directly.

## Step 4: Deduplicate

Read the three backlog files in `<knowledge_folder>/intake/`:
- `insights-backlog.md`
- `decisions-backlog.md`
- `extraction-backlog.md`

For each finding, check against:
1. Existing entries in the three backlogs.
2. Existing knowledge files in `<knowledge_folder>/{approaches,decisions,guides,references}/`.

**Skip anything already captured.** Note skipped items in the preview.

## Step 5: Preview findings

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

## Step 6: Stage approved items

Based on user response:
- **"all"** — append everything to the appropriate backlogs.
- **Numbers to exclude** (e.g., "exclude 3, 7") — stage everything except the specified items.
- **"none"** — abort, stage nothing.

Route each approved item to the appropriate backlog using the `/extract` format (when v0.2.0 ships, formats stay aligned):

### Insights → `<knowledge_folder>/intake/insights-backlog.md`
```markdown
### YYYY-MM-DD — [project or "intake"] — Imported from [source]
- Insight bullet 1
- Insight bullet 2
```

### Decisions → `<knowledge_folder>/intake/decisions-backlog.md`
```markdown
### YYYY-MM-DD — [project or "intake"] — Imported from [source]
**Decision:** What was decided
**Why:** Rationale (if documented)
**Alternatives considered:** (if documented, otherwise omit)
```

### Feedback / Project / References → `<knowledge_folder>/intake/extraction-backlog.md`
```markdown
### YYYY-MM-DD — [type: feedback|project|reference] — Imported from [source]
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

Knowledge staged in backlogs for next /audit-knowledge to review and promote (v0.2.0).
```

## Rules

- **Always preview before staging** — unlike `/extract` (v0.2.0), intake operates on content the user may not have reviewed.
- **Attribute sources** — every staged item includes the source file path or URL.
- **Respect copyright** — for URLs, summaries and key points only. The URL itself is the reference.
- **Don't over-extract** — a 500-line architecture doc might yield 3-5 knowledge items, not 50.
- **Project attribution** — if the source path indicates a project, tag the entries with that project tag. Otherwise use "intake" or "cross".
- **Large directories need confirmation** — if a directory scan finds >10 files, list them and ask before proceeding.
- **One intake, one scope** — don't mix sources from different projects in a single intake.
- **Use Cowork's native I/O** — never invoke a Filesystem MCP connector (per ADR-003).
