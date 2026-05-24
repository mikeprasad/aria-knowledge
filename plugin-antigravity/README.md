# aria-knowledge — Antigravity Port

This is the Antigravity 2.0 port of [aria-knowledge](https://github.com/mikeprasad/aria-knowledge) v2.19.2.

Targets **Antigravity IDE** (VS Code fork) and **Antigravity CLI** (`agy`) from a single plugin install. The Antigravity 2.0 Agent Manager desktop app is out of scope (different paradigm — see `PORTING.md` and the design guide at `docs/ARIA Knowledge v2.19.2 — Antigravity Port Guide (Verified).md`).

## Install

```sh
# Inside Antigravity (IDE or CLI):
/plugin marketplace add mikeprasad/aria-knowledge
/plugin install aria-knowledge
```

Then run `/setup` inside Antigravity to configure your knowledge folder. This creates `~/.gemini/antigravity/aria-knowledge.local.md` and the knowledge folder scaffold.

## Manual install (advanced)

If you don't have a published marketplace entry, manually place the plugin into Antigravity's plugin discovery paths:

```sh
# Global install (active across all workspaces):
cp -R plugin-antigravity ~/.gemini/config/plugins/aria-knowledge

# OR workspace install (only active in the current project):
mkdir -p .agents/plugins/
cp -R plugin-antigravity .agents/plugins/aria-knowledge
```

Restart Antigravity. Open the Customizations panel — `aria-knowledge` should appear.

## Requirements

- **`jq`** — required by the hook wrappers for stdin-JSON parsing. Install via `brew install jq` (macOS) or `apt-get install jq` (Linux).
- **`bash`** — required by all hook scripts.

If `jq` is missing, every hook fails closed with a deny-and-reason. Install before first use.

## What's included

| Component | Path | Purpose |
|---|---|---|
| Plugin manifest | `plugin.json` | Marker file identifying this dir as a plugin |
| Hooks | `hooks.json` + `bin/antigravity/` | 4 per-turn hooks (3 PreToolUse + 1 PostToolUse) |
| Hook wrappers | `bin/antigravity/*.sh` | Translate Antigravity stdin JSON to ARIA canonical env vars |
| MCP servers | `mcp_config.json` | 12 servers (Slack, Linear, Notion, Atlassian, etc.) — HTTP transport with `serverUrl` |
| Session-lifecycle rules | `GEMINI.md` | One-time-per-session behaviors (audit cadence, knowledge surfacing) |
| Skills | `skills/<name>/SKILL.md` × 30 | All ARIA commands (`/setup`, `/extract`, `/handoff`, `/audit-knowledge`, etc.) |
| Knowledge template | `template/` | Knowledge folder scaffold; copied to `knowledge_folder` on `/setup` |

## What's NOT included

- **SessionStart / PreCompact / PostCompact / TaskCreated hooks** — Antigravity has no equivalent events. Their behaviors moved to `GEMINI.md` (session-start logic) or to user-invoked skills (`/snapshot`, `/wrapup`).
- **`${CLAUDE_PLUGIN_ROOT}` env var** — derived from `BASH_SOURCE` inside `lib-antigravity-input.sh`.
- **AGENTS.md** — Antigravity uses `GEMINI.md` instead.

## Build / update

This port is assembled from canonical `plugin/` by `build.sh`. Run after any `plugin/` update:

```sh
bash plugin-antigravity/build.sh
```

Hand-authored files (`plugin.json`, `hooks.json`, `mcp_config.json`, `GEMINI.md`, `bin/antigravity/*`, this README, `PORTING.md`, `SMOKE-TEST.md`) are preserved; only `skills/`, `template/`, and `bin/*.sh` (the canonical scripts) are regenerated.

## Testing

```sh
bats plugin-antigravity/tests/
```

Tests cover the shared lib + 4 wrappers. Smoke test in actual Antigravity is documented separately in `SMOKE-TEST.md` (manual; can't be automated without an Antigravity install in CI).

## See also

- [PORTING.md](PORTING.md) — full drift log + adaptation notes
- [SMOKE-TEST.md](SMOKE-TEST.md) — manual test plan for first install in Antigravity
- [../docs/ARIA Knowledge v2.19.2 — Antigravity Port Guide (Verified).md](../docs/ARIA%20Knowledge%20v2.19.2%20%E2%80%94%20Antigravity%20Port%20Guide%20%28Verified%29.md) — design rationale
- [../docs/superpowers/plans/2026-05-24-antigravity-port-full-implementation.md](../docs/superpowers/plans/2026-05-24-antigravity-port-full-implementation.md) — the implementation plan this directory was built from
