---
description: "Rebuild the knowledge tag index. Scans promoted files, normalizes tags, flags untagged files, suggests freeform-to-known promotions, detects stale files, suggests cross-references, updates project-to-tag mappings, and regenerates index.md. Use when user says '/index', 'rebuild index', 'update index', 'reindex knowledge'. Also called automatically by /audit-knowledge."
---

# /index — Knowledge Index Builder

Scan all promoted knowledge files, normalize tags, detect issues, and regenerate `{knowledge_folder}/index.md`.

## Step 0: Resolve Config

Read `~/.gemini/antigravity/aria-knowledge.local.md` and extract:
- `knowledge_folder` — base path for all operations
- `freeform_promotion_threshold` — minimum file count before suggesting promotion (default: 3)
- `staleness_threshold_months` — months before a file is flagged stale (default: 6)
- `projects_enabled` — default `false`; controls whether project tier is scanned and indexed
- `projects_list` — default empty; comma-separated `tag:path` pairs; only relevant if `projects_enabled: true`
- `projects_promotion_threshold` — default `2`; minimum projects sharing a similar pattern to surface as a cross-project promotion candidate
- `projects_shared_knowledge` — default empty; comma-separated list of project tags enabled for shared knowledge. When non-empty, scan each listed project's `_project-knowledge/` folder for team-shared knowledge. Tags not in this list are skipped (their `_project-knowledge/` folders, if any exist on disk, are NOT indexed).

If the config file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

## Step 1: Scan Promoted Folders

Scan these directories for `.md` files (excluding directory README stubs that only contain a few lines of boilerplate):
- `{knowledge_folder}/approaches/`
- `{knowledge_folder}/decisions/`
- `{knowledge_folder}/guides/` (recursive — includes subdirectories)
- `{knowledge_folder}/references/`

**Do NOT scan:** `archive/`, `intake/`, `rules/`, top-level `logs/*.md` (audit-log files like `config-audit-log.md`, `knowledge-audit-log.md`, `hook-debug.log`), or root-level files (`README.md`, `LOCAL.md`, `OVERVIEW.md`, `index.md`).

**Carve-out for review reports:** the two subfolders `logs/prospect/` and `logs/retrospect/` ARE scanned as a separate "reviews tier" — see the dedicated sub-step below. Review reports use the same frontmatter scanning convention as cross-project files (tags, Last updated, first heading).

For each `.md` file found:
1. Read the file
2. Extract YAML frontmatter (content between `---` markers at the top of the file)
3. From frontmatter, extract:
   - `tags:` — array of tags (e.g., `tags: [api, pagination, django]`). If missing, record as untagged.
   - `Last updated:` — date string (YYYY-MM-DD). If missing, record as unknown.
   - `semantic-hints:` — array of free-form phrases (e.g., `semantic-hints: [cursor pagination, keyset pagination]`). Optional; if missing, treat as empty list. Added 2.16.0.
4. Extract the first `#` heading as the file's description
5. Store: `{path, tags[], hints[], description, last_updated, source: "cross-project"}`

Report: "Scanned N files in approaches/, decisions/, guides/, references/."

### Reviews tier scan (always run if either review subfolder exists)

After the cross-project scan, scan `logs/prospect/` and `logs/retrospect/` for review reports written by the `/prospect` and `/retrospect` skills.

For each `.md` file found in either subfolder:
1. Read the file
2. Extract YAML frontmatter — review reports have a richer schema than cross-project files. Pull:
   - `tags:` — array of tags. Always includes `prospect` or `retrospect` plus the scope keyword. If missing (legacy reports written before the structured-frontmatter format), record as untagged and emit a soft warning (one-line) suggesting the file be re-run or hand-tagged.
   - `Last updated:` — fall back to `date:` if `Last updated:` is absent (review reports use `date:` for the report-creation date).
   - `type:` — `prospect` or `retrospect`. Used to bucket the file under "Retrospects" or "Prospects" in the `## Review Index` section of `index.md` (see Step 9).
   - `scope:` — the scope keyword (e.g., `release`, `deployment`, `commit`, `plan`).
   - `tickets:` — for cross-reference enrichment (consumed by `/context`).
3. Extract the first `#` heading as the file's description (typically "/prospect — <goal>" or "/retrospect — <goal>").
4. Store: `{path, tags[], description, last_updated, source: "review", review_type: <prospect|retrospect>, scope: <keyword>, tickets: [...]}`

Report: "Scanned R review reports across logs/prospect/ and logs/retrospect/ (P prospect, Q retrospect)."

If neither subfolder exists yet on disk, skip this sub-step silently (first run before any /prospect or /retrospect has been invoked).

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

### Team-shared scan (only if `projects_shared_knowledge` list is non-empty)

After the project tier scan, scan each enabled project's `_project-knowledge/` folder. Only projects whose tags appear in `projects_shared_knowledge` are scanned — non-listed projects are skipped, even if their `_project-knowledge/` folders exist on disk.

For each tag in `projects_shared_knowledge` (parsed as comma-separated list):
1. Resolve the project root: look up the tag in `projects_list` to get its path, then resolve to `~/Projects/<path>`. If the tag is not present in `projects_list`, log a warning and skip (config inconsistency — `/setup` validation should catch this, but defensive).
2. **Determine scan locations** based on whether the tag has a `projects_groups` entry (multi-repo project):
   - **Single-repo project** (no `projects_groups[tag]`): scan `<project-root>/_project-knowledge/` directly.
   - **Multi-repo project** (`projects_groups[tag]` is set): the project-root is a container, not a repo. Iterate the role:sub-repo pairs in `projects_groups[tag]` (preserving declaration order), and for EACH sub-repo, scan `<project-root>/<sub-repo>/_project-knowledge/`. Skip sub-repos whose path doesn't exist on disk (sub-repo not yet cloned).
3. For each scan location determined in step 2, probe for `_project-knowledge/`. If the folder doesn't exist, skip that location (no team-shared knowledge yet there). Continue to next location (don't bail on the whole tag — sibling sub-repos may have content).
4. Glob `<scan-location>/_project-knowledge/**/*.md` recursively.
5. **Exclude** `<scan-location>/_project-knowledge/README.md` (auto-generated convention explainer, not knowledge content).
6. For each file found, perform frontmatter extraction as in the cross-project scan above.
7. **Path-derived metadata:**
   - If the file path is at `<scan-location>/_project-knowledge/*.md` (top level), categorize as `team-shared` with `project: <tag>` (always the parent project tag from `projects_shared_knowledge`, NOT the sub-repo name — sub-repo identity is captured in the absolute path stored in step 9).
   - If the file path is under `<scan-location>/_project-knowledge/cross/*.md`, categorize as `team-shared-cross` with `project: cross`.
   - The path-derived project tag is added to the file's tag set even if not in YAML frontmatter (same Decision #9 pattern as project tier).
8. **IDEAS-BACKLOG.md handling:** treat `_project-knowledge/IDEAS-BACKLOG.md` and `_project-knowledge/cross/IDEAS-BACKLOG.md` as single files (don't try to split them into entries for indexing). Index them as one file each, tagged with the project tag (or `cross`).
9. Store: `{path: <absolute-path-from-home>, tags[], description, last_updated, source: "team-shared", project: <tag>, scope: "repo" | "cross"}`.

Report: "Scanned T team-shared files across P enabled projects: [project tags from `projects_shared_knowledge` with non-empty `_project-knowledge/` folders]."

If `projects_shared_knowledge` is empty/missing, skip this sub-step entirely. Team-shared files (if any exist on disk) won't be indexed.

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

## Step 2b: Read and Validate Aliases (added 2.16.0)

Read `{knowledge_folder}/aliases.md` if it exists.

Parse the alias map: each line matching the pattern `` - `<alias>` → `<canonical>` `` contributes one entry. The alias and canonical are the backtick-quoted strings; whitespace around the arrow is tolerated; non-matching lines (headers, comments, blank lines) are ignored.

If the file doesn't exist OR contains no parseable entries, treat the alias map as empty and continue to Step 3.

**Chain check (internal to the alias map):** if any canonical name in the parsed map ALSO appears as an alias key in another entry of the same map, abort `/index` with:

> `"Alias chain detected: \`x\` → \`y\` → \`z\` in aliases.md. Aliases must point directly to a canonical tag, not to another alias. Fix the chain (typically: rewrite the intermediate alias to point at the final canonical) and re-run /index."`

**Collision check (against Step 1's per-file tag data):** for each alias `a` in the parsed map, scan the per-file `tags[]` arrays collected in Step 1. If any file declares `a` in its `tags:` frontmatter, abort `/index` with:

> `"Alias \`a\` in aliases.md collides with existing tag \`a\` used in N file(s): <comma-separated paths>. Either remove the alias from aliases.md or rename the tag in those files."`

On successful validation, retain the alias map for Step 9 (Known Tags annotation). The map is also consumed by `/context` Step 2.5 (which reads it from the `## Known Tags` section's `[aliases: ...]` annotations, not from `aliases.md` directly).

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

**Exclude ephemeral tags before applying the threshold.** Session/phase/plan stamps recur across many files (so they hit the threshold) but are NOT durable concepts and should never become canonical Known Tags. Drop any candidate whose **whole tag** matches one of these patterns (case-insensitive) before counting:

- `^s\d+$` — session stamps (`s4`, `s60`, `s82`, `s111`)
- `^p-?\d+$` — plan / work-item ids (`p-23`, `p23`)
- `^phase-?\d+$` — phase stamps (`phase-3`, `phase3`)
- `^plan-\d+[a-z]?$` — plan ids (`plan-01a`)
- literal denylist: `future-session-plan`, `soft-launch`

This **suppresses AUTO-promotion suggestions only — it is not a hard ban.** A user can still hand-add any of these to Known Tags (Step 9 writes whatever is in the set, and a tag in Known Tags never re-enters the freeform pool). Because a pattern could occasionally match a genuine concept (e.g. a future `s3` meaning AWS S3 — note `s3` is not a session stamp in the current corpus, but `^s\d+$` would match it), the skipped set is **surfaced, not silent**. Emit a one-line note so a false-positive can be rescued:

```
Skipped N ephemeral tag(s) from promotion (session/phase/plan stamps): s82, s75, phase-3, … — hand-add to Known Tags if any is actually a durable concept.
```

To make an exclusion permanent for a real concept, hand-add that tag to Known Tags (it then never re-enters the freeform pool). To tune the patterns, edit this list — there is intentionally no config field for it (Rule 13: the hand-add override + this documented list cover the need without a new setting).

**Present suggestions:** (candidates remaining after the ephemeral-exclusion filter)

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

## Step 7b: Heavy-Pass Gate (REQUIRED before Steps 8.x)

Steps 8 (Cross-Reference Pass), 8b (Entity Detection), 8c (Skill Connection Discovery), and 8d (Cross-Project Promotion Candidates) require **body content scans** of every promoted knowledge file — substantially more expensive than the frontmatter-only scan that powers Steps 1-7. For a 500+ file knowledge base, expect ~3 minutes wall-clock and meaningful token cost.

These steps were silently skipped in the first 35+ `/index` passes (added to the spec but never invoked at routine pass cost). v2.20.0+ makes the cost explicit and gates the heavy work behind user confirmation.

**Prompt:**

> Routine `/index` indexes via frontmatter (tags, dates, descriptions). Heavy-pass Steps 8.x run additional body-content scans for:
> - **Step 8** — Cross-reference suggestions (pairs of files sharing ≥2 tags with no mutual `## Related` link, plus reverse-link gaps)
> - **Step 8b** — Entity detection (tools/services/frameworks appearing in ≥2 files)
> - **Step 8c** — Skill-knowledge connection discovery (skill names referenced in knowledge files; name-overlap matching)
> - **Step 8d** — Cross-project promotion candidates (similar patterns across ≥2 projects in `projects_list`)
>
> Cost: ~3 min wall-clock for N files (N = scanned count from Step 1) + meaningful token spend. Output: enriched `index.md` sections.
>
> Run heavy-pass Steps 8.x? **(y / n / partial)**

- **`y`** — proceed with Steps 8, 8b, 8c, 8d as defined below
- **`n`** — skip Steps 8.x entirely; proceed to Step 9 with frontmatter-only data; resulting `index.md` will omit the `## Cross-Reference Suggestions`, `## Entities`, `## Skill Connections`, `## Cross-Project Promotion Candidates` sections
- **`partial: <substep-list>`** — run a subset (e.g., `partial: 8d` runs only cross-project; `partial: 8,8d` runs cross-reference + cross-project, skips entity detection + skill connections). Useful when one substep is the user's actual interest and the other three are noise for this pass.

### When `/index` is called from `/audit-knowledge` Step 7b

If `/index` is being invoked as part of `/audit-knowledge`'s Step 7b rebuild (not stand-alone), the heavy-pass gate **still fires** — the audit user is the same human; ask them once. If the user declines or chose `partial`, the audit's Step 5b drift-detection capabilities are degraded (skill-knowledge drift relies on Step 8c output, cross-project candidate detection relies on Step 8d). Surface this degradation explicitly in `/audit-knowledge` Step 6's "Integrity Issues" section with a "Limited by Steps 8.x skip" note.

### When the user pre-authorizes via argument

`/index` accepts an optional argument:
- `/index` — default; prompt at Step 7b
- `/index --deep` — pre-authorize all of Steps 8.x (treat the gate as auto-`y`)
- `/index --shallow` — pre-authorize skip of all Steps 8.x (treat the gate as auto-`n`)
- `/index --partial=8d` — pre-authorize partial run (same syntax as the prompt's `partial:` response)

When pre-authorized, skip the prompt and proceed accordingly. Audit-time invocations should typically run shallow or partial (audit is the long-flow already); explicit `/index --deep` is the right shape for periodic baseline refreshes (every 1-2 weeks, or when a major batch of new files lands).

### Skill-spec history (informational)

Steps 8.x were defined in the spec from v1.0 but never invoked because routine `/index` calls treated them as frontmatter-tier work. 35+ passes silently skipped. v2.20.0 (2026-05-20) introduces this gate after the 37th-pass `/audit-knowledge` first invoked Steps 8.x via parallel agent (one-time baseline) and the resulting agent output ran ~3 min producing 599 lines of findings — Mike confirmed the cost-value gate-explicit pattern over routine-silent-skip.

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
2. Also scan any other installed plugins: `~/.gemini/config/plugins/**/skills/*/SKILL.md`
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

tag1, tag2 [aliases: alt1, alt2], tag3, tag4, ...

(Canonical tags with aliases declared in `aliases.md` are annotated inline: `tag [aliases: alias1, alias2]` enumerates all aliases pointing to that canonical. Tags with no aliases appear without annotation. The flat tag list is comma-separated. `/context` reads these annotations to build its alias→canonical map at query time. Added 2.16.0.)

## Tag Index

### [known_tag]
- relative/path/to/file.md — File description

(repeat for each known tag that has matching files, sorted alphabetically)

## Other Tags

### [freeform_tag]
- relative/path/to/file.md — File description

(repeat for each freeform tag, sorted alphabetically)

## Semantic Hints Index

### [hint phrase]
- relative/path/to/file.md

(Repeat for each unique hint phrase declared across promoted files, sorted alphabetically by phrase. Each file appears under every hint it declares. Hint phrases are stored verbatim from frontmatter — `/context` does the case-insensitive + hyphen-normalized substring match at query time. Omit this section entirely if no files declare `semantic-hints:`. Added 2.16.0.)

## Team-Shared Tag Index

### [tag]
- ~/Projects/<path>/_project-knowledge/2026-04-28-init-foo.md — File description [project: proj-a, scope: repo]
- ~/Projects/<path>/_project-knowledge/cross/2026-04-28-init-bar.md — File description [project: cross, scope: cross]

(repeat for each tag matching team-shared files, sorted alphabetically. File paths are absolute-from-home so /context can distinguish them from knowledge-folder-relative paths in the regular Tag Index. The trailing `[project: ..., scope: ...]` annotation lets /context render team-shared results with their origin info. Omit this section entirely if `projects_shared_knowledge` is empty/missing or no team-shared files exist.)

## Review Index

### Retrospects
- YYYY-MM-DD [scope] — Goal text (truncated to ~60 chars) [LINEAR-123, LINEAR-456] → outcome
- YYYY-MM-DD [scope] — Goal text [tickets] → outcome

### Prospects
- YYYY-MM-DD [scope] — Goal text [tickets] → verdict
- YYYY-MM-DD [scope] — Goal text [tickets] → verdict

(Sourced from files indexed under the reviews tier — `logs/retrospect/*.md` and `logs/prospect/*.md`. Within each subsection, sort descending by `date:` from frontmatter (newest first — most actionable for catch-up). Each entry shows: ISO date, scope keyword in brackets, truncated goal, ticket list (if any), and the report's overall_outcome (retrospects: closed / partial / unresolved / mixed) or overall_verdict (prospects: PROCEED / PROCEED-WITH-CHANGES / HOLD / KILL). The ticket list links to the ticket reference if Linear MCP is available; otherwise shows the bare IDs.

Path is relative to the knowledge folder root: `logs/retrospect/YYYY-MM-DD-scope-slug.md`. Use the file path as the link target so the user can click through to the full report.

If no review reports exist (first run before any /prospect or /retrospect was invoked), omit this section entirely.

If reviews lack frontmatter `overall_outcome` / `overall_verdict` (legacy reports written before the structured-frontmatter format), substitute "[no verdict recorded]" rather than omitting the entry.)

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
