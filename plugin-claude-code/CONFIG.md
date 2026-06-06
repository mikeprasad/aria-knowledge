# ARIA Configuration Schema

Canonical reference for `~/.claude/aria-knowledge.local.md` — every field, what reads it, what's safe to hand-edit. Run `/setup` to configure interactively, or edit directly using the rules below.

## File shape

YAML frontmatter between `---` delimiters, optional markdown body for human notes. Keys are at column 1. Values are unquoted. Empty values are bare `key:` (never `null`, `""`, `none`, or `[]`).

```yaml
---
knowledge_folder: /absolute/path/to/knowledge
audit_cadence_knowledge: 7
…
projects_groups:
  acme:
    backend: acme-server
    web: acme-web
---

# Knowledge Tools Configuration

Configured by /setup on YYYY-MM-DD.
```

## Two parser tiers

ARIA fields split into two classes by who reads them. The split is structural, not stylistic — see ADR 028 (YAML frontmatter for skill fields).

| Tier | Reader | Constraint | Field shapes allowed |
|---|---|---|---|
| **Hook-parsed** | `bin/*.sh` scripts (pure grep+sed, no jq) | Must round-trip through column-1 grep + simple sed | Single-line scalar or comma-separated `tag:value` flat string |
| **Skill-only** | Skills (Claude parses YAML natively in skill context) | Free YAML — multi-line nested blocks are fine | Any valid YAML structure |

Hook-parsed fields run on every session start, every edit, every compaction — they need to be cheap and bash-safe. Skill-only fields are read inside specific skills, so they can use the structures that fit the data.

`/setup` Step 7b validates hook-parsed fields strictly (round-trip extraction match) and skill-only fields structurally (well-formed YAML, no flatten attempts).

## Hook-parsed fields

| Field | Type | Default | Read by |
|---|---|---|---|
| `knowledge_folder` | absolute path | (required) | All hooks + skills |
| `audit_cadence_knowledge` | integer (days) | 7 | session-start-check.sh |
| `audit_trigger_threshold` | integer (entries) | 20 | session-start-check.sh |
| `audit_cadence_config` | integer (days) | 14 | session-start-check.sh |
| `audit_cadence_update` | integer (days) | 30 | session-start-check.sh |
| `last_setup_version` | semver string | (set by `/setup`) | session-start-check.sh |
| `explanatory_plugin` | `true` \| `false` | (detected by `/setup`) | extract skill |
| `freeform_promotion_threshold` | integer | 3 | audit-knowledge skill |
| `staleness_threshold_months` | integer | 6 | audit-knowledge skill |
| `ideas_staleness_threshold_days` | integer | 7 | audit-knowledge skill |
| `auto_capture` | `true` \| `false` | true | pre-compact-check.sh, extract skill |
| `active_knowledge_surfacing` | `true` \| `false` | true | session-start-check.sh, task-context-check.sh, bash-cd-check.sh, post-compact-check.sh, /prospect, /retrospect, /audit-config, /stats, /handoff, /wrapup (v2.16.1+ also gates CODEMAP+STITCH tracked-artifact loading) |
| `critical_paths` | comma-separated patterns | empty | pre-edit-check.sh |
| `ticketing_plugins` | `tag:command` pairs | empty | audit-knowledge skill |
| `projects_enabled` | `true` \| `false` | false | session-start-check.sh, audit-knowledge skill |
| `projects_list` | `tag:path` pairs | empty | session-start-check.sh, distill, stitch |
| `projects_remotes` | `tag:url-substring` pairs | empty | session-start-check.sh |
| `projects_promotion_threshold` | integer ≥ 1 | 2 | audit-knowledge skill |
| `auto_load_project_context` | `true` \| `false` | false | session-start-check.sh |
| `session_start_project_picker` | `true` \| `false` | false | session-start-check.sh |
| `projects_labels` | `tag:Label` pairs | empty | session-start-check.sh |
| `subagent_capture` | `true` \| `false` | true | subagent-stop-capture.sh, subagent-start-selfreport.sh |
| `subagent_capture_types` | comma-separated agent types | `general-purpose,Plan,feature-dev:code-architect,feature-dev:code-explorer,feature-dev:code-reviewer` | subagent-stop-capture.sh |
| `subagent_selfreport_types` | comma-separated agent types | `Explore` | subagent-start-selfreport.sh |
| `auto_prospect` | `off` \| `nudge` \| `run` | off | post-plan-prospect-check.sh |
| `auto_retrospect` | `off` \| `nudge` \| `run` | off | post-push-retrospect-check.sh |
| `retrospect_min_commits` | integer | 3 | post-push-retrospect-check.sh |
| `retrospect_branches` | comma-separated branch names | `main,master,production` | post-push-retrospect-check.sh |
| `usage_alert_threshold` | integer 1–100 \| `off` | 80 | usage-threshold-inject.sh |

### Format rules (hook-parsed fields)

- Each key starts at column 1, no indentation, exact name match
- Values unquoted: `knowledge_folder: /path` not `"/path"`
- Empty values: bare `key:` only — `null` / `""` / `none` / `[]` are parsed as literal strings
- Booleans: lowercase `true` / `false` only (not `True`, `yes`, `1`)
- Cadences and integers: bare digits, no units
- `last_setup_version`: bare semver (`2.12.2`), no `v` prefix, no quotes
- `tag:value` pair fields: no spaces around `:` or `,`; tags may not contain `:` or `,` (parser delimiters)
- `ticketing_plugins` command values: bare names without leading `/` (the audit prepends the slash)
- No blank lines between frontmatter entries

## Skill-only fields

Skill-only fields use multi-line nested YAML blocks because their consumers (`/distill`, `/stitch`) parse YAML in Claude's skill context, not via bash. They live at the **end** of the frontmatter so the indented sub-keys can't be mistaken for column-1 hook-parsed keys.

### `projects_groups` — multi-repo group mapping

Read by `/distill --group=<tag>` and `/stitch <mode> <tag>` to resolve a project tag to its sub-repo folder layout. Required for any project that contains multiple repositories under one root (e.g., a Django backend + React web + React Native mobile in adjacent sibling directories).

**Schema:**

```yaml
projects_groups:
  <tag>:
    <role>: <relative-folder-name>
    <role>: <relative-folder-name>
    stitch_path: <relative-path>   # optional, /stitch only
```

**Standard role names** (recognized by the auto-propose bootstrap in `/distill` and `/stitch`):

| Role | Inferred from | Used by |
|---|---|---|
| `backend` | `manage.py`+`settings.py` (Django), `composer.json`+`artisan` (Laravel), `Gemfile` with `rails`, `package.json` with `express`/`fastify`/`nestjs` | `/stitch` (BACKEND_ROOT), `/distill` (cited paths) |
| `web` | `next.config.*` (Next.js), `package.json` with `react` (no `next`/`expo`) | `/stitch` (FRONTEND_ROOTS), `/distill` |
| `mobile` | `app.json` + `expo` in `package.json` | `/stitch` (FRONTEND_ROOTS), `/distill` |

Custom roles are allowed — `analytics: metabase-server`, `worker: celery-jobs`, `web-admin: ops-dashboard`, etc. The auto-propose bootstrap will prompt for a role name when it can't infer one. `/stitch` treats every non-`backend` role as a frontend.

**`stitch_path` sub-field (optional, since v2.10):** override where `/stitch` writes `STITCH.md`. Default is `<project_root>/STITCH.md`. Use this for monorepo layouts or workspace conventions that put binding artifacts under `docs/contracts/` etc. See ADR 034 (stitch workspace root).

**Example — multi-repo group with three frontend layers and an optional `stitch_path` override:**

```yaml
projects_groups:
  acme:
    backend: acme-server
    web: acme-web
    mobile: acme-mobile
  flux:
    backend: flux-api
    web: flux-dashboard
    stitch_path: docs/contracts/STITCH.md
```

Tag must also appear in `projects_list` so the resolver can find `<project_root>`. Folder names are relative to that project root.

**First-time setup** is normally interactive — running `/distill --group=<new-tag>` or `/stitch create <new-tag>` triggers an auto-propose bootstrap that scans the project root, infers roles, shows a preview diff, and writes the entry on approval. See ADR 032 (auto-propose bootstrap). Hand-editing this section is supported (use the schema above) but the auto-propose path is generally faster.

`/setup` does **not** offer interactive `projects_groups` editing — Step 6 surfaces the field as a "skill-only fields" pointer to this doc, and Step 7 preserves any existing block verbatim. Bootstrap belongs to the consuming skills where filesystem detection is the source of truth.

## Hand-editing checklist

Before saving manual edits to `~/.claude/aria-knowledge.local.md`:

1. Hook-parsed keys at column 1, skill-only blocks at the end of the frontmatter
2. No quotes on values; no `null` / `""` for empty
3. `tag:` keys consistent across `projects_list`, `projects_groups`, `projects_remotes`, and `ticketing_plugins` (the same tag means the same project everywhere)
4. Re-run `/setup` afterward — Step 7b round-trip verification catches formatting issues before the next session does

## Status-line meter (`/statusline`)

The CLI status-line meter (context-window bar + rolling 5-hour / 7-day plan-usage %) is **not** configured in this file. The main status line is read only from `~/.claude/settings.json`, so `/statusline` wires it there directly:

- Copies `bin/statusline-meter.sh` to `~/.claude/aria-statusline-meter.sh` (a stable path that survives plugin updates), then
- Merges a `statusLine` block into `~/.claude/settings.json` pointing at the absolute copy (existing settings preserved; a backup is written to `settings.json.aria-bak`).

It's an opt-in command, not automatic — a plugin manifest cannot register a main `statusLine`. Claude Code only (the status line is a Code feature). The 5h/7d segments render only on Pro/Max sessions, after the first response. Re-run `/statusline` after a plugin update to refresh the meter script; remove with `/statusline off`.

**Agent awareness.** When installed, the meter also persists a snapshot per account to `~/.claude/aria-statusline-state-<accountKey>.json` (`written_at`, `model`, `runtime`, `session_id`, `account_email`, `account_uuid`, `context_pct`, `five_hour_pct`, `five_hour_resets_at`, `seven_day_pct`, `seven_day_resets_at`) on each render — the only path by which the session's Claude can know its own usage, since no hook payload carries it. The file is **keyed by the resolved per-user account** (v2.24.3, ADR-099): under the standalone CLI that's `accountUuid` from `~/.claude.json` (as before); under **Claude-Desktop-hosted** Claude Code — where `~/.claude.json` is the *CLI* login, not the session account — it's resolved from the Desktop runtime (`claude-code-sessions/<acct>/` / env), so the meter + alert never read the wrong runtime's usage. The `account_email` segment renders **only on the CLI runtime** (the Desktop email isn't plainly readable); `runtime` is `cli`/`desktop`/`desktop-unknown`. Staleness/scope guards: 5h/7d are ignored past their `resets_at`; `context_pct` (per-session) is trusted only for the matching `session_id`. `refreshInterval: 30` keeps the snapshot current during idle. Consumption is **on-demand** by default (the SessionStart TASK BUDGET guardrail tells Claude to read it before `/handoff`/compaction). The `usage_alert_threshold` field (above) additionally drives `usage-threshold-inject.sh`, a `UserPromptSubmit` hook that injects a warning when context/5h/7d crosses the threshold (default 80; `off` disables). See [skills/statusline/SKILL.md](skills/statusline/SKILL.md).

## Related

- [QUICKSTART.md](QUICKSTART.md) — first-three-sessions guide
- [skills/setup/SKILL.md](skills/setup/SKILL.md) — `/setup` workflow that writes this file
- [skills/statusline/SKILL.md](skills/statusline/SKILL.md) — `/statusline` status-line meter (writes `~/.claude/settings.json`, not this file)
- [skills/distill/SKILL.md](skills/distill/SKILL.md), [skills/stitch/SKILL.md](skills/stitch/SKILL.md) — `projects_groups` consumers
- ADR 028 (YAML frontmatter for skill fields), ADR 032 (auto-propose bootstrap), ADR 034 (stitch workspace root) — design rationale for the skill-only tier
