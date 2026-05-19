# CLAUDE.md — aria-cowork

**Status (2026-05-19):** **v1.0.1 SHIPPED publicly** at `mikeprasad/aria-cowork` (first public release) — first MCP-consuming release + v1.0 stable-contract claim per ADR-006. v1.0.0 ship cycle: originally planned as v0.4.0; bumped to v1.0.0 mid-build per Mike's directive (capability triggers landed); shipped as initial public release ceremony (git init + push to mikeprasad/aria-cowork + gh release create); v1.0.1 follow-on patch (parallel session) fixed `.mcp.json` `google_docs` → `google docs` MCP id mismatch + trimmed skill descriptions for Cowork validator + added aggregate-description preflight to release.sh. 6 new Cowork-native skills (5 bidirectional MCP-consuming: clip-thread / extract-doc / meeting-notes / digest / sync-decisions, ported byte-faithfully from aria-knowledge v2.18.0 per ADR-013 + ADR-014; plus 1 cowork-only: daily-audit, first-message audit-cadence substitute since Cowork has no SessionStart hook per ADR-004). Skill manifest 20 → 26 (24 distinct + 2 aliases). Ships `.mcp.json` + `CONNECTORS.md` foundation (12 MCPs across 4 categories: chat / email / project tracker / docs) plus 2 new ADRs (015 capability-probe pattern, 016 Rule 22 advisory preamble for external writes). Coordinated release pair with aria-knowledge v2.18.0. **First WRITE-side skill in either ARIA plugin** (`/sync-decisions` mirrors approved decisions to ~~docs MCP per ADR-016 with explicit per-write go-gate). v0.3.0 history below: major parity-catch-up release with aria-knowledge v2.14.0 → v2.17.0. Cowork's skill manifest grew from 10 → 20 skills (18 distinct + 2 aliases for /audit-knowledge ↔ /knowledge-audit and /audit-config ↔ /config-audit). Adds 5 planned-but-missing skills (/extract, /snapshot, /wrapup, /audit-knowledge, /audit-config) + 3 net-new skills not in original ADR-005 triage (/prospect, /retrospect, /handoff with three modes including new `brief`). Knowledge folder schema parity: aliases.md user-owned template (v2.16.0), semantic-hints frontmatter convention (v2.16.0), archive-cohort conventions for never-delete (v2.15.1+2), working-rules.md sync to v2.14.3+ baseline (Behavioral Foundation preamble + Rule 20 dual-form + 7 rule refinements), user-examples.md with cowork-flavored seed. 7 cowork-modified skills produce schema-identical knowledge-folder outputs per ADR-013. v0.3.0 also introduced the bidirectional feature flow precedent (B2 `/handoff brief` + B5 `/intake doc` originated in cowork's design discussion, shipped in aria-knowledge v2.17.0 first per schema-source-of-truth) — see ADR-014. **Cowork install works.** Prior release sequence (v0.2.1 through v0.2.5) preserved in CHANGELOG.md. Persistent-grant + default-path architecture per ADR-008 unchanged. Memory file at `~/.claude/projects/.../memory/project_aria_cowork.md` has full session history.

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

A planned sibling plugin to [aria-knowledge](../aria-knowledge/) that targets [Claude Cowork](https://claude.com/product/cowork) instead of Claude Code. Both plugins share the same `~/Projects/knowledge/` folder so the user gets one knowledge truth across both surfaces.

## Where the spec lives

- **Canonical spec:** [`~/Projects/knowledge/projects/aria-cowork/OVERVIEW.md`](../../knowledge/projects/aria-cowork/OVERVIEW.md)
- **Project README:** [`~/Projects/knowledge/projects/aria-cowork/README.md`](../../knowledge/projects/aria-cowork/README.md)
- **ADRs (14, as of v0.3.0):** [`~/Projects/knowledge/projects/aria-cowork/decisions/`](../../knowledge/projects/aria-cowork/decisions/) — includes new ADR-013 (cowork-modified-skills schema-identical outputs) + ADR-014 (bidirectional feature flow) + Section 5b amendment to ADR-005
- **Validation gate (Phase -1 checklist):** [`~/Projects/knowledge/projects/aria-cowork/VALIDATION.md`](../../knowledge/projects/aria-cowork/VALIDATION.md)
- **Implementation plan file (ephemeral):** `~/.claude/plans/how-could-we-enable-groovy-dijkstra.md`

## Before doing anything in this folder

1. Read the canonical spec (link above).
2. Run the validation gate per VALIDATION.md. **Probes 2 and 3 are hard-fail** — if either fails, return to spec, don't start building.
3. Confirm Mike has explicitly greenlit Phase 1 build. The spec round was approved 2026-04-30; Phase 1 is a separate go-signal.

## Scaffolding tools (locally available as of 2026-04-30)

`cowork-plugin-management` was installed locally:

- Install path: `~/.claude/plugins/marketplaces/knowledge-work-plugins/cowork-plugin-management/`
- Cached version (0.2.2): `~/.claude/plugins/cache/knowledge-work-plugins/cowork-plugin-management/0.2.2/`
- Two skills available via the Skill tool:
  - **`create-cowork-plugin`** — 5-phase guided workflow (Discovery → Component Planning → Design → Implementation → Review & Package). Use this to scaffold aria-cowork's production plugin folder when Phase 1 begins.
  - **`cowork-plugin-customizer`** — for end-users adapting aria-cowork to their stack via `~~` placeholder replacement.

Useful CLI: `claude plugin validate <path-to-plugin-json>` checks plugin structure (per `create-cowork-plugin/SKILL.md` Phase 5).

Packaging recipe (verbatim from canonical):

```bash
cd /path/to/plugin && zip -r /tmp/<name>.plugin . -x "*.DS_Store" && cp /tmp/<name>.plugin <outputs-or-target-dir>/<name>.plugin
```

## Eventual layout (Phase 1)

```
aria-cowork/
├── .claude-plugin/plugin.json
├── .mcp.json
├── skills/
├── commands/
├── template/
├── CHANGELOG.md
├── CLAUDE.md         # <- this file, expanded
├── LICENSE           # CC BY-NC-SA 4.0
├── PRIVACY.md
├── QUICKSTART.md
├── README.md
└── release.sh
```

## Container context

This folder lives under [`Projects/aria/`](../CLAUDE.md), the ARIA container, alongside `aria-knowledge/` (the existing Code-side plugin) and `aria-site/` (the website).

## Rules

- This folder will eventually be a public GitHub repo (`mikeprasad/aria-cowork`). Once the repo exists, never commit secrets, internal URLs, or personal info.
- License is CC BY-NC-SA 4.0 (same as aria-knowledge).
- All architectural decisions go through ADRs in `~/Projects/knowledge/projects/aria-cowork/decisions/`.
