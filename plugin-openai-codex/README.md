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

Codex hooks currently cover the 2.30.0 Codex port feature set where Codex has
a native event or intent surface:

- `SessionStart` cadence and setup prompts through the existing ARIA script
- `UserPromptSubmit` active knowledge surfacing from the prompt text, using the shared tag index
- `PreToolUse` Rule 22 checks for Codex `apply_patch`
- `PostToolUse` scope-check reminders, `SESSION.md` in-progress state, and `auto_prospect` nudges for Codex `apply_patch`
- `PostToolUse` `auto_retrospect` nudges after qualifying `git push` output
- `PreToolUse` advisory reminders for shell commands that appear to write files
- `PreToolUse` CODEMAP reminders for broad `rg`, `grep`, and `find` exploration
- `PreCompact` and `PostCompact` passthrough to the existing ARIA scripts
- `SubagentStart` self-report instructions and `SubagentStop` durable capture to `intake/subagent-captures/`
- `/foundational-review` and `/readiness-audit` ship as Codex-native skills with the canonical process document bundled in the plugin

Known gaps:

- Claude Code `TaskCreated` has no exact Codex event. The port maps the intent to `UserPromptSubmit` plus `SubagentStart`/`SubagentStop`, which catches prompt intent and subagent boundaries but is not a one-for-one task dispatch hook.
- Claude Code's `/statusline` meter has no Codex equivalent yet. Codex does not expose a plugin statusline slot or context-window/rate-limit percentages in hook payloads, so this port does not ship `/statusline`, `statusline-meter.sh`, or `usage-threshold-inject.sh`. The shared `usage_alert_threshold` config key is preserved but ignored by Codex.
- Claude Code's `/aria-assist` scheduler and PM helper scripts remain non-equivalent in this port. Codex has no bundled launchd/headless scheduler path in this plugin surface yet.
- Codex shell interception is narrower than Claude Code Bash hooks. Rule 22 enforcement is strongest on `apply_patch`; shell write detection remains advisory.
- Some durable knowledge templates intentionally still mention Claude Code because the shared knowledge folder remains cross-port.

## Development Notes

See [PORTING.md](PORTING.md) for the adapter boundary and current parity notes.

## License

CC BY-NC-SA 4.0. See [LICENSE](LICENSE) for details.
