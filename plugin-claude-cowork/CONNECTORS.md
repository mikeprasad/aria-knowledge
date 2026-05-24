# Connectors

## How tool references work

aria-cowork files use `~~category` as a placeholder for whatever tool the user connects in that category. For example, `~~project tracker` might mean Linear, Asana, Jira, or any other project tracker with an MCP server.

The plugin is **tool-agnostic** — it describes workflows in terms of categories (chat, email, project tracker, docs) rather than specific products. The [`.mcp.json`](.mcp.json) pre-configures specific MCP servers; **any MCP server in that category works** because skills probe at runtime to discover what's connected (see [ADR-015 capability-probe pattern](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/015-capability-probe-pattern.md)).

This convention follows Anthropic's published guidance in `cowork-plugin-management/skills/cowork-plugin-customizer/SKILL.md`:

> "When a plugin is intended to be shared with others outside their company, use generic language and mark customization points with two tilde characters such as `create an issue in ~~project tracker`."

aria-cowork ships under CC BY-NC-SA 4.0 (matching aria-knowledge — see ADR-006 + ADR-011 for the family's licensing posture), so this customization-marker convention applies. Organizations adopting aria-cowork can run `cowork-plugin-customizer` to replace `~~project tracker` with `Linear` (or whatever their team standardizes on) for their team's installs.

## Connectors for this plugin

| Category | Placeholder | Included MCP servers | Other options |
|---|---|---|---|
| **Chat** | `~~chat` | Slack, Microsoft 365 (Teams) | Discord (via custom MCP) |
| **Email** | `~~email` | Microsoft 365, Gmail | — |
| **Project tracker** | `~~project tracker` | Linear, Asana, Atlassian (Jira), Monday, ClickUp, Notion | Shortcut, Basecamp, Wrike (via custom MCP) |
| **Docs** | `~~docs` | Notion, Atlassian (Confluence), Box, Egnyte, Google Docs | Guru, Coda (via custom MCP) |

Notion + Atlassian + Microsoft 365 appear in multiple categories because their MCP servers expose multiple surfaces — Notion can be used as a project tracker OR as a docs/wiki; Atlassian covers Jira (project tracker) and Confluence (docs); Microsoft 365 covers Teams (chat) and Outlook (email).

## Which skills use which connectors

| Skill | `~~category` consumed | Read or write? | Fallback if no MCP |
|---|---|---|---|
| `/aria-cowork:clip-thread` | `~~chat` OR `~~email` | Read | Stop with notice |
| `/aria-cowork:extract-doc` | `~~docs` | Read | Stop with notice |
| `/aria-cowork:meeting-notes` | `~~docs` (paste fallback) | Read | Offer paste affordance |
| `/aria-cowork:sync-decisions` | `~~docs` | **Write** | Stop with notice |
| `/aria-cowork:digest` | `~~chat` + `~~email` + `~~project tracker` + `~~docs` | Read | Degrade with gap surfacing |
| `/aria-cowork:daily-audit` | none (cowork-only, local) | — | Always runs (no MCP probe) |

The other 20 skills (capture/govern/apply lifecycle ported from aria-knowledge) operate on the local knowledge folder and don't consume MCPs. They work without any external connector.

## How to connect MCPs

**In Claude Cowork** (this plugin's primary surface): Cowork manages MCP connections at the account level via **Settings → Connectors**. Click into each category, follow the OAuth flow, and Cowork remembers the connection across all your plugins and sessions. aria-cowork's skills will discover the connected MCPs automatically at runtime per [ADR-015](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/015-capability-probe-pattern.md).

**In Claude Code** (via the sibling [aria-knowledge](https://github.com/mikeprasad/aria-knowledge) plugin): MCPs declared in `.mcp.json` are loaded by Code's MCP client. Connect each via Code's OAuth flow on first use — the runtime prompts you to authenticate against the vendor's MCP endpoint. The aria-knowledge sibling ships the same `.mcp.json` + `CONNECTORS.md` since v2.18.0 (the 5 bidirectional MCP-consuming skills run identically across both surfaces per ADR-014).

In both surfaces, you do NOT need to connect all 12 MCPs — connect what you have access to. Skills probe at runtime and gracefully degrade for unconnected categories. See [ADR-015](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/015-capability-probe-pattern.md) for the probe semantics.

## What this plugin does NOT integrate with

- **Calendar.** aria-cowork has no calendar-consuming skill in v1.1.1. If/when a `/scheduling` or `/meeting-prep` skill lands, calendar MCPs (Google Calendar, Microsoft 365 Calendar) would be added.
- **Office suite (Excel/Word/PowerPoint).** Out of scope — aria-cowork's domain is decisions/insights/rules, not document authoring. Use Anthropic's `productivity` Cowork plugin alongside aria-cowork if you want that surface.
- **Code hosting (GitHub/GitLab).** Cowork has no shell access (per ADR-004 + the 2026-04-30 probe arc); `/codemap`-style git introspection is intentionally cowork-excluded per ADR-005. aria-knowledge sibling on Code covers this surface.
- **Vendor-specific Slack-alternatives** (Discord, Mattermost, Rocket.Chat, etc.). Not declared in `.mcp.json`. Users with these can configure custom MCPs at the surface level and the `~~chat` category will pick them up at runtime per ADR-015.

## Related references

- [`.mcp.json`](.mcp.json) — the manifest declaring the 12 MCP servers above.
- [ADR-003](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/003-cowork-native-mcp-placeholder-pattern.md) — three-mechanism design (named MCPs in manifest, `~~` markers in prose, native I/O for filesystem).
- [ADR-013](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/013-cowork-modified-skills-schema-identical-outputs.md) — output schema identical across plugins (input-discovery diverges per-surface).
- [ADR-014](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/014-bidirectional-feature-flow.md) — bidirectional feature flow (5 of the 6 v1.0.0 native skills originate as cross-plugin parity).
- [ADR-015](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/015-capability-probe-pattern.md) — runtime capability-probe pattern (prose-only, no API).
- [ADR-016](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/016-rule-22-advisory-preamble-for-external-writes.md) — Rule 22 advisory preamble for write-side skills (applies to `sync-decisions`).
- Anthropic reference: `cowork-plugin-management/skills/cowork-plugin-customizer/SKILL.md` — the `~~` marker convention's canonical source.
- Anthropic reference plugin: [`anthropics/knowledge-work-plugins/productivity`](https://github.com/anthropics/knowledge-work-plugins/tree/main/productivity) — the canonical `.mcp.json` + `CONNECTORS.md` shape that this plugin mirrors.
- Sibling plugin: [aria-knowledge](https://github.com/mikeprasad/aria-knowledge) ships the same `.mcp.json` + `CONNECTORS.md` since v2.18.0.
