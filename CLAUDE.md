# CLAUDE.md — ARIA

## What This Is

ARIA (Applied Reasoning and Insight Architecture) — an active knowledge and development discipline plugin for Claude Code. Three pillars: a five-phase knowledge lifecycle (capture → govern → promote → apply → refresh), decision discipline (Rule 22 enforcement at every edit), and codebase & task mapping (/codemap for repo traces, /stitch for cross-repo contract binding, /distill for task spec shaping). The "Applied" framing emphasizes the apply phase: trusted knowledge actively shapes the next decision via /context, /rules, /codemap, /stitch, /distill, and Rule 22 — not just stored and recalled.

**Repository:** GitHub (`mikeprasad/aria-knowledge`) — **public repo**

## Cowork Port (plugin-claude-cowork/)

The Claude Cowork port lives at `plugin-claude-cowork/` — consolidated into this repo in v2.20.0 (2026-05-24) from the previously standalone `mikeprasad/aria-cowork` (last standalone release: v1.1.0, 2026-05-19). **Current cowork release: v1.1.3** (2026-05-25, coordinated with aria-knowledge v2.20.2 — wrapup/handoff spec fixes: closing-heading labeling correction + auto-mode extract-always-runs invariant). Prior coordinated cowork release: v1.1.2 (with aria-knowledge v2.20.1 — ADR-094 §Part 1/2/3 gate UX revision). Both ports share the user's `~/Projects/knowledge/` folder and write to the same canonical config (`aria-config.md`) under an additive-only schema (per ADR-002). Edits to shared surfaces — `aria-config.md` field names, `template/rules/` content, `working-rules.md` rule numbering — must preserve cross-port compatibility. 26 skills (24 distinct + 2 aliases). Cowork-specific authoring constraints documented in `knowledge/guides/claude/cowork-plugin-validation.md`. **Cowork-specific release constraint**: aria-cowork release.sh enforces a 9000-char hard cap on summed SKILL.md description chars (empirical install-fail at 9233, documented v0.2.1 + v1.0.0); v2.20.1's trailing-parenthetical port-id uses a short form on cowork (`(Cowork variant — namespaced-only.)` ~36 chars) versus Code's verbose form (~96 chars), with the full ADR-094 narrative in the Runtime Gate body where no cap applies.

**Bidirectional feature flow (since v0.3.0 / v2.17.0):** Features may originate in either port and port to the other; plugin-claude-code remains the schema source-of-truth (output formats, knowledge-folder conventions, archive structures). v0.3.0's `/handoff brief` and `/intake doc` modes are the first cowork-originated features ported into aria-knowledge. See plugin-claude-cowork ADR-014 for the architectural rationale.

**Bare-slash ownership (ADR-094, v2.19.1):** When both ports are loaded in the same session (most common in Claude Desktop), 24 colliding skill names (`/handoff`, `/wrapup`, `/extract`, `/intake`, etc.) deterministically resolve to **plugin-claude-code** as canonical owner. plugin-claude-cowork's variants are namespaced-only (`/aria-cowork:handoff`, etc.). Each colliding skill carries a Runtime Gate in its body that surfaces a notification when invoked from the wrong runtime (Bash-availability is the fingerprint). The gate applies even in `auto` modes — auto's "implicit-yes" rule is suspended for the runtime-mismatch check per ADR-094 §Part 3. Edits affecting cross-port compatibility (description prepend conventions, gate clause text, anti-trigger language) should preserve this ownership rule. Full design: [`~/Projects/knowledge/projects/aria/decisions/094-bare-slash-canonical-owner-and-dual-runtime-gate.md`](../../knowledge/projects/aria/decisions/094-bare-slash-canonical-owner-and-dual-runtime-gate.md).

## Cursor Port (plugin-cursor-template/)

The Cursor port is a **repo skeleton** (not a Claude marketplace plugin). Users unzip `aria-knowledge-cursor-<version>.zip` into the root of their own project. **Current Cursor release: `2.20.2-cursor.0`** (2026-05-27, parity with plugin-claude-code v2.20.2). Prior Cursor baseline was `2.19.2-cursor.0` / audit build at canonical v2.16.1.

**What ships:** `.cursor/hooks.json`, `.cursor/rules/*.mdc` (5 compiled rule files), `.cursor/aria-knowledge.local.md`, root `AGENTS.md` (Cursor's equivalent of `CLAUDE.md`), `scripts/aria/*.sh`, and a root-level `knowledge/` mirror of `plugin-claude-code/template/`.

**Skill surface (27 commands in `aria-commands.mdc` + audits in `aria-audit.mdc`):** 22 core workflow commands + 3 aliases (documented in preambles) + 5 MCP-consuming skills (`/clip-thread`, `/extract-doc`, `/meeting-notes`, `/digest`, `/sync-decisions`) + `/help` + `/audit-share`. Includes v2.17.0 `/intake doc`, v2.20.2 wrapup/handoff auto-mode `/extract` invariants.

**Intentional Cursor divergences (do not port ADR-094 Runtime Gates per-skill):** aria-cowork is not loaded in typical Cursor sessions. A single preamble note in `aria-commands.mdc` replaces per-skill gates. Rule 22 uses an edit-intent marker (`record-edit-intent.sh`) — advisory `beforeFileEdit`, no transcript proof. No PreCompact; `stop` → `capture-task-boundary.sh` substitutes. MCP servers are user-configured in **Cursor Settings → MCP** (no bundled `.mcp.json` in the template). See `plugin-cursor-template/PORTING.md` and `plugin-cursor-template/audit/ARIA_CURSOR_AUDIT_REPORT.md` §5.

**Maintainer re-sync after canonical skill edits:**

```bash
python3 plugin-cursor-template/scripts/port-skills-to-mdc.py
./release-cursor.sh
```

`port-skills-to-mdc.py` strips Runtime Gate blocks, adapts paths (`AGENTS.md`, `.cursor/aria-knowledge.local.md`), and upserts MCP skill sections idempotently.

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
│   │   └── rules/     ← 5 compiled .mdc files (27 commands in aria-commands + audits)
│   ├── AGENTS.md      ← Cursor's equivalent of CLAUDE.md (ships to user projects)
│   ├── QUICKSTART.md  ← Cursor-adapted quickstart
│   ├── PORTING.md     ← Maintainer drift tracking + skill→.mdc map
│   ├── knowledge/     ← Knowledge folder (hoisted to root, not under template/)
│   ├── scripts/aria/  ← Hook scripts (instead of bin/)
│   │   └── VERSION    ← Port version (e.g. 2.20.2-cursor.0)
│   ├── scripts/port-skills-to-mdc.py  ← Re-sync from plugin-claude-code/skills/
│   └── audit/         ← Frozen audit artifacts (2.16.1 baseline; see PORTING.md for current)
└── docs/              ← Extended documentation (future)
```

## Key Conventions

- **`plugin-claude-code/` is the installable unit** — everything inside it is what users copy to their plugins directory
- **`plugin-openai-codex/` is the Codex installable unit** — independent adapter surface, same knowledge schema. Claude `plugin-claude-code/` remains the standard for template/content shape.
- **`plugin-cursor-template/` is the Cursor repo-skeleton** — not a plugin install. Users clone or unzip its contents into the root of their own project. Cursor compiles 27 commands (22 core + 5 MCP) into 5 `.cursor/rules/*.mdc` files because Cursor's Rules system doesn't have a one-skill-per-folder concept. Port version tracks canonical via `scripts/aria/VERSION` (currently `2.20.2-cursor.0`). Maintainer re-sync: `python3 plugin-cursor-template/scripts/port-skills-to-mdc.py`. ADR-094 Runtime Gates are omitted in Cursor. Knowledge folder schema stays compatible with `plugin-claude-code/template/`.
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

1. Edit canonical skills in `plugin-claude-code/skills/` first (schema source-of-truth), then re-sync the Cursor port:
   ```bash
   python3 plugin-cursor-template/scripts/port-skills-to-mdc.py
   ```
2. Keep durable knowledge surfaces in sync with `plugin-claude-code/template/` — apply the same edits to `plugin-cursor-template/knowledge/` (root-level, not nested under `template/`). See `plugin-cursor-template/PORTING.md` §A for the lockstep file list.
3. The 5 `.mdc` rule files are *compiled* views of canonical `SKILL.md` bodies. `port-skills-to-mdc.py` refreshes `aria-commands.mdc` (core + MCP skills, wrapup/handoff patches, `/help` table) and strips ADR-094 Runtime Gates. Hand-edit `aria-audit.mdc`, `aria-context.mdc`, `aria-core.mdc`, or `aria-rule-22.mdc` when those surfaces change outside the scripted path.
4. Bump `plugin-cursor-template/scripts/aria/VERSION` (`<canonical>-cursor.0`) and run `./release-cursor.sh` from repo root. Zip: `aria-knowledge-cursor-<canonical>.zip`.
5. Users install by unzipping the artifact into the root of their own project, then restarting Cursor. End-user doc: `plugin-cursor-template/QUICKSTART.md`; project instructions file: `AGENTS.md` (not repo-root `CLAUDE.md`).

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
- `plugin-cursor-template/PORTING.md` — Cursor skill→`.mdc` compilation map and drift tracking
- `plugin-cursor-template/audit/ARIA_CURSOR_AUDIT_REPORT.md` — Cursor enforcement-gap matrix (§5)

Pre-staged ADR candidates live in `~/Projects/knowledge/intake/decisions-backlog.md` — check there for what's currently queued for next `/audit-knowledge`. Themes queued here historically drift as ADRs promote; the live backlog is the source of truth.

Use `/context aria` to load relevant knowledge by project tag.

---

*Last reviewed: 2026-05-27 — plugin-claude-code v2.20.2, plugin-claude-cowork v1.1.3, plugin-cursor-template 2.20.2-cursor.0.*
