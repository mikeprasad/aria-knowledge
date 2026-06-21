# Connectors

## How tool references work

aria-knowledge files use `~~category` as a placeholder for whatever tool the user connects in that category. For example, `~~project tracker` might mean Linear, Asana, Jira, or any other project tracker with an MCP server.

The plugin is **tool-agnostic** — it describes workflows in terms of categories (chat, email, project tracker, docs) rather than specific products. The [`.mcp.json`](.mcp.json) pre-configures specific MCP servers; **any MCP server in that category works** because skills probe at runtime to discover what's connected (see [ADR-015 capability-probe pattern](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/015-capability-probe-pattern.md)).

This convention follows Anthropic's published guidance in `cowork-plugin-management/skills/cowork-plugin-customizer/SKILL.md`:

> "When a plugin is intended to be shared with others outside their company, use generic language and mark customization points with two tilde characters such as `create an issue in ~~project tracker`."

aria-knowledge ships publicly (CC BY-NC-SA 4.0), so this customization-marker convention applies. Organizations adopting aria-knowledge can run `cowork-plugin-customizer` to replace `~~project tracker` with `Linear` (or whatever their team standardizes on) for their team's installs.

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
| `intake thread` | `~~chat` OR `~~email` | Read | Notice to authenticate the MCP (Code-native once authed) |
| `intake extract` (MCP-doc source) | `~~docs` | Read | Notice to authenticate the MCP |
| `meeting-notes` | `~~docs` (paste fallback) | Read | Offer paste affordance |
| `sync-decisions` | `~~docs` | **Write** | Stop with notice |
| `digest` | `~~chat` + `~~email` + `~~project tracker` + `~~docs` | Read | Degrade with gap surfacing |

The other 22 skills (capture/govern/apply lifecycle) operate on the local knowledge folder and don't consume MCPs. They work without any external connector.

## How to connect MCPs

**In Claude Code** (this plugin's primary surface): MCPs declared in `.mcp.json` are loaded by Code's MCP client. Connect each via Code's OAuth flow on first use — the runtime prompts you to authenticate against the vendor's MCP endpoint.

**In Claude Cowork** (via the sibling [aria-cowork](https://github.com/mikeprasad/aria-cowork) plugin, when released): Cowork manages MCP connections at the account level via Settings → Connectors. Connect the MCPs you want; aria-cowork's skills will discover them at runtime.

In both surfaces, you do NOT need to connect all 12 MCPs — connect what you have access to. Skills probe at runtime and gracefully degrade for unconnected categories. See [ADR-015](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/015-capability-probe-pattern.md) for the probe semantics.

## What this plugin does NOT integrate with

- **Calendar.** aria-knowledge has no calendar-consuming skill in v2.18.0. If/when a `/scheduling` or `/meeting-prep` skill lands, calendar MCPs (Google Calendar, Microsoft 365 Calendar) would be added.
- **Office suite (Excel/Word/PowerPoint).** Out of scope — aria-knowledge's domain is decisions/insights/rules, not document authoring. Use Anthropic's `productivity` plugin alongside aria-knowledge if you want that surface.
- **Code hosting (GitHub/GitLab).** Skills like `/codemap` use `gh` CLI + local filesystem; no MCP needed.
- **Vendor-specific Slack-alternatives** (Discord, Mattermost, Rocket.Chat, etc.). Not declared in `.mcp.json`. Users with these can configure custom MCPs at the surface level (Code or Cowork) and the `~~chat` category will pick them up at runtime per ADR-015.

## Related references

- [`.mcp.json`](.mcp.json) — the manifest declaring the 12 MCP servers above.
- [ADR-003](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/003-cowork-native-mcp-placeholder-pattern.md) — three-mechanism design (named MCPs in manifest, `~~` markers in prose, native I/O for filesystem).
- [ADR-015](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/015-capability-probe-pattern.md) — runtime capability-probe pattern (prose-only, no API).
- [ADR-016](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/016-rule-22-advisory-preamble-for-external-writes.md) — Rule 22 advisory preamble for write-side skills (applies to `sync-decisions`).
- Anthropic reference: `cowork-plugin-management/skills/cowork-plugin-customizer/SKILL.md` — the `~~` marker convention's canonical source.
- Anthropic reference plugin: [`anthropics/knowledge-work-plugins/productivity`](https://github.com/anthropics/knowledge-work-plugins/tree/main/productivity) — the canonical `.mcp.json` + `CONNECTORS.md` shape that this plugin mirrors.
