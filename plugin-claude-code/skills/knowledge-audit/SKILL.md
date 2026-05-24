---
description: "Alias for /audit-knowledge. Invoked by the '/knowledge-audit' slash command. Same behavior as /audit-knowledge — just an alternative phrasing. (Claude Code variant — alias for /audit-knowledge; see ADR-094.)"
argument-hint: "[detailed]"
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# /knowledge-audit — Alias for /audit-knowledge

This is an **alias skill**. The canonical implementation lives at `plugin-claude-code/skills/audit-knowledge/SKILL.md` within the aria-knowledge plugin. Invoking `/knowledge-audit` and `/audit-knowledge` produces identical behavior — this alias exists only to accommodate users who prefer the inverted "knowledge-audit" phrasing.

## Execute

Read `plugin-claude-code/skills/audit-knowledge/SKILL.md` (relative to the aria-knowledge plugin root — resolve via `${CLAUDE_PLUGIN_ROOT}/skills/audit-knowledge/SKILL.md` if available, otherwise locate it within the installed plugin tree) and follow every step in that file exactly, passing through any arguments the user provided to this alias.

Do not duplicate canonical logic here. When the canonical skill changes, this alias continues to work because it delegates.

## Why this alias exists

Natural-language phrasing varies between "knowledge audit" and "audit knowledge." The canonical skill is named `audit-knowledge` for consistency with `audit-config` (both follow the `audit-<subject>` pattern). This alias covers the alternative convention without forcing users to remember the canonical form.

Natural-language dispatch ("run a knowledge audit") should still route to the canonical `/audit-knowledge` via its description's trigger phrases. This alias is primarily for users who type `/knowledge-audit` as an explicit slash command.

## Maintenance

- If the canonical skill's frontmatter changes (new argument hints, updated tools), this alias's frontmatter should mirror the tools list so invocation permissions match. Description stays alias-specific to avoid natural-language dispatch conflicts.
- If the canonical skill moves or is renamed, update the Read target in the Execute section above.
- The `/audit-knowledge` row in `/help` notes this alias; if the alias's name or existence changes, update that row too.
