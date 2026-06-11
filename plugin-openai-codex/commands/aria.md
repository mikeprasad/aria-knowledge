# /aria

Use ARIA Knowledge in Codex.

## Common Actions

- `setup aria-knowledge` - configure a knowledge folder
- `load aria context for <topic>` - query the ARIA tag index
- `extract knowledge from this session` - stage insights and decisions
- `run aria knowledge audit` - review backlogs and promote knowledge
- `run aria prospect on this plan` - review a plan before execution
- `run aria retrospect on this branch` - review a shipped or drafted change set
- `run aria readiness audit for this release` - audit whether a surface is clean to ship
- `run aria foundational review for this decision` - review whether an irreversible decision is sound
- `run aria wrapup` - produce an end-of-session handoff

## Codex Notes

- This port keeps the Claude-standard ARIA knowledge folder schema.
- Codex uses the shared `~/.claude/aria-knowledge.local.md` config by default.
- Legacy `~/.codex/aria-knowledge.local.md` is only a fallback for older Codex-only installs.
- Plugin-bundled hooks are enabled by current Codex, but Codex may ask you to review and trust them after install or updates.
- Codex maps ARIA active context to `UserPromptSubmit`, file-edit discipline to `apply_patch`, and subagent capture to `SubagentStart`/`SubagentStop`.
