# ARIA Knowledge Codex Port

This directory is the standalone Codex port of ARIA Knowledge.

The Claude Code plugin in `../plugin-claude-code/` remains the canonical implementation for the
knowledge folder and content schema. The Codex port may diverge in manifests,
commands, hook payload handling, and Codex-specific tool names, but it should not
silently fork the markdown knowledge contract.

## Stable Contract

Keep these compatible with the Claude Code-standard plugin:

- Knowledge folder layout under `template/`
- Backlog formats under `intake/`
- `index.md` sections and tag semantics
- Project tier under `projects/{tag}/`
- Team-shared tier under `_project-knowledge/`
- Rule 22 content and working-rule numbering

## Codex Adapter Surface

Codex-specific files live here:

- `.codex-plugin/plugin.json`
- `hooks.json`
- `commands/`
- `bin/codex-hook.sh`
- `bin/codex-hook.py`

The hook adapter reads the shared `~/.claude/aria-knowledge.local.md` first, then
falls back to legacy `~/.codex/aria-knowledge.local.md` for older Codex-only
installs. The shared config is intentional: Claude Code and Codex should use the
same knowledge folder, cadences, project tier, and shared-knowledge settings
unless the user explicitly overrides `KT_CONFIG` or `ARIA_KNOWLEDGE_CONFIG`.

## Current Parity Notes

- Skills should keep shared knowledge schemas compatible while using Codex-native
  metadata, config, and hook wording.
- Rule 22 maps Codex file edits to `apply_patch`.
- Shell write detection is advisory in this port; use `apply_patch` for edits.
- Claude `TaskCreated` has no direct Codex equivalent yet. Prefer explicit
  context-loading skills plus SessionStart/UserPromptSubmit-compatible guidance.
- Hooks are enabled by default in current Codex, but plugin-bundled hooks still
  require user trust review before they run.

## v2.18.0 update (2026-05-18) — MCP-consuming skills

5 MCP-consuming skills originally ported from `../plugin-claude-code/skills/` and now maintained with Codex-native metadata:

- `clip-thread/SKILL.md` — `~~chat` / `~~email` thread capture
- `extract-doc/SKILL.md` — `~~docs` page → N intake-backlog entries
- `meeting-notes/SKILL.md` — `~~docs` page OR paste fallback → structured meeting note
- `digest/SKILL.md` — composite probe across all 4 categories → weekly rollup
- `sync-decisions/SKILL.md` — **first WRITE-side ARIA skill**; mirrors decisions to `~~docs` MCP with Rule 22 advisory preamble per ADR-016

Plus `.mcp.json` (12 MCPs across chat/email/project-tracker/docs categories) and `CONNECTORS.md` (`~~` marker convention reference) — both byte-identical to the Claude port.

### Concept-and-function-preserved-but-method-may-diverge (per Mike's D2 framing)

- **MCP runtime parity:** Codex's MCP client may or may not surface the same tool names as Claude Code's MCP client for any given vendor MCP (slack, notion, linear, etc.). The capability-probe pattern (ADR-015) degrades gracefully — if a `~~category` tool isn't available at runtime, the SKILL.md outputs the standard fallback notice ("No required MCPs connected") and stops. No SKILL.md modification needed in Codex.
- **OAuth flow surface:** Claude Code prompts for OAuth via its own MCP client. Codex's flow may differ. The `.mcp.json` declaration (with `oauth.clientId` + `callbackPort` for Slack) is the same; the runtime that consumes it differs per surface.
- **Write-side discipline:** `sync-decisions` Rule 22 advisory preamble (ADR-016) is Layer-1-only (skill prose + required output format). Codex has no PreToolUse hook on MCP tool calls; this matches Cowork's constraint and is the documented Layer-1 enforcement pattern. SKILL.md body unchanged.

Skill descriptions are Codex-native; durable knowledge templates may still mention Claude Code where the shared knowledge folder documents cross-port conventions.
