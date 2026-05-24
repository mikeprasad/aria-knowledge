<!-- plugin-managed: /aria-setup diffs this file on plugin updates. Customize it freely — your edits appear as diff prompts on future `/aria-setup` runs (this is how you receive plugin improvements). For customizations you want ARIA to leave alone, use `LOCAL.md` (user-owned, never diffed). -->

# ARIA Knowledge — Design Philosophy

This is the canonical doc for how aria-cowork (and aria-knowledge in Code) think about durable knowledge.

## The Problem

Knowledge worker memory has the shape of a sieve. You learn something useful in a Slack thread, an email, a meeting, a research session, a code review — and a week later it's gone. The knowledge isn't lost forever; it's spread across tools, conversations, and personal memory in a form that won't surface when you need it next.

ARIA's premise: **promoted knowledge has to be authored, governed, and applied by humans** — but the capture, organization, and surfacing can be delegated to a discipline you trust.

## The Approach — five phases

ARIA structures knowledge work into five phases. Both aria-cowork and aria-knowledge implement them, with different surface affordances per phase.

### 1. Capture
Pull knowledge into staging without committing yet. In aria-cowork: `/clip` (URLs/snippets), `/intake` (bulk), `/ask` (research). In aria-knowledge (Code): adds `/extract` from active conversations. Output lands in `intake/` backlogs.

### 2. Govern (Phase 2+ in aria-cowork)
Review staged items, decide what's worth promoting, archive the rest. Currently a manual sweep; v0.2.0 adds `/audit-knowledge` to automate the cadence.

### 3. Promote
Move promoted material into the canonical folders: `approaches/` (proven methods), `decisions/` (ADRs), `guides/` (operational), `references/` (external).

### 4. Apply
Surface relevant knowledge when starting new work: `/context <tag>` returns a curated set of files matching the topic; `/rules` looks up active principles.

### 5. Refresh
Audit cadences flag stale content, suggest promotions from freeform tags, detect missing cross-references. v0.2.0 ships `/audit-knowledge` for this.

## The Plugin (aria-cowork v0.1.0)

### Skills

10 skills covering setup, capture, retrieval, and audit:

| Skill | Phase | What it does |
|-------|-------|--------------|
| `setup` | bootstrap | Folder attach, scaffold structure, write `aria-config.md` |
| `help` | reference | Command list |
| `clip` | capture | Save URL/snippet to intake/clippings/ |
| `intake` | capture | Bulk import from files/URLs/dirs |
| `ask` | capture | Research → save directly to category |
| `context` | apply | Load knowledge by tag |
| `index` | refresh | Rebuild tag index |
| `stats` | refresh | Knowledge folder health |
| `rules` | apply | Working-rules lookup |
| `backlog` | govern | View/manage pending intake |

### What's deferred to v0.2.0+

- **MCP integrations** (Slack, Notion, Linear, Gmail, etc.) for cross-tool capture
- **`/extract`** from active conversations (no automated transcript API in Cowork — uses agent self-recall + paste fallback)
- **`/audit-knowledge`** for governance cadence
- **Cowork-native skills:** `/digest`, `/clip-thread`, `/extract-doc`, `/sync-decisions`, `/meeting-notes`, `/daily-audit`

### Hooks (Phase 2+, optional)

aria-cowork v0.1.0 ships **zero hooks**, matching the canonical pattern of Anthropic's published Cowork plugins. Cowork supports hooks (`hooks/hooks.json`, events PreToolUse/PostToolUse/Stop/SessionStart) but the convention is skill-embedded discipline. If a future use case demands runtime enforcement (e.g., audit-cadence reminders), `hooks/hooks.json` is available without re-spec.

aria-knowledge in Code DOES ship hooks for Rule 22 enforcement, audit cadence, and pre-compact transcript capture. Different runtime, different conventions.

## Plugin-Managed vs User-Owned Files

Your knowledge folder contains two classes of files:

### Plugin-Managed (diffed on `/aria-setup` updates)

These files ship with aria-cowork (and aria-knowledge) and are diffed against your version on each `/aria-setup` run:

- `README.md` — folder root README
- `OVERVIEW.md` — this file
- `rules/working-rules.md` — the universal working rules
- `rules/change-decision-framework.md` — Rule 22 framework
- `rules/enforcement-mechanisms.md` — three-tier enforcement model

When the plugin updates, you see diff prompts for these files. Customize freely — your edits surface for review on future `/aria-setup` runs.

### User-Owned (never overwritten)

These files are yours; ARIA never modifies them after first creation:

- `LOCAL.md` — your project-specific conventions
- `rules/user-rules.md` — your custom rules
- All `intake/*-backlog.md` files
- All `intake/clippings/`, `intake/notes/`, `intake/attachments/` content
- All `logs/*` audit logs
- Directory README stubs (`approaches/README.md`, etc.)
- Anything you create or move into the folder

## How aria-cowork resolves the knowledge folder (technical)

A subtle but important detail: **Cowork's `cwd` is NOT the user-attached folder.** Cowork's cwd is a per-session sandbox dir at `/sessions/<session-id>/`. The user-attached folder (your knowledge folder) is reachable via:

1. Its **absolute path** (e.g., `/Users/you/Projects/knowledge/`)
2. Its **sandbox mount** (`/sessions/<session-id>/mnt/<folder-name>/`)

aria-cowork resolves the absolute path once at `/aria-setup` (asking you to confirm), stores it in `aria-config.md`, and uses it for all cross-surface communication. aria-knowledge in Code reads the same `aria-config.md` and finds the same folder. This is what makes the two plugins share knowledge truth without a sync layer.

See [ADR-008](https://github.com/mikeprasad/aria-knowledge/tree/main/plugin-claude-cowork) for the full mechanism.

## Design principles

- **Opinionated defaults, easy customization.** ARIA scaffolds a sensible folder structure with reasonable rules. Customize anything; ARIA leaves user-owned content alone.
- **Human review gates.** Promotions, normalizations, archives all require explicit user yes. ARIA proposes; you decide.
- **Signal accumulation over forced curation.** Knowledge accretes naturally as you work. Audit cadences surface what's worth attention; nothing is forced.
- **Stable identifiers.** ADR numbers don't get reused, tag names persist, folder paths are predictable. Build on what's there.
- **Archive, don't delete.** Move retired content to `archive/` with pointers. Keep history.

## Why human-anchored knowledge

ARIA deliberately doesn't auto-promote knowledge. The five-phase lifecycle has explicit human gates because:

- **Tacit knowledge requires judgment** — "is this insight true broadly, or just here?" is a question only the operator can answer.
- **Forced curation produces stale archives** — auto-generated knowledge bases bloat with material no one trusts.
- **Authoring discipline pays off downstream** — knowledge written by you, for future-you, is the kind that surfaces usefully via `/context`.

ARIA's job is to remove friction from the parts that AREN'T judgment (capture, organization, retrieval, freshness signals). The judgment stays with you.

## Getting started

After `/aria-setup`:

1. **Capture as you work.** Hit interesting URLs? `/clip`. Researching a question? `/ask`. Bulk-importing notes? `/intake <path>`.
2. **Apply when starting new work.** `/context <topic>` surfaces relevant approaches, decisions, and references.
3. **Refresh periodically.** Run `/index` to rebuild the tag index after capture sweeps.

## Getting the most from ARIA

- **Run `/index` after capture sweeps** — keeps `/context` queries returning fresh results.
- **Customize `LOCAL.md`** — document your project-specific conventions there; ARIA leaves it alone.
- **Use `rules/user-rules.md`** — your team's custom rules live here, separate from the plugin's working rules.
- **Cross-surface flow** — when both aria-cowork (Cowork) and aria-knowledge (Code) are installed, work in either mode and the other sees your captures.

When v0.2.0 ships, `/audit-knowledge` adds a structured governance pass for promoting backlogs to canonical files. Until then, periodic manual sweeps via `/backlog` work fine.
