---
description: "Batch-review personal knowledge for promotion to team-shared project knowledge. Walks insights/decisions/approaches/rules and IDEAS-BACKLOG.md entries, recommends a target _project-knowledge/ destination per item, and lets the user approve all/numbers/modify/skip. Use when user says '/audit-share', '/share-audit', 'share knowledge', 'promote to team', 'sync to shared knowledge', or after enabling the projects_shared_knowledge feature."
argument-hint: ""
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# /audit-share — Batch-Review Personal Knowledge for Team Sharing

Walk personal knowledge files and IDEAS-BACKLOG.md entries; recommend a target `_project-knowledge/` destination per item; present a batch summary; let the user approve, modify, or skip.

## Step 0: Resolve Config

Read `~/.gemini/antigravity/aria-knowledge.local.md` and extract:

- `knowledge_folder` — required
- `projects_enabled` — required (must be `true`)
- `projects_list` — required (parsed into tag→path map)
- `projects_shared_knowledge` — required (comma-separated tag list; non-empty list of tags from `projects_list`); each tag in the list is a project enabled for shared knowledge
- `author_tag` — required (non-empty); fall back to deriving from `git config user.name` (first 2 chars of first + first 2 chars of last) if missing

If the config file doesn't exist: *"aria-knowledge is not configured. Run /setup to get started."*

If `projects_shared_knowledge` is empty/missing (or the legacy literal `true`): *"Shared knowledge has no projects enabled. Run /setup and pick which projects to enable in the 'Which projects do you want to enable shared knowledge for?' prompt."*

If `projects_enabled: false` or `projects_list` empty: *"Shared knowledge requires the project tier. Run /setup to enable projects and configure your project list."*

If `author_tag` is missing AND no derivable git user.name: *"Author tag is required. Set `author_tag` in `~/.gemini/antigravity/aria-knowledge.local.md` (e.g., `init`) or configure `git config user.name`."*

## Step 1: Scan Candidates

Walk these directories under `{knowledge_folder}/`:

- `insights/`
- `decisions/`
- `approaches/`
- `rules/`
- `projects/<tag>/` for each tag in `projects_shared_knowledge` (the per-project opt-in list — projects not in this list stay personal-tier and are skipped here)

Plus IDEAS-BACKLOG.md entries from each project root:

- For each tag in `projects_shared_knowledge`, resolve to project root via `~/Projects/<path>` (where `<path>` is the corresponding `projects_list` value).
- Probe `<project-root>/_project-knowledge/IDEAS-BACKLOG.md` first (post-feature location).
- Fall back to `<project-root>/IDEAS-BACKLOG.md` (pre-feature location, will trigger Step 7 migration on first execute).
- Parse the file by `### YYYY-MM-DD — {title}` headers; treat each section as a candidate "entry."

**Skip candidates** when:

- File frontmatter contains a `shared:` array with an entry whose `path` matches the proposed target. (Already shared; no action needed.)
- File type is `feedback` or `references` (out of scope per design Q10 — feedback memories tend to be personal preferences; references are pointers to external systems that may not apply uniformly to teammates).

## Step 2: Suggest Action Per Candidate

For each candidate, determine:

1. **Project tag(s)** — derived from any of three sources, unioned (matches `/index` Phase 4 Decision #9 path-derived convention so audit-share and /index see the same tag set):
   - **Path-derived:** if file path is under `{knowledge_folder}/projects/<tag>/`, that `<tag>` is implicit (even if not in YAML frontmatter).
   - **Frontmatter `project:` field** if present (split on `,` for multi-value).
   - **Frontmatter `tags:` array:** any tag matching a project in `projects_shared_knowledge` is treated as a share signal. A file tagged `[architecture, cs, ss]` with `cs,ss` in `projects_shared_knowledge` produces TWO share recommendations (one to cs, one to ss) — multi-tag files generate one recommendation per matching project, with independent destinations.
   - The literal value `cross` (in any source) marks the file as cross-cutting within its product group, not as cross-PROJECT-GROUP. Cross-PROJECT-GROUP relevance is naturally expressed by multi-tag (e.g., `[cs, ss]` = relevant to both cs and ss product groups) and is handled by the multi-tag fan-out above, not by `cross`.
2. **Recommended action** (per recommendation produced in step 1):
   - Tag is `cross` → recommend **share-to-cross** (will need user to pick destination repo at execute time, since cross items can land in any repo's `cross/` subfolder; cross destinations may be any tag from `projects_shared_knowledge`).
   - Tag matches a tag in `projects_shared_knowledge` → recommend **share-to-{project}**.
   - Tag exists in `projects_list` but is NOT in `projects_shared_knowledge` → recommend **skip** with reason "project not enabled for shared knowledge (use `/setup` to enable)".
   - Otherwise (no tag detected, or tag not in projects_list) → recommend **skip**.
3. **Target path** — compute as follows. Multi-repo projects (those with a `projects_groups` entry) require sub-repo selection because the projects_list path resolves to a container, not a git repo:
   - **Single-repo project** (no `projects_groups[tag]` entry):
     - Repo-scoped: `<project-root>/_project-knowledge/<YYYY-MM-DD>-<author_tag>-<slug>.md`
     - Cross-stack: `<destination-repo-root>/_project-knowledge/cross/<YYYY-MM-DD>-<author_tag>-<slug>.md`
   - **Multi-repo project** (`projects_groups[tag]` is set, listing role:sub-repo pairs like `backend: foo-backend`, `web: foo-web`, `mobile: foo-mobile`):
     - Run **role-detection heuristic** on file content + frontmatter tags:
       - **backend keywords:** django, flask, fastapi, server-side, api, endpoint, jwt, oauth, auth, idor, impersonation, sql, database, migration, model, view, serializer, drf, rest, graphql resolver
       - **web keywords:** nextjs, next.js, react, frontend, client-side, app router, spa, redux, rtk, rtk-query, css, tailwind, ui component, hook, page, route component
       - **mobile keywords:** ios, android, react native, expo, swift, kotlin, swiftui, jetpack
       - Plus any **custom roles** defined in `projects_groups[tag]` — match keywords from the role name itself plus inferable tokens.
       - Score = count of matching keywords per role (case-insensitive whole-word match against body + tags).
       - **Single dominant role** (one role's score is ≥2× the next, AND ≥3 hits): recommend that role's sub-repo, repo-scoped destination.
       - **Multiple roles tied or all low scores**: recommend cross-stack → **primary sub-repo's `_project-knowledge/cross/`**.
       - **Primary sub-repo** = first role declared in `projects_groups[tag]` (declaration order, NOT alphabetical), OR an explicit `primary:` field if user has added one to the group entry. For Mike's example `cs: { backend: commonspace-app, web: commonspace-ui-v3, mobile: commonspace-mobile-ui }`, primary is `commonspace-app`.
     - Multi-repo paths:
       - Repo-scoped (dominant role detected): `<project-root>/<role-sub-repo>/_project-knowledge/<YYYY-MM-DD>-<author_tag>-<slug>.md`
       - Cross-stack (no dominant role): `<project-root>/<primary-sub-repo>/_project-knowledge/cross/<YYYY-MM-DD>-<author_tag>-<slug>.md`
   - **Common to both shapes:**
     - **Date** is today (the share date), not the original capture date.
     - **Author** is `author_tag` from config.
     - **Slug** is derived from the source filename (strip date prefix and extension) or from frontmatter `title:`.
     - **Collision handling**: if the target path already exists, append `-2`, `-3`, etc. to the slug until unique.
4. **IDEAS-BACKLOG.md entries** are special-cased: each entry promotes by appending to the project's IDEAS-BACKLOG.md, not by creating a new file. Path resolution mirrors step 3's single-vs-multi-repo logic — single-repo: `<project-root>/_project-knowledge/IDEAS-BACKLOG.md`; multi-repo: `<project-root>/<primary-sub-repo>/_project-knowledge/IDEAS-BACKLOG.md` (always primary, since IDEAS-BACKLOG entries are project-wide queue items not per-role). Cross-cutting ideas append to `cross/IDEAS-BACKLOG.md` instead.
5. **Public-repo flag** — for each unique target sub-repo (not container), run `gh repo view --json visibility 2>/dev/null` (cache result for the session). If visibility is `PUBLIC`, mark target as needing sanitization warn-prompt at execute time. If `gh` is unavailable, skip the check (do not block); note in summary as "could not verify repo visibility."

## Step 3: Present Batch Summary

Group recommendations by action; number continuously across groups; flag public-repo targets:

```
audit-share — found N candidates not yet in shared knowledge

## Recommended: share to repo (X)
1. knowledge/insights/foo.md (project: proj-a)
   → ~/Projects/<path>/_project-knowledge/2026-04-28-init-foo.md
2. knowledge/decisions/008-bar.md (project: proj-a)
   → ~/Projects/<path>/_project-knowledge/2026-04-28-init-bar.md
   ⚠️ public repo — content-safety prompt at execute time
3. ...

## Recommended: share to cross (Y)
9. knowledge/approaches/api.md (project: cross)
   → ⚠️ pick destination repo at execute time
10. ...

## Recommended: skip (Z)
12. knowledge/feedback/baz.md — feedback type, not in scope
13. knowledge/insights/qux.md — no project tag, no destination
...

⚠️ T of these target public repos: <repo-1>, <repo-2>

Decide:
  all                 — execute all recommended actions
  numbers (1 3 5)     — execute only specified items
  modify N            — change action / destination / slug for item N
  skip                — cancel without executing
```

**Section omission**: omit a heading entirely if its count is zero. If no candidates at all, skip Steps 4-7 and report: *"No candidates to share — all eligible knowledge is already shared or out of scope."*

## Step 4: User Decision

Wait for user input. Parse:

- `all` — proceed with all recommendations from Steps 1-3.
- Space- or comma-separated numbers (e.g., `1 3 9` or `1,3,9`) — proceed only with those items.
- `modify N` — sub-prompt for item N:
  - *"What would you like to change for item N? [action / destination / slug / skip]"*
  - Apply the change; re-summarize the modified item; wait for confirmation; then continue to Step 5.
- `skip` — cancel without executing; jump to Step 8 with a "user-cancelled" report.

## Step 5: Execute Approved Actions

For each approved item, execute in order:

1. **Resolve cross destination** (only if action is share-to-cross and destination not yet set): prompt *"Pick destination repo for cross item: <list of projects_shared_knowledge entries>"*. For multi-repo projects, the cross destination further resolves to that project's primary sub-repo's `_project-knowledge/cross/` folder (not the container). Update target path accordingly.
2. **Sanitization warn-prompt** (only if target repo is public):
   ```
   ⚠️ Target repo "<repo-name>" is PUBLIC.
   Source file: <personal-path>
   Confirm content has no secrets / internal URLs / personal names? [yes / no / show-file]
   ```
   - `yes` — proceed.
   - `no` — skip this item; record as `sanitization-blocked` in the summary.
   - `show-file` — print full file body for review; re-prompt yes/no.
3. **Read source file** — full content with frontmatter.
4. **Build team copy**:
   - Strip personal-only frontmatter fields (e.g., `originSessionId`, `name`, `description`, internal session IDs).
   - Add team-copy fields: `origin: <relative-path-from-knowledge-folder>`, `shared_by: <author_tag>`, `shared_at: <YYYY-MM-DD>`, `project: <repo-tag-or-cross>`.
   - Preserve `title:`, `tags:`, body content as-is.
5. **Write team copy** at target path (Step 2's computed path). For IDEAS-BACKLOG.md entries, append the section to the target file rather than creating a new file.
6. **Update personal copy frontmatter** — add an entry to the `shared:` array:
   ```yaml
   shared:
     - path: <repo>/_project-knowledge/2026-04-28-init-foo.md
       date: 2026-04-28
   ```
   If the array doesn't exist, create it. If it exists, append (don't overwrite — supports re-sharing to multiple repos over time).
7. **Auto-create README.md** if this is the first write to this `_project-knowledge/` folder (folder was empty or didn't exist before). Use the template from Step 6 below.
8. **`git add`** the new/changed files. The git operation must run **inside the destination sub-repo's working tree** (`<sub-repo-root>` for multi-repo projects, `<project-root>` for single-repo) — running `git add` from a non-repo container directory silently no-ops. Use `git -C <sub-repo-root> add <relative-path>` to make the working-tree explicit. **Do NOT commit** — user reviews and commits via normal flow.

## Step 6: README Template (Auto-Created on First Write)

When the first file is written to a repo's `_project-knowledge/` folder, create `README.md` alongside it with this content:

```markdown
# _project-knowledge/

This folder holds team-shared project knowledge promoted from individual developers' personal knowledge captures.

**Convention:**
- Files use `{YYYY-MM-DD}-{author-tag}-{slug}.md` naming (e.g., `2026-04-28-init-foo.md`).
- Each file's frontmatter includes `origin:` (where it came from), `shared_by:` (who promoted it), and `shared_at:` (when).
- The `cross/` subfolder holds cross-cutting knowledge that applies across multiple repos in the same product group.
- `IDEAS-BACKLOG.md` is a queue of unscheduled future work — entries are dated sections.

**Tooling (optional):**
- These files are plain markdown — readable and editable without any tool.
- The ARIA Claude Code plugin (https://github.com/mikeprasad/aria-knowledge) provides:
  - `/audit-share` to promote personal knowledge here
  - `/index` + `/context` to discover and load these files into Claude sessions
- Non-ARIA teammates can read and write directly; no tool dependency.

**Contributing:**
- Edit personal knowledge in your own knowledge store, then promote via `/audit-share` (or copy manually).
- Direct edits to files in this folder are fine; commit through normal PR review.
```

## Step 6.5: CLAUDE.md Reference Offer (First-Write Hook, Per Repo)

The first time `audit-share` writes to a repo's `_project-knowledge/` folder (same trigger as Step 6's README auto-create), offer to add a `_project-knowledge/` reference to that repo's `CLAUDE.md` so non-ARIA teammates can discover the convention. This used to be a setup-time batch prompt; it was deferred here so the documentation appears alongside the first real share rather than as an aspirational forward reference.

Per-repo, gated by these conditions in order:

1. **Probe** for `<repo-root>/CLAUDE.md`. If absent, skip silently (don't auto-create).
2. **Probe** for an existing `## Team-Shared Knowledge` heading inside the CLAUDE.md (or a previous reference to `_project-knowledge/`). If present, skip silently (already documented; don't append again on re-shares).
3. **Detect git tracking** via `git -C <repo-root> ls-files --error-unmatch CLAUDE.md` (exit 0 = tracked, non-zero = untracked or no git). Cache result for the session.
4. **Detect remote visibility** if tracked: `gh repo view --json visibility 2>/dev/null` (cache per repo for the session). If `gh` is unavailable, treat as "unknown remote."

**Prompt user with the appropriate warning tier:**

| Tracking state | Prompt form |
|----------------|-------------|
| Untracked or no git | `Add a _project-knowledge/ reference to <repo-root>/CLAUDE.md? This is a 5-line section explaining the convention to teammates not using ARIA. (y/N)` |
| Tracked, public remote | `⚠️ <repo-root>/CLAUDE.md is committed to a PUBLIC remote — this edit will be visible to anyone on push. Add a _project-knowledge/ reference? (y/N)` |
| Tracked, private remote | `<repo-root>/CLAUDE.md is committed to a remote — teammates will see this edit on next push. Add a _project-knowledge/ reference? (y/N)` |
| Tracked, unknown remote (gh missing or repo not on GitHub) | `<repo-root>/CLAUDE.md is git-tracked — committing this edit will broadcast it to anyone with the remote. Add a _project-knowledge/ reference? (y/N)` |

**Default is N** for all four tiers. Per-repo confirmation matches the cadence of `/setup`'s file-diff prompts.

**On `y`:** append the following block to `<repo-root>/CLAUDE.md` (insert after the title H1 if one exists, otherwise append at end). `git add` the change but do NOT commit.

```markdown
## Team-Shared Knowledge

Team-shared knowledge for this repo lives in `_project-knowledge/` (committed). Files follow `{YYYY-MM-DD}-{author}-{slug}.md` naming with frontmatter origin pointers. Cross-cutting items live in `_project-knowledge/cross/`. See `_project-knowledge/README.md` for the convention.
```

**On `N` or empty input:** skip; record the decision in the Step 8 report ("CLAUDE.md reference declined for `<repo-root>`"). User can add manually later or accept on a future first-write to a different repo.

**Idempotency:** the existing-heading probe in step 2 above prevents duplicate sections if the user accepts on a first share, then later runs `audit-share` again with new content into the same repo. The "first-write hook" trigger only fires when `_project-knowledge/` is newly created OR when CLAUDE.md still lacks the reference.

## Step 6.5b: Container CLAUDE.md Offer (Multi-Repo Group Awareness)

Single-repo projects are fully covered by Step 6.5a above — `<repo-root>/CLAUDE.md` is the only relevant CLAUDE.md, and the canned single-repo text accurately describes that repo's `_project-knowledge/` folder.

Multi-repo projects (those with a `projects_groups` entry) have a second CLAUDE.md worth pointing at: the **container** that holds the sub-repos. Teammates navigating at the container level (above any one sub-repo) benefit from a group-level pointer that names each sub-repo's `_project-knowledge/`. The single-repo canned text is structurally wrong for the container — the container has no `_project-knowledge/` of its own — so this step uses a different text variant.

Run this step after Step 6.5a, gated by these conditions in order:

1. **Detect group membership.** Parse the `projects_groups` block from `~/.gemini/antigravity/aria-knowledge.local.md`. For each group tag, walk the role-value pairs (e.g., `backend:`, `web:`, `mobile:`, plus any custom roles); if any role-value resolves to a path equal to the current sub-repo's path, the current sub-repo belongs to that group tag. Record the group tag. If no match, skip Step 6.5b entirely (pure single-repo case).
2. **Resolve container path.** Look up the matched group tag in `projects_list` to get the container's relative path; the container root is `~/Projects/<that-path>`.
3. **Session cache check.** If this group tag has already had its container offer made (or skipped) earlier in the current `audit-share` invocation — e.g., user shared to one sub-repo, then later to a sibling sub-repo in the same group — skip silently. The cache prevents re-prompting across sibling shares within one run.
4. **Probe `<container-root>/CLAUDE.md`.** If absent, skip silently (don't auto-create) and record group as "container CLAUDE.md absent" in the session cache.
5. **Idempotency probe.** Search the container CLAUDE.md for an existing `## Team-Shared Knowledge` heading OR any reference to `_project-knowledge/`. If present, skip silently and record group in the session cache as "container CLAUDE.md already has reference."
6. **Detect git tracking** for the container CLAUDE.md via `git -C <container-root> ls-files --error-unmatch CLAUDE.md`. Cache result.
7. **Detect remote visibility** if tracked: `gh repo view --json visibility 2>/dev/null` (cache per container for the session). If `gh` is unavailable, treat as "unknown remote."

**Prompt user with the appropriate warning tier** (same three-tier shape as Step 6.5a, retargeted at the container path):

| Tracking state | Prompt form |
|----------------|-------------|
| Untracked or no git | `Add a group-level _project-knowledge/ reference to <container-root>/CLAUDE.md? This points teammates at each sub-repo's _project-knowledge/ folder. (y/N)` |
| Tracked, public remote | `⚠️ <container-root>/CLAUDE.md is committed to a PUBLIC remote — this edit will be visible to anyone on push. Add a group-level _project-knowledge/ reference? (y/N)` |
| Tracked, private remote | `<container-root>/CLAUDE.md is committed to a remote — teammates will see this edit on next push. Add a group-level _project-knowledge/ reference? (y/N)` |
| Tracked, unknown remote | `<container-root>/CLAUDE.md is git-tracked — committing this edit will broadcast it to anyone with the remote. Add a group-level _project-knowledge/ reference? (y/N)` |

**Default is N** for all four tiers, matching Step 6.5a's posture.

**On `y`:** append the **group-aware variant** to `<container-root>/CLAUDE.md` (insert after the title H1 if one exists, otherwise append at end). `git add` the change but do NOT commit. Variant text:

```markdown
## Team-Shared Knowledge

Team-shared knowledge for repos in this group lives in each sub-repo's `_project-knowledge/` folder (committed per repo: `{sub1}/_project-knowledge/`, `{sub2}/_project-knowledge/`, ...). Files follow `{YYYY-MM-DD}-{author}-{slug}.md` naming with frontmatter origin pointers. Cross-cutting items live in `_project-knowledge/cross/` in any one repo. See any sub-repo's `_project-knowledge/README.md` for the convention (auto-created on first share via the ARIA plugin).
```

Substitute `{sub1}`, `{sub2}`, etc., with the relative paths of each sub-repo from the matched group entry (preserve role ordering: backend → web → mobile → custom roles in declaration order).

**On `N` or empty input:** skip; record in session cache and Step 8 report. User can add manually later or accept on a future share that triggers a fresh first-write to this group (i.e., the group's container offer fires again on the next `audit-share` invocation if still not satisfied).

**Why session cache, not persistent cache:** the container offer should re-fire across sessions because the user may have changed their mind, the CLAUDE.md may have been edited externally, or sub-repos may have been added/removed. Within a single `audit-share` invocation, sibling sub-repo shares share the cache so the container offer fires at most once per run.

## Step 7: IDEAS-BACKLOG.md Migration (One-Time Per Project)

For each project touched in Step 5, check if migration is needed. Migration target depends on project shape:

- **Single-repo project** (no `projects_groups[tag]` entry): migration target is `<project-root>/_project-knowledge/IDEAS-BACKLOG.md`.
- **Multi-repo project** (`projects_groups[tag]` set): migration target is `<project-root>/<primary-sub-repo>/_project-knowledge/IDEAS-BACKLOG.md` (primary sub-repo = first role in declaration order, matching Step 2.3's resolution).

Migration logic:

- If `<project-root>/IDEAS-BACKLOG.md` exists AND the migration target does NOT:
  - If the source location is in a git repo (single-repo case, OR rare multi-repo edge case where the container itself is a repo), use `git mv <source> <target>`.
  - Otherwise, use filesystem `mv` (multi-repo containers are typically untracked; the move crosses from container to sub-repo).
  - For multi-repo projects, after the filesystem move, run `git -C <primary-sub-repo-root> add _project-knowledge/IDEAS-BACKLOG.md` to stage the new file inside the sub-repo. **Do NOT commit** — user reviews and commits via normal flow.
  - Note migration in the summary report (include source → target paths so user can verify).
- If both source and target exist, log a warning: *"Both `<project-root>/IDEAS-BACKLOG.md` and `<migration-target>` exist. Manual reconciliation needed."* Skip migration; user resolves.
- If only the target exists, no migration needed.
- If neither exists, no IDEAS-BACKLOG.md is in play for this project (audit-share may still create the target on first IDEAS-BACKLOG entry promotion via Step 2.4).

## Step 8: Report

Output a summary of what happened:

```
## /audit-share complete

- N candidates reviewed
- A shared:
  - A1 to repo: <count>
  - A2 to cross: <count>
  - A3 modified-then-shared: <count>
- B skipped:
  - B1 user-declined: <count>
  - B2 not-in-scope: <count>
  - B3 sanitization-blocked: <count>
- C deferred (will re-prompt next invocation): <count>
- M IDEAS-BACKLOG.md migrations performed: <list>

Files written:
- <repo-1>/_project-knowledge/<filename> (from <source>)
- <repo-2>/_project-knowledge/<filename> (from <source>)
- ...

Next steps:
- Review staged changes: `cd <repo-1> && git diff --cached`
- Commit and push when ready.
- Run `/index` to refresh the tag index with the new files.
- Run `/context <project-tag>` to verify discovery works.
```

If the user cancelled in Step 4, report: *"audit-share cancelled — no actions taken."*

## Rules

- **Read-then-write** — Steps 1-3 are read-only (build the recommendation list); Step 5 is where writes happen.
- **No auto-commit** — `git add` only; the user reviews staged changes and commits through their normal flow.
- **Sanitization is a warn-prompt, not an auto-block** — the user makes the call. Auto-scanning for secrets/URLs is out of scope for v1 (deferred to v2.x).
- **Frontmatter is the source of truth for "already shared"** — files with `shared:` array entries matching the proposed target are skipped silently.
- **Personal copies are independent records from team copies** — they can drift; re-running `/audit-share` after editing personal will offer to share again (incrementing the array, not overwriting).
- **Cross items are federated, not centralized** — a cross item promoted from one user lands in one repo's `cross/`; another user might promote a similar item to a different repo's `cross/`. Aggregation/dedup is a read-side concern handled by `/index` + `/context`, not write-side here.
