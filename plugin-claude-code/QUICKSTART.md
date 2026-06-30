# ARIA Quick Start

Your first 3 sessions with aria-knowledge. ARIA's five-phase lifecycle — **Capture → Govern → Promote → Apply → Refresh** — maps onto these sessions: session 1 captures, session 2 governs and promotes, session 3 applies trusted knowledge and starts the refresh loop. Rule 22 edit-time discipline is active from session 1 forward.

## After Install

Run `/setup` to configure your knowledge folder. This creates the folder structure and sets preferences. Everything else is automatic.

**What's immediately active:**
- **Rule 22 checks** appear before every file edit — a brief impact assessment to keep changes intentional
- **Session start** checks if any audits are due and reminds you
- **Insight capture** auto-appends Insight blocks to backlogs at task completion boundaries

## Session 1: Just Work (Capture phase)

Work normally. ARIA observes in the background. Insight blocks are auto-captured at task boundaries. Rule 22 fires before/after every Edit/Write — that's the Apply phase already running while you work.

Before wrapping up, run **`/extract`** to capture decisions, feedback, references, and ideas from the conversation. Items go to intake backlogs for review — nothing is promoted automatically.

## Session 2: Govern and Promote

The session-start hook will prompt: *"Want me to scan for extractable knowledge?"*

Run **`/audit-knowledge`** to govern (review) what's been captured, then promote what's worth keeping:
- Approve items to promote them into your knowledge repository
- Reject items to clear them from backlogs
- Defer or reclassify items that aren't ready
- Themes across multiple entries get flagged for synthesis
- Pending ideas route through the Accept submenu (`tracker | roadmap | todo | adr | backlog | bundle | rule`) per project's available destinations

Run **`/index`** to build a tag-based index of your knowledge files.

## Session 3: Apply and Refresh

With an index built, ARIA surfaces trusted knowledge automatically and the refresh loop kicks in:
- **`/context [tags]`** loads knowledge files matching your topic
- **`/rules [number]`** surfaces working rules during reasoning
- **`/codemap`** generates feature-organized maps; **`/stitch`** binds cross-repo product groups; **`/distill`** turns raw tickets into executable specs
- When you create tasks, ARIA checks if related knowledge exists and tells you
- **`/stats`** shows your knowledge base health at a glance
- Audit cadences and staleness thresholds prompt periodic review so the base doesn't quietly rot

## Commands at a Glance

| Command | What it does |
|---------|-------------|
| `/setup` | Configure plugin, check for updates |
| `/extract` | Capture knowledge from current conversation |
| `/audit-knowledge` | Review backlogs and promote to knowledge files |
| `/audit-config` | Check project configs and docs for drift |
| `/audit-share` (or `/share-audit`) | Batch-review personal knowledge for promotion to per-repo `_project-knowledge/` (opt-in via `projects_shared_knowledge`) |
| `/context [tags]` | Load relevant knowledge by topic — surfaces team-shared files alongside personal/project tiers when shared knowledge is enabled |
| `/index` | Rebuild the tag-based knowledge index |
| `/rules [number]` | Look up a working rule |
| `/backlog` | View pending intake items |
| `/stats` | Knowledge base health dashboard |
| `/ask [question]` | Research a question, save answer as a knowledge doc |
| `/clip [url or text]` | Quick-save a URL or snippet to intake |
| `/intake [path or url]` | Bulk import knowledge from files, directories, or URLs |
| `/codemap [mode]` | Generate or update a feature-organized codebase map |
| `/help` | Command reference |

## Configuration

All settings are in `~/.claude/aria-knowledge.local.md`. Run `/setup` to change them interactively, or edit directly using the schema in [CONFIG.md](CONFIG.md) — every field's type, default, and reader, plus the rules for hand-editing.

**Key settings:**
- `audit_trigger_threshold` — backlog entry count that triggers the knowledge audit prompt (default: 20). Primary activity-driven signal. Tier messaging: 20+ suggested, 35+ recommended, 50+ overdue.
- `audit_cadence_knowledge` — days between knowledge audit prompts when the entry-count trigger hasn't fired (default: 7). Safety net for low-activity weeks.
- `audit_cadence_config` — days between config audit prompts (default: 14)
- `auto_capture` — auto-capture insights at task boundaries and save transcript snapshots before compaction (default: true)
- `critical_paths` — file patterns that always require full impact assessment (default: empty)
- `planning_paths` — file patterns downgraded to the abbreviated `[Rule 22 · Planning]` marker (the inverse of `critical_paths`; a marker is still required, only the format is lighter; `critical_paths` wins any conflict) (default: empty)

See [OVERVIEW.md](template/OVERVIEW.md) for the full design philosophy and [CONFIG.md](CONFIG.md) for the configuration schema reference.
