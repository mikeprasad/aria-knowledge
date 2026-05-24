---
name: stats
description: 'Show knowledge base health metrics — file counts, backlog depth, audit status, tag stats, and coverage gaps. Use when user says "/aria-cowork:stats", "knowledge stats", "how is my knowledge base", "show stats", "knowledge health", "dashboard". (Claude Cowork variant. Namespaced-only — bare /stats belongs to aria-knowledge per ADR-094.)'
---

# /stats — Knowledge Base Health

Read-only dashboard showing the current state of the knowledge repository.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Cowork variant — namespaced-only. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/stats` resolves to aria-knowledge's variant — Code is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. To reach this skill, use the namespaced form: `/aria-cowork:stats`. Do NOT match bare `/stats` — that belongs to aria-knowledge.

**Before Step 0:** Check whether the `Bash` tool is available in this session. If `Bash` IS available (you are running in Claude Code or another runtime with shell access), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-cowork's `/stats` from a runtime with shell access.**
>
> Behavior is largely the same in both runtimes; for the Code-native variant (includes codemap-date metrics), use `/stats` (the aria-knowledge canonical).
>
> **Use `/stats` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `stats` (the bare-slash canonical, which routes to aria-knowledge when both ports are loaded) with the same arguments the user provided to this invocation. Do not proceed with this skill's steps; the aria-knowledge variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-cowork) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args.

If `Bash` is NOT available (normal Cowork runtime), proceed to Step 0.

## Step 0: Resolve config

The default knowledge folder is `~/Projects/knowledge/` (expand `~` to your home directory's absolute path). Read `<knowledge_folder>/aria-config.md` and extract `knowledge_folder` and `last_setup_date`. If `aria-config.md` doesn't exist, stop: *"aria-cowork is not configured. Run `/aria-setup` to get started."*

Use `<knowledge_folder>` for all file operations during this session.

## Step 1: Count promoted files

Count `.md` files (excluding README.md) in each promoted folder:

- `<knowledge_folder>/rules/*.md`
- `<knowledge_folder>/approaches/*.md`
- `<knowledge_folder>/decisions/*.md`
- `<knowledge_folder>/guides/**/*.md` (recursive — guides may have subdirectories)
- `<knowledge_folder>/references/*.md`
- `<knowledge_folder>/archive/*.md`

Record counts per category and total.

## Step 2: Count backlog items

For each backlog file, count the number of `### ` (h3) entries below the `---` separator:

- `<knowledge_folder>/intake/insights-backlog.md`
- `<knowledge_folder>/intake/decisions-backlog.md`
- `<knowledge_folder>/intake/extraction-backlog.md`
- `<knowledge_folder>/intake/rules-backlog.md`

Also count `.md` files in `<knowledge_folder>/intake/clippings/` (unreviewed clippings).

## Step 3: Read audit dates

Extract the `**Date:**` from:
- `<knowledge_folder>/logs/knowledge-audit-log.md` (created by `/audit-knowledge` in v0.2.0+; may not exist yet in Phase 1)
- `<knowledge_folder>/logs/config-audit-log.md` (same — v0.2.0+)
- `last_setup_date` field from `<knowledge_folder>/aria-config.md`

Calculate days since each. If a date is missing or *"never"*, note *"never"*.

## Step 4: Index health (if index.md exists)

If `<knowledge_folder>/index.md` exists, read it and extract:
- **Known tags count:** count lines in `## Known Tags` section.
- **Top tags:** from `## Tag Index`, count files listed under each `### tag` header, sort by count, show top 5.
- **Stale files:** read `## Stale Files` section, count entries.
- **Untagged files:** read `## Untagged Files` section, count entries.
- **Semantic-hints coverage (added v0.3.0 — parity with aria-knowledge v2.16.0):** count files declaring `semantic-hints:` frontmatter / total promoted files; report as `N of M (P%)`. Always emit (zero coverage = `0 of M (0%)`) to track adoption over time. Source: scan promoted-folder files (same set as Step 1) for the `semantic-hints:` field; matches `/aria-cowork:index`'s Semantic Hints Index input.

If `index.md` doesn't exist, note: *"No index — run `/aria-cowork:index` to build."*

## Step 5: Coverage gaps

Check which promoted folders have zero `.md` files (excluding README.md):
- If `approaches/` is empty: note it.
- If `decisions/` is empty: note it.
- If `guides/` is empty: note it.
- If `references/` is empty: note it.

These suggest areas where knowledge capture hasn't started yet.

## Step 6: Present

**Output policy:** emit every section defined in the format below with all fields, even when counts are zero. Zero counts are meaningful data points — *"Pending insights: 0"* confirms the backlog is clear, *"Stale files: 0"* confirms the index is current. Do not collapse the dashboard into prose or shorten sections for brevity. The Index Health and Coverage Gaps sections have explicit conditional branches embedded in the template; all other sections are always-emit.

```markdown
## Knowledge Stats (aria-cowork view)

### Repository
- Promoted files: N total
  - Rules: N
  - Approaches: N
  - Decisions: N
  - Guides: N
  - References: N
- Archived: N

### Intake
- Pending insights: N
- Pending decisions: N
- Pending extractions: N
- Pending rules: N
- Unreviewed clippings: N

### Audit Status
- Knowledge audit: [YYYY-MM-DD (N days ago) | never]  *(populated when /audit-knowledge ships in v0.2.0)*
- Config audit: [YYYY-MM-DD (N days ago) | never]  *(populated when /audit-config ships in v0.2.0)*
- Last /aria-setup: YYYY-MM-DD (N days ago)

### Index Health
[If index exists:]
- Known tags: N
- Top tags: tag1 (N files), tag2 (N files), tag3 (N files), tag4 (N files), tag5 (N files)
- Untagged files: N
- Stale files: N
- Semantic-hints coverage: N of M files (P%)
[If no index:]
- No index built yet — run /aria-cowork:index

### Coverage Gaps
[List empty categories, or "All categories have content."]
```

## Phase 1 notes

- **No `/audit-knowledge` or `/audit-config` skills in v0.1.0** — those land in v0.2.0. The "Audit Status" section will show *"never"* until then. That's expected.
- **No `/codemap` integration** — codemap is Code-only per [ADR-005](../../../knowledge/projects/aria-cowork/decisions/005-code-only-skills-excluded.md). The codemap-status section from aria-knowledge's stats is intentionally absent.

## Rules

- **Read-only** — this skill never modifies files.
- **Fast** — just counting and date parsing, no heavy analysis.
- **No recommendations** — just present the data. The user decides what to act on.
- **Use Cowork's native I/O** — never invoke a Filesystem MCP connector (per ADR-003).
