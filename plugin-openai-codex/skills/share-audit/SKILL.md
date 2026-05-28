---
name: share-audit
description: "Alias for /audit-share. Use when the user invokes /share-audit or asks to audit shareable knowledge using the inverted command phrasing."
argument-hint: ""
allowed-tools: Read, Glob, Grep, Write, Edit, Bash
---

# /share-audit — Alias for /audit-share

This is an **alias skill**. The canonical implementation lives at `skills/audit-share/SKILL.md` within this Codex plugin. Invoking `/share-audit` and `/audit-share` produces identical behavior — this alias exists only to accommodate users who prefer the inverted "share-audit" phrasing.

## Execute

Read `${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/skills/audit-share/SKILL.md` and follow every step in that file exactly, passing through any arguments the user provided to this alias.

Do not duplicate canonical logic here. When the canonical skill changes, this alias continues to work because it delegates.

## Why this alias exists

Natural-language phrasing varies between "share audit" and "audit share." The canonical skill is named `audit-share` for consistency with `audit-config` and `audit-knowledge` (all follow the `audit-<subject>` pattern). This alias covers the alternative convention without forcing users to remember the canonical form.
