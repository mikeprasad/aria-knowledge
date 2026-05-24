---
description: "Extract uncaptured knowledge from the current conversation before it's lost to compaction. Use after completing a task, before switching context, before large exploratory work (multi-file reads, codebase scans), or when the user signals session end. Trigger: '/extract', 'extract knowledge', 'capture session knowledge'. Also prompt mid-session: 'Task complete — want me to run /extract?' and 'Switching context — want me to run /extract first?'."
---

# /extract — Pre-Compaction Knowledge Extraction

Scan the current conversation since the last extraction for uncaptured insights, decisions, feedback, project context, and references. Dump everything to backlogs for review at the next knowledge audit. No confirmation dialog — just scan, deduplicate, and append.

## Step 0: Resolve Config and Detect Project Context

Read `~/.gemini/antigravity/aria-knowledge.local.md` and extract:
- `knowledge_folder` — required
- `projects_enabled` — default `false`
- `projects_list` — default empty (only relevant if `projects_enabled: true`)

If the config file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Use `{knowledge_folder}` as the base path for all file operations in subsequent steps.

### Detect current project (only if `projects_enabled: true`)

Determine the current working directory and check if it matches a configured project path:

1. Get the current working directory (typically the user's primary working directory, e.g., `~/Projects/path/to/proj-a`).
2. Parse `projects_list` into `tag:path` pairs.
3. For each pair, check if the CWD contains the configured path as a substring. If so, set `current_project` to that tag and stop iterating (first match wins).
4. If no path-based match is found AND `projects_remotes` is configured AND git is available, fall back to git-remote matching: run `git config --get remote.origin.url` from the CWD; for each `tag:url-pattern` pair in `projects_remotes`, check if the remote URL contains the pattern; if so, set `current_project` to that tag.
5. If still no match, leave `current_project` unset — subsequent steps will skip auto-tagging.

This logic mirrors the `kt_project_for_path` shell helper in `bin/config.sh`. Skills can either invoke that helper via Bash or replicate the matching logic in markdown-driven flow as above.

Examples:
- CWD = `~/Projects/myproject/sub-module/file.md`, `projects_list: myproject:myproject,other:other` → `current_project = myproject` (substring match on `myproject`)
- CWD = `~/Projects/other`, `projects_list: myproject:myproject,other:other` → `current_project = other`
- CWD = `~/Downloads/scratch-folder`, `projects_list: myproject:myproject,other:other` → `current_project` unset (no configured path matches)

## Step 1: Determine Extraction Scope

Check if a previous extraction happened this session by looking for a timestamp marker. If this is the first extraction of the session, scan the entire conversation. If a previous extraction occurred, scan only from that point forward.

The timestamp is tracked as the last entry date in the backlogs from this session — check the most recent entry dates in:
- `{knowledge_folder}/intake/insights-backlog.md`
- `{knowledge_folder}/intake/decisions-backlog.md`
- `{knowledge_folder}/intake/extraction-backlog.md`
- `{knowledge_folder}/intake/ideas/` — use the `YYYY-MM-DD` prefix of the most recent `*.md` file (via `ls -1 intake/ideas/*.md | sort -r | head -1`)

If no entries exist from today's date, treat the entire conversation as unscanned.

## Step 2: Scan Conversation for Uncaptured Knowledge

Review the conversation and categorize findings into six buckets. The first five (insights, decisions, feedback, project context, references) capture **observations about what IS** — they promote to knowledge during audit. The sixth bucket (ideas) captures **proposals about what SHOULD BE different** — these route via the audit's Accept submenu (tracker / roadmap / todo / adr / backlog / bundle / rule) rather than promoting directly into knowledge files.

### Insights
- Insight blocks that were output but NOT yet appended to `insights-backlog.md` (per-task capture may have already appended some — Step 3 dedup handles this)
- Non-obvious technical observations discussed in conversation
- Patterns discovered during debugging or exploration
- Codebase behaviors that surprised either party

### Decisions
- Architectural or design choices made during the session
- Technology or approach selections with rationale
- Cross-project decisions that set precedents
- Scope decisions (what was included/excluded and why)

### Feedback
- Corrections from the user ("don't do X", "that's wrong", "not like that")
- Confirmed approaches ("yes exactly", "perfect", accepting an unusual choice)
- Workflow preferences expressed during the session
- Communication style preferences

### Project Context
- Status updates about what's in-flight or blocked
- Who is working on what and by when
- Sprint or milestone context
- Dependency or integration information

### References
- External URLs, tools, dashboards, or services mentioned
- Linear projects, Slack channels, or other system pointers
- Documentation locations discovered during the session

### Ideas (proposals, not observations)
- Feature proposals for any project ("this should support X", "X could be better if Y")
- Bug reports noticed in passing ("X silently fails when Y", "this UX is broken in case Z")
- Design ideas or refactoring proposals not yet scoped for implementation
- Workflow improvements ("it would help if the tool did X")
- **Classification signal:** phrases like "should", "could be", "missing handling for", "UX gap", "would help if", "this is broken" typically indicate an idea rather than an observation
- **Soft routing:** classification is a suggestion, not a hard rule. An item can legitimately be both observation and proposal — if so, put the observation in its appropriate bucket (insights/decisions/etc.) AND a separate file in `intake/ideas/` covering just the proposal. The audit step can refine routing if needed.

## Step 3: Deduplicate

For each finding, check against:
1. Existing entries in `{knowledge_folder}/intake/insights-backlog.md`
2. Existing entries in `{knowledge_folder}/intake/decisions-backlog.md`
3. Existing entries in `{knowledge_folder}/intake/extraction-backlog.md`
4. Existing files in `{knowledge_folder}/intake/ideas/*.md` (glob the directory; read frontmatter + body of each to compare)
5. CLAUDE.md files in the current working directory (root and project-level)
6. Memory files in `~/.gemini/antigravity/transcripts/` for the current project
7. Knowledge files in `{knowledge_folder}/`

**Skip anything already captured.** Be conservative — if the content is substantively the same even with different wording, skip it.

**If any deduplication source cannot be read** (missing file, permissions error), note which source was skipped and include it in the Step 5 report: "Deduplication incomplete — could not read [file]. Some entries may be duplicates."

## Step 4: Append to Backlogs

Route each finding to the appropriate backlog file. Do NOT ask for confirmation — just append.

### Project tag auto-prepending

If `current_project` was set in Step 0:
- For findings that don't already have a project attribution, use `current_project` as the `[project]` value in the entry header.
- For findings that already have an explicit project attribution that conflicts (e.g., user said "this is a cross-project pattern" while CWD is `path/to/proj-a`), preserve the explicit attribution — don't override it.
- The auto-tag is a default, not a forced override. The audit process will refine it during promotion.

If `current_project` is unset, use the existing rules: tag with the project (or "cross") when identifiable from conversation context; otherwise omit `[project]` from the header (use `[no-project]` or just the context label).

Examples:
- CWD inside proj-a, finding doesn't mention a project → `### 2026-04-15 — proj-a — feedback — [context]`
- CWD inside proj-a, finding explicitly says "this is cross-project" → `### 2026-04-15 — cross — decision — [context]`
- CWD outside any configured project, finding mentions df → `### 2026-04-15 — df — insight — [context]`
- CWD outside any configured project, finding has no clear project → `### 2026-04-15 — [no-project] — reference — [context]`

### Insights → `{knowledge_folder}/intake/insights-backlog.md`

Use existing format:
```markdown
### YYYY-MM-DD — [project] — [task context]
- Insight bullet 1
- Insight bullet 2
```

### Decisions → `{knowledge_folder}/intake/decisions-backlog.md`

Use existing format:
```markdown
### YYYY-MM-DD — [project(s)] — [decision context]
**Decision:** What was decided
**Why:** Rationale
**Alternatives considered:** What else was evaluated
```

### Feedback, Project Context, References → `{knowledge_folder}/intake/extraction-backlog.md`

Use this format:
```markdown
### YYYY-MM-DD — [type: feedback|project|reference] — [context]
**Content:** What was captured
**Source:** Where in the conversation this came from (brief description)
```

### Ideas → `{knowledge_folder}/intake/ideas/{YYYY-MM-DD}-{project}-{slug}.md` (one file per idea)

Ideas use **per-file storage**, not a single append-only backlog. Write one new markdown file per idea under `intake/ideas/`.

**Filename pattern:**

```
{YYYY-MM-DD}-{project}-{slug}.md
```

- `YYYY-MM-DD` — today's date (from the conversation's current date, not the OS clock; convert relative dates per Rules)
- `{project}` — the project tag from Step 0's `current_project`, or an explicit project attribution from the finding, or `cross` for cross-project, or `no-project` if unattributed
- `{slug}` — kebab-cased short title derived from the idea: lowercase, alphanumerics + hyphens only, truncated to ~60 chars, strip trailing hyphens
- **On collision** (same date + project + slug already exists): append `-2`, `-3`, etc. to the slug until unique. Check via `ls intake/ideas/` before writing.

Examples:
- `2026-04-21-aria-force-interactive-index-steps.md`
- `2026-04-21-proj-a-extract-shared-postcard.md`
- `2026-04-21-cross-generalize-build-playbook.md`

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

Ideas do NOT promote to knowledge files directly — during audit review the user picks a destination from the Accept submenu: external tracker (Linear, GitHub Issues, Jira, etc.), project `ROADMAP.md` or `TODO.md` (when present), the decisions backlog (for ADR review), a dated entry in `IDEAS-BACKLOG.md`, a bundled merge of related ideas, or the rules backlog (for working-rule review).

### Before writing:
- For the four single-file backlogs (insights, decisions, extraction, rules): remove any "(No pending ...)" placeholder, then append new entries below existing ones with a blank line separator.
- For ideas (per-file): write a new file per the filename pattern above; there is no placeholder to remove.
- **If a single-file backlog is missing:** do not create it from scratch. Stop and tell the user: "Backlog file [name] is missing. Run /setup to repair the knowledge folder structure."
- **If the `intake/ideas/` directory is missing:** do not create it. Stop and tell the user: "Ideas directory `intake/ideas/` is missing. Run /setup to repair the knowledge folder structure."
- **Legacy-file detection (one-time):** if `{knowledge_folder}/intake/ideas-backlog.md` exists alongside `intake/ideas/`, surface a one-line note in Step 5's report: "Legacy `ideas-backlog.md` detected — run `/setup` or `bash ${CLAUDE_PLUGIN_ROOT}/bin/migrate-ideas-backlog.sh` to migrate pre-2.11 entries." Do not attempt the migration from within `/extract`.

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

Knowledge staged in backlogs for next audit to review and promote. Ideas staged for the Accept submenu — pick destination per idea at next `/audit-knowledge`.
```

If nothing was found:
```
## Extraction Complete

No uncaptured knowledge found — everything from this session is already persisted.
```

## Rules

- **Never ask for confirmation** — scan and dump. The audit process handles review and promotion.
- **Be thorough but not noisy** — capture genuinely useful knowledge, not every minor exchange. "User asked to read a file" is not knowledge. "User explained that the auth middleware rewrite is driven by legal compliance" IS knowledge.
- **Convert relative dates** — "last Thursday" becomes the actual date (YYYY-MM-DD)
- **Project attribution** — always tag with the project (or "cross") when identifiable
- **Don't duplicate CLAUDE.md content** — if it's already a rule or convention in any CLAUDE.md, skip it
- **Feedback is high-value** — corrections and confirmed approaches are the most actionable extraction type. Capture the correction AND the reason if one was given.
- **Keep entries concise** — each backlog entry should be self-contained but brief. The audit process adds depth when promoting.
- **One extraction per natural breakpoint** — don't run multiple times for the same conversation segment
