# CLAUDE.md — ARIA

## What This Is

ARIA (Applied Reasoning and Insight Architecture) — an active knowledge and development discipline plugin for Claude Code. Three pillars: a five-phase knowledge lifecycle (capture → govern → promote → apply → refresh), decision discipline (Rule 22 enforcement at every edit), and codebase & task mapping (/codemap for repo traces, /stitch for cross-repo contract binding, /distill for task spec shaping). The "Applied" framing emphasizes the apply phase: trusted knowledge actively shapes the next decision via /context, /rules, /codemap, /stitch, /distill, and Rule 22 — not just stored and recalled.

**Repository:** GitHub (`mikeprasad/aria-knowledge`) — **public repo**

## Sibling Plugin (aria-cowork)

A Cowork-side counterpart lives at `~/Projects/aria/aria-cowork/` — **public** at `mikeprasad/aria-cowork` (CC BY-NC-SA 4.0; first public release v1.0.0 shipped 2026-05-19; v1.0.1 patch shipped same day with `.mcp.json` `google_docs` → `google docs` MCP id fix + description-length validator fixes; v1.1.0 same-day minor with `/wrapup` vs `/handoff` intent split + `/wrapup auto` mode, mirroring aria-knowledge v2.19.0). Both plugins share the user's `~/Projects/knowledge/` folder and write to the same canonical config (`aria-config.md`) under an additive-only schema (per ADR-002 in the aria-cowork knowledge folder). Edits to shared surfaces — `aria-config.md` field names, the `template/rules/` content, the `working-rules.md` rule numbering — should preserve cross-plugin compatibility. aria-cowork **v1.1.0 SHIPPED** alongside aria-knowledge v2.19.0 as a coordinated release pair — aria-cowork imports the 5 bidirectional MCP-consuming skills (clip-thread, extract-doc, meeting-notes, digest, sync-decisions) byte-faithfully per ADR-014, plus adds 1 cowork-only `/daily-audit` skill (first-message audit substitute since Cowork has no SessionStart hook per ADR-004). 26 skills (24 distinct + 2 aliases). Cowork-specific authoring constraints documented in `knowledge/guides/claude/cowork-plugin-validation.md`.

**Bidirectional feature flow (since v0.3.0 / v2.17.0):** Features may originate in either plugin and port to the other; aria-knowledge remains the schema source-of-truth (output formats, knowledge-folder conventions, archive structures). v0.3.0's `/handoff brief` and `/intake doc` modes are the first cowork-originated features ported into aria-knowledge. See aria-cowork ADR 014 for the architectural rationale.

**Bare-slash ownership (ADR-094, v2.19.1):** When both plugins are loaded in the same session (most common in Claude Desktop), 24 colliding skill names (`/handoff`, `/wrapup`, `/extract`, `/intake`, etc.) deterministically resolve to **aria-knowledge** as canonical owner. aria-cowork's variants are namespaced-only (`/aria-cowork:handoff`, etc.). Each colliding skill carries a Runtime Gate in its body that surfaces a notification when invoked from the wrong runtime (Bash-availability is the fingerprint). The gate applies even in `auto` modes — auto's "implicit-yes" rule is suspended for the runtime-mismatch check per ADR-094 §Part 3. Edits affecting cross-plugin compatibility (description prepend conventions, gate clause text, anti-trigger language) should preserve this ownership rule. Full design: [`~/Projects/knowledge/projects/aria/decisions/094-bare-slash-canonical-owner-and-dual-runtime-gate.md`](../../knowledge/projects/aria/decisions/094-bare-slash-canonical-owner-and-dual-runtime-gate.md).

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
├── plugin-codex/      ← Codex port (independent installable unit)
│   ├── .codex-plugin/
│   │   └── plugin.json
│   ├── hooks.json     ← Codex hook registration
│   ├── bin/           ← Claude-standard scripts + Codex adapter
│   ├── commands/      ← Codex command entrypoints
│   ├── skills/        ← Copied ARIA skills (schema-compatible)
│   └── template/      ← Copied Claude-standard knowledge templates
├── cursor-template/   ← Cursor port (repo-skeleton, not a plugin install)
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

- **`plugin/` is the installable unit** — everything inside it is what users copy to their plugins directory
- **`plugin-codex/` is the Codex installable unit** — independent adapter surface, same knowledge schema. Claude `plugin/` remains the standard for template/content shape.
- **`cursor-template/` is the Cursor repo-skeleton** — not a plugin install. Users clone or unzip its contents into the root of their own project. Cursor compiles 25 skills into 5 `.cursor/rules/*.mdc` files because Cursor's Rules system doesn't have a one-skill-per-folder concept. Knowledge folder schema stays compatible with `plugin/template/`.
- **Template files** in `plugin/template/` are either plugin-managed (diffable on `/setup`) or user-owned (created once, never overwritten). See `plugin/skills/setup/SKILL.md` for the authoritative list.
- **Version** lives in `plugin/.claude-plugin/plugin.json`
- **Hook scripts** in `plugin/bin/` are bash — they read config from `~/.claude/aria-knowledge.local.md`
- **Skills** are markdown files — each skill is a `SKILL.md` with YAML frontmatter
- **Codex hooks** require Codex `plugin_hooks` enabled; the adapter reads `~/.codex/aria-knowledge.local.md` first, then falls back to `~/.claude/aria-knowledge.local.md`
- **Cursor hooks** use `.cursor/hooks.json` and resolve script paths via `git rev-parse --show-toplevel`. Some Claude enforcement is weaker on Cursor (no transcript access, no documented pre-edit deny) — port uses an edit-intent marker file as the closest available mechanism. See `cursor-template/audit/ARIA_CURSOR_AUDIT_REPORT.md` §5.

## Development Workflow

1. Edit files in `plugin/`
2. To test, copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/`
3. Restart Claude Code to pick up changes

### Codex Port Workflow

1. Edit Codex adapter files in `plugin-codex/`
2. Keep durable knowledge template/schema changes in sync with `plugin/` — Claude remains the schema standard
3. Enable Codex plugin hooks with `codex features enable plugin_hooks` before testing automatic hooks
4. Install via `.agents/plugins/marketplace.json` or copy `plugin-codex/` into a Codex local marketplace

### Cursor Port Workflow

1. Edit Cursor adapter files in `cursor-template/`
2. Keep durable knowledge surfaces in sync with `plugin/template/` — Claude remains the schema standard. Knowledge folder shape lives at `cursor-template/knowledge/` (root-level, not nested under `template/`).
3. The 5 `.mdc` rule files (`aria-commands`, `aria-audit`, `aria-context`, `aria-core`, `aria-rule-22`) are *compiled* views of the 25 canonical skills in `plugin/skills/`. When a skill changes, the corresponding section in the `.mdc` file needs a matching edit — no auto-build pipeline exists yet.
4. Users install by unzipping the cursor port artifact (or cloning the folder) into the root of their own project, then restarting Cursor.

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
- `knowledge/rules/working-rules.md` — the 34 universal rules (ARIA's source of truth ships in plugin/template)
- `knowledge/rules/change-decision-framework.md` — Rule 22 framework
- `knowledge/rules/enforcement-mechanisms.md` — enforcement tier model
- `knowledge/guides/claude/plugin-development.md` — Claude Code plugin patterns
- `knowledge/guides/claude/cowork-plugin-validation.md` — Claude Cowork plugin patterns (sibling guide; relevant if coordinating with aria-cowork or shipping a Cowork-side plugin)

Pre-staged ADR candidates live in `~/Projects/knowledge/intake/decisions-backlog.md` — check there for what's currently queued for next `/audit-knowledge`. Themes queued here historically drift as ADRs promote; the live backlog is the source of truth.

Use `/context aria` to load relevant knowledge by project tag.
