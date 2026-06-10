# CLAUDE.md — ARIA

## What This Is

ARIA (Applied Reasoning and Insight Architecture) — an active knowledge and development discipline plugin for Claude Code. Three pillars: a five-phase knowledge lifecycle (capture → govern → promote → apply → refresh), decision discipline (Rule 22 enforcement at every edit), and codebase & task mapping (/codemap for repo traces, /stitch for cross-repo contract binding, /distill for task spec shaping). The "Applied" framing emphasizes the apply phase: trusted knowledge actively shapes the next decision via /context, /rules, /codemap, /stitch, /distill, and Rule 22 — not just stored and recalled.

**Repository:** GitHub (`mikeprasad/aria-knowledge`) — **public repo**

## Cowork Port (plugin-claude-cowork/)

The Claude Cowork port lives at `plugin-claude-cowork/` — consolidated into this repo in v2.20.0 (2026-05-24) from the previously standalone `mikeprasad/aria-cowork` (last standalone release: v1.1.0, 2026-05-19). **Current cowork release: v1.2.0** (2026-06-10, with aria-knowledge v2.28.0 — `snap` mode parity; tag `cowork-v1.2.0` + GH release w/ `.plugin` asset). Prior: v1.1.5 (2026-06-04, with aria-knowledge ~v2.24.x — `/index` ephemeral-tag exclusion + `/wrapup` picker fix). Prior: v1.1.4 (2026-05-29, with aria-knowledge v2.20.3 — Opus 4.8 readiness: `working-rules.md` `Why` clause de-versioned, mirroring plugin-claude-code; Cowork is skills-only so the v2.20.3 hook hardening does not apply here). Prior coordinated cowork release: v1.1.3 (2026-05-25, with aria-knowledge v2.20.2 — wrapup/handoff spec fixes: closing-heading labeling correction + auto-mode extract-always-runs invariant). Both ports share the user's `~/Projects/knowledge/` folder and write to the same canonical config (`aria-config.md`) under an additive-only schema (per ADR-002). Edits to shared surfaces — `aria-config.md` field names, `template/rules/` content, `working-rules.md` rule numbering — must preserve cross-port compatibility. 26 skills (24 distinct + 2 aliases). Cowork-specific authoring constraints documented in `knowledge/guides/claude/cowork-plugin-validation.md`. **Cowork-specific release constraint**: aria-cowork release.sh enforces a 9000-char hard cap on summed SKILL.md description chars (empirical install-fail at 9233, documented v0.2.1 + v1.0.0); v2.20.1's trailing-parenthetical port-id uses a short form on cowork (`(Cowork variant — namespaced-only.)` ~36 chars) versus Code's verbose form (~96 chars), with the full ADR-094 narrative in the Runtime Gate body where no cap applies.

**Bidirectional feature flow (since v0.3.0 / v2.17.0):** Features may originate in either port and port to the other; plugin-claude-code remains the schema source-of-truth (output formats, knowledge-folder conventions, archive structures). v0.3.0's `/handoff brief` and `/intake doc` modes are the first cowork-originated features ported into aria-knowledge. See plugin-claude-cowork ADR-014 for the architectural rationale.

**Bare-slash ownership (ADR-094, v2.19.1):** When both ports are loaded in the same session (most common in Claude Desktop), 24 colliding skill names (`/handoff`, `/wrapup`, `/extract`, `/intake`, etc.) deterministically resolve to **plugin-claude-code** as canonical owner. plugin-claude-cowork's variants are namespaced-only (`/aria-cowork:handoff`, etc.). Each colliding skill carries a Runtime Gate in its body that surfaces a notification when invoked from the wrong runtime (Bash-availability is the fingerprint). The gate applies even in `auto` modes — auto's "implicit-yes" rule is suspended for the runtime-mismatch check per ADR-094 §Part 3. Edits affecting cross-port compatibility (description prepend conventions, gate clause text, anti-trigger language) should preserve this ownership rule. Full design: [`~/Projects/knowledge/projects/aria/decisions/094-bare-slash-canonical-owner-and-dual-runtime-gate.md`](../../knowledge/projects/aria/decisions/094-bare-slash-canonical-owner-and-dual-runtime-gate.md).

## Cursor Port (plugin-cursor-template/)

The Cursor port is a **repo skeleton** (not a Claude marketplace plugin). Users unzip `aria-knowledge-cursor-<version>.zip` into the root of their own project. **Current Cursor release: `2.20.2-cursor.0`** (2026-05-27, parity with plugin-claude-code v2.20.2). Prior Cursor baseline was `2.19.2-cursor.0` / audit build at canonical v2.16.1.

**What ships:** `.cursor/hooks.json`, `.cursor/rules/*.mdc` (5 compiled rule files), `.cursor/aria-knowledge.local.md`, root `AGENTS.md` (Cursor's equivalent of `CLAUDE.md`), `scripts/aria/*.sh`, and a root-level `knowledge/` mirror of `plugin-claude-code/template/`.

**Skill surface (27 commands in `aria-commands.mdc` + audits in `aria-audit.mdc`):** 22 core workflow commands + 3 aliases (documented in preambles) + 5 MCP-consuming skills (`/clip-thread`, `/extract-doc`, `/meeting-notes`, `/digest`, `/sync-decisions`) + `/help` + `/audit-share`. Includes v2.17.0 `/intake doc`, v2.20.2 wrapup/handoff auto-mode `/extract` invariants.

**Intentional Cursor divergences (do not port ADR-094 Runtime Gates per-skill):** aria-cowork is not loaded in typical Cursor sessions. A single preamble note in `aria-commands.mdc` replaces per-skill gates. Rule 22 uses an edit-intent marker (`record-edit-intent.sh`) — advisory `beforeFileEdit`, no transcript proof. No PreCompact; `stop` → `capture-task-boundary.sh` substitutes. MCP servers are user-configured in **Cursor Settings → MCP** (no bundled `.mcp.json` in the template). See `plugin-cursor-template/PORTING.md` and `plugin-cursor-template/audit/ARIA_CURSOR_AUDIT_REPORT.md` §5.

**Maintainer re-sync after canonical skill edits:**

```bash
python3 plugin-cursor-template/scripts/port-skills-to-mdc.py
./release-cursor.sh
```

`port-skills-to-mdc.py` strips Runtime Gate blocks, adapts paths (`AGENTS.md`, `.cursor/aria-knowledge.local.md`), and upserts MCP skill sections idempotently.

## Codex Port (plugin-openai-codex/)

The OpenAI Codex port lives at `plugin-openai-codex/` — an independent installable adapter that uses the shared ARIA knowledge folder and content schema while diverging on plugin manifest shape, hook registration, and tool-boundary behavior for Codex. **Current Codex release: `2.20.2-codex.0`** (2026-05-28, parity with plugin-claude-code v2.20.2). Wires MCP servers via `.mcp.json` (Codex manifest convention uses `mcp_servers` snake_case key vs. Claude's `mcpServers` camelCase — both are correct for their target runtime). Strips ADR-094 Runtime Gate sections from ported skills (gates are Bash-availability-fingerprint-dependent and don't fire in Codex). Ships a port-specific test suite at `plugin-openai-codex/tests/run.sh` that release-codex.sh gates on (skills carry codex metadata, no ADR-094 gates leaked through, `apply_patch` denial shape current, transcript reader doesn't scan without `turn_id`).

**Build with** `./release-codex.sh` from repo root. Reads version from `plugin-openai-codex/.codex-plugin/plugin.json` (single source of truth, strips `-codex.N` suffix for filename). Produces `aria-knowledge-codex-<canonical>.zip` + version-stable `aria-knowledge-codex.zip`. Verification gates: MCP manifest present, `tests/` excluded from artifact, no junk.

## Antigravity Port (plugin-antigravity/)

The Antigravity IDE port lives at `plugin-antigravity/` — targets **Antigravity IDE** (VS Code fork) and **Antigravity CLI** (`agy`) from Google's Antigravity team. **Current Antigravity release: `2.20.2`** (2026-05-28, parity with plugin-claude-code v2.20.2; same-day refresh added native workflow + rules scaffolding and expanded plugin.json — commit `f635e61`). The setup skill's **Step 7ca** scaffolds `.agents/workflows/` (10 thin-shim workflows) and `.agents/rules/aria-rules.md` into the user's workspace, enabling **true native slash-command invocation** (`/setup`, `/handoff`, `/wrapup`, `/extract` fire as first-class Antigravity workflows) and **native Always-On rule enforcement** — distinct from Claude Code's hook-based enforcement model.

**Version sources (two, kept in sync by the maintainer):** `plugin-antigravity/plugin.json` carries the full standard plugin manifest including a `version` field (Antigravity's manifest schema ignores unknown fields, and the standard plugin shape is now used here for parity with sibling ports). `plugin-antigravity/version.txt` is a sidecar that `build.sh` auto-syncs from canonical `plugin-claude-code/.claude-plugin/plugin.json` — `bin/` scripts and the setup skill read from the sidecar. **Maintainer responsibility:** when bumping canonical version, also hand-bump `plugin-antigravity/plugin.json`'s `version` field. `build.sh` auto-syncs `version.txt` but does NOT touch `plugin.json` (it's in the preserved hand-authored files list per `build.sh` line 284). Candidate for `build.sh` automation later — flag as follow-up if the manual two-step becomes a friction point.

**Custom setup behavior is preserved via the overlay pattern.** `build.sh` (lines 117-139) copies canonical skills from `plugin-claude-code/skills/`, then applies `plugin-antigravity/overlays/skills/<name>/SKILL.md` overlays LAST — so port-specific bodies survive canonical resyncs. The setup skill currently has an overlay snapshot at `plugin-antigravity/overlays/skills/setup/SKILL.md` (byte-identical to the live `skills/setup/SKILL.md` — drift detection is a future-work `diff` between the two).

**Two-script model** (different from sibling ports' one-script model):
1. `plugin-antigravity/build.sh` — *regenerates* port content from canonical sources (copies skills from `plugin-claude-code/skills/`, applies overlays from `plugin-antigravity/overlays/`, syncs `version.txt`, patches setup/SKILL.md paths). Run when canonical sources change.
2. `release-antigravity.sh` (at repo root) — stages regenerated port content with junk exclusions and emits `aria-knowledge-antigravity-<version>.zip` + version-stable copy.

**Zip structure is flat (no top-level wrapper dir).** This differs from claude-code/codex/cursor zips which nest content under a plugin-name wrapper, matching Antigravity IDE's install machinery. `release-antigravity.sh` verifies this invariant (`wrapper` count must be 0).

## Project Structure

```
aria/
├── README.md          ← GitHub-facing intro
├── LICENSE            ← CC BY-NC-SA 4.0
├── CHANGELOG.md       ← Version history
├── CLAUDE.md          ← You are here
├── plugin-claude-code/            ← The installable plugin
│   ├── .claude-plugin/
│   │   └── plugin.json
│   ├── bin/           ← Hook scripts (bash)
│   ├── skills/        ← Skill definitions (SKILL.md files)
│   └── template/      ← Knowledge folder templates
├── plugin-openai-codex/      ← Codex port (independent installable unit)
│   ├── .codex-plugin/
│   │   └── plugin.json
│   ├── hooks.json     ← Codex hook registration
│   ├── bin/           ← Claude-standard scripts + Codex adapter
│   ├── commands/      ← Codex command entrypoints
│   ├── skills/        ← Copied ARIA skills (schema-compatible)
│   └── template/      ← Copied Claude-standard knowledge templates
├── plugin-claude-cowork/     ← Cowork port (skills-only; no hooks API in Cowork runtime)
│   ├── .claude-plugin/
│   │   └── plugin.json
│   ├── skills/        ← 26 skills (24 distinct + 2 aliases)
│   ├── template/      ← Knowledge folder templates (schema mirror of plugin-claude-code/)
│   ├── .mcp.json      ← 12 MCP servers across 4 categories
│   └── release.sh     ← Builds aria-cowork-<version>.plugin
├── plugin-cursor-template/   ← Cursor port (repo-skeleton, not a plugin install)
│   ├── .cursor/       ← Cursor-native config
│   │   ├── hooks.json
│   │   ├── aria-knowledge.local.md
│   │   └── rules/     ← 5 compiled .mdc files (27 commands in aria-commands + audits)
│   ├── AGENTS.md      ← Cursor's equivalent of CLAUDE.md (ships to user projects)
│   ├── QUICKSTART.md  ← Cursor-adapted quickstart
│   ├── PORTING.md     ← Maintainer drift tracking + skill→.mdc map
│   ├── knowledge/     ← Knowledge folder (hoisted to root, not under template/)
│   ├── scripts/aria/  ← Hook scripts (instead of bin/)
│   │   └── VERSION    ← Port version (e.g. 2.20.2-cursor.0)
│   ├── scripts/port-skills-to-mdc.py  ← Re-sync from plugin-claude-code/skills/
│   └── audit/         ← Frozen audit artifacts (2.16.1 baseline; see PORTING.md for current)
├── plugin-antigravity/         ← Antigravity IDE / CLI port (flat-zip install)
│   ├── plugin.json   ← Manifest (no version field per Antigravity docs)
│   ├── version.txt   ← Port version sidecar (source of truth — synced by build.sh)
│   ├── mcp_config.json
│   ├── hooks.json
│   ├── bin/          ← Canonical bin scripts + Antigravity adapter (bin/antigravity/)
│   ├── skills/       ← Regenerated from canonical via build.sh
│   ├── template/     ← Regenerated from canonical via build.sh
│   ├── overlays/     ← Per-skill overrides applied by build.sh
│   ├── build.sh      ← Regenerates port content from canonical sources
│   └── tests/        ← Port test suite (smoke + structural)
├── release.sh                  ← Builds claude-code zip (canonical)
├── release-codex.sh            ← Builds codex zip
├── release-cursor.sh           ← Builds cursor zip
├── release-antigravity.sh      ← Builds antigravity zip (flat layout)
└── docs/              ← Extended documentation (future)
```

## Key Conventions

- **`plugin-claude-code/` is the installable unit** — everything inside it is what users copy to their plugins directory
- **`plugin-openai-codex/` is the Codex installable unit** — independent adapter surface, same knowledge schema. Claude `plugin-claude-code/` remains the standard for template/content shape.
- **`plugin-cursor-template/` is the Cursor repo-skeleton** — not a plugin install. Users clone or unzip its contents into the root of their own project. Cursor compiles 27 commands (22 core + 5 MCP) into 5 `.cursor/rules/*.mdc` files because Cursor's Rules system doesn't have a one-skill-per-folder concept. Port version tracks canonical via `scripts/aria/VERSION` (currently `2.20.2-cursor.0`). Maintainer re-sync: `python3 plugin-cursor-template/scripts/port-skills-to-mdc.py`. ADR-094 Runtime Gates are omitted in Cursor. Knowledge folder schema stays compatible with `plugin-claude-code/template/`.
- **Template files** in `plugin-claude-code/template/` are either plugin-managed (diffable on `/setup`) or user-owned (created once, never overwritten). See `plugin-claude-code/skills/setup/SKILL.md` for the authoritative list.
- **Version** lives in `plugin-claude-code/.claude-plugin/plugin.json`
- **Hook scripts** in `plugin-claude-code/bin/` are bash — they read config from `~/.claude/aria-knowledge.local.md`
- **Skills** are markdown files — each skill is a `SKILL.md` with YAML frontmatter
- **Codex hooks** require Codex `plugin_hooks` enabled; the adapter reads `~/.codex/aria-knowledge.local.md` first, then falls back to `~/.claude/aria-knowledge.local.md`
- **`plugin-claude-cowork/` is the Claude Cowork installable unit** — sibling to plugin-claude-code/, both share schema-identical knowledge-folder outputs (per ADR-013). Cowork runtime is skills-only (no hooks API); enforcement is skill-embedded. Per ADR-094, bare-slash skill names resolve to plugin-claude-code as canonical owner when both ports are loaded in the same session; cowork-namespaced variants are `/aria-cowork:handoff` etc.
- **Cursor hooks** use `.cursor/hooks.json` and resolve script paths via `git rev-parse --show-toplevel`. Some Claude enforcement is weaker on Cursor (no transcript access, no documented pre-edit deny) — port uses an edit-intent marker file as the closest available mechanism. See `plugin-cursor-template/audit/ARIA_CURSOR_AUDIT_REPORT.md` §5.
- **`plugin-antigravity/` is the Antigravity IDE/CLI installable unit** — independent port targeting Google's Antigravity IDE (VS Code fork) and `agy` CLI. **Two version sources**: `plugin.json` carries the standard plugin manifest including `version` (Antigravity ignores unknown manifest fields); `version.txt` sidecar is auto-synced by `build.sh` from canonical and read by `bin/` scripts. Maintainer must hand-bump `plugin.json` on canonical bumps (`build.sh` preserves it). Two-script build model: `plugin-antigravity/build.sh` regenerates port content from canonical sources + applies overlays at `overlays/skills/<name>/SKILL.md`; `release-antigravity.sh` (repo root) zips. Zip layout is **flat** (no top-level wrapper dir) vs. sibling ports' wrapped layout. Setup skill's **Step 7ca** scaffolds Antigravity-native `.agents/workflows/` + `.agents/rules/` so slash commands fire as first-class workflows.

## Development Workflow

1. Edit files in `plugin-claude-code/`
2. To test, copy `plugin-claude-code/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/`
3. Restart Claude Code to pick up changes

### Codex Port Workflow

1. Edit Codex adapter files in `plugin-openai-codex/`
2. Keep durable knowledge template/schema changes in sync with `plugin-claude-code/` — Claude remains the schema standard
3. Enable Codex plugin hooks with `codex features enable plugin_hooks` before testing automatic hooks
4. Install via `.agents/plugins/marketplace.json` or copy `plugin-openai-codex/` into a Codex local marketplace

### Cursor Port Workflow

1. Edit canonical skills in `plugin-claude-code/skills/` first (schema source-of-truth), then re-sync the Cursor port:
   ```bash
   python3 plugin-cursor-template/scripts/port-skills-to-mdc.py
   ```
2. Keep durable knowledge surfaces in sync with `plugin-claude-code/template/` — apply the same edits to `plugin-cursor-template/knowledge/` (root-level, not nested under `template/`). See `plugin-cursor-template/PORTING.md` §A for the lockstep file list.
3. The 5 `.mdc` rule files are *compiled* views of canonical `SKILL.md` bodies. `port-skills-to-mdc.py` refreshes `aria-commands.mdc` (core + MCP skills, wrapup/handoff patches, `/help` table) and strips ADR-094 Runtime Gates. Hand-edit `aria-audit.mdc`, `aria-context.mdc`, `aria-core.mdc`, or `aria-rule-22.mdc` when those surfaces change outside the scripted path.
4. Bump `plugin-cursor-template/scripts/aria/VERSION` (`<canonical>-cursor.0`) and run `./release-cursor.sh` from repo root. Zip: `aria-knowledge-cursor-<canonical>.zip`.
5. Users install by unzipping the artifact into the root of their own project, then restarting Cursor. End-user doc: `plugin-cursor-template/QUICKSTART.md`; project instructions file: `AGENTS.md` (not repo-root `CLAUDE.md`).

### Cowork Port Workflow

1. Edit Cowork-specific files in `plugin-claude-cowork/`. Most skills mirror `plugin-claude-code/` via ADR-013 schema-identical outputs; cowork-specific skills (`daily-audit`, cowork-modified `/extract-doc`, etc.) live only here.
2. Keep MCP-consuming skills (clip-thread, extract-doc, meeting-notes, digest, sync-decisions) byte-faithful between ports per ADR-014; plugin-claude-code remains schema source-of-truth.
3. Per ADR-094, when both ports load in the same session, bare-slash command names (`/handoff`, `/extract`, etc.) resolve to plugin-claude-code as canonical owner; cowork-namespaced variants are `/aria-cowork:handoff` etc.
4. Build with `./release.sh` in `plugin-claude-cowork/` — produces `aria-cowork-<version>.plugin`. Install by dragging into a Cowork conversation or via Settings → Plugins → Install from file.
5. Cowork runs as a skills-only plugin (no hooks API). The `/daily-audit` skill substitutes for SessionStart on first message.

### Antigravity Port Workflow

1. Edit canonical skills in `plugin-claude-code/skills/` first (schema source-of-truth). For Antigravity-specific adapter behavior, edit hand-authored files preserved by build.sh: `plugin.json`, `hooks.json`, `mcp_config.json`, `GEMINI.md`, `bin/antigravity/*`, `PORTING.md`, `README.md`, `SMOKE-TEST.md`. Place per-skill overrides in `plugin-antigravity/overlays/`.
2. Regenerate port content from canonical sources:
   ```bash
   ./plugin-antigravity/build.sh
   ```
   This copies skills/template from `plugin-claude-code/`, applies overlays, syncs `version.txt` from the canonical `plugin.json` version, and patches setup/SKILL.md to read version from the sidecar instead of JSON.
3. Bump `plugin-claude-code/.claude-plugin/plugin.json` version first (canonical), then re-run `build.sh` — `version.txt` syncs automatically. **Also hand-bump `plugin-antigravity/plugin.json`'s `version` field** — it's in build.sh's preserved hand-authored files list (line 284) and won't be touched automatically. Forgetting this creates silent drift between `version.txt` and `plugin.json`.
4. Build the release zip from repo root:
   ```bash
   ./release-antigravity.sh
   ```
   Produces `aria-knowledge-antigravity-<version>.zip` (flat layout) + version-stable `aria-knowledge-antigravity.zip`. Verification gates: `plugin.json` present, `version.txt` present, no top-level wrapper dir, no junk.
5. Users install per Antigravity IDE / CLI conventions; see `plugin-antigravity/README.md` and `plugin-antigravity/SMOKE-TEST.md`.

## Rules

- Follow the universal rules in `Projects/CLAUDE.md`
- **This is a public repository** — never commit personal information, API keys, secrets, credentials, internal URLs, or any sensitive data. Content here is visible to anyone on GitHub.
- The plugin's own template content (working-rules, change-decision-framework, enforcement-mechanisms) is both shipped content AND documentation of how the plugin works — edits to these have dual impact
- Bump version in `plugin.json` when making release-worthy changes

## Knowledge Repository

Project-specific architecture decisions live in `~/Projects/knowledge/projects/aria/`:

- `decisions/002-knowledge-extraction-architecture.md` — task-based /extract + audit promotion model
- `decisions/006-full-rule22-format-every-edit.md` — full format on every edit (no compression)
- `decisions/008-skill-knowledge-connections.md` — skill-knowledge connection discovery + drift detection

Cross-project knowledge that applies to ARIA:
- `knowledge/rules/working-rules.md` — the 34 universal rules (ARIA's source of truth ships in plugin-claude-code/template)
- `knowledge/rules/change-decision-framework.md` — Rule 22 framework
- `knowledge/rules/enforcement-mechanisms.md` — enforcement tier model
- `knowledge/guides/claude/plugin-development.md` — Claude Code plugin patterns
- `knowledge/guides/claude/cowork-plugin-validation.md` — Claude Cowork plugin patterns (sibling guide; relevant if coordinating with aria-cowork or shipping a Cowork-side plugin)
- `plugin-cursor-template/PORTING.md` — Cursor skill→`.mdc` compilation map and drift tracking
- `plugin-cursor-template/audit/ARIA_CURSOR_AUDIT_REPORT.md` — Cursor enforcement-gap matrix (§5)

Pre-staged ADR candidates live in `~/Projects/knowledge/intake/decisions-backlog.md` — check there for what's currently queued for next `/audit-knowledge`. Themes queued here historically drift as ADRs promote; the live backlog is the source of truth.

Use `/context aria` to load relevant knowledge by project tag.

---

*Last reviewed: 2026-06-10 — plugin-claude-code **v2.28.0** RELEASED + plugin-claude-cowork **v1.2.0** RELEASED (both tagged + GH releases w/ assets; `main` pushed `59d2237..bce3dd8`): **`snap` mode for `/wrapup` + `/handoff`.** A new mode = **`auto` + one swap**: runs the full silent close-out/handoff (PROGRESS/CLAUDE/memory/commit + handoff's next-session opener) but archives the transcript via `/snapshot` for later extraction **instead of** running `/extract` now — for when context is high and a live `/extract` would risk compaction mid-synthesis. Defining override is the capture step (wrapup Step 8 / handoff Step 6: snap→`/snapshot`, auto→`/extract`); every per-step auto-conditional now reads `auto (or snap)`; invariant = snap **defers, never drops** capture (the snapshot always runs, no skip path). `/help` advertises `[auto|snap]` / `[auto|brief|snap]`. **Cowork v1.2.0** ports snap with adaptations: namespaced `/aria-cowork:snapshot`, **no Bash dependency** (cowork's 3-path snapshot), terser descriptions to clear the 9000-char summed-description cap (build at 8972; `release.sh` preflight caught a 9143 overage → 2 trim passes — trust the build gate, not a hand count), + fixed a pre-existing `/handoff` Step-7 duplicated-checklist-row bug. **Not ported (tracked-drift):** cowork's `/handoff` model-recommendation rubric (Suggested-next-session + Fable-5 prose); codex/cursor/antigravity all tracked-drift. Also: the dangling **v2.27.2** docs-footer commit (`ffbc47d`) was finally pushed in this arc (it had been committed-but-unpushed despite the footer claiming "pushed"). Prior: plugin-claude-code **v2.27.2** (canonical only — pushed 2026-06-10 in the v2.28.0 arc): **Fable 5 readiness.** Mike's Claude Code default is now Fable 5 (`claude-fable-5[1m]`, 1M context, tier above Opus, $10/$50). Runtime is already model-agnostic (statusline reads `model.display_name`; usage/context hooks are percentage-based), so this was docs-only: `/handoff` + `/help` model-tier prose gained `Fable` as the top tier (de-version lists, effort ladder, advisory notes; rubric/table rows unchanged per minimal-touch); `/statusline` example refreshed to "Fable 5". **v2.27.2 corrected v2.27.1**: window size is NOT the Fable-vs-Opus differentiator (both are 1M) — re-anchored on capability/judgment (Fable for extreme difficulty; Opus 4.8 the default at half the price). plugin-antigravity skill mirror = tracked-drift (carry both 2.27.1 + 2.27.2 framing at next parity pass); cowork/codex/cursor have no model tables. Prior same-day: plugin-claude-code **v2.27.0 RELEASED** (tag + GH release w/ zip; also retro-tagged + GH-released the dangling **v2.26.0** picker version). **ARIA Assist morning-run schedule surfaces in aria-atlas (read-only).** `pm-schedule.sh`/`pm-morning-run.sh` write a global `<pm_digest_dir>/.aria-assist.json` overlay (via new `apm_write_assist_status` jq deep-merge helper in `pm-lib.sh`) — `schedule` section (enabled/time/label) on install/uninstall + `lastRun` per run; aria-atlas reads it for a read-only "Morning run" card (toggle stays aria-side; atlas never shells to `launchctl`). **Fix:** `pm-schedule.sh` octal crash at hours ≥ 08 (`printf '%d'` on leading-zero hour → base-10 `$((10#$HOUR))`; latent at the 07:30 default). **Fix:** removed `/wrapup` token from `/handoff` description (slash-picker pollution). **Test:** revived the `pm-*` repro harness into `plugin-claude-code/tests/` (shipped untested since v2.25.0; 35 assertions). Canonical only; codex/cursor/antigravity stay 2.24.2 tracked-drift (schedule is Bash + macOS launchd). aria-atlas reader/endpoint/card live in the aria-atlas repo (local/unpushed). Prior: 2026-06-06 — plugin-claude-code v2.25.2 (**Superpowers recommended as a `/setup` companion**): new Step 5c detects/recommends [Superpowers](https://github.com/obra/superpowers) as the complementary process-discipline layer to ARIA's knowledge+edit discipline — strongly recommended but optional, no skill gated on it (verified install `superpowers@claude-plugins-official`); + README "Works Well With Superpowers" section. **v2.25.1** (**SessionStart injection trimmed ~11%**, ~588 B / ~147 tok, zero enforcement change): TASK BUDGET branch-gated on statusline-installed (was emitting both exists/not-exists branches every session) + CODEMAP report shows full detail for stale maps only, collapsing current maps to a `+N current` tail. Also `docs/value-analysis.md` evidence-digest refreshed to the current corpus (171 `/prospect` + 68 `/retrospect` logs; two-stream promotion model; corrected cost surface). Canonical port only; codex/cursor/antigravity tracked-drift for a parity pass. Prior: 2026-06-05 — plugin-claude-code v2.24.3 (**runtime-aware statusline account resolution + staleness/scope guards**, ADR-099): shared `kt_resolve_account` (in `config.sh`, byte-mirrored into the standalone-copied meter) keys the usage snapshot by the real **per-user** account under Claude-Desktop hosting — where `~/.claude.json` is the CLI login, not the session account — falling back to `~/.claude.json` for the CLI (v2.24.2 unchanged). Inject hook + SessionStart reader use it too; inject gains 5h/7d `resets_at` staleness + context `session_id`/null guards; `/statusline` wires `refreshInterval:30`; snapshot adds `runtime`/`session_id`/`seven_day_resets_at`; email renders only on the CLI runtime. **Ports:** statusline ships only in plugin-claude-code; **plugin-antigravity is exempt** (targets `~/.gemini/antigravity.json`, no Claude-Desktop hosting), codex/cursor/cowork don't ship the scripts. Resolver live-validated in-session; real-runtime meter/inject check is post-merge. Prior: 2026-06-04 — plugin-claude-code v2.24.2 (per-account statusline usage-state scoping — fixes cross-account false usage alerts by keying the snapshot on `oauthAccount.accountUuid` read from `~/.claude.json`, plus account email as the last status-line segment). Prior same-day: v2.24.1 (statusline model-label trim + am/pm reset clocks). **Cursor port 2.24.2-cursor.0** tracks canonical v2.24.2 (2026-06-04, statusline-only delta — not ported). **Cursor port 2.24.1-cursor.0 SHIPPED** (2026-06-04): full parity pass to canonical v2.24.1 — hooks (`afterFileEdit` auto-prospect, `afterShellExecution` auto-retrospect, `subagentStart`/`subagentStop`), SESSION.md piggyback, config keys; **`port-skills-to-mdc.py` rewritten for full `.mdc` regeneration** (retrospect caught incremental script's silent drift); release `aria-knowledge-cursor-2.24.1.zip`; commit `8bb1fc1` local/unpushed. Prior: 2026-06-01 — plugin-claude-code v2.22.2 (**auto-prospect & auto-retrospect hooks**, Claude Code only, opt-in default off: `post-plan-prospect-check.sh` [PostToolUse:Write] offers/runs `/prospect file <path>` on a plan written to `docs/plans/` or `docs/superpowers/plans/` when `auto_prospect` is `nudge`/`run`; `post-push-retrospect-check.sh` [PostToolUse:Bash] offers/runs `/retrospect range <old>..<new>` on a qualifying `git push` when `auto_retrospect` is `nudge`/`run`; + 4 config keys `auto_prospect`/`auto_retrospect`/`retrospect_min_commits`/`retrospect_branches`; other 4 ports tracked-drift). v2.22.1 (**SESSION.md producer dogfood fixes**: `/wrapup`+`/handoff` Step 1 disambiguates the active project when cwd is a multi-project/workspace root; `SESSION.md` is now gitignored + never committed by the producer). v2.22.0 (**SESSION.md producer**, Claude Code only: `/wrapup` + `/handoff` write a per-project `SESSION.md` across an `in-progress`/`wrapup`/`handoff` lifecycle, gated on the new `session_state` config key [default off, surfaced in `/setup`]; a flag-gated `session-start-check.sh` instruction offers resume [auto-resume on the `handoff` keyword] then light-touch-marks `in-progress`; contract at `aria-atlas/docs/TEMPLATE_SESSION.md`, consumed read-only by aria-atlas; the live-session JSON registry is intentionally not built; other 4 ports tracked-drift, not re-synced). Prior: 2026-05-31 — plugin-claude-code v2.21.0 (**subagent knowledge capture**: new `SubagentStop` archive hook [`bin/subagent-stop-capture.sh`, archives `agent_transcript_path` to `intake/subagent-captures/`, sticky retention] + `SubagentStart` self-report hook [`bin/subagent-start-selfreport.sh`] + 3 `subagent_capture*` config keys + `/audit-knowledge` Step 2e + `/extract` Step 2.5 sweep-all; plus `/wrapup` description picker fix; tag `v2.21.0` + public GH release; validated end-to-end in production; Claude Code only). **All 5 ports synced to 2.24.2 parity** (`origin/main` `7bcdf57` + tags `v2.24.2` / `cowork-v1.1.5`): plugin-claude-cowork v1.1.5, plugin-openai-codex 2.24.2-codex.0, plugin-antigravity 2.24.2, plugin-cursor-template 2.24.2-cursor.0.*
