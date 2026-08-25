# aria-cowork Codemap

> Feature-organized reference for the aria-cowork plugin (Claude Cowork sibling of aria-knowledge).
> Last updated: 2026-07-22 | Last refreshed: **2026-08-26** | Sections: 7 | Skills: **24** (measured on disk 2026-08-26; the prior claim of 27 was stale)
>
> **2026-07-22 refresh (update mode):** version drift only — the plugin advanced v1.0.1 → **v1.5.0** since the last stamp. Layout/architecture is otherwise unchanged (still skills-only, persistent-grant, shared knowledge folder). What moved: **skill manifest 26 (24 distinct + 2 aliases) → 27 distinct, 0 aliases.** v1.3.0 added `/foundational-review` + `/readiness-audit` (porting aria-knowledge v2.29.0's review chain) AND removed the 2 audit aliases (`/knowledge-audit`, `/config-audit` — their slash-forms still route via the canonical skills' trigger lists, they just no longer cost a skill dir against the description cap). v1.4.0 added `/interview` (parity with aria-knowledge v2.31.0). v1.5.0 was a `working-rules.md` template sync only (no skill/manifest change). Built artifacts now run through `aria-cowork-1.5.0.plugin`. See Section 2 (Skills) + Section 5 (Built Artifacts) for the refreshed detail. Coordinated aria-knowledge line is now at v2.4x (see `../CLAUDE.md`).
>
> **2026-05-19 refresh (historical):** v0.2.4 → v1.0.1 SHIPPED PUBLIC at `mikeprasad/aria-cowork` (first public release). Skill manifest grew 10 → 26 (v0.3.0 parity-catch-up adding /extract, /snapshot, /wrapup, /audit-knowledge, /audit-config, /prospect, /retrospect, /handoff; v1.0.0 added 5 bidirectional MCP-consuming skills /clip-thread + /extract-doc + /meeting-notes + /digest + /sync-decisions, plus 1 cowork-only /daily-audit). First MCP-consuming release: ships `.mcp.json` (12 servers, 4 categories: chat / email / project tracker / docs) + `CONNECTORS.md`. First WRITE-side ARIA skill (/sync-decisions per ADR-016). 16 ADRs (added 013 schema-identical outputs, 014 bidirectional feature flow, 015 capability-probe, 016 Rule 22 advisory preamble). Coordinated with aria-knowledge v2.18.1.
>
> **How to use:** Read the directory below (~22 lines), then load specific
> sections with `Read CODEMAP.md offset=X limit=Y`.
> To find a section's line: `Grep "^## " CODEMAP.md`

## Directory

| # | Section | Covers | Key paths |
|---|---------|--------|-----------|
| 0 | Project Identity & Stack | plugin metadata, version, license, distribution | `.claude-plugin/plugin.json`, `CLAUDE.md` |
| 1 | Plugin Layout | top-level folders + docs | `.claude-plugin/`, `skills/`, `template/`, `probe/` |
| 2 | Skills | the 27 user-facing skills (27 distinct, 0 aliases) — see 2026-07-22 refresh note above | `skills/*/SKILL.md` |
| 3 | Template Scaffold | knowledge folder structure deployed by `aria-setup` | `template/` |
| 4 | Probe Plugin | diagnostic sibling plugin (`aria-probe`) | `probe/`, `aria-probe.plugin` |
| 5 | Built Artifacts | versioning history, build process | `aria-cowork-*.plugin` |
| 6 | Relationship to aria-knowledge | sibling port, divergences, shared rules | `../plugin-claude-code/` |
| C1 | File Index | quick lookup table | top-level |
| BL | Build Log | per-section status + dates | end of file |

---

## 0. Project Identity & Stack

**Plugin:** aria-cowork **v1.7.0** (on-disk manifest verified 2026-08-26; latest built artifact `aria-cowork-1.7.0.plugin`). The prior v1.5.0 claim was stale — v1.6/v1.7 shipped the /intake consolidation and /interview guided cadence.
**Type:** Claude Cowork plugin (skills-only — no commands/, hooks/, agents/; ships `.mcp.json` + `CONNECTORS.md` for 12-server MCP framework across 4 categories: chat / email / project tracker / docs).
**License:** CC BY-NC-SA 4.0 (matches aria-knowledge).
**Author:** Mike Prasad.
**Distribution:** Consolidated into `mikeprasad/aria-knowledge/plugin-claude-cowork/` as of v2.20.0 (2026-05-24). Originally published as standalone `mikeprasad/aria-cowork` (first public release 2026-05-19 — v1.0.0 ceremony + v1.0.1 same-day patch; the standalone repo is archived with a redirect).
**Spec:** Canonical at `~/Projects/knowledge/projects/aria-cowork/OVERVIEW.md`; ADRs in `decisions/`. Validation gate at `VALIDATION.md` (Probes 2 + 3 hard-fail).

See `CLAUDE.md` for full session/build status (v0.2.x → v0.3.0 parity-catch-up → v1.0.0 first-public + MCP foundation → v1.0.1 patch → **v1.1.x** wrapup/handoff intent-split + Opus/index parity → **v1.2.0** `snap` mode → **v1.3.0** `/foundational-review` + `/readiness-audit` added, 2 audit aliases removed → **v1.4.0** `/interview` added → **v1.5.0** working-rules template sync to canonical parity). See `../CLAUDE.md` for ARIA container context. **Cowork-specific release constraint:** `release.sh` enforces a hard cap (~9000 chars, empirical fail at 9233) on the sum of all `description` fields across `skills/*/SKILL.md` — the recurring driver behind the description trims in v1.3.0/v1.4.0.

---

## 1. Plugin Layout

```
aria-cowork/
├── .claude-plugin/plugin.json          # plugin manifest (name, version, description, author)
├── .gitignore
├── .mcp.json                           # 12 MCP servers across 4 categories (v1.0.0+)
├── CLAUDE.md                           # session status + spec pointers (~8.6KB)
├── CHANGELOG.md                        # versioned release notes (~78KB)
├── CHANGELOG.archive.md                # pre-v1.0 release notes
├── README.md                           # user-facing overview (~25KB)
├── CONFIG.md                           # config-field reference (used by /audit-config field enumeration)
├── CONNECTORS.md                       # MCP integration guide (v1.0.0+)
├── IDEAS-BACKLOG.md
├── PRIVACY.md
├── QUICKSTART.md
├── LICENSE                             # CC BY-NC-SA 4.0
├── SESSION.md                          # atlas-read session snapshot (gitignored, ephemeral)
├── CODEMAP.md                          # this file
├── release.sh                          # builds aria-cowork-<version>.plugin (+ aggregate-description preflight)
├── skills/                             # 27 skill folders (SKILL.md each; 0 aliases)
├── template/                           # knowledge-folder scaffold deployed by aria-setup
├── probe/                              # source for aria-probe diagnostic plugin
├── aria-cowork-1.1.2.plugin … aria-cowork-1.5.0.plugin   # built artifacts (zip); 1.5.0 is CURRENT (~300KB)
└── aria-cowork.plugin                  # version-stable mirror of the latest artifact
```

**No `commands/`, no `hooks/`, no `agents/`** — pure skills-only architecture (Cowork has no hooks API). Slash commands surface via skill `name:` frontmatter; user invokes `/help`, `/ask`, etc. **It DOES ship `.mcp.json`** (12 servers) as of v1.0.0 — the 5 MCP-consuming skills probe it at runtime per ADR-015.

---

## 2. Skills

27 user-facing skills under `skills/<name>/SKILL.md` (27 distinct, **0 aliases** — the 2 audit aliases were removed in v1.3.0; their slash-forms still route via the canonical skills' trigger lists). Each has a `name:` (the slash command) and `description:` with trigger phrases; most have `argument-hint:`. Per ADR-094, when both ports load in one session, bare-slash names resolve to plugin-claude-code — cowork's variants are namespaced (`/aria-cowork:handoff`, etc.). Grouped by function:

**Config / lookup / health**

| Skill | Slash | Purpose |
|-------|-------|---------|
| `aria-setup` | `/aria-setup` | First-run + post-update config: verify knowledge folder reachable from Cowork, scaffold structure, write `aria-config.md`. Re-runnable. |
| `help` | `/help` | List available aria-cowork commands. |
| `rules` | `/rules [number\|keyword]` | Look up working rules by number or keyword. |
| `stats` | `/stats` | Knowledge-base health metrics — counts, backlog depth, audit status, tag stats, coverage gaps. |
| `context` | `/context <tags>` | Load relevant promoted knowledge by tag (AND-able). |
| `backlog` | `/backlog [type] [clear …]` | View / manage pending backlog items (insights, decisions, extraction, rules). |
| `index` | `/index` | Rebuild knowledge tag index — normalize tags, flag untagged, detect stale, regenerate `index.md`. |

**Capture / research**

| Skill | Slash | Purpose |
|-------|-------|---------|
| `ask` | `/ask <question>` | Research a question, check existing knowledge first, draft a doc, save directly (real-time review). |
| `clip` | `/clip <url\|text>` | Quick-capture a URL or snippet to intake for later audit review. |
| `intake` | `/intake <path\|glob\|url> …` | Bulk-import files/dirs/URLs/pasted content into intake backlogs. |
| `extract` | `/extract` | Extract uncaptured knowledge from the current conversation before compaction. |
| `snapshot` | `/snapshot` | Save a snapshot of the current Cowork conversation to intake on demand. |
| `interview` | `/interview <project\|knowledge\|deep-dive> [topic]` | ELICIT knowledge by interviewing the user, stage to `intake/` for manual review. **Added v1.4.0.** |

**Audit / lifecycle**

| Skill | Slash | Purpose |
|-------|-------|---------|
| `audit-knowledge` | `/audit-knowledge` | Scan the attached knowledge folder for extractable items, run idea-routing dispositions, archive, reindex. |
| `audit-config` | `/audit-config` | Audit project config/docs for drift, staleness, broken references (field enumeration via `CONFIG.md`, not `bin/config.sh`). |
| `daily-audit` | `/daily-audit` | First-message audit-cadence substitute for Cowork (no SessionStart hook per ADR-004). Cowork-only. |
| `wrapup` | `/wrapup [auto\|snap]` | Close out cleanly — no passoff. Updates PROGRESS/CLAUDE/memory, emits a commit message, runs `/extract`. |
| `handoff` | `/handoff [auto\|brief\|snap]` | Passoff package — future-you (restart) or coworker (brief mode). |

**Review chain (added v1.3.0, ports aria-knowledge v2.29.0)**

| Skill | Slash | Purpose |
|-------|-------|---------|
| `prospect` | `/prospect [scope]` | Structured pre-mortem on a plan BEFORE execution: per-step risk verdicts (PROCEED/SHRINK/SPLIT/DEFER/KILL). |
| `retrospect` | `/retrospect [scope]` | Structured retrospective on a shipped range/release/PR/commit/session: per-fix validation. |
| `foundational-review` | `/foundational-review <scope-root> [--decision …]` | Verdict-led review before an irreversible decision. Bundles the genericized process doc at `skills/foundational-review/foundational-review-chain.md`. |
| `readiness-audit` | `/readiness-audit <scope-root> [--for …]` | "Is it clean/legal/consistent to ship for THIS event?" — recurring surface-audit sibling of `/foundational-review`. Read-only. |

**MCP-consuming (bidirectional; probe `.mcp.json` at runtime per ADR-015)**

| Skill | Slash | `~~category` deps |
|-------|-------|-------|
| `clip-thread` | `/clip-thread <id>` | `~~chat` OR `~~email` — capture a chat/email thread to intake. |
| `extract-doc` | `/extract-doc <src>` | `~~docs` — pull insights from a single doc/page (Notion, Google Doc, Confluence). |
| `meeting-notes` | `/meeting-notes` | `~~docs` (paste fallback) — fold a meeting transcript into structured intake. |
| `digest` | `/digest` | `~~chat` + `~~email` + `~~project tracker` + `~~docs` — cross-tool rollup of pending/shipped/blocked. |
| `sync-decisions` | `/sync-decisions` | `~~docs` (WRITE) — mirror approved decisions out to a connected docs MCP (first write-side ARIA skill, per ADR-016; explicit per-write go-gate). |

**Still Code-only by design (ADR-005 permanent exclusions, each with a documented revisit-condition):** `/codemap`, `/stitch`, `/distill`, `/audit-share`. Cowork skips the CODEMAP/STITCH-authoring surface + the share-classification surface; Code-side absorbs them.

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

Version ceremony (per `CLAUDE.md` §"Build + release flow"): bump `.claude-plugin/plugin.json` version → update `CHANGELOG.md` → `./release.sh` (runs the aggregate-description preflight against the ~9000-char cap) → `gh release create vX.Y.Z` with the `.plugin` asset + stable-filename mirror. On-disk artifacts (`aria-cowork-*.plugin`) present as of this refresh:

| Version | Date | Size | Highlights |
|---------|------|------|-----------|
| 1.1.2 | 2026-05-25 | ~270KB | (Coordinated w/ aria-knowledge v2.20.1 — ADR-094 gate UX revision.) |
| 1.1.3 | 2026-05-28 | ~272KB | wrapup/handoff spec fixes (coordinated w/ aria-knowledge v2.20.2). |
| 1.1.4 | 2026-05-29 | ~272KB | Opus 4.8 readiness — `working-rules.md` `Why`-clause de-versioned (coordinated w/ v2.20.3). |
| 1.1.5 | 2026-06-04 | ~273KB | `/index` ephemeral-tag exclusion + `/wrapup` picker fix (coordinated w/ v2.21.0/v2.22.3). |
| 1.2.0 | 2026-06-10 | ~276KB | `snap` mode for `/wrapup` + `/handoff` (coordinated w/ v2.28.0). |
| 1.3.0 | 2026-06-18 | ~291KB | Added `/foundational-review` + `/readiness-audit`; removed the 2 audit aliases; description cap-relief trim (coordinated w/ v2.30.0). |
| 1.4.0 | 2026-06-29 | ~297KB | Added `/interview` (coordinated w/ v2.31.0); cap-relief trim (summed descriptions 8864/9000). |
| **1.5.0** | **2026-06-29** | **~301KB** | `working-rules.md` template sync to canonical parity — Rules 35+36+37 (coordinated w/ v2.38.0); no skill/manifest change. **CURRENT.** |

Older artifacts (0.1.0 – 1.1.0) are no longer retained on disk; full lineage is in `CHANGELOG.md` + `CHANGELOG.archive.md`.

Diagnostic: `aria-probe.plugin` was a separate one-shot validation artifact (source still at `probe/`, manifest `aria-probe` v0.2.0), not part of aria-cowork's version chain. The built `.plugin` is no longer on disk.

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
| Audit/extraction/review surface | full (incl. `/codemap`, `/distill`, `/stitch`, `/audit-share`) | most of it ported (`/extract`, `/audit-*`, `/wrapup`, `/handoff`, `/retrospect`, `/prospect`, `/snapshot`, `/foundational-review`, `/readiness-audit`, `/interview`); still excludes `/codemap`, `/distill`, `/stitch`, `/audit-share` per ADR-005 |
| Repo status | consolidated repo, public on GitHub | same repo (nested at `plugin-claude-cowork/`); public since first release |
| Version (this refresh) | v2.4x line (see `../CLAUDE.md`) | **v1.5.0** |

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
| 0 | Project Identity & Stack | Complete | 2026-07-22 |
| 1 | Plugin Layout | Complete | 2026-07-22 |
| 2 | Skills | Complete | 2026-07-22 |
| 3 | Template Scaffold | Complete | 2026-05-06 |
| 4 | Probe Plugin | Complete | 2026-05-06 |
| 5 | Built Artifacts | Complete | 2026-07-22 |
| 6 | Relationship to aria-knowledge | Complete | 2026-07-22 |
| C1 | File Index | Complete | 2026-05-06 |

**Generation notes (2026-05-06):** Created via `/codemap create` non-interactive mode. Skills-only plugin — no Section 1 (Data Flow) or Section 2 (Entity Model) since there's no request lifecycle or persistent entity model; folded into Section 1 (Plugin Layout) + Section 2 (Skills). No `/extract` offer in this run (per CREATE-mode constraints).

**Update notes (2026-07-22):** `/codemap update` mode. Version drift refresh (v1.0.1 → v1.5.0); no genuine architecture change since the last stamp. Refreshed sections 0/1/2/5/6: skill manifest 26 (24 distinct + 2 aliases) → 27 distinct (v1.3.0 added `/foundational-review` + `/readiness-audit` and removed the 2 audit aliases; v1.4.0 added `/interview`); corrected the stale "No `.mcp.json`" claim (`.mcp.json` shipped in v1.0.0) and the stale "audit surface = none" divergence; rebuilt the artifact table from the on-disk `.plugin` files (1.1.2–1.5.0). Sections 3 (Template Scaffold), 4 (Probe Plugin), C1 (File Index) unchanged — no content drift (template/, probe/ source untouched; probe README-only `ls` confirms). Both changelog files preserved as historical record.
