# aria-knowledge for Codex

This is the standalone Codex port of ARIA Knowledge.

The Claude plugin in `../plugin/` remains the standard for the knowledge folder
and content schema. This port adapts the installable plugin shell for Codex:
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
Claude-standard plugin.

## Quick Start

1. Enable Codex plugin hooks if you want automatic hook behavior:

   ```bash
   codex features enable plugin_hooks
   ```

2. Restart Codex.

3. Install this local plugin from the repo marketplace metadata at
   `.agents/plugins/marketplace.json`, or copy `plugin-codex/` into a local
   Codex marketplace.

4. Configure ARIA:

   - Existing ARIA users can keep using `~/.claude/aria-knowledge.local.md`.
   - Codex-specific installs may create `~/.codex/aria-knowledge.local.md`.
   - Codex hooks read `~/.codex/aria-knowledge.local.md` first, then fall back
     to the Claude config.

5. Use the copied ARIA skills by asking Codex directly:

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

- Claude `TaskCreated` has no direct Codex equivalent yet.
- Existing skills are copied from the Claude-standard plugin in this first pass,
  so some prose still names Claude-specific surfaces.
- `plugin_hooks` is a Codex under-development feature; use this port as a test
  adapter until the hook surface is fully stable.

## Development Notes

See [PORTING.md](PORTING.md) for the adapter boundary and current parity notes.

## License

CC BY-NC-SA 4.0. See [LICENSE](LICENSE) for details.
