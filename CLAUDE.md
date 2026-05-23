# CLAUDE.md — aria-cowork

**Status (2026-05-19):** **v1.1.0 SHIPPED publicly** at `mikeprasad/aria-cowork` — three same-day releases on top of the first public release ceremony: v1.0.0 (initial public ship) → v1.0.1 (install-fix patch from parallel session: `google_docs` → `google docs` MCP id + Cowork validator description-length fixes + aggregate-description preflight in release.sh) → v1.1.0 (minor: `/wrapup` vs `/handoff` intent split + `/wrapup auto` mode, mirroring aria-knowledge v2.19.0; no new skills, no MCP changes, no schema changes — pure behavioral/documentation refactor). First MCP-consuming release + v1.0 stable-contract claim per ADR-006. v1.0.0 ship cycle: originally planned as v0.4.0; bumped to v1.0.0 mid-build per Mike's directive (capability triggers landed); shipped as initial public release ceremony (git init + push to mikeprasad/aria-cowork + gh release create). 6 new Cowork-native skills (5 bidirectional MCP-consuming: clip-thread / extract-doc / meeting-notes / digest / sync-decisions, ported byte-faithfully from aria-knowledge v2.18.0 per ADR-013 + ADR-014; plus 1 cowork-only: daily-audit, first-message audit-cadence substitute since Cowork has no SessionStart hook per ADR-004). Skill manifest 20 → 26 (24 distinct + 2 aliases). Ships `.mcp.json` + `CONNECTORS.md` foundation (12 MCPs across 4 categories: chat / email / project tracker / docs) plus 2 new ADRs (015 capability-probe pattern, 016 Rule 22 advisory preamble for external writes). Coordinated release pair with aria-knowledge v2.18.0. **First WRITE-side skill in either ARIA plugin** (`/sync-decisions` mirrors approved decisions to ~~docs MCP per ADR-016 with explicit per-write go-gate). v0.3.0 history below: major parity-catch-up release with aria-knowledge v2.14.0 → v2.17.0. Cowork's skill manifest grew from 10 → 20 skills (18 distinct + 2 aliases for /audit-knowledge ↔ /knowledge-audit and /audit-config ↔ /config-audit). Adds 5 planned-but-missing skills (/extract, /snapshot, /wrapup, /audit-knowledge, /audit-config) + 3 net-new skills not in original ADR-005 triage (/prospect, /retrospect, /handoff with three modes including new `brief`). Knowledge folder schema parity: aliases.md user-owned template (v2.16.0), semantic-hints frontmatter convention (v2.16.0), archive-cohort conventions for never-delete (v2.15.1+2), working-rules.md sync to v2.14.3+ baseline (Behavioral Foundation preamble + Rule 20 dual-form + 7 rule refinements), user-examples.md with cowork-flavored seed. 7 cowork-modified skills produce schema-identical knowledge-folder outputs per ADR-013. v0.3.0 also introduced the bidirectional feature flow precedent (B2 `/handoff brief` + B5 `/intake doc` originated in cowork's design discussion, shipped in aria-knowledge v2.17.0 first per schema-source-of-truth) — see ADR-014. **Cowork install works.** Prior release sequence (v0.2.1 through v0.2.5) preserved in CHANGELOG.md. Persistent-grant + default-path architecture per ADR-008 unchanged. Memory file at `~/.claude/projects/.../memory/project_aria_cowork.md` has full session history.

**Cross-plugin compatibility (since v0.3.0 / aria-knowledge v2.17.0):** Features may originate in either plugin and port to the other; aria-knowledge remains the schema source-of-truth (output formats, knowledge-folder conventions, archive structures). v0.3.0's `/handoff brief` and `/intake doc` modes are the first cowork-originated features ported into aria-knowledge. See ADR-014 for the architectural rationale.

## Probe results — 2026-04-30 (live)

aria-probe plugin built + installed in Cowork + ran. Probe results at `~/Projects/knowledge/probe-test/probe-results-2026-04-30T07-01-09.md`. Headline:

| Probe | Verdict |
|-------|---------|
| 11 — Folder attachment | INCONCLUSIVE (spec finding: cwd ≠ attached folder) |
| 2 — Filesystem write | **PASS** (hard-fail GREEN) |
| 3 — Cross-surface read | **PASS** (hard-fail GREEN) |
| 7 — Transcript capture | PASS (degraded — no Cowork API; agent self-recall + user-paste) |

**Architecture works.** Bidirectional file passing through the user-attached folder is confirmed. The cwd-vs-attached-folder finding triggered a mechanical ADR 008 rewrite (renamed: cwd-pattern → attached-folder pattern) and matching corrections in OVERVIEW + ADR 002 + ADR 004. No re-architecture needed.

**Phase 1 is greenlit** pending Mike's separate go-signal.

## What is aria-cowork?

The sibling plugin to [aria-knowledge](../aria-knowledge/) that targets [Claude Cowork](https://claude.com/product/cowork) instead of Claude Code. Both plugins share the same `~/Projects/knowledge/` folder so the user gets one knowledge truth across both surfaces. **Public at `mikeprasad/aria-cowork` since 2026-05-19** (current: v1.1.0).

## Where the spec lives

- **Canonical spec:** [`~/Projects/knowledge/projects/aria-cowork/OVERVIEW.md`](../../knowledge/projects/aria-cowork/OVERVIEW.md)
- **Project README:** [`~/Projects/knowledge/projects/aria-cowork/README.md`](../../knowledge/projects/aria-cowork/README.md)
- **ADRs (14, as of v0.3.0):** [`~/Projects/knowledge/projects/aria-cowork/decisions/`](../../knowledge/projects/aria-cowork/decisions/) — includes new ADR-013 (cowork-modified-skills schema-identical outputs) + ADR-014 (bidirectional feature flow) + Section 5b amendment to ADR-005
- **Validation gate (Phase -1 checklist):** [`~/Projects/knowledge/projects/aria-cowork/VALIDATION.md`](../../knowledge/projects/aria-cowork/VALIDATION.md)
- **Implementation plan file (ephemeral):** `~/.claude/plans/how-could-we-enable-groovy-dijkstra.md`

## Working in this folder

1. Read the canonical spec (link above) if context is fuzzy.
2. Edit plugin internals under `skills/`, `template/`, `.mcp.json`, etc. Built artifacts (`aria-cowork-*.plugin`) are produced by `./release.sh`.
3. Build + release flow: bump `.claude-plugin/plugin.json` version → update CHANGELOG.md → `./release.sh` (includes aggregate-description preflight as of v1.0.1) → `gh release create vX.Y.Z` with the .plugin asset + stable-filename mirror.
4. Test installs in Cowork via Settings → Plugins → Install from file.

## Current layout (as built)

```
aria-cowork/
├── .claude-plugin/plugin.json
├── .mcp.json                ← 12 MCPs across 4 categories (v1.0.0+)
├── CHANGELOG.md
├── CHANGELOG.archive.md
├── CLAUDE.md                ← this file
├── CODEMAP.md               ← refreshed 2026-05-19
├── CONFIG.md
├── CONNECTORS.md            ← MCP integration guide (v1.0.0+)
├── IDEAS-BACKLOG.md
├── LICENSE                  ← CC BY-NC-SA 4.0
├── PRIVACY.md
├── QUICKSTART.md
├── README.md
├── release.sh               ← + aggregate-description preflight (v1.0.1+)
├── skills/                  ← 26 skills (24 distinct + 2 aliases as of v1.0.0)
└── template/                ← knowledge-folder templates (schema mirror of aria-knowledge)
```

## Historical context (pre-v1.0)

The "Probe results — 2026-04-30 (live)" section above is the original architecture-validation pass that greenlit Phase 1 build. Before v1.0.0 shipped publicly on 2026-05-19, this file documented scaffolding tools and an "Eventual layout (Phase 1)" plan; both are now history. The `cowork-plugin-management` plugin (`~/.claude/plugins/marketplaces/knowledge-work-plugins/cowork-plugin-management/`) is still installed and remains the canonical reference for Cowork plugin authoring patterns — the v0.2.1 description-length validator quirk is documented in `~/Projects/knowledge/guides/claude/cowork-plugin-validation.md`. The original ephemeral plan file (`~/.claude/plans/how-could-we-enable-groovy-dijkstra.md`) is no longer in play.

## Container context

This folder lives under [`Projects/aria/`](../CLAUDE.md), the ARIA container, alongside `aria-knowledge/` (the existing Code-side plugin) and `aria-site/` (the website).

## Rules

- This folder is a public GitHub repo (`mikeprasad/aria-cowork`, public since 2026-05-19). Never commit secrets, internal URLs, or personal info.
- License is CC BY-NC-SA 4.0 (same as aria-knowledge).
- All architectural decisions go through ADRs in `~/Projects/knowledge/projects/aria-cowork/decisions/`.
