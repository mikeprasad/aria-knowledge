# Changelog

All notable changes to ARIA will be documented in this file.

## [2.18.0] - 2026-05-18

**First MCP-consuming release. 5 new cross-tool skills + `.mcp.json` + `CONNECTORS.md` + 2 new architectural ADRs.** aria-knowledge gains a category of capability it didn't previously have — pulling from connected MCP servers (Slack, Notion, Linear, Gmail, etc.) and writing structured artifacts back into the knowledge folder. 5 new skills (clip-thread, extract-doc, meeting-notes, digest, sync-decisions) consume 4 `~~category` placeholders (chat / email / project tracker / docs) via the `~~` customization-marker convention from `cowork-plugin-management`. Minor bump because this is a structural-shift-by-addition: the manifest's new `.mcp.json` declaration is additive (existing installs without `.mcp.json` continue to work), but a whole external-integration surface arrives. Bidirectional flow continues — aria-cowork v1.0.0 ships shortly with 5/5 of these skills imported byte-faithfully + 1 cowork-only `daily-audit` skill per ADR-014.

### Added — `/clip-thread` skill

New skill at `plugin/skills/clip-thread/SKILL.md`. Captures a chat or email thread from a connected `~~chat` (slack, ms365) or `~~email` (gmail, ms365) MCP into `intake/clippings/{YYYY-MM-DD}-{slug}.md`. Source-type detection by URL pattern (Slack archives, Teams message links, Gmail thread IDs, MS365 message IDs). 50-message cap with truncation notice. Per-message structure preserves author + timestamp + body + reactions/attachments-noted. Reaction section left empty as user-fill slot (matches `/intake doc` precedent from v2.17.0).

### Added — `/extract-doc` skill

New skill at `plugin/skills/extract-doc/SKILL.md`. Pulls insights from a single Notion / Confluence / Google Doc / Box / Egnyte page via `~~docs` MCP. **Differs from `/intake doc`** (v2.17.0): `/intake doc` captures one structured artifact per doc; `/extract-doc` decomposes a doc into N intake-backlog entries for audit routing. 5 standard intake categories (insight / decision / extraction / idea / reference). 20KB extraction cap with truncation notice. Default fewer-but-stronger ranking discipline.

### Added — `/meeting-notes` skill

New skill at `plugin/skills/meeting-notes/SKILL.md`. Folds a meeting transcript into `intake/meetings/{YYYY-MM-DD}-{slug}.md` with structured participants / topics / action items / decisions / open questions sections + raw transcript preserved verbatim. **Unique among Phase 2 skills:** offers a **paste fallback** when no `~~docs` MCP is connected (Granola exports, hand-typed notes, transcript paste-from-clipboard). The only skill in v2.18.0 that doesn't hard-stop on missing MCP. New `intake/meetings/` lazy-created subfolder convention.

### Added — `/digest` skill

New skill at `plugin/skills/digest/SKILL.md`. Cross-tool rollup synthesizing what's pending / what shipped / what's blocked across `~~chat` + `~~email` + `~~project tracker` + `~~docs`. The composite-MCP skill — probes all 4 categories and degrades gracefully when partial connection (surfaces gap callouts in output). Time window args: `--week` (default), `--month`, `--quarter`, `--since YYYY-MM-DD [--until YYYY-MM-DD]`. Output to `intake/digests/{YYYY-MM-DD}.md` (lazy-created subfolder). Inspired by Anthropic's productivity plugin `update --comprehensive` mode, adapted for ARIA's intake-then-audit model.

### Added — `/sync-decisions` skill

New skill at `plugin/skills/sync-decisions/SKILL.md`. **First WRITE-side skill in ARIA.** Mirrors approved decisions from `{knowledge_folder}/decisions/` out to a `~~docs` MCP destination (Notion page, Confluence space, Google Doc, Box/Egnyte file). Embeds the 4-step Rule 22 advisory preamble per ADR-016 with explicit per-decision go-gate (`Ready to write? (yes / no / edit)`). The only path to batch is the literal phrase `yes to all` per ADR-016's batch carve-out. Logs every sync attempt (success / skip / fail) to `logs/sync-decisions.md`. Adds new `synced_to_~~docs:` frontmatter field on synced decision files for sync-state tracking.

### Added — `plugin/.mcp.json`

First time aria-knowledge ships an `.mcp.json` manifest. Declares 12 MCP servers across 4 categories — mirrors Anthropic's published `productivity/.mcp.json` shape:

| Category | MCPs declared |
|---|---|
| Chat | slack, ms365 |
| Email | gmail (placeholder URL), ms365 |
| Project tracker | linear, asana, atlassian, monday, clickup, notion |
| Docs | notion, atlassian, box, egnyte, google_docs (placeholder URL) |

Slack ships with Anthropic's published OAuth config (clientId `1601185624273.8899143856786`, callbackPort 3118) — mirrored from productivity's manifest. Gmail + google_docs ship with empty URLs (placeholder declarations per productivity's pattern, pending public MCP server availability).

### Added — `plugin/CONNECTORS.md`

First time aria-knowledge ships a `CONNECTORS.md`. Documents the `~~category` marker convention per the canonical guidance from `cowork-plugin-management/skills/cowork-plugin-customizer/SKILL.md`. Four categories (chat / email / project tracker / docs) — a focused subset of productivity's 6 (we don't have calendar or office-suite skills). Per-skill MCP-usage table shows which `~~category` each new skill consumes + the fallback behavior. "What this plugin does NOT integrate with" section preempts confusion about calendar / office-suite / code-hosting omissions.

### Added — ADR-015 + ADR-016 (in `~/Projects/knowledge/projects/aria-cowork/decisions/`)

Two new ADRs lock the v2.18.0 design decisions:

- **ADR-015 — Capability-Probe Pattern (Prose-Only, No API).** Locks the `~~category` probe convention verified against productivity plugin reference: prose-only, no helper script, Claude's runtime tool list IS the probe, SKILL.md handles missing-MCP via explicit fallback prose. Composes with ADR-004 (no hooks in cowork) — Layer-1 + Layer-3 only.
- **ADR-016 — Rule 22 Advisory Preamble for External-Write Skills.** Locks the 4-step preamble + explicit `Ready to write? (yes / no / edit)` go-gate that all WRITE-side skills MUST embed. Applies to `sync-decisions` in v2.18.0; pattern is durable for future write-side skills. Composes with ADR-004 + v0.2.5 "Principles transfer, enforcement doesn't" framing.

Both ADRs include a **Stability and revision triggers** section acknowledging that the patterns derive from Anthropic-published Cowork plugins as of 2026-05-18 and may revise as future Anthropic releases ship new capability surfaces (formal capability-probe APIs, Cowork hook surface for MCP write tools, etc.).

### Schema impact

| Surface | Change | Compatibility |
|---|---|---|
| `plugin/.mcp.json` | New file declaring 12 MCP servers | Additive — installs without `.mcp.json` continue to work (existing skills don't probe MCPs) |
| `plugin/CONNECTORS.md` | New companion doc explaining `~~` markers | Additive — documentation only |
| `intake/clippings/` | Existing folder, new content shape (`<date>-<slug>.md` with thread structure) | Additive — `/clip-thread` writes alongside `/clip` outputs; no shape conflict |
| `intake/meetings/` | New subfolder, lazy-created | Additive — created on first `/meeting-notes` invocation |
| `intake/digests/` | New subfolder, lazy-created | Additive — created on first `/digest` invocation |
| `logs/sync-decisions.md` | New artifact, lazy-created | Additive — created on first `/sync-decisions` invocation |
| `synced_to_~~docs:` frontmatter field on decision files | New optional field | Additive — decisions without the field still work; `/audit-knowledge` ignores the field for routing |

### Cross-plugin parity (bidirectional flow continuing per ADR-014)

5/5 new skills are bidirectional per [ADR-014](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/014-bidirectional-feature-flow.md) row 3 — the cross-tool workflow problem exists in both Code and Cowork surfaces. Per ADR-013 (schema-source-of-truth), aria-knowledge ships first; aria-cowork v1.0.0 imports the 5 SKILL.md bodies byte-faithfully with only the Step 0 config-resolution path diverging per ADR-013's "input-discovery diverges per-surface; output-schema converges per-corpus" principle.

aria-cowork v1.0.0 also adds 1 cowork-only skill (`daily-audit` — first-message audit substitute since Cowork has no SessionStart hook per ADR-004). That skill does NOT ship in aria-knowledge.

Output schema is byte-identical across plugins per ADR-013. Both plugins write to the same shared `intake/clippings/`, `intake/meetings/`, `intake/digests/`, `logs/sync-decisions.md` paths in the user's `~/Projects/knowledge/` (or configured) folder.

### Files changed

- New: `plugin/.mcp.json` (~50 lines, 12 MCP server declarations)
- New: `plugin/CONNECTORS.md` (~80 lines, ~~category convention reference)
- New: `plugin/skills/clip-thread/SKILL.md` (~155 lines)
- New: `plugin/skills/extract-doc/SKILL.md` (~145 lines)
- New: `plugin/skills/meeting-notes/SKILL.md` (~170 lines)
- New: `plugin/skills/digest/SKILL.md` (~180 lines)
- New: `plugin/skills/sync-decisions/SKILL.md` (~200 lines, Rule 22 preamble embedded)
- Modified: `plugin/.claude-plugin/plugin.json` (version bump 2.17.0 → 2.18.0)
- Modified: `README.md` (skill list additions in Capture + Promote sections, MCP integration mention in Install)
- Modified: `CLAUDE.md` (Sibling Plugin section refreshed for v0.3.0 → v1.0.0 SHIPPED on disk; originally drafted as v0.4.0 + bumped to v1.0.0 mid-build per ADR-006 stability claim)
- Cross-knowledge: `~/Projects/knowledge/projects/aria-cowork/decisions/015-capability-probe-pattern.md` + `016-rule-22-advisory-preamble-for-external-writes.md` (new ADRs)

### Compatibility

- **No breaking changes.** Existing skills work unchanged. New skills are opt-in by invocation; no auto-fire hooks reference the new skills.
- **No new required config.** Existing `aria-knowledge.local.md` works unchanged. Future `default_sync_target:` field is optional (consumed only by `/sync-decisions`).
- **No new dependencies.** Pure markdown + the MCP runtime that Code already provides. `.mcp.json` is read by Code's MCP client; aria-knowledge doesn't build or host any MCP server itself.
- **Graceful degradation built-in.** If no MCPs are connected, all 5 new skills output a clear fallback notice and stop. `/meeting-notes` additionally offers a paste-fallback path.
- **MCP-consuming is opt-in.** Users who don't want any of the 5 new skills can ignore them; no behavior changes to the existing 23 skills.
- **Cowork sibling release coming:** aria-cowork v1.0.0 ships shortly with 5/5 bidirectional ports + the cowork-only `/daily-audit`.

### Known limitations

- **Slack OAuth clientId** is mirrored from productivity plugin's public manifest. May "just work" if Anthropic's Slack OAuth app covers third-party plugins; may require aria-knowledge to register its own Slack OAuth app if reality differs. Capability probe per ADR-015 will surface "No `~~chat` MCP connected" if Slack auth fails — degraded but not broken.
- **`gmail` and `google_docs` MCPs ship with empty URLs** (placeholders, per productivity plugin's pattern). Will be populated when Anthropic's hosted Google MCPs go public. Patchable in v2.18.1 if/when that lands.
- **Probe semantics may evolve.** ADR-015 + ADR-016 explicitly note that future Anthropic releases (formal capability-probe API, Cowork MCP-aware PreToolUse hook) would trigger revision.

## [2.17.0] - 2026-05-18

**Two new mode flags on existing skills: `/handoff brief` + `/intake doc`.** Both originate as cross-plugin parity items from aria-cowork's v0.3.0 design discussion — this release implements them in aria-knowledge first (per the schema-source-of-truth principle), so aria-cowork's v0.3.0 port can import the templates byte-identical. Minor bump because of the new `intake/docs/` subfolder convention + new `intake-doc` frontmatter type — additive schema, no breaking changes.

### Added — `/handoff brief` mode

New mode flag on the existing `/handoff` skill: `/handoff brief` produces a copy/paste coworker brief (Hey [coworker]-style prose, 80-150 words, capped at 200) instead of the default mode's next-session opener. Different artifact, different audience — brief mode is for handing off to a person, not to a future session.

- **No side effects.** Unlike default and `auto` modes, `brief` skips PROGRESS.md / CLAUDE.md / memory / commit / `/extract` entirely. The brief is the only artifact.
- **`[coworker]` is a literal placeholder.** Users fill the recipient name at paste time — supports "send to multiple people" use cases without forcing an upfront prompt.
- **Sections:** "What happened" / "Key decisions" / "What's next" / "Where to pick up" (last line omitted if no concrete artifact reference applies).
- **Tone:** warm-but-professional default. No `casual` / `formal` variants in v2.17.0 (deferred unless demand emerges).
- **Users who want both:** run `/handoff brief` first, then `/handoff` (or `/handoff auto`) for the state-updating pass. Two invocations, two artifacts.

### Added — `/intake doc` mode

New mode flag on the existing `/intake` skill: `/intake doc <url-or-title-or-path>` captures a single doc with a structured 5-section body (claims / worth keeping / contested / action / reaction) instead of bulk scanning multiple sources.

- **New subfolder convention:** `{knowledge_folder}/intake/docs/{YYYY-MM-DD}-{slug}.md`. Lazy-created on first doc-mode capture (not bootstrapped on `/setup`).
- **New frontmatter type:** `type: intake-doc` plus `source_url` (optional), `source_title`, `source_author` (optional), `captured_at`, `read_at` (separate from `captured_at` so users can capture notes days after reading), `tags`, `semantic-hints`.
- **Body sections (D3 step):**
  - **What the doc claims** — central thesis or key argument in your own words
  - **Worth keeping** — durable insights / quotes / data points (2-6 bullets typical)
  - **Contested or unclear** — populated if scan surfaced debatable claims; omitted otherwise
  - **Action implied** — populated if doc suggests a decision or next step; omitted otherwise
  - **My reaction** — left as user-fill placeholder (the user's voice, not Claude's)
- **Source types accepted:** URL (WebFetch), file path (Read), or title-only (user fills body manually — valid use case for "notes while reading something offline").
- **Slug generation:** lowercased, hyphenated, max ~60 chars from source title. Collision handling: append `-2`, `-3` etc. if `{date}-{slug}.md` already exists.
- **Preview before write (D4 step):** populated entry shown for user confirmation; per-section `edit` directives allowed.

### Added — `plugin/template/intake/intake-doc.md`

New plugin-managed template defining the 5-section body structure. Read by `/intake doc` Step D3 when populating new doc-mode captures. Single new file (~42 lines).

### Changed — `plugin/skills/handoff/SKILL.md`

- Frontmatter `argument-hint`: `[auto]` → `[auto|brief]`; `description` updated to introduce three modes
- Step 0 mode parser: added `brief` branch; error message updated to mention all three modes
- New Step 2B (Brief Output): runs only when `mode = brief`; emits the prose brief via the locked template; exits without running Steps 3-8
- Rules section: scoped existing rules (e.g., "always emit next-session opener" qualified to default + auto only); added 3 brief-mode-specific rules (no side effects, literal placeholder, 200-word cap)

### Changed — `plugin/skills/intake/SKILL.md`

- Frontmatter `argument-hint`: `<path|directory|glob|url> [path2] [path3]` → `[doc <url-or-title>] | <path|directory|glob|url> [path2] [path3]`; `description` updated to introduce both modes
- Step 0 renamed to "Resolve Config + Mode Detection"; doc-mode branch added at end of Step 0
- New Doc Mode Steps section (D1-D6) inserted before existing Step 1; runs to completion + exits when `mode = doc`
- Rules section: scoped existing rules to bulk vs doc mode; added 4 doc-mode-specific rules (reaction-is-user-voice, lazy subfolder creation, slug collisions, title-only captures valid)

### Changed — `plugin/skills/help/SKILL.md`

- Existing `/handoff` row updated: `[auto]` → `[auto|brief]` with brief mode description appended
- New `/intake doc [url or title]` row added below existing `/intake` row, naming the 5-section body and `intake/docs/` destination

### Schema impact

| Surface | Change | Compatibility |
|---|---|---|
| `intake/docs/` subfolder | New, lazy-created on first doc-mode capture | Additive — no impact on existing intake folders |
| `type: intake-doc` frontmatter value | New value | Additive — `/audit-knowledge` routes intake-doc files through same disposition flow as other intake entries |
| `source_url` / `source_title` / `source_author` / `read_at` frontmatter fields | New optional fields on doc-mode captures | Additive — no impact on other knowledge file types |

### Cross-plugin parity (bidirectional flow precedent)

Both modes originated in aria-cowork's v0.3.0 design discussion as B2 + B5 candidates. This release is the **first instance of cowork→aria-knowledge feature flow** — features conceived in cowork's context, designed cross-plugin, shipped in aria-knowledge first (schema source-of-truth) so aria-cowork's port can import the resulting templates byte-identical. Pattern documented in aria-cowork ADR 014.

The plugin-codex/ port mirrors the same skill body + template changes per the Codex Port Workflow ("keep durable knowledge template/schema changes in sync with `plugin/` — Claude remains the schema standard").

### Files changed

- New: `plugin/template/intake/intake-doc.md` (42 lines)
- Modified: `plugin/skills/handoff/SKILL.md` (195 → 260 lines, +65)
- Modified: `plugin/skills/intake/SKILL.md` (177 → 271 lines, +94)
- Modified: `plugin/skills/help/SKILL.md` (59 → 60 lines, +1)
- Modified: `plugin/.claude-plugin/plugin.json` (version bump 2.16.1 → 2.17.0)
- Modified: `CLAUDE.md` (bidirectional flow note added per aria-cowork ADR 014)
- Mirrored: same changes in `plugin-codex/skills/{handoff,intake,help}/SKILL.md` + `plugin-codex/template/intake/intake-doc.md`

### Compatibility

- **No breaking changes.** Existing `/handoff` and `/intake` invocations work exactly as before. New modes are additive flags.
- **No new config schema.** Existing `aria-knowledge.local.md` works unchanged.
- **No new dependencies.** Pure markdown + WebFetch (already in /intake's `allowed-tools`).
- **Cowork sibling release coming:** aria-cowork v0.3.0 will land shortly with the doc-mode + brief-mode ports plus a much larger parity catch-up arc.

## [2.16.1] - 2026-05-14

**Full session-lifecycle CODEMAP/STITCH awareness.** Completes v2.16.0's surfacing story — passive `/context` surfacing (v2.16.0) + proactive trigger-based loading (v2.16.1). 6 trigger sites + 4 companion surfaces share the same primitive and config flag. Patch bump — no new schema, no new dependencies; reuses the existing `active_knowledge_surfacing` flag for atomic toggling.

### Added — Trigger-based CODEMAP + STITCH loading (6 sites)

- **New shared lib** `plugin/bin/lib-tracked-artifacts.sh` — boundary-detected CODEMAP directory load (~600-1200 tokens) + full STITCH load (~4K tokens) when multi-repo. Reuses the existing `/tmp/aria-active-{session_id}` ledger from v2.15.0 for cross-trigger dedup.
- **T-1 `bash-cd-check.sh`** (PreToolUse:Bash with cd) — surfaces tracked artifacts on first cd into a configured project per session, alongside knowledge-file surfacing. Restructured to compute-both-then-decide pattern.
- **T-2 `session-start-check.sh`** (SessionStart) — surfaces tracked artifacts when `$PWD` substring-matches a `projects_list` entry. Complementary to the existing multi-project CODEMAP staleness reporter; non-interfering.
- **T-3 `task-context-check.sh`** (TaskCreated) — surfaces tracked artifacts for the project containing `$PWD` at subagent-spawn time, giving subagents structural context.
- **T-4 `post-compact-check.sh`** (PostCompact) — auto-covered via the shared ledger; tracked-artifact paths recorded by T-1/T-2/T-3 are re-surfaced after compaction with zero code changes.
- **T-5 `/prospect` Step 0.5** — extended with Step 11 detecting the plan's project (`--group=<tag>` → Linear prefix → plan-path match) and loading CODEMAP directory + STITCH.
- **T-6 `/retrospect` Step 0.5** — extended with Step 11 detecting the analyzed range's project via `git diff --name-only` majority-file-path match against `projects_list`.

### Added — Companion surfaces (S-3, S-4, S-7)

- **`/audit-config` Step 5a** — cadence-based tracked-artifact staleness audit. Classifies CODEMAP/STITCH into Critical (refusal zone, >2× threshold) / Should Fix (>threshold) / Low Priority (missing) / Healthy. Feeds existing 4-tier findings table without schema change.
- **`/stats` Step 3b + presentation** — cross-project dashboard view of CODEMAP + STITCH freshness across all `projects_list` entries. New "Cross-Project Tracked Artifacts" section in Step 6 template. Pairs with cwd-focused Step 3a (kept as-is).
- **`/handoff` + `/wrapup` Step 7 checklists** — added "Tracked artifacts" line to handoff-readiness checklist. Visibility-only; doesn't block at session end.

### Config flag scope expansion

- **`active_knowledge_surfacing`** (existing, default `true`) now ALSO gates CODEMAP/STITCH loading at all 6 trigger sites + skips companion surfacing when `false`. Single atomic toggle for the entire proactive-surfacing capability — no new flag bloat.
- **`/setup`** Advanced Options help text updated to describe the expanded scope.
- **`CONFIG.md`** consumers table row updated.

### Load model

- **CODEMAP**: directory section only (boundary-detected via `awk '/^## [0-9]+\.|^---$/ && NR>5'`; fallback `limit=50`). ~600-1200 tokens per project; never the full 1790-line CODEMAP.
- **STITCH**: full file (~4K tokens; typical 188-200 lines). Loads only when `STITCH.md` exists (multi-repo signal).
- **Staleness thresholds** (from v2.16.0): `codemap_staleness_threshold_days` (14), `stitch_staleness_threshold_days` (30). Grossly-stale (>2× threshold) refuses to load with warning.
- **User-facing output**: every load fires `[aria] Loaded {artifact} for {project} ({N days fresh|STALE|REFUSED})` notification. No silent context injection.

### Files

- **New:** `plugin/bin/lib-tracked-artifacts.sh` (~180 LOC).
- **Modified:** 3 hooks (`bash-cd-check.sh`, `session-start-check.sh`, `task-context-check.sh`), 6 skills (`/prospect`, `/retrospect`, `/audit-config`, `/stats`, `/handoff`, `/wrapup`, `/setup`), 1 docs (`CONFIG.md`).

### Compatibility

- **No breaking changes.** All v2.16.1 behavior gated by `active_knowledge_surfacing: true` (existing default-on flag); passive-mode users see no new behavior.
- **No new dependencies.** Pure markdown + sh extensions.
- **No new config schema.** Reuses v2.16.0's `codemap_staleness_threshold_days` + `stitch_staleness_threshold_days`.
- **`pre-explore-codemap-check.sh`** (PreToolUse:Glob|Grep) **deliberately not extended** in v2.16.1 — existing CODEMAP nudge surface kept independent for scope discipline; v2.16.2+ enhancement candidate.

## [2.16.0] - 2026-05-13

**Five additive items: staleness gap close, vocabulary primitives, ecosystem doc.** Closes the CODEMAP/STITCH surfacing gap in `/context`; introduces two new optional frontmatter primitives (`semantic-hints` + tag aliases via `aliases.md`); refactors staleness logic into a shared block; adds the ARIA family section to the README. Minor bump — no breaking changes; existing knowledge folders work unchanged.

### Added

- **`/context` surfaces CODEMAP and STITCH artifacts** for queried projects with staleness markers (`[STALE — run /codemap update]`, etc.). Project-tag-gated; topic-only queries unaffected. (P-1, ADR 081)
- **`semantic-hints:` optional frontmatter field** — list of free-form phrases that match query tokens via substring (case-insensitive, hyphen-normalized). Indexed under new `## Semantic Hints Index` section of `index.md`. (P-4)
- **Tag aliases via `aliases.md`** — user-edited synonym map (`` `rn` → `react-native` ``). `/context` resolves alias queries to canonical tags before matching. Validates chains + collisions at `/index` time with user-actionable error messages. (P-13)
- **Shared staleness-marker block** in `/context` Step 5 — pure state-computation primitive (age + stale marker). Consumed by Pending Ideas and Tracked Artifacts. (P-2, ADR 082)
- **"ARIA family" section** in README documenting sibling projects and license posture. aria-cowork mentioned conceptually (public release planned); aria-hypergraph held out per privacy. (P-16)
- **`/stats` semantic-hints coverage line** — adoption signal showing `N of M files (P%)` declaring hints.

### Config

- New optional keys in `~/.claude/aria-knowledge.local.md` (defaults baked into `bin/config.sh` for graceful degradation when absent):
  - `codemap_staleness_threshold_days: 14` — CODEMAP age before flagged stale
  - `stitch_staleness_threshold_days: 30` — STITCH age before flagged stale (slower decay because cross-repo contracts change less often)

### Templates

- **New user-owned template:** `aliases.md` — bootstrapped on first `/setup`, never overwritten, never diffed.

### Skills affected

`/context` (5 changes: shared block, Pending Ideas refactor, Tracked Artifacts surfacing, semantic-hints matching, alias Step 2.5 + display), `/index` (3 changes: hints parse, aliases Step 2b + Step 9 annotation), `/ask` (2 changes: hints + alias resolution at Step 2), `/setup` (5 changes: 4 declarative-list updates + new template bootstrap), `/stats` (2 changes: extraction + output template).

### Compatibility

- **No breaking changes.** Files without `semantic-hints:` or aliases.md behave identically to v2.15.x. Existing knowledge folders work without modification.
- **Byte-identical refactor guarantee** for Pending Ideas rendering — verified via pre/post capture-diff at implementation time.
- **Graceful degradation** for missing config keys: `bin/config.sh` defaults apply silently if `codemap_staleness_threshold_days` / `stitch_staleness_threshold_days` are absent from existing configs.

## [2.15.2] - 2026-05-13

**Three quality-of-life arcs bundled.** Generalizes v2.15.1's archive-don't-delete rule to all known deletion call-sites; structural fix for Rule 22 marker enforcement under tool-call-interleaved transcripts; defense-in-depth against `/setup` discipline failures. Patch bump — no new features, only safety + correctness fixes.

### Arc 1 — Comprehensive delete-call-site audit

Generalizes v2.15.1's archive-don't-delete rule beyond `/audit-knowledge` Phase 2c2's ideas-routing. Investigation grep across all `plugin/skills/*/SKILL.md` + `plugin/bin/*.sh` classified each deletion site as compliant / needs-ledger / needs-archive / out-of-scope.

- **`/audit-knowledge` Step 2d (pre-compact snapshots)** — Clear / Approved / Rejected branches no longer `rm` snapshot files. Apply the **ledger-clear pattern**: write `{knowledge_folder}/archive/audit-{date}/pre-compact-captures/REMOVED.md` with frontmatter (`audit_date`, `removed_count`, `canonical_source_pattern`) + per-snapshot list (filename + session-id + capture-timestamp + canonical-jsonl-pointer), then remove snapshot bodies. Bodies are *derived copies* of Claude Code's per-session transcript log; canonical preservation lives at `~/.claude/projects/{cwd-encoded}/{session-id}.jsonl` until Claude Code rotates the log. Ledger pattern chosen over full archive because snapshots are large (100KB-1MB each) and the canonical source exists elsewhere.
- **`/audit-knowledge` Step 5e (cross-project pattern Remove)** — doc clarification: this is already verify-no-loss-compliant (source moves to cross-project file with `originally_at:` frontmatter providing audit trail). Added `(v2.15.2 note: ...)` inline comment so the compliance is explicit for future readers. No behavior change.
- **`/backlog clear`** — destructive "remove entries" replaced with **archive-then-remove pattern**: matching entries are copied to `{knowledge_folder}/archive/backlog-cleared-{type}-{YYYY-MM-DD-HHmmss}.md` with frontmatter metadata (`archived_at`, `source_backlog`, `cleared_through_date`, `entry_count`, `reason: /backlog clear user-invoked`) before removal from the live backlog. Full archive (not ledger) because backlog entries are user-authored content with no canonical source elsewhere. Skill's `allowed-tools` extended to include `Write` (was `Read, Edit, Grep`).
- **User-override clause for all three never-delete sites** — Step 2c2 (ideas, inherited from v2.15.1), Step 2d (snapshots, new), `/backlog clear` (new) all gain an explicit-user-override escape hatch. If the user explicitly approves or asks for a deletion that skips archive/ledger (phrases like *"delete without archiving"*, *"really delete this"*, *"skip the archive"*), the destructive operation is permitted. Default safety floor remains archive-on-disk; override is one-off per invocation (does not flip default for subsequent files); requires surfacing what would have been preserved before confirming. Legitimate use cases: sensitive content the user doesn't want traceable, archive-growth aversion, test/spam entries that don't deserve archive space.
- Out-of-scope sites (no spec change): all `rm` calls in `bin/*.sh` operate on temp files (`/tmp/aria-match-*`) or ephemeral runtime state (`active-batch.json`); descriptive "delete"/"remove" mentions in handoff/codemap/wrapup/snapshot are session-summary fields, not deletion calls.

### Arc 2 — Marker-window structural fix (`bin/pre-edit-check.sh`)

Rule 22's marker-detection walker in `pre-edit-check.sh` stopped at any `type: "user"` message going backward through the transcript. But Claude Code encodes tool_results as `type: "user"` messages too — so a `[Rule 22]` marker emitted in an assistant text block, followed by a Bash/Read tool call, followed by an Edit/Write, hit the tool_result boundary and the marker became invisible. Result: false-deny on the Edit/Write, requiring re-emit of the marker.

The fix: distinguish actual user prompts from tool_results via a conservative `all()` heuristic — if the user-typed message's content blocks are ALL `tool_result` blocks, walk past (it's a tool result, not a real user message); if any non-tool_result content exists, treat as a real user turn boundary. 6-line addition to the Python walker.

**Risk profile**: low. Heuristic uses `all()` so any mixed-content message stops the walker (conservative — avoids false-allow). Fail-open behavior preserved on any parse error. Worst case under future Claude Code transcript-format changes: hook denies, same workaround as today (re-emit marker).

### Arc 3 — `/setup` discipline hardening (3 sub-items, defense-in-depth)

- **3a — `/setup` Step 7e (Self-Validation Audit)** — after Step 7b's round-trip verification, enumerate known fields from `bin/config.sh`'s grep patterns, scan user's config for each, surface missing-fields list with defaults, prompt `(y/n/select)` to add. Catches the failure mode where `/setup` Step 6's Advanced Options bundle silently skipped surfacing a new field (the `active_knowledge_surfacing` gap that surfaced this arc).
- **3b — `/audit-config` Step 3b (Missing-Known-Fields Cascade)** — same check as 3a but runs at config-audit cadence (default 14 days). Catches gaps that escaped `/setup`'s self-validation — defense-in-depth at audit cadence. Reports missing fields under **Should Fix** with field name + default value + recommended action.
- **3c — [NEW]-detection observability** — before showing Step 6's Advanced Options bundle, emit a transcript-visible one-liner naming the detection result: flagged-N-keys / none / fresh-install-skipped. Makes the [NEW]-detection step observable so users can verify it ran instead of silently skipping.

### Changed — `bin/pre-edit-check.sh`

Python walker: 6-line addition distinguishing tool_results from actual user prompts.

### Changed — `plugin/skills/audit-knowledge/SKILL.md`

Step 2d (Clear / Approved / Rejected) — ledger-clear pattern. Step 5e Remove — doc-only clarification. New ### Ledger schema subsection at end of Step 2d.

### Changed — `plugin/skills/backlog/SKILL.md`

Step 4 (Clear) — archive-then-remove pattern. `allowed-tools` frontmatter: `Read, Edit, Grep` → `Read, Edit, Write, Grep`.

### Changed — `plugin/skills/setup/SKILL.md`

Step 6 Advanced Options — [NEW]-detection observability emit-summary paragraph added after the existing detection-mechanism sentence. New Step 7e (Self-Validation Audit) inserted between Step 7d and Step 8.

### Changed — `plugin/skills/audit-config/SKILL.md`

New Step 3b (Missing-Known-Fields Cascade) inserted between Step 3a and Step 4.

### Out of scope (deferred)

- Backfill of historical destructive audits (e.g., the 2026-05-13 parallel-session incident from v2.15.1's Origin) is handled per-incident by the operator.
- Pre-compact snapshot retention TTL (when Claude Code rotates jsonl) is not addressed — users who need belt-and-suspenders retention can set up their own backup tooling for `~/.claude/projects/`.

### Origin

Three independent threads converged in this release:

1. **Comprehensive delete-call-site audit** — v2.15.1 fixed ideas-routing but left other deletion sites under the old "git history will preserve it" assumption. A grep across the plugin surfaced two more sites needing the new rule (Step 2d snapshots, `/backlog clear`) plus one already-compliant site needing only doc clarification (Step 5e). User asked: "lets do all of them in the same release."
2. **Marker-window discovery** — encountered live during v2.15.1's session: writing the retrospect log triggered a false-deny because the `[Rule 22]` marker became invisible past an intervening Bash call. Documented as a novel failure mode in `logs/retrospect/2026-05-13-session-active-knowledge-surfacing-v2150.md` §9 row 6.
3. **`/setup` discipline failure** — user's parallel `/setup` run on v2.15.1-installed plugin did NOT surface the new `active_knowledge_surfacing` field as `[NEW]` in the Advanced Options bundle, despite v2.15.1's setup SKILL.md correctly containing the bullet. Diagnosis: Step 6's [NEW] detection is a soft instruction to Claude, not hook-enforced; the wizard skipped it. v2.15.2's defense-in-depth approach (Step 7e + Step 3b + observability) ensures detection failures are caught at three different moments.

## [2.15.1] - 2026-05-13

**`/audit-knowledge` Phase 2c2 — never delete; archive instead.** Closes a destructive failure mode in the ideas-routing flow: prior versions assumed `git log --all -- intake/ideas/` would recover idea bodies after Phase 2c2 deletion, but that assumption silently fails for any idea file created since the last git commit (untracked files have no history). Patch bump because the change is a safety fix on existing behavior, not a new feature surface.

### Changed — `plugin/skills/audit-knowledge/SKILL.md` Step 2c2

Three coordinated edits replace "delete after routing" with "move-or-archive, never delete":

1. **Disposition list rewritten** — Accept / Reject / Reclassify no longer delete the idea file. Accept moves to destination (full-body preservation) OR to `archive/audit-{date}/` (summary-only destinations, with `demoted-to:` frontmatter). Reject moves to archive with `dismissal-reason:` frontmatter. Reclassify moves to archive with `reclassified-to:` frontmatter. Defer unchanged (no-op).
2. **Verify-no-loss check added** — before any Accept disposition's move-to-destination is executed, the audit inventories the original idea's substantive content ({Why, Motivation, Implementation, Source}) against the planned destination's coverage. Three outcomes: full coverage → move to destination; insufficient coverage → archive alongside; partial coverage → surface options to user. Edits/revisions during move are explicitly permitted — the rule is "no useful substantive content is lost," not "body byte-identical."
3. **Archive-folder canonical-preservation semantics + MANIFEST.md spec** — `archive/audit-{date}/` is the new canonical preservation surface; git tracking no longer assumed. Per-audit `MANIFEST.md` captures the cohort (touched, moved, archived-by-reason) as a human-readable counterpart to the audit log.
4. **Bundle row updated** — source idea files in a bundle disposition move to archive with `bundled-into:` frontmatter (not deleted). Verify-no-loss runs on the merged file's destination, not per-source individually.

### Why this matters (non-git users)

Prior versions effectively required users to commit `intake/ideas/` before every `/audit-knowledge` run. Users who don't keep their knowledge folder under git (a valid configuration) had no preservation guarantee — Phase 2c2's delete was destructive without recourse. v2.15.1 makes archive-on-disk the universal preservation surface, with non-git knowledge folders first-class.

### Out of scope (deferred to future patch)

- `/audit-knowledge` Step 2d (pre-compact captures) and other deletion points in other skills are NOT yet rewritten under the new rule. They use separate semantics (transcript snapshots are auto-generated, larger, and their substance is the conversation — already persisted in Claude Code's own transcript log). A v2.15.x audit of all delete-call-sites across the plugin is queued for follow-up.
- Backfill of historical destructive audits (e.g., the 2026-05-13 parallel-session incident that surfaced this bug) is handled per-incident by the operator, not by this skill's spec.

### Origin

A parallel `/audit-knowledge` session on 2026-05-13 deleted 36 idea files whose bodies were never in git history (untracked working-tree files). The user surfaced the destructive damage mid-session; recovery surfaces (Trash, APFS snapshots, Time Machine, VS Code local history) were all exhausted, confirming the bodies were permanently lost. Three iterations of design discussion converged on: never delete; verify substantive coverage before claiming move-preservation is sufficient; archive on insufficient coverage. The shape of the spec change captures all three: dispositions move-or-archive, Accept gates through verify-no-loss, archive folder is the universal preservation surface.

## [2.15.0] - 2026-05-13

**Active Knowledge Surfacing.** New `active_knowledge_surfacing: true` config field (default `true` per D4 of the design discussion) that promotes ARIA's apply pillar from passive (hook suggests `/context`, user types it) to active (hook + skill instructs Claude to autonomously Read matched files, then summarize what loaded before answering). Four hook trigger sites (SessionStart, TaskCreated, PreToolUse:Bash with cd-pattern matching, PostCompact) plus two skill trigger sites (`/prospect` and `/retrospect` via new Step 0.5). Honors a session-scoped dedup ledger at `/tmp/aria-active-{session_id}` so files surfaced by one trigger aren't re-Read by another within the same session. Cleared on SessionStart per the fresh-per-session decision; cross-session continuity comes from PostCompact's re-surface block, not from a persistent ledger. Minor bump (not patch) because the default-true posture is a posture flip, not just an additive knob — existing users upgrading to 2.15.0 will see autonomous Read calls on first session-start.

### Added — `bin/lib-index-match.sh`

New shared shell helper exporting `kt_index_match`, `kt_match_cleanup`, `kt_match_filter_ledger`, and `kt_match_record_ledger`. Refactored out of the inline matcher previously living in `task-context-check.sh` (lines 55-99 of v2.14.4). Single source of truth for the tokenize → match → file-collection → ledger pipeline; called by 3 of the 4 hooks (TaskCreated, Bash-cd, PostCompact reads but doesn't re-match). The two skills do Claude-driven matching via Read on `index.md` rather than shelling out, because skills run inside Claude where `${CLAUDE_PLUGIN_ROOT}` isn't reachable. Preserves the existing ≥2-tag-match threshold and 5-file emission cap as policy constants — changing them is a deliberate cross-cutting decision, not a per-caller knob.

### Added — `bin/bash-cd-check.sh`

New PreToolUse:Bash hook. Parses `cd <path>` from the command string (including compound commands like `cd foo && bar`), resolves relative + `~`-prefixed paths against `$PWD`/`$HOME`, derives a query from the destination path's last 2 basenames (e.g., `cd cs/cs-builder` → query `"cs cs-builder"`), and surfaces matched knowledge files. Per-project-per-session cooldown via `/tmp/aria-bashcd-{session_id}-{project_key}` so repeated cd into the same project doesn't re-prompt. Never blocks the cd — emits `additionalContext` only.

### Added — `Step 0.5: Active Knowledge Surfacing` in `/prospect` and `/retrospect`

Both skills gain an identically-shaped Step 0.5 between Step 0 (Inputs & Mode Detection) and Step 1 (Anchor Block). 10-substep Claude-driven algorithm: query-build (from skill arguments) → Read `index.md` → tokenize → match → threshold gate → collect → ledger filter (best-effort via `ls -t /tmp/aria-active-*`) → Read top-5 → 3-line summarize block → carry-forward into Steps 2 and 3.5. The /retrospect variant adds a `prefer logs/retrospect/` priority hint in substep 8 — past retros on overlapping tags are the loop-closure case (retrospect output becomes the next prospect's input on the same topic, after `/index` promotes them to the tag index).

### Changed — `bin/config.sh`

Adds parse + default (`true`) + validation case for `active_knowledge_surfacing`. Mirrors the `auto_capture` shape exactly (3 contiguous lines in each of the three blocks). Invalid values fall back to `true` (active mode is the secure default per D4).

### Changed — `bin/task-context-check.sh`

Inline matcher removed; delegates to `kt_index_match` via the new shared helper. Cooldown, threshold, and emission cap behavior preserved byte-identical to v2.14.4. Active mode branches: filters previously-surfaced paths via the session ledger, swaps "Run /context" wording for an active-Read instruction, records emitted paths to the ledger after a successful surfacing. Passive mode (when the flag is `false`) preserves the v2.14.4 message verbatim.

### Changed — `bin/session-start-check.sh`

Adds a janitor pass clearing stale `aria-active-*` ledgers older than 24h at session start. The knowledge-surfacing block now branches on the flag: active mode emits a 6-step prescriptive algorithm for Claude to execute after the first user task statement (Read index.md → tokenize → match ≥2 known tags → Read top-5 → summarize 1-2 sentences); passive mode preserves the v2.14.4 "suggest `/context`" wording verbatim.

### Changed — `bin/post-compact-check.sh`

Existing pre-compact snapshot detection preserved. New parallel block reads the active-surfacing ledger and emits a re-surface reminder after compaction wipes context. Both blocks coalesce into a single `additionalContext` emission since each hook fires one JSON output. Active-mode-gated; passive mode skips Block 2 entirely.

### Changed — `.claude-plugin/plugin.json`

Registers `PreToolUse:Bash` matcher pointing to `bash-cd-check.sh` (5s timeout, same as the other PreToolUse entries). Existing `PreToolUse: Edit|Write` and `PreToolUse: Glob|Grep` entries untouched.

### Changed — `/setup` wizard

Adds Step 6 Advanced Options bullet for `active_knowledge_surfacing` (named all six trigger sites + ledger path + thresholds inline). Adds Step 7 YAML template line. Adds Step 7b round-trip validation row. Existing users running `/setup` after upgrade will see the field marked `[NEW]` per the existing new-key detection behavior.

### Changed — `CONFIG.md`

New row in the hook-parsed-fields table positioned between `auto_capture` and `critical_paths`. "Read by" column enumerates all six consumers (4 hooks + 2 skills).

### Origin

Design discussion 2026-05-13: user invoked `aria/aria-knowledge` skill context and asked how indexed knowledge gets auto-surfaced, then requested a setup toggle to switch between passive ("suggest `/context`") and active ("autonomously Read matches") modes. Decisions locked through a 4-question form (Active-Read semantic; SessionStart + TaskCreated + Bash:cd + PostCompact trigger surface; single boolean field; default true) plus an addition for skill insertion on /prospect and /retrospect. Step 0.5 placement chosen over Step 0 inline so the conditional active block stays audit-visible separate from each skill's unconditional Inputs step. Implementation followed a 3-checkpoint plan with `[Rule 22]` markers per edit; final retrospect runs after this changelog lands.

## [2.14.4] - 2026-05-12

**New `/handoff` express-handoff skill + `/audit-config` release-state cascade checks.** Closes two ideas filed during the 2026-05-09 wrapup and the 2026-05-11 cascade-traced pipeline-adoption arc. Together they form a prospective↔retrospective release-discipline loop: `/handoff` writes the post-release version-stamp and adoption-state docs (and emits a paste-ready next-session opener); the next `/audit-config` mechanically catches any surfaces that didn't get touched. Patch bump per `feedback_aria_versioning_patch_for_new_skill`: new isolated skill + additive extension to an existing skill, no schema or contract change.

### Added — `/handoff` skill (`plugin/skills/handoff/SKILL.md`)

Express end-of-session handoff. Same coverage as `/wrapup` (review session work → update PROGRESS.md / CLAUDE.md / memory → commit → run `/extract` → verify continuity) compressed into a single combined-go review. Two modes:

- **Default (`/handoff`)** — Generates ALL drafts (session synthesis, PROGRESS entry, CLAUDE.md edits, memory updates, commit message, next-session opener) into one scroll, asks once for combined-go (`yes` / `edit {section}` / `skip {section}` / `abort`), then applies atomically. Preserves the verification pass with the lowest interruption cost.
- **`auto` (`/handoff auto`)** — Implicit-yes on all gates. Runs silently. Applies all drafts without confirmation. Emits final report only. For short, unambiguous sessions.

Always emits a paste-ready **next-session opener** as the headline artifact, even when no other surfaces changed — a fenced block with project marker + read list + "where we left off" + open threads + first action, formatted to drop directly into the next session.

`/wrapup` stays the interactive default for ambiguous sessions; `/handoff` is the express lane. Both call `/extract` (already non-interactive by design); neither ever pushes to git.

### Changed — `/audit-config` skill (`plugin/skills/audit-config/SKILL.md`)

Two new check categories added to Step 3 + a dedicated Step 3a documenting the detection patterns:

- **Version-stamp ripple (Step 3a.1)** — After a plugin/package release, version references typically touch 5+ surfaces (manifest, project CLAUDE.md, parent container CLAUDE.md, project memory file description + body + version-row, MEMORY.md index entry). Detection: for each manifest's canonical version, grep CLAUDE.md / memory files for older semver strings near a project-name mention, flag any surface where the stated version is older than the manifest's.
- **Adoption-state cascade (Step 3a.2)** — When a binary config value flips (e.g., enabled flag, placeholder folder becomes a built artifact), N referenced docs may still describe the prior state. Detection: pattern table of phrases (`"currently disabled"`, `"NOT YET BUILT"`, `"(placeholder)"`, `"pipeline built but not yet adopted"`, `"deferred to v{X.Y.Z}+"` where X.Y.Z is now in the past) cross-checked against the underlying flag/manifest/artifact state.

Both check classes report under **Should Fix** (not **Critical**) because they're pattern-based heuristics — false positives possible. Surface + contradicting phrase + underlying state are presented for user judgment.

"What This Audit Catches" table extended with a **Release-state cascade** row covering both shapes.

### Changed — `/help` skill (`plugin/skills/help/SKILL.md`)

`/handoff [auto]` added to the commands table directly after `/wrapup`, and to the "Sonnet 4.6, medium effort" row in Model Recommendations alongside `/wrapup` (same complexity class: structured work with prescribed output).

### Origin

Two ideas filed during prior sessions converged in this release:
- 2026-05-09 wrapup insight (PROGRESS.md Phase F): post-aria-cowork-v0.2.5 release surfaced a 5-surface version-stamp ripple shape; idea filed to extend `/audit-config` with a version-stamp drift check.
- 2026-05-11 idea file (`intake/ideas/2026-05-11-cross-audit-config-adoption-state-cascade-check.md`): the ariaknowledge.com pipeline-adoption arc traced an 11-surface cascade from a single `0`→`1` flag flip; idea filed to extend `/audit-config` with adoption-state cascade detection.

Both share structural shape (one source-of-truth change → N downstream surfaces drift), so they bundled cleanly into one `/audit-config` extension. The /handoff skill provides the writer side of the same loop — emit the version-stamp + adoption-state updates at release time, let /audit-config verify them later.

## [2.14.3] - 2026-05-08

**Cull-pass refinement of 7 working rules — closes ADR 069's S4 deferral.** Applied Karpathy's litmus test (*"Would removing this rule cause Claude to make a mistake it couldn't recover from?"*) to all 34 working rules across a live-review session. **Zero retirements, zero MERGEs, zero file-class changes** — every flagged candidate became KEEP, REFINE, or KEEP+REFINE after deeper read surfaced scope-mismatch concerns and accuracy gaps yesterday's analogical reasoning had missed. Patch bump per `feedback_aria_versioning_patch_for_new_skill`: in-place content refinements without semver-meaningful behavior change. The cull-pass-became-refinement-pass outcome is a more honest result than the original DEMOTE-heavy plan would have shipped.

### Changed — Rule 4 retitled and rewritten for accuracy (`template/rules/working-rules.md`)

**Title:** "Prefer CLIs over MCP servers" → "**Choose the lower-token option per operation**"

**Body:** Replaced misleading blanket claim ("CLIs reduce token overhead, unless...") with operationally accurate guidance naming the cases where each form wins. CLI is leaner for simple stdout-friendly Unix operations (file listing, grep, git log); MCP is leaner for structured queries (Linear, Supabase, browser state, API/auth) because it returns only the fields requested. Rule 4 now asks the operational question (*"which form returns sparser output for THIS task?"*) rather than encoding a wrong default.

**Why:** the original blanket was 2024-era intuition that's only directionally true for some operations and false for others (structured-data MCP queries are routinely cheaper than equivalent CLI). Rule numbers preserve per Rule 14 policy — readers expecting Rule 4 still find Rule 4, with sharpened content.

### Changed — Rule 8 expanded with broad-scope clause + Origin (`template/rules/working-rules.md`)

Rule 8's body adds a paragraph naming its broad scope (applies to design / exploration / debugging / advice — not just before edits) and an Origin section. The motivating concern: yesterday's plan flagged Rule 8 as a MERGE candidate into Rule 22 Step 2, but Rule 22 hooks fire only on Edit/Write while Rule 8 should apply whenever reasoning starts. The scope-mismatch would have been lost in a merge. The refinement makes the broad scope and the Rule-22-Step-2 composition explicit so future merge-temptation has documented counter-evidence.

### Changed — Rule 16 example list extended (`template/rules/working-rules.md`)

Added a language-agnostic naming example (`fetchUserOrders` over `getUO`) alongside the existing React hook-naming example (`useRequireAuth` over `useAuthGuard`). Recognition for non-JS readers; ~5 words added; original example preserved.

### Changed — Rule 19 retitled and refined for capture-stage clarity (`template/rules/working-rules.md`)

**Title:** "When something fails, learn from it" → "**When something fails, capture the learning**"

**Body:** Original "Failures are data, not just problems" reframe leads. Added paragraph naming the *capture* stage explicitly — applies to test failures, deploy failures, design didn't meet need, hypothesis contradicted, tool call surprised. Names the staging discipline ("capture into extraction-backlog or insights-backlog; do NOT promote into rules at this stage"). Reciprocal composition pointer to Rule 23.

### Changed — Rule 23 retitled and refined for rule-poisoning gate (`template/rules/working-rules.md`)

**Title:** "Review learnings before saving" → "**Review captured learnings before saving them as rules**"

**Body:** Original sentence preserved. Added "Why this gate exists" section naming the load-bearing concern: saved rules become enforced via `/rules` lookups, Rule 22 hooks, and CLAUDE.md context; a wrong rule, once saved, propagates its error across all future sessions until detected and revoked. The review step is the check against rule-poisoning. Reciprocal composition pointer to Rule 19.

The Rule 19 ↔ Rule 23 pairing now explicitly forms the lifecycle: failure → capture (Rule 19) → review (Rule 23) → save.

### Changed — Rule 27 expanded to structural parallel with Rule 33 (`template/rules/working-rules.md`)

Rule 27 gains three sub-sections that mirror Rule 33's existing structure:

1. **Triggers — when this rule fires** — recognizable failure shapes (API error mismatch, version mismatch, deprecation warning, previously-working call now fails)
2. **Routing order** — 5 prioritized verification sources (discovery endpoints → release notes → status page → registry → ask user)
3. **Composes with Rule 33** — reciprocal pointer (Rule 33 already had "Composes with Rule 27"; the asymmetry is now closed)

Original body preserved verbatim; Origin preserved at end. Rule 27 (retrospective verification) and Rule 33 (prospective verification) now read as visibly paired halves of the same external-verification discipline.

### Changed — Rule 29 gains composition pointer to Rule 28 (`template/rules/working-rules.md`)

Inserted a 2-sentence composition note between the minimization tips and the Origin section: Rule 29 specializes Rule 28's "write only as much as needed" discipline to the visual-testing case where tool-cost asymmetry is highest. The pointer surfaces Rule 29 as a worked-example of broader output discipline rather than a standalone tool-cost concern.

### Origin — Karpathy 4-line article review, S4 deferral closes

Surfaced from a 2026-05-06 → 2026-05-08 design conversation walking the 6 cull candidates yesterday's plan flagged. Two patterns fired retrospectively on the original plan's analogical reasoning:

- **`judgment-confused-with-evidence`** — Rules 4 and 29 were flagged as DEMOTE on "tool-specific narrow scope" reasoning that didn't survive deeper read (both turned out to be universal AI-coding cost guidance, not Mike-specific tooling preference)
- **`pattern-matched-from-memory`** — Rule 29's DEMOTE flag was pattern-matched from Rule 4's flag without examining whether the rules served different audiences

The live review surfaced two new analytical lenses worth carrying forward:
- **The universal-vs-personal axis** — DEMOTE-to-user-rules.md is appropriate for personal preferences; harmful for universal cost guidance
- **The scope-mismatch concern** — MERGE proposals frequently collapse rules with different firing conditions (Rule 8's broad reasoning scope vs Rule 22's Edit/Write hook scope; Rule 19's capture stage vs Rule 23's governance stage)

### Considered and rejected

- **DEMOTE Rule 4 / Rule 29 to user-rules.md** — both turned out to be universal cost guidance; demoting harms users who don't read migration notes. Refined in place instead.
- **MERGE Rule 8 → Rule 22 Step 2** — would lose Rule 8's broad-reasoning scope (applies to design / exploration / debugging / advice; Rule 22 hooks fire only on Edit/Write). Hooks were source-traced as parsing markers not framework body, so the merge was *technically* feasible but *semantically* lossy.
- **MERGE Rule 19 → Rule 23 (or vice versa)** — would lose either the "failures are data" reframe (Rule 19) or the broader rule-candidate review scope (Rule 23, which covers non-failure-derived learnings too). Kept paired with reciprocal composition pointers.
- **MERGE Rule 27 → Rule 33** — would lose the timing distinction (Rule 27 retrospective, Rule 33 prospective). Both rules cover stale third-party information but fire on different triggers. Kept paired.
- **Patch (v2.14.3) vs Minor (v2.15.0)** — v2.15.0 was originally targeted assuming retirements/structural shift. With zero retirements and only content refinements, patch is more honest. No semver-meaningful behavior change.

### Self-binding observation

The cull-pass-became-refinement-pass outcome (zero retirements out of 6 candidates) suggests the 34 working rules are leaner than the Karpathy article's "Configuration Paradox" framing assumed for ARIA's context. v2.14.0's Behavioral Foundation preamble already absorbed the four-line discipline as the entry point; the 34 below it earned their keep when each was tested against operational use. Future cull passes should default to KEEP-or-REFINE; only flag for retirement when a rule is demonstrably never load-bearing across multiple sessions.

### Preserved

- All 34 rule numbers preserved per Rule 14 policy
- All hook-enforced rules unchanged in structure (Rule 22, 25, 26)
- Behavioral Foundation preamble (v2.14.0) and `user-examples.md` tier (v2.14.2) unchanged
- Rule 33's "Composes with Rule 27" reference (already correct) unchanged — reciprocity now achieved by Rule 27's new pointer
- All `/rules`, `/index`, `/audit-knowledge`, `/setup`, `/prospect`, `/retrospect` skill behavior unchanged

---

## [2.14.2] - 2026-05-07

**New `rules/user-examples.md` — user-owned file for per-rule before/after examples + `/rules N` skill extension to surface matching examples automatically.** Closes ADR 069's S5 deferral (the "should ARIA ship per-rule examples?" question) with a user-owned single-file design that honors the principle *examples are inherently user-specific* — generic examples drift back into being the rule itself or a separate canonical pattern; project-specific examples ship as foreign content to other users. Patch bump per `feedback_aria_versioning_patch_for_new_skill`: skill extension + new user-owned file is patch-scoped (smaller than a new skill). Plugin ships zero example content; `user-examples.md` is created once on `/setup` from a stub template, then never diffed.

### Added — `rules/user-examples.md` user-owned template (`plugin/template/rules/user-examples.md`)

A new user-owned file alongside `user-rules.md` for project-specific before/after examples illustrating the rules in `working-rules.md`. Mirrors the user-rules.md voice — friendly intro, "examples are user-specific" framing, naming convention, format guidance, skeleton template clearly labeled for replacement.

**Format:**
- Required: `## Rule N — {short title}` heading + `### Before` + `### After` sub-sections
- Optional: `**Calibrated against:** {project / commit / date / incident}`, `### Why this example`, inline citations

**Ownership:** user-owned (created once on `/setup`, never overwritten or diffed). Same class as `LOCAL.md`, `rules/user-rules.md`, directory README stubs.

### Added — `/rules` skill extension (`plugin/skills/rules/SKILL.md`)

Step 3 (Lookup by Identifier) extended with an "Examples lookup" sub-section:

After returning a rule's body, the skill now also reads `{knowledge_folder}/rules/user-examples.md` (if it exists) and searches for a heading matching `## Rule N`. Matching example bodies are appended to the output as a separate section. Multiple examples for the same rule are returned in document order, separated by `---`. If `user-examples.md` doesn't exist or has no matching heading, the example section is omitted silently — no warning for the normal "no examples authored yet" state.

Discovery is automatic: no forward-link maintenance in `working-rules.md` required.

### Added — Documentation surface updates

- `plugin/skills/setup/SKILL.md` — `rules/user-examples.md` added to Expected files list (line 55), User-owned files list (line 57), User-owned bullet in first-setup educational note (line 66), and "Never diff" list (line 107). Same set of integration surfaces as `rules/user-rules.md` since the file class is identical.
- `plugin/template/OVERVIEW.md` — User-owned files paragraph (line 201) updated with `rules/user-examples.md` and v2.14.2 origin annotation.
- `plugin/template/README.md` — `rules/` tree listing gained `user-examples.md` between `user-rules.md` and `change-decision-framework.md`, grouping user-owned files together visually.

### Origin — Karpathy 4-line article review (S5 deferral closes)

Surfaced from a 2026-05-07 design conversation that revisited the originally-recommended Option B (plugin-managed stub with forward-links from `working-rules.md`). Two underweighted concerns invalidated B's trajectory:

1. **Cost to non-users** — plugin-managed stub means recurring diff prompts during `/setup` for users who never author examples (compounds over time)
2. **Examples are inherently user-specific** — Mike's articulated principle: a "universal Rule N example" drifts back toward being the rule itself OR a new canonical pattern; examples earn their illustrative value by being grounded in *specific context* (file paths, commits, project conventions)

Refined Option H (user-owned file + `/rules` extension, zero shipped examples) emerged from synthesizing two alternative designs Mike proposed:
- **Ship-and-freeze with seeds** (no diffs after install, didactic seeds bake at install time)
- **Working/user split** (mirrors rules-split, automatic `/rules` discovery)

The hybrid keeps the no-diff property of the first (user-owned) and the automatic-discovery property of the second (skill extension), while *removing* the seed authoring (which would have violated the user-specific principle).

### Considered and rejected

- **Option B — plugin-managed stub + forward-link convention.** Recurring diff-prompt cost; manual forward-link discipline; speculative demand without empirical motivation.
- **Option F — single file shipped with seeds, becomes user-owned post-install.** Seeds violate user-specific principle (either project-specific = foreign to most users, or generic = should be in the rule itself); bake-time risk.
- **Option G — working-examples.md / user-examples.md split mirroring `working-rules.md` / `user-rules.md`.** Doubles file count; inflates example importance to rule-tier parity; ongoing curation burden on plugin author.
- **Option H-original — user-owned file + 2–3 seed examples + `/rules` extension.** Seeds violate user-specific principle (same as F).
- **Inline `**Example:**` subsections under each rule in `working-rules.md`.** File balloons; behavioral foundation gets buried; re-introduces the Configuration Paradox v2.14.0 was designed to fight.

See ADR 070 (`~/Projects/knowledge/projects/aria/decisions/070-rules-examples-user-owned-tier-decision.md`) for the full alternatives evaluation and consumer-distinction rationale (`detection-mediated tiers = plugin-curated; illustration-only tier = user-authored`).

### Self-binding constraint

ADR 070 records: **no further additions to `rules/` (working-, user-, or otherwise) without an ADR.** Current rule-tier files (`working-rules.md`, `user-rules.md`, `user-examples.md`, `change-decision-framework.md`, `enforcement-mechanisms.md`, `retrospect-patterns.md`, `prospect-patterns.md`) are sufficient for the rule-tier consumer model.

### Preserved

All 34 rules and the Behavioral Foundation preamble (v2.14.0) unchanged. Rule 20's two-half structure preserved verbatim. /retrospect, /prospect, /index, /audit-knowledge, /audit-config, /setup, all hooks: behavior unchanged for users who never author examples. Empty `user-examples.md` is the expected fresh-install state.

---

## [2.14.1] - 2026-05-06

**New /prospect skill (forward-looking pre-mortems on plans before execution) + active Evidence-Sourcing Pass on both /prospect and /retrospect + new release/deployment scopes for /retrospect with hybrid detection cascade + structured-frontmatter persistent log under `~/knowledge/logs/{prospect,retrospect}/` + /index discoverability for review reports.** /prospect is the forward-looking counterpart to /retrospect — runs a 10-section pre-mortem on a plan before any code is written, with the same per-step validation discipline /retrospect applies after a fix ships. Both skills now run a synchronous Evidence-Sourcing Pass (new procedural Step 3.5) that autonomously sources accessible evidence (codebase reads, public docs, MCP queries) and surfaces user-input asks for anything that requires judgment — converting unsupported assumptions to ✅/❌ before the report finalizes. Patch bump per `feedback_aria_versioning_patch_for_new_skill`: additive new skill + extension to existing skills + index scan extension; no breaking changes.

### Added — /prospect skill (`plugin/skills/prospect/SKILL.md`)

Forward-looking pre-mortem on a plan or approach that has been *created but not yet executed*. Mirror of /retrospect's shape so the same review muscle works in both directions. Six positional scopes plus a no-args default:

| Scope | Plan source |
|---|---|
| `plan` (default) | Current conversation's articulated plan — TodoWrite + recent assistant plan + in-session plan files |
| `session` | Synonym for `plan` |
| `todos` | Just the active TodoWrite list |
| `file <path>` | Explicit plan markdown file |
| `linear <id>` | Linear ticket Technical Intake |
| `branch <name>` | Uncommitted/unpushed local branch changes |

Backward-compat flag forms (`--plan`, `--linear`, `--branch`, `--todos`, `--session`) accepted indefinitely. Modifier flags: `--linear-post` (post verdict to detected Linear tickets), `--no-source` (skip Step 3.5).

Produces a 10-section markdown report with anchor / plan-specificity gate / per-step verdict / failure-mode pattern check / cross-step tally / frame check / diagnosis confidence / action verdict / process pre-mortem / pre-execution evidence ask. Per-step actions: PROCEED / SHRINK / SPLIT / DEFER / KILL / DEFER-PENDING-DESIGN. Risk-status taxonomy mirrors /retrospect's validation taxonomy in forward form: ✅ Pre-validated / ⚠ Theory-driven / ❌ Falsified / ❓ Unsupported / 🚫 Unverifiable-yet.

Hard rule: a step's Action cannot be PROCEED unless post-Step-3.5 Risk? is ✅ Pre-validated, OR ⚠ Theory-driven WITH explicit "Acceptable risk because: …" appended. The theory-driven carve-out exists because every plan is theory-driven by definition (you're imagining, not measuring) — the carve-out forces the planner to *name the risk* rather than block all forward motion.

### Added — Evidence-Sourcing Pass on both skills (`plugin/skills/{prospect,retrospect}/SKILL.md`)

New procedural Step 3.5 inserted between Step 3 (Enumerate) and Step 4 (Render Report). For each candidate with non-✅ preliminary status, Step 3.5 generates the *single most decisive question* whose answer would upgrade the verdict to ✅ or ❌, categorizes the answer source as AUTO-SOURCEABLE / USER-INPUT / MIXED, then either sources autonomously or surfaces a structured ask to the user.

**Auto-source tools** (allowed-tools extended with `WebFetch` + `WebSearch`):
- Codebase: Read, Grep, Glob — for file content, references, structure
- Version control: `git log`, `git diff`, `git show`, `git blame`
- Public web: WebFetch (specific URL — library docs, official spec) and WebSearch (when URL is unknown). Per Rule 33, prefer official sources; per Rule 27, verify identifiers/versions are still current.
- Local probes: `curl`, `gh`, log-tail, file-existence checks
- MCP queries that don't require new credentials and that the user has already authorized in this session

**User-input ask format** (codified inline, respecting 7 prior feedback rules — `ask_with_inline_context`, `numbered_options`, `neutral_option_framing`, `per_question_explicit_pick`, `per_item_review_cadence`, `hold_gate_steps`, `terse_numeric_answers`): one ask at a time, citations inline, four numbered options with the fourth always being "Skip — leave at <preliminary status>; will DEFER in §4.10". Synchronous barrier — the skill holds for response. "Skip" defaults to DEFER per `feedback_no_self_fabricated_go_signals` (the skill never invents a decision the user didn't make).

**Constraints** (apply to both skills): two corroborating sources required for ✅ upgrade (single source upgrades only to ⚠ Theory-driven with sub-tag `single-source-inferred`); one contradicting authoritative source falsifies to ❌; no credential reads without explicit per-session permission (per `feedback_ask_before_credentials`); no destructive probes (read-only commands only); time-box ~5 tool-call rounds per question.

**Skip path:** `--no-source` flag skips the entire pass for quick structural reviews. When skipped, all preliminary statuses pass through unchanged and §4.10 lists every gap as `SKIPPED-BY--no-source`.

/retrospect's Step 3.5 has *two* sub-passes (vs /prospect's single pass) — bundle-marker first (resolves 🤷 by sourcing the deployed bundle and grepping for the in-bundle marker), then outcome (resolves ⚠/❓/🚫 by sourcing post-deploy logs/repros). Bundle-marker pass feeds §4.2's emit value; outcome pass feeds §4.3's emit value.

### Added — `release` and `deployment` scopes for /retrospect (`plugin/skills/retrospect/SKILL.md`)

Two new positional scopes joining the existing `commit`, `range`, `pr`, `session` set:

- **`release`** — `git describe --tags --abbrev=0` to find the most recent semver tag, then `git log <tag>..HEAD`. If no tags, fall back to auto-range with a warning.
- **`deployment`** — hybrid detection cascade (4 steps): (1) `gh release view --json publishedAt,tagName`, (2) `git tag --sort=-creatordate | head -1` matching `v?\d+\.\d+\.\d+`, (3) last commit on `origin/main` (or `origin/master`), (4) prompt user. First success wins. Print the resolved marker source in §4.1 Anchor so the user can verify what the skill thought "deployment" meant.

Designed to cover the union of CS (semver tags), SS (Bitbucket pipelines without GH releases), and builder repos (semver) deploy conventions without per-project config.

### Added — RESHIP-AND-VERIFY action for /retrospect (`plugin/skills/retrospect/SKILL.md`)

New action introduced when §4.2 emits ❌ Not-in-bundle (Step 3.5.1 positively confirmed the fix did NOT ship, e.g., bundle returned 200 but the marker grep was empty, OR the deploy log shows a failed/superseded job). The fix's code is correct — it just didn't ship. §4.8 emits a project-appropriate re-deploy command (from `aria-config.md`'s `projects_list[<tag>]` if present, otherwise prompt user) plus a directive: "After re-deploy, re-run `/retrospect deployment` to confirm the bundle now contains the fix and validate outcome." Closes the loop between failed-deploy detection and re-validation.

### Changed — Positional scope syntax for /prospect and /retrospect

First positional argument is now the **scope keyword**; subsequent positional arguments are scope-specific. Existing flag forms (`--range`, `--pr`, `--session`, `--commit`, `--plan`, `--linear`, `--branch`, `--todos`) remain accepted indefinitely as backward-compat aliases. Both `/retrospect range a..b` and `/retrospect --range a..b` resolve identically. Argument-hint frontmatter updated to `[<scope>] [<scope-arg>] [--linear-post] [--no-source]`.

### Changed — `--linear` renamed to `--linear-post` on /retrospect (no alias)

For consistency with /prospect's existing `--linear-post` flag. The verb form makes the side-effect explicit (the flag triggers a POST to Linear, doesn't just consult it). Per Mike's pick, no `--linear` alias — old invocations break, but the rename is documented in plugin.json description and Step 0 mode table.

### Changed — Persistent log filename + structured YAML frontmatter

Reports persist to `~/knowledge/logs/prospect/<YYYY-MM-DD>-<scope>-<slug>.md` and `~/knowledge/logs/retrospect/<YYYY-MM-DD>-<scope>-<slug>.md` (existing files under the older `<YYYY-MM-DD>-<slug>.md` pattern are grandfathered — no rename).

Each report is now prepended with structured YAML frontmatter (Q1.1=2 schema):

```yaml
---
type: prospect | retrospect
date: <YYYY-MM-DD>
scope: <scope keyword>
goal: <one-line>
tickets: [<LINEAR-123>, ...]
steps_count | fixes_count: <N>
sourcing_pass: <flat block for prospect; nested bundle_marker + outcome blocks for retrospect>
patterns_hit: [...]
overall_verdict (prospect): PROCEED | PROCEED-WITH-CHANGES | HOLD | KILL
overall_outcome (retrospect): closed | partial | unresolved | mixed
related: [<paths to overlapping prior runs>]
tags: [<type>, <scope>, <project-tag-if-detected>, <pattern-tag-if-applicable>]
---
```

`related:` auto-detection (Q1.2=1, ticket-based): before writing, glob `~/knowledge/logs/{prospect,retrospect}/*.md` for files whose frontmatter `tickets:` overlaps with the current report's tickets. Cap at 10 most-recent overlaps. Bidirectional discoverability — yesterday's retrospect surfaces in today's prospect's `related:` and vice versa.

`overall_outcome` derivation (retrospect): `closed` if every fix's post-Step-3.5 Validated? is ✅; `unresolved` if any fix is ❌ Invalidated or ❌ Not-in-bundle; `partial` if any fix is ⚠ partial AND none are ❌; `mixed` for any other combination.

### Added — Reviews tier scan + Review Index in `/index` (`plugin/skills/index/SKILL.md`)

Q1.3=1 (review reports discoverable via /context). Step 1's "Do NOT scan: ... logs/" rule replaced with a more precise carve-out: top-level `logs/*.md` (audit logs, hook debug log) remain excluded, but `logs/prospect/` and `logs/retrospect/` ARE scanned via a new "Reviews tier scan" sub-step. Review files are stored with `source: "review"` and pull retrospect/prospect-specific frontmatter (`type`, `scope`, `tickets`) alongside standard tags.

Step 9's `index.md` schema gets a new `## Review Index` section between `## Team-Shared Tag Index` and `## Stale Files`, with two subsections (Retrospects, Prospects), descending-by-date sort, compact one-line entries showing date / scope / goal (truncated) / tickets / overall_outcome|overall_verdict.

### Considered and deferred — Step 8 / 8c filter for review files (option C)

Considered applying a high-signal triple-gate filter (ticket-ID match / pattern-hit match / explicit citation) to /index Step 8 (Cross-Reference Pass) for review files, plus a skip-with-mention-exception for Step 8c (Skill Connection Discovery). Motivation: review files have rich tag sets that match many things shallowly via the existing ≥2-tag heuristic, producing dozens of low-signal Y/N suggestions per /index run; reviews are CONSUMERS of knowledge, not SOURCES that other files should link back to. Three options were proposed (A: high-signal triple-gate + direction asymmetry + Step 8c skip; B: skip Step 8 + Step 8c entirely; C: defer with documentation).

**Mike's pick: C.** Deferred because pattern depth is not yet known — until /index runs against several real review files in active /context queries, the actual signal-to-noise of the existing heuristic is theoretical. Better to ship the review-tier scan now, observe noise on real runs, refine filtering based on observed cases. Full design captured in `aria/IDEAS-BACKLOG.md` (2026-05-06 entry — `/index Step 8 + 8c filter for review files`) including implementation sketch and composes-with pointers to existing entries (the 2026-05-05 "/index focused-session cross-reference-only mode" and the 2026-04-30 "25th-Pass /index Run Findings").

### Preserved

All 34 working rules unchanged. Behavioral Foundation preamble from v2.14.0 unchanged. retrospect-patterns.md from v2.13.9 unchanged. /retrospect's existing 10-section report structure preserved verbatim (no section renumbering, no removals); the additions are: Step 3.5 procedural step inserted between Step 3 and Step 4, and §4.2/§4.3/§4.5/§4.7/§4.8/§4.10/Step 8 bodies extended to integrate Step 3.5 findings without breaking the section count.

### Origin — applying /retrospect's discipline to forward-looking work

The /prospect design surfaced from a 2026-05-06 session question: "we have /retrospect for shipped work, but the same per-fix validation discipline applies to plans before they ship — what if every step in a plan got the same scrutiny *before* code lands?" The answer was a mirror skill with parallel structure: same 10 sections, same validation taxonomy (in forward form), same hard rule (with a theory-driven carve-out for the obvious case that all plans are theory-driven). The Evidence-Sourcing Pass was added to *both* skills in the same pass to close the gap between "name the missing evidence" and "actively try to gather it" — a refinement Mike requested after seeing /prospect ship without it.

---

## [2.14.0] - 2026-05-06

**Behavioral Foundation preamble + Rule 20 reframed for upfront-criteria leverage + Evidence-and-limits section in README.** Distills the 34 working rules into four behavioral principles aligned with [Andrej Karpathy's January 2026 diagnosis](https://x.com/karpathy/status/2015883857489522876) and the [4-line CLAUDE.md repo](https://github.com/forrestchang/andrej-karpathy-skills) it inspired. Positions the 4-line foundation as a load-bearing entry point with the 34 rules as the operationalized expansion. Minor bump because the preamble is a user-visible structural addition above all 34 rules.

### Added — Behavioral Foundation preamble (`template/rules/working-rules.md`)

A new section between "How to Use This Document" and "Coding Rules" introduces four behavioral principles distilling what the 34 rules collectively enforce:

1. **Don't assume — surface tradeoffs.** *(Rules 5, 7, 9, 10)*
2. **Simplest solution wins — nothing speculative.** *(Rules 13, 14, 18)*
3. **Touch only what you must.** *(Rules 22, 25, 26)*
4. **Define success criteria upfront, loop until verified.** *(Rule 20)*

Each principle cross-references the rules below that operationalize it. Includes a "Why both layers exist" paragraph naming the conditions that justify expansion past four lines: (a) work spans multiple sessions and needs persistent discipline, (b) failures have asymmetric cost and need explicit gating, or (c) team coordination requires shared, named conventions. The volume past four is justified by the operational context, not added for its own sake.

### Changed — Rule 20 reframed for leverage + discipline (`template/rules/working-rules.md`)

Rule 20 retitled from "Always validate before assuming completion" to "Define success criteria upfront, validate before assuming completion." The original verify-before-done discipline is preserved verbatim as the second half. A new first half introduces the leverage framing: strong, verifiable criteria let Claude loop independently; weak criteria ("make it work", "fix the bug") require constant clarification. Concrete transformations included:

- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Refactor X" → "Ensure tests pass before and after"

A "Why both halves matter" paragraph names the distinction: verify-before-done is *discipline* (catches failure after the work), define-criteria-first is *leverage* (prevents most failure by giving the agent a verifiable target to loop against). Composes-with pointers to Rule 22 Step 6 and Rule 24 added.

### Added — Evidence and limits section (`README.md`)

A new section between "Philosophy" and "ARIA vs Other Memory Architectures" honestly names the calibration shape: real-failure data from the plugin author's projects, not controlled study; the 5-instance cs-builder cycle on 2026-05-05 as the strongest single calibration; no before/after benchmarks across the broader developer population. References the Karpathy 4-line repo as a peer with the same evidence shape ("strong resonance, no controlled study") and notes ARIA now ships those 4 principles as the Behavioral Foundation preamble. Includes "Where ARIA is most likely to help" and "Where ARIA may be overkill" lists to set expectations.

### Origin — applying the Karpathy 4-line article to ARIA

Surfaced from a 2026-05-06 review of [Yanli Liu's "The 4 Lines Every CLAUDE.md Needs"](https://levelup.gitconnected.com/the-4-lines-every-claude-md-needs-2717a46866f6) and the underlying `forrestchang/andrej-karpathy-skills` repo. The article's diagnosis — that behavioral constraints outperform feature checklists past a certain rule-count threshold — is partially a critique of ARIA-shaped systems. v2.14.0's response: keep the 34 rules (justified by ARIA's operational scope), add the 4-line foundation as the entry point, and acknowledge the evidence limit honestly. The four principles are not a replacement; they're the elevator-pitch summary of what the rules already enforce.

### Considered and deferred — `rules-examples.md` plugin-managed tier (S5)

Considered shipping a new plugin-managed file `template/rules/rules-examples.md` with before/after code walkthroughs per rule (modeled on [the Karpathy repo's EXAMPLES.md](https://github.com/forrestchang/andrej-karpathy-skills/blob/main/EXAMPLES.md)). Deferred because (1) per v2.13.7's "Considered and rejected — full approach file in plugin source" precedent, adding a new tier of shipped content is an ADR-class decision, not a routine release, (2) the integration cost is non-trivial — README.md tree, OVERVIEW.md managed-files list, setup SKILL.md (3 places) all require updates, and (3) the design intent question ("does ARIA ship per-rule examples, and at what tier — plugin-managed, user-curated like `approaches/`, or mixed?") deserves explicit deliberation. Recorded as a candidate for an ADR + future release.

### Considered and deferred — aria-cowork tool-portability framing (S6)

Considered adding a "principles transfer, phrasing doesn't" section to aria-cowork's README acknowledging the article's tool-portability point and the design challenge of generalizing aria-knowledge's enforcement layer (Code-only) to Cowork's skills-only surface. Deferred because aria-cowork is a sibling plugin with its own release cycle (v0.2.4 BUILT 2026-05-05); the framing edit belongs in aria-cowork's source, not aria-knowledge's. Recorded for the next aria-cowork release.

### Considered and deferred — litmus-test cull pass on 34 rules (S4)

Considered running Karpathy's litmus test ("Would removing this cause Claude to make a mistake it couldn't recover from?") on each of the 34 working rules to identify candidates for removal, demotion to user-side, or merging into adjacent rules. Deferred per user direction to a separate review session — the cull is judgment-heavy and shouldn't be bundled into a release that introduces new structure.

### Preserved

All 34 rules unchanged in body content and numbering. Rule 20's title evolved (refinement allowed per the file's stated rule-evolution policy) but the original "validate before assuming completion" sentence is preserved verbatim as the second half of the reframed rule. Retrospect-patterns.md from v2.13.9 unchanged.

---

## [2.13.9] - 2026-05-06

**Two new canonical retrospect patterns: `fix-without-call-site-audit` and `new-artifact-without-consumer-trace`.** Decomposes the broader completion-claim-without-trace family that v2.13.8 opened — covers two distinct sub-shapes surfaced by a five-instance real-use cycle, each with independent calibration data and distinct counter-disciplines. Pure additive content; no plugin behavior, schema, or skill changes.

### Added — Two canonical retrospect patterns (`template/rules/retrospect-patterns.md`)

- **`fix-without-call-site-audit`** — fixing a function-contract bug at one call site without auditing all sibling call sites of the same function for the identical gap. Detection cues cover commit-message framing ("fix at X" naming the symptom rather than the function), recurrence at sibling call sites within hours, and missing "audited all callers" language. Counter-discipline: grep all call sites of the function before claiming complete; document why any unpatched sibling is exempt. Calibrated against four sequential cs-builder Stage 1 instances on 2026-05-05 (gallery merge, tool-use rehost, action-chip render, Discovery onBlur rehost) — the strongest single-session calibration in the canonical library.

- **`new-artifact-without-consumer-trace`** — creating a new artifact (blueprint, route, skill, handler, template) consumed by a static enumerator (registry, manifest, dispatch table, type union) and claiming end-to-end completeness without verifying or updating the enumerator. Detection cues include the new file matching a plural-file shape, completion-claim language ("will work end-to-end", "auto-mirrors", "deployed") elided of consumer naming, and the consumer being reachable by a single grep that wasn't run. Counter-discipline: identify the consumer, grep for analogous entries, name the consumer explicitly in the completion claim. Inverse of the call-site discipline above: where `fix-without-call-site-audit` covers existing-function → multiple-callers, this pattern covers new-artifact → existing-enumerator. Calibrated against the bar blueprint instance from the same 2026-05-05 cs-builder Stage 1 cycle.

### Origin — Sub-shape decomposition

Both patterns were surfaced by the same 2026-05-05 cs-builder Stage 1 close-out cycle. The cycle produced five instances of completion-claim failure: four sharing the call-site-audit shape and one sharing the consumer-trace shape. Decomposition into two pattern entries (rather than one umbrella) preserves each calibration: 4x for `fix-without-call-site-audit`, 1x for `new-artifact-without-consumer-trace` — both at or above the bake level v2.13.8 shipped at.

### Layering map across four same-week releases

| Version | Layer | Surface |
|---|---|---|
| v2.13.6 | Rule text | "Architectural claims about existing systems" trigger added to Rule 34 |
| v2.13.7 | Layer 3 enforcement | Recognition cues + required `[Rule 34]` marker format |
| v2.13.8 | Retrospective × 1 | `architectural-claim-without-source-trace` (negative-existence claims about existing systems) |
| v2.13.9 | Retrospective × 2 | `fix-without-call-site-audit` + `new-artifact-without-consumer-trace` (two distinct completion-claim sub-shapes) |

The three v2.13.x retrospective patterns now cover three distinct completion-claim sub-shapes: "X doesn't enforce Y" (v2.13.8), "fixed at site X" omitting siblings (v2.13.9), and "X will work" omitting consumers (v2.13.9). Each has independent calibration data and distinct counter-disciplines.

### Considered and rejected — single umbrella pattern

Considered shipping one umbrella pattern (`completion-claim-without-trace`) covering both sub-shapes. Rejected because the 4x and 1x calibrations point to genuinely different counter-disciplines (audit call sites vs. grep registry consumers) — an umbrella would dilute both. Each canonical pattern in the library targets a specific counter-discipline, and merging the two would break that convention.

### Considered and deferred — artifact-shape hook gate

Considered shipping an artifact-shape gate in `pre-edit-check.sh` that fires on `Write` of new files matching registered globs in a per-project artifact-shape registry, emitting an advisory line ("creating artifact X matches shape Y; consumer is Z; have you grepped?"). Deferred because (1) one calibration instance for the consumer-trace shape is insufficient bake to lock the gate's storage location, severity (advisory vs. ack-required), and registry schema, (2) source-trace work required (read `pre-edit-check.sh`, current `aria-knowledge.local.md` schema, `enforcement-mechanisms.md` Layer 2/3 boundary criteria) is non-trivial and shouldn't be combined with content additions, and (3) the call-site-audit sub-shape is a poor fit for hook enforcement since it operates over edit-history not file-paths. Recorded as plan-of-record for v2.14.x pending usage data on (a) `new-artifact-without-consumer-trace` retrospective hit rate, (b) registry-shape diversity across projects, and (c) whether the canonical pattern alone closes the gap or hook enforcement is required.

### Preserved

All template content from v2.13.8 unchanged. `retrospect-patterns.md` is purely additive — the 10 prior canonical entries (`diagnose-from-shape-not-path`, `fix-bundling`, `bundle-unverification`, `speculative-iteration`, `judgment-confused-with-evidence`, `phrase-tell-consistent-with-evidence`, `pattern-matched-from-memory`, `pushback-as-cue`, `user-not-recruited`, `architectural-claim-without-source-trace`) are byte-identical to v2.13.8.

---

## [2.13.8] - 2026-05-05

**New canonical retrospect pattern: `architectural-claim-without-source-trace`.** Adds the failure-mode detection counterpart to v2.13.7's prospective Rule 34 layering. Where v2.13.7 added recognition cues + required marker format to catch the trigger *before* claiming, v2.13.8 adds the post-incident pattern that `/retrospect` runs detect when the trigger fired but wasn't caught — closing the prospective-plus-retrospective discipline pair against the same recognition gap.

### Added — Canonical retrospect pattern (`template/rules/retrospect-patterns.md`)

- **`architectural-claim-without-source-trace`** — new canonical pattern entry following the existing pattern-library format. Detection cues cover both code-side (architectural-substitution proposals before source-trace) and docs-side (stale "STILL OPEN" tracker entries written without source-trace) instances of the same recognition gap. The pattern's *Why it's a problem* names negative-existence claims ("X is not enforced") as the highest-confidence wrong-claim shape — *exactly* the claim that requires a source-trace because the cost of being wrong is shipping work that duplicates existing infrastructure or replaces working code. Counter-discipline cross-references Rule 34, framing the rule-text as the prospective catch and the pattern as the retrospective catch.
- First identified in a real-use cs-builder retrospective on 2026-05-05 — same incident lineage as v2.13.6's Rule 34 trigger expansion and v2.13.7's enforcement layering. v2.13.8 closes the third leg.

### Origin — Layering map across three same-day releases

| Version | Layer | Surface |
|---|---|---|
| v2.13.6 | Rule text | "Architectural claims about existing systems" trigger added to Rule 34 (working-rules.md) |
| v2.13.7 | Layer 3 enforcement | Recognition cues + required `[Rule 34]` marker format + self-check questions (working-rules.md + change-decision-framework.md) |
| v2.13.8 | Retrospective detection | `/retrospect` pattern entry for post-incident bundle scans (retrospect-patterns.md) |

The three releases form a complete prospective-plus-retrospective discipline pair against the architectural-claims recognition gap. Rule 34 catches the trigger before the architectural turn happens; the new pattern catches the failure shape when `/retrospect` runs on a bundle where the trigger fired uncaught.

### Preserved

All template content from v2.13.7 unchanged. `retrospect-patterns.md` is purely additive — the 9 prior canonical entries (`diagnose-from-shape-not-path`, `fix-bundling`, `bundle-unverification`, `speculative-iteration`, `judgment-confused-with-evidence`, `phrase-tell-consistent-with-evidence`, `pattern-matched-from-memory`, `pushback-as-cue`, `user-not-recruited`) are byte-identical to v2.13.7.

---

## [2.13.7] - 2026-05-05

**Rule 34 enforcement layered up to soft Layer 3 (non-hook), plus restoration of `rules/retrospect-patterns.md` references in two user-facing template docs that were inadvertently dropped in v2.13.6.** Adds recognition cues, layer-trace methodology, required `[Rule 34]` marker format, self-check questions, and a CODEMAP-gap conditional clause to Rule 34's enforcement surface — without crossing to Layer 2 (hook). Closes the prevention-work item filed 2026-05-05 from the S62 cs-builder nav-architecture audit.

### Added — Rule 34 enforcement layered to Layer 3 (`template/rules/`)

Per `enforcement-mechanisms.md`, Rule 34 previously sat at Layer 1 (rule text + honor-system marker). The S62 nav-architecture audit (2026-05-04) provided calibration data: ~6 turns of architectural recommendation produced from a single-file render-layer read, when the actual rule was already implemented in a 20-day-old commit at the data-loader layer. **Recognition was the failure mode, not absence of rule text.** This release adds non-hook catches at Layer 3 — required output format that forces visible reasoning — without yet crossing to Layer 2 (hook prompt). Mirrors Rule 22's evolution arc: text first, format spec second, hooks once usage data clarifies trigger surface.

- **`template/rules/working-rules.md`** — under Rule 34's trigger list, added a **"Recognition cues"** sub-section listing two phrase-pattern categories that signal architectural-claims trigger risk:
  - *Positive architectural framing* — "the right model" / "the wrong model" / "architectural endpoint" / "the data flow should" / "this changes how [system] works" / "via substitution" / "substitution model" / "append model" / "should be [substituting / appending / merging]"
  - *Negative existence claims* (highest-confidence wrong-claim shape) — "doesn't enforce" / "isn't implemented" / "isn't handled" / "no [rule / check / validation] for this" / "this should be enforced but isn't" / "X is missing from [layer]"

  Phrase fragments give Claude concrete recognition cues, lowering threshold for the gate to fire. Single words like "append" or "merge" appear in routine code talk and are too noisy alone, so the gate is on phrase-fragments only.

  Also added a **"CODEMAP-gap conditional"** clause: if the project has a CODEMAP and the trigger fires for an area whose CODEMAP doesn't surface the rule-enforcement layer, file a gap before claiming. **Conditional on CODEMAP existence** — does not force CODEMAP creation as a Rule 34 prerequisite. If the project doesn't use CODEMAPs, the layer-trace methodology still applies; the gap-filing requirement doesn't.

- **`template/rules/change-decision-framework.md`** — under "Plan-Level Application (Rule 34)":
  - Added **"Layer-trace methodology (architectural-claims trigger)"** sub-section with the 5-step trace that populates Step 2 (Intake) and Step 6 (Validate) of the 7-step framework when the architectural-claims trigger fires: CODEMAP-first → cross-layer grep across data/transform/render/export/type/validator → `git blame` recent commits → simulate data flow with current state → only then claim.
  - Expanded the terse "Marker:" paragraph into a full **"Required marker format"** specification with a concrete 7-step body example. Per the 2026-05-02 design decision pinning the marker name (`[Rule 34]`, not `[Plan · Rule 22]`), the block mirrors Rule 22's per-edit marker structure but covers the whole plan, with framework body identical to Rule 22 High Impact format (Identify / Intake / Criteria / Solutions / Rank / Validate / Execute). Each labeled field is a recognition checkpoint; skipping a field means the framework step it represents was skipped at plan-formation time.
  - Added **"Self-check before claiming"** sub-section with 4 forcing-function questions targeting the highest-value recognition gaps (have I read the layer that actually contains the rule's enforcement; recent commits; CODEMAP coverage; cross-layer grep for negative-existence claims).
  - Updated **"Enforcement state"** paragraph to reflect Layer 3 status. Self-audit of transcripts for missing `[Rule 34]` blocks where they should appear is named as the calibration data feeding the eventual Layer 2 hook decision.

### Origin — Rule 34 enforcement layering

Surfaced from S62 cs-builder nav-architecture conversation (2026-05-04): ~6 turns of architectural recommendation about a "missing" append model when the append model was already implemented at `cs-builder-working/src/lib/blueprint-loader.ts:645-662`, committed 2026-04-15 (20 days before the conversation). User explicit pushback ("review and validate") triggered the audit that surfaced the gap. The S62 retrospective produced a validated approach (`audit-before-architecture-claims.md`, user-side) and queued plugin-source prevention work as an extraction-backlog item dated 2026-05-05. This release closes that loop. The phrase-pattern categories and methodology shipped in plugin source are abstracted from that approach; concrete project-specific examples, file references, and memory cross-refs stay user-side.

### Considered and rejected — full approach file in plugin source

Considered shipping `template/approaches/audit-before-architecture-claims.md` as a new tier of plugin-managed content. Rejected because (1) plugin design intent (per `setup` SKILL.md) treats `approaches/` as user-curated content with only the README skeleton shipped, (2) the approach was validated 2026-05-05 with one example session — insufficient bake time across diverse projects to generalize, (3) Mike-specific examples (S62 commit hashes, cs-builder file paths, memory cross-refs) are what make it concrete; sanitizing for general use weakens it, and (4) shipping one approach establishes a precedent requiring a generalizability principle for which others ship — better filed as an ADR-class decision than a routine patch. The Layer 3 mechanism shipping here closes most of the gap the approach addresses without changing plugin source's content model.

### Fixed — `template/README.md` rules/ tree

The `rules/` directory tree in the README's "Structure" section now lists `retrospect-patterns.md` alongside the other four rules-tier files. Previously the file shipped at `plugin/template/rules/retrospect-patterns.md` and was referenced by `/retrospect` and `/setup`, but the user-facing tree omitted it — making it undiscoverable to anyone reading the template README to understand what's in their knowledge folder.

### Fixed — `template/OVERVIEW.md` plugin-managed files paragraph

The "Plugin-Managed vs User-Owned Files" section's managed-files list now includes `rules/retrospect-patterns.md` between `rules/enforcement-mechanisms.md` and `projects/README.md`. This brings OVERVIEW.md in sync with `plugin/skills/setup/SKILL.md` (lines 65 and 105), which already listed the file as plugin-managed and in the `/setup` diff loop — the contradiction has now been resolved.

### Origin — README/OVERVIEW docs regression

Surfaced during a `/setup` diff session on a v2.13.6-installed knowledge folder where the user noticed both files were listed as "user ahead, plugin regressed." Cross-checked against the file's actual presence in `plugin/template/rules/` (still shipped) and against `setup/SKILL.md` (still authoritative on managed-file status). Both were correct; the documentation surface was the only point of drift. This patch restores the documentation invariant.

## [2.13.6] - 2026-05-05

**Documentation patch — surface aria-cowork as a sibling plugin, cross-reference the new Cowork plugin-authoring guide, and refine Rule 34's trigger list with an architectural-claims trigger surfaced by a real failure mode.** Pure CLAUDE.md + template/rules/ additions; no plugin behavior, schema, or skill changes.

### Added — Rule 34 trigger refinement in `template/rules/`

A new trigger added to Rule 34's plan-level review list: **"Architectural claims about existing systems"** — asserting how a system's data flow, rendering model, or rule-enforcement layer currently works *or doesn't work*. Single-layer reads frequently produce wrong claims when transformations live upstream; the claim becomes a load-bearing premise for downstream proposals.

- **`template/rules/working-rules.md`** — added the trigger bullet to Rule 34's trigger list, between "Asymmetric failure cost" and the "Out of scope" sub-section.
- **`template/rules/change-decision-framework.md`** — added the matching "or claims about existing systems" qualifier to the parenthetical trigger summary at the start of "Plan-Level Application (Rule 34)" so the summary stays in sync with the authoritative list.

**Origin:** A multi-turn conversation produced ~6 turns of architectural recommendation about an existing nav-construction layer, based on a single-file render-layer read. The actual rule was already implemented at the data-loader layer, in a commit predating the conversation by 20 days. Audit found this only after explicit pushback. The "currently works or doesn't work" qualifier specifically catches the highest-confidence wrong-claim shape — claims that an existing rule *isn't* enforced when it actually is, where the proposed fix duplicates already-existing logic.

**Cross-plugin parity:** aria-cowork v0.2.4 mirrors this template change in the same patch window — both plugins ship the same Rule 34 trigger list per the cross-plugin compatibility note in their CLAUDE.mds.

### Added — `CLAUDE.md` updates

- **New "Sibling Plugin (aria-cowork)" section** between the intro and Project Structure. Names the sibling repo (`mikeprasad/aria-cowork`, public, at `~/Projects/aria/aria-cowork/`), notes the shared `~/Projects/knowledge/` folder + additive-only `aria-config.md` schema (per aria-cowork's ADR-002), flags shared-surface edit caution (cross-plugin compatibility on field names, template/rules/ content, working-rules.md numbering), summarizes the 10-of-23 skills port + 5 explicit Code-only exclusions per aria-cowork's ADR-005, and forward-points to `knowledge/guides/claude/cowork-plugin-validation.md`.
- **New cross-project knowledge bullet**: `knowledge/guides/claude/cowork-plugin-validation.md` added to the Knowledge Repository list alongside the existing Code-side `plugin-development.md`. The Cowork guide captures durable findings from the aria-cowork v0.2.0 → v0.2.1 description-length-cap diagnostic — relevant to anyone coordinating with aria-cowork or shipping a Cowork-side plugin.

### Considered and rejected — `captured_via: aria-knowledge` field backport

aria-cowork v0.1.0–v0.2.3 wrote `captured_via: aria-cowork` to `/ask` and `/clip` frontmatter. Backporting a symmetric `captured_via: aria-knowledge` was considered for cross-surface provenance audit. **Rejected** per Rules 13 + 18 (simplest solution wins; foundational design over patching) — per-doc metadata accumulates unbounded cost across 100s of captured docs over months for a hypothetical-only consumer. aria-cowork v0.2.4 also removes the field on the same reasoning, restoring symmetry rather than breaking it. Better alternatives if surface-provenance becomes a real audit need: centralized `logs/capture-log.md` event log, time-correlation against existing surface session logs, or discretionary `tags: [surface:cowork]` on specific captures.

### Preserved

- All skill behavior unchanged.
- All hook configurations unchanged.
- aria-config.md schema unchanged.
- License + repository + keywords + homepage in plugin.json unchanged.
- All template content outside Rule 34 trigger list unchanged.

---

## [2.13.5] - 2026-05-03

Patch release adding the `/retrospect` skill — a structured retrospective tool for shipped commit ranges with per-fix validation enforcement, simpler-alternative discipline, re-diagnosis when fixes failed, and a growing failure-mode pattern library.

### Added — `/retrospect` skill in `plugin/skills/retrospect/SKILL.md`

A new slash command that runs a 10-section retrospective on a shipped commit range, single commit, PR, or current session. The skill enforces a validation discipline: no fix is marked effective without explicit, named evidence (log event, reproduction-then-fix-verified, production instrumentation, or deployed-state check). Unvalidated fixes are flagged 🤷 Bundle-unverified or ❓ Unvalidated and cannot reach a KEEP action. Failed/partial fixes feed back into a re-diagnosis section that names surviving hypotheses and the specific instrumentation needed to discriminate between them — converting failed releases into evidence for the next attempt rather than another speculative fix.

The skill also runs a **failure-mode pattern check** against `rules/retrospect-patterns.md` (canonical) and `projects/<proj>/retrospect-patterns.md` (project-specific when applicable). Pattern hits surface named process failure modes (e.g., `diagnose-from-shape-not-path`, `bundle-unverification`, `speculative-iteration`, `phrase-tell-consistent-with-evidence`) so that recurring discipline gaps are visible across retrospectives. Novel patterns identified during a retrospective can be added to either library on user approval.

### Added — Canonical pattern library at `plugin/template/rules/retrospect-patterns.md`

Seeded with 9 canonical, project-agnostic failure-mode patterns derived from real retrospective evidence. Each entry includes detection cues, why-it's-a-problem, counter-discipline, and a references list. The file is registered as plugin-managed in `plugin/skills/setup/SKILL.md` — user-added patterns appear as diff prompts on plugin upgrades, never silently overwritten.

### Added — Plugin-managed registration in `plugin/skills/setup/SKILL.md`

`rules/retrospect-patterns.md` added to both the educational plugin-managed file list and the diff-loop file list, so `/setup` recognizes the new template.

### Added — `/retrospect` listing in `plugin/skills/help/SKILL.md` and `README.md`

Discoverability via `/help` and the public-facing skill catalog.

### Why this skill now

After shipping releases that produced multi-fix bundles where some fixes were necessary, some addressed misdiagnosed causes, and some over-engineered working code paths, the failure mode was clear: without a structured retrospective, the next instinct after a partial release is another speculative fix, repeating the loop. The `/retrospect` skill makes a structured retrospective the default response to a failed/partial release and treats post-deploy reality (not pre-merge code review) as the primary source of truth. Validation enforcement is the keystone — no fix is marked "shipped" without named evidence — and the failure-mode pattern library makes process learnings reusable across projects rather than re-discovered each retrospective.

### Soft-suggest trigger

The skill instructions include Claude-side judgment for offering `/retrospect` (never auto-executing) when the user's message contains regression cues ("still broken," "didn't fix," "review what you did," sharing test logs that show failure) and the current session has shipped recent fixes. Hook-based auto-trigger is deferred to v2 pending real-world calibration of which release events deserve auto-prompting.

### Out of scope (v1)

- Cross-change pattern *interpretation* (raw counts only)
- Automated pattern cue matching (judgment-based in v1)
- Auto-trigger on git push events
- Linear ticket auto-creation for FOLLOWUP-TICKET actions (drafts only in v1)
- Multi-bundle/series retrospectives

### Upgrade notes

- **Reinstall recommended** to pick up the new skill, the seeded canonical pattern library, and the setup registration.
- **No config migration** — no new hooks, no new top-level config keys. (A future `retrospect:` block in `~/.claude/aria-knowledge.local.md` will configure default destinations; v1 uses fixed defaults.)
- **No existing skill behavior changed** — `/retrospect` is purely additive.

## [2.13.4] - 2026-05-02

Patch release adding **Rule 34: Validate the plan with Rule 22's framework before executing** to the working-rules template, plus supporting cross-references in `change-decision-framework.md` and `enforcement-mechanisms.md`. Rule 33's plan-level counterpart — extends the same framework discipline from per-edit to per-plan scope.

### Added — Rule 34 in `plugin/template/rules/working-rules.md`

Plan-formation discipline rule directing that any qualifying plan be validated with Rule 22's full 7-step framework *before* execution begins. The goal: validate that this is the right plan based on (a) what we know now, (b) what's accessible to know, and (c) the actual goal. A plan can pass per-edit Rule 22 on every edit and still fail systemically if any framework step — Identify, Intake, Criteria, Solutions, Rank, Validate, Execute — was skipped or shortcut at plan-formation time.

**Triggers (plan-level review required):** new features, external surfaces (composes with Rule 33), architecture/structural changes, re-implementations/rewrites/migrations, unfamiliar-domain plans, asymmetric failure cost (irreversible operations, shared state, public-repo content).

**Out of scope:** localized bug fixes, doc-only changes within existing structure, single-edit operations, routine maintenance.

**Marker:** Claude emits a `[Rule 34]` block before the first qualifying edit, formatted the same as Rule 22's per-edit marker but covering the whole plan. Per-edit `[Rule 22]` markers continue to fire after; in-scope edits can briefly reference the plan instead of re-deriving the framework.

### Added — Plan-Level Application section in `change-decision-framework.md`

Documents that Rule 22's framework runs at two scopes: per-edit (hook-enforced via `PreToolUse`/`PostToolUse` on Edit/Write) and per-plan (currently discipline-enforced via Rule 34's `[Rule 34]` marker). Includes plan-level application of all 7 framework steps and clarifies the relationship to ARIA's existing batch-manifest mechanism — batch manifests reduce ceremony *during* execution within a declared scope; Rule 34 validates plan *quality before* execution starts. Distinct axes, complementary in practice.

### Added — Rule 34 enforcement note in `enforcement-mechanisms.md`

Brief paragraph noting Rule 34 currently uses Layer 1 only (CLAUDE.md text + discipline-emitted marker). Hook enforcement deferred pending real-world calibration of trigger heuristics — matches Rule 22's own evolution arc (text first, hooks added once usage data clarified the trigger surface).

### Why this rule now

Same scraping-API origin as Rule 33: an integration was planned, executed cleanly per per-edit Rule 22, and failed on every call due to assumptions that the freely-accessible documentation would have corrected. Rule 33 patches the third-party-API-specific case at the call layer; Rule 34 patches the general plan-formation case at the framework layer. Both Rule 27's model-ID-rename origin and Rule 33's scraping-API origin fit Rule 34's trigger set retroactively, which validated the rule's design before shipping.

### Dogfood note

This release applied Rule 34 to its own creation. The original 8-surface plan (working-rules.md + plugin.json + marketplace.json + CHANGELOG + CLAUDE.md + 2 README refs + Projects/CLAUDE.md) was expanded to 10 surfaces after plan-level intake surfaced two real dependents — `change-decision-framework.md` (cross-reference target of Rule 34's wording) and `enforcement-mechanisms.md` (Rule 34's enforcement state belongs alongside Rule 22's). Without the plan-level review, Rule 34 would have shipped with a silent cross-reference inconsistency to a doc that's per-edit-only. The rule earned its keep on its first run.

### Upgrade notes

- **Reinstall recommended** to pick up Rule 34 in `working-rules.md`, the new section in `change-decision-framework.md`, and the enforcement-mechanisms note. Existing rules 1-33 are unchanged.
- **No config migration.** No new fields, no new hooks (yet), no skill changes.
- **Rule numbering preserved.** Rule numbers remain permanent IDs per the file's "How to Use" directive.

### Maintainer notes

- README.md and CLAUDE.md rule-count references updated from "33 rules" to "34 rules".
- Hook implementation deferred — trigger heuristics need real-world data before mechanism design. Discipline-only ship matches Rule 22's text-first evolution arc.
- Per `feedback_aria_versioning_patch_for_new_skill`: a single isolated rule addition is a patch bump.

## [2.13.3] - 2026-05-02

Patch release adding **Rule 33: Verify third-party surfaces against current docs before use** to the working-rules template. Single isolated rule addition; no skill, hook, or behavior changes.

### Added — Rule 33 in `plugin/template/rules/working-rules.md`

Proactive doc-check rule directing that any third-party API, SDK, library, CLI, or external tool surface be verified against current documentation before the call is written. Defines *current* as fetched-or-read-this-session (not training memory, not analogy, not cached belief). Provides four objective triggers (first-use, version-volatile surfaces, silent-failure-prone calls, project-version-differs-from-training-version), a five-step routing order (local docs → `context7` → official docs → `--help` → ask the user), an explicit out-of-scope clause for language standard library, and a Rule 7 escape hatch when docs are inaccessible.

Composes with **Rule 27** as its proactive counterpart: Rule 27 verifies external identifiers after a failure; Rule 33 verifies before the call.

### Why this rule now

A new scraping API integration in another session produced multiple runtime errors — payload shape, auth, pagination — every one of which was resolved by reading the API documentation after the fact. Reading the docs before writing the integration would have prevented all of them. The rule names this failure mode (trained-knowledge drift + unfamiliar surfaces produce calls that look correct, pass review, and fail at runtime) and routes around it deterministically.

### Upgrade notes

- **Reinstall recommended** to pick up the new rule in `working-rules.md`. Existing rules 1-32 are unchanged.
- **No config migration.** No new fields, no new hooks, no skill changes.
- **Rule numbering preserved.** Rule numbers remain permanent IDs per the file's "How to Use" directive.

### Maintainer notes

- README.md and CLAUDE.md rule-count references updated from "31 rules" to "33 rules" (the count had been stale since Rule 32 added in v2.10.6; v2.13.3 corrects both the previous drift and the current addition).
- Per `feedback_aria_versioning_patch_for_new_skill`: a single isolated rule addition is a patch bump, not a minor.

## [2.13.2] - 2026-04-29

Documentation patch release. Adds three Tier-2 docs (public on the GitHub repo, NOT shipped in the plugin zip) that surface positioning, cross-pollination tracking, and release-validation discipline. **No plugin behavior changes** — `plugin/` is unchanged from v2.13.1, so users running v2.13.1 do not need to reinstall.

### Added — `docs/non-goals.md`

Explicit statement of what aria-knowledge does NOT aim to do, separated into permanently out of scope vs deferred. Helps prospective users self-select before installing, especially given the existence of adjacent execution-first plugins. Includes a pointer to [aria-ex1](https://github.com/nrek/aria-ex1) for users whose fit is execution scaffolding without the personal-knowledge-management surface.

### Added — `docs/related-repo-delta-ledger.md`

Append-only ledger of notable changes from related Claude Code plugin repos (currently aria-ex1), classified IMPORT / OPTIONAL / REJECT / N/A per change. Tracks both directions of cross-pollination — changes adopted from related repos AND changes that originated in aria-knowledge and were adopted downstream. Auditable record of design relationships across versions.

### Added — `docs/release-validation.md`

Pre-release checklist walking each skill, hook, and release-artifact step across eight phases (setup, exploration, capture, audit, lookup, hooks, distill, release artifacts). Catches regressions that `tests/run.sh` doesn't surface — drifted skill prose, renamed commands, broken `/setup` flows on existing config. Codifies the two-commit release pattern (source changes commit → `release.sh` → release artifacts commit → push).

### Why these now

aria-knowledge cross-pollinates with [aria-ex1](https://github.com/nrek/aria-ex1) (a leaner fork). Until v2.13.2 the relationship was implicit; the three new docs make it auditable, help users choose between adjacent plugins, and capture release-validation discipline that's been informal until now. All three docs adopt patterns observed in aria-ex1 v0.1.1 with content fully written from aria-knowledge's perspective.

### Upgrade notes

- **No reinstall required** for users on v2.13.1 — the plugin zip's contents are unchanged.
- **For new installs**, the v2.13.2 zip is functionally identical to v2.13.1's; the version bump exists to give the documentation additions a release reference.
- **Maintainers:** consult `docs/release-validation.md` before tagging the next release. Consult `docs/related-repo-delta-ledger.md` when reviewing changes from aria-ex1 (or future related repos) for adoption.

## [2.13.1] - 2026-04-29

Patch release fixing two real spec gaps surfaced during the first `/audit-share` run on a non-trivial knowledge folder. Both issues caused the v2.13.0 audit-share to silently produce zero shareable candidates on data that should have produced 15+. No config migration; no new fields; backward-compatible with v2.13.0 setups.

### Fixed — Path-derived tag detection (`/audit-share` Step 2)

The v2.13.0 spec required a frontmatter `project:` field for tag detection — but ARIA's actual data model uses `tags:` arrays plus path location under `projects/<tag>/`. `/index` Phase 4 (since v2.8.0) already recognized this via Decision #9 (path-derived tag union); `/audit-share` Step 2 just hadn't picked up the convention.

`/audit-share` Step 2 now derives project tag(s) from three sources, unioned (matches `/index` exactly):
- **Path-derived:** files under `{knowledge_folder}/projects/<tag>/` carry `<tag>` implicitly.
- **Frontmatter `project:` field** if present (multi-value comma-split).
- **Frontmatter `tags:` array:** any tag matching a project in `projects_shared_knowledge` triggers a share recommendation.

Multi-tag files (e.g., a file tagged `[architecture, cs, ss]` with `cs,ss` enabled) generate one share recommendation per matching project — independent destinations per share. This is cross-PROJECT-GROUP relevance, not cross-sub-repo within one group, so it doesn't trigger `cross/` treatment.

### Fixed — Multi-repo destination resolution (`/audit-share` Step 5, `/index` Phase 5, `/setup` folder detection)

The v2.13.0 spec wrote files to `<project-root>/_project-knowledge/` and ran `git add` from that path — assuming `<project-root>` is always a git repo. But `projects_list` paths often resolve to **container directories** that hold multiple sub-repos (e.g., a project group whose sub-repos are `<project-root>/<backend-sub-repo>/`, `<project-root>/<web-sub-repo>/`, `<project-root>/<mobile-sub-repo>/`). When the container isn't a git repo, the v2.13.0 `git add` step silently no-ops; files land in untracked container directories.

`projects_groups` already documents the role:sub-repo mapping per project tag (since v2.9.0, parsed by `/distill` and `/stitch`). v2.13.1 makes `/audit-share`, `/index`, and `/setup` all consult `projects_groups[tag]` when resolving destinations:

- **`/audit-share` Step 2.3 target-path resolution** — single-repo path unchanged. Multi-repo path runs a **role-detection heuristic** on file content + tags (keyword scoring against `backend`, `web`, `mobile`, plus any custom roles): single dominant role → that sub-repo's `_project-knowledge/`; multiple roles or tied scores → **primary sub-repo** (first declared role) `_project-knowledge/cross/`. User can `modify N` in the batch summary to override the recommendation.
- **`/audit-share` Step 5.8 `git add`** — now uses `git -C <sub-repo-root> add ...` to make the working tree explicit; protects against the silent-no-op trap where `git add` from a non-repo container exits cleanly without staging.
- **`/audit-share` Step 7 IDEAS-BACKLOG migration** — multi-repo migration target is `<project-root>/<primary-sub-repo>/_project-knowledge/IDEAS-BACKLOG.md` (always primary, since IDEAS-BACKLOG entries are project-wide queue items, not per-role). Filesystem `mv` from the container, then `git -C <primary-sub-repo-root> add` to stage.
- **`/audit-share` Step 5.5 public-repo flag** — visibility detection scoped per sub-repo (was per-container).
- **`/index` Phase 5** — single-repo scan unchanged. Multi-repo scan iterates `projects_groups[tag]` role:sub-repo pairs and scans each sub-repo's `_project-knowledge/`. The path stored for each entry is absolute-from-home so `/context` can render it correctly; the `project:` annotation is the parent project tag (not the sub-repo name) so cross-sub-repo discovery within a group still groups by project.
- **`/setup` existing-folder detection** — same single-vs-multi branch; multi-repo projects probe each sub-repo independently.

### Why fold these patches together

Both fixes are corrections to the same narrow surface (where do we read from / write to for the team-shared tier) that v2.13.0 shipped with overly narrow assumptions. They share the same `projects_groups[tag]` lookup and the same single-vs-multi-repo branch shape, so fixing them in one release keeps the spec internally consistent across audit-share / /index / /setup.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` (or unzip the v2.13.1 release zip into that directory).
- **Run `/setup` after upgrade** to record `last_setup_version: 2.13.1`. No config field changes from v2.13.0 — `projects_shared_knowledge` (comma-separated tag list) and `author_tag` (string) are unchanged in shape.
- **Backward-compatible with v2.13.0 configs.** Single-repo project setups continue to work identically. Multi-repo project setups (those with `projects_groups[tag]`) now actually function — previously they would silently produce zero shareable candidates and zero indexable team-shared files.

## [2.13.0] - 2026-04-28

Minor release. Adds a third knowledge tier — **Shared Knowledge** — that lets developers promote selected personal knowledge into per-repo `_project-knowledge/` folders so teammates working in the same code repo can find and read it. The personal knowledge tier (`~/Projects/knowledge/`) and project knowledge tier (`projects/{tag}/`) are unchanged; the new tier composes with both. Fully opt-in and **per-project**: the `projects_shared_knowledge` config field is a comma-separated tag list (e.g., `cs,ss`) — empty/missing means feature disabled, populated means enabled for those specific projects only. Most users have many repos but only a few with teams to share with; this avoids accidentally exposing solo projects to a non-existent team-share workflow.

The release also renames the `/audit-knowledge` Accept submenu disposition from `plan` to `backlog` (with corresponding rename of the destination file `PLAN.md` → `IDEAS-BACKLOG.md`) — the `plan` term was overloaded with implementation-plan semantics elsewhere (`docs/plans/`, `superpowers:writing-plans`) and consistently produced confusion about what the destination was for.

### New — `audit-share` skill (alias `share-audit`)

The batch-review surface for promoting personal knowledge to team-shared. Walks `~/Projects/knowledge/insights/`, `decisions/`, `approaches/`, `rules/`, plus IDEAS-BACKLOG.md entries, and recommends a destination per item:

- **Repo-scoped** items (matching a project tag in `projects_list`) → `<project-root>/_project-knowledge/{YYYY-MM-DD}-{author}-{slug}.md`
- **Cross-cutting** items (`project: cross`) → `<project-root>/_project-knowledge/cross/{YYYY-MM-DD}-{author}-{slug}.md` in a user-selected repo
- **Skip** items (no project tag, or types out of scope — `feedback`, `references`)

Presents a numbered batch summary grouped by recommended action; user picks `all`, specific numbers, `modify N` to change action/destination/slug, or `skip`. Public-repo targets get a sanitization warn-prompt before each write. Files are `git add`-ed but not committed — user reviews staged changes and commits through their normal flow.

Frontmatter back-pointers maintain provenance both directions: personal copies gain a `shared:` array entry pointing at where each share landed; team copies carry `origin:`, `shared_by:`, and `shared_at:` fields naming the source.

### New — `_project-knowledge/` folder convention

Each project repo where the user has shared knowledge gains a conventional folder:

```
<project-root>/
└── _project-knowledge/
    ├── README.md                           (auto-created on first share — convention explainer for non-ARIA teammates)
    ├── IDEAS-BACKLOG.md                    (idea queue moves here when feature enabled)
    ├── {YYYY-MM-DD}-{author}-{slug}.md     (repo-scoped knowledge)
    └── cross/                              (cross-cutting items)
        ├── IDEAS-BACKLOG.md
        └── {YYYY-MM-DD}-{author}-{slug}.md
```

Folder name `_project-knowledge/` — leading underscore sorts to top of repo listings; NOT hidden; tool-agnostic so non-ARIA teammates can read/write the markdown directly.

### New — `/index` Phase 5 + `/context` "Team-shared" grouping

Read-side aggregation — no STITCH integration needed:

- `/index` gains a new scan phase that walks each project's `_project-knowledge/` folder and adds entries to a new `## Team-Shared Tag Index` section in `index.md`. Path-derived metadata (`project: <tag>`, `scope: repo|cross`) is preserved as annotation.
- `/context` reads the new section in Step 4c and groups results in Step 5 as **Team-shared → Project-specific → Cross-project** (continuous numbering across all three).

Tag-based discovery works seamlessly — a query like `/context api` surfaces team-shared `api` files alongside personal/project results. No new STITCH file format; no new query syntax.

### New — `/setup` integration

After Project Setup completes, `/setup` asks two follow-up questions when projects tier is enabled:

1. *"Which projects do you want to enable shared knowledge for?"* — sets `projects_shared_knowledge` to a comma-separated tag list (or empty for disabled); each tag must already exist in `projects_list`
2. *"Author tag for shared-knowledge filenames?"* — sets `author_tag: <string>` (falls back to deriving from `git config user.name`)

Followed by an offer to invoke `/audit-share` inline as the cold-start sweep.

The CLAUDE.md reference offer (a 5-line "Team-Shared Knowledge" section pointing teammates at the convention) lives inside `/audit-share` Step 6.5 rather than at setup time. It fires the first time `audit-share` actually writes to a repo's `_project-knowledge/` folder — at that moment the folder + README exist (no aspirational forward reference), the user has just made an active sharing decision, and the prompt can carry per-repo confirmation with git-tracked detection and three warning tiers (public remote / private remote / unknown). Default is `N` regardless of tier; idempotency check skips the prompt on subsequent shares to repos that already have the reference.

For multi-repo projects (those with a `projects_groups` entry), Step 6.5b runs after the sub-repo offer to additionally surface the **container's** CLAUDE.md with a group-aware text variant. The container variant references each sub-repo's `_project-knowledge/` folder by name rather than describing a non-existent `<container>/_project-knowledge/`. Same per-file confirmation, default-N posture, and three-tier warning system as 6.5a. A session-level cache prevents re-prompting when subsequent shares hit sibling sub-repos within the same `audit-share` invocation; idempotency at the file level (existing-heading probe) prevents duplicate appends across runs.

### Changed — `/audit-knowledge` Accept submenu disposition `plan` → `backlog`

The previous `plan` disposition wrote to `plans/{slug}.md` (or `PLAN.md`) with `## Goal`/`## Why` headers — overloading the `plan` term with execution-plan semantics that already had separate homes (`docs/plans/`, `superpowers:writing-plans` output). Renamed to `backlog` with destination `IDEAS-BACKLOG.md` at the project-root path; treats the destination as a queue (dated entries) rather than a sequenced execution doc.

When the project's tag appears in `projects_shared_knowledge`, the destination shifts to `<project-root>/_project-knowledge/IDEAS-BACKLOG.md` (team-visible); migration of existing project-root `IDEAS-BACKLOG.md` files happens on first `/audit-share` invocation. Projects whose tags are NOT in `projects_shared_knowledge` keep IDEAS-BACKLOG.md at the project root (personal-tier behavior unchanged).

16 surfaces across 7 files updated for terminology consistency: `audit-knowledge/SKILL.md`, `template/intake/ideas/README.md`, `template/OVERVIEW.md`, `template/README.md`, `QUICKSTART.md`, `extract/SKILL.md`, `audit-config/SKILL.md`. The previous `audit-config` Step 5 PLAN.md alignment check (now obsolete under queue semantics) replaced with an IDEAS-BACKLOG.md presence check.

### Changed — `/setup` Step 8 summary surfaces shared-knowledge status

Adds one bullet to the post-setup confirmation: *"Shared knowledge: enabled (author_tag: {tag}) | disabled (opt-in via re-run /setup)"*.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` (or unzip the v2.13.0 release zip into that directory).
- **Run `/setup` after upgrade** to record `last_setup_version: 2.13.0` and (optionally) opt into the new Shared Knowledge tier. The two new config fields (`projects_shared_knowledge`, `author_tag`) are introduced as `[NEW]` markers in the advanced-options bundle on re-run.
- **Backward-compatible defaults.** `projects_shared_knowledge` defaults to empty (feature disabled, no projects enabled); existing users who don't opt in see no behavior change. A legacy literal `true` from any pre-publish v2.13.0 stub is treated the same as empty and triggers `/setup` to populate the list properly on next run. The `plan → backlog` disposition rename is also backward-compatible — the new disposition keyword `backlog` is recognized; users with existing IDEAS-BACKLOG.md files at project-root continue to work.
- **No config migration required.** Existing configs (with or without `projects_groups`, with or without project tier enabled) work unchanged.

## [2.12.2] - 2026-04-26

Patch release. Closes a long-standing documentation gap around `projects_groups`, the multi-line YAML field consumed by `/distill` and `/stitch` for multi-repo group mapping. Until now the field was documented only inline in the two consuming skills' shared-block, with no single-page schema reference and no `/setup` awareness — users running `/setup` got no signal that the field existed in their config, and users hand-editing `~/.claude/aria-knowledge.local.md` had no canonical place to look for the schema. v2.12.2 adds a dedicated `CONFIG.md` reference covering all 18 frontmatter fields plus the skill-only tier, and extends `/setup` with read-only awareness so re-runs surface existing groups and link to the schema.

### New — `plugin/CONFIG.md` configuration schema reference

A single-page reference documenting every field in `~/.claude/aria-knowledge.local.md`:

- **Two parser tiers** — explicit framing of the hook-parsed (column-1, grep+sed-safe) versus skill-only (multi-line YAML, parsed by Claude in skill context) split per ADR 028. Helps users understand why some fields fit the `/setup` advanced-options bundle and others don't.
- **Hook-parsed table** — all 18 single-line fields with type, default, and which hook or skill reads them.
- **Skill-only schema** — `projects_groups` block structure with standard role names (`backend`, `web`, `mobile`), custom-role conventions, and the optional `stitch_path` sub-field per ADR 034.
- **Format rules and hand-editing checklist** — the same parser invariants that have been embedded in the `/setup` SKILL Step 7 formatting block, surfaced here for users who edit the config directly without running `/setup`.

Cross-linked from `QUICKSTART.md`, `setup` SKILL Step 6, and the `<!-- shared-block: group-loader -->` opening line in both `distill` and `stitch` SKILL.md.

### Changed — `/setup` awareness for skill-only fields

Four touch-points in `setup` SKILL extended to surface `projects_groups` without trying to flatten or interactively edit it:

- **Step 1** — when an existing config is detected, also detect the `projects_groups` block and report current group count alongside the standard "already configured" announcement. Uses an awk pattern bounded by the closing frontmatter delimiter so it can't escape the block.
- **Step 6** — new "Skill-only fields (read-only awareness)" subsection below the advanced-options bundle. Restates the current group count if Step 1 detected it, or describes how `/distill --group=<tag>` and `/stitch create <tag>` auto-populate the field via their existing bootstrap (ADR 032). Explicit that `/setup` never writes new entries here.
- **Step 7** — two new formatting rules: skill-only multi-line YAML blocks must sit at the end of the frontmatter (after every column-1 hook-parsed key), and the block must be preserved verbatim in update mode (no reformatting, no reordering, no sub-entry stripping).
- **Step 7b** — three structural validation checks for `projects_groups`: block placement (must be last), indentation shape (2-space tag, 4-space role), and tag cross-check against `projects_list` (warn, do not fail — staging tags before path-mapping is a legitimate pattern).

### Changed — `distill` and `stitch` shared-block cite `CONFIG.md`

The opening line of the `<!-- shared-block: group-loader -->` block in both `distill/SKILL.md` and `stitch/SKILL.md` now references `CONFIG.md` "Skill-only fields" as the canonical schema reference, including the optional `stitch_path` sub-field and custom-role conventions. The shared-block remains the operational specification (what the skill does at runtime); `CONFIG.md` is the schema reference (what valid input looks like).

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` (or unzip the v2.12.2 release zip into that directory).
- **Run `/setup` after upgrade** to record `last_setup_version: 2.12.2` and surface the new Step 1 group-count detection if you have `projects_groups` configured.
- **No breaking changes.** `projects_groups` schema is unchanged from prior versions; the auto-propose bootstrap in `/distill` and `/stitch` continues to work identically. No new config keys; no existing config keys changed shape; no skill behaviors changed beyond `setup` awareness.
- **No config migration required.** Existing configs (with or without `projects_groups`) work unchanged.

## [2.12.1] - 2026-04-26

Patch release. Closes a version-awareness gap: existing users who upgrade ARIA between 30-day setup-cadence windows currently see no prompt to re-run `/setup`, so template diffs and any new config keys land silently until either the cadence fires or the user notices independently. v2.12.1 adds an immediate version-mismatch prompt at session start and surfaces the running ARIA version inside `/setup` itself so users always know which version configured their knowledge folder.

### New — `last_setup_version` config field

`/setup` now records the plugin version active at the time of the run as a YAML frontmatter field in `~/.claude/aria-knowledge.local.md`:

```yaml
last_setup_version: 2.12.1
```

Read at Step 1 from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` via the same grep+sed pattern as every other config field (no jq dependency added). Written at Step 7 alongside the other config keys. Verified at Step 7b for semver shape and round-trip match against the Step 1 capture. Format rules: bare digits-and-dots, no `v` prefix, no quotes — matches the parser invariant for the rest of the frontmatter.

### New — version-mismatch prompt at session start

`bin/session-start-check.sh` now compares the installed plugin version against `last_setup_version` from config. When they differ:

> *"ARIA was updated (last /setup ran on v{old}, plugin is now v{new}). Run /setup to apply template diffs and surface any new config keys?"*

Three guards keep the prompt silent in non-upgrade cases: installed version must be parseable from `plugin.json`, `last_setup_version` must be present in config (so fresh installs and pre-2.12.1 users don't trigger), and the two strings must differ. The existing 30-day cadence prompt becomes the fallback — it only fires when the version-mismatch prompt did not, so users never see two competing update prompts in one session.

### Changed — `/setup` displays the ARIA version

Three surfaces in `setup` SKILL now show the version:

- **Step 1 announcement:** *"aria-knowledge v{version} is already configured"* (existing config) or *"Let's set up aria-knowledge v{version}"* (fresh install). When the recorded `last_setup_version` differs from the installed version, an additional line surfaces: *"Plugin upgraded from v{X} → v{Y} since last setup. Diff prompts and any new config keys will surface in the steps below."*
- **Step 8 summary:** the `Setup complete!` header becomes `Setup complete for ARIA v{version}.` so users see what they configured.
- **Step 7 frontmatter write:** `last_setup_version` is recorded so the next session-start hook has the data it needs to detect the next upgrade.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` (or unzip the v2.12.1 release zip into that directory).
- **Run `/setup` once after upgrade.** This populates `last_setup_version` in your config so the next plugin upgrade triggers the new prompt. Until then, existing v2.12.0 users still see the time-based cadence prompt as before — the version-mismatch prompt is silent without `last_setup_version` in config.
- **No breaking changes.** The session-start hook's existing 30-day cadence check is preserved as a fallback for users who haven't yet recorded `last_setup_version`. No existing config keys changed shape; no existing skills changed behavior beyond `setup`.
- **No config migration required.** Existing configs work unchanged. The new key is added on the next `/setup` run.

## [2.12.0] - 2026-04-26

Minor release. Expands the idea-disposition vocabulary in `/audit-knowledge` from a single Accept verb (which previously only meant "copy to external tracker") to a seven-destination submenu: `tracker | roadmap | todo | adr | plan | bundle | rule`. Adds a new `intake/rules-backlog.md` artifact to receive the `rule` path. Adds a `ticketing_plugins` config key so the audit can hint at user-installed ticket-drafting plugins per project tag without coupling ARIA to any specific plugin name. Adds detection probes that surface `roadmap` / `todo` only when the relevant file exists at the project root or under `docs/`. Adds bundle auto-clustering when the audit detects 2+ ideas sharing project tag and ≥2 significant title words. No behavior changes for existing knowledge backlogs (insights/decisions/extraction); existing single-Accept disposition still works as `Accept → tracker` (the new default).

### Why this matters

The single-Accept-to-tracker model assumed every actionable idea belonged in an external issue tracker. In practice many ideas are too small for tickets (TODO line), too coarse for tickets (roadmap entry), too principled for tickets (working-rule), or actually decisions in disguise (ADR candidate). The new submenu lets each idea route to the surface that fits its weight, while preserving the routes-out-not-promotes invariant — `adr` and `rule` paths land in their respective backlogs for normal audit-cycle review, not directly in `decisions/` or `rules/`.

### New — Accept submenu in `/audit-knowledge`

Step 2c2 expanded with the seven-destination spec. Step 6 Pending Ideas presentation now uses a two-step prompt (top-level Accept/Reject/Defer/Reclassify; Accept submenu computed per idea). Submenu items are conditional:

- `tracker | adr | plan | rule` — always available.
- `roadmap` — only if `ROADMAP.md` exists at the idea's project root (closest ancestor with `.git/` or `CLAUDE.md`) or under that root's `docs/`.
- `todo` — same probe pattern for `TODO.md`.
- `bundle` — only when the audit detects a cluster (same project tag + ≥2 shared significant title words across 2+ pending ideas).

Routing behavior per destination is documented in the SKILL Step 2c2 table and mirrored in `intake/ideas/README.md`.

### New — `intake/rules-backlog.md` artifact

Mirrors the shape of `decisions-backlog.md` but for rule candidates — observations or proposals about *how to work* (rather than *what is*). Populated three ways: via the `Accept → rule` path during idea audits, via `/extract` when conversation surfaces a repeating discipline, or by manual append. Reviewed in `/audit-knowledge` Step 2c3 with three valid promotion targets — all inside the user memory directory or `{knowledge_folder}` (ARIA never writes to project source):

- **User memory** — write `feedback_*.md` under the active project's `~/.claude/projects/{cwd-encoded}/memory/` directory (matches existing feedback-memory pattern).
- **Cross-project ARIA rule** — append to `{knowledge_folder}/rules/user-rules.md` (user-owned counterpart to plugin-managed `working-rules.md`).
- **Project-tier working rule** (projects tier only) — append to `{knowledge_folder}/projects/{tag}/rules/working-rules.md`. Setup's Step 7c scaffolds the parent `rules/` subdirectory under each configured project so this destination is always available when the projects tier is enabled.

Rejected entries clear from the backlog. The new file is registered in `setup` SKILL Step 3 expected-files list and Step 4 never-diff list (user-owned).

### New — `ticketing_plugins` config key

User-declared registry mapping project tags to ticket-drafting plugin commands (e.g., `proj-a:foo-ticket,proj-b:bar-ticket`). Format mirrors `projects_list` so the existing pure-grep/sed config parser handles it without `bin/config.sh` changes. When set, `/audit-knowledge` prints a one-line hint during `Accept → tracker` disposition (e.g., *"Use `/foo-ticket` to draft this as a ticket"*) for ideas whose project matches a mapped tag. Hint only — never auto-invokes the other plugin's skill (preserves consent and avoids cross-plugin coupling). Empty default; users who don't use a ticketing plugin or prefer manual tracker copy-paste leave it empty.

`setup` SKILL extended at four surfaces: Step 6 Advanced Options (now always shown — see "Advanced Options now unconditional" below), Step 7 frontmatter write, Step 7 formatting rules, and Step 7b round-trip + empty-sentinel verification. The advanced-options bullet for `ticketing_plugins` carries inline validation rules (each pair has exactly one `:`, tags reject `:`/`,`, plugin commands strip leading `/` with a warning). Step 8 summary line confirms the disposition (configured count or empty default). Plugin tags follow the same `:`/`,` exclusion as `projects_list`; plugin-command values must be bare command names without leading `/` (the audit prepends the slash when printing the hint).

### Changed — `/stats` and `/backlog` now read four backlogs

Both skills updated to include `intake/rules-backlog.md` alongside insights/decisions/extraction:

- `/stats` Intake section gains a `Pending rules: N` line.
- `/backlog` overview emits a Rules row; `/backlog rules` opens the detail view; `/backlog clear rules YYYY-MM-DD` clears entries by date.
- `/audit-knowledge` Step 1 backlog-count loop includes rules-backlog so the entry-count trigger threshold (default 20) accounts for rule candidates too.

Audit-log fields in Step 8 now break out per-destination counts (`accepted: A1 tracker / A2 roadmap / ... / A7 rule`) and add `R rules reviewed` to the Counts line. Zero-valued sub-counts are omitted to keep entries readable.

### Changed — `ideas_staleness_threshold_days` default lowered 21 → 7

Pending ideas under the staleness threshold auto-defer (no per-entry prompt) per Step 6's existing rule. At the 21-day default, modest-volume idea capture from `/extract` could silently accumulate for three weeks before any forced engagement, and high-volume capture (the migration brought 188 entries onto a single user's machine in this release) compounds that. Lowering the default to 7 days aligns staleness pressure with the existing knowledge audit cadence (`audit_cadence_knowledge: 7` default) — every safety-net audit cycle now finds at least one tier of ideas eligible for forced disposition. Trade-off: fresh ideas captured today get nagged within a week. For users who prefer the old behavior, set `ideas_staleness_threshold_days: 21` (or any other integer) in `~/.claude/aria-knowledge.local.md`.

Surfaces touched: `setup` SKILL Step 6 advanced-options prompt + Step 7 frontmatter default; `audit-knowledge` SKILL Step 2c2 + Step 6 default-mentions; `context` SKILL `KT_IDEAS_STALENESS_DAYS` default and fallback; `intake/ideas/README.md` staleness paragraph. Existing user configs retain whatever value they had — the source default change only affects new installs that use empty advanced-options answers.

### Changed — Advanced Options now unconditional + new-key highlighting

`setup` SKILL Step 6 Advanced Options previously rendered only when the user explicitly asked for it OR re-ran setup with an existing config. Fresh installs that didn't ask got the entire bundle silently (defaults applied without surfacing what was tunable). With the bundle now containing settings whose right values depend on user landscape — `ticketing_plugins`, `critical_paths`, `ideas_staleness_threshold_days` — silent defaults misfire often enough that the gate was costing users more than it saved.

**New behavior:** the Advanced Options bundle is shown on every `/setup` run, fresh or re-run. New users see what's tunable up front; returning users get a chance to surface and adjust values they didn't configure initially. Auto-mode users still get the bundle and can press enter to accept defaults — the difference is that the no-op is now an explicit choice rather than a silent skip.

**New-key highlighting (re-runs only):** before rendering the bundle, `setup` runs `grep -q '^{key}:'` against the existing config for each Advanced Option key. Any key missing from the user's config (an upgrade case where a plugin update added the key) gets a `[NEW]` annotation in the bundle and a one-line preamble note: *"Some settings are new since your last `/setup` run — `[NEW]` markers below indicate keys added by plugin updates that aren't yet in your config. Consider whether to set them now."* Fresh installs skip the comparison since there's no prior config — bundle just renders defaults.

**Step 6b removed.** The original v2.12.0 design added Step 6b as a focused y/n for `ticketing_plugins` to escape the gate. With the gate gone, Step 6b became redundant — the always-on bundle subsumes its purpose. Its missing-key detection and inline validation rules survived; they now live in the always-on Advanced Options bundle directly. No regression for `ticketing_plugins` setup: upgraders still see it flagged `[NEW]` and can populate it from the bundle.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` to pick up the SKILL changes, the new template artifact, and the version bump.
- **Run `/setup` to land `intake/rules-backlog.md`** in your knowledge folder. Existing folders won't get the file automatically — `/setup` adds missing files in update mode without overwriting anything else. Until then, `/audit-knowledge` will report the missing file with a "run /setup to repair" note.
- **`ticketing_plugins` surfaced via the always-on Advanced Options bundle.** Every `/setup` run (fresh install or re-run) shows the bundle; on re-runs, keys missing from the existing config are flagged `[NEW]` so upgraders see what the plugin update added. To set a value: type the comma-separated mapping (e.g., `proj-a:foo-ticket,proj-b:bar-ticket`) when prompted, or press enter to keep the current value/default. Plugin commands are bare names (no leading `/`); leading `/` is stripped automatically with a warning.
- **No behavior change for existing dispositions.** A user choosing `Accept` and not picking a submenu destination receives a follow-up prompt — there's no implicit default. Older `Accept → tracker` muscle memory still works since it remains an explicit option.
- **Public-repo discipline preserved.** No project-specific plugin names ship in templates, SKILLs, or the manifest. Examples in docs use generic placeholders (`proj-a:foo-ticket`).
- **Backward compatible audit-log entries.** Pre-2.12.0 entries kept the old four-option Ideas-disposition shape (`A accepted → tracker, B rejected, C deferred, D reclassified`); these remain valid and don't need rewriting. New entries use the seven-destination breakdown.

## [2.11.2] - 2026-04-24

Patch release. Adds `/snapshot`, an on-demand equivalent of the pre-compact transcript capture hook. Until now the only way to archive a raw session transcript was to wait for Claude Code's PreCompact event — a useful safety net, but not a control the user can reach for mid-session before switching context or kicking off a risky operation. `/snapshot` closes that gap by reusing the hook's archival contract under explicit user invocation.

### New — `/snapshot` skill

`plugin/skills/snapshot/SKILL.md` registers the command. The skill is a thin wrapper: it delegates to `bin/save-transcript.sh` and relays the output verbatim. Description triggers include `/snapshot`, "snapshot the session", "save this conversation", "archive this session", and explicitly contrasts with `/extract` (knowledge synthesis) and `/clip` (URL or snippet capture) so the LLM routes cleanly between the three. `allowed-tools: Bash`.

Also registered in `/help`: row added to the commands table and to the Sonnet-low-effort row of the model-recommendations table. `/snapshot` is mechanical (bash-script-driven), so Sonnet is the right default — no judgment lift from a larger model.

### New — `bin/save-transcript.sh` helper

Mirrors the archival logic of `pre-compact-check.sh` with three differences driven by the on-demand context:

- **Bypasses `KT_AUTO_CAPTURE`.** The config key's name scopes it to hook-driven auto capture; explicit `/snapshot` always runs. Honoring the gate would silently refuse an explicit command, which is worse UX than violating the (auto-scoped) flag.
- **Discovers the transcript instead of receiving it.** The hook gets `session_id` and `transcript_path` via stdin JSON. A skill-invoked shell has neither. The script finds the current session's transcript by picking the most recently modified `*.jsonl` under `~/.claude/projects` using fractional-second mtime (`stat -f "%Fm"`), which disambiguates concurrent Claude Code windows that `ls -t`'s second granularity cannot.
- **Writes to the same captures directory.** Snapshots land in `intake/pre-compact-captures/{YYYY-MM-DD}_{sid8}.md` — same filename convention and same folder as the hook, so `/extract` and audit review pick them up without change.

Same-session repeats overwrite (matches hook behavior — filename is determined by date + session-id-short).

### Changed — SessionStart hook surfaces codemap staleness

`bin/session-start-check.sh` now annotates each `CODEMAP.md` found under cwd with age, git-activity count, and staleness classification (current / possibly stale / stale) — previously it only listed the paths. Classification mirrors `/audit-knowledge` Step 5d exactly:

- **Stale** — `>30 days` since last update AND `>0` files changed
- **Possibly stale** — `>14 days` since last update AND `>20` files changed
- **Current** — otherwise

Header parse looks for `> Last updated: YYYY-MM-DD | …`; falls back to file mtime when the header is missing. Activity count runs `git log --name-only --since="$CM_DATE"` from the codemap's directory — multi-repo parent folders (where the parent dir isn't itself a git repo) report 0 files changed, matching the same limitation as `/audit-knowledge` Step 5d. Guarded on `command -v git` so the hook degrades gracefully when git isn't installed. Head-5 cap on codemap count preserved. Bash-side cost is well under the hook's 10s timeout.

The goal is cheap visibility: users now see staleness classifications at session start without having to run a full `/audit-knowledge`. The audit remains the canonical classifier — session-start just mirrors its logic so the two surfaces agree.

### Changed — `/stats` dashboard adds Codemap Status section

`skills/stats/SKILL.md` gains a new Step 3a that globs for `CODEMAP.md` files under cwd (depth 0-2), parses the `Last updated` header, and reports date + days-since per codemap. The new `### Codemap Status` section renders between `### Audit Status` and `### Index Health` in the dashboard output. Frontmatter description updated to include "codemap dates" in the metric list.

Presentation-only: `/stats` reports the raw date; classification and git-activity checks remain with `/audit-knowledge` Step 5d. This keeps `/stats`'s read-only posture and its "fast — just counting and date parsing, no heavy analysis" rule intact — no Bash added to allowed-tools.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` to pick up the new skill, helper script, and hook changes.
- **No config migration.** No hook contract changes. No behavior changes for existing skills beyond the additive surfaces.
- **macOS-only.** Three BSD-specific constructs: `stat -f "%Fm"` (save-transcript.sh fractional mtime), `stat -f "%Sm" -t "%Y-%m-%d"` (session-start codemap mtime fallback), and `date -j -f "%Y-%m-%d"` (session-start epoch math). A Linux port would need `stat -c "%.Y"`, `date -r $(stat -c %Y …) +%Y-%m-%d`, and `date -d "$date" +%s` respectively. Matches the rest of the shipped hooks.
- **Concurrent-session disclaimer (snapshot).** If two or more Claude Code windows are active on the same machine, `/snapshot` picks the most-recently-written transcript, which is usually but not always the invoking window. The source path is shown in the output so users can verify at a glance.
- **Multi-repo codemap limitation (session-start).** Codemaps at the root of a parent folder that contains sub-repos but isn't itself a git repo report 0 files changed — `git log` runs from the codemap's directory and returns empty for non-git paths. Classification will read as "current" regardless of sub-repo activity. Same limitation as `/audit-knowledge` Step 5d today; a future enhancement could recurse into sub-repos.

## [2.11.1] - 2026-04-24

Patch release. Reduces Rule 22 compliance-block verbosity under Claude Opus 4.7 without weakening the forcing function. Driven by observation that 4.7 fills open-ended slot placeholders more expansively than 4.5/4.6 did, multiplied by ARIA's per-edit emission frequency. No hook, regex, doctrine, or enforcement-mechanism changes — the shift is entirely in the template examples and in a single template slot that was duplicating work the pre-edit block already performed.

### Changed — Post-Edit PASS templates collapse to secondary-status clause

Both tiers (High Impact and Low Impact) now use `[Rule 22 · Scope] PASS — [secondary status: none / what was reviewed]` as the pass-format template. Previously the placeholder was `[what was done + why it passes, including secondary status]` — which invited Claude to restate the plan that the pre-edit block had already established. The revised slot keeps the Q5 secondary-impact check visible (which is the post-edit hook's primary discipline) while dropping the "what was done" restatement. This is the biggest per-session saver because post-edit PASS fires on the majority of successful edits. The `pass with secondary` and `fail` templates are unchanged.

### Changed — 10 examples tightened to one-clause grain

All 10 worked examples in `rules/change-decision-framework.md` rewritten to one-clause slot fills. Slot structure, marker format, and decision sequence are unchanged — only the prose inside each slot is compressed. 4.7 length-matches example grain aggressively, so tightening the examples is the lowest-risk behavioral lever: no doctrine added, no placeholder syntax changed, no hook logic touched. Worked examples affected: High pre-edit pass/flag, High post-edit pass/pass-with-secondary/fail, Low pre-edit pass/flag, Low post-edit pass/pass-with-secondary/fail.

### Mechanism preserved

- Marker regex `\[Rule 22(\s·\s[^\]]+)?\]` unchanged — legacy longer blocks from in-flight sessions still validate.
- Slot structure (Change/Intake/Criteria/Solutions/Rank/Validate/Execute for High; Change/Solutions/Execute for Low) unchanged.
- Ordering discipline, Rationalizations-that-do-not-apply doctrine, batch-manifest variants, Planning variant, Reference-Based Builds — all unchanged.
- Post-edit 5-question scope check unchanged; the compressed PASS template surfaces Q5's result inline rather than restating Q1-Q4.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` to pick up the framework-doc changes.
- **Template diff on `/setup`:** `rules/change-decision-framework.md` has example-grain changes and two template-slot changes. Accept to adopt the tighter grain; decline to keep your customized local copy.
- **No config migration.** No hook changes. No behavior changes beyond what Claude emits in Rule 22 blocks.
- **Backward compatible:** older sessions mid-way through longer emissions continue to pass the marker regex unchanged.

## [2.11.0] - 2026-04-21

Minor release. Splits the ideas backlog from a single `intake/ideas-backlog.md` file to per-file storage under `intake/ideas/`. Driven by three observed pain points in the single-file design: (a) `ideas-backlog.md` crossed the Read tool's 25k-token context limit (~1200 lines in production), forcing offset/limit workarounds during audits; (b) "Pattern 21" drift between audit passes — entries logically cleared but physically still in place — was a recurring hygiene burden that only existed because of single-file semantics; (c) HTML-comment cleared-history markers accrued metadata in the content layer that already lived in `logs/knowledge-audit-log.md`. This release moves ideas to one markdown file per idea with YAML frontmatter, glob-driven reads, and delete-on-disposition semantics. Single-file format is retained for `insights-backlog.md`, `decisions-backlog.md`, and `extraction-backlog.md` — those backlogs stay under the threshold because they're cleared every 3-day audit cycle.

### New — `intake/ideas/` directory with per-file storage

Ideas now live as individual markdown files under `intake/ideas/` with the naming pattern `{YYYY-MM-DD}-{project}-{slug}.md`. Each file has YAML frontmatter (`date`, `project`, `type`, `title`) followed by the body (`**Proposal:**`, `**Motivation:**`, `**Source:**`). Filename collisions are handled by appending `-2`, `-3`, etc. The new `template/intake/ideas/README.md` documents the format, disposition flow (Accept/Reject/Defer/Reclassify with file-delete semantics), and migration path from pre-2.11 installations.

### Changed — `/extract` writes new files instead of appending

Step 4's "Ideas" section now writes one file per idea to `intake/ideas/` with frontmatter-first format. Step 1's timestamp-detection uses the date prefix of the most recent `*.md` file in the directory; Step 3's dedup loop globs `intake/ideas/*.md`. Step 5's summary line updated from "appended to ideas-backlog.md" to "written to intake/ideas/". If a legacy `ideas-backlog.md` is detected alongside the new directory, Step 5 surfaces a one-line migration pointer (but never attempts the migration from within `/extract` — that's `/setup`'s job).

### Changed — `/audit-knowledge` globs the directory

Step 2c2 "Review Ideas Directory" replaces "Review Ideas Backlog": globs `intake/ideas/*.md`, reads frontmatter for staleness computation (falls back to filename date prefix if frontmatter is missing), and surfaces Accept/Reject/Reclassify as file-delete operations. Git history becomes the audit trail — disposition notes still go to `knowledge-audit-log.md`, but the HTML-comment cleared-history pattern in the content file is retired. Legacy-file detection added: if `intake/ideas-backlog.md` exists alongside `intake/ideas/`, surface a "Legacy Ideas Backlog" finding in Step 6 with a migration pointer.

### Changed — `/context` reads frontmatter for project-scoped ideas

The "Pending Ideas surfacing" block in Step 5 now globs `intake/ideas/*.md` and filters by the frontmatter `project:` field rather than parsing entry headers from a single file. Staleness uses frontmatter `date:` with filename-prefix fallback. Multi-project entries (`project: aria,cross`) appear under each matching project query. Legacy-file detection surfaces a one-line informational note.

### New — `/setup` Step 3b: Legacy `ideas-backlog.md` Detection

Inserted between Step 3 (structure validation) and Step 4 (file diffing). Counts active entries in any legacy `ideas-backlog.md` and prompts the user with three options: migrate now (runs `bin/migrate-ideas-backlog.sh`), skip for this run (prompts again next time), or never migrate (writes a `.legacy-skipped` sentinel that suppresses future prompts). Empty legacy files are handled separately (offer to delete). This is the catch-net that ensures upgrading users see the migration path on their first post-upgrade `/setup` without an active prompt on every `/extract`.

### New — `bin/migrate-ideas-backlog.sh` one-shot migration script

Takes an optional knowledge-folder argument (falls back to config lookup). Parses `intake/ideas-backlog.md`, strips HTML comment blocks (cleared-history markers — information already lives in `logs/knowledge-audit-log.md`), splits on `^### YYYY-MM-DD — ` headers, emits one file per entry with generated frontmatter. Title extracted from header; `type` extracted from `**Type:**` body line (normalized to one of `feature|bug|design|refactor|workflow`, defaults to `feature` on missing/unparseable). Filename collisions resolved with `-2`, `-3`, ... up to 99. On success, renames the original to `ideas-backlog.md.pre-2.11-migration` (preserves rollback). Bash wrapper around embedded python3 heredoc, matching the `pre-edit-check.sh` pattern.

### Changed — template and doc updates

- `template/README.md` tree diagram: `ideas-backlog.md` line replaced with `ideas/` directory line.
- `template/OVERVIEW.md`: three references updated — the "Ideas Backlog" flow description (with migration pointer), the user-owned files paragraph, and the Batch Manifests future-consumer mention.
- `template/rules/user-rules.md`: "What Belongs Here vs ideas-backlog.md" section heading, feature-proposal bullet, and auto-routing paragraph all updated to reference `intake/ideas/`.
- `template/rules/change-decision-framework.md`: "If a rationalization seems novel" paragraph updated to file new escape-hatch requests in `intake/ideas/`.
- `template/intake/ideas-backlog.md` deleted from the shipped template; `template/intake/ideas/README.md` added.
- `bin/session-start-check.sh`: comment at line 82 updated to reference `intake/ideas/` terminology; shell logic unchanged (ideas were already excluded from the audit-eligible count).

### Retained — single-file format for other backlogs

`insights-backlog.md`, `decisions-backlog.md`, and `extraction-backlog.md` remain single-file. These are promotion-eligible and cleared on every 3-day audit cycle, so they stay under the size threshold where single-file semantics are fine. Only `ideas-backlog.md` had the retention profile (longest shelf life + largest entries + external-tracker destination rather than in-tree promotion) that crossed the threshold. If any of the other backlogs cross the threshold later, the same per-file split is available as a precedent.

### Fixed — `/help` commands table now lists `/codemap` and `/wrapup`

Both skills were referenced in the Model Recommendations table below but absent from the Commands table — an internal inconsistency within `/help`'s own output. Added `/codemap [mode]` grouped with the other mapping skills (`/distill`, `/stitch`) and `/wrapup` immediately before `/help` as the session-end meta. No behavior change; reference-doc sync only.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` to pick up the skill and template changes.
- **Migration:** run `bash ${CLAUDE_PLUGIN_ROOT}/bin/migrate-ideas-backlog.sh` or re-run `/setup` (Step 3b will prompt). Migration preserves the original file as `ideas-backlog.md.pre-2.11-migration` — nothing is deleted.
- **Template diffs on `/setup`:** the plugin-managed template files (`README.md`, `OVERVIEW.md`, `rules/change-decision-framework.md`) have minor wording updates for the new terminology. Accept to take the v2.11 language; decline to keep customized local copies.
- **User-owned additions:** `intake/ideas/README.md` is classified user-owned (consistent with other directory README stubs) and will not diff on future `/setup` runs. Customize freely.
- **No action needed if your backlog was empty:** fresh installs create `intake/ideas/` directly; no legacy file to migrate.

## [2.10.6] - 2026-04-20

Patch release. Resolves a structural deadlock introduced in v2.10.5 under Claude Opus 4.7: the PreToolUse compliance scanner assumed text and tool_use blocks co-locate in a single assistant message, but 4.7's harness splits them into separate messages, causing every Edit/Write to deny. Diagnosed in a 2026-04-20 session via statistical tally of 51 assistant messages (zero text+tool_use co-location). v2.10.6 replaces same-message scan with turn-scoped walk-back bounded by the previous Edit/Write tool_use or user message — preserves per-edit marker requirement, aligns implementation with the framework doc's "same assistant turn" language. Also bundles four supporting fixes, a new rule (32), and the first test infrastructure for hook contracts.

### Changed â `plugin/bin/pre-edit-check.sh` turn-scoped scanner

The embedded python scanner now walks backward through assistant messages, collecting text blocks until encountering either a previous Edit/Write tool_use (which caps the walk and clears collected blocks from before that cap) or a user message (turn boundary). The walk also handles a prior Edit/Write in the target tool_use's own message by resetting the collection mid-message. Marker regex unchanged; fail-open paths unchanged; deny REASON wording updated to clarify "text output (not thinking)" and "between the previous Edit/Write (if any) and this one" — closing the thinking-block loophole and making the per-edit scope explicit. Verified via three test fixtures (see `tests/`).

### Changed â `plugin/bin/session-start-check.sh` accuracy + guardrails

The RULE 22 ORDERING text at line 192 previously claimed "the PreToolUse hook cannot enforce this; discipline is Claude-side." v2.10.5's `permissionDecision: deny` mechanism made that statement false, and under 4.7's literal reading the contradiction was an active compliance hazard. Rewritten to accurately describe the deny behavior, the per-edit scope ("between the previous Edit/Write and this one"), and four common rationalizations (added "too trivial" to the existing three). Also adds two new guardrails: **TASK BUDGET** (prompts Claude to surface strain symptoms — cut-short responses, deep sessions, compaction warnings — to the user for decision, since Claude Code's UI exposes actual usage to the user but not to the model; explicitly forbids self-defeating `/extract` during strain since the raw transcript persists via PreCompact anyway) and **MEMORY PATHWAY** (routes 4.7's enhanced file-system memory through ARIA's `/clip`, `/extract`, `/intake`, `/audit-knowledge` flow so the knowledge tree stays curated rather than fragmenting into ad-hoc notes).

### Changed â `plugin/bin/post-edit-check.sh` prose trimmed

Non-planning-path `additionalContext` reduced from ~580 to ~515 characters. All five verification questions (scope held, nothing extra touched, no unnecessary rewrites, matches decision, secondary impact) preserved. All three output formats (PASS, PASS CONDITIONAL, FAIL) preserved with full markers. Only redundant prose removed. Saves ~65 chars per edit; scales favorably under 4.7's 1.0â1.35Ã tokenizer inflation.

### Changed â `plugin/bin/task-context-check.sh` case normalization

Index tag extraction now pipes through `tr '[:upper:]' '[:lower:]'` so mixed-case tags in `index.md` (e.g., `### TypeScript`, `### React`) match against task words (which were already lowercased). Prior to this fix, any mixed-case tag was silently never-matched, suppressing context suggestions. Single-pipeline change; no other behavior affected.

### New â Rule 32: Halt on direct contradiction with a written directive

Added to `plugin/template/rules/working-rules.md` (and mirrored in `knowledge/rules/working-rules.md` for this install). If a user request directly contradicts a written directive (rule in `rules/working-rules.md`, instruction in the currently-invoked skill's prompt, or recorded decision under `decisions/` or `projects/{tag}/decisions/`), halt before any tool call, name the contradiction verbatim, and ask for explicit override. Trigger is literal textual contradiction only â perceived expectations and inferred intent don't trigger (handled by Rule 7); scope-creep concerns remain governed by Rule 22. Motivated by 4.7's literal instruction-following: silent resolution of a contradiction masks a disagreement the user may not know exists.

### New â `tests/` directory with hook regression protection

First-ever test infrastructure for ARIA hook contracts. Three fixtures under `tests/fixtures/` capture the 4.7 split-message transcript shape in three scenarios (compliant, non-compliant, second-edit-without-fresh-marker). A repro script at `tests/repros/4-7-split-message.sh` invokes `pre-edit-check.sh` with each fixture and asserts the expected allow/deny outcome. A minimal runner at `tests/run.sh` executes all repros and reports pass/fail. The absence of this infrastructure was identified as the root cause of the v2.10.5 regression (mechanism-shift release without replay validation); future hook changes should add or update fixtures as appropriate.

### Retracted â v2.10.5 "self-recovers within one retry" claim

The v2.10.5 CHANGELOG stated that Claude "self-recovers within one retry" when the deny fires on a missing marker. That claim did not hold under 4.7 â the split-message architecture made every retry produce the same deny outcome, creating an unbounded deny loop. v2.10.6's turn-scoped scan makes the original self-recovery semantic work as intended. The claim is retracted in this release rather than silently corrected, so users reviewing the version history understand why the bug presented differently than the v2.10.5 notes suggested.

### Explicitly rejected â softening LOW-impact post-edit scope check

An external analysis suggested that 4.7's native self-verification makes the post-edit scope check redundant for LOW-impact edits and recommended dropping the required output on that path. This was considered and rejected. Native self-verification is internal reasoning; Rule 22's scope check is an external audit artifact â a grep-able, user-reviewable compliance record. Dropping the LOW-path output would eliminate the audit trail for ~80%+ of edits, defeating Rule 24's process-steps-define-done semantics. The token savings pursued in v2.10.6 come from trimming redundant prose (`post-edit-check.sh` above), not from dropping enforcement surface. Decision captured as ADR 039 at `knowledge/projects/aria/decisions/039-preserve-post-edit-scope-check.md`.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` to pick up the hook changes. Sessions running the pre-v2.10.6 hook continue to deadlock under 4.7 until reinstalled.
- **Template diffs on `/setup`:** `plugin/template/rules/working-rules.md` has a new Rule 32. `/setup` will present a diff prompt on next run. Accept to take Rule 32; decline to keep your customized local copy (and note that Rule 32 applies regardless of which version of the doc is loaded when the user opts to adopt it).
- **Regression protection:** run `sh tests/run.sh` at `Projects/aria/` to verify the hook scanner behavior on the 4.7 split-message shape. All three cases should pass.
- **Related references:** `knowledge/projects/aria/references/opus-4-7-aria-compatibility.md` documents the verified 4.7 behaviors this release is designed around and serves as the canonical ARIAâ4.7 design reference.
- **Deferred to v2.11.x:** `config.sh` sed batching (CPU, not 4.7-specific), usage-monitor hook (automatic token-usage observation via transcript sum), post-edit scope-check structural enforcement (Scenario E gap), Bash-write detection (Scenario C gap).

## [2.10.5] - 2026-04-20

Patch release. Replaces instructional Rule 22 enforcement with compliance-detecting mechanism. The v2.10.1 PreToolUse hook emitted "output retroactively AND prospectively" as an unconditional directive because the hook text claimed the platform gave hooks "no preventive authority." This claim was incorrect — PreToolUse hooks can return `permissionDecision: "deny"` to block the tool call. Under Claude 4.7's literal reading of ambiguous instructions, the "AND" clause was applied unconditionally, causing duplicate block emission per edit (one prospective above, one retroactive after, one prospective for next). Diagnosed in a live 4.7 session on 2026-04-20 after ~15 edits accrued ~3-6k wasted tokens. This release makes the retroactive path unreachable by construction: the PreToolUse hook now parses the current assistant turn's transcript, looks for a `[Rule 22]` marker, and denies with recovery instructions if absent. There is no code path in which compliance is satisfied after the edit lands, so the instruction ambiguity that drove duplication no longer exists.

### Changed — `plugin/bin/pre-edit-check.sh` rewrite

Full rewrite. Preserves all v2.10.x path-classification logic (planning path, protected basenames, knowledge-folder conditional protection, critical paths, batch-manifest layers 3a/3b/3c/4/5). Adds compliance detection: parses `transcript_path` for the assistant message containing the current `tool_use_id`, scans text blocks preceding the tool_use for regex `\[Rule 22(\s·\s[^\]]+)?\]`. On match, exits silently (no `additionalContext` emission — compliant path is now zero-noise). On miss, emits `permissionDecision: "deny"` with a concise recovery message naming the expected format for the matched variant (planning / batch / full). Fail-open on every detector error path: unreadable transcript, malformed JSONL, missing `tool_use_id`, or python exception all fall through to allow rather than block.

### Changed — `plugin/bin/post-edit-check.sh` scope marker

Scope-check output format updated to `[Rule 22 · Scope] PASS — ...`, `[Rule 22 · Scope] PASS CONDITIONAL — ...`, `[Rule 22 · Scope] FAIL — ...` (planning branch: `[Rule 22 · Scope] OK — planning doc.`). Marker is symmetric with pre-edit compliance blocks — same regex, same readability. Hook logic (path classification, protection detection) unchanged.

### Changed — `plugin/template/rules/change-decision-framework.md` harmonization

Three classes of edit: (1) "Ordering (required)" opening paragraphs rewritten — the "hook has no preventive authority" claim is replaced with the accurate v2.10.5 mechanism description including marker format + `permissionDecision: "deny"` behavior; (2) "The hook can only be satisfied retroactively" rationalization subsection marked historical — retained per Rule 6 archive principle (the rationalization was real in v2.10.1–v2.10.4 sessions; naming it preserves institutional memory for future instruction-design patches); (3) marker convention note added to "Required Output Formats" section; all format templates and examples (Impact headers + Scope pass/fail lines) prefixed with `[Rule 22]` / `[Rule 22 · Scope]` so doc and hook teach the same format.

### New — marker convention

Every Rule 22 compliance block starts with `[Rule 22]` or `[Rule 22 · <variant>]` on its header line:

- `[Rule 22] Low Impact — ...` (full low-impact block)
- `[Rule 22] High Impact — ...` (full high-impact 7-step block)
- `[Rule 22 · Planning] <file>` (planning-path abbreviated)
- `[Rule 22 · Batch N/M] <file> per declared scope.` (batch-manifest compressed)
- `[Rule 22 · Scope] PASS | PASS CONDITIONAL | FAIL — ...` (post-edit scope check)

The marker serves two purposes: (1) unambiguously signals the block as a compliance artifact so the hook's detector has zero false positives / negatives in prose that mentions Rule 22; (2) gives readers a greppable anchor when auditing sessions for compliance history.

### Resolved from v2.10.4 deferrals

The v2.10.4 CHANGELOG deferred "Rule 22 hook text strengthening (v2.11.x candidate)" pending observed drift. Drift emerged in a 2026-04-20 session where 4.7 emitted the retroactive block unconditionally. The structural fix shipping here supersedes the instruction-wording strengthening originally sketched in `knowledge/intake/ideas-backlog.md` — rather than reinforcing language in the instruction, the mechanism is changed so the ambiguous instruction is no longer reachable. That ideas-backlog entry can be closed on next `/audit-knowledge`.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` to pick up the hook rewrite. Sessions running the pre-v2.10.5 hook continue to behave as before (retroactive-AND-prospective instruction fires, duplicate blocks possible); only reinstalled sessions get the deny-on-miss mechanism.
- **No config migration:** no new fields in `~/.claude/aria-knowledge.local.md`. Existing configs continue to work unchanged.
- **First-edit teaching moment for Claude-in-flight:** immediately after reinstall, the first Edit/Write in any session will be denied if Claude hasn't yet emitted a `[Rule 22]` marker. The deny message includes the expected format template; Claude self-recovers within one retry. No user action required.
- **Template diff on `/setup`:** `plugin/template/rules/change-decision-framework.md` changed; `/setup` will present a diff prompt on next run. Accept to take the v2.10.5 teaching content; decline to keep a customized local copy (and note that the marker convention applies regardless of which version of the doc is loaded — enforcement is hook-side, not doc-side).
- **Examples now use the marker:** if you had copied an older example block as a snippet or template, update the first line to include `[Rule 22]` before re-using it.

## [2.10.4] - 2026-04-18

Patch release. Applies Opus 4.7 best-practices guidance to ARIA's bulk-scan and bulk-output skills. Two distinct changes landed: (1) explicit parallel-Read directives in skills that read multiple files per step — 4.7's less-eager tool use would otherwise serialize these under the new defaults, doubling per-step I/O latency and token consumption; (2) top-level output policy guards + per-section zero-state rules in skills producing structured reports — 4.7's adaptive response-length behavior would otherwise silently collapse empty sections that are actually informational signals ("0 integrity issues detected" confirms the audit ran the check). All edits are skill-markdown directives; no behavior/schema/hook/API changes. No config migration required.

### Changed — Parallel-Read directives in bulk-scan skills (Change 1)

Added explicit "issue Read calls in a single parallel tool-use block" guidance to steps that read multiple files of the same kind for the same purpose. Under 4.6 defaults the model tended to parallelize implicitly; under 4.7's less-eager tool use, these serialize unless told. Scope kept strictly within-step to protect each skill's cross-step sequencing and user-approval checkpoints.

- `plugin/skills/audit-knowledge/SKILL.md` — Step 3 (memory files), Step 4 (plan files), Step 5 (knowledge-folder dedup — feeds 5b/5c without re-reads), Step 5b ("do not re-read" reinforcement at the highest-risk re-read site)
- `plugin/skills/audit-config/SKILL.md` — Step 3 (CLAUDE.md scan), Step 4 (knowledge-folder verify), Step 5 (PROGRESS.md scan)
- `plugin/skills/intake/SKILL.md` — Step 2 (source-file reads, with explicit URL/WebFetch exception), Step 4 (dedup reads)

### Changed — Output policy guards in bulk-output skills (Change 2)

Added top-level "emit every section defined below" directives to skills producing structured comprehensive reports, plus per-section zero-state rules where empty-state behavior was previously ambiguous. Guards against 4.7 adaptively collapsing dashboards into prose or silently omitting zero-finding sections that carry informational signal. The pattern that emerged: **top-level output policy directive placed between the "Output in this format:" / "Present ... in this format:" opener and the fenced code-block template.**

- `plugin/skills/audit-knowledge/SKILL.md` — Step 6 top-level output policy directive + per-section zero-state rules for four previously-ambiguous subsections (Pending Insights, Pending Decisions, Category C Items, Cross-Reference Findings). Four other subsections already had explicit conditional-on-feature-presence omission rules and were left unchanged.
- `plugin/skills/audit-config/SKILL.md` — Step 6 top-level output policy directive only (existing `[list items or "None"]` template was already prescriptive per-section; gap was the whole-report-is-None collapse case).
- `plugin/skills/stats/SKILL.md` — Step 6 top-level output policy directive only (existing dashboard template was already prescriptive; gap was potential misreading of Rules section's "Fast — just counting and date parsing, no heavy analysis" as "keep output short" rather than as an implementation-effort directive).

### Declined / Deferred — Intentional no-change decisions

Per-skill Change 1 and Change 2 assessments identified 5 skills where no edit was warranted, with rationale documented for durable scope-memory:

- **`/codemap` Change 1 (declined)** — Step 4's "process one feature at a time to manage context" is a deliberate sequentialization discipline. A parallel-Read directive would pressure the model against the explicit serialization instruction. Step 2 indexing uses Grep/Glob rather than Read, so parallelism has low payoff anyway.
- **`/stitch` Change 1 (deferred)** — the relevant read logic lives in the `group-loader` shared-block, which is duplicated verbatim in `/distill`. Editing one copy without the other triggers `/audit-knowledge` Step 5b3 shared-block drift detection. Modest gain (2–4 CODEMAPs per load) doesn't justify the coordinated-edit ceremony. Revisit when the shared block is touched for other reasons.
- **`/backlog` Change 2 (no-edit)** — content-proportional by design across all three modes (overview dashboard, detail view, interactive clear flow). No structured comprehensive output to guard.
- **`/context` Change 2 (no-edit)** — adaptive-by-design. Skill purpose is targeted retrieval with deliberate section omission; has 6 existing explicit omission rules throughout Step 5. Adding an emit-all directive would actively fight the skill's intent.
- **`/codemap` Change 2 (no-edit)** — already rigorously guarded. Every user-facing output has forcing confirmation prompts or explicit format templates; CODEMAP.md section content has explicit required elements per feature.

Full scope records with per-skill revisit triggers captured in `knowledge/intake/ideas-backlog.md` (2026-04-18 entries: "Change 1 propagation scope" and "Change 2 sweep").

### Deferred — Rule 22 hook text strengthening (v2.11.x candidate)

Considered and deferred: reinforcing language in `plugin/bin/pre-edit-check.sh` rejecting "extensive prose reasoning = compliant" readings under 4.7's adaptive thinking. The framework mechanism is correct (adaptive thinking expands *quantity* of reasoning, not *shape* — Rule 22's slots force the shape). Current hook text fires cleanly in real sessions; no observed drift tied to 4.7. **Revisit after 2-3 weeks of 4.7 usage if drift emerges** where the block "technically fires" but named slots are under-addressed. Candidate phrasing captured in `knowledge/intake/ideas-backlog.md` (2026-04-18 entry: "Strengthen Rule 22 hook text against 4.7 adaptive-thinking drift").

### Shared-pattern opportunity — not acted on

The top-level output policy directive across `/audit-knowledge`, `/audit-config`, and `/stats` is near-identical. Could become a shared-block like `group-loader` in `/distill` and `/stitch`. **Deferred** — 3 instances is near the shared-block amortization threshold but not clearly over it. Revisit if a 4th skill needs the same directive.

### No migration required

All edits are additive skill-markdown directives. No schema change, no hook change, no config change, no API change. Existing sessions pick up new behavior on next skill invocation. Reinstall `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` per usual; no config migration needed.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` to pick up the skill changes.
- **No template diff on `/setup`:** the edits are skill-internal; `plugin/template/` is unchanged.
- **No Rule 22 hook change:** the v2.10.3 hook text is unchanged. The v2.11.x candidate strengthening (captured in `ideas-backlog.md`) is future work.
- **Empty-state output verification:** next run of `/audit-knowledge`, `/audit-config`, or `/stats` on a clean baseline should emit zero-state lines/counts explicitly — if you see collapsed or prose-style summaries instead, the skill didn't reload.

## [2.10.3] - 2026-04-18

Patch release. Replaces the day-only `/audit-knowledge` trigger with activity-driven OR-logic and tiered messaging. The prior 3-day cadence mis-fired in both directions — prompting on empty backlogs during low-activity weeks, and staying silent through high-activity days where backlogs had already crossed the reviewable ceiling. This release makes backlog-entry count the primary trigger and keeps elapsed-days as a safety net for silent-drift periods. No breaking changes: existing configs keep working; the new field takes its default (20) when absent.

### Added — `audit_trigger_threshold` config field (default 20)

New YAML frontmatter key in `~/.claude/aria-knowledge.local.md` counted via `^### ` headers across `intake/insights-backlog.md`, `intake/decisions-backlog.md`, and `intake/extraction-backlog.md`. `ideas-backlog.md` is deliberately excluded — ideas route out rather than promoting, so counting them would conflate staging with action. Parsing and numeric-validation plumbed through `plugin/bin/config.sh` alongside existing cadence fields.

### Changed — Tiered SessionStart prompt messaging

`plugin/bin/session-start-check.sh` now composes one of three prompt tiers based on backlog size (tier boundaries derived from `audit_trigger_threshold` via fixed `+15` / `+30` offsets):

- `count ≥ threshold` → *"Knowledge audit suggested — N entries ready for review."*
- `count ≥ threshold + 15` → *"Knowledge audit recommended — N entries, near one-pass ceiling."*
- `count ≥ threshold + 30` → *"Knowledge audit overdue — N entries, plan for multi-pass."*

If both entry-count and elapsed-days triggers fire, the entry-tier message wins and the day-count is appended as context. Every prompt embeds a `(trigger: count=N threshold=T days=D)` hint — both for user clarity and for greppable post-ship tuning. The day-only prompt (fired when count tier doesn't trigger but cadence has) is reformatted to *"Knowledge audit due — N days since last audit. (trigger: days=N threshold=C; backlog=M) Run /audit-knowledge?"* — same firing conditions as before, with the trigger hint appended so the audit log can capture it.

### Changed — `audit_cadence_knowledge` default 3 → 7 days

Bumped throughout: `plugin/bin/config.sh` default + fallback, `plugin/skills/setup/SKILL.md` prompt prose + Step 7 config template, `plugin/QUICKSTART.md` documented default. Rationale: once activity-count is the primary signal, the day-based check becomes the safety net for "did anything drift silently while I wasn't writing" — weekly cadence matches that intent better than the original 3 days, which was calibrated for day-only triggering.

### Added — `Trigger:` subfield in audit-log entries

`plugin/skills/audit-knowledge/SKILL.md` Step 8 audit-log template (both promoted-items and empty-audit variants) now records `Trigger: count=N threshold=T days=D cadence=C — (which fired)`. This makes trigger distribution greppable across audits, enabling data-driven tuning once 3-4 entries accumulate. Applied to both promoted and yield-zero audits — the yield-zero cases are the most important tuning signal since they indicate the threshold fired but nothing promoted.

### Skill updates

`plugin/skills/audit-knowledge/SKILL.md` Step 0 reads `audit_trigger_threshold`; Step 1 computes current backlog count and enumerates tier-message semantics so user-invoked runs see the same state as hook-triggered prompts.

### No migration required

Existing configs lacking `audit_trigger_threshold` automatically use the default (20). Existing configs with `audit_cadence_knowledge: 3` continue working unchanged; only the default for fresh installs changes. No schema breakage, no hook-timing change, no API change.

## [2.10.2] - 2026-04-18

Patch release. Strengthens v2.10.1's Rule 22 ordering discipline after a real-session failure mode was observed: an in-flight session continued across a plugin reinstall produced ~dozens of retroactive Rule 22 assessments, then (when challenged) proposed to "skip the block for this review" as an escape hatch the framework does not offer. Root causes: (1) the v2.10.1 hook message put the retroactive recovery clause first and the prospective-next-edit requirement second — the second half got skimmed; (2) SessionStart injection only fires at session start, so continued sessions across plugin updates don't receive the preventive layer; (3) no doctrine named and rejected the specific rationalizations Claude was inventing. v2.10.2 addresses (1) and (3) directly, and partially mitigates (2) via the stronger hook text. No config migration or API changes.

### Changed — Hook message leads with prospective requirement, names escape hatches inline

`plugin/bin/pre-edit-check.sh` MAIN_MSG reworded. The message now opens with:

> "REQUIRED: your NEXT Edit/Write must be preceded (in the same assistant turn, ABOVE the tool call) by the Low/High Impact block."

— making the prospective requirement load-bearing text a skim-reader cannot miss. The retroactive-recovery clause is secondary. The message then explicitly names four rationalizations observed in the wild ("conversation already covered it," "docs-only / in-review / discuss-then-edit cadence," "only way to satisfy the hook is retroactively," "skipping for this session is a plugin-config option") and rejects each inline. HIGH/LOW format specs unchanged.

### Added — "Rationalizations that do not apply" section in doctrine

New `## Rationalizations that do not apply` section in `plugin/template/rules/change-decision-framework.md`, placed between the v2.10.1 `## Ordering (required)` section and `## Required Output Formats`. Names and rejects the four escape hatches with framework-semantic reasoning (not just "don't do it"):

- **"Conversation already established the reasoning"** — conversation surfaces decisions; the block surfaces ranked alternatives and scope checks. Skipping drops the alternative-ranking.
- **"Hook can only be satisfied retroactively"** — reading only half the AND clause; retroactive is recovery, not method.
- **"Docs-only / in-review / routine edit"** — the framework is about decision discipline, not edit content. Tier is determined by stakes; exemption is not an option.
- **"Skipping is a plugin-config the user can make"** — no such config exists. The correct response to ceremony cost is shorter LOW blocks or a batch manifest, not skipping.

Plus a catch-all subsection for novel rationalizations: file as an `ideas-backlog.md` entry, not adopted mid-session.

### Changed — SessionStart reminder references the new doctrine section

`plugin/bin/session-start-check.sh` RULE 22 ORDERING reminder updated to cite both `"Ordering (required)"` and `"Rationalizations that do not apply"` sections, and to name three of the specific invalid arguments inline as quick-reference against skim-reading. Length increase ~50 tokens per session-start; acceptable cost for closing the doctrine cross-reference.

### Observed failure this patch addresses

For maintainers auditing whether the fix matches the observed failure:

- **Session:** pre-v2.10.1 session continued across plugin reinstall (new hook message loaded; SessionStart context stale)
- **Failure pattern:** ~30 Rule 22 assessments output retroactively across a single-file review pass; when challenged, Claude cited the hook text as justification ("the only way to satisfy it is retroactively")
- **Proposed escape:** "Skip the blocks for the rest of this review — we've already established the reasoning conversationally"
- **Why v2.10.2 catches it:** the new hook message leads with the prospective requirement (so skim-reading catches it); the doctrine explicitly rejects the "conversation already covered it" argument; the SessionStart text names invalid-argument examples a model might reach for

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/`. No config migration needed.
- **Template diff on next `/setup`:** `rules/change-decision-framework.md` gains the new `## Rationalizations that do not apply` section. Accept to receive the canonical doctrine.
- **Continued sessions across this reinstall:** SessionStart injection still only fires on fresh sessions. Sessions already in progress at reinstall time will get the new MAIN_MSG per-edit but not the new SessionStart text until restart. The v2.10.2 hook message change is strong enough to compensate; if you see the failure mode recur, restart the session to pick up the new SessionStart injection.
- **Longer-term fix for the continued-session gap:** filed as a v2.11.x candidate — the Layer 4 verification hook in `ideas-backlog.md` would detect the failure mode mechanically rather than relying on doctrinal text.

## [2.10.1] - 2026-04-18

Patch release. Fixes a coordination gap between v2.10.0's batch-manifest mechanism and the knowledge-folder protection layer that prevented `/audit-knowledge` — v2.10.0's sole motivating use case — from receiving the compression v2.10.0 was designed to deliver. Also clarifies Rule 22 ordering discipline across three enforcement layers (doctrine, SessionStart injection, hook message) to close a long-standing gap where the pre-edit assessment was being output retroactively (after the tool call) instead of prospectively (above it). Behavior is unchanged for non-manifest sessions, for declared-high ops, for structural-signal paths, and for protected basenames (`CLAUDE.md`, `working-rules.md`, `plugin.json`, etc.). No config migration or user-visible API changes.

### Fixed — Knowledge-folder protection now respects batch-manifest declarations (ADR 035)

In v2.10.0, `pre-edit-check.sh` marked every file inside `KT_KNOWLEDGE_FOLDER` as `IS_PROTECTED=true` unconditionally, which pre-empted the layer 3a compression check. Since `/audit-knowledge`'s entire workload lives inside the knowledge folder, ADR 021's compression never activated for the workload that motivated it.

v2.10.1 reorders the hook so `SIGNALS` and `BATCH_MATCH` are computed before knowledge-folder protection, then gates knowledge-folder protection on batch state:

- **No manifest (or file not matched):** knowledge folder stays protected — full Rule 22 (unchanged from v2.10.0).
- **Declared-low + matched + no structural signals:** knowledge folder protection is lifted for this file only; layer 3a compression activates.
- **Declared-high + matched:** full Rule 22 with `BATCH DECLARED-HIGH` prefix (unchanged).
- **Declared-low + matched + signals fire:** full Rule 22 with `BATCH SIGNAL OVERRIDE` prefix (unchanged).
- **Protected basename (`CLAUDE.md`, `working-rules.md`, `plugin.json`, etc.):** full Rule 22 regardless of manifest — protected basenames are stricter than knowledge-folder blanket.
- **User `critical_paths` protection:** unchanged by this patch — critical paths represent explicit user intent to always scrutinize and are NOT overridden by batch manifest.

### Verified — Six-scenario hook regression matrix

This fix was validated against six enforcement scenarios before shipping:

1. **No manifest** → full Rule 22 ✓
2. **Declared-low + matched + no signals** → compressed directive ✓
3. **Declared-low + matched + signals fire** → `BATCH SIGNAL OVERRIDE` + full Rule 22 ✓
4. **Declared-high + matched** → `BATCH DECLARED-HIGH` + full Rule 22 ✓
5. **Protected basename (`plugin.json`) + declared-low matched** → full Rule 22 (protection wins) ✓
6. **Manifest active, file NOT matched** → full Rule 22 (scope-drift detection) ✓

Documented in ADR 035 as candidate test cases for future hook refactors.

### Changed — `pre-edit-check.sh` decision hierarchy comment updated

Header comment block in `plugin/bin/pre-edit-check.sh` now documents the v2.10.1 conditional-protection semantics inline, with explicit `v2.10.1:` markers at the two logic sites for future maintainability.

### Clarified — Rule 22 ordering discipline (three-layer fix)

Prior versions had a latent gap: the PreToolUse hook fires alongside the tool result (not before the tool runs), so Claude was reading the CHANGE DECISION CHECK reminder AFTER each Edit/Write landed, then outputting the Low/High Impact block retroactively. The hook's wording ("Output this REQUIRED format before proceeding... STOP and do so before proceeding.") implied preventive behavior that Claude Code's tool lifecycle can't actually provide. v2.10.1 adds three coordinated layers so the ordering discipline shifts from hook-driven correction to Claude-side proactive output.

**Layer 1 — Doctrine:** New `## Ordering (required)` section in `plugin/template/rules/change-decision-framework.md` states the rule explicitly, with WRONG/RIGHT examples and the reasoning that the hook is a safety net, not a primary mechanism. Plugin-managed file — users will see this as a `/setup` diff on next update.

**Layer 2 — SessionStart injection:** `plugin/bin/session-start-check.sh` now emits a `RULE 22 ORDERING` reminder on every non-first-run session start, so the ordering rule is in Claude's foreground context before the first edit of the session, not after. This is the preventive layer — the only one that fires before any Edit/Write.

**Layer 3 — Hook message rewrite:** `plugin/bin/pre-edit-check.sh` MAIN_MSG reworded. Removed the deceptive "before proceeding" / "STOP and do so before proceeding" phrasing (which implied preventive timing the hook doesn't have). Replaced with honest framing: the hook fires with the tool result, so if Claude is reading the message the edit has already landed. Dual-action recovery: output retroactively now AND put the next edit's block above the tool call. HIGH/LOW format specs preserved verbatim — only the framing around them changed. Batch-mode (BATCH_MSG) variant unchanged since its timing framing is already honest.

**Why three layers, not one:** the PreToolUse hook cannot technically prevent the ordering violation (it fires too late). Rewriting its wording alone would have improved honesty but not the failure rate. The SessionStart injection is the only preventive layer — without it, the doctrine and hook rewrite stay corrective. All three are complementary: doctrine is canonical reference, SessionStart puts the rule in foreground before first edit, hook rewrite is the per-edit safety net when discipline slips.

**Post-edit hook unchanged:** the POST-EDIT SCOPE CHECK fires after the edit by design (that's when scope verification makes sense), so its timing framing ("Output this REQUIRED format after edit") was already honest. No change needed.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` as per `CLAUDE.md`. No config migration needed.
- **Template diff on next `/setup`:** the new Ordering section in `rules/change-decision-framework.md` is plugin-managed, so `/setup` will surface it as a diff prompt. Accept to receive the canonical ordering rule; if you've customized the file locally, the diff will let you merge selectively.
- **No CHANGELOG rollback needed for v2.10.0** — the v2.10.0 entry correctly describes the designed mechanism; v2.10.1 is the implementation correction that makes v2.10.0's design operational for its motivating case.

## [2.10.0] - 2026-04-17

Ceremony-reduction release. Implements ADR 021 Plan A's bundled Upgrades 1+2 — the batch-manifest mechanism that compresses Rule 22 ceremony for declared-mechanical bulk operations while preserving full CHANGE DECISION CHECK for high-impact edits. Requires `jq` on PATH (graceful degradation to full Rule 22 if jq missing). No breaking changes to existing skills; hook behavior is unchanged for edits with no active manifest.

### Added — Batch-manifest mechanism (core infrastructure)

Skills and manual plan-execution can declare an active batch by writing `~/.claude/active-batch.json`. The `pre-edit-check.sh` hook detects the manifest and, for matching low-impact ops with no structural signals and no protected-path conflict, emits a compressed directive ("BATCH OPERATION (N/M) — declared scope: ...") instead of the full CHANGE DECISION CHECK template. Out-of-scope edits, declared-high ops, signal-triggering files, and protected paths all continue to get full format.

**Manifest schema** (validated by `kt_batch_begin`):

```json
{
  "batch_id": "unique-identifier",
  "skill_name": "invoking-skill or 'manual-plan-execution'",
  "plan_summary": "one-line description",
  "started_at": "ISO-8601 UTC timestamp",
  "expected_operations": [
    {
      "file_path_pattern": "glob pattern",
      "operation_type": "create|update|delete",
      "impact": "high|low",
      "justification": "non-empty string"
    }
  ]
}
```

**New helpers in `plugin/bin/config.sh`:**
- `kt_batch_begin SKILL_NAME PLAN_SUMMARY OPS_JSON` — validates the ops array (each op must have non-empty `file_path_pattern`, `impact` in {high, low}, and non-empty `justification`) and writes the manifest
- `kt_batch_end` — removes the active manifest (safe no-op if none exists)
- `kt_batch_find_match FILE_PATH` — used by the hook to check if an edit matches an expected op
- `kt_batch_clear_stale [MAX_AGE_SECONDS]` — removes stale manifests (default 30 minutes) to recover from crashed sessions

### Added — Safety floor (multi-layer defense)

The batch mechanism compresses ceremony only when every safety layer clears. Any layer firing degrades to full Rule 22:

1. **Protected paths always win** — `CLAUDE.md`, `working-rules.md`, `change-decision-framework.md`, `enforcement-mechanisms.md`, `settings.local.json`, `plugin.json`, the knowledge folder itself, and user `critical_paths` always get full assessment regardless of manifest declaration.
2. **Structural signal override** — if `kt_detect_signals` detects auth, migration, model, routing, or external-service signals on a declared-low op, the hook escalates to full Rule 22 with a `BATCH SIGNAL OVERRIDE` prefix. Signals are ground truth from the filesystem; cannot be self-declared away. This promotes `kt_detect_signals` from advisory-only (v2.9.0) to having override authority when a batch manifest is active.
3. **Declared-high fires full format** — `impact: high` in the manifest always gets the full CHANGE DECISION CHECK with a `BATCH DECLARED-HIGH` prefix.
4. **Scope-drift detection** — edits to files not matched by any manifest op get full Rule 22. The manifest is both compression signal and declared-scope boundary; the hook catches wandering automatically.
5. **Post-edit scope check unchanged** — `post-edit-check.sh` ceremony is not compressed; aggregate drift detection (many individually-small edits collectively constituting an architectural change) surfaces there.
6. **Justification validation** — manifest entries with empty or missing `justification` fall back to full Rule 22 for that op (enforces articulated intent).
7. **Stale-manifest auto-clear** — `session-start-check.sh` removes manifests older than 30 minutes so crashed sessions don't silently suppress Rule 22 on later unrelated edits.

### Added — Three-tier ceremony calibration

With v2.10.0 the framework has three ceremony tiers, each triggered by a file-based signal:

| Tier | Trigger | Output |
|------|---------|--------|
| Planning | Edit to `*/docs/plans/*` or `*/docs/specs/*` | Abbreviated ("Planning edit — [filename]") |
| Batch declared-low | Edit matches manifest op + impact:low + no signals + not protected | Compressed directive (single-line acknowledgment) |
| Default | Everything else (no batch; declared-high; signal override; scope drift; protected) | Full CHANGE DECISION CHECK |

All three tiers use file-based signals — post-compaction safe per ADR 006 because the hook re-derives the tier from filesystem state on every fire.

### Added — `/audit-knowledge` batch integration

`/audit-knowledge` gains Step 7a (after user-approved promotion plan, before executing promotions) that constructs and writes a batch manifest classifying each approved op as high/low impact. Step 8b (after audit log is updated) clears the manifest. The audit's 15-30 edits per pass was the primary cost center that motivated ADR 021; this integration delivers the compression value for exactly that case.

**Classification guidance documented in Step 7a:** stub-and-reference, backlog clears, log appends, and new `approaches/`/`guides/`/`references/` files are typically declared `low`; new `decisions/` ADRs, new/modified `rules/` entries, and cross-project consolidations that create new authoritative files are typically declared `high`. "When in doubt, declare high — full Rule 22 is always the safe choice."

### Added — Manual plan-execution use case (general-purpose mechanism)

The batch manifest is **skill-agnostic by design**. When Claude is executing a user-supplied multi-file plan (e.g., implementing `docs/plans/feature-x.md`), Claude can write the manifest itself using the same helpers — no skill wrapper required. Documented in the new OVERVIEW.md "Batch Manifests for Ceremony Reduction" section with example. This generalization makes the mechanism useful for any declared-scope multi-edit operation, not just built-in skills.

### Deferred to follow-up releases

- **`/wrapup` manifest integration** (v2.10.1 candidate) — typical wrapup edit volume (2-4 files) is below the ceremony-reduction value threshold; filed for future evaluation.
- **`/extract` manifest integration** (v2.10.1 candidate) — /extract's dynamic-scope capture pattern doesn't pre-declare cleanly; filed for future design work on loose-pattern manifests.
- **post-edit-check.sh manifest symmetry** (v2.10.x) — ideas-backlog entry for symmetric post-edit compression on declared-low ops.
- **Bash-write-matcher extension** (v2.10.x) — widen hook matcher to catch `cat >>`, `sed -i`, shell redirect patterns that currently bypass Rule 22 (filed as separate ideas-backlog entry from v2.9.0).

### Changed

- `plugin/.claude-plugin/plugin.json` — version bumped to 2.10.0.
- `plugin/bin/pre-edit-check.sh` — rewritten with safety-floor decision hierarchy (planning → protected → batch compression → full with contextual prefixes). Backward-compatible for all no-batch edits.
- `plugin/bin/session-start-check.sh` — added `kt_batch_clear_stale 1800` early in the hook.
- `plugin/template/OVERVIEW.md` — new "Batch Manifests for Ceremony Reduction" section (between "Plugin-Managed vs User-Owned Files" and "Design Principles").
- `plugin/skills/audit-knowledge/SKILL.md` — added Step 7a (declare manifest) and Step 8b (clear manifest).

### Dependencies

- **Requires `jq` on PATH.** Install via `brew install jq` (macOS) or your package manager. Graceful degradation: if jq is missing, the hook falls back to full Rule 22 format for all edits — batch compression is lost but correctness is preserved.

### Related ADRs

- `knowledge/projects/aria/decisions/021-rule22-ceremony-plan-a.md` — updated to "Implemented in v2.10.0" with implementation notes (split-calibration field, signal-override promotion, justification validation).
- `knowledge/projects/aria/decisions/006-full-rule22-format-every-edit.md` — unchanged. Batch manifest is a narrow file-based exception structurally equivalent to the planning-path exception; ADR 006's core principle (no session-history-based self-judgment; file-based signals only) remains load-bearing.

## [2.9.1] - 2026-04-17

Documentation patch with small ergonomic additions. No changes to existing hook or skill logic. README, `/help`, and shipped plugin surfaces (OVERVIEW, skill docs, template files, `/setup` first-run note) gain positioning, usage guidance, and rationale surfaced from internal ADRs. Adds two delegate slash-command aliases (`/knowledge-audit`, `/config-audit`) for users who prefer inverted phrasing. Users will see diff prompts for `OVERVIEW.md`, `README.md`, `rules/change-decision-framework.md`, `rules/enforcement-mechanisms.md`, `rules/working-rules.md`, `rules/user-rules.md`, `LOCAL.md`, and `projects/README.md` on their next `/setup` — this is expected and correct behavior under ADR 011's diffability model; reconcile by keeping your version, adopting plugin version, or merging as appropriate.

### Added — Model Recommendations (README + /help)

New "Model Recommendations" section in README.md and as a second section in `/help` output (commands table surfaces first; recommendations second). Documents per-skill model tiers: **Opus 4.7, high effort** for judgment-heavy skills (`/extract`, `/audit-knowledge`, `/audit-config`); **Opus 4.6 (1M context) minimum** for `/codemap create` (full-repo traversal needs the large context window to avoid mid-generation truncation); **Sonnet 4.6** for structured and lightweight skills (`/codemap update/section`, `/wrapup`, `/intake`, `/distill`, `/stitch`, `/index`, `/stats`, `/backlog`, `/rules`, `/context`, `/clip`, `/help`, `/setup`). Haiku is not recommended for any ARIA skill — judgment and cross-reference demands exceed its strengths. Guidance only — ARIA does not force a model via frontmatter; users switch per session via `/model`.

### Added — Staleness & Freshness section (README)

New README section surfacing how ARIA handles knowledge staleness as a first-class concern: `Last updated` frontmatter on every knowledge file, configurable thresholds (`ideas_staleness_threshold_days` default 21, `staleness_threshold_months` for promoted files), audit cadences with SessionStart prompts when review is overdue, stale-first surfacing in `/audit-knowledge` Step 2c2 with asymmetric Accept/Reject/Defer/Reclassify disposition, and drift detection across `/audit-config`, `/audit-knowledge` Step 5b3, `/codemap update`, `/index`, plus Rule 22 edit-level enforcement preventing silent drift. Addresses the common first-impression question from users coming from graph-DB memory systems ("how do you handle staleness in markdown?").

### Added — ARIA vs Other Memory Architectures section (README)

New README positioning section contrasting ARIA against two alternative memory architectures: Karpathy-style LLM-compiled markdown wikis and graph-DB memory systems (mem0, Graphiti). Three-column comparison table across storage, curation authority, auditability, freshness mechanism, process discipline, failure mode, and ideal scale. Frames Karpathy's model as well-suited for **automated research compilation** (LLM authorial speed is the point; occasional drift acceptable because the artifact isn't load-bearing on daily decisions) and ARIA as tuned for **operationally applied decision-making** (working rules, architecture decisions, team conventions acted on every day, where LLM-promoted wrong rules cascade across references and degrade real output). Graph-DB memory positioned as complementary for retrieval-heavy workloads — can be layered below ARIA as a retrieval surface for promoted markdown. Grounded in ADR 010 ("LLM captures, human promotes").

### Added — ADR-grounded documentation in plugin surfaces

Surfaces the *why* behind several internal architecture decisions into user-visible plugin files. Each incorporation lands at the point where the corresponding behavior or convention is visible, so users encounter rationale at the surface instead of discovering it by reading internal ADRs.

- **ADR 018** (`/context` project-scoping) — `plugin/skills/context/SKILL.md` Step 5 gains a "Why project-scoped only" blockquote explaining why ideas surface on project-tagged queries but not topic-only queries (capture-vs-track boundary; retrieval-intent protection).
- **ADR 020** (behavioral vs feature routing) — `plugin/template/rules/user-rules.md` gains a "What Belongs Here vs ideas-backlog.md" subsection with examples, clarifying that behavioral observations about Claude's drift patterns go in `user-rules.md` while feature proposals, bug reports, and design ideas route to `intake/ideas-backlog.md` for external-tracker scheduling.
- **ADR 012** (`originally_at` provenance) — `plugin/template/LOCAL.md` generalizes the `originally_at` frontmatter note from a Decisions-template-only mention to a dedicated "Provenance — `originally_at` (any promoted file)" subsection with greppable enumeration command and the full frontmatter example.
- **ADR 006** (full Rule 22 format every edit) — `plugin/template/rules/enforcement-mechanisms.md` section 3 ("Required Output Format") gains a "Why the full format fires on every edit" paragraph explaining the post-compaction-safety rationale for the ~11K tokens/session overhead.
- **ADR 019** (stale-ideas asymmetric disposition) — README Staleness & Freshness section's "Stale-first surfacing" bullet gains a closing clause naming the accumulation failure mode that implicit Defer prevents.
- **ADR 011** (plugin-managed vs user-owned files) — triple surface:
  - `plugin/template/OVERVIEW.md` gains a new "Plugin-Managed vs User-Owned Files" section between "The Plugin" and "Design Principles," teaching the two-class model, listing files in each class, and stating the rule of thumb for customization routing.
  - Every plugin-managed template file (`OVERVIEW.md`, `README.md`, `rules/working-rules.md`, `rules/change-decision-framework.md`, `rules/enforcement-mechanisms.md`, `projects/README.md`) gains an HTML comment header at the top signaling its class at the point of customization. HTML comments are invisible in rendered markdown but visible in raw view, flagging the file class when users open it to edit.
  - `plugin/skills/setup/SKILL.md` Step 3 create mode gains a one-time first-install educational note enumerating both classes so new users encounter the split at their first `/setup`.

### Added — Public positioning (ADR 022)

New ADR `knowledge/projects/aria/decisions/022-public-positioning-operational-decisionmaking.md` (in the private knowledge repo, not shipped with the plugin) grounds the v2.9.1 README positioning claims in internal design rationale. Documents that ARIA's public stance — operational decision-making tool, markdown for auditability, human-promotion as load-bearing discipline — is a deliberate mirror of ADR 010's internal boundary, creating a public-facing commitment that future plugin features must remain compatible with.

### Added — Slash command aliases

Two new delegate alias skills accommodate the inverted "subject-audit" phrasing some users prefer:

- `plugin/skills/knowledge-audit/SKILL.md` — alias for `/audit-knowledge`. Invoking `/knowledge-audit` produces identical behavior.
- `plugin/skills/config-audit/SKILL.md` — alias for `/audit-config`. Invoking `/config-audit` produces identical behavior.

Both aliases are delegate stubs — they instruct Claude to read and execute the canonical SKILL.md rather than duplicating content. Canonical changes automatically apply to the alias; no drift risk. Frontmatter descriptions are deliberately non-competing with the canonical skills' natural-language trigger phrases, so natural-language dispatch ("run a knowledge audit") continues to route to the canonical skill; aliases are primarily for explicit slash-command invocation.

The `/help` commands table shows the alias form on the relevant rows: `/audit-knowledge (alias: /knowledge-audit)` and `/audit-config (alias: /config-audit)`.

### Changed

- `plugin/.claude-plugin/plugin.json` — version bumped to 2.9.1.

## [2.9.0] - 2026-04-17

Major release absorbing design imports from the `nrek/aria-ex1` fork (execution-first variant by Enrique Gutierrez). ARIA's knowledge lifecycle stays intact; additions are `/distill` spec shaping, `/stitch` cross-repo binding, structural signal surfacing in hooks, and rule-sub-structure extensions. Zero breaking changes; all new features are opt-in or additive.

### Added — /distill skill

Tiered task spec generator. Transforms raw ticket text into an executable spec following `TASK.schema.md`. Always emits Objective, Scope, Dependencies & API Requirements, QA, and Definition of Done; conditionally adds Frontend/Backend/Database layers only when the task touches them; `full` tier adds Non-Goals; `standard` and `full` add Assumptions and Edge Cases when non-empty.

- **Complexity scoring** — auto-tiers via point system (>1 layer +2, new endpoint/route/model +2, external service +2, auth/security +2, input >150 words +1, names >3 files +1, single-sentence trivial −3). Score ≤ 0 → `micro`; 1–3 → `standard`; ≥ 4 → `full`. Explicit `--tier` flag overrides.
- **Inputs** — inline string, file path, or prompt-to-paste when no argument provided.
- **Auto-archive on overwrite** — existing `TASK.md` moved to `.aria-distill/archive/TASK-YYYY-MM-DD-HHMMSS.md` before fresh write. First-run notice explains once; subsequent runs silent. Flags: `--append` (new entry below with separator), `--out=<path>`, `--no-archive` (destructive opt-in).
- **Advisory vocabulary** — `TASK.schema.md` flags 8 watered-down phrases (`flexible`, `extensible`, `scalable framework`, `we could also`, `alternatively`, `one option`, `potentially`, `might want to`) as soft warnings during validation. Not hard rejections.
- **`--group=<tag>` flag** — optional CODEMAP + STITCH context loading when the group is registered in `projects_groups`. Auto-propose bootstrap handles first-time groups.

### Added — /stitch skill

Cross-repo binding artifact generator for product groups (backend + one or more frontends). Produces `STITCH.md` with 6 sections: Group identity, Auth stitch, Endpoint stitch, Entity stitch, Integration stitch, Drift log.

- **Modes** — `create`, `verify`, `diff`, `section <n>`.
- **Drift detection precedence** — user-provided `analyze-stitch.sh|.py` script → CODEMAP-based endpoint diff (default) → explicit user prompt when CODEMAPs lack endpoint sections → opt-in grep fallback. Output always labels source ("Drift source: CODEMAPs" / "user script" / "fallback grep").
- **Output location** — workspace root (`<project_root>/STITCH.md`), adjacent to CODEMAP.md. Per-group override via optional `stitch_path` field. Distinct from fork's backend-root default — STITCH represents the contract between repos, not a backend-owned artifact.
- **Auto-archive** — same pattern as `/distill`; existing `STITCH.md` moved to `.aria-stitch/archive/` before write.
- **Pluggable script contract** — `analyze-stitch.sh|.py` at workspace root receives JSON stdin (`backend_root`, `frontend_roots[]`, `group`), returns JSON stdout (`fe_orphans[]`, `be_orphans[]`). Documented in `STITCH.template.md`.

### Added — projects_groups config (YAML block)

New multi-line YAML frontmatter field in `~/.claude/aria-knowledge.local.md` for multi-repo group metadata. First departure from the "every field is sed-parseable flat string" convention — `projects_groups` is consumed only by skills (Claude parses YAML natively), not by bash hooks, so the constraint doesn't apply.

```yaml
projects_groups:
  proj-a:
    backend: proj-a-backend
    web: proj-a-web
    mobile: proj-a-mobile
  proj-b:
    backend: proj-b-backend
    web: proj-b-frontend
```

- **Sparse entries** — only multi-repo projects appear; single-repo projects (e.g., `proj-c`, `proj-d`) omit entries.
- **Auto-propose bootstrap** — `/distill --group=<tag>` or `/stitch <mode> <tag>` with a missing entry scans `<project_root>` for repo markers (`manage.py` → backend, `next.config.*` → web, `app.json` + `expo` → mobile, etc.), proposes structured YAML with diff preview, writes on user approval. Eliminates the "register-first-and-retry" friction round-trip.
- **Optional `stitch_path` field** — per-group override for STITCH.md output location.

### Added — Shared-block marker convention + drift audit

New skill-development pattern: skills that inline shared logic use `<!-- shared-block: NAME -->` / `<!-- /shared-block: NAME -->` HTML comments to delimit duplicated content. `/audit-knowledge` Step 5b3 detects drift by normalizing whitespace and comparing contents across all skills with the same block `NAME`. First use: `group-loader` shared between `/distill` and `/stitch` for config-resolution + auto-propose bootstrap logic. Intentional divergence handled by renaming the block (e.g., `group-loader-distill`) so audit flags are a choice, not a noise.

### Added — Signal-surfacing advisory in pre-edit hook

`pre-edit-check.sh` now prepends structural signal labels to the CHANGE DECISION CHECK injection when detected. New `kt_detect_signals()` helper in `config.sh` matches:

- `auth` — paths containing `/auth/`, `/permissions/`, `/security/`, `/jwt/`, `/login/`
- `migration` — paths containing `/migrations/` or `/migrate/`
- `model` — filename `models.py`, `schema.ts`, `schema.prisma`, or `*.prisma`
- `routing` — filename `urls.py`, `routes.ts`, `route.ts`, `middleware.ts`
- `external-service` — filename contains `stripe`, `twilio`, `sendgrid`, `algolia`, `openai`, `vercel`, `supabase`, `auth0`, `firebase`, `segment`

Advisory only — Claude still classifies HIGH/LOW qualitatively. Zero user setup; patterns hardcoded in helper. Planning-path branch unchanged. Output format identical on non-matching files.

### Added — STITCH sibling surfacing in pre-explore hook

`pre-explore-codemap-check.sh` now checks for sibling `STITCH.md` next to discovered `CODEMAP.md`. When present, the cooldown reminder message extends to mention STITCH: *"STITCH.md also present at {path} (endpoint / entity / drift tables for cross-repo reasoning)."* Fires once per project per session, same cooldown as existing CODEMAP reminder.

### Added — Stack-aware cross-cutting candidates in /codemap

`/codemap` Step 3 now proposes stack-specific cross-cutting sections as candidates during feature-list generation:

- **Django** — URLConf tree overview, Signal registry (`post_save`/`pre_save` handlers), Migration state (latest per app), Env matrix (grouped env var names)
- **Next.js / React** — Route tree overview, API client & interceptors configuration, Env matrix
- **Laravel** — Route file overview, Job/queue registry, Service providers, Env matrix
- **Expo / React Native** — Screen tree overview, Navigation config, API client, Env matrix

Feature-organized codemaps systematically under-document these because they span all features rather than attaching to one. Explicit candidates surface the gap. User accepts/declines each; no force-insert.

### Added — /audit-knowledge Step 5d2 codemap coverage check

After Step 5d (codemap staleness), new Step 5d2 verifies each CODEMAP has the expected stack-level cross-cutting sections for its detected stack. Grep-based section-name matching with per-stack keyword lists. Surfaces missing sections in Step 6 output under "Codemap Coverage Gaps" with recommended `/codemap section <name>` command per gap. Does not auto-add — same deferral pattern as the staleness check.

### Changed — Hook text decoupled from Rule 22 number

`pre-edit-check.sh` comment + two hook message strings now reference the framework by filename (`change-decision-framework.md`) instead of by rule number (`Rule 22`). Survives future rule renumbering without hook patches. Rule file itself keeps Rule 22 as its stable identifier.

### Changed — Flattened + hardened critical_paths iteration in both edit hooks

- `pre-edit-check.sh` critical_paths iteration moved out of the knowledge-folder nested IF into a sibling check (matches `config.sh` invariant that `KT_CONFIGURED=true` guarantees `KT_KNOWLEDGE_FOLDER` is set, per validation at lines 50-62).
- `post-edit-check.sh` gains the same critical_paths block. Previously only in pre-edit — user-configured `critical_paths` protected pre-edit but not post-edit (asymmetry fixed).
- Both now include parser hardening: whitespace trim (`sed 's/^[[:space:]]*//;s/[[:space:]]*$//'`), empty-guard (`[ -z "$PREFIX" ] && continue`), and quoted case-pattern expansion (`*/"$PREFIX"/*` instead of `*/$PREFIX/*` — literal match, not glob).

### Changed — Rule 18 gains "Specific cases:" subsection

New sub-structure in `working-rules.md` Rule 18 ("Prefer foundational design over patching"). First specific case added:

- **Producer–consumer ordering** — when a schema, config field, or interface exists primarily to serve a specific consumer, design them together. Don't ship the schema alone against a speculative consumer (creates two migrations when the real consumer lands) or a consumer against a placeholder schema (creates fragile coupling). Watch for: *"I'll ship the schema now and use it properly when the consumer lands."*

Establishes "Specific cases:" as a precedent for future concrete applications under existing rules, rather than creating new rule numbers for each specific case.

### Changed — Rule 22 Step 6 gains principle-consistency cross-check

`change-decision-framework.md` Step 6 (Validate Decision) extended with one sentence: *"Also cross-check against principles invoked in recent adjacent decisions — principles applied once can silently erode across a long decision chain, so re-test rather than assuming earlier reasoning still applies."* Catches the "invoked a principle then violated it one decision later" failure mode that emerges in multi-hour design sessions.

### Changed — Help updates

- `/help` command reference now lists `/distill` and `/stitch` with brief descriptions.

### Backward Compatibility

- Existing `~/.claude/aria-knowledge.local.md` configs continue to work unchanged. `projects_groups` is optional; users without multi-repo groups see no behavior change.
- Existing CODEMAPs continue to work; Step 3 candidates extension is advisory and only appears on new-codemap generation or during audit coverage check.
- Hook behavior preserved — existing classification, planning-path abbreviation, knowledge-folder protection, and critical_paths protection all intact. Structural signal advisory emits no prefix on non-matching files (identical JSON output to v2.8.4).
- New skills `/distill` and `/stitch` are opt-in; they only fire when explicitly invoked.
- Rule extensions are additive — existing Rule 18 body text and Rule 22 Step 6 questions are preserved verbatim.

## [2.8.4] - 2026-04-15

### Added — Ideas Backlog (capture/track boundary)

Fourth intake backlog for feature proposals, bug reports, and design ideas. Distinct from the other three backlogs: ideas **never promote to knowledge files** — they route out of ARIA to the user's external tracker (Linear, GitHub Issues, Jira, etc.) during audit review, or get discarded.

Motivated by a common drift mode observed in practice: feature proposals and bug reports captured during work were getting misfiled as knowledge, ending up in `approaches/` or `guides/` as documentation of features that don't exist yet. The ideas-backlog creates a staging area with a different disposition — ARIA captures; your tracker schedules.

- **New template file** — `plugin/template/intake/ideas-backlog.md` ships with format + disposition explanation. Scaffolded on first `/setup` for new installs, auto-added on next `/setup` re-run for existing installs (Step 3 missing-file detection).
- **/extract updates** — new "Ideas (proposals, not observations)" bucket with classification signals ("should", "could be better if", "missing handling for", "UX gap", "would help if"). Soft-routing — items can legitimately split between observation (insights/decisions) and proposal (ideas); audit can refine if misclassified.
- **/audit-knowledge updates** — new Step 2c2 reviews ideas-backlog with distinct disposition options (Accept → tracker, Reject, Defer, Reclassify). Step 2c adds a reclassification check flagging misfiled proposals in the extraction-backlog. Step 6 presents ideas in their own report section without promotion targets.
- **/setup updates** — Expected files list includes `intake/ideas-backlog.md`; Never-diff list excludes it from template reconciliation (it's a user data file once scaffolded).
- **Docs** — OVERVIEW.md gains a "capture vs. track boundary" section explaining the philosophical separation. README.md directory tree includes the new file with inline routing note.

No breaking changes. Existing backlog formats and disposition rules are unchanged; this is purely additive.

### Added — Ideas Surfacing (project-scoped + aging)

Two surfacing mechanisms so staged ideas reach the user during normal workflow instead of only during explicit `/audit-knowledge` review. Addresses the dead-letter-office problem: a staging backlog nobody looks at stops being staging and starts being noise.

- **`/context {project}` extension** — when the query includes a configured project tag, `/context` appends a "Pending Ideas for {project}" section showing entries tagged with that project. Items include age (`filed N days ago`) and a `[STALE — still relevant?]` marker when age exceeds `ideas_staleness_threshold_days`. Non-selectable informational section — to triage, use `/audit-knowledge` or edit `ideas-backlog.md` directly. Pairs with the existing `auto_load_project_context` flag: users who opt into auto-loading see pending ideas for their current project every time `/context` fires.
- **`/audit-knowledge` Step 2c2 aging** — each idea entry gets an age annotation and stale marker. Stale entries sort first in the Pending Ideas section and prompt explicitly for Accept/Reject/Defer/Reclassify (implicit Defer is disallowed for stale items). Forces triage on long-sitting ideas each audit cycle.
- **New config field** — `ideas_staleness_threshold_days` (default 21). Extractable via `config.sh` like other numeric settings. Configurable through `/setup` Advanced Options.
- **Design trade-off** — urgency/priority fields were considered and deferred. Aging is a cheaper triage signal (counted, not predicted) and the audit pass is the right place for deliberate Accept/Reject/Defer decisions. If usage reveals a need for priority beyond age, add an optional `**Urgency:**` field to the ideas-backlog schema in a future release.

### Changed — Audit Log Structured Template

`/audit-knowledge` Step 8 replaces the prior single-paragraph "Result:" template with a multi-field structured format (counts / new-files / extended-files / memory / integrity-fixes / themes / notes / ideas-disposition). Keeps audit logs scannable over many passes and makes counts grep-able for trend analysis across audits. Previous free-form entries remain valid — the new template applies to entries going forward. Includes an empty-audit variant for "no new items" passes and explicit nesting rules for same-day continuation passes (Pass 2 / Pass 2 final / tenth-pass) to avoid sibling date headers.

## [2.8.3] - 2026-04-15

### Changed — Setup Flow Polish

Refinements to `/setup` for the project-specific knowledge tier (v2.8.0 feature), plus parser-robustness clarifications and re-run discoverability fixes.

- **Inline consent for `auto_load_project_context`** — removed the standalone Advanced Options bullet for this flag. It's now asked as the 4th follow-up question in the Project Setup subsection, only when the user enables (or keeps enabled) the project tier. Keeps the two flags (`projects_enabled` + `auto_load_project_context`) as independent opt-ins while improving discoverability at the moment of relevance.
- **Re-run and shortcut discoverability** — Project Setup follow-ups now fire for "keeps enabled" re-runs in update mode. The existing-folder detection path asks Q4 on fresh enable-via-shortcut and surfaces a Q4 status-check when the tier was previously enabled. All four user-reachable state transitions now have a `/setup` path without requiring manual config-file editing.
- **Step 7 parser rationale** — added a preamble to the formatting rules explaining that the config is parsed with pure `grep + sed` (no jq/yq/python), so future contributors understand why the constraints are strict and any deviation breaks parsing silently.
- **Empty-value formatting rule** — documented the exact byte sequence for empty values (`key:` with nothing after the colon). Explicitly called out that `key: null`, `key: ""`, `key: none`, and `key: []` parse as literal strings and silently mis-behave against validators.
- **Step 7b empty-sentinel verification** — round-trip verification now rejects the literal-string empty sentinels (`null`, `""`, `none`, `[]`) for string-valued keys with empty defaults (`critical_paths`, `projects_list`, `projects_remotes`) and rewrites them as truly empty.

### Changed — OVERVIEW.md

- Added `/wrapup` row to the skills table; the skill already exists in the plugin but wasn't listed in the user-facing overview.

### Backward Compatibility

- No schema, parser, or hook changes. Existing `~/.claude/aria-knowledge.local.md` configs continue to work unchanged.
- Users who previously enabled `projects_enabled: true` without `auto_load_project_context` explicitly set: next `/setup` run will surface the Q4 status-check in the existing-folder detection branch, giving them a discoverable toggle path.

## [2.8.2] - 2026-04-15

### Added — Per-Task Insight Batch Capture

Insight blocks (★) are now automatically captured at task completion boundaries, closing the gap where insights were lost if `/extract` wasn't run before session end.

- **`session-start-check.sh`** — injects a behavioral instruction at session start telling Claude to batch-append uncaptured Insight blocks to `insights-backlog.md` after completing discrete tasks (not mid-task). Gated by `auto_capture` config toggle (which also gates pre-compact capture, post-compact prompts, and task-created context surfacing).
- **`/extract` dedup** — already checks `insights-backlog.md` before appending, so running `/extract` after per-task capture produces no duplicates.

### Removed — Dead Stop Hook

- **`session-stop-check.sh`** — removed. Was never registered in `plugin.json` (dead code since creation). Its session-end cleanup responsibilities are covered by `/wrapup` (Step 8) and the new per-task capture. The CHANGELOG entry in v2.6.0 previously noted it was dead code.

### Changed

- **`config.sh`** — updated comment to remove stale `session-stop-check.sh` reference.
- **`OVERVIEW.md`** — updated hooks list to document per-task insight capture; replaced stale Stop hook paragraph with auto-capture description.

## [2.8.1] - 2026-04-15

### Added — User Rules Separation

A new `rules/user-rules.md` file separates user-created custom rules from plugin-shipped working rules, eliminating the numbering-collision risk where a user's added Rule 30 would conflict with a plugin-shipped Rule 30 on `/setup --update`.

- **New shipped template:** `plugin/template/rules/user-rules.md` — user-owned (never overwritten by `/setup`); ships with usage notes, U-prefix naming convention, and 4 sample rules across Team Rules / Personal Conventions / Retired sections (samples marked for deletion).
- **`/setup` updates:** `rules/user-rules.md` registered as user-owned alongside `LOCAL.md`; created once from template if missing; never diffed on subsequent runs.
- **`/rules` skill:** searches both `working-rules.md` and `user-rules.md`. Index mode shows them grouped ("Plugin Rules" + "Your Rules"). Lookup by number checks both files; warns on collisions. Search mode searches both.
- **`working-rules.md` pointer:** plugin's rules file now references `user-rules.md` in the "How to Use" section so users discover the separation naturally.

### Added — Two New Plugin Rules

- **Rule 30: Signal context pressure — don't silently degrade.** When the context window fills with file contents, tool results, and conversation history, say so explicitly rather than silently cutting corners. Long sessions are where discipline breaks down most. Context pressure is not permission to skip process steps — flag it instead of producing lower-quality output.
- **Rule 31: Diff rewrites against the original — verify nothing was dropped.** When rewriting, restructuring, or migrating a file, diff against the original to verify no content was silently lost. Complements Rule 26 (declare scope before building from references): Rule 26 prevents undeclared *additions*; Rule 31 prevents undeclared *omissions*.

Both rules originated from a parallel user's working-rules.md and were adopted into the official rule set after review confirmed they fill genuine gaps and apply universally.

### Backward Compatibility

- Existing v2.8.0 users without `user-rules.md`: `/rules` works exactly as before (searches only `working-rules.md`); next `/setup` run creates the user-rules.md template once.
- Pre-existing custom rules in `working-rules.md`: unaffected. The pointer at the top of `working-rules.md` documents where to put new custom rules going forward, but existing additions stay where they are unless the user chooses to migrate.

## [2.8.0] - 2026-04-15

### Added — Project-Specific Knowledge Tier (opt-in)

A new `projects/` tier in the knowledge folder for project-specific architecture decisions and patterns that don't yet warrant cross-project promotion. Sits between ephemeral memory files and cross-project knowledge in `approaches/`/`decisions/`/`rules/`. Validated by manual implementation in the maintainer's knowledge folder on 2026-04-15; this release formalizes the pattern as a first-class plugin feature.

**Opt-in default:** `projects_enabled: false`. Existing v2.7.x users see zero behavior change unless they opt in via `/setup`.

**Config schema (5 new fields)** — `projects_enabled`, `projects_list` (comma-separated `tag:path` pairs), `projects_remotes` (optional git-remote fallback), `projects_promotion_threshold` (default 2), `auto_load_project_context` (second opt-in for hook-driven session-start prompts).

**Setup skill (`/setup`)**
- New "Project tier scaffolding" sub-block in Step 3 — creates `projects/{tag}/{decisions,patterns}/` with auto-generated per-project READMEs from configured projects.
- Diff list updates in Step 4 — `projects/README.md` is plugin-managed (diffable on update); per-project READMEs and content under `projects/{tag}/**` are user-owned (never overwritten).
- Step 6 Advanced Options — new prompts for the 5 config fields with input validation (no `:` or `,` in tags).
- Existing-folder detection — auto-detects manually-created `projects/` folders during `/setup` re-run; auto-populates `projects_list` from detected subdirectories.

**Context skill (`/context`)** — when a query matches a project tag, also Globs `projects/{tag}/**/*.md` for project-specific files (excluding READMEs). Step 5 summary now groups results: "Project-specific" first, "Cross-project" second; empty project folders surfaced with informational note (Decision #8 — mention but don't nag).

**Extract skill (`/extract`)** — Step 0 detects current project from CWD via `kt_project_for_path` helper; Step 4 auto-prepends the project tag to backlog entry headers when CWD matches a configured project. Auto-tagging is a default, not an override (explicit project attribution from conversation context wins).

**Index skill (`/index`)** — Step 1 scans `projects/{tag}/**` in addition to cross-project tree; path-derived tag union (Decision #9 — files under `projects/proj-a/` automatically carry the `proj-a` tag even if not in YAML frontmatter); new Step 8d detects cross-project promotion candidates using filename/tag/title similarity heuristics; Step 9 enriches the Projects section with file counts, last-update dates, and promotion candidates list.

**Audit skill (`/audit-knowledge`)** — new Step 5e (Cross-Project Pattern Detection) mirrors `/index` Step 8d but runs an interactive promotion workflow: detects candidates, presents to user, synthesizes content from project-specific sources, writes the new cross-project file with `originally_at:` provenance frontmatter, and offers source-file disposition (default: stub-and-reference). Step 6 Category C routing biases toward project subfolders when item tags match configured projects. Step 7 validates the project subfolder exists in config when promoting; offers to add new projects on the fly.

**Hooks (double opt-in)**
- `session-start-check.sh` — when both `projects_enabled` AND `auto_load_project_context` are true AND CWD matches a configured project, suggests `/context {project}` to load project knowledge.
- `session-stop-check.sh` — when `projects_enabled` is true AND CWD matches a project, appends a 4th checklist item noting that `/extract` will auto-tag findings with the project tag. (Removed in v2.8.2 — this script was never registered in plugin.json.)

**Provenance convention (`originally_at:`)** — when files are promoted/synthesized across the projects/ ↔ cross-project boundary, the new file gets a YAML frontmatter field documenting source(s). Greppable consolidation history that survives git history truncation.

**New shipped template** — `plugin/template/projects/README.md` documents the projects/ tier structure, promotion ladder (project → cross-project approach → universal rule), multi-project tagging convention, indexing behavior, and `originally_at:` provenance.

**Backward compatibility verified** — sandbox test suite confirms v2.7.x configs (no projects fields) load cleanly with all new vars defaulting safely; helper function returns empty when feature disabled; validation coerces malformed values to safe defaults.

### Changed
- `config.sh` — `KT_CONFIG` now uses `${VAR:-default}` override pattern (testability improvement; production callers see no behavior change).
- `context/SKILL.md` — "Index-only" rule replaced with explicit dual-source description (index for cross-project; filesystem for project tier).

### Documentation
- New `aria/project_knowledge_plan.md` — implementation plan with phase breakdown, key design decisions, and verification steps.
- New `aria/docs/plans/2026-04-15-project-specific-knowledge-feature.md` — companion design doc with architectural rationale, alternatives considered, and open questions.

## [2.7.5] - 2026-04-09

### Added
- CODEMAP-first enforcement — two mechanisms ensure CODEMAP.md is read before codebase exploration:
  - **SessionStart hook** detects CODEMAP.md files in project directories and reminds at session start.
  - **PreToolUse hook on Glob|Grep** fires once per project per session when exploring a directory that has a CODEMAP.md ancestor.

## [2.7.4] - 2026-04-09

### Added
- `/wrapup` skill — end-of-session handoff. Reviews session work, updates PROGRESS.md and CLAUDE.md if needed, prompts for commit, verifies next session can pick up cleanly, and prompts for `/extract`. Confirms before every write. Project-agnostic — detects project from cwd markers.

## [2.7.3] - 2026-04-09

### Added
- Rule 28 (concise, precise writing) — all communication should be semantically accurate, concise, and precise. Preserves detail and nuance while eliminating verbosity.

## [2.7.2] - 2026-04-09

### Added
- Rule 28 (template; renumbered to Rule 29 in v2.7.6) — evaluate tool cost before visual testing. Code-verifiable changes skip visual testing; unpredictable visual output warrants testing with user confirmation first.
- **Origin:** DOM reorder consumed ~15% session tokens on visual testing self-evident from the code diff.

## [2.7.1] - 2026-04-09

### Added
- Skill-to-knowledge connection discovery in `/index` (Step 8c) — scans plugin skill files and auto-discovers connections to knowledge files using 4 heuristics (explicit references, Related sections, name overlap, tag/keyword overlap). Stored in `## Skill Connections` section in `index.md`.
- Skill-knowledge drift detection in `/audit-knowledge` (Step 5b) — compares skill modification dates against connected knowledge file dates to flag when a skill evolves past its documentation.
- Index freshness check in `/audit-knowledge` (Step 1b) — verifies index.md is current before audit begins.

## [2.7.0] - 2026-04-09

### Added
- `/codemap` skill — generate feature-organized CODEMAP.md for any codebase. Scans repos, detects frameworks (Django, Next.js, Express, Rails, etc.), identifies features by clustering routes/models/views, traces full-stack flows per feature (frontend routes → hooks → Redux → backend views → models → integrations), and produces a navigable reference document
- Four codemap modes: `create` (full generation from scratch), `inventory` (quick index of files/routes/models), `update` (incremental refresh using git diff), `section` (rebuild a single section)
- Directory table at top of CODEMAP.md for selective section loading — new sessions read ~50 lines to orient, then load only relevant sections via offset/limit
- Mermaid diagrams for entity relationships (erDiagram), auth flows (flowchart), and dependency graphs (flowchart) — renderable in GitHub/Obsidian for team members
- Common Change Patterns section — "how to add X" procedural recipes per framework
- Integrations summary table — all external services with env keys and consuming features
- Build Log for tracking per-section completeness and staleness
- Security issues flagged inline at point of occurrence in feature sections
- Codemap staleness detection in `/audit-knowledge` (Step 5d) — scans for CODEMAP.md files, checks last-updated date against git changes, reports status (Current/Possibly stale/Stale)
- Codemap staleness findings in `/audit-knowledge` Step 6 report with token usage warning
- Codemap update guidance in `/audit-knowledge` Step 7 — directs users to run `/codemap update` in a separate session to avoid context blow-up

## [2.6.0] - 2026-04-07

### Added
- `/ask` skill — research a question, check existing knowledge first, save answer directly to promoted files (skips backlogs)
- `/intake` skill — bulk knowledge import from file paths, directories, glob patterns, or URLs with preview-before-staging and deduplication against existing knowledge
- Entity detection in `/index` (Step 8b) — scans promoted files for recurring proper nouns (tools, services, APIs) appearing in 2+ files, generates `## Entities` section in `index.md`
- Entity integrity checks in `/audit-knowledge` Step 5b — flags stale entity references and missing entities
- "Update existing" option in `/audit-knowledge` Step 7 — merge backlog items into existing promoted docs instead of always creating new files
- `digest-transcript.sh` — standalone script that extracts high-signal content from JSONL session transcripts (~1-2% of original token cost)
- `README.md` inside `plugin/` — usage-focused docs available when plugin is installed from marketplace
- `LICENSE` inside `plugin/` — CC BY-NC-SA 4.0 for marketplace requirement
- Discovery metadata in `plugin.json` — homepage, repository, license, keywords for marketplace searchability

### Changed
- `/audit-knowledge` Step 2d now runs transcript digest before reading pre-compact snapshots (default), reducing ~50K+ token reads to ~2-3K; use `detailed` flag for full review
- Session-start hook messages shortened ~50% across all 7 message types — collapsed redundant error branches into single flag-based pattern
- Session-stop hook shortened from ~100 to ~35 tokens
- Unregistered Stop hook from `plugin.json` — fired on every response (15-30 times per session), not just session end; `/extract` and PreCompact capture cover its checks. Script kept in `bin/` for optional re-enablement.

### Fixed
- Remove `category` field from `plugin.json` per validator warning (belongs in `marketplace.json`)

## [2.5.1] - 2026-04-07

### Fixed
- Register Stop hook in plugin.json — `session-stop-check.sh` was never executing (dead code)
- Guard empty `SESSION_ID` in task-context-check to prevent cooldown file collision across sessions
- Remove hardcoded user-specific Projects path from `/index` skill
- Fix `allowed-tools` frontmatter in `/help` skill (quoted empty string → bare empty)
- Use `mktemp` for temp files in task-context-check instead of predictable `$$` PID names
- Document intentional no-default for `KT_CRITICAL_PATHS` in config.sh

## [2.5.0] - 2026-04-07

### Added
- PreCompact hook — saves transcript snapshot to `intake/pre-compact-captures/` before context compaction, preserving knowledge that would otherwise be lost to summarization
- PostCompact hook — prompts user to review pre-compaction snapshots immediately after compaction
- TaskCreated hook — auto-context retrieval that matches task keywords against the tag index and surfaces relevant knowledge files with 30-second cooldown for batch creation
- `/clip` skill — quick-save URLs or text snippets to `intake/clippings/` without leaving the session
- `/stats` skill — read-only knowledge base health dashboard (file counts, backlog depth, audit status, tag stats, coverage gaps)
- `QUICKSTART.md` — concise "your first 3 sessions" guide for marketplace users
- First-run welcome message — friendly introduction on first session instead of audit prompts
- `auto_capture` config key (default: true) — gates all automatic features (pre-compact capture, post-compact prompt, task-created context retrieval)
- `critical_paths` config key (default: empty) — comma-separated path patterns that always require HIGH impact Rule 22 assessment
- `audit_cadence_update` config key (default: 30) — days between update check prompts, parsed from config file's own `/setup on` date
- `intake/pre-compact-captures/` directory in template structure
- `/help` skill — quick command reference table with descriptions for all available skills

### Changed
- `/setup` — new fields in cadence display (update check), advanced options (auto-capture, critical paths), config write, and verification
- `/audit-knowledge` — new Step 2d scans pre-compact captures for extractable knowledge, new Step 6 section presents findings
- `config.sh` — parses `audit_cadence_update`, `auto_capture`, and `critical_paths` with defaults and validation
- `session-start-check.sh` — first-run detection (skips audit prompts on fresh install), update check cadence using config file date
- `pre-edit-check.sh` — matches file paths against user-configured `critical_paths` patterns

## [2.4.0] - 2026-04-06

### Added
- `/index` skill — scans promoted knowledge files, normalizes tags, detects staleness, suggests cross-references between files with 2+ shared tags, updates project-to-tag mappings, and regenerates `index.md`
- `/context` skill — on-demand knowledge retrieval by topic tags with OR (default) and AND modes, project tag expansion (e.g., `/context ss` expands to all Seersite-relevant tags), summary-first presentation with selective file loading
- Tag convention — YAML frontmatter `tags: [tag1, tag2]` on all promoted knowledge files, with seeded known tags across tech domain, cross-cutting, tool/service, process, and project groups
- `index.md` generated artifact at knowledge folder root — tag-first index with Known Tags, Tag Index, Other Tags, Stale Files, and Untagged Files sections
- Staleness detection — flags promoted files not updated within configurable threshold (default: 6 months)
- Bidirectional cross-reference linking — `/index` suggests `## Related` links between files sharing 2+ tags, detects reverse link gaps
- Session-start knowledge surfacing — hook prompts Claude to suggest `/context` command after user states their task (when index exists)
- Planning path abbreviated Rule 22 — `pre-edit-check.sh` and `post-edit-check.sh` hook scripts detect `docs/specs/` and `docs/plans/` paths and allow one-line assessment instead of full framework, with protected filename safeguard for operational files (CLAUDE.md, working-rules.md, etc.)
- `freeform_promotion_threshold` config key (default: 3) — suggest promoting freeform tags to known after this many files
- `staleness_threshold_months` config key (default: 6) — flag knowledge files older than this

### Changed
- `/audit-knowledge` — new Step 5c cross-references backlog entries against promoted docs (topic overlap and potential invalidation detection), new Step 6 sections for Stale Knowledge and Cross-Reference Findings, new Step 7b rebuilds index after promotions
- `/setup` — offers advanced options for freeform promotion threshold and staleness threshold
- `plugin.json` hooks — PreToolUse and PostToolUse now use bash scripts (`pre-edit-check.sh`, `post-edit-check.sh`) instead of inline echo commands, enabling planning path detection
- `config.sh` — parses `freeform_promotion_threshold` and `staleness_threshold_months` with defaults and numeric validation
- `LOCAL.md` template — format templates now include `tags:` in frontmatter, new Tag Convention section, `/context` and `/index` added to When to Read table
- `README.md` template — `index.md` in structure diagram, tagging and index conventions added

## [2.3.2] - 2026-04-06

### Added
- `intake/clippings/`, `intake/notes/`, `intake/attachments/` subdirectories in template — new users now get the full content capture structure on `/setup`
- "Extended Structure" example section in `LOCAL.md` template — shows users how to document custom subdirectory organization
- Comprehensive feature list in README
- Obsidian Web Clipper recommendation in README and OVERVIEW template
- Support section with PayPal and Venmo in README
- Release download link in install instructions

### Changed
- Removed `setup_version` from config template (unused field)

### Fixed
- Documented known Claude Code "hook error" UI bug (anthropics/claude-code#17088) in README and OVERVIEW template

## [2.3.0] - 2026-04-05

### Added
- `OVERVIEW.md` template — full design philosophy and rationale, shipped with plugin
- `## Related` cross-references in `enforcement-mechanisms.md` template
- `OVERVIEW.md` added to `/setup` expected files and diff lists
- Project moved to standalone repository (`Projects/aria/`)

### Changed
- `README.md` template now references `OVERVIEW.md`

## [2.0.0] - Previous

- Initial versioned release with setup wizard, extraction, audits, backlogs, rules lookup
- Rule 22 enforcement hooks (PreToolUse/PostToolUse)
- Session start/stop hooks
- Knowledge folder templating system
