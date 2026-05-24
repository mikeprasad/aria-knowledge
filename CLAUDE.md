# CLAUDE.md — ARIA

## What This Is

ARIA (Applied Reasoning and Insight Architecture) — an active knowledge and development discipline plugin for Claude Code. Three pillars: a five-phase knowledge lifecycle (capture → govern → promote → apply → refresh), decision discipline (Rule 22 enforcement at every edit), and codebase & task mapping (/codemap for repo traces, /stitch for cross-repo contract binding, /distill for task spec shaping). The "Applied" framing emphasizes the apply phase: trusted knowledge actively shapes the next decision via /context, /rules, /codemap, /stitch, /distill, and Rule 22 — not just stored and recalled.

**Repository:** GitHub (`mikeprasad/aria-knowledge`) — **public repo**

## Cowork Port (plugin-claude-cowork/)

The Claude Cowork port lives at `plugin-claude-cowork/` — consolidated into this repo in v2.20.0 (2026-05-24) from the previously standalone `mikeprasad/aria-cowork` (last standalone release: v1.1.0, 2026-05-19). Both ports share the user's `~/Projects/knowledge/` folder and write to the same canonical config (`aria-config.md`) under an additive-only schema (per ADR-002). Edits to shared surfaces — `aria-config.md` field names, `template/rules/` content, `working-rules.md` rule numbering — must preserve cross-port compatibility. 26 skills (24 distinct + 2 aliases). Cowork-specific authoring constraints documented in `knowledge/guides/claude/cowork-plugin-validation.md`.

**Bidirectional feature flow (since v0.3.0 / v2.17.0):** Features may originate in either port and port to the other; plugin-claude-code remains the schema source-of-truth (output formats, knowledge-folder conventions, archive structures). v0.3.0's `/handoff brief` and `/intake doc` modes are the first cowork-originated features ported into aria-knowledge. See plugin-claude-cowork ADR-014 for the architectural rationale.

**Bare-slash ownership (ADR-094, v2.19.1):** When both ports are loaded in the same session (most common in Claude Desktop), 24 colliding skill names (`/handoff`, `/wrapup`, `/extract`, `/intake`, etc.) deterministically resolve to **plugin-claude-code** as canonical owner. plugin-claude-cowork's variants are namespaced-only (`/aria-cowork:handoff`, etc.). Each colliding skill carries a Runtime Gate in its body that surfaces a notification when invoked from the wrong runtime (Bash-availability is the fingerprint). The gate applies even in `auto` modes — auto's "implicit-yes" rule is suspended for the runtime-mismatch check per ADR-094 §Part 3. Edits affecting cross-port compatibility (description prepend conventions, gate clause text, anti-trigger language) should preserve this ownership rule. Full design: [`~/Projects/knowledge/projects/aria/decisions/094-bare-slash-canonical-owner-and-dual-runtime-gate.md`](../../knowledge/projects/aria/decisions/094-bare-slash-canonical-owner-and-dual-runtime-gate.md).

## Project Structure

```
aria/
├── README.md          ← GitHub-facing intro
├── LICENSE            ← CC BY-NC-SA 4.0
├── CHANGELOG.md       ← Version history
├── CLAUDE.md          ← You are here
├── plugin-claude-code/            ← The installable plugin
│   ├── .claude-plugin/
│   │   └── plugin.json
│   ├── bin/           ← Hook scripts (bash)
│   ├── skills/        ← Skill definitions (SKILL.md files)
│   └── template/      ← Knowledge folder templates
├── plugin-openai-codex/      ← Codex port (independent installable unit)
│   ├── .codex-plugin/
│   │   └── plugin.json
│   ├── hooks.json     ← Codex hook registration
│   ├── bin/           ← Claude-standard scripts + Codex adapter
│   ├── commands/      ← Codex command entrypoints
│   ├── skills/        ← Copied ARIA skills (schema-compatible)
│   └── template/      ← Copied Claude-standard knowledge templates
├── plugin-claude-cowork/     ← Cowork port (skills-only; no hooks API in Cowork runtime)
│   ├── .claude-plugin/
│   │   └── plugin.json
│   ├── skills/        ← 26 skills (24 distinct + 2 aliases)
│   ├── template/      ← Knowledge folder templates (schema mirror of plugin-claude-code/)
│   ├── .mcp.json      ← 12 MCP servers across 4 categories
│   └── release.sh     ← Builds aria-cowork-<version>.plugin
├── plugin-cursor-template/   ← Cursor port (repo-skeleton, not a plugin install)
│   ├── .cursor/       ← Cursor-native config
│   │   ├── hooks.json
│   │   ├── aria-knowledge.local.md
│   │   └── rules/     ← 5 compiled .mdc files (25 skills compiled into 5)
│   ├── AGENTS.md      ← Cursor's equivalent of CLAUDE.md
│   ├── QUICKSTART.md  ← Cursor-adapted quickstart
│   ├── knowledge/     ← Knowledge folder (lives at root in Cursor port, not under template/)
│   ├── scripts/aria/  ← Hook scripts (instead of bin/)
│   └── audit/         ← Frozen audit artifacts for the 2.16.1 port build
└── docs/              ← Extended documentation (future)
```

## Key Conventions

- **`plugin-claude-code/` is the installable unit** — everything inside it is what users copy to their plugins directory
- **`plugin-openai-codex/` is the Codex installable unit** — independent adapter surface, same knowledge schema. Claude `plugin-claude-code/` remains the standard for template/content shape.
- **`plugin-cursor-template/` is the Cursor repo-skeleton** — not a plugin install. Users clone or unzip its contents into the root of their own project. Cursor compiles 25 skills into 5 `.cursor/rules/*.mdc` files because Cursor's Rules system doesn't have a one-skill-per-folder concept. Knowledge folder schema stays compatible with `plugin-claude-code/template/`.
- **Template files** in `plugin-claude-code/template/` are either plugin-managed (diffable on `/setup`) or user-owned (created once, never overwritten). See `plugin-claude-code/skills/setup/SKILL.md` for the authoritative list.
- **Version** lives in `plugin-claude-code/.claude-plugin/plugin.json`
- **Hook scripts** in `plugin-claude-code/bin/` are bash — they read config from `~/.claude/aria-knowledge.local.md`
- **Skills** are markdown files — each skill is a `SKILL.md` with YAML frontmatter
- **Codex hooks** require Codex `plugin_hooks` enabled; the adapter reads `~/.codex/aria-knowledge.local.md` first, then falls back to `~/.claude/aria-knowledge.local.md`
- **`plugin-claude-cowork/` is the Claude Cowork installable unit** — sibling to plugin-claude-code/, both share schema-identical knowledge-folder outputs (per ADR-013). Cowork runtime is skills-only (no hooks API); enforcement is skill-embedded. Per ADR-094, bare-slash skill names resolve to plugin-claude-code as canonical owner when both ports are loaded in the same session; cowork-namespaced variants are `/aria-cowork:handoff` etc.
- **Cursor hooks** use `.cursor/hooks.json` and resolve script paths via `git rev-parse --show-toplevel`. Some Claude enforcement is weaker on Cursor (no transcript access, no documented pre-edit deny) — port uses an edit-intent marker file as the closest available mechanism. See `plugin-cursor-template/audit/ARIA_CURSOR_AUDIT_REPORT.md` §5.

## Development Workflow

1. Edit files in `plugin-claude-code/`
2. To test, copy `plugin-claude-code/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/`
3. Restart Claude Code to pick up changes

### Codex Port Workflow

1. Edit Codex adapter files in `plugin-openai-codex/`
2. Keep durable knowledge template/schema changes in sync with `plugin-claude-code/` — Claude remains the schema standard
3. Enable Codex plugin hooks with `codex features enable plugin_hooks` before testing automatic hooks
4. Install via `.agents/plugins/marketplace.json` or copy `plugin-openai-codex/` into a Codex local marketplace

### Cursor Port Workflow

1. Edit Cursor adapter files in `plugin-cursor-template/`
2. Keep durable knowledge surfaces in sync with `plugin-claude-code/template/` — Claude remains the schema standard. Knowledge folder shape lives at `plugin-cursor-template/knowledge/` (root-level, not nested under `template/`).
3. The 5 `.mdc` rule files (`aria-commands`, `aria-audit`, `aria-context`, `aria-core`, `aria-rule-22`) are *compiled* views of the 25 canonical skills in `plugin-claude-code/skills/`. When a skill changes, the corresponding section in the `.mdc` file needs a matching edit — no auto-build pipeline exists yet.
4. Users install by unzipping the cursor port artifact (or cloning the folder) into the root of their own project, then restarting Cursor.

### Cowork Port Workflow

1. Edit Cowork-specific files in `plugin-claude-cowork/`. Most skills mirror `plugin-claude-code/` via ADR-013 schema-identical outputs; cowork-specific skills (`daily-audit`, cowork-modified `/extract-doc`, etc.) live only here.
2. Keep MCP-consuming skills (clip-thread, extract-doc, meeting-notes, digest, sync-decisions) byte-faithful between ports per ADR-014; plugin-claude-code remains schema source-of-truth.
3. Per ADR-094, when both ports load in the same session, bare-slash command names (`/handoff`, `/extract`, etc.) resolve to plugin-claude-code as canonical owner; cowork-namespaced variants are `/aria-cowork:handoff` etc.
4. Build with `./release.sh` in `plugin-claude-cowork/` — produces `aria-cowork-<version>.plugin`. Install by dragging into a Cowork conversation or via Settings → Plugins → Install from file.
5. Cowork runs as a skills-only plugin (no hooks API). The `/daily-audit` skill substitutes for SessionStart on first message.

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
- `knowledge/rules/working-rules.md` — the 34 universal rules (ARIA's source of truth ships in plugin-claude-code/template)
- `knowledge/rules/change-decision-framework.md` — Rule 22 framework
- `knowledge/rules/enforcement-mechanisms.md` — enforcement tier model
- `knowledge/guides/claude/plugin-development.md` — Claude Code plugin patterns
- `knowledge/guides/claude/cowork-plugin-validation.md` — Claude Cowork plugin patterns (sibling guide; relevant if coordinating with aria-cowork or shipping a Cowork-side plugin)

Pre-staged ADR candidates live in `~/Projects/knowledge/intake/decisions-backlog.md` — check there for what's currently queued for next `/audit-knowledge`. Themes queued here historically drift as ADRs promote; the live backlog is the source of truth.

Use `/context aria` to load relevant knowledge by project tag.
