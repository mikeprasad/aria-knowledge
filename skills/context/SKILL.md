---
name: context
description: Load relevant knowledge by topic. Queries the tag index and presents matching promoted files for selective loading into context. Use when user says "/context stripe", "/context api pagination", "/aria-cowork:context architecture", "load knowledge about...", "what do we know about...".
argument-hint: <tag1> [tag2] [AND tag3]
---

# /context — On-Demand Knowledge Retrieval

Query the knowledge tag index and load relevant promoted files into the conversation context.

## Step 0: Resolve config

The default knowledge folder is `~/Projects/knowledge/` (expand `~` to your home directory's absolute path). Read `<knowledge_folder>/aria-config.md` and extract `knowledge_folder`. If `aria-config.md` doesn't exist, stop: *"aria-cowork is not configured. Run `/aria-setup` to get started."*

Use `<knowledge_folder>` for all file operations during this session.

**Phase 1 note:** Project-tier expansion (e.g., `/context ss` expanding to all `ss` project's relevant tags) and team-shared knowledge surfacing are deferred to Phase 2+. v0.1.0 supports cross-project tag matching only.

## Step 1: Read index

Read `<knowledge_folder>/index.md`.

If the file doesn't exist, stop: *"No knowledge index found. Run `/aria-cowork:index` to build it."*

Parse the index to extract:
- `## Known Tags` section — the canonical tag list
- `## Tag Index` section — tag → file mappings for known tags
- `## Other Tags` section — tag → file mappings for freeform tags

## Step 2: Parse query

The user's argument is a space-separated list of tags with optional `AND` keyword.

**Parsing rules:**
- Split on spaces.
- If the token `AND` (case-insensitive) appears, use **intersection mode** — a file must have ALL specified tags.
- Otherwise, use **union mode** (default) — a file matches if it has ANY of the specified tags.
- Remove `AND` tokens from the tag list.

Examples:
- `/context stripe` → tags: [`stripe`], mode: OR
- `/context api pagination` → tags: [`api`, `pagination`], mode: OR
- `/context api AND pagination` → tags: [`api`, `pagination`], mode: AND

If no argument provided, stop: *"Usage: `/aria-cowork:context <tag1> [tag2] [AND tag3]`. Run `/aria-cowork:index` to see available tags."*

## Step 2.5: Resolve aliases (added v0.3.0 — parity with aria-knowledge v2.16.0)

After parsing the query into tokens (Step 2) but BEFORE matching (Step 3), resolve any aliases.

**Source:** the alias map is encoded in `index.md`'s `## Known Tags` section as `[aliases: ...]` annotations on canonical tag entries. Parse that section to build a flat `alias → canonical` map. If no aliases are declared (no `[aliases: ...]` annotations exist), skip this step entirely.

**Resolution:** for each token `t` in the parsed query, look up `t` in the alias→canonical map. If matched, replace `t` with its canonical form. Record the resolution.

**Notification:** for each resolution, emit one line BEFORE the Step 3 matching begins:

```
Resolved `meeting` → `meetings`
```

**Unidirectional:** resolution is alias → canonical only. Querying the canonical does NOT match alias-only declarations (i.e., querying `meetings` won't surface files that only declare alias `meeting`).

## Step 3: Match files

Scan the `## Tag Index`, `## Other Tags`, and `## Semantic Hints Index` sections for entries matching the query tokens.

**Matching rule (extended v0.3.0 — parity with aria-knowledge v2.16.0):** a query token `t` matches a file `f` if either:

1. `t` equals a tag declared by `f` (existing behavior — checked in `## Tag Index` / `## Other Tags`), OR
2. `t.lower()` (with hyphens stripped) appears as a substring of any phrase listed under any `## Semantic Hints Index` heading where `f` is listed. The hint phrase is also lowercased + hyphen-stripped before comparison.

When a file matches via hint rather than tag, record the matching hint phrase so Step 4 can annotate the result with `[hint: <phrase>]`.

**Union mode (OR):** Collect files that satisfy any query token via either rule above. Deduplicate — each file appears once even if it matches multiple tags or hints.

**Intersection mode (AND):** Collect files that satisfy ALL query tokens (each token can independently satisfy via tag OR hint).

If `## Semantic Hints Index` is absent (no files in the index declared `semantic-hints:`), the matching reduces to tag-only — behavior is byte-identical to pre-v0.3.0.

For each matching file, collect:
- File path (relative to knowledge folder)
- Description (from the index entry)
- All tags the file carries (scan all tag sections for this file path)
- Matching hint phrase(s), if any (used for Step 4's `[hint: ...]` annotation)

## Step 4: Present summary

If matches found, present them with the file's tags in brackets. When a file matched via semantic hint (Step 3 rule 2) rather than tag, append `[hint: <phrase>]` after the tag list so the user can see why the file was surfaced:

```
Found N files matching: [tags] ([OR|AND])

1. approaches/api-pagination.md — Cursor-based pagination patterns [api, pagination, stripe]
2. decisions/003-cursor-vs-offset.md — Why we chose cursor pagination [api, stripe]
3. references/stripe-webhook-patterns.md — Webhook signature verification [stripe, webhooks]
4. approaches/stakeholder-framing.md — Framing template for new initiatives [framing, comms] [hint: stakeholder framing for new initiative]

Load which files? (all / numbers / none)
```

**If no matches at all:**

```
No files match tag(s): [tags]

Known tags: api (a), architecture, database, kubernetes (k8s, kube), react-native (rn), ...
Run `/aria-cowork:index` to rebuild if you've recently added files.
```

**Alias display in no-match case (added v0.3.0 — parity with aria-knowledge v2.16.0):** when rendering the "Known tags:" list, append each canonical tag's aliases in parens, e.g., `kubernetes (k8s, kube)`. Source aliases from `index.md`'s `## Known Tags` section `[aliases: ...]` annotations (built by `/index` Step 2b + Step 8). Cap at 2 aliases per canonical to keep the list scannable; truncate with `…` (e.g., `aws (a, b …)`) if more exist. Omit the parens entirely for canonicals with no aliases declared.

## Step 5: Load selected files

Based on user response:
- **"all"** — read and present the full content of every matched file.
- **Numbers (e.g., "1 3" or "1,3")** — read and present only the specified files.
- **"none"** — stop, don't load anything.

For each selected file:
1. Read `<knowledge_folder>/{file_path}`
2. Present the full file content.

After loading, confirm: *"Loaded N knowledge files into context."*

## Rules

- **Read-only** — this skill never modifies any files.
- **Index is the discovery source** — no file reads happen during discovery. File contents are only read at load time (Step 5).
- **Promoted files only** — does not search backlogs, intake, rules, or logs.
- **No full-text search** — tag-based matching only. If the user needs content search, suggest using Grep directly.
- **Present before loading** — always show the summary and let the user choose which files to load.
- **Use Cowork's native I/O** — never invoke a Filesystem MCP connector (per ADR-003).
- **Phase 2+ features**: project-tier expansion, team-shared knowledge surfacing, and ideas-backlog integration are NOT in v0.1.0. They land when the projects/ tier and `~~project tracker` MCP integrations ship.
