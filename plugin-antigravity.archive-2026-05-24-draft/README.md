# plugin-antigravity (Archived Draft, 2026-05-24)

This directory was a first-draft port of aria-knowledge to Google Antigravity, built on three incorrect assumptions about the Antigravity plugin contract:

1. Plugin manifest location was assumed to be `.agent-plugin/plugin.json` — Antigravity actually uses a flat `plugin.json` at the plugin root.
2. Hook config was assumed to use Claude Code's `{"hooks": {...}}` wrapper with `${CLAUDE_PLUGIN_ROOT}` env var — Antigravity uses named-hook top-level entries with stdin-JSON I/O and no env vars.
3. MCP config was at `.mcp.json` with `"url"` key — Antigravity uses `mcp_config.json` at `~/.gemini/antigravity/` with `"serverUrl"`.

The replacement port lives at `plugin-antigravity/` and is built against the primary-source verified contract from `antigravity.google/docs/*` (clipped 2026-05-24 to `~/Projects/knowledge/intake/clippings/`).

See `docs/superpowers/plans/2026-05-24-antigravity-port-full-implementation.md` for the rewrite plan and `docs/ARIA Knowledge v2.19.2 — Antigravity Port Guide (Verified).md` for the design rationale.

This directory is retained per Rule 6 (don't delete — archive) for forensic value: it documents what the contract was inferred to be before verification, which is useful future context for anyone investigating cross-port architecture decisions.
