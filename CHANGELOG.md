# Changelog

All notable changes to ARIA will be documented in this file.

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
