---
name: index
description: 'Rebuild the knowledge tag index. Scans promoted files, normalizes tags, flags untagged files, suggests freeform-to-known promotions, detects stale files, and regenerates index.md. Use when user says "/aria-cowork:index", "rebuild index", "update index", "reindex knowledge". (Cowork variant — namespaced-only.)'
---

# /index — Knowledge Index Builder

Scan all promoted knowledge files, normalize tags, detect issues, and regenerate `<knowledge_folder>/index.md`.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Cowork variant — namespaced-only. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/index` resolves to aria-knowledge's variant — Code is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. To reach this skill, use the namespaced form: `/aria-cowork:index`. Do NOT match bare `/index` — that belongs to aria-knowledge.

**Before Step 0:** Check whether the `Bash` tool is available in this session. If `Bash` IS available (you are running in Claude Code or another runtime with shell access), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-cowork's `/index` from a runtime with shell access.**
>
> Behavior is largely the same in both runtimes; for the Code-native variant (uses Bash for stat-based staleness detection and supports `projects_shared_knowledge`), use `/index` (the aria-knowledge canonical).
>
> **Use `/index` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `index` (the bare-slash canonical, which routes to aria-knowledge when both ports are loaded) with the same arguments the user provided to this invocation. Do not proceed with this skill's steps; the aria-knowledge variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-cowork) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args.

If `Bash` is NOT available (normal Cowork runtime), proceed to Step 0.

## Step 0: Resolve config

The default knowledge folder is `~/Projects/knowledge/` (expand `~` to your home directory's absolute path). Read `<knowledge_folder>/aria-config.md` and extract:
- `knowledge_folder` — the absolute path (used for index entries that need cross-surface portability)
- `freeform_promotion_threshold` — minimum file count before suggesting promotion (default: 3 if not set)
- `staleness_threshold_months` — months before flagging stale (default: 6)

If `aria-config.md` doesn't exist, stop: *"aria-cowork is not configured. Run `/aria-setup` to get started."*

Use `<knowledge_folder>` for all file operations during this session.

**Phase 1 note:** Project-tier scan and team-shared `_project-knowledge/` scan are deferred to Phase 2+. v0.1.0 indexes cross-project files only (approaches/, decisions/, guides/, references/).

## Step 1: Scan promoted folders

Scan these directories for `.md` files (excluding directory README stubs):
- `<knowledge_folder>/approaches/`
- `<knowledge_folder>/decisions/`
- `<knowledge_folder>/guides/` (recursive — guides may have subdirectories)
- `<knowledge_folder>/references/`

**Do NOT scan:** `archive/`, `intake/`, `rules/`, `logs/`, root-level files (`README.md`, `LOCAL.md`, `OVERVIEW.md`, `index.md`).

For each `.md` file found:
1. Read the file.
2. Extract YAML frontmatter (content between `---` markers at the top).
3. From frontmatter, extract:
   - `tags:` — array of tags (e.g., `tags: [api, pagination]`). If missing, record as untagged.
   - `Last updated:` — date string (YYYY-MM-DD). If missing, record as unknown.
   - `semantic-hints:` — array of free-form phrases (e.g., `semantic-hints: ["stakeholder framing for new initiative", "exec summary template"]`). Optional; if missing, treat as empty list. Added v0.3.0 (parity with aria-knowledge v2.16.0).
4. Extract the first `#` heading as the file's description.
5. Store: `{path, tags[], hints[], description, last_updated}`.

Report: *"Scanned N files in approaches/, decisions/, guides/, references/."*

## Step 2: Read existing index

Read `<knowledge_folder>/index.md` if it exists.

Extract:
- `## Known Tags` section — current canonical tag vocabulary (comma-separated).

If `index.md` doesn't exist (first run), use the seeded known tags:

```
api, architecture, database, deployment, security, performance, accessibility, testing, process, decision-framework, enforcement, claude-cowork, aria, knowledge-management
```

## Step 2b: Read and validate aliases (added v0.3.0 — parity with aria-knowledge v2.16.0)

Read `<knowledge_folder>/aliases.md` if it exists.

Parse the alias map: each line matching the pattern `` - `<alias>` → `<canonical>` `` contributes one entry. The alias and canonical are the backtick-quoted strings; whitespace around the arrow is tolerated; non-matching lines (headers, comments, blank lines) are ignored.

If the file doesn't exist OR contains no parseable entries, treat the alias map as empty and continue to Step 3.

**Chain check (internal to the alias map):** if any canonical name in the parsed map ALSO appears as an alias key in another entry of the same map, abort `/index` with:

> *"Alias chain detected: `x` → `y` → `z` in aliases.md. Aliases must point directly to a canonical tag, not to another alias. Fix the chain (typically: rewrite the intermediate alias to point at the final canonical) and re-run `/aria-cowork:index`."*

**Collision check (against Step 1's per-file tag data):** for each alias `a` in the parsed map, scan the per-file `tags[]` arrays collected in Step 1. If any file declares `a` in its `tags:` frontmatter, abort `/index` with:

> *"Alias `a` in aliases.md collides with existing tag `a` used in N file(s): <comma-separated paths>. Either remove the alias from aliases.md or rename the tag in those files."*

On successful validation, retain the alias map for Step 8 (Known Tags annotation). The map is also consumed by `/context` Step 2.5 (which reads it from the `## Known Tags` section's `[aliases: ...]` annotations, not from `aliases.md` directly).

## Step 3: Tag normalization

Compare all tags found across scanned files. Detect similar tags using these heuristics:
- **Plural/singular:** `api` vs `apis`, `test` vs `tests`
- **Hyphen variants:** `react-native` vs `reactnative` vs `react native`
- **Common abbreviations:** `db` vs `database`, `infra` vs `infrastructure`

For each pair of similar tags, check which is in the Known Tags set. If one is known and the other isn't, the known one is the normalization target. If both are unknown, prefer the more common one (appears on more files).

**Present conflicts to user:**

```
## Tag Normalization

Found similar tags:
1. `apis` (1 file) → normalize to `api` (4 files)? [y/n]
2. `reactnative` (1 file) → normalize to `react-native` (2 files)? [y/n]
```

For each user-confirmed normalization, edit the source files to update their `tags:` frontmatter.

## Step 4: Freeform tag promotion

Identify freeform tags (not in Known Tags) that appear on `freeform_promotion_threshold` or more files.

**Exclude ephemeral tags before applying the threshold.** Session/phase/plan stamps recur across many files (so they hit the threshold) but are NOT durable concepts and should never become Known Tags. Drop any candidate whose **whole tag** matches one of these patterns (case-insensitive) before counting:

- `^s\d+$` — session stamps (`s4`, `s60`, `s82`)
- `^p-?\d+$` — plan / work-item ids (`p-23`, `p23`)
- `^phase-?\d+$` — phase stamps (`phase-3`, `phase3`)
- `^plan-\d+[a-z]?$` — plan ids (`plan-01a`)
- literal denylist: `future-session-plan`, `soft-launch`

This suppresses AUTO-promotion suggestions only — **not a hard ban** (a user can still hand-add any of these to Known Tags, and a Known tag never re-enters the freeform pool). Because a pattern could occasionally match a real concept, **surface the skipped set** (not silent) so a false-positive can be rescued:

```
Skipped N ephemeral tag(s) from promotion (session/phase/plan stamps): s82, s75, phase-3, … — hand-add to Known Tags if any is actually a durable concept.
```

```
## Freeform Tag Promotions

These tags appear on enough files to consider adding to Known Tags:
1. `cowork` (5 files) → add to Known Tags? [y/n]
2. `mcp` (3 files) → add to Known Tags? [y/n]
```

For each user-confirmed promotion, add the tag to the Known Tags list.

## Step 5: Untagged files

List files with empty or missing `tags:` frontmatter.

```
## Untagged Files

These files have no tags and won't surface in /context:
1. approaches/some-pattern.md
2. guides/setup-thing.md

Suggest tags? (y to walk through each, n to skip)
```

If yes, walk through each file: read content, propose 1-3 tags based on content, edit frontmatter on user confirmation.

## Step 6: Stale files

Identify files whose `Last updated:` is older than `staleness_threshold_months` months ago (or missing entirely).

```
## Stale Files

These files haven't been updated in 6+ months:
1. references/some-old-tool.md (last updated 2025-09-15, 8 months ago)
2. guides/legacy-deployment.md (last updated unknown — no `Last updated:` header)

Review needed. Run /audit-knowledge (v0.2.0) to triage, or update manually.
```

Stale files are surfaced for awareness only. Don't auto-archive or auto-modify.

## Step 7: Cross-reference suggestions

For each tag with 2+ files, suggest cross-reference linking:

```
## Cross-References

Files sharing tags but not cross-linked:
1. approaches/api-pagination.md ↔ decisions/003-cursor-vs-offset.md (both tagged: api, pagination)
   Suggest: add Related section linking the other?
```

Cross-references are suggestions, not auto-applied. User runs through them as desired.

## Step 8: Regenerate index.md

Write `<knowledge_folder>/index.md`:

```markdown
---
generated_by: aria-cowork /index
generated_at: YYYY-MM-DD
---

# Knowledge Index

## Known Tags

api, architecture [aliases: arch], database, ...

(Canonical tags with aliases declared in `aliases.md` are annotated inline: `tag [aliases: alias1, alias2]` enumerates all aliases pointing to that canonical. Tags with no aliases appear without annotation. The flat tag list is comma-separated. `/context` reads these annotations to build its alias→canonical map at query time. Added v0.3.0 — parity with aria-knowledge v2.16.0.)

## Tag Index

### api
- approaches/api-pagination.md — Cursor-based pagination patterns
- decisions/003-cursor-vs-offset.md — Why we chose cursor pagination
- references/stripe-webhook-patterns.md — Webhook signature verification

### architecture
- approaches/microservices-pattern.md — When to split services
- decisions/004-monolith-first.md — Why we kept the monolith

[... all known tags with their files]

## Other Tags

[Freeform tags that haven't been promoted, with their files]

## Semantic Hints Index

### [hint phrase]
- relative/path/to/file.md

(Repeat for each unique hint phrase declared across promoted files, sorted alphabetically by phrase. Each file appears under every hint it declares. Hint phrases are stored verbatim from frontmatter — `/context` does the case-insensitive + hyphen-normalized substring match at query time. Omit this section entirely if no files declare `semantic-hints:`. Added v0.3.0 — parity with aria-knowledge v2.16.0.)

## Untagged Files

[Files with no tags — surfaced from Step 5]

## Stale Files

[Files older than staleness_threshold_months — surfaced from Step 6]
```

## Step 9: Report

```
## Index Rebuild Complete

- Scanned: N files
- Known tags: M (added: K via promotion)
- Freeform tags: F (suggested for promotion: P)
- Untagged files: U
- Stale files: S
- Tag normalizations applied: T

Index written to <knowledge_folder>/index.md.
```

## Rules

- **Read the file before editing it** — never modify a file's frontmatter without reading and confirming current contents.
- **User confirms every change** — tag normalizations, freeform promotions, untagged-file tag suggestions all require explicit user yes per item.
- **Stale-file surfacing is informational** — don't auto-archive or auto-modify based on staleness.
- **Idempotent** — re-running `/index` on an unchanged folder produces an identical `index.md`.
- **Use Cowork's native I/O** — never invoke a Filesystem MCP connector (per ADR-003).
- **Phase 2+ features**: project-tier scan (`projects/{tag}/**`), team-shared scan (`_project-knowledge/`), and multi-repo `projects_groups` traversal are NOT in v0.1.0. They land when the projects/ tier and shared-knowledge infrastructure ship.
