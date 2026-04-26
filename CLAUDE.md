# CLAUDE.md — ARIA

## What This Is

ARIA (Applied Reasoning and Insight Architecture) — an active knowledge and development discipline plugin for Claude Code. Three pillars: knowledge lifecycle (capture → review → promote), decision discipline (Rule 22 enforcement at every edit), and codebase & task mapping (/codemap for repo traces, /stitch for cross-repo contract binding, /distill for task spec shaping).

**Repository:** GitHub (`mikeprasad/aria-knowledge`) — **public repo**

## Project Structure

```
aria/
├── README.md          ← GitHub-facing intro
├── LICENSE            ← CC BY-NC-SA 4.0
├── CHANGELOG.md       ← Version history
├── CLAUDE.md          ← You are here
├── plugin/            ← The installable plugin
│   ├── .claude-plugin/
│   │   └── plugin.json
│   ├── bin/           ← Hook scripts (bash)
│   ├── skills/        ← Skill definitions (SKILL.md files)
│   └── template/      ← Knowledge folder templates
└── docs/              ← Extended documentation (future)
```

## Key Conventions

- **`plugin/` is the installable unit** — everything inside it is what users copy to their plugins directory
- **Template files** in `plugin/template/` are either plugin-managed (diffable on `/setup`) or user-owned (created once, never overwritten). See `plugin/skills/setup/SKILL.md` for the authoritative list.
- **Version** lives in `plugin/.claude-plugin/plugin.json`
- **Hook scripts** in `plugin/bin/` are bash — they read config from `~/.claude/aria-knowledge.local.md`
- **Skills** are markdown files — each skill is a `SKILL.md` with YAML frontmatter

## Development Workflow

1. Edit files in `plugin/`
2. To test, copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/`
3. Restart Claude Code to pick up changes

## Rules

- Follow the universal rules in `Projects/CLAUDE.md`
- **This is a public repository** — never commit personal information, API keys, secrets, credentials, internal URLs, or any sensitive data. Content here is visible to anyone on GitHub.
- The plugin's own template content (working-rules, change-decision-framework, enforcement-mechanisms) is both shipped content AND documentation of how the plugin works — edits to these have dual impact
- Bump version in `plugin.json` when making release-worthy changes

## Knowledge Repository

Project-specific architecture decisions live in `~/Projects/knowledge/projects/aria/`:

- `decisions/002-knowledge-extraction-architecture.md` — task-based /extract + audit promotion model
- `decisions/006-full-rule22-format-every-edit.md` — full format on every edit (no compression)
- `decisions/008-skill-knowledge-connections.md` — skill-knowledge connection discovery + drift detection

Cross-project knowledge that applies to ARIA:
- `knowledge/rules/working-rules.md` — the 31 universal rules (ARIA's source of truth ships in plugin/template)
- `knowledge/rules/change-decision-framework.md` — Rule 22 framework
- `knowledge/rules/enforcement-mechanisms.md` — enforcement tier model
- `knowledge/guides/claude/plugin-development.md` — Claude Code plugin patterns

Pre-staged ADR candidates live in `~/Projects/knowledge/intake/decisions-backlog.md` — check there for what's currently queued for next `/audit-knowledge`. Themes queued here historically drift as ADRs promote; the live backlog is the source of truth.

Use `/context aria` to load relevant knowledge by project tag.
