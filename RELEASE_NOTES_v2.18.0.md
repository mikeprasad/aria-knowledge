# ARIA v2.18.0 — Release Notes (2026-05-19)

**First MCP-consuming release for ARIA.** 5 new bidirectional cross-tool skills + `.mcp.json` + `CONNECTORS.md` foundation + 2 new architectural ADRs. First WRITE-side ARIA skill (`/sync-decisions` per new ADR-016). Coordinated release pair with **aria-cowork v1.0.0** (first MCP-consuming release on the Cowork sibling + v1.0 stable-contract claim).

## Three artifacts shipped (6 total assets — 3 versioned + 3 stable-filename)

| Port | Versioned zip | Stable-filename zip | Status |
|---|---|---|---|
| **Claude** (canonical) | `aria-knowledge-plugin-2.18.0.zip` | `aria-knowledge-plugin.zip` | Full v2.18.0 (5 new skills + foundation files) |
| **Codex** | `aria-knowledge-codex-2.18.0.zip` | `aria-knowledge-codex.zip` | Full v2.18.0-codex.0 (byte-faithful skill mirror + foundation) |
| **Cursor** (repo-skeleton) | `aria-knowledge-cursor-2.18.0.zip` | `aria-knowledge-cursor.zip` | v2.18.0-cursor.0 light-touch — VERSION + PORTING.md drift tracker. SKILL.md `.mdc` compilation deferred pending Cursor MCP runtime validation (per Pending sync items in `plugin-cursor-template/PORTING.md`). |

Stable-filename URLs continue to auto-resolve to latest release via `/releases/latest/download/aria-knowledge-<port>.zip`.

## What's new

### 5 new bidirectional MCP-consuming skills

All five ship in aria-knowledge v2.18.0 (canonical) and aria-cowork v1.0.0 (byte-faithful import per ADR-013):

- **`/clip-thread`** — Capture a chat or email thread from a connected `~~chat` (Slack, Teams) or `~~email` (Gmail, MS365) MCP to `intake/clippings/{date}-{slug}.md`. Source-type detection by URL pattern; per-message structure with reactions + attachment notes; user-fillable reaction section.
- **`/extract-doc`** — Decompose a single Notion / Confluence / Google Doc / Box / Egnyte page (via `~~docs` MCP) into N intake-backlog entries for audit routing. Differs from `/intake doc` (v2.17.0) which captures one doc as one structured artifact.
- **`/meeting-notes`** — Fold a meeting transcript into structured intake with participants / topics / action items / decisions / open questions + raw transcript preserved verbatim. **Unique among the 5:** offers paste fallback when no `~~docs` MCP connected (Granola exports, hand-typed notes, transcript paste).
- **`/digest`** — Cross-tool weekly rollup synthesizing what's pending / shipped / blocked across `~~chat` + `~~email` + `~~project tracker` + `~~docs`. Composite-MCP probe — degrades gracefully when partial connection; surfaces gap callouts.
- **`/sync-decisions`** — **First WRITE-side ARIA skill.** Mirrors approved decisions from `decisions/` out to a connected `~~docs` MCP destination. Embeds ADR-016's 4-step Rule 22 advisory preamble + explicit per-decision `Ready to write? (yes / no / edit)` go-gate. The literal phrase `yes to all writes` is the only path to batch authorization.

### New foundation: `plugin/.mcp.json` + `plugin/CONNECTORS.md`

First time aria-knowledge ships an `.mcp.json` manifest. Declares 12 MCP servers across 4 categories (chat / email / project tracker / docs). Mirrors Anthropic's published `productivity/.mcp.json` shape. `CONNECTORS.md` documents the `~~` customization-marker convention per `cowork-plugin-management` canonical guidance.

### 2 new ADRs (in `mikeprasad/knowledge`)

- **ADR-015** — Capability-probe pattern (prose-only, no API). Productivity plugin's `update/SKILL.md` is the canonical reference: Claude's runtime tool list IS the probe; SKILL.md handles missing-MCP via explicit fallback prose. Composes with ADR-004 (no hooks).
- **ADR-016** — Rule 22 advisory preamble for external-write skills. 4-step preamble + explicit go-gate. Layer-1 + Layer-3 only per aria-cowork v0.2.5's "Principles transfer, enforcement doesn't" framing. Applies to `/sync-decisions`; pattern durable for future write-side skills.

Both ADRs include **Stability and revision triggers** sections — patterns derive from Anthropic-published Cowork plugins as of 2026-05-19 and may revise as future Anthropic releases ship new capability surfaces.

## Coordinated companion release: aria-cowork v1.0.0

aria-cowork v1.0.0 ships on disk same day as a coordinated companion release. Imports the 5 bidirectional skills byte-faithfully + adds 1 cowork-only `/daily-audit` (first-message audit-cadence substitute since Cowork has no SessionStart hook). v1.0.0 is aria-cowork's first stable-contract claim — locks the cowork-runtime integration shape (persistent-grant + default-path + aria-config.md bridge + skills-only invocation + 4-category MCP framework). Independent semver tracks per ADR-006 (aria-knowledge at v2.18.0, aria-cowork at v1.0.0).

## Compatibility

- **No breaking changes.** All 23 prior skills work unchanged. The 5 new skills are opt-in by invocation.
- **No new required config.** Existing `aria-knowledge.local.md` unchanged. Future `default_sync_target:` field is optional (consumed only by `/sync-decisions`).
- **Graceful degradation built-in.** If no MCPs are connected, the 5 new skills output a clear fallback notice and stop.
- **MCP-consuming is opt-in.** Users who don't want any of the 5 new skills can ignore them.

## Install

### Claude Code (canonical)

1. Download `aria-knowledge-plugin-2.18.0.zip` (or use the stable-filename `aria-knowledge-plugin.zip` for auto-update workflows)
2. Install via Claude Code's local-zip mechanism
3. Run `/setup` to configure (or pick up existing `~/.claude/aria-knowledge.local.md`)
4. Optional: connect MCPs via Claude Code's `.mcp.json` to enable the 5 new MCP-consuming skills

### Codex

1. Download `aria-knowledge-codex-2.18.0.zip`
2. Install via Codex local marketplace
3. Optional MCP setup per Codex docs

### Cursor

1. Download `aria-knowledge-cursor-2.18.0.zip`
2. Unzip into the root of your project (it's a repo-skeleton, not a plugin install)
3. Restart Cursor
4. Note: 5 new MCP-consuming skills are declared in `plugin-cursor-template/PORTING.md` "Pending sync items" but NOT YET compiled into `.mdc` rules. Cursor MCP runtime validation is the prerequisite — see PORTING.md for the deferred-compilation tracker.

## Full changelog

See [`CHANGELOG.md` v2.18.0 entry](CHANGELOG.md) for the full structured changelog.

## Cross-editor knowledge folder sharing

Per the multi-port architecture: a Claude Code user, a Codex user, and a Cursor user can share the same `~/Projects/knowledge/` folder across editors. Schema parity is enforced via ADR-013 byte-faithful output contracts; all three ports write to the same intake/decisions/approaches/rules paths with byte-identical frontmatter.

## Version scheme

| Port | Format | This release |
|---|---|---|
| Claude (canonical) | `<MAJOR>.<MINOR>.<PATCH>` | `2.18.0` |
| Codex | `<MAJOR>.<MINOR>.<PATCH>-codex.<N>` | `2.18.0-codex.0` |
| Cursor | `<MAJOR>.<MINOR>.<PATCH>-cursor.<N>` | `2.18.0-cursor.0` |
