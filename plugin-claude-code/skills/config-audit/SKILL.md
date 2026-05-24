---
description: "Alias for /audit-config. Invoked by the '/config-audit' slash command. Same behavior as /audit-config — just an alternative phrasing. (Claude Code variant — alias for /audit-config; see ADR-094.)"
argument-hint: ""
allowed-tools: Read, Glob, Grep, Write, Edit, Agent
---

# /config-audit — Alias for /audit-config

This is an **alias skill**. The canonical implementation lives at `plugin-claude-code/skills/audit-config/SKILL.md` within the aria-knowledge plugin. Invoking `/config-audit` and `/audit-config` produces identical behavior — this alias exists only to accommodate users who prefer the inverted "config-audit" phrasing.

## Execute

Read `plugin-claude-code/skills/audit-config/SKILL.md` (relative to the aria-knowledge plugin root — resolve via `${CLAUDE_PLUGIN_ROOT}/skills/audit-config/SKILL.md` if available, otherwise locate it within the installed plugin tree) and follow every step in that file exactly, passing through any arguments the user provided to this alias.

Do not duplicate canonical logic here. When the canonical skill changes, this alias continues to work because it delegates.

## Why this alias exists

Natural-language phrasing varies between "config audit" and "audit config." The canonical skill is named `audit-config` for consistency with `audit-knowledge` (both follow the `audit-<subject>` pattern). This alias covers the alternative convention without forcing users to remember the canonical form.

Natural-language dispatch ("run a config audit") should still route to the canonical `/audit-config` via its description's trigger phrases. This alias is primarily for users who type `/config-audit` as an explicit slash command.

## Maintenance

- If the canonical skill's frontmatter changes (new argument hints, updated tools), this alias's frontmatter should mirror the tools list so invocation permissions match. Description stays alias-specific to avoid natural-language dispatch conflicts.
- If the canonical skill moves or is renamed, update the Read target in the Execute section above.
- The `/audit-config` row in `/help` notes this alias; if the alias's name or existence changes, update that row too.
