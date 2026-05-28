# aria-knowledge for Codex

This is the standalone Codex port of ARIA Knowledge.

The Claude Code plugin in `../plugin-claude-code/` remains the standard for the
knowledge folder and content schema. This port adapts the installable plugin shell for Codex:
`.codex-plugin/plugin.json`, Codex commands, and Codex hook payload handling.

## Compatibility Contract

The Codex port intentionally shares the same durable knowledge surfaces:

- `README.md`, `OVERVIEW.md`, `LOCAL.md`, and `aliases.md`
- `intake/` backlogs and per-file ideas
- `rules/`, `approaches/`, `decisions/`, `guides/`, `references/`, `archive/`
- `projects/{tag}/` project-specific knowledge
- `_project-knowledge/` team-shared knowledge in code repos
- `index.md` tag index semantics

Do not fork those formats in this directory without also updating the
Claude Code-standard plugin.

## Quick Start

1. Restart Codex after installing or changing the plugin. Hooks are enabled by default in current Codex, but plugin-bundled hooks must be reviewed and trusted when Codex prompts for hook review.

2. Install this local plugin from the repo marketplace metadata at
   `.agents/plugins/marketplace.json`, or copy `plugin-openai-codex/` into a local
   Codex marketplace.

3. Configure ARIA:

   - Codex uses the shared ARIA config at `~/.claude/aria-knowledge.local.md` so it can share the same knowledge folder and settings as the Claude Code port.
   - A legacy `~/.codex/aria-knowledge.local.md` is only a fallback for older Codex-only installs.

4. Use the copied ARIA skills by asking Codex directly:

   - `setup aria-knowledge`
   - `load aria context for stripe`
   - `extract knowledge from this session`
   - `run aria knowledge audit`
   - `run aria wrapup`

The `/aria` command included here is a compact command reference for Codex.

## Hook Parity

Codex hooks currently cover:

- `SessionStart` cadence and setup prompts through the existing ARIA script
- `PreToolUse` Rule 22 checks for Codex `apply_patch`
- `PostToolUse` scope-check reminders for Codex `apply_patch`
- `PreToolUse` advisory reminders for shell commands that appear to write files
- `PreToolUse` CODEMAP reminders for broad `rg`, `grep`, and `find` exploration
- `PreCompact` and `PostCompact` passthrough to the existing ARIA scripts

Known gaps:

- Claude `TaskCreated` has no direct Codex equivalent yet; the port relies on SessionStart, UserPromptSubmit-compatible guidance, and explicit `/context` use.
- Some durable knowledge templates intentionally still mention Claude Code because the shared knowledge folder remains cross-port.

## Development Notes

See [PORTING.md](PORTING.md) for the adapter boundary and current parity notes.

## License

CC BY-NC-SA 4.0. See [LICENSE](LICENSE) for details.
