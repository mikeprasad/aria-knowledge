# aria-cowork Codemap

> Feature-organized reference for the aria-cowork plugin (Claude Cowork sibling of aria-knowledge).
> Last updated: 2026-05-19 | Sections: 7 | Skills: 26 (24 distinct + 2 aliases)
>
> **2026-05-19 refresh:** v0.2.4 → v1.0.1 SHIPPED PUBLIC at `mikeprasad/aria-cowork` (first public release). Skill manifest grew 10 → 26 (v0.3.0 parity-catch-up adding /extract, /snapshot, /wrapup, /audit-knowledge, /audit-config, /prospect, /retrospect, /handoff; v1.0.0 added 5 bidirectional MCP-consuming skills /clip-thread + /extract-doc + /meeting-notes + /digest + /sync-decisions, plus 1 cowork-only /daily-audit). First MCP-consuming release: ships `.mcp.json` (12 servers, 4 categories: chat / email / project tracker / docs) + `CONNECTORS.md`. First WRITE-side ARIA skill (/sync-decisions per ADR-016). 16 ADRs (added 013 schema-identical outputs, 014 bidirectional feature flow, 015 capability-probe, 016 Rule 22 advisory preamble). Coordinated with aria-knowledge v2.18.1.
>
> **How to use:** Read the directory below (~20 lines), then load specific
> sections with `Read CODEMAP.md offset=X limit=Y`.
> To find a section's line: `Grep "^## " CODEMAP.md`

## Directory

| # | Section | Covers | Key paths |
|---|---------|--------|-----------|
| 0 | Project Identity & Stack | plugin metadata, version, license, distribution | `.claude-plugin/plugin.json`, `CLAUDE.md` |
| 1 | Plugin Layout | top-level folders + docs | `.claude-plugin/`, `skills/`, `template/`, `probe/` |
| 2 | Skills | the 26 user-facing skills (24 distinct + 2 aliases) — see 2026-05-19 refresh note above | `skills/*/SKILL.md` |
| 3 | Template Scaffold | knowledge folder structure deployed by `aria-setup` | `template/` |
| 4 | Probe Plugin | diagnostic sibling plugin (`aria-probe`) | `probe/`, `aria-probe.plugin` |
| 5 | Built Artifacts | versioning history, build process | `aria-cowork-*.plugin` |
| 6 | Relationship to aria-knowledge | sibling port, divergences, shared rules | `../plugin-claude-code/` |
| C1 | File Index | quick lookup table | top-level |
| BL | Build Log | per-section status + dates | end of file |

---

## 0. Project Identity & Stack

**Plugin:** aria-cowork v1.0.1 (shipped publicly 2026-05-19).
**Type:** Claude Cowork plugin (skills-only — no commands/, hooks/, agents/; now ships `.mcp.json` + `CONNECTORS.md` for 12-server MCP framework across 4 categories: chat / email / project tracker / docs).
**License:** CC BY-NC-SA 4.0 (matches aria-knowledge).
**Author:** Mike Prasad.
**Distribution:** Consolidated into `mikeprasad/aria-knowledge/plugin-claude-cowork/` as of v2.20.0 (2026-05-24). Originally published as standalone `mikeprasad/aria-cowork` (first public release 2026-05-19 — v1.0.0 ceremony + v1.0.1 same-day patch).
**Spec:** Canonical at `~/Projects/knowledge/projects/aria-cowork/OVERVIEW.md`; 16 ADRs in `decisions/`. Validation gate at `VALIDATION.md` (Probes 2 + 3 hard-fail).

See `CLAUDE.md` for full session/build status (v0.2.0 → v0.2.5 → v0.3.0 parity-catch-up → v1.0.0 first-public + MCP foundation → v1.0.1 same-day patch with google_docs MCP id fix + description-length validator fixes + aggregate-description preflight). See `../CLAUDE.md` for ARIA container context.

---

## 1. Plugin Layout

```
aria-cowork/
├── .claude-plugin/plugin.json          # plugin manifest (name, version, description, author)
├── .gitignore
├── CLAUDE.md                           # session status + spec pointers (5.4KB)
├── CHANGELOG.md                        # versioned release notes (24KB)
├── README.md                           # user-facing overview (6.6KB)
├── LICENSE                             # CC BY-NC-SA 4.0
├── skills/                             # 10 skill folders (SKILL.md each)
├── template/                           # knowledge-folder scaffold deployed by aria-setup
├── probe/                              # source for aria-probe diagnostic plugin
├── aria-cowork-0.1.0.plugin            # built artifact (zip)
├── aria-cowork-0.2.0.plugin
├── aria-cowork-0.2.1.plugin
├── aria-cowork-0.2.2.plugin
├── aria-cowork-0.2.3.plugin
├── aria-cowork-0.2.4.plugin            # CURRENT (~80KB)
└── aria-probe.plugin                   # built diagnostic plugin (~9KB)
```

**No `.mcp.json`, no `commands/`, no `hooks/`, no `agents/`** — pure skills-only architecture. Slash commands surface via skill `name:` frontmatter; user invokes `/help`, `/ask`, etc.

---

## 2. Skills

10 user-facing skills under `skills/<name>/SKILL.md`. Each has a `name:` (used as the slash command) and `description:` with trigger phrases. Several have `argument-hint:`.

| # | Skill | Slash | Purpose |
|---|-------|-------|---------|
| 1 | `aria-setup` | `/aria-setup` | First-run + post-update config: verify knowledge folder reachable from Cowork, scaffold structure, write `aria-config.md`. Re-runnable. (Renamed from `setup` in v0.2.2 for collision-free natural-language invocation.) |
| 2 | `ask` | `/ask <question>` | Research a question, check existing knowledge first, draft a knowledge doc, save directly (skips backlogs — real-time review). |
| 3 | `backlog` | `/backlog [type] [clear ...]` | View / manage pending backlog items (insights, decisions, extraction, rules). |
| 4 | `clip` | `/clip <url\|text> [tags]` | Quick-capture URL or snippet to intake for later review at next `/audit-knowledge`. |
| 5 | `context` | `/context <tags>` | Load relevant promoted knowledge by tag (AND-able). |
| 6 | `help` | `/help` | List available aria-cowork commands. |
| 7 | `index` | `/index` | Rebuild knowledge tag index — normalize tags, flag untagged, detect stale, regenerate `index.md`. |
| 8 | `intake` | `/intake <path\|glob\|url> ...` | Bulk import from files/dirs/URLs/pasted content into intake backlogs (vs `/clip` which is single-item). |
| 9 | `rules` | `/rules [number\|keyword]` | Look up working rules by number or keyword. |
| 10 | `stats` | `/stats` | Knowledge base health metrics — counts, backlog depth, audit status, tag stats, coverage gaps. |

**Notable absences vs. aria-knowledge:** no `/extract`, `/snapshot`, `/wrapup`, `/retrospect`, `/audit-knowledge`, `/audit-config`, `/audit-share`, `/codemap`, `/distill`, `/stitch`. Cowork is read/write-light + capture-focused; Code-side absorbs the heavy audit/extraction surface.

---

## 3. Template Scaffold

`template/` is the knowledge-folder skeleton deployed by `/aria-setup` into the user's knowledge folder (default `~/Projects/knowledge/`).

```
template/
├── OVERVIEW.md             # knowledge-folder orientation doc
├── README.md               # user-facing readme
├── LOCAL.md                # local-only notes scaffold
├── intake/                 # capture buckets
│   ├── insights-backlog.md
│   ├── decisions-backlog.md
│   ├── extraction-backlog.md
│   ├── rules-backlog.md
│   ├── attachments/
│   ├── clippings/
│   └── notes/
├── rules/
│   ├── working-rules.md             # mirrored from aria-knowledge baseline
│   ├── user-rules.md
│   ├── change-decision-framework.md # includes Plan-Level Application (v0.2.3)
│   └── enforcement-mechanisms.md    # Rule 34 enforcement note (v0.2.3)
├── decisions/README.md
├── approaches/README.md
├── guides/README.md
├── references/README.md
├── archive/README.md
└── logs/
    ├── knowledge-audit-log.md
    └── config-audit-log.md
```

**v0.2.3 sync:** `template/rules/` now mirrors aria-knowledge v2.13.5 baseline (Rules 33 + 34 added to working-rules.md, Plan-Level Application section added to change-decision-framework.md, Rule 34 enforcement note added to enforcement-mechanisms.md). The scaffold is the source of truth for the user's first-run knowledge folder.

---

## 4. Probe Plugin

`probe/` is source for a separate diagnostic plugin shipped as `aria-probe.plugin` (~9KB). Used to validate Cowork plugin capabilities before / during aria-cowork build.

```
probe/
├── .claude-plugin/plugin.json    # name=aria-probe, version=0.2.0
├── README.md                     # probe specs (7.7KB)
└── skills/aria-probe/            # the single diagnostic skill
```

**v0.2.0 (probe):** also tests whether Cowork can read existing aria-knowledge config at `~/.claude/aria-knowledge.local.md` when `~/.claude/` is attached as additional workspace folder.

**Live results (2026-04-30):** Probes 2 (filesystem write) + 3 (cross-surface read) PASS hard-fail GREEN. Probe 11 (folder attachment) inconclusive — surfaced cwd-vs-attached-folder finding that triggered ADR 008 mechanical rewrite. Results at `~/Projects/knowledge/probe-test/probe-results-2026-04-30T07-01-09.md`. Bidirectional file passing through user-attached folder is confirmed.

**Lifecycle:** install once, run `/aria-probe`, uninstall.

---

## 5. Built Artifacts

Build process (per CLAUDE.md packaging recipe):
```bash
cd /path/to/plugin && zip -r /tmp/<name>.plugin . -x "*.DS_Store" && cp /tmp/<name>.plugin <target>/<name>.plugin
```

Validation: `claude plugin validate <path-to-plugin.json>` (per `cowork-plugin-management/create-cowork-plugin/SKILL.md` Phase 5).

| Version | Date | Size | Highlights |
|---------|------|------|-----------|
| 0.1.0 | 2026-04-30 | 68.5KB | Initial build |
| 0.2.0 | 2026-05-03 | 72.2KB | First feature expansion (clip → audit-knowledge flow noted in skill descriptions) |
| 0.2.1 | 2026-05-04 | 73.6KB | Fix: undocumented `plugin.json` description-length cap (~500 chars) was rejecting v0.2.0 uploads |
| 0.2.2 | 2026-05-04 | 74.6KB | Renamed `setup` skill → `aria-setup` for collision-free natural-language invocation |
| 0.2.3 | 2026-05-04 | 79.8KB | Sync to aria-knowledge v2.13.5 baseline: Rules 33 + 34 in working-rules, Plan-Level Application in change-decision-framework, Rule 34 enforcement note, dynamic-version-from-plugin.json in `aria-setup/SKILL.md` |
| **0.2.4** | **2026-05-05** | **81.3KB** | Removed speculative `captured_via: aria-cowork` field from `/ask` and `/clip` frontmatter (Rules 13 + 18 — no pre-pollution before a real audit consumer needs it). **CURRENT.** |

Diagnostic: `aria-probe.plugin` (8.97KB, dated 2026-04-30) is a separate artifact, not part of aria-cowork's version chain.

---

## 6. Relationship to aria-knowledge

Sibling port to [`../plugin-claude-code/`](../plugin-claude-code/) within the same repo (`mikeprasad/aria-knowledge`). Both share the same `~/Projects/knowledge/` folder so the user gets one knowledge truth across both surfaces.

**Shared:**
- Knowledge folder (default `~/Projects/knowledge/`).
- License (CC BY-NC-SA 4.0).
- Working rules (`template/rules/` mirrors aria-knowledge baseline; v0.2.3 synced to v2.13.5 incl. Rules 33 + 34).
- Change decision framework, enforcement mechanisms.
- Tag index format.
- Backlog files (`insights-backlog.md`, `decisions-backlog.md`, `extraction-backlog.md`, `rules-backlog.md`).

**Divergences:**

| Axis | aria-knowledge (Code) | aria-cowork (Cowork) |
|------|----------------------|----------------------|
| Surface | Claude Code | Claude Cowork |
| Components | skills + commands + hooks + agents | **skills-only** |
| .mcp.json | yes | no |
| Folder access | direct (cwd) | persistent grant via `claude_desktop_config.json` |
| Path discovery | cwd-relative | attached-folder-relative (ADR 008 third revision) |
| Audit/extraction surface | full (`/extract`, `/audit-*`, `/wrapup`, `/retrospect`, `/snapshot`, `/codemap`, `/distill`, `/stitch`) | none — capture-focused |
| Repo status | public on GitHub | local-only (will become public in Phase 1) |

**Architecture (per ADR 008, third revision):** path resolution = cwd → attached-folder → persistent-grant. Cowork plugin uses persistent-grant + default-path; folder is granted once via `claude_desktop_config.json` and reachable across all project workspaces.

**Scaffolding tools:** `cowork-plugin-management` plugin (installed locally) provides `create-cowork-plugin` (5-phase guided workflow) and `cowork-plugin-customizer` (end-user adaptation via `~~` placeholders).

---

## C1. File Index

| Looking for... | Location |
|----------------|----------|
| Plugin manifest | `.claude-plugin/plugin.json` |
| Project status / build history | `CLAUDE.md` |
| User-facing overview | `README.md` |
| Versioned release notes | `CHANGELOG.md` |
| License | `LICENSE` (CC BY-NC-SA 4.0) |
| Skill source | `skills/<name>/SKILL.md` |
| Knowledge folder scaffold | `template/` |
| Working rules template | `template/rules/working-rules.md` |
| Change decision framework template | `template/rules/change-decision-framework.md` |
| Enforcement mechanisms template | `template/rules/enforcement-mechanisms.md` |
| Probe plugin source | `probe/` |
| Built plugin artifacts | `aria-cowork-*.plugin` (and `aria-probe.plugin`) |
| Canonical project spec | `~/Projects/knowledge/projects/aria-cowork/OVERVIEW.md` |
| ADRs | `~/Projects/knowledge/projects/aria-cowork/decisions/` |
| Validation gate | `~/Projects/knowledge/projects/aria-cowork/VALIDATION.md` |
| Probe live results | `~/Projects/knowledge/probe-test/probe-results-2026-04-30T07-01-09.md` |

---

## Build Log

| # | Section | Status | Updated |
|---|---------|--------|---------|
| 0 | Project Identity & Stack | Complete | 2026-05-06 |
| 1 | Plugin Layout | Complete | 2026-05-06 |
| 2 | Skills | Complete | 2026-05-06 |
| 3 | Template Scaffold | Complete | 2026-05-06 |
| 4 | Probe Plugin | Complete | 2026-05-06 |
| 5 | Built Artifacts | Complete | 2026-05-06 |
| 6 | Relationship to aria-knowledge | Complete | 2026-05-06 |
| C1 | File Index | Complete | 2026-05-06 |

**Generation notes (2026-05-06):** Created via `/codemap create` non-interactive mode. Skills-only plugin — no Section 1 (Data Flow) or Section 2 (Entity Model) since there's no request lifecycle or persistent entity model; folded into Section 1 (Plugin Layout) + Section 2 (Skills). No `/extract` offer in this run (per CREATE-mode constraints).
