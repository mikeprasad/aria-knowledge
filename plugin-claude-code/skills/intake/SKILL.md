---
description: "Capture knowledge from outside the conversation. A single URL or text snippet is clipped whole to intake/clippings/; files/directories/globs are bulk-scanned into the backlogs; `extract <source>` decomposes a source into backlog entries; `doc <source>` captures a structured 5-section reflection (claims/worth-keeping/contested/action/reaction); `thread <id>` pulls a chat/email thread via MCP. Use when user says '/intake', 'intake from', 'import knowledge from', 'scan this file for knowledge', 'onboard this project', 'clip this', 'save this link', 'save this snippet', 'capture this URL', 'clip this thread', 'save this Slack thread', 'capture this email chain', 'extract insights from this doc', 'mine this Notion page', 'capture a doc', 'log notes on this doc'. Unlike /extract (current conversation), /intake captures external sources; clipped/bulk items are reviewed at the next /audit-knowledge run. (Code port — ADR-094.)"
argument-hint: "[extract|doc|thread] <url|text|path|glob|id> [tags]"
allowed-tools: Read, Glob, Grep, Write, Edit, WebFetch, Bash
---

# /intake — Bulk Knowledge Import + Doc-Anchored Capture

Two modes:

- **Bulk mode (default)** — Scan files, directories, or URLs for knowledge-worthy content and stage findings to the existing backlogs (insights / decisions / extraction). Multi-source, category-based, dedup-aware. Same surface as prior /intake versions.
- **Doc mode (`/intake doc`)** — Capture a single doc as a structured intake entry at `intake/docs/{YYYY-MM-DD}-{slug}.md` with a 5-section body: what the doc claims / worth keeping / contested or unclear / action implied / my reaction. For when you're reading something and want a thoughtful capture rather than a bulk scan.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/intake` resolves to this skill — aria-knowledge (Code) is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. The Cowork variant is namespaced-only: `/aria-cowork:intake`.

**Before Step 0:** Check that the `Bash` tool is available in this session. If `Bash` is NOT available (you are running in Claude Cowork or another non-Code runtime), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/intake` from a non-Code runtime.**
>
> This variant scans local files/directories/globs via Bash + WebFetch, which Cowork can't access the same way. For the Cowork-native variant (file scan reads from attached folder; doc mode uses ~~docs MCPs; supports pasted content), use `/aria-cowork:intake`.
>
> **Use `/aria-cowork:intake` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `aria-cowork:intake` with the same arguments the user provided to this invocation. Do not proceed with this skill's steps; the cowork variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-knowledge) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args.

If `Bash` is available, proceed to Step 0.

## Step 0: Resolve Config + Mode Detection

Read `~/.claude/aria-knowledge.local.md` and extract `knowledge_folder`. If the file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Use `{knowledge_folder}` as the base path for all file operations in subsequent steps.

**Mode detection (first match wins):**

1. First arg `== extract` (case-insensitive) → `mode = extract`. The remaining arg is ONE source (URL / file / dir / doc-URL); decompose it into backlog entries by running the bulk-scan logic (Step 1 onward) on that single source. `extract` is **standalone** — it does NOT combine with `doc`/`thread` (no `/intake extract doc …`); a doc to decompose is just `/intake extract <doc-url>` (extract fetches it). If the arg after `extract` is literally `doc` or `thread`, treat as malformed and prompt for clarification.
2. First arg `== doc` → `mode = doc`. Jump to "Doc Mode Steps" (D1–D6), unchanged.
3. First arg `== thread` → `mode = thread`. Jump to "Thread Mode Steps" (T1–T3) below.
4. *(auto)* Single arg whose host is a chat/email service (`slack.com`, `teams.microsoft.com`, `mail.google.com`, outlook/office) → `mode = thread` (no keyword needed).
5. *(auto)* Single arg matching `^https?://` OR free text (not an existing path) → `mode = clip-whole`. Jump to "Clip-Whole Steps" (C1–C3) below.
6. *(auto)* Args are existing file paths / directories / globs, OR multiple sources → `mode = bulk`. Proceed to Step 1 (bulk scan, unchanged).
7. No args → ask: "What would you like to intake? (a URL, text, file/dir/glob; or `extract <src>` to decompose, `doc <src>` for a reflection capture, `thread <id>` for a chat/email thread)".

The mental model: default = *capture this whole*; `extract` = *decompose it*; `doc` = *reflect on it (5-section)*; `thread` = the one source that needs naming (or auto-detected from a chat URL). **Note (behavior change from prior versions):** a bare URL now CLIPS WHOLE — it no longer auto-mines into backlogs. To mine a single URL, use `/intake extract <url>` (or let `/audit-knowledge` Step 2f decompose the clipping later).

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

## Clip-Whole Steps (mode = clip-whole)

Capture the source **whole** as one clipping for later review at `/audit-knowledge` Step 2f. Runs C1–C3 and exits. (Absorbs the retired `/clip`.)

### C1: Acquire content
- **URL:** WebFetch; extract the page title + a summary (do NOT copy full page content — respect copyright). Capture the URL as `source`.
- **Text snippet:** use the provided text verbatim as the body; title = first line.

### C2: Write the clipping
Resolve target `{knowledge_folder}/intake/clippings/{slug}.md` (slug from title; append `-2`/`-3` until unique). Write:

```
---
source: [URL or "manual"]
date: YYYY-MM-DD
tags: [user-provided tags, or auto-detected from index.md, or empty array]
---

# [Title or first line of text]

[Summary for URLs, full text for snippets]
```

**Tag detection:** if the user didn't provide tags, match title/content words against known tags in `{knowledge_folder}/index.md` (if it exists). Only high-confidence matches — don't guess.

### C3: Confirm
```
Clipped to intake/clippings/{slug}.md
Tags: [tags or "none"]
Reviewed at the next /audit-knowledge run (Step 2f).
```

**Exit after C3.**

---

## Thread Mode Steps (mode = thread)

Pull a chat/email thread via a `~~chat` (Slack/Teams) or `~~email` (Gmail/MS365) MCP into one clipping. Runs T1–T3 and exits. (This mode absorbs the former standalone thread-capture skill, retired v2.33.0.)

### T1: MCP availability check
If no `~~chat`/`~~email` MCP is connected/authenticated, surface:

> "`thread` mode needs a chat or email MCP connected. These are bundled with the plugin — run the MCP's authenticate flow (e.g. Slack auth), or connect it via your MCP config, then retry. (This is NOT Cowork-only — thread mode runs in Claude Code once the MCP is authed.)"

Then exit. **Do NOT redirect to Cowork** — the capability is Code-native once the MCP is authenticated. (The ADR-094 Bash-availability runtime gate is separate and only fires on a genuine runtime mismatch, not on an unauthenticated MCP.)

### T2: Pull the thread
Fetch thread content + metadata (participants, timestamps, channel/subject) via the connected MCP.

### T3: Write the clipping
Write to `{knowledge_folder}/intake/clippings/{slug}.md` with the same frontmatter shape as C2 (`source` = thread URL/id; body = thread metadata + messages). Confirm as in C3.

**Exit after T3.**

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
