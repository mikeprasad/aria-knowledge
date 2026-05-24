# ARIA Knowledge

ARIA (Applied Reasoning and Insight Architecture) is active in this repository.
It maintains a persistent knowledge base at `knowledge/` and enforces structured edit discipline.

## Configuration

Config is at `.cursor/aria-knowledge.local.md`. Run the setup command below if it does not exist.

## Commands

| Command / Ask | What it does |
|---|---|
| `/setup` or "set up ARIA" | Configure knowledge folder and preferences |
| `/help` or "aria help" | Print the full command reference |
| `/extract` or "extract session knowledge" | Capture decisions, insights, references from this conversation |
| `/audit-knowledge` (alias `/knowledge-audit`) or "audit knowledge" | Review intake backlogs, promote approved items |
| `/audit-config` (alias `/config-audit`) or "audit config" | Check project configs and docs for drift |
| `/audit-share` (alias `/share-audit`) or "share knowledge" | Batch-review personal knowledge for promotion to team-shared project knowledge (requires `projects_enabled: true`) |
| `/context <tags>` or "load knowledge about X" | Load relevant knowledge files by tag |
| `/index` or "rebuild knowledge index" | Rebuild `knowledge/index.md` |
| `/rules <number>` or "show rule N" | Look up a working rule by number |
| `/backlog` or "show backlog" | View pending intake items |
| `/stats` or "knowledge stats" | Knowledge base health dashboard |
| `/ask <question>` or "research and save: X" | Research a question, save answer as a knowledge doc |
| `/clip <url or text>` or "save this" | Quick-save URL or snippet to `knowledge/intake/clippings/` |
| `/intake <path>` or "import from file" | Bulk import knowledge from files or URLs |
| `/codemap` or "map the codebase" | Generate a feature-organized `CODEMAP.md` |
| `/distill <text or path>` or "shape a task spec" | Tiered task spec from raw text; `--group` loads CODEMAP context |
| `/stitch <mode> <group>` or "stitch repos" | Cross-repo binding (auth/endpoints/entities/drift) for a product group |
| `/prospect <plan>` or "pre-mortem this plan" | Plan pre-mortem with risk enforcement + Evidence-Sourcing Pass |
| `/retrospect [--range/--pr/--session/--commit]` or "retrospective" | Structured retrospective on shipped work — per-fix validation, simpler-alternative discipline, action verdicts |
| `/handoff [auto]` or "handoff session" | Express handoff — paste-ready next-session opener |
| `/snapshot` or "capture task boundary" | Write a non-transcript task-boundary capture under `intake/task-boundary-captures/` (git + hook + config state) |
| `/wrapup` or "wrap up session" | End-of-session handoff — update tracking, prompt to extract and commit |

Full skill instructions are in `.cursor/rules/`. Aliases (`/knowledge-audit`, `/config-audit`, `/share-audit`) are accepted as alternate phrasings of their canonical commands.

## Rule 22 — Edit Discipline (MANDATORY)

Before every file edit, emit a change decision block:

For low-impact changes:
```
[Rule 22] LOW IMPACT — <one-line description>
Scope: <what files/functions are affected>
Alternatives considered: <what else was evaluated>
```

For high-impact changes:
```
[Rule 22] HIGH IMPACT — <one-line description>
Scope: <full impact surface>
Alternatives considered: <options evaluated>
Risk: <what could go wrong>
Rollback: <how to undo>
```

This block MUST appear ABOVE (before) the Edit/Write tool call in the same turn.
Do NOT emit it after the edit. Do NOT skip it for "trivial", "docs-only", or "routine" changes.

**Edit-intent marker (Cursor-native enforcement).** Before invoking Edit/Write, run:

```bash
bash scripts/aria/record-edit-intent.sh <filePath> rule22-low|rule22-high "<one-line rationale>"
```

This writes `.cursor/aria-edit-intent.json` with the filePath, sessionId, marker type, rationale, and timestamp. The `beforeFileEdit` hook reads it and verifies a recent (<10 min) marker matching the file being edited. Missing / stale / mismatched markers escalate the advisory wording — for protected files, the hook calls out the violation explicitly. The marker is consumed (deleted) by `afterFileEdit` on a successful matching edit, so each edit needs its own fresh marker.

After every edit, verify scope was not exceeded and check for unintended side effects on parent, sibling, or dependent files.

Signs that a change is HIGH IMPACT: touches auth, migrations, data models, routing, external service integrations, or any file in `critical_paths` config.

## Context Surfacing (Automatic)

When a new task is stated, before responding:
1. Read `knowledge/index.md`
2. Parse the `## Tag Index` section for `### tagname` entries
3. Tokenize the task text (lowercase, alphanumeric only, deduplicated)
4. Find tags whose names exactly match any token
5. If 2 or more tags match: collect file paths under those tag sections, deduplicate, cap at 5
6. Read each matched file
7. Output 1-2 sentences naming which files were loaded and why

Repeat on clear topic change within the session.

## Knowledge Lifecycle

Knowledge moves through five phases. Never auto-promote without explicit user approval:

1. **Capture** — surface insights and decisions during work. Use `/extract` at task boundaries.
2. **Govern** — run `/audit-knowledge` to review backlogs. Nothing reaches permanent files without your approval.
3. **Promote** — approved items go to their permanent home by type:
   - `rules/` — principles and constraints
   - `approaches/` — validated methodologies
   - `decisions/` — architectural choices with context and consequences
   - `guides/` — operational knowledge
   - `references/` — external research and evaluations
4. **Apply** — load relevant knowledge with `/context <tag>` before coding.
5. **Refresh** — `/audit-knowledge` and `/audit-config` on cadence. Session-start hook prompts when due.

## Session Start Behavior

At session start, the hook checks whether knowledge audits, config audits, or a setup update are due.
If any are due, you will receive a prompt. Note the prompt but you do not need to act immediately.

## Config Reference

`.cursor/aria-knowledge.local.md` YAML frontmatter fields:

| Field | Default | Purpose |
|---|---|---|
| `knowledge_folder` | required | Absolute path to knowledge repo |
| `audit_cadence_knowledge` | 7 | Days between knowledge audit prompts |
| `audit_cadence_config` | 14 | Days between config audit prompts |
| `audit_trigger_threshold` | 20 | Backlog entry count that triggers knowledge audit prompt |
| `auto_capture` | true | Auto-capture task-boundary insights |
| `active_knowledge_surfacing` | true | Enable automatic context surfacing on task start |
| `critical_paths` | empty | Comma-separated path patterns always requiring HIGH IMPACT assessment |
