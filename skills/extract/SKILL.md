---
name: extract
description: 'Extract uncaptured knowledge from the current conversation before it is lost to compaction. Use after completing a task, before switching context, before large exploratory work (multi-file reads, codebase scans), or when the user signals session end. Trigger: "/aria-cowork:extract", "extract knowledge", "capture session knowledge". Also.'
---

# /extract — Pre-Compaction Knowledge Extraction

Scan the current conversation since the last extraction for uncaptured insights, decisions, feedback, project context, and references. Dump everything to backlogs for review at the next knowledge audit. No confirmation dialog — just scan, deduplicate, and append.

## Runtime Gate (per ADR-094)

**Before Step 0:** Check whether `Bash` is available. If `Bash` IS available (you are in Claude Code), surface:

> ⚠️ **Runtime mismatch — you invoked aria-cowork's `/extract` from a runtime with shell access.**
>
> This variant only writes to the attached knowledge folder and skips `~/.claude/projects/.../memory/` + `~/.claude/plans/` — but you appear to be in Claude Code, where those memory + plans paths ARE reachable and the aria-knowledge canonical includes them. For the Code-native variant, use `/extract` (the aria-knowledge canonical).
>
> Proceed with the aria-cowork variant anyway? (`y` / `n`)

Wait for `y` / `yes`. **Gate applies even in `auto`** (ADR-094 §Part 3). If `Bash` is NOT available, proceed to Step 0.

## Step 0: Resolve config and detect project context

The default knowledge folder is `~/Projects/knowledge/` (expand `~` to your home directory's absolute path). Read `<knowledge_folder>/aria-config.md` and extract:

- `knowledge_folder` — required
- `projects_enabled` — default `false`
- `projects_list` — default empty (only relevant if `projects_enabled: true`)
- `projects_remotes` — default empty (parse-tolerated by cowork; consumed only when projects_enabled is true)

If `aria-config.md` doesn't exist, stop: *"aria-cowork is not configured. Run `/aria-setup` to get started."*

Use `<knowledge_folder>` for all file operations during this session.

### Detect current project (only if `projects_enabled: true`)

Determine the current project context. Cowork has no automatic CWD detection (unlike aria-knowledge running in Code) — use these signals in order:

1. **Explicit user attribution:** if the conversation already mentions a project tag (e.g., "I'm working on proj-a today"), use that as `current_project`.
2. **Conversation-thread context:** if the conversation is anchored to docs, files, or topics that match a configured project, infer the project tag from `projects_list`.
3. **No match:** leave `current_project` unset — subsequent steps will skip auto-tagging and use explicit context labels.

Cowork's persistent-grant model means there's no single "current working directory" — multiple folders may be attached, and the active conversation context is the better signal than path inference. Aria-knowledge's `bin/config.sh` CWD-matching helper does not apply here.

## Step 1: Determine extraction scope

Check if a previous extraction happened this session by looking for a timestamp marker. If this is the first extraction of the session, scan the entire conversation. If a previous extraction occurred, scan only from that point forward.

The timestamp is tracked as the last entry date in the backlogs from this session — check the most recent entry dates in:

- `<knowledge_folder>/intake/insights-backlog.md`
- `<knowledge_folder>/intake/decisions-backlog.md`
- `<knowledge_folder>/intake/extraction-backlog.md`
- `<knowledge_folder>/intake/ideas/` — most recent `*.md` file by name (filenames are date-prefixed `YYYY-MM-DD-...`)

If no entries exist from today's date, treat the entire conversation as unscanned.

## Step 2: Scan conversation for uncaptured knowledge

Review the conversation and categorize findings into six buckets. The first five (insights, decisions, feedback, project context, references) capture **observations about what IS** — they promote to knowledge during audit. The sixth bucket (ideas) captures **proposals about what SHOULD BE different** — these route via the audit's Accept submenu (tracker / roadmap / todo / adr / backlog / bundle / rule) rather than promoting directly into knowledge files.

### Insights

- Non-obvious technical observations discussed in conversation
- Patterns discovered during research, exploration, or stakeholder discussion
- Behaviors that surprised either party
- Insight blocks that were output but NOT yet appended to `insights-backlog.md`

### Decisions

- Architectural, process, or design choices made during the session
- Technology or approach selections with rationale
- Cross-project decisions that set precedents
- Scope decisions (what was included/excluded and why)
- Stakeholder decisions surfaced in conversation

### Feedback

- Corrections from the user (*"don't do X"*, *"that's wrong"*, *"not like that"*)
- Confirmed approaches (*"yes exactly"*, *"perfect"*, accepting an unusual choice)
- Workflow preferences expressed during the session
- Communication style preferences

### Project Context

- Status updates about what's in-flight or blocked
- Who is working on what and by when
- Sprint, milestone, or release-cycle context
- Dependency or integration information

### References

- External URLs, tools, dashboards, or services mentioned
- Linear projects, Slack channels, or other system pointers
- Documentation locations discovered during the session

### Ideas (proposals, not observations)

- Feature proposals for any project (*"this should support X"*, *"X could be better if Y"*)
- Bug reports noticed in passing (*"X silently fails when Y"*, *"this UX is broken in case Z"*)
- Design ideas or refactoring proposals not yet scoped for implementation
- Workflow improvements (*"it would help if the tool did X"*)
- **Classification signal:** phrases like *"should"*, *"could be"*, *"missing handling for"*, *"UX gap"*, *"would help if"*, *"this is broken"* typically indicate an idea rather than an observation
- **Soft routing:** classification is a suggestion, not a hard rule. An item can legitimately be both observation and proposal — if so, put the observation in its appropriate bucket (insights/decisions/etc.) AND a separate file in `intake/ideas/` covering just the proposal. The audit step can refine routing if needed.

## Step 3: Deduplicate

For each finding, check against:

1. Existing entries in `<knowledge_folder>/intake/insights-backlog.md`
2. Existing entries in `<knowledge_folder>/intake/decisions-backlog.md`
3. Existing entries in `<knowledge_folder>/intake/extraction-backlog.md`
4. Existing files in `<knowledge_folder>/intake/ideas/*.md` (read frontmatter + body of each to compare)
5. Knowledge files in `<knowledge_folder>/` (approaches/, decisions/, guides/, references/)

**Skip anything already captured.** Be conservative — if the content is substantively the same even with different wording, skip it.

**Cowork-specific note (parity with aria-knowledge):** aria-knowledge's `/extract` ALSO dedups against `CLAUDE.md` files in the current working directory and memory files at `~/.claude/projects/`. Cowork's persistent-grant model can't reliably reach those surfaces. If a CLAUDE.md is in the attached knowledge folder OR was explicitly Read during this conversation, include it in dedup. Otherwise, accept the broader-dedup gap as a cowork divergence — duplicates can be cleaned up at `/audit-knowledge` time.

**If any deduplication source cannot be read** (missing file, permissions error), note which source was skipped and include it in the Step 5 report: *"Deduplication incomplete — could not read [file]. Some entries may be duplicates."*

## Step 4: Append to backlogs

Route each finding to the appropriate backlog file. Do NOT ask for confirmation — just append.

### Project tag auto-prepending

If `current_project` was set in Step 0:

- For findings that don't already have a project attribution, use `current_project` as the `[project]` value in the entry header.
- For findings that already have an explicit project attribution that conflicts (e.g., user said "this is a cross-project pattern" while context was proj-a), preserve the explicit attribution — don't override it.
- The auto-tag is a default, not a forced override. The audit process will refine it during promotion.

If `current_project` is unset, use the existing rules: tag with the project (or "cross") when identifiable from conversation context; otherwise omit `[project]` from the header (use `[no-project]` or just the context label).

### Insights → `<knowledge_folder>/intake/insights-backlog.md`

```markdown
### YYYY-MM-DD — [project] — [task context]
- Insight bullet 1
- Insight bullet 2
```

### Decisions → `<knowledge_folder>/intake/decisions-backlog.md`

```markdown
### YYYY-MM-DD — [project(s)] — [decision context]
**Decision:** What was decided
**Why:** Rationale
**Alternatives considered:** What else was evaluated
```

### Feedback, Project Context, References → `<knowledge_folder>/intake/extraction-backlog.md`

```markdown
### YYYY-MM-DD — [type: feedback|project|reference] — [context]
**Content:** What was captured
**Source:** Where in the conversation this came from (brief description)
```

### Ideas → `<knowledge_folder>/intake/ideas/{YYYY-MM-DD}-{project}-{slug}.md` (one file per idea)

Ideas use **per-file storage**, not a single append-only backlog. Write one new markdown file per idea under `intake/ideas/`.

**Filename pattern:**

```
{YYYY-MM-DD}-{project}-{slug}.md
```

- `YYYY-MM-DD` — today's date (from the conversation's current date, not the OS clock; convert relative dates per Rules)
- `{project}` — the project tag from Step 0's `current_project`, or an explicit project attribution from the finding, or `cross` for cross-project, or `no-project` if unattributed
- `{slug}` — kebab-cased short title derived from the idea: lowercase, alphanumerics + hyphens only, truncated to ~60 chars, strip trailing hyphens
- **On collision** (same date + project + slug already exists): append `-2`, `-3`, etc. to the slug until unique. Check via directory listing of `intake/ideas/` before writing.

**File format (YAML frontmatter + body):**

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

Ideas do NOT promote to knowledge files directly — during audit review the user picks a destination from the Accept submenu: external tracker, project `ROADMAP.md` or `TODO.md` (when present), the decisions backlog (for ADR review), a dated entry in `IDEAS-BACKLOG.md`, a bundled merge of related ideas, or the rules backlog (for working-rule review).

### Before writing

- For the four single-file backlogs (insights, decisions, extraction, rules): remove any *"(No pending ...)"* placeholder, then append new entries below existing ones with a blank line separator.
- For ideas (per-file): write a new file per the filename pattern above; there is no placeholder to remove.
- **If a single-file backlog is missing:** do not create it from scratch. Stop and tell the user: *"Backlog file [name] is missing. Run `/aria-setup` to repair the knowledge folder structure."*
- **If the `intake/ideas/` directory is missing:** do not create it. Stop and tell the user: *"Ideas directory `intake/ideas/` is missing. Run `/aria-setup` to repair the knowledge folder structure."*

## Step 5: Report

After appending, output a brief summary:

```
## Extraction Complete

- **Insights:** N new (appended to insights-backlog.md)
- **Decisions:** N new (appended to decisions-backlog.md)
- **Feedback:** N new (appended to extraction-backlog.md)
- **Project context:** N new (appended to extraction-backlog.md)
- **References:** N new (appended to extraction-backlog.md)
- **Ideas:** N new (written to intake/ideas/ — one file per idea; routed at audit time to tracker / roadmap / todo / adr / backlog / bundle / rule)
- **Skipped:** N duplicates

Knowledge staged in backlogs for next audit to review and promote. Ideas staged for the Accept submenu — pick destination per idea at next `/aria-cowork:audit-knowledge`.
```

If nothing was found:

```
## Extraction Complete

No uncaptured knowledge found — everything from this session is already persisted.
```

## Rules

- **Never ask for confirmation** — scan and dump. The audit process handles review and promotion.
- **Be thorough but not noisy** — capture genuinely useful knowledge, not every minor exchange. *"User asked to read a doc"* is not knowledge. *"User explained that the auth strategy is driven by compliance requirements"* IS knowledge.
- **Convert relative dates** — *"last Thursday"* becomes the actual date (YYYY-MM-DD).
- **Project attribution** — always tag with the project (or *"cross"*) when identifiable.
- **Feedback is high-value** — corrections and confirmed approaches are the most actionable extraction type. Capture the correction AND the reason if one was given.
- **Keep entries concise** — each backlog entry should be self-contained but brief. The audit process adds depth when promoting.
- **One extraction per natural breakpoint** — don't run multiple times for the same conversation segment.
- **No hook companion in Cowork** — aria-knowledge ships a Stop hook that nudges users to run `/extract` at session-end. Cowork has no hook layer, so `/extract` is manual-invoke only. Users should develop the habit of running it before context switches or session-end; `/aria-cowork:wrapup` and `/aria-cowork:handoff` invoke it automatically as part of end-of-session flows.
- **Use Cowork's native I/O** — never invoke a Filesystem MCP connector (per ADR-003).
