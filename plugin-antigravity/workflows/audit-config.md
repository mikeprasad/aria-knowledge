# /audit-config — Configuration & Documentation Audit

Scan Antigravity config surfaces + CLAUDE.md / GEMINI.md files for drift, staleness, and broken references.

## Steps

Invoke the aria-knowledge **`audit-config`** skill. Audits `hooks.json`, `mcp_config.json`, plugin manifests (flat `plugin.json` schema), `~/.gemini/GEMINI.md`, workspace `.agents/rules/` + `.agents/workflows/`, and `~/.gemini/antigravity/aria-knowledge.local.md` for issues — then walks every CLAUDE.md and GEMINI.md file checking references, version stamps, and cross-pointers.
