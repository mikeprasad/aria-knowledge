# ARIA Knowledge Codex Port

This directory is the standalone Codex port of ARIA Knowledge.

The Claude plugin in `../plugin/` remains the canonical implementation for the
knowledge folder and content schema. The Codex port may diverge in manifests,
commands, hook payload handling, and Codex-specific tool names, but it should not
silently fork the markdown knowledge contract.

## Stable Contract

Keep these compatible with the Claude-standard plugin:

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

The hook adapter reads `~/.codex/aria-knowledge.local.md` first, then falls back
to `~/.claude/aria-knowledge.local.md`. This lets Codex share an existing ARIA
knowledge folder immediately while still allowing a future independent Codex
setup path.

## Current Parity Notes

- Skills are copied from the Claude-standard plugin in this first pass, so some
  skill prose still names Claude surfaces.
- Rule 22 maps Codex file edits to `apply_patch`.
- Shell write detection is advisory in this port; use `apply_patch` for edits.
- Claude `TaskCreated` has no direct Codex equivalent yet. Prefer explicit
  context-loading skills and SessionStart/UserPrompt patterns.
- Plugin hooks require Codex `plugin_hooks`, which is currently an
  under-development feature.
