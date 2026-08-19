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
| `/audit` or "run an audit" | Dispatcher for knowledge / config / style / usage sub-audits |
| `/audit-knowledge` (alias `/knowledge-audit`) or "audit knowledge" | Review intake backlogs, promote approved items |
| `/audit-config` (alias `/config-audit`) or "audit config" | Check project configs and docs for drift |
| `/audit style` or "mine my working style" | Evidence-gated working-style rules from session transcripts (opt-in) |
| `/audit usage` or "is ARIA worth it" | Value/ROI report over your own knowledge corpus (opt-in) |
| `/audit-share` (alias `/share-audit`) or "share knowledge" | Batch-review personal knowledge for promotion to team-shared project knowledge (requires `projects_enabled: true`) |
| `/context <tags>` or "load knowledge about X" | Load relevant knowledge files by tag |
| `/index` or "rebuild knowledge index" | Rebuild `knowledge/index.md` |
| `/rules <number>` or "show rule N" | Look up a working rule by number |
| `/backlog` or "show backlog" | View pending intake items |
| `/stats` or "knowledge stats" | Knowledge base health dashboard |
| `/ask <question>` or "research and save: X" | Research a question, save answer as a knowledge doc |
| `/intake` or "save this" / "import from file" | Clip a URL/text, bulk-import files, or `/intake extract` / `doc` / `thread` |
| `/meeting-notes` or "capture meeting notes" | Fold meeting transcript into `intake/meetings/` (MCP or paste) |
| `/digest` or "weekly digest" | Cross-tool rollup into `intake/digests/` |
| `/sync-decisions` or "mirror decisions to wiki" | Push approved decisions to external docs (MCP write) |
| `/codemap` or "map the codebase" | Generate a feature-organized `CODEMAP.md` |
| `/distill <text or path>` or "shape a task spec" | Tiered task spec from raw text; `--group` loads CODEMAP context |
| `/stitch <mode> <group>` or "stitch repos" | Cross-repo binding (auth/endpoints/entities/drift) for a product group |
| `/prospect <plan>` or "pre-mortem this plan" | Plan pre-mortem with risk enforcement + Evidence-Sourcing Pass |
| `/retrospect [--range/--pr/--session/--commit]` or "retrospective" | Structured retrospective on shipped work — per-fix validation, simpler-alternative discipline, action verdicts |
| `/preflight` or "preflight this" | Pre-completion checklist before claiming done / shipping / posting a result |
| `/auto` or "just build it" / "run this arc" | Autonomous execution arc (Rule 35). Cursor: no CronCreate / statusline / self-restart |
| `/roadmap` or "show the roadmap" | Per-project Band×Status feature grid from AGENTS.md + PROGRESS.md |
| `/recap` or "what just happened" | Read-only orientation table; `/recap project [name\|all]` for roster glance |
| `/interview` or "interview me about this" | Guided Q&A to capture tacit knowledge |
| `/foundational-review` / `/readiness-audit` | Decision-anchored review / recurring readiness audit |
| `/handoff [auto\|brief\|snap]` or "handoff session" | Passoff — next-session opener or coworker brief |
| `/snapshot` or "capture task boundary" | Write a non-transcript task-boundary capture under `intake/task-boundary-captures/` (git + hook + config state) |
| `/wrapup [auto\|snap]` or "wrap up session" | Session close-out — update tracking, commit, capture via /extract |

Full skill instructions are in `.cursor/rules/`. Aliases (`/knowledge-audit`, `/config-audit`, `/share-audit`) are accepted as alternate phrasings of their canonical commands. `/audit knowledge|config|style|usage` routes through the `/audit` dispatcher.

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
| `session_state` | false | Enable SESSION.md producer + resume (atlas integration) |
| `session_state_tracked` | false | If true, SESSION.md is committed (not gitignored). Workspace repos often want `true` |
| `session_stale_days` | 7 | Age after which a saved resume prompt is treated as possibly-stale |
| `autonomy` | default | SessionStart Rule 35 posture: `default` (silent) / `balanced` / `autonomous` |
| `planning_paths` | empty | Path patterns that downgrade Rule 22 to the abbreviated planning marker (protect always wins) |
| `preflight_gate` | warn | `off` / `warn` / `deny` on `git commit` with no `/preflight` this session |
| `preflight_deny_paths` | empty | Staged-path globs that deny a commit regardless of baseline |
| `preflight_deny_repos` | empty | Substrings matched against the commit's git toplevel (deny regardless of baseline) |
| `external_fetch_gate` | off | When `on`, first WebFetch/WebSearch per surface that local files already cover is denied once |
| `external_fetch_max_hits` | 8 | Ambient-surface cap — above this many matching files the fetch gate stays silent |
| `style_lookback_days` | 90 | `/audit style` first-run lookback window |
| `style_max_sessions` | 50 | `/audit style` over-cap gate |
| `subagent_capture` | true | Archive subagent transcripts on subagentStop |
| `subagent_capture_types` | generalPurpose,explore,shell,... | Subagent types to archive |
| `subagent_selfreport_types` | explore | Subagent types that get self-report nudge |
| `auto_prospect` | off | nudge/run after plan writes (`docs/plans/`, `docs/superpowers/plans/`) |
| `auto_retrospect` | off | nudge/run after qualifying `git push` |
| `retrospect_min_commits` | 3 | Minimum commits in push range to trigger auto-retrospect |
| `retrospect_branches` | main,master,production | Branches eligible for auto-retrospect |
| `usage_alert_threshold` | off (Cursor) | Claude Code only — requires `/statusline` meter |
| `critical_paths` | empty | Comma-separated path patterns always requiring HIGH IMPACT assessment |
