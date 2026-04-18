# ARIA Quick Start

Your first 3 sessions with aria-knowledge — knowledge capture, decision discipline, and codebase mapping.

## After Install

Run `/setup` to configure your knowledge folder. This creates the folder structure and sets preferences. Everything else is automatic.

**What's immediately active:**
- **Rule 22 checks** appear before every file edit — a brief impact assessment to keep changes intentional
- **Session start** checks if any audits are due and reminds you
- **Insight capture** auto-appends Insight blocks to backlogs at task completion boundaries

## Session 1: Just Work

Work normally. ARIA observes in the background. Insight blocks are auto-captured at task boundaries.

Before wrapping up, run **`/extract`** to capture decisions, feedback, and references from the conversation. Items go to intake backlogs for review — nothing is promoted automatically.

## Session 2: Review and Promote

The session-start hook will prompt: *"Want me to scan for extractable knowledge?"*

Run **`/audit-knowledge`** to review what's been captured:
- Approve items to promote them into your knowledge repository
- Reject items to clear them from backlogs
- Themes across multiple entries get flagged for synthesis

Run **`/index`** to build a tag-based index of your knowledge files.

## Session 3: Knowledge Works For You

With an index built, ARIA surfaces relevant knowledge automatically:
- **`/context [tags]`** loads knowledge files matching your topic
- When you create tasks, ARIA checks if related knowledge exists and tells you
- **`/stats`** shows your knowledge base health at a glance

## Commands at a Glance

| Command | What it does |
|---------|-------------|
| `/setup` | Configure plugin, check for updates |
| `/extract` | Capture knowledge from current conversation |
| `/audit-knowledge` | Review backlogs and promote to knowledge files |
| `/audit-config` | Check project configs and docs for drift |
| `/context [tags]` | Load relevant knowledge by topic |
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

All settings are in `~/.claude/aria-knowledge.local.md`. Run `/setup` to change them, or edit directly.

**Key settings:**
- `audit_trigger_threshold` — backlog entry count that triggers the knowledge audit prompt (default: 20). Primary activity-driven signal. Tier messaging: 20+ suggested, 35+ recommended, 50+ overdue.
- `audit_cadence_knowledge` — days between knowledge audit prompts when the entry-count trigger hasn't fired (default: 7). Safety net for low-activity weeks.
- `audit_cadence_config` — days between config audit prompts (default: 14)
- `auto_capture` — auto-capture insights at task boundaries and save transcript snapshots before compaction (default: true)
- `critical_paths` — file patterns that always require full impact assessment (default: empty)

See [OVERVIEW.md](template/OVERVIEW.md) for the full design philosophy and detailed documentation.
