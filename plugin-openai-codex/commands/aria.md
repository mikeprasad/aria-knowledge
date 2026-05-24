# /aria

Use ARIA Knowledge in Codex.

## Common Actions

- `setup aria-knowledge` - configure a knowledge folder
- `load aria context for <topic>` - query the ARIA tag index
- `extract knowledge from this session` - stage insights and decisions
- `run aria knowledge audit` - review backlogs and promote knowledge
- `run aria wrapup` - produce an end-of-session handoff

## Codex Notes

- This port keeps the Claude-standard ARIA knowledge folder schema.
- If `~/.codex/aria-knowledge.local.md` exists, Codex hooks read it.
- Otherwise Codex hooks fall back to `~/.claude/aria-knowledge.local.md`.
- Automatic plugin hooks require `codex features enable plugin_hooks` and a Codex restart.
