---
description: "Alias for /audit-share. Invoked by the '/share-audit' slash command. Same behavior as /audit-share — just an alternative phrasing."
---

# /share-audit — Alias for /audit-share

This is an **alias skill**. The canonical implementation lives at `plugin-claude-code/skills/audit-share/SKILL.md` within the aria-knowledge plugin. Invoking `/share-audit` and `/audit-share` produces identical behavior — this alias exists only to accommodate users who prefer the inverted "share-audit" phrasing.

## Execute

Read `plugin-claude-code/skills/audit-share/SKILL.md` (relative to the aria-knowledge plugin root — resolve via `${CLAUDE_PLUGIN_ROOT}/skills/audit-share/SKILL.md` if available, otherwise locate it within the installed plugin tree) and follow every step in that file exactly, passing through any arguments the user provided to this alias.

Do not duplicate canonical logic here. When the canonical skill changes, this alias continues to work because it delegates.

## Why this alias exists

Natural-language phrasing varies between "share audit" and "audit share." The canonical skill is named `audit-share` for consistency with `audit-config` and `audit-knowledge` (all follow the `audit-<subject>` pattern). This alias covers the alternative convention without forcing users to remember the canonical form.
