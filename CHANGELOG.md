# Changelog

All notable changes to ARIA will be documented in this file.

## [2.13.0] - 2026-04-28

Minor release. Adds a third knowledge tier — **Shared Knowledge** — that lets developers promote selected personal knowledge into per-repo `_project-knowledge/` folders so teammates working in the same code repo can find and read it. The personal knowledge tier (`~/Projects/knowledge/`) and project knowledge tier (`projects/{tag}/`) are unchanged; the new tier composes with both. Fully opt-in, gated by the `projects_shared_knowledge` config flag.

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

1. *"Enable shared knowledge feature?"* — sets `projects_shared_knowledge: true|false`
2. *"Author tag for shared-knowledge filenames?"* — sets `author_tag: <string>` (falls back to deriving from `git config user.name`)

Followed by an optional offer to add `_project-knowledge/` references to each project's CLAUDE.md (helps non-ARIA teammates discover the convention) and an offer to invoke `/audit-share` inline as the cold-start sweep.

### Changed — `/audit-knowledge` Accept submenu disposition `plan` → `backlog`

The previous `plan` disposition wrote to `plans/{slug}.md` (or `PLAN.md`) with `## Goal`/`## Why` headers — overloading the `plan` term with execution-plan semantics that already had separate homes (`docs/plans/`, `superpowers:writing-plans` output). Renamed to `backlog` with destination `IDEAS-BACKLOG.md` at the project-root path; treats the destination as a queue (dated entries) rather than a sequenced execution doc.

When `projects_shared_knowledge: true`, the destination shifts to `<project-root>/_project-knowledge/IDEAS-BACKLOG.md` (team-visible); migration of existing project-root `IDEAS-BACKLOG.md` files happens on first `/audit-share` invocation.

16 surfaces across 7 files updated for terminology consistency: `audit-knowledge/SKILL.md`, `template/intake/ideas/README.md`, `template/OVERVIEW.md`, `template/README.md`, `QUICKSTART.md`, `extract/SKILL.md`, `audit-config/SKILL.md`. The previous `audit-config` Step 5 PLAN.md alignment check (now obsolete under queue semantics) replaced with an IDEAS-BACKLOG.md presence check.

### Changed — `/setup` Step 8 summary surfaces shared-knowledge status

Adds one bullet to the post-setup confirmation: *"Shared knowledge: enabled (author_tag: {tag}) | disabled (opt-in via re-run /setup)"*.

### Upgrade notes

- **Reinstall required:** copy `plugin/` to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` (or unzip the v2.13.0 release zip into that directory).
- **Run `/setup` after upgrade** to record `last_setup_version: 2.13.0` and (optionally) opt into the new Shared Knowledge tier. The two new config fields (`projects_shared_knowledge`, `author_tag`) are introduced as `[NEW]` markers in the advanced-options bundle on re-run.
- **Backward-compatible defaults.** `projects_shared_knowledge: false` is the default; existing users who don't opt in see no behavior change. The `plan → backlog` disposition rename is also backward-compatible — the new disposition keyword `backlog` is recognized; users with existing IDEAS-BACKLOG.md files at project-root continue to work.
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
  cs:
    backend: commonspace-app
    web: commonspace-ui-v3
    mobile: commonspace-mobile-ui
  ss:
    backend: seersite-server
    web: seersite-frontend
```

- **Sparse entries** — only multi-repo projects appear; single-repo projects (e.g., `aria`, `df`, `cs-builder`) omit entries.
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

**Index skill (`/index`)** — Step 1 scans `projects/{tag}/**` in addition to cross-project tree; path-derived tag union (Decision #9 — files under `projects/cs-builder/` automatically carry the `cs-builder` tag even if not in YAML frontmatter); new Step 8d detects cross-project promotion candidates using filename/tag/title similarity heuristics; Step 9 enriches the Projects section with file counts, last-update dates, and promotion candidates list.

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
- Remove hardcoded `/Users/mikeprasad/Projects/CLAUDE.md` path from `/index` skill
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
