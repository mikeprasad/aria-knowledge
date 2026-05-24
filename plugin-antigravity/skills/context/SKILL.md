---
description: "Load relevant knowledge by topic. Queries the tag index and presents matching promoted files for selective loading into context. Use when user says '/context stripe', '/context api pagination', '/context ss', 'load knowledge about...', 'what do we know about...'."
---

# /context — On-Demand Knowledge Retrieval

Query the knowledge tag index and load relevant promoted files into the conversation context.

## Runtime Gate (per ADR-094)

**Before Step 0:** Check that `Bash` is available. If `Bash` is NOT available (e.g., Cowork), surface:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/context` from a non-Code runtime.**
>
> Behavior is largely the same in both runtimes; for the Cowork-native variant (reads `index.md` from the attached knowledge folder via persistent grant), use `/aria-cowork:context`.
>
> Proceed with the aria-knowledge variant anyway? (`y` / `n`)

Wait for `y` / `yes`. **Gate applies even in `auto`** (ADR-094 §Part 3). If `Bash` is available, proceed to Step 0.

## Step 0: Resolve Config

Read `~/.gemini/antigravity/aria-knowledge.local.md` and extract:
- `knowledge_folder` — required
- `projects_enabled` — default `false`
- `projects_list` — default empty (only relevant if `projects_enabled: true`)
- `projects_shared_knowledge` — default empty; comma-separated list of project tags enabled for shared knowledge. When non-empty, also surface team-shared files indexed under `## Team-Shared Tag Index`. Tags not in this list are not surfaced even if they appear in the index.

Parse `projects_list` into a tag→path map. The format is comma-separated `tag:path` pairs (e.g., `proj-a:path/to/proj-a,proj-b:proj-b`). Tags are used to identify project-specific files; paths are not used by `/context` (they're for CWD detection in other skills).

If the config file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

## Step 1: Read Index

Read `{knowledge_folder}/index.md`.

If the file doesn't exist, stop: "No knowledge index found. Run `/index` to build it."

Parse the index to extract:
- `## Projects` section — project name/key and their relevant tags
- `## Known Tags` section — the canonical tag list
- `## Tag Index` section — tag → file mappings for known tags
- `## Other Tags` section — tag → file mappings for freeform tags
- `## Team-Shared Tag Index` section — tag → team-shared file mappings (only when `projects_shared_knowledge` is a non-empty list); paths are absolute-from-home (`~/Projects/...`) and entries carry a `[project: ..., scope: ...]` annotation. Section may be absent if no team-shared files exist or the list is empty.

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

## Step 2.5: Resolve Aliases (added 2.16.0)

After parsing the query into tokens (Step 2) but BEFORE project expansion (Step 3), resolve any aliases.

**Source:** the alias map is encoded in `index.md`'s `## Known Tags` section as `[aliases: ...]` annotations on canonical tag entries. Parse that section to build a flat `alias → canonical` map. If no aliases are declared (no `[aliases: ...]` annotations exist), skip this step entirely.

**Resolution:** for each token `t` in the parsed query, look up `t` in the alias→canonical map. If matched, replace `t` with its canonical form. Record the resolution.

**Notification:** for each resolution, emit one line BEFORE the Step 3 "Expanded …" notification:

```
Resolved `rn` → `react-native`
```

**Order matters:** alias resolution runs BEFORE project expansion. If `seer → ss` is an alias and `ss` is a project tag, querying `/context seer` resolves to `ss` first; Step 3 then expands `ss` to its relevant tags.

**Unidirectional:** resolution is alias → canonical only. Querying the canonical does NOT match alias-only declarations (i.e., querying `react-native` won't surface files that only declare alias `rn`).

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

File discovery has three sources: the index `## Tag Index` and `## Other Tags` sections (cross-project tagged files), the filesystem (project-specific files under `projects/{tag}/**`), and the index `## Team-Shared Tag Index` section (team-shared files in code repos under `_project-knowledge/`). All three contribute to the result set; results are categorized so Step 5 can present them grouped.

**Matching rule (extended 2.16.0):** for any source, a query token `t` matches a file `f` if either:
1. `t` equals a tag declared by `f` (existing behavior), OR
2. `t.lower()` (with hyphens stripped) appears as a substring of any phrase in `f`'s `semantic-hints:` frontmatter (also lowercased + hyphen-stripped).

The `## Semantic Hints Index` in `index.md` is the discovery surface for hint matches — Step 4a scans both `## Tag Index` / `## Other Tags` AND `## Semantic Hints Index` for query-token matches. AND/OR mode applies per-token: each token can satisfy independently via tag OR hint.

When a file matches via hint rather than tag, append `[hint: <phrase>]` to the Step 5 result render so the user can see why the file was surfaced.

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

### Step 4c: Index-driven matches (team-shared)

Skip this sub-step entirely if `projects_shared_knowledge` is empty/missing or the index lacks a `## Team-Shared Tag Index` section.

**Per-tag membership filter:** even when the section exists, only surface entries whose `[project: <tag>, ...]` annotation has a `<tag>` that appears in `projects_shared_knowledge` (or is `cross`). This is a defensive guard for the case where `/index` was run while a tag was enabled, the user later disabled that tag via `/setup`, but `/index` hasn't been re-run yet — entries from now-disabled projects shouldn't surface. Cross-cutting items (`project: cross`) always surface as long as `projects_shared_knowledge` is non-empty.

Scan the `## Team-Shared Tag Index` section for entries matching the query tags. The section's entries are tag headers (`### tag`) followed by bulleted file paths in the form:

```
- ~/Projects/<path>/_project-knowledge/2026-04-28-init-foo.md — Description [project: proj-a, scope: repo]
```

**Union mode (OR):** Collect files appearing under any query tag. Deduplicate by path (a file matching multiple tags appears once).

**Intersection mode (AND):** Collect files appearing under ALL query tags.

**Project-tag interaction:** if a query tag matches a configured project tag, also include team-shared files annotated with `project: <that-tag>` (path-derived project tag from `_project-knowledge/` directly under the project root). Cross-cutting items (`project: cross`) match the query tag `cross` AND surface for any project-tag query when the query mode is OR (cross knowledge is relevant to all projects).

For each matching file, collect:
- File path (absolute-from-home, kept as-is from the index)
- Description (from the index entry)
- Tags the file carries (from the index annotation and any other tag sections it appears under)
- Project metadata (`project: <tag>` and `scope: repo|cross` from the index entry's annotation)
- Category: `team-shared`

## Step 5: Present Summary

<!-- shared-block: staleness-marker -->
### About this block

Compute age + render `[STALE — …]` marker. Consumed by Pending Ideas surfacing (later in this Step) and Tracked Artifacts surfacing (also later in this Step, added 2.16.0). Pure state-computation primitive — caller owns layout.

**Inputs (caller provides):**
- `date_source`: literal date `YYYY-MM-DD` OR file mtime (Unix epoch or `YYYY-MM-DD`) — resolved by caller before invocation
- `threshold_days`: integer, resolved from config by caller (e.g., `KT_IDEAS_STALENESS_DAYS`, `KT_CODEMAP_STALENESS_DAYS`, `KT_STITCH_STALENESS_DAYS`). If the config key is missing, caller falls back to its own baked-in default.
- `remediation`: template string interpolated into the stale marker (e.g., `"still relevant?"`, `"run /codemap update"`, `"run /stitch verify {tag}"`). Caller substitutes any `{tag}` placeholder before invocation.

**Outputs:**
- `age_days`: integer = `(today - date_source).days`
- `age_string`: `"(today)"` if `age_days == 0`, `"(yesterday)"` if `age_days == 1`, else `"(N days ago)"` where N = `age_days`
- `is_stale`: bool = `age_days > threshold_days`
- `marker`: `" [STALE — {remediation}]"` if `is_stale` else `""` (empty string)

**Behavior notes:**
- Future dates (clock skew or mis-dated frontmatter) clamp to `(today)` with `is_stale = false`. Never render `"in future"`.
- The block is computed-state only; callers render the surrounding line.
<!-- /shared-block: staleness-marker -->

If matches found, group results by category — **Team-shared first, Project-specific second, Cross-project third**. Use a single continuous numbering across all groups so the user can select by number across categories.

```
Found N files matching: [tags] ([OR|AND])

## Team-shared (T files)
1. ~/Projects/<path>/_project-knowledge/2026-04-28-init-foo.md — Description [project: proj-a, scope: repo, tags: api, pagination]
2. ~/Projects/<path>/_project-knowledge/cross/2026-04-28-init-bar.md — Description [project: cross, scope: cross, tags: api]

## Project-specific (M files)
3. projects/proj-a/decisions/004-state-sync.md — State sync between AI and wizard [proj-a, state-management]
4. projects/proj-a/patterns/internal-patterns.md — Reusable patterns [proj-a, patterns]

## Cross-project (K files)
5. approaches/api-pagination.md — Cursor-based pagination patterns [api, pagination, stripe]
6. decisions/003-cursor-vs-offset.md — Why we chose cursor pagination [api, stripe]
7. references/stripe-webhook-patterns.md — Webhook signature verification [stripe, webhooks]

Load which files? (all / numbers / none)
```

**Section omission:** if a section has zero results, omit its heading entirely. If only one section has results, omit the heading (categorization is moot — match the original flat presentation in that case).

**Empty project-folder note (Decision #8):** if Step 4b recorded a "no project-specific files yet" note for any configured project tag in the query, append a single line after the result list (before the prompt):

```
(No files yet in projects/proj-a/ — folder is configured but empty.)
```

Do NOT pad results with empty folder notes for project tags that weren't queried.

**Tracked Artifacts surfacing (added 2.16.0):** if the query includes a configured project tag, surface CODEMAP and STITCH artifacts for that project as a numbered section in the result list (continuous numbering from above — artifacts are loadable, same as files).

Per-project artifact resolution:

- **CODEMAP path:** `{project_root}/CODEMAP.md` (per `/codemap` skill convention). Resolve `project_root` from `projects_list` parsed in Step 0.
- **STITCH path:** `{project_root}/STITCH.md` by default; override with `projects_groups[<tag>].stitch_path` if set in `~/.gemini/antigravity/aria-knowledge.local.md`. **Skip STITCH entry silently** if the project tag is NOT in `projects_groups` (single-repo project — `/stitch` doesn't apply).
- **If file does not exist:** render `~/Projects/<path>/CODEMAP.md — (not found — run /codemap create) [project: <tag>]`. Same for STITCH with `(not found — run /stitch create <tag>)`.
- **If file exists:** stat for mtime, invoke the **staleness-marker shared block** (defined at the head of Step 5) with:
  - `date_source` = file mtime
  - `threshold_days` = `KT_CODEMAP_STALENESS_DAYS` (default 14) for CODEMAP, or `KT_STITCH_STALENESS_DAYS` (default 30) for STITCH. Both read from `~/.gemini/antigravity/aria-knowledge.local.md` via `config.sh`. Asymmetric defaults: CODEMAP changes with feature churn (faster decay); STITCH with cross-repo contract changes (slower).
  - `remediation` = `"run /codemap update"` for CODEMAP, or `"run /stitch verify {tag}"` for STITCH (substitute `{tag}` with the project tag at invocation time).
  - Render: `N. ~/Projects/<path>/CODEMAP.md — {age_string} — fresh{marker} [project: <tag>]` (the literal word `fresh` appears only when `marker` is empty; when stale, the marker replaces "fresh").

**Multi-project queries:** one combined "Tracked artifacts" section; each row carries the `[project: <tag>]` annotation so per-project attribution is visible.

**Skip this section entirely** on topic-only queries (no configured project tag in resolved query). Mirrors the Pending Ideas project-scope-only constraint — topic queries stay clean.

Example render:
```
## Tracked artifacts (3)
8. ~/Projects/cs/CODEMAP.md — 8 days ago — fresh [project: cs]
9. ~/Projects/cs/STITCH.md — 34 days ago [STALE — run /stitch verify cs] [project: cs]
10. ~/Projects/ss/CODEMAP.md — (not found — run /codemap create) [project: ss]
```

**Pending Ideas surfacing:** if the query includes a configured project tag AND `{knowledge_folder}/intake/ideas/` exists, glob `intake/ideas/*.md`, read YAML frontmatter from each, and collect files whose `project:` field matches (or includes) the query's project tag. Present matches as a compact informational section after the file list, before the "Load which files?" prompt.

> **Why project-scoped only:** `/context` loads knowledge for retrieval; ideas are staging for external-tracker routing, not retrieval. Surfacing ideas on topic-only queries (`/context api`, `/context architecture`) would pollute the retrieval intent and blur ARIA's capture-vs-track boundary. Project-tagged queries get ideas as ambient project context; topic-only queries stay clean. See the capture-vs-track architecture in `intake/ideas/README.md`.


```
## Pending Ideas for proj-a (3)
- 2026-04-15 (1 day ago) — feature — /setup diff prompts ahead vs diverged
- 2026-03-22 (25 days ago) — bug — theme tokens missing from blueprint XYZ [STALE — still relevant?]
- 2026-03-12 (35 days ago) — refactor — simplify blueprint merge logic [STALE — still relevant?]
```

Details:
- **Age + stale marker:** for each idea, invoke the **staleness-marker shared block** (defined at the head of Step 5) with:
  - `date_source` = YAML frontmatter `date:` field; fall back to filename `YYYY-MM-DD` prefix if frontmatter missing or malformed
  - `threshold_days` = `KT_IDEAS_STALENESS_DAYS` (default 7; read from `~/.gemini/antigravity/aria-knowledge.local.md` via `config.sh`, fall back to 7 if absent)
  - `remediation` = `"still relevant?"`

  Apply the block's `age_string` after the date and `marker` after the description. The rendered line is `- YYYY-MM-DD {age_string} — {type} — {description}{marker}` — byte-identical to pre-2.16 output.
- **Multi-project entries:** if the frontmatter `project:` field has comma-separated project tags (e.g., `cs,ss`), include the file for each matching project query.
- **Not selectable:** ideas are informational. They do NOT appear in the numbered file list and are not loadable via "all" or numbers. To triage them, use `/audit-knowledge` (structured disposition flow) or edit the files in `intake/ideas/` directly.
- **Omission:** if no ideas match, omit the section entirely (do not show an empty "Pending Ideas" heading).
- **Non-project queries:** skip this section entirely when the query is topic-only (e.g., `/context api` or `/context architecture`). Ideas surfacing is project-scoped; cross-project ideas reach the user through `/audit-knowledge`, not `/context`.
- **Legacy-file handling:** if `intake/ideas-backlog.md` exists alongside `intake/ideas/`, do NOT parse it here. Surface a one-line informational note at the end of the Pending Ideas block: "(Legacy `ideas-backlog.md` detected — run `/setup` to migrate pre-2.11 entries into this view.)"

Show the file's tags in brackets after the description so the user can see why each file matched.

**If no matches at all:**

```
No files match tag(s): [tags]

Known tags: api, architecture, css, database, ...
Run `/index` to rebuild if you've recently added files.
```

If the query included a project tag and that project's folder was empty, mention it here too:

```
No files match tag(s): [proj-a]

(projects/proj-a/ exists but is empty — populate it via /extract or by creating files manually.)
Known tags: api, architecture, ...
```

**Alias display (added 2.16.0):** when rendering the "Known tags:" list in either no-match case above, append each canonical tag's aliases in parens, e.g., `kubernetes (k8s, kube), react-native (rn)`. Source the aliases from `index.md`'s `## Known Tags` section `[aliases: ...]` annotations (built by `/index` Step 2b + Step 9). Cap at 2 aliases per canonical to keep the list scannable; truncate with `…` (e.g., `aws (a, b …)`) if more exist. Omit the parens entirely for canonicals with no aliases declared.

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
