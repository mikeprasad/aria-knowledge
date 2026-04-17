---
description: "Load relevant knowledge by topic. Queries the tag index and presents matching promoted files for selective loading into context. Use when user says '/context stripe', '/context api pagination', '/context ss', 'load knowledge about...', 'what do we know about...'."
argument-hint: "<tag1> [tag2] [AND tag3]"
allowed-tools: Read, Glob, Grep
---

# /context — On-Demand Knowledge Retrieval

Query the knowledge tag index and load relevant promoted files into the conversation context.

## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md` and extract:
- `knowledge_folder` — required
- `projects_enabled` — default `false`
- `projects_list` — default empty (only relevant if `projects_enabled: true`)

Parse `projects_list` into a tag→path map. The format is comma-separated `tag:path` pairs (e.g., `cs-builder:cs/cs-space-builder,df:df`). Tags are used to identify project-specific files; paths are not used by `/context` (they're for CWD detection in other skills).

If the config file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

## Step 1: Read Index

Read `{knowledge_folder}/index.md`.

If the file doesn't exist, stop: "No knowledge index found. Run `/index` to build it."

Parse the index to extract:
- `## Projects` section — project name/key and their relevant tags
- `## Known Tags` section — the canonical tag list
- `## Tag Index` section — tag → file mappings for known tags
- `## Other Tags` section — tag → file mappings for freeform tags

## Step 2: Parse Query

The user's argument is a space-separated list of tags with optional `AND` keyword.

**Parsing rules:**
- Split on spaces
- If the token `AND` (case-insensitive) appears, use **intersection mode** — a file must have ALL specified tags
- Otherwise, use **union mode** (default) — a file matches if it has ANY of the specified tags
- Remove `AND` tokens from the tag list

Examples:
- `/context stripe` → tags: [`stripe`], mode: OR
- `/context api pagination` → tags: [`api`, `pagination`], mode: OR
- `/context api AND pagination` → tags: [`api`, `pagination`], mode: AND
- `/context ss` → tags: [`ss`], mode: OR (with project expansion)

If no argument provided, stop: "Usage: `/context <tag1> [tag2] [AND tag3]`. Run `/index` to see available tags."

## Step 3: Project Tag Expansion

For each tag in the query, check if it matches a project key in the `## Projects` section (e.g., `ss`, `cs`, `df`, `aria`).

If a tag matches a project:
1. Keep the project tag itself in the search
2. Also add all of that project's "Relevant tags" to the search
3. Notify the user:
   ```
   Expanded `ss` to include: api, django, nextjs, stripe, supabase, database, deployment
   ```

Project expansion only applies in union (OR) mode. In AND mode, project tags are treated as literal tags (a file must be tagged `ss` specifically).

## Step 4: Match Files

File discovery has two sources: the index (cross-project tagged files) and the filesystem (project-specific files under `projects/{tag}/**`). Both contribute to the result set; results are categorized so Step 5 can present them grouped.

### Step 4a: Index-driven matches (cross-project)

Scan the `## Tag Index` and `## Other Tags` sections for entries matching the query tags.

**Exclude files whose path starts with `projects/`** — those are project-tier files, handled by Step 4b. This prevents duplicate listings when a project-tier file is discoverable via both its YAML tag (in the index) and its path (via Glob in Step 4b). Since `/index` (Phase 4+) scans project-tier files and adds them to the Tag Index with path-derived tags, a project file tagged `agentic-ui` would otherwise appear in both Step 4a (via the `agentic-ui` tag match) and Step 4b (via the `projects/{tag}/**` Glob) — the exclusion puts project-tier files under Step 4b's authoritative categorization.

**Union mode (OR):** Collect non-`projects/` files that appear under any of the query tags. Deduplicate — each file appears once even if it matches multiple tags.

**Intersection mode (AND):** Collect non-`projects/` files that appear under ALL of the query tags. A file must be listed under every specified tag.

For each matching file, collect:
- File path (relative to knowledge folder)
- Description (from the index entry)
- All tags the file carries (scan all tag sections for this file path)
- Category: `cross-project`

### Step 4b: Filesystem-driven matches (project tier)

Skip this sub-step entirely if `projects_enabled: false` or `projects_list` is empty.

For each query tag that matches a configured project tag (i.e., is a key in the parsed `projects_list` from Step 0):
1. Glob `{knowledge_folder}/projects/{tag}/**/*.md` to find all project-specific files.
2. Exclude `projects/{tag}/README.md` from the results (it's per-project navigation, not knowledge content).
3. For each file found:
   - Read the YAML frontmatter to extract `tags:` (if present) and the file's first H1 or summary line as description (if `tags:` is missing, treat the file as carrying just the project tag).
   - In **intersection mode (AND)**: only include the file if its tag set contains ALL query tags (the project tag is implicit since the file lives under `projects/{tag}/`).
   - In **union mode (OR)**: include all files found by the Glob (matching the project tag is sufficient).
4. Mark each result with category: `project-specific` and the originating project tag.

**Empty folder handling (Decision #8):** If the Glob returns no files for a configured project tag, record a "no project-specific files yet in `projects/{tag}/`" note. Don't treat this as an error — Step 5 will mention it informationally and continue with cross-project results.

**Deduplication:** Cross-source duplication is prevented by Step 4a's `projects/**` path exclusion — project-tier files are always routed through Step 4b, never through the index-driven Step 4a. Within each sub-step, deduplicate by path as before (a file matching multiple tags in Step 4a, or a file found multiple times within Step 4b's Glob, appears only once).

## Step 5: Present Summary

If matches found, group results by category — **Project-specific first, Cross-project second**. Use a single continuous numbering across both groups so the user can select by number across categories.

```
Found N files matching: [tags] ([OR|AND])

## Project-specific (M files)
1. projects/cs-builder/decisions/004-state-sync.md — State sync between AI and wizard [cs-builder, state-management]
2. projects/cs-builder/patterns/internal-patterns.md — Reusable patterns within cs-builder [cs-builder, patterns]

## Cross-project (K files)
3. approaches/api-pagination.md — Cursor-based pagination patterns [api, pagination, stripe]
4. decisions/003-cursor-vs-offset.md — Why we chose cursor pagination [api, stripe]
5. references/stripe-webhook-patterns.md — Webhook signature verification [stripe, webhooks]

Load which files? (all / numbers / none)
```

**Section omission:** if a section has zero results, omit its heading entirely. If only project-specific results exist, show only the "Project-specific" section. If only cross-project results exist, show only the "Cross-project" section (and you can omit the heading since the categorization is moot — match the original flat presentation in that case).

**Empty project-folder note (Decision #8):** if Step 4b recorded a "no project-specific files yet" note for any configured project tag in the query, append a single line after the result list (before the prompt):

```
(No files yet in projects/cs-builder/ — folder is configured but empty.)
```

Do NOT pad results with empty folder notes for project tags that weren't queried.

**Pending Ideas surfacing:** if the query includes a configured project tag AND `{knowledge_folder}/intake/ideas-backlog.md` exists, scan the file for entries whose header project field matches (or includes) the query's project tag. Present matches as a compact informational section after the file list, before the "Load which files?" prompt.

> **Why project-scoped only:** `/context` loads knowledge for retrieval; ideas are staging for external-tracker routing, not retrieval. Surfacing ideas on topic-only queries (`/context api`, `/context architecture`) would pollute the retrieval intent and blur ARIA's capture-vs-track boundary. Project-tagged queries get ideas as ambient project context; topic-only queries stay clean. See the capture-vs-track architecture in `intake/ideas-backlog.md`.


```
## Pending Ideas for cs-builder (3)
- 2026-04-15 (1 day ago) — feature — /setup diff prompts ahead vs diverged
- 2026-03-22 (25 days ago) — bug — theme tokens missing from blueprint XYZ [STALE — still relevant?]
- 2026-03-12 (35 days ago) — refactor — simplify blueprint merge logic [STALE — still relevant?]
```

Details:
- **Age computation:** `(today - entry date)` in days; show as "(N day ago)" or "(N days ago)".
- **Stale marker:** append ` [STALE — still relevant?]` when age > `KT_IDEAS_STALENESS_DAYS` (default 21). Read the threshold from `~/.claude/aria-knowledge.local.md` via `config.sh` or fall back to 21.
- **Multi-project entries:** if the entry header has comma-separated project tags (e.g., `cs,ss`), include it for each matching project query.
- **Not selectable:** ideas are informational. They do NOT appear in the numbered file list and are not loadable via "all" or numbers. To triage them, use `/audit-knowledge` (structured disposition flow) or edit `intake/ideas-backlog.md` directly.
- **Omission:** if no ideas match, omit the section entirely (do not show an empty "Pending Ideas" heading).
- **Non-project queries:** skip this section entirely when the query is topic-only (e.g., `/context api` or `/context architecture`). Ideas surfacing is project-scoped; cross-project ideas reach the user through `/audit-knowledge`, not `/context`.

Show the file's tags in brackets after the description so the user can see why each file matched.

**If no matches at all:**

```
No files match tag(s): [tags]

Known tags: api, architecture, css, database, ...
Run `/index` to rebuild if you've recently added files.
```

If the query included a project tag and that project's folder was empty, mention it here too:

```
No files match tag(s): [cs-builder]

(projects/cs-builder/ exists but is empty — populate it via /extract or by creating files manually.)
Known tags: api, architecture, ...
```

## Step 6: Load Selected Files

Based on user response:
- **"all"** — read and present the full content of every matched file
- **Numbers (e.g., "1 3" or "1,3")** — read and present only the specified files
- **"none"** — stop, don't load anything

For each selected file:
1. Read `{knowledge_folder}/{file_path}`
2. Present the full file content

After loading, confirm: "Loaded N knowledge files into context."

## Rules

- **Read-only** — this skill never modifies any files
- **Discovery sources:** the index for cross-project files (no file reads at this stage); the filesystem (Glob) for project-tier files under `projects/{tag}/**` when project tags are queried. File contents are only read at load time (Step 6) — except for project-tier files where YAML frontmatter is parsed during discovery to extract tags and descriptions.
- **Promoted files only** — does not search backlogs, intake, rules, or logs
- **No full-text search** — tag-based matching only. If the user needs content search, suggest using Grep directly
- **Present before loading** — always show the summary and let the user choose which files to load
