---
description: "Batch-review personal knowledge for promotion to team-shared project knowledge. Walks insights/decisions/approaches/rules and IDEAS-BACKLOG.md entries, recommends a target _project-knowledge/ destination per item, and lets the user approve all/numbers/modify/skip. Use when user says '/audit-share', '/share-audit', 'share knowledge', 'promote to team', 'sync to shared knowledge', or after enabling the projects_shared_knowledge feature."
argument-hint: ""
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# /audit-share — Batch-Review Personal Knowledge for Team Sharing

Walk personal knowledge files and IDEAS-BACKLOG.md entries; recommend a target `_project-knowledge/` destination per item; present a batch summary; let the user approve, modify, or skip.

## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md` and extract:

- `knowledge_folder` — required
- `projects_enabled` — required (must be `true`)
- `projects_list` — required (parsed into tag→path map)
- `projects_shared_knowledge` — required (must be `true`)
- `author_tag` — required (non-empty); fall back to deriving from `git config user.name` (first 2 chars of first + first 2 chars of last) if missing

If the config file doesn't exist: *"aria-knowledge is not configured. Run /setup to get started."*

If `projects_shared_knowledge: false` or missing: *"Shared knowledge is not enabled. Run /setup and choose 'Enable shared knowledge feature?' to opt in."*

If `projects_enabled: false` or `projects_list` empty: *"Shared knowledge requires the project tier. Run /setup to enable projects and configure your project list."*

If `author_tag` is missing AND no derivable git user.name: *"Author tag is required. Set `author_tag` in `~/.claude/aria-knowledge.local.md` (e.g., `init`) or configure `git config user.name`."*

## Step 1: Scan Candidates

Walk these directories under `{knowledge_folder}/`:

- `insights/`
- `decisions/`
- `approaches/`
- `rules/`
- `projects/<tag>/` for each tag in `projects_list`

Plus IDEAS-BACKLOG.md entries from each project root:

- For each tag in `projects_list`, resolve to project root via `~/Projects/<path>` (where `<path>` is the projects_list value).
- Probe `<project-root>/_project-knowledge/IDEAS-BACKLOG.md` first (post-feature location).
- Fall back to `<project-root>/IDEAS-BACKLOG.md` (pre-feature location, will trigger Step 7 migration on first execute).
- Parse the file by `### YYYY-MM-DD — {title}` headers; treat each section as a candidate "entry."

**Skip candidates** when:

- File frontmatter contains a `shared:` array with an entry whose `path` matches the proposed target. (Already shared; no action needed.)
- File type is `feedback` or `references` (out of scope per design Q10 — feedback memories tend to be personal preferences; references are pointers to external systems that may not apply uniformly to teammates).

## Step 2: Suggest Action Per Candidate

For each candidate, determine:

1. **Project tag** — from frontmatter `project:` field. Multi-value tags (e.g., `proj-a, proj-b`) are split and each tag triggers a separate share recommendation.
2. **Recommended action**:
   - `project: cross` → recommend **share-to-cross** (will need user to pick destination repo at execute time, since cross items can land in any repo's `cross/` subfolder).
   - Project tag matches a configured `projects_list` entry → recommend **share-to-{project}**.
   - Otherwise (no project tag, or tag not in projects_list) → recommend **skip**.
3. **Target path** — compute as:
   - Repo-scoped: `<project-root>/_project-knowledge/<YYYY-MM-DD>-<author_tag>-<slug>.md`
   - Cross-cutting: `<destination-repo-root>/_project-knowledge/cross/<YYYY-MM-DD>-<author_tag>-<slug>.md`
   - **Date** is today (the share date), not the original capture date.
   - **Author** is `author_tag` from config.
   - **Slug** is derived from the source filename (strip date prefix and extension) or from frontmatter `title:`.
   - **Collision handling**: if the target path already exists, append `-2`, `-3`, etc. to the slug until unique.
4. **IDEAS-BACKLOG.md entries** are special-cased: each entry promotes by appending to `<project-root>/_project-knowledge/IDEAS-BACKLOG.md` (or the `cross/IDEAS-BACKLOG.md` for cross items), not by creating a new file.
5. **Public-repo flag** — for each unique target repo, run `gh repo view --json visibility 2>/dev/null` (cache result for the session). If visibility is `PUBLIC`, mark target as needing sanitization warn-prompt at execute time. If `gh` is unavailable, skip the check (do not block); note in summary as "could not verify repo visibility."

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

1. **Resolve cross destination** (only if action is share-to-cross and destination not yet set): prompt *"Pick destination repo for cross item: <list of projects_list entries>"*. Update target path.
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
8. **`git add`** the new/changed files in the target repo. **Do NOT commit** — user reviews and commits via normal flow.

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

## Step 7: IDEAS-BACKLOG.md Migration (One-Time Per Repo)

For each project root touched in Step 5, check if migration is needed:

- If `<project-root>/IDEAS-BACKLOG.md` exists AND `<project-root>/_project-knowledge/IDEAS-BACKLOG.md` does NOT:
  - If the project root is a git repo, use `git mv <project-root>/IDEAS-BACKLOG.md <project-root>/_project-knowledge/IDEAS-BACKLOG.md`.
  - Otherwise, use filesystem `mv`.
  - Note migration in the summary report.
- If both exist, log a warning: *"Both <project-root>/IDEAS-BACKLOG.md and <project-root>/_project-knowledge/IDEAS-BACKLOG.md exist. Manual reconciliation needed."* Skip migration; user resolves.
- If only the new location exists, no migration needed.

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
