# v1 Spec — `projects_shared_knowledge`

**Status:** Shipped 2026-04-29 in v2.13.0
**Target version:** 2.13.0 — released
**Implementation notes:** Shipped with three install-session design corrections layered on top of the original spec: (1) CLAUDE.md reference offer deferred from setup-time to `/audit-share` first-write to avoid aspirational forward references and accidental teammate-affecting edits; (2) `projects_groups`-aware container CLAUDE.md offer added as Step 6.5b for multi-repo projects; (3) `projects_shared_knowledge` config field changed from boolean to comma-separated tag list to support per-project opt-in (most users have many repos but only a few with teams). See CHANGELOG `[2.13.0]` entry for the full set of design dimensions.

## Mental model

Three knowledge tiers, opt-in for tier 2:

| Tier | Location | Visibility | Lifecycle |
|------|----------|-----------|-----------|
| **Personal** (existing) | `~/Projects/knowledge/` | One developer | Captured during sessions, promoted via `/audit-knowledge` |
| **Project-shared** (new) | `<repo>/_project-knowledge/` | All teammates with repo clone | Promoted from personal via `/audit-share`; commits flow through normal PR review |
| **Cross-repo aggregation** (read-side) | `/index` indexes team folders → `/context` surfaces them | All teammates with all repos | Read-only; rebuilt via `/index` after team folders change |

`audit-share` is the WRITE flow (personal → team copy). `/index` + `/context` is the READ flow (cross-repo discovery).

## Design decisions captured

The spec resolves these design questions (recorded for future-audit context):

| Q | Decision |
|---|----------|
| Q1 — Knowledge types in scope | All promoted types EXCEPT `feedback` and `references` (insights, decisions, approaches, rules, IDEAS-BACKLOG.md entries) |
| Q1a — Duplication policy | Personal copy stays; team copy is independent record. Both carry frontmatter back-pointers (`shared:` on personal, `origin:`/`shared_by:`/`shared_at:` on team copy) |
| Q1b — IDEAS-BACKLOG.md location | Migrates from `<project-root>/IDEAS-BACKLOG.md` → `<project-root>/_project-knowledge/IDEAS-BACKLOG.md` when team-share enabled (one-time, performed by `/audit-share` Step 7) |
| Q1c — `_project-knowledge/` internal structure | Flat (no per-type subfolders); only `cross/` subfolder for cross-cutting items |
| Q2 — Cross-detection heuristic | Frontmatter `project: cross` triggers the cross-repo destination prompt |
| Q3 — Config flag | `projects_shared_knowledge: true|false` (default false); `author_tag` field also added (e.g., `init`) |
| Q4 — Repo detection | projects_list-resolved path (per existing convention) |
| Q5 — Git behavior | `git add` only; user reviews + commits; no auto-commit |
| Q6 — Read-side | One-line session-start prompt + `/context` extension (third grouping); `_project-knowledge/` referenced from CLAUDE.md / CODEMAP.md / STITCH.md / knowledge index where relevant |
| Q7 — Sub-prompt label | "Add to shared knowledge? (yes / yes-cross / no / defer)" |
| Q8 — Source idea behavior | Moot under copy-not-move semantics |
| Q9 — Pointer format | Frontmatter only (no inline body lines) |
| Q10 — Excluded types | feedback (personal preferences), references (external pointers may not apply uniformly) |
| Q11 — Cross-cutting IDEAS-BACKLOG | `_project-knowledge/cross/IDEAS-BACKLOG.md` (preserves queue model) |
| Q12 — Audit-share scope | Separate skill `/audit-share` (alias `/share-audit`); standalone invocation; not inline during `/audit-knowledge`; offered post-setup as initial sweep |
| Q13 — `cross` / `no-project` items | `cross`: prompt for destination repo. `no-project`: skip team-share. |
| M2 — UX pattern | Batch-review (scan → suggest → summarize → user approves all/numbers/modify/skip), not per-item prompt |
| Read-side mechanism | `/index` extension (Phase 5) scans `_project-knowledge/`; `/context` reads it via existing index-driven discovery — STITCH untouched |

## Config additions to `~/.claude/aria-knowledge.local.md`

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `projects_shared_knowledge` | bool | `false` | Master enable for the feature; gates everything else |
| `author_tag` | string | (empty) | Required when feature enabled; e.g., `init` or initials. Prompted by setup; falls back to git config user.name initials at runtime if missing |

## Folder + filename conventions

Per repo (when feature enabled):

```
<repo-root>/
  _project-knowledge/
    README.md                                    # auto-created on first write — convention explainer
    IDEAS-BACKLOG.md                             # migrated from <repo-root>/IDEAS-BACKLOG.md on first audit-share
    2026-04-28-init-feature-rename.md            # repo-scoped knowledge entry
    2026-04-28-init-deploy-flow-fix.md
    cross/
      IDEAS-BACKLOG.md                           # cross-repo idea queue (separate from repo-scoped)
      2026-04-28-init-shared-design-pattern.md   # cross-repo knowledge entry
```

- **Folder `_project-knowledge/`** — leading underscore sorts to top of repo listings; NOT hidden; tool-agnostic name (non-ARIA teammates can read/write)
- **Filename `{YYYY-MM-DD}-{author}-{slug}.md`** — date is the **share date** (not original capture date); author is `author_tag`; slug derived from origin filename or title; collisions resolved via `-2`, `-3` suffix
- **README** auto-created on first write with a 10-line template explaining the convention to non-ARIA teammates

## Frontmatter contract

**Personal copy** (in `~/Projects/knowledge/`):

```yaml
---
# ...existing fields preserved...
shared:
  - path: <repo>/_project-knowledge/2026-04-28-init-foo.md
    date: 2026-04-28
---
```

(Array because the same personal item could be re-shared to multiple repos over time.)

**Team copy** (in `<repo>/_project-knowledge/`):

```yaml
---
title: Foo
date: 2026-04-28           # share date
origin: knowledge/insights/foo.md
shared_by: init
shared_at: 2026-04-28
project: proj-a            # repo tag, or "cross" for cross/ subfolder
tags: [...]                # carried from origin
---
```

## `audit-share` skill — `plugin/skills/audit-share/SKILL.md` (new)

Alias: `share-audit`. Pattern matches `audit-config`/`config-audit`.

### Step 1 — Resolve config
Read `~/.claude/aria-knowledge.local.md`. Require `projects_shared_knowledge: true` + non-empty `author_tag`. Stop with helpful prompt otherwise.

### Step 2 — Scan candidates
Walk:
- `{knowledge_folder}/insights/`, `decisions/`, `approaches/`, `rules/`
- `{knowledge_folder}/projects/<tag>/` for each tag in `projects_list`
- `<project-root>/IDEAS-BACKLOG.md` (pre-feature) or `<project-root>/_project-knowledge/IDEAS-BACKLOG.md` (post-feature) for each project

Skip files where frontmatter `shared:` already includes the target path. Skip `feedback` + `references` types entirely.

### Step 3 — Suggest per candidate
For each:
- Read frontmatter `project:` field
- `cross` → recommend share-to-cross (need user to pick destination repo at execute time)
- Project tag matches `projects_list` entry → recommend share-to-{project}
- Otherwise → recommend skip
- Compute target path
- Detect public-repo flag via `gh repo view --json visibility` (per repo, cache for session)

### Step 4 — Present batch summary

```
audit-share — found N candidates

## Recommended: share to repo (X)
1. knowledge/insights/foo.md → <project-root-of-proj-a>/_project-knowledge/2026-04-28-init-foo.md
2. ...

## Recommended: share to cross (Y)
9. knowledge/approaches/api.md (project: cross) → ⚠️ pick destination repo
...

## Recommended: skip (Z)
12. knowledge/feedback/bar.md — feedback type, not in scope
...

⚠️ T of these target public repos: <repo-name>

Decide: all / numbers / modify N / skip
```

### Step 5 — User decision
- `all` — execute all recommended actions
- `numbers` (e.g., `1 3 9`) — execute only specified items
- `modify N` — sub-prompt for item N: change action / change destination repo / edit slug
- `skip` — cancel without executing

### Step 6 — Execute approved actions
Per item:
1. Resolve destination (prompt for cross-target if needed)
2. **Sanitization warn-prompt** for public-repo targets:
   ```
   ⚠️ Target repo "<repo-name>" is public — confirm content has no secrets / internal URLs / personal names? (yes / no / show file)
   ```
3. Read source, strip personal-only fields, add team-copy frontmatter (`origin`, `shared_by`, `shared_at`)
4. Write team copy at target path
5. Update personal copy frontmatter (append `shared:` array entry)
6. Auto-create `_project-knowledge/README.md` if first write to this folder
7. `git add` new file (NO commit — user reviews)

### Step 7 — IDEAS-BACKLOG.md migration (one-time per repo)
On first audit-share when team-share enabled, if `<repo-root>/IDEAS-BACKLOG.md` exists AND `<repo-root>/_project-knowledge/IDEAS-BACKLOG.md` does NOT — `git mv` (or filesystem mv if untracked) from project root → `_project-knowledge/`. Audit-knowledge SKILL.md disposition row's conditional location language already accounts for this transition.

### Step 8 — Report
```
## audit-share complete

- N reviewed
- A shared (A1 to repo / A2 to cross / A3 modified-and-shared)
- B skipped (B1 user-declined / B2 not-in-scope / B3 sanitization-blocked)
- C deferred — re-prompt next invocation

Targets written:
- <repo-1>/_project-knowledge/<files>
- <repo-2>/_project-knowledge/<files>

Next steps:
- Review staged changes: cd <repo> && git diff --cached
- Commit and push when ready
- Run /index to refresh tag index with new files
- Run /context <project-tag> to verify discovery works
```

## `/index` extension — `plugin/skills/index/SKILL.md`

New Phase 5 (after current Phase 4 project-tier scan): scan `_project-knowledge/` folders.

For each tag in `projects_list`:
1. Resolve project root path
2. Probe `<root>/_project-knowledge/`; skip if absent
3. Glob `_project-knowledge/**/*.md` (excluding `README.md`)
4. For each file: read frontmatter (`tags:`, `project:`); add to tag index with category `team-shared` (or `team-shared-cross` if path includes `/cross/`)

Result: tag index includes team-shared entries alongside personal + project entries; same query path. No new file format.

## `/context` extension — `plugin/skills/context/SKILL.md`

**Step 4c (new):** read team-shared category entries from the index, filter by query tags using existing union/intersection rules.

**Step 5 presentation:** grow a third grouping above the existing two — order is **Team-shared → Project-specific → Cross-project**, single continuous numbering across all three:

```
Found N files matching: [tags]

## Team-shared (T files)
1. <repo>/_project-knowledge/2026-04-28-init-foo.md — Foo [proj-a, css]

## Project-specific (M files)
2. projects/proj-a/decisions/004-state.md — State sync [proj-a]

## Cross-project (K files)
3. approaches/api.md — Pagination [api]

Load which files? (all / numbers / none)
```

Section omission rules apply (zero-results section omitted entirely).

## Setup skill update — `plugin/skills/setup/SKILL.md`

After projects-tier setup, add a "shared knowledge" enable step:

```
Enable shared knowledge feature? [y/N]
  Personal knowledge stays in ~/Projects/knowledge/ (unchanged).
  Team knowledge gets copied to <repo>/_project-knowledge/ via /audit-share.
  Opt-in; can disable later.

> y

Your author tag for shared-knowledge filenames? (e.g., 'init', initials)
  Used in filenames like 2026-04-28-init-foo.md.
  Default: derived from git config user.name → 'init'

> [user input or accept default]

Add `_project-knowledge/` references to your project CLAUDE.md files? [Y/n]
  Helps non-ARIA teammates discover the convention.

> Y

Run /audit-share now to share existing personal knowledge with relevant projects? [Y/n]

> Y    # (invokes audit-share inline if confirmed)
```

Each prompt skipped if `projects_enabled: false`.

## Documentation cascade

| File | Change |
|------|--------|
| `OVERVIEW.md` | Add "Shared knowledge" section under tier model |
| `QUICKSTART.md` | Add `/audit-share` line + note that `/context` shows team-shared |
| `template/README.md` | (No directory tree change — user knowledge folder unchanged) |
| `template/intake/ideas/README.md` | Note IDEAS-BACKLOG.md location switch when feature enabled |
| `audit-knowledge/SKILL.md` | Update L118 disposition row to reference conditional IDEAS-BACKLOG.md location |
| `index/SKILL.md` | Phase 5 spec |
| `context/SKILL.md` | Step 4c + Step 5 grouping update |
| `setup/SKILL.md` | Three new prompts + audit-share inline invocation |
| **New:** `audit-share/SKILL.md` | Full skill spec |

## CHANGELOG `[2.13.0] — 2026-04-28`

```markdown
### Added
- `projects_shared_knowledge` opt-in feature for team-shared project knowledge
- `audit-share` skill (alias `share-audit`) — batch-review personal knowledge for sharing
- `_project-knowledge/` folder convention per project (with `cross/` for cross-cutting items)
- Filename convention `{YYYY-MM-DD}-{author}-{slug}.md` with frontmatter origin/shared back-pointers
- `/index` Phase 5 — scans `_project-knowledge/` folders into the tag index
- `/context` "Team-shared" presentation grouping (third tier)
- Auto-created `_project-knowledge/README.md` template explaining convention to non-ARIA teammates
- Public-repo sanitization warn-prompt at share-time

### Changed
- IDEAS-BACKLOG.md migrates from `<project-root>/` → `<project-root>/_project-knowledge/` when team-share enabled (one-time, performed by `/audit-share`)
- Setup skill prompts for `projects_shared_knowledge` + `author_tag` when enabling
```

## Version bump

`plugin/.claude-plugin/plugin.json`: 2.12.2 → 2.13.0 (minor — structural addition, opt-in, backward-compatible)
`marketplace.json`: auto-synced via release.sh

## Implementation order

| Phase | Step |
|-------|------|
| 1 | New `audit-share` skill spec |
| 2 | `/index` Phase 5 spec extension |
| 3 | `/context` Step 4c + Step 5 update |
| 4 | Setup skill enable + author_tag prompts |
| 5 | Audit-knowledge L118 disposition row update |
| 6 | Doc cascade (OVERVIEW, QUICKSTART, ideas/README) |
| 7 | CHANGELOG entry + plugin.json version bump |
| 8 | Release flow via release.sh |

## Out of scope for v1 (deferred to v2.x)

- STITCH integration with team-knowledge bridges (current v1 uses /index aggregation alone)
- Cross-repo dedup logic at read time
- Auto-sanitization scanner (regex patterns for secrets, emails, URLs) — v1 ships warn-prompt only
- Retroactive scan UX refinements (audit-share covers retroactive via batch sweep; further cleanup deferred)
- Multi-developer write-conflict resolution beyond default git merge

## Spec authorship

Drafted 2026-04-28 from a multi-round design discussion: team-share concept proposed → repo-as-substrate confirmed → uniform `_project-knowledge/` + federated `cross/` settled → folder name + filename convention finalized → batch-review UX selected over per-item prompts → /index extension chosen as the read-side mechanism (instead of STITCH integration). Full conversation persisted in session transcript; this doc captures the resulting spec.
