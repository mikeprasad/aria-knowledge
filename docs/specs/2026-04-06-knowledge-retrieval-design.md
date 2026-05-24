# Knowledge Retrieval & Resurfacing — Design Spec

**Date:** 2026-04-06
**Status:** Draft
**Scope:** ARIA plugin — Ranks 1-5, 7 + abbreviated Rule 22 (tag index, /context command, audit cross-referencing, staleness detection, session-start surfacing, bidirectional linking, planning-path hook optimization)

## Problem

ARIA's capture-to-promotion pipeline is strong, but promoted knowledge in `approaches/`, `decisions/`, `guides/`, and `references/` sits passive on disk. Rules get enforced via hooks (always-on), but non-rule knowledge has no retrieval mechanism. It surfaces only when someone manually remembers it exists and goes looking.

This means validated approaches, architectural decisions, and operational guides fail to inform the sessions where they'd prevent mistakes or improve decisions.

## Solution Overview

Seven additions that form a retrieval and maintenance layer on top of existing promoted knowledge:

1. **Tag index with frontmatter tags** — make knowledge findable by topic (Rank 1)
2. **`/context` command** — make knowledge loadable on demand (Rank 2)
3. **`/audit-knowledge` cross-referencing** — make the audit smarter about existing knowledge (Rank 3)
4. **Staleness detection** — flag knowledge that hasn't been reviewed within a configurable threshold (Rank 4)
5. **Session-start knowledge surfacing** — prompt users to load relevant knowledge after stating their task (Rank 5)
6. **Bidirectional cross-reference linking** — auto-suggest `## Related` links between files with tag overlap (Rank 7)
7. **Abbreviated Rule 22 for planning paths** — reduce hook friction for spec/planning docs without disabling enforcement

Rank 6 (pre-edit knowledge injection) is deferred — see Future Considerations.

## Design

### 1. Tag Convention & Frontmatter Format

Every promoted knowledge file gets a `tags:` field in YAML frontmatter:

```yaml
---
Last updated: 2026-04-06
tags: [api, pagination, django]
---
```

**Seeded known tags** (initial vocabulary):

| Group | Tags |
|-------|------|
| Tech domain | `api`, `css`, `database`, `deployment`, `django`, `react`, `nextjs`, `react-native`, `tailwind`, `testing`, `infrastructure` |
| Cross-cutting | `architecture`, `performance`, `security`, `accessibility` |
| Tool/service | `stripe`, `linear`, `supabase`, `figma`, `claude-code` |
| Process | `process`, `decision-framework`, `enforcement` |
| Project | `cs`, `ss`, `df`, `aria` |

**Freeform tags** are fully supported. Any tag not in the known set is valid — it gets indexed under `## Other Tags` in the index and is searchable via `/context`. Over time, `/index` suggests promoting frequently-used freeform tags into the known set.

**Project-to-tag mappings** associate each project with its relevant tags:

```
### cs — Commonspace
Relevant tags: api, django, react, react-native, css, tailwind, stripe, supabase, database, deployment
```

These are maintained in the index file and updated by `/index` (scanning project CLAUDE.md files).

### 2. Index File (`index.md`)

Lives at `{knowledge_folder}/index.md`. Generated artifact — rebuilt by `/index` and `/audit-knowledge`. Never hand-edited.

**Structure:**

```markdown
# Knowledge Index

Last rebuilt: 2026-04-06

## Projects

### cs — Commonspace
Relevant tags: api, django, react, react-native, css, tailwind, stripe, supabase, database, deployment

### ss — Seersite
Relevant tags: api, django, nextjs, stripe, supabase, database, deployment

### df — Designframe
Relevant tags: css, tailwind, accessibility

### aria — ARIA
Relevant tags: claude-code, process, decision-framework, enforcement

## Known Tags

api, architecture, css, database, deployment, django, react, nextjs,
react-native, tailwind, testing, infrastructure, performance, security,
accessibility, stripe, linear, supabase, figma, claude-code, process,
decision-framework, enforcement, cs, ss, df, aria

## Tag Index

### api
- approaches/api-pagination.md — Cursor-based pagination patterns
- decisions/003-cursor-vs-offset.md — Why we chose cursor pagination

### css
- approaches/combo-class-pattern.md — Designframe combo class methodology

### stripe
- references/stripe-webhook-patterns.md — Webhook signature verification

## Other Tags

### webhooks
- references/stripe-webhook-patterns.md — Webhook signature verification

### rate-limiting
- approaches/api-rate-limiting.md — Rate limiting strategy for public endpoints

## Untagged Files

- guides/claude/environment-architecture.md — (no tags in frontmatter)
```

Key details:
- Each entry: `path — description` (from file's first heading or description field)
- Files appear under every tag they carry
- `## Untagged Files` flags promoted files missing `tags:` frontmatter
- `## Known Tags` is the canonical vocabulary list

### 3. `/index` Skill

New skill. Scans promoted knowledge, normalizes tags, flags gaps, updates project mappings, and regenerates `index.md`.

**Usage:** `/index`

**Behavior:**

1. **Read config** from `~/.claude/aria-knowledge.local.md` to get `knowledge_folder`
2. **Scan promoted folders** — `approaches/`, `decisions/`, `guides/`, `references/` (not `archive/`, `intake/`, `rules/`, `logs/`)
3. **Read each `.md` file** — extract YAML frontmatter `tags:` and first heading for description
4. **Tag normalization pass:**
   - Detect similar tags (plural/singular, hyphen variants, known synonyms)
   - Present conflicts: "Found similar tags: `apis` (1 file) and `api` (4 files) — normalize `apis` to `api`?"
   - On confirmation, update frontmatter in affected files
   - If user declines, leave both as-is
5. **Freeform-to-known tag promotion:**
   - Identify freeform tags appearing on 3+ files (threshold configurable, default 3)
   - Present: "Tag `webhooks` appears on 4 files — promote to known tags?"
   - On confirmation, add to `## Known Tags` and move entries to `## Tag Index`
6. **Untagged file resolution:**
   - Prompt: "Found N untagged files — want to add tags now?"
   - For each, suggest tags based on filename, heading, and content scan
   - User confirms, edits, or skips each file
   - On confirmation, write `tags:` into file's frontmatter
7. **Project-to-tag mapping update:**
   - Scan each project's CLAUDE.md (paths from root `Projects/CLAUDE.md` project table)
   - Extract tech stack, tools, domain keywords
   - Match against known tags + tags found in promoted files
   - Update `## Projects` section
   - Present changes: "Added `supabase` to ss project tags"
8. **Rebuild index sections** — `## Tag Index`, `## Other Tags`, `## Untagged Files`
9. **Write `index.md`**
10. **Report summary:** `Indexed N files. M tagged, K untagged. L unique tags (J known, F freeform). P normalizations applied. Q tags promoted to known.`

**First run (no existing index):** Creates `index.md` with seeded known tags, scans projects for initial mappings, prompts to tag existing untagged files.

### 4. `/context` Skill

New skill. On-demand knowledge retrieval using the tag index.

**Usage:**
- `/context stripe` — files tagged with `stripe`
- `/context api pagination` — OR (default): files tagged with `api` or `pagination`
- `/context api AND pagination` — AND: files tagged with both
- `/context ss` — project expansion: matches `ss` tag + all tags in ss's project mapping

**Behavior:**

1. **Read config** to get `knowledge_folder`
2. **Read `index.md`** — if missing, prompt: "No index found — run `/index` first."
3. **Parse query** — split on spaces, detect `AND` keyword for intersection mode, otherwise OR
4. **Project tag expansion** — if a tag matches a project name in `## Projects`, include all files tagged with that project's relevant tags. Show note: "Expanded `ss` to include: api, django, nextjs, stripe, supabase, database, deployment"
5. **Match files** — scan `## Tag Index` and `## Other Tags` for matching entries
6. **Present summary:**
   ```
   Found 5 files matching: stripe (OR)

   1. approaches/api-pagination.md — Cursor-based pagination patterns [api, pagination, stripe]
   2. decisions/003-cursor-vs-offset.md — Why we chose cursor pagination [api, stripe]
   3. references/stripe-webhook-patterns.md — Webhook signature verification [stripe, webhooks]
   4. references/stripe-api-versioning.md — API version pinning strategy [stripe, api]
   5. guides/payments/checkout-flow.md — End-to-end checkout implementation [stripe, cs]

   Load which files? (all / numbers / none)
   ```
7. **Load selected files** — read full content and inject into conversation context
8. **No matches:** "No files match tag `foobar`. Known tags: [list]. Run `/index` to rebuild if you've recently added files."

**Constraints:**
- Promoted files only (no backlog searching)
- Tag-based only (no full-text search)
- Read-only (no file modification)
- Project tag expansion may return large result sets (e.g., `/context ss` expands to 10+ tags) — the summary-first presentation handles this by letting the user pick which files to load rather than injecting everything

### 5. `/audit-knowledge` Extensions

Three additions to the existing audit skill.

**Revised audit order:**

1. Existing behavior — scan memory/plans, review backlogs, categorize findings, emerging themes, integrity lint
2. **Cross-reference backlog against promoted docs** — for each backlog entry, check topic overlap against existing promoted files:
   - **Topic overlap:** If a backlog insight mentions pagination and `approaches/api-pagination.md` exists, flag: "This insight may relate to existing doc — update existing rather than create new?"
   - **Potential invalidation:** If a clipping describes a change (new API version, deprecated pattern), check if promoted docs reference the affected topic: "New clipping about Stripe API v2025-04 — existing `references/stripe-webhook-patterns.md` may need review."
   - Matching uses tags from the index when available, falls back to keyword matching in headings and content
3. Present all findings — user reviews, approves promotions, updates to existing docs
4. Execute approved promotions — new files written, existing files updated
5. **Index rebuild** — runs last after all file changes. Full `/index` logic: normalization, freeform promotion, untagged resolution, project mapping updates. Interactive prompts batched into findings presentation:
   ```
   ## Index Health
   - 2 similar tags: `apis` -> `api` (1 file), `react native` -> `react-native` (1 file)
   - 1 freeform tag eligible for promotion: `webhooks` (4 files)
   - 1 untagged file: guides/claude/environment-architecture.md
   - Project mappings: added `supabase` to ss

   [Approve normalizations? Promote webhooks? Tag untagged files?]
   ```
6. Audit log update

### 6. Session-Start Knowledge Surfacing (Rank 5)

Extends the session-start hook to prompt Claude to suggest a `/context` command after the user states their task. Works for any user regardless of project prompt setup.

**Mechanism:**

The session-start hook adds a system message instruction (in addition to existing audit cadence checks):

```
After the user describes their task, check if the knowledge index exists at {knowledge_folder}/index.md.
If it does, suggest a /context command with tags relevant to their stated task.
Only suggest once per session. Don't block — just offer.
```

**Behavior flow:**

1. Session starts — hook fires, outputs audit cadence checks (existing) plus the knowledge surfacing instruction
2. User states their task: "lets work on the Seersite API pagination"
3. Claude (prompted by the hook instruction) reads `index.md`, identifies relevant tags from the user's message (`api`, `pagination`, `ss`)
4. Claude suggests: "Before we start — you have knowledge docs that may be relevant. Want me to run `/context api pagination ss`?"
5. User accepts or declines — either way, the suggestion doesn't repeat

**Key properties:**
- **Fires after conversation starts** — doesn't guess from CWD alone, waits for user's stated intent
- **Universal** — no dependency on project prompt setup or folder structure conventions
- **Non-blocking** — a suggestion, not a gate. User can ignore and proceed
- **Low token cost** — one system message instruction, one suggestion from Claude, done
- **One-shot** — suggests once per session, doesn't nag

**What it doesn't do:**
- Auto-load knowledge (user must accept the `/context` suggestion)
- Fire on every task switch mid-session (only on first task statement)
- Require CWD detection or branch inspection

### 7. Staleness Detection (Rank 4)

Flags promoted knowledge files that haven't been reviewed within a configurable threshold.

**Default threshold:** 6 months for all categories (`approaches/`, `decisions/`, `guides/`, `references/`). User can edit the threshold in config. Rules are excluded — they're actively enforced via hooks and reviewed through `/audit-knowledge` integrity linting.

**Behavior in `/index`:**

During the file scan (step 3), read `Last updated` from frontmatter alongside tags. After rebuilding tag sections, generate a `## Stale Files` section in `index.md`:

```markdown
## Stale Files

### references/stripe-webhook-patterns.md
Last updated: 2025-09-14 (6 months ago) — threshold: 6 months

### decisions/003-cursor-vs-offset.md
Last updated: 2025-08-01 (8 months ago) — threshold: 6 months
```

Report in summary: `S stale files found (threshold exceeded).`

No action taken by `/index` — just flagged in the index.

**Behavior in `/audit-knowledge`:**

Since audit calls `/index` rebuild, stale files appear in the index automatically. Audit presents them as action items:

```
## Stale Knowledge
- 2 files past review threshold:
  - references/stripe-webhook-patterns.md (6 months, threshold: 6 months)
  - decisions/003-cursor-vs-offset.md (8 months, threshold: 6 months)

Review and update Last updated date? Update content? Archive if no longer relevant?
```

User can: update the `Last updated` date (confirming content is still valid), update the content, or archive the file.

**Config:**
- `staleness_threshold_months` (default: 6) — stored in `aria-knowledge.local.md`, configurable via `/setup` as an advanced option
- Single threshold for all categories — user can change the default, keeps it simple

### 8. Bidirectional Cross-Reference Linking (Rank 7)

Auto-suggests `## Related` cross-references between promoted files based on tag overlap. Runs as part of `/index` (and therefore also `/audit-knowledge`).

**Behavior in `/index`:**

After rebuilding the tag index (step 8), add a cross-reference pass:

1. For each promoted file, compute its tag set
2. Compare against all other promoted files — find pairs sharing 2+ tags (threshold avoids noise from single-tag overlap like `cs` appearing on everything)
3. Check each file's existing `## Related` section for already-linked files
4. Present **new** cross-reference suggestions only:
   ```
   ## Cross-Reference Suggestions

   approaches/api-pagination.md <-> decisions/003-cursor-vs-offset.md
   Shared tags: api, pagination
   Neither file references the other — add cross-links?

   references/stripe-webhook-patterns.md <-> guides/payments/checkout-flow.md
   Shared tags: stripe, cs
   checkout-flow.md already links to stripe-webhook-patterns.md — add reverse link?
   ```
5. On confirmation, append to each file's `## Related` section:
   ```markdown
   ## Related
   - [Cursor vs Offset Decision](../decisions/003-cursor-vs-offset.md)
   ```
6. If user declines, skip — no file changes

**Key details:**
- **2+ shared tags** threshold to avoid low-signal suggestions
- **Only suggests new links** — skips pairs already cross-referenced in either direction
- **Reverse link detection** — if A links to B but B doesn't link to A, suggests adding the reverse
- **Relative paths** in `## Related` so links work from any viewer (Obsidian, GitHub, etc.)
- **Non-destructive** — only appends to `## Related`, never modifies other sections

**Behavior in `/audit-knowledge`:**

Inherits this from the `/index` rebuild pass. Cross-reference suggestions are batched into the index health findings presentation alongside tag normalization, freeform promotion, and untagged file resolution.

### 9. Abbreviated Rule 22 Assessment for Planning Paths

Reduces Rule 22 hook friction for planning/spec work without disabling enforcement.

**Problem:** The PreToolUse/PostToolUse hooks require a full impact assessment on every Edit/Write. For planning docs (specs, design docs), the assessment is always "Low Impact — documentation" and the scope check is always "Scope PASS." This adds token overhead and friction without value.

**Solution:** The hooks detect file paths in designated planning directories and allow an abbreviated one-line assessment instead of the full framework output.

**Planning paths (hardcoded):**
- `docs/specs/`
- `docs/plans/`

**Protected filenames (always full enforcement regardless of path):**
- `CLAUDE.md` (any path)
- `working-rules.md`
- `change-decision-framework.md`
- `enforcement-mechanisms.md`
- `settings.local.json`
- `plugin.json`
- Any file inside the knowledge folder (`{knowledge_folder}/*`)

**Hook behavior:**

PreToolUse (Edit|Write):
1. Check file path against planning paths
2. If match AND filename is not protected → inject modified prompt: "Planning path — abbreviated assessment permitted"
3. Claude outputs: `Planning edit — [filename]`
4. If no match OR protected filename → full Rule 22 assessment (existing behavior)

PostToolUse (Edit|Write):
1. Same path/filename check
2. If planning path AND not protected → Claude outputs: `Scope OK — planning doc`
3. Otherwise → full scope check (existing behavior)

**Key properties:**
- **Enforcement never turns off** — hooks still fire on every edit, Claude still acknowledges
- **Habit preserved** — Claude still thinks about scope, just outputs less for known-safe paths
- **Protected filename safeguard** — operational files always get full enforcement even if placed in a planning directory
- **No config needed** — hardcoded paths, no user setting to forget to toggle back
- **Small hardcoded set** — can be expanded later if needed, but starts conservative

## Future Considerations (Rank 6)

**Rank 6 — Pre-edit knowledge injection (deferred):** Extend pre-edit hook to check file path against project-to-tag mappings, then scan index for matching docs. Deferred due to high token overhead on every edit cycle and noisy matching (a single file path could match many tags, surfacing 10+ docs). Needs real `/context` usage data to determine whether automated injection solves a real gap or just adds noise.

## Implementation Notes

### New files to create
- `plugin-claude-code/skills/index/SKILL.md` — the `/index` skill definition
- `plugin-claude-code/skills/context/SKILL.md` — the `/context` skill definition

### Files to modify
- `plugin-claude-code/skills/audit-knowledge/SKILL.md` — add cross-referencing, staleness action items, and index rebuild steps
- `plugin-claude-code/bin/session-start-check.sh` — add knowledge surfacing instruction to system message output
- `plugin-claude-code/template/README.md` — document `index.md` in the folder structure
- `plugin-claude-code/template/LOCAL.md` — add tag convention to format templates, document `/context` and `/index`
- `plugin-claude-code/.claude-plugin/plugin.json` — register new skills, update hook prompts, bump version

### Template updates
- Knowledge file format templates in `LOCAL.md` need `tags:` added to their frontmatter examples
- `README.md` folder taxonomy table needs `index.md` entry

### Config additions
- `freeform_promotion_threshold` (default: 3) — stored in `aria-knowledge.local.md`, configurable via `/setup` as an advanced option (not prompted by default in the setup wizard, but settable if user asks or re-runs setup)
- `staleness_threshold_months` (default: 6) — stored in `aria-knowledge.local.md`, configurable via `/setup` as an advanced option. Single threshold for all promoted categories

### Seeded tags storage
- Known tags live in `index.md` itself (in the `## Known Tags` section)
- Initial set is hardcoded in the `/index` skill for first-run generation
- After first run, `index.md` is the source of truth (skill preserves existing known tags on rebuild)
