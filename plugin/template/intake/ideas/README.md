# Ideas Backlog

Feature proposals, bug reports, and design ideas captured during Claude Code sessions via `/extract`. **One file per idea** under this directory. Reviewed during the knowledge audit as a separate section from promotion candidates.

## Purpose

ARIA captures observations about **what IS** (knowledge) and stages proposals about **what SHOULD BE different** (ideas). Observations promote into knowledge files; proposals route out to your external tracker (Linear, GitHub Issues, Jira, etc.).

**ARIA captures; your tracker schedules.** This directory is staging only — ARIA does not replace your issue tracker.

## File naming

```
YYYY-MM-DD-{project}-{slug}.md
```

- `YYYY-MM-DD` — the date the idea was captured
- `{project}` — project tag from your `projects_list`, or `cross` for cross-project, or `no-project` if unattributed
- `{slug}` — kebab-cased short title, truncated to ~60 chars
- On collision (same date + project + slug), append `-2`, `-3`, etc.

Examples:
- `2026-04-21-aria-force-interactive-index-steps.md`
- `2026-04-21-cs-builder-extract-shared-postcard.md`
- `2026-04-21-cross-generalize-build-playbook.md`

## File format

Each file has YAML frontmatter plus the idea body:

```markdown
---
date: YYYY-MM-DD
project: project-tag-or-cross
type: feature | bug | design | refactor | workflow
title: Short title matching the filename slug
---

**Proposal:** What change is being proposed.

**Motivation:** Why it would help (what gap or friction it addresses).

**Source:** Where in the conversation it came up (brief description).
```

`/extract` writes these automatically. If you're filing by hand, follow the same frontmatter + body shape.

## Disposition (during `/audit-knowledge`)

Ideas are surfaced in their own section without promotion suggestions. For each idea:

- **Accept** — copy the idea to your external tracker, then the file is deleted
- **Reject** — delete the file with a disposition note recorded in the audit log
- **Defer** — leave the file in place for a future audit cycle
- **Reclassify** — if on review the item is actually an observation, move content to the appropriate knowledge backlog (insights / decisions / extraction) for normal promotion, then delete the idea file

Unlike the knowledge backlogs, ideas **never promote to knowledge files** — they leave ARIA entirely (to a tracker) or get discarded. Git history is the audit trail; deleted files remain recoverable via `git log --all -- intake/ideas/`.

## Staleness

During `/audit-knowledge`, idea files older than `ideas_staleness_threshold_days` (default 21, configurable in `~/.claude/aria-knowledge.local.md`) are tagged `[STALE — still relevant?]` and require an explicit Accept / Reject / Defer decision — you can't implicitly defer a stale idea.

Staleness is computed from the `date:` field in the frontmatter, falling back to the `YYYY-MM-DD` prefix in the filename if frontmatter is missing or malformed.

## Migration from pre-2.11 `ideas-backlog.md`

If your knowledge folder was created under ARIA v2.10.x or earlier, you'll have a legacy single-file `intake/ideas-backlog.md`. ARIA v2.11 switched to per-file storage to eliminate these issues:

- Single file eventually exceeds the Read tool's context window (hit at ~1200 lines).
- "Cleared but still physically present" drift between audit passes (the clear-entries-with-HTML-comments pattern accrues cruft).
- Concurrent `/extract` runs risk merge conflicts on the same file.

### How to migrate

Run the migration script against your knowledge folder:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/bin/migrate-ideas-backlog.sh /path/to/your/knowledge
```

Or on next `/setup`: if a legacy `intake/ideas-backlog.md` is detected alongside this `intake/ideas/` directory, `/setup` will prompt you to run the migration automatically.

### What the migration does

1. Parses each `### YYYY-MM-DD — ...` entry below the `---` separator in `ideas-backlog.md`.
2. Emits one file per entry here, with YAML frontmatter derived from the entry header.
3. Drops the cleared-history HTML comment markers (the same information lives in `logs/knowledge-audit-log.md`).
4. Renames the original file to `ideas-backlog.md.pre-2.11-migration` so you can spot-check the migration output before deleting the old artifact.

### If you prefer not to migrate

The new per-file format is what ARIA v2.11+ skills read and write. Leaving `ideas-backlog.md` in place means:

- New ideas from `/extract` land here as per-file, not in the old backlog.
- `/audit-knowledge` will only see ideas in this directory; old entries become invisible.
- `/context {project}` will only surface ideas from here.

Running the migration preserves your existing entries. Skipping it silently strands them.
