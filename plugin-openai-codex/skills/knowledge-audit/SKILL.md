---
name: knowledge-audit
description: "Alias for /audit-knowledge. Use when the user invokes /knowledge-audit or asks for a knowledge audit using the inverted command phrasing."
argument-hint: "[detailed]"
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# /knowledge-audit — Alias for /audit-knowledge

This is an **alias skill**. The canonical implementation lives at `skills/audit-knowledge/SKILL.md` within this Codex plugin. Invoking `/knowledge-audit` and `/audit-knowledge` produces identical behavior — this alias exists only to accommodate users who prefer the inverted "knowledge-audit" phrasing.

## Execute

Read `${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/audit-knowledge/SKILL.md` and follow every step in that file exactly, passing through any arguments the user provided to this alias.

Do not duplicate canonical logic here. When the canonical skill changes, this alias continues to work because it delegates.

## Why this alias exists

Natural-language phrasing varies between "knowledge audit" and "audit knowledge." The canonical skill is named `audit-knowledge` for consistency with `audit-config` (both follow the `audit-<subject>` pattern). This alias covers the alternative convention without forcing users to remember the canonical form.

Natural-language dispatch ("run a knowledge audit") should still route to the canonical `/audit-knowledge` via its description's trigger phrases. This alias is primarily for users who type `/knowledge-audit` as an explicit slash command.

## Maintenance

- If the canonical skill's frontmatter changes (new argument hints, updated tools), this alias's frontmatter should mirror the tools list so invocation permissions match. Description stays alias-specific to avoid natural-language dispatch conflicts.
- If the canonical skill moves or is renamed, update the Read target in the Execute section above.
- The `/audit-knowledge` row in `/help` notes this alias; if the alias's name or existence changes, update that row too.
