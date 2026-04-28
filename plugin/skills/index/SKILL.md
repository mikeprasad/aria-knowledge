---
description: "Rebuild the knowledge tag index. Scans promoted files, normalizes tags, flags untagged files, suggests freeform-to-known promotions, detects stale files, suggests cross-references, updates project-to-tag mappings, and regenerates index.md. Use when user says '/index', 'rebuild index', 'update index', 'reindex knowledge'. Also called automatically by /audit-knowledge."
argument-hint: ""
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# /index — Knowledge Index Builder

Scan all promoted knowledge files, normalize tags, detect issues, and regenerate `{knowledge_folder}/index.md`.

## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md` and extract:
- `knowledge_folder` — base path for all operations
- `freeform_promotion_threshold` — minimum file count before suggesting promotion (default: 3)
- `staleness_threshold_months` — months before a file is flagged stale (default: 6)
- `projects_enabled` — default `false`; controls whether project tier is scanned and indexed
- `projects_list` — default empty; comma-separated `tag:path` pairs; only relevant if `projects_enabled: true`
- `projects_promotion_threshold` — default `2`; minimum projects sharing a similar pattern to surface as a cross-project promotion candidate
- `projects_shared_knowledge` — default `false`; when `true`, also scan each project's `_project-knowledge/` folder for team-shared knowledge

If the config file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

## Step 1: Scan Promoted Folders

Scan these directories for `.md` files (excluding directory README stubs that only contain a few lines of boilerplate):
- `{knowledge_folder}/approaches/`
- `{knowledge_folder}/decisions/`
- `{knowledge_folder}/guides/` (recursive — includes subdirectories)
- `{knowledge_folder}/references/`

**Do NOT scan:** `archive/`, `intake/`, `rules/`, `logs/`, or root-level files (`README.md`, `LOCAL.md`, `OVERVIEW.md`, `index.md`).

For each `.md` file found:
1. Read the file
2. Extract YAML frontmatter (content between `---` markers at the top of the file)
3. From frontmatter, extract:
   - `tags:` — array of tags (e.g., `tags: [api, pagination, django]`). If missing, record as untagged.
   - `Last updated:` — date string (YYYY-MM-DD). If missing, record as unknown.
4. Extract the first `#` heading as the file's description
5. Store: `{path, tags[], description, last_updated, source: "cross-project"}`

Report: "Scanned N files in approaches/, decisions/, guides/, references/."

### Project tier scan (only if `projects_enabled: true` and `projects_list` is non-empty)

After the cross-project scan, scan the project tier:

For each `tag:path` pair in `projects_list`:
1. Glob `{knowledge_folder}/projects/{tag}/**/*.md` recursively
2. **Exclude** `projects/{tag}/README.md` (per-project navigation, not knowledge content)
3. **Exclude** `projects/README.md` (the projects/ tier README, plugin-managed)
4. For each file found, perform the same frontmatter extraction as above.
5. **Path-derived tag union (Decision #9):** automatically add `{tag}` to the file's tag set even if not in YAML frontmatter. The union of YAML tags + path tag is what gets indexed. This means project files don't have to manually include the project tag in their frontmatter.
6. Store: `{path, tags[], description, last_updated, source: "project-specific", project: tag}`

Report: "Scanned M files across N project subdirectories: [project tags]."

If `projects_enabled: false` or `projects_list` is empty, skip this sub-step entirely. Project tier files (if any exist on disk) won't be indexed.

### Team-shared scan (only if `projects_shared_knowledge: true`)

After the project tier scan, scan each project's `_project-knowledge/` folder if the team-shared feature is enabled.

For each `tag:path` pair in `projects_list`:
1. Resolve the project root: `~/Projects/<path>` (where `<path>` is the projects_list value).
2. Probe `<project-root>/_project-knowledge/`. If the folder doesn't exist, skip this project (no team-shared knowledge yet).
3. Glob `<project-root>/_project-knowledge/**/*.md` recursively.
4. **Exclude** `<project-root>/_project-knowledge/README.md` (auto-generated convention explainer, not knowledge content).
5. For each file found, perform frontmatter extraction as in the cross-project scan above.
6. **Path-derived metadata:**
   - If the file path is at `<project-root>/_project-knowledge/*.md` (top level), categorize as `team-shared` with `project: <tag>`.
   - If the file path is under `<project-root>/_project-knowledge/cross/*.md`, categorize as `team-shared-cross` with `project: cross`.
   - The path-derived project tag is added to the file's tag set even if not in YAML frontmatter (same Decision #9 pattern as project tier).
7. **IDEAS-BACKLOG.md handling:** treat `_project-knowledge/IDEAS-BACKLOG.md` and `_project-knowledge/cross/IDEAS-BACKLOG.md` as single files (don't try to split them into entries for indexing). Index them as one file each, tagged with the project tag (or `cross`).
8. Store: `{path: <absolute-path-from-home>, tags[], description, last_updated, source: "team-shared", project: <tag>, scope: "repo" | "cross"}`.

Report: "Scanned T team-shared files across P projects: [project tags with non-empty `_project-knowledge/` folders]."

If `projects_shared_knowledge: false`, skip this sub-step entirely. Team-shared files (if any exist on disk) won't be indexed.

## Step 2: Read Existing Index

Read `{knowledge_folder}/index.md` if it exists.

Extract:
- `## Known Tags` section — the current canonical tag vocabulary (comma-separated list)
- `## Projects` section — current project-to-tag mappings

If `index.md` doesn't exist (first run), use the seeded known tags:

```
api, architecture, css, database, deployment, django, react, nextjs, react-native, tailwind, testing, infrastructure, performance, security, accessibility, stripe, linear, supabase, figma, claude-code, process, decision-framework, enforcement, aria
```

And leave the Projects section empty (will be populated in Step 6).

## Step 3: Tag Normalization

Compare all tags found across scanned files. Detect similar tags using these heuristics:
- **Plural/singular:** `api` vs `apis`, `test` vs `tests`
- **Hyphen variants:** `react-native` vs `reactnative` vs `react native`
- **Common abbreviations:** `db` vs `database`, `infra` vs `infrastructure`

For each pair of similar tags, check which one is in the Known Tags set. If one is known and the other isn't, the known one is the normalization target.

If both are unknown, prefer the more common one (appears on more files).

**Present conflicts to user:**

```
## Tag Normalization

Found similar tags:
1. `apis` (1 file) → normalize to `api` (4 files)? [y/n]
2. `reactnative` (1 file) → normalize to `react-native` (2 files)? [y/n]
```

For each approved normalization:
- Edit the source file's YAML frontmatter to replace the old tag with the normalized tag
- Record the change for the summary

If no similar tags found, skip this step silently.

## Step 4: Freeform-to-Known Tag Promotion

Identify tags that are NOT in the Known Tags set but appear on `{freeform_promotion_threshold}` or more files (default: 3).

**Present suggestions:**

```
## Freeform Tag Promotion

These freeform tags appear frequently:
1. `webhooks` — 4 files. Promote to known tags? [y/n]
2. `authentication` — 3 files. Promote to known tags? [y/n]
```

For each approved promotion:
- Add the tag to the Known Tags set (will be written to index.md in Step 9)
- Record for summary

If no tags qualify, skip this step silently.

## Step 5: Untagged File Resolution

For each file with no `tags:` in its frontmatter:

**Present list and offer to fix:**

```
## Untagged Files

Found N files without tags:
1. guides/claude/environment-architecture.md — "Environment Architecture"
   Suggested tags: [claude-code, architecture, infrastructure]
2. approaches/combo-class-pattern.md — "Combo Class Pattern"
   Suggested tags: [css, tailwind, df]

Add suggested tags? (all / numbers / skip)
```

For each file the user approves:
- Read the file
- If the file has existing YAML frontmatter (between `---` markers), add `tags: [tag1, tag2]` as a new line inside it
- If the file has no frontmatter, add a frontmatter block at the top:
  ```
  ---
  Last updated: YYYY-MM-DD
  tags: [tag1, tag2]
  ---
  ```
  (Use the file's existing `Last updated` date if found in the body, or today's date if none exists)
- Record the change for the summary

Tag suggestions are based on:
- Filename keywords (e.g., `api-pagination` → `api`, `pagination`)
- First heading keywords
- Content scan for known tag keywords
- Parent directory (e.g., file in `guides/claude/` → suggest `claude-code`)

## Step 6: Project-to-Tag Mapping Update

Determine the authoritative project list using this priority:

1. **If `projects_enabled: true` and `projects_list` is non-empty:** use `projects_list` as the project enumeration. Each `tag:path` pair contributes a project entry where the tag is the project key and the path is the project location. This is the configured set of projects ARIA recognizes.
2. **Otherwise** (or as a supplement when `projects_enabled: false`): read the root project CLAUDE.md to find a project table. Look for the closest ancestor directory containing a `CLAUDE.md` with a project table.

For each project (from either source):
1. Read the project's CLAUDE.md (e.g., `cs/CLAUDE.md`, `ss/CLAUDE.md`) if it exists at the configured path
2. Extract tech stack, tools, frameworks, and services mentioned
3. Match extracted keywords against the Known Tags set (including any newly promoted tags from Step 4)
4. Also check which tags appear on files that mention the project name in their path or content
5. **If projects tier is enabled:** add tags inferred from project-tier files (i.e., tags appearing on files under `projects/{tag}/**` from Step 1's project tier scan) to the project's relevant tag set

Build a mapping:
```
proj-a — Project A: api, django, react, react-native, css, tailwind, stripe, supabase, database, deployment
proj-b — Project B: api, django, nextjs, stripe, supabase, database, deployment
proj-c — Project C: css, tailwind, accessibility
aria — ARIA: claude-code, process, decision-framework, enforcement
```

Compare against existing mappings (from Step 2). If any changed:

```
## Project Mapping Updates

- proj-a: added `supabase` (found in proj-a/CLAUDE.md tech stack)
- proj-b: no changes
```

If this is the first run (no existing mappings), present the full initial mapping for confirmation.

## Step 7: Staleness Detection

For each scanned file, compare its `Last updated` date against today's date.

If the file's age exceeds `{staleness_threshold_months}` months (default: 6):
- Add to the stale files list with age and threshold info

This data is used when generating the `## Stale Files` section in Step 9. No user interaction here — just collection.

## Step 8: Cross-Reference Pass

For each pair of promoted files, compute tag overlap:
1. Count shared tags between the two files
2. If overlap >= 2 tags, check each file's `## Related` section for existing cross-references
3. If one or both files don't reference the other, record as a suggestion

Also check for **reverse link gaps**: if file A's `## Related` links to file B, but file B's `## Related` doesn't link to file A.

**Present suggestions:**

```
## Cross-Reference Suggestions

1. approaches/api-pagination.md <-> decisions/003-cursor-vs-offset.md
   Shared tags: api, pagination
   Neither references the other — add cross-links? [y/n]

2. references/stripe-webhook-patterns.md <-> guides/payments/checkout-flow.md
   Shared tags: stripe, cs
   checkout-flow.md links to stripe-webhook-patterns.md but not the reverse — add reverse link? [y/n]
```

For each approved cross-reference:
- If the file has a `## Related` section, append the new link:
  ```markdown
  - [Target File Title](../relative/path/to/target.md)
  ```
- If the file has no `## Related` section, add one at the end of the file:
  ```markdown

  ## Related
  - [Target File Title](../relative/path/to/target.md)
  ```
- Use relative paths from the source file to the target file

If no suggestions, skip this step silently.

## Step 8b: Entity Detection

Scan all promoted files for recurring proper nouns — tool names, service names, API names, framework names, and other named entities that appear across multiple knowledge files.

**How to detect entities:**
1. Scan headings, bold text, and inline code spans in promoted files for proper nouns and technical names
2. Filter to entities that appear in **2+ files** (single-file mentions aren't useful for cross-referencing)
3. Exclude entities that are already covered by tags (e.g., if "Stripe" is both a tag and an entity, the tag index already covers it)
4. Exclude common words that happen to be capitalized (sentence starters, section headings like "Overview", "Summary")

**Build an entity map:**
```
Stripe → approaches/payment-flow.md, references/stripe-webhook-patterns.md, decisions/003-payment-provider.md
Supabase → guides/infrastructure/supabase-setup.md, decisions/005-builder-architecture.md
Django → approaches/api-pagination.md, guides/api-auth.md
```

This data is used when generating the `## Entities` section in Step 9. No user interaction here — just collection.

## Step 8c: Skill Connection Discovery

Scan for connections between the plugin's skills and knowledge files. This enables `/audit-knowledge` to detect when a skill evolves but its related knowledge docs haven't been updated.

**Scan skill files:**

1. Glob for `${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md` (or use the plugin's own skill directory)
2. Also scan any other installed plugins: `~/.claude/plugins/**/skills/*/SKILL.md`
3. For each skill: extract `name` from frontmatter or directory name, extract `description`, scan for `## Related` sections

**Auto-discover connections** using these heuristics (in priority order):

1. **Explicit references:** Knowledge file content mentions the skill name (e.g., `/codemap` appears in an approach doc). Grep promoted files for `/skillname`.
2. **Skill `## Related` section:** Skill file explicitly references knowledge files. Parse relative paths.
3. **Name overlap:** Skill name is a substring of a knowledge filename or vice versa (e.g., "codemap" matches `codebase-documentation`). Use fuzzy matching — strip hyphens and compare.
4. **Tag/keyword overlap:** Skill description keywords match knowledge file tags. Extract significant nouns from the skill description and match against the Known Tags set + file tags.

**Present discoveries for user confirmation:**

```
## Skill Connections

Discovered N connections between skills and knowledge files:

1. /codemap → approaches/codebase-documentation.md
   Match: skill name referenced in file content
   Relationship: [auto-suggest or ask user]

2. /codemap → decisions/007-codebase-documentation-structure.md
   Match: "/codemap" mentioned in decisions backlog clear comment
   Relationship: [auto-suggest or ask user]

3. /extract → decisions/002-knowledge-extraction-architecture.md
   Match: name overlap ("extract" ↔ "extraction")
   Relationship: [auto-suggest or ask user]

Add connections? (all / numbers / skip / add manual)
```

For "add manual": let the user specify `skill → file → relationship` for connections the heuristics missed.

**Relationship types** (suggest the most likely, let user override):
- `documents the approach this skill implements`
- `records decisions that shaped this skill`
- `provides reference data used by this skill`
- `defines rules enforced by this skill`
- `guides usage patterns for this skill`

Store approved connections for Step 9 output.

## Step 8d: Cross-Project Promotion Candidate Detection

Skip this step entirely if `projects_enabled: false` or `projects_list` has fewer than 2 entries.

Scan files indexed under the project tier (from Step 1's project tier scan) for patterns that may represent the same concept across multiple projects.

**Detection heuristics** (compute pairwise across all project-tier files):

1. **Filename similarity:** Files with similar kebab-case names (e.g., `state-management-patterns.md` in `projects/proj-a/patterns/` AND `projects/proj-b/patterns/`). Use case-insensitive equality of stem (filename without `.md`) as the primary match; allow minor variants (`-patterns` vs `-pattern`, plural vs singular).
2. **Tag overlap:** Files sharing 3+ tags (excluding the project tags themselves, which are auto-derived from path).
3. **Title/H1 similarity:** Files whose H1 (first `#` heading) shares 3+ significant terms (excluding stop words and project names).

**Threshold:** if a pattern (i.e., a similar file) appears in ≥`projects_promotion_threshold` projects (default 2), surface as a candidate.

For each candidate group, collect:
- The set of project-tier files that triggered the match
- The shared tags (excluding project tags)
- A suggested cross-project location (typically `approaches/{descriptive-name-derived-from-shared-tags-or-title}.md`)

This data is used when generating the `## Cross-Project Promotion Candidates` section in Step 9. **No user interaction at this step** — just collection. Promotion itself happens in `/audit-knowledge` Step 5e (Phase 3 of the project knowledge feature).

**Rationale for surfacing in the index:** the index is a regularly-rebuilt artifact. Detecting candidates here means users see them whenever they look at the index, not only when they explicitly run `/audit-knowledge`. Lower-friction discovery, same downstream promotion workflow.

## Step 9: Rebuild and Write `index.md`

Generate `{knowledge_folder}/index.md` with this structure:

```markdown
# Knowledge Index

Last rebuilt: YYYY-MM-DD

## Projects

### [project_key] — [project_name]
Relevant tags: tag1, tag2, tag3
Project-tier files: N (decisions: D, patterns: P, other: O)
Last project-tier update: YYYY-MM-DD
Promotion candidates: M (see below — same pattern appears in ≥`projects_promotion_threshold` projects)

(repeat for each project. If `projects_enabled: false`, the per-project metrics lines after "Relevant tags:" are omitted — just the project key and tag mapping appear, mirroring v2.7.x format.)

(For projects with zero project-tier files, show `Project-tier files: 0` and omit "Last project-tier update" — Decision #8: list configured projects even if empty so the user sees what's available.)

## Known Tags

tag1, tag2, tag3, tag4, ...

## Tag Index

### [known_tag]
- relative/path/to/file.md — File description

(repeat for each known tag that has matching files, sorted alphabetically)

## Other Tags

### [freeform_tag]
- relative/path/to/file.md — File description

(repeat for each freeform tag, sorted alphabetically)

## Team-Shared Tag Index

### [tag]
- ~/Projects/<path>/_project-knowledge/2026-04-28-init-foo.md — File description [project: proj-a, scope: repo]
- ~/Projects/<path>/_project-knowledge/cross/2026-04-28-init-bar.md — File description [project: cross, scope: cross]

(repeat for each tag matching team-shared files, sorted alphabetically. File paths are absolute-from-home so /context can distinguish them from knowledge-folder-relative paths in the regular Tag Index. The trailing `[project: ..., scope: ...]` annotation lets /context render team-shared results with their origin info. Omit this section entirely if `projects_shared_knowledge: false` or no team-shared files exist.)

## Stale Files

### relative/path/to/file.md
Last updated: YYYY-MM-DD (N months ago) — threshold: M months

(repeat for each stale file. Omit this section entirely if no stale files.)

## Untagged Files

- relative/path/to/file.md — File description (no tags in frontmatter)

(Omit this section entirely if no untagged files remain after Step 5.)

## Entities

### [Entity Name]
- relative/path/to/file1.md
- relative/path/to/file2.md

(Repeat for each entity appearing in 2+ files, sorted alphabetically. Omit this section entirely if no entities detected or all are already covered by tags.)

## Skill Connections

| Skill | Related knowledge | Relationship |
|-------|------------------|-------------|
| /skillname | relative/path/to/file.md | documents the approach this skill implements |

(Repeat for each approved connection from Step 8c, sorted by skill name. Omit this section entirely if no connections discovered or approved.)

## Cross-Project Promotion Candidates

### [shared-tag-or-title-derived-name]
- Appears in: projects/{tag1}/patterns/file.md, projects/{tag2}/patterns/file.md
- Shared tags: tag-a, tag-b, tag-c
- Suggested location: approaches/{descriptive-name}.md
- Run `/audit-knowledge` Step 5e to promote (synthesizes content + adds `originally_at:` provenance)

(Repeat for each candidate group from Step 8d, sorted by number of projects involved descending then alphabetically. Omit this section entirely if `projects_enabled: false` or no candidates detected.)
```

**File paths** in the index are relative to the knowledge folder root (e.g., `approaches/api-pagination.md`, not the absolute path).

**Tag Index entries** are sorted: known tags alphabetically, then other tags alphabetically. Within each tag, files are sorted alphabetically by path.

**A file appears under every tag it carries.** If `api-pagination.md` has `tags: [api, pagination, django]`, it appears under all three tag headings.

## Step 10: Report Summary

```
Index rebuilt successfully.

Files: N scanned, M tagged, K untagged
Tags: L unique (J known, F freeform)
Normalizations: P applied
Promotions: Q tags promoted to known
Stale files: S (threshold: T months)
Cross-references: R suggested, X added
Entities: E detected (across 2+ files)
Skill connections: C discovered, D approved
Project mappings: updated/unchanged
```

## Rules

- **Never modify files outside the knowledge folder** except for the root CLAUDE.md read (read-only) in Step 6
- **Always present changes before making them** — normalizations, promotions, untagged fixes, and cross-references all require user approval
- **Preserve existing frontmatter** — when adding tags to a file, don't remove or modify other frontmatter fields
- **Relative paths in index** — all paths in index.md are relative to the knowledge folder root
- **Skip empty directories** — if approaches/ has no .md files, don't create an empty tag section
- **Directory README stubs are not knowledge files** — skip files that are only 1-5 lines of boilerplate (the README.md stubs in approaches/, decisions/, etc.)
