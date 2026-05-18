<p align="left">
  <img src="aria-icon-rounded.png" width="120" alt="ARIA">
</p>

# ARIA — Applied Reasoning and Insight Architecture

**The AI captures. The human promotes. Trusted knowledge acts.**

> **New to ARIA?** See [QUICKSTART.md](QUICKSTART.md) — 5-minute setup + best practices by session phase.

ARIA is a Claude Code plugin that gives AI coding sessions persistent memory and structured discipline. It manages a complete knowledge lifecycle — capturing insights, decisions, and feedback during sessions, staging them in backlogs for human review, and promoting what matters into a searchable, tag-indexed knowledge base. Session hooks prevent knowledge loss during context compaction, surface relevant knowledge when tasks are created, and enforce a change decision framework at every file edit, requiring visible impact assessment and scope verification before and after changes. Each session builds on the last instead of starting from scratch.

Beyond capture, ARIA provides active tooling: `/codemap` generates feature-organized maps that trace full-stack flows; `/stitch` builds cross-repo binding tables for product groups; `/distill` turns raw ticket text into tiered executable task specs that cite real files. `/ask` researches questions and saves answers as knowledge docs. `/intake` bulk-imports from files, URLs, or directories. `/audit-config` and `/audit-knowledge` detect drift, staleness, and gaps on configurable cadences. `/wrapup` (interactive) and `/handoff` (combined-go or `auto`) handle end-of-session handoff and emit paste-ready next-session openers. An optional project-specific tier (v2.8.0+) organizes architecture decisions and patterns by project, with cross-project promotion when patterns validate across multiple projects. Everything is plain markdown, works as an Obsidian vault, and follows the core philosophy: **the AI captures, the human promotes, trusted knowledge acts.**

## The problem

AI coding sessions generate valuable knowledge every day. Architecture decisions. Debugging discoveries. Product constraints. Team conventions. Reviewer feedback. Lessons learned the hard way.

Then the session ends. Context gets compacted. Decisions disappear into transcripts. The next session repeats old questions, misses known constraints, or reopens choices already settled.

Most memory tools solve this by helping the assistant remember more. ARIA goes further: it asks **what knowledge is worth trusting**, **how should it be reviewed**, and **how should that trusted knowledge actively shape the next decision, task, and code change.** That is the difference between passive memory and applied operational knowledge.

## How It Works

Knowledge moves through a five-phase lifecycle: **Capture → Govern → Promote → Apply → Refresh.**

### Capture

Preserve session knowledge before context evaporates.

- `/extract` — Scan conversations for uncaptured insights, decisions, feedback, references, and ideas. Deduplicates against existing entries.
- `/clip` — Quick-save URLs or text snippets to intake without leaving the session.
- `/ask` — Research a question, check existing knowledge first, save the answer directly as a knowledge doc.
- `/intake` — Bulk import from files, directories, or URLs with preview before staging.
- `/snapshot` — On-demand raw transcript archive. Same artifact the PreCompact hook produces, invoked explicitly.
- `/wrapup` — End-of-session handoff: reviews work, updates PROGRESS.md/CLAUDE.md/memory, prompts for commit and `/extract`, verifies the next session can pick up.
- `/handoff` (`/handoff auto`) — Express handoff. Same coverage as `/wrapup` compressed into a single combined-go review (or silent `auto` mode). Always emits a paste-ready next-session opener as the headline artifact.

### Govern

Decide what's worth keeping. Captured knowledge enters backlogs, not the canonical knowledge base.

- `/backlog` — View and manage pending items across all four backlogs (insights, decisions, extraction, rules).
- `/audit-knowledge` — Review backlogs and memory for promotable knowledge. Detects emerging themes across entries. Checks codemap staleness. The trust layer that prevents memory drift.

This phase is what separates ARIA from systems that auto-canonicalize: confident-wrong knowledge cannot quietly become permanent. Humans are the gate.

### Promote

Approved knowledge becomes durable markdown — rules, approaches, decisions, guides, references. Each promotion is a human decision, traceable through git history.

- `/index` — Rebuild the tag index. Normalizes tags, flags untagged files, suggests cross-references, updates project mappings.
- `/audit-share` (alias `/share-audit`) — Batch-promote personal knowledge to team-visible per-repo `_project-knowledge/` folders when the optional shared-knowledge tier is enabled. Per-item review with sanitization warnings on public-repo targets. See [Shared knowledge tier](#shared-knowledge-tier-since-v213) below.
- An optional **project-specific tier** (v2.8.0+) organizes architecture decisions and patterns by project under `projects/{tag}/`. Cross-project promotion fires when patterns validate across multiple projects.

### Apply

A trusted knowledge base only matters if it shapes future work. ARIA's "Applied" framing lives here — promoted knowledge actively guides reasoning, planning, and code changes.

**Rule 22 — change decision framework enforced at every Edit/Write via hooks.**

- **PreToolUse hook** — Before every file edit: assess impact (HIGH/LOW), state alternatives considered, define scope.
- **PostToolUse hook** — After every edit: verify scope wasn't exceeded, check for secondary impact on parents/siblings/dependents.
- **Structural signal surfacing** — edits touching auth, migrations, models/schemas, routing, or external-service integrations get advisory labels even when the content classifies as Low impact.
- **Batch-manifest ceremony reduction** — declared-scope multi-file work compresses Rule 22 ceremony for low-impact ops in-scope. Protected paths, declared-high ops, structural signals, and out-of-scope drift still get the full assessment. Requires `jq`.
- Configurable critical paths that always require full impact assessment.
- Ships 34 working rules, a 7-step change decision framework with worked examples, and enforcement mechanisms documentation.

**Knowledge surfaces during work.**

- `/context` — Load relevant knowledge by topic using the tag index, with project expansion. `/context {project-tag}` also loads project-specific files from `projects/{tag}/**`, grouped separately from cross-project results.
- `/rules` — Quick lookup into the 34 working rules by number or keyword.

**Codebase and task mapping turn ambiguous surface area into structured artifacts Claude can ground decisions against.**

- `/codemap` — Feature-organized reference for any repository. Scans repos, detects frameworks, traces full-stack flows (routes → hooks → state → views → models → integrations). Four modes: `create` (full generation), `inventory` (quick index), `update` (incremental via git diff), `section` (rebuild one section). Stack-aware cross-cutting candidates (URLConf tree, signal registry, env matrix, route tree) surface as explicit gap prompts during generation.
- `/stitch` — Cross-repo binding artifact for product groups (backend + frontends). Tables for group identity, auth path, endpoint stitch, entity stitch, integration stitch, and a drift log. Modes: `create`, `verify`, `diff`, `section`. Drift detection follows a precedence ladder; output labels its drift source so you can trust or distrust accordingly.
- `/distill` — Turns raw ticket text into an executable task spec following a `TASK.schema.md` contract. Auto-tiers by complexity (micro / standard / full). Conditional layers (Frontend / Backend / Database) appear only when the task touches them. Optional `--group` flag loads CODEMAP + STITCH context for cited-path specs.
- `/prospect` — Forward-looking pre-mortem on a plan or approach that's been *created but not yet executed*. Mirror of `/retrospect`'s shape — same 10-section structure, same per-step validation discipline, applied to imagined steps rather than shipped fixes. Six positional scopes: `plan` (default — current session's articulated plan), `session`, `todos`, `file <path>`, `linear <id>`, `branch <name>`. Per-step actions: PROCEED / SHRINK / SPLIT / DEFER / KILL. Hard rule: a step's Action cannot be PROCEED unless its Risk? is ✅ Pre-validated, OR ⚠ Theory-driven WITH explicit "Acceptable risk because: …" justification. Soft-suggested before code lands ("let me implement…", "ok ship it" cues). Output saved to `logs/prospect/`.
- `/retrospect` — Structured retrospective on a shipped commit range, single commit, PR, release, deployment, or current session. Seven positional scopes: `commit <hash>`, `range <ref1>..<ref2>`, `pr <num>`, `session`, `release` (since most recent semver tag), `deployment` (with hybrid auto-detect cascade: GH releases → semver tags → last main commit → prompt user), or auto-range (default — last push). Enforces per-fix validation (no fix marked "shipped" without named evidence — log event, reproduction-then-fix-verified, production instrumentation, or deployed-state check), surfaces simpler alternatives and maintenance cost per change, runs a failure-mode pattern check against a growing canonical + project-specific library, re-diagnoses when fixes failed, and emits an action verdict (KEEP / REVERT / REDO-MINIMAL / RESHIP-AND-VERIFY / FOLLOWUP-TICKET / HOLD-PENDING-EVIDENCE / HOLD-PENDING-VERIFICATION). RESHIP-AND-VERIFY fires when bundle verification confirms the fix didn't ship — the code is correct but the deploy didn't land. Soft-suggested when the user reports a regression. Output saved to `logs/retrospect/`.
- **Evidence-Sourcing Pass (both `/prospect` and `/retrospect`)** — A synchronous pass between enumerate and report that autonomously sources accessible evidence (codebase reads, public docs, MCP queries, deployed bundle fetches, production log queries) and surfaces user-input asks for anything that requires judgment. Converts unsupported assumptions to ✅/❌ before the report finalizes — only genuinely residual uncertainty appears in the final "next-step evidence ask" section. Skip with `--no-source` for a quick structural review. Reports persist with structured YAML frontmatter (`type`, `scope`, `tickets`, `sourcing_pass`, `patterns_hit`, `overall_verdict`/`overall_outcome`, `related`, `tags`) and become discoverable via `/context`.

**Hooks make application continuous in the background.**

- **PreToolUse hook on Glob/Grep** — Reminds to read CODEMAP.md (and sibling STITCH.md when present) before exploring a codebase directly. Fires once per project per session.
- **TaskCreated hook** — Surfaces relevant knowledge files when tasks are created (tag index matching).
- **PreCompact hook** — Saves transcript snapshot before context compaction.
- **PostCompact hook** — Prompts to review captured snapshot after compaction.
- `auto_capture` toggle gates all automatic features.

### Refresh

Knowledge bases rot when nothing forces a review. ARIA treats freshness as a first-class concern and solves it through **process**, not storage format.

- **`Last updated` frontmatter on every knowledge file** enables mechanical staleness checks.
- **Configurable staleness thresholds** — `ideas_staleness_threshold_days` (default 7) for `intake/ideas/` entries; `staleness_threshold_months` for promoted knowledge files. Tune per install in `~/.claude/aria-knowledge.local.md`.
- **Audit cadences** enforce periodic review. SessionStart hook prompts when `/audit-knowledge` or `/audit-config` is overdue.
- **Stale-first surfacing** — `/audit-knowledge` sorts stale items above fresh ones and demands explicit disposition.
- **Drift detection** — `/audit-config` scans CLAUDE.md files and configs for broken references; `/audit-knowledge` Step 5b3 checks skill-knowledge connections; `/codemap update` refreshes incrementally via git diff; `/index` flags untagged or stale files and suggests cross-references.
- **Rule 22 enforcement** — every Edit/Write requires a visible impact assessment and post-edit scope check. No silent drift because no silent edits.
- `/stats` — Knowledge base health dashboard — file counts, backlog depth, audit status, tag coverage, gaps.

Format determines auditability; process determines freshness. ARIA's answer is plain markdown for auditability + layered review cadences for freshness + humans in the promotion loop so wrong knowledge doesn't accumulate silently.

## Ideas lifecycle (since v2.12)

Ideas — feature proposals, bug reports, design suggestions — flow into `intake/ideas/` during `/extract`. They have a distinct lifecycle from the four knowledge backlogs because they describe **what should be different**, not **what is**.

1. **Capture** — `/extract` writes one file per idea to `intake/ideas/`, with YAML frontmatter (date, project, type, title) and a Proposal/Motivation/Source body.
2. **Stale-first surfacing** — `/audit-knowledge` sorts stale ideas above fresh ones (default 7 days) and forces explicit disposition on stale entries. Fresh ideas auto-defer; stale ideas can't.
3. **Seven-destination Accept submenu** — each accepted idea routes to one of: `tracker | roadmap | todo | adr | backlog | bundle | rule`.
4. **Detection-aware routing** — `roadmap` and `todo` only appear when `ROADMAP.md` / `TODO.md` exists at the project root or under `docs/`. The submenu shrinks per idea so users can't pick a destination that doesn't fit.
5. **Bundle clustering** — when 2+ ideas in the same project share ≥2 significant title words, the audit offers to merge them into one disposition with a sub-prompt for the merged file's destination.
6. **`ticketing_plugins` config** — declare your ticket-drafting plugin per project tag (e.g., `proj-a:foo-ticket`) and `/audit-knowledge` prints a one-line hint at `Accept → tracker` time. Hint only — never auto-invokes another plugin.

Ideas never promote directly into `approaches/`, `decisions/`, or `rules/`. The `adr` and `rule` destinations route through their respective backlogs (`decisions-backlog.md`, `rules-backlog.md`) for normal audit-cycle review. Rejected ideas are deleted (git history is the audit trail); deferred ideas stay in `intake/ideas/` until they age into stale.

## Shared knowledge tier (since v2.13)

Personal knowledge captures stay on one developer's laptop. The Shared Knowledge tier adds a third level alongside personal (`~/Projects/knowledge/`) and project-specific (`projects/{tag}/`): selected items can be promoted to per-repo `_project-knowledge/` folders so teammates working in the same code repo can find and read them. Independent records, not a sync layer — personal copies stay where they are; team copies get committed through normal git/PR review.

1. **Per-project opt-in** — the `projects_shared_knowledge` config field is a comma-separated tag list (e.g., `cs,ss`); empty/missing means feature disabled. Most users have many repos but only a few with teams; opt in for the ones that benefit, leave the rest as personal-only.
2. **`/audit-share` (alias `/share-audit`)** — batch-review surface. Walks personal knowledge folders + IDEAS-BACKLOG.md entries, filters by enabled-project list, recommends destinations grouped by action, lets the user `all` / specific numbers / `modify N` / `skip`. Public-repo targets get a sanitization warn-prompt before each write.
3. **Folder + filename convention** — `<project-root>/_project-knowledge/{YYYY-MM-DD}-{author}-{slug}.md`; cross-cutting items live in `_project-knowledge/cross/`. The leading underscore sorts to top of repo listings; tool-agnostic so non-ARIA teammates can read/write the markdown directly.
4. **Frontmatter back-pointers** — personal copies gain a `shared:` array entry pointing at where each share landed; team copies carry `origin:`, `shared_by:`, `shared_at:` fields. Provenance both directions.
5. **CLAUDE.md reference offer at first-write** — when `/audit-share` writes the first file to a repo's `_project-knowledge/`, it offers to append a 5-line "Team-Shared Knowledge" section to that repo's `CLAUDE.md` so teammates not using ARIA can discover the convention. Per-repo confirmation, default `N`, three warning tiers based on git-tracked + remote-visibility detection (public / private / unknown / untracked). For multi-repo projects (`projects_groups` configured), an additional offer fires for the container's `CLAUDE.md` with a group-aware text variant naming each sub-repo's `_project-knowledge/`.
6. **Read-side via `/index` + `/context`** — `/index` Phase 5 scans enabled projects' `_project-knowledge/` folders into the tag index under a new `## Team-Shared Tag Index` section; `/context` adds a "Team-shared" presentation grouping above project-specific and cross-project results. Tag-based discovery composes naturally — `/context api` surfaces team-shared, project, and cross-project files together.

Personal vs team copies are intentionally independent records. They can drift; re-running `/audit-share` after editing a personal file will offer to share again (incrementing the `shared:` array, not overwriting). Solves the "knowledge stays trapped on one laptop" failure mode without violating ARIA's local-first or human-governed-trust principles.

## Key Habits

Two habits determine how much value you get from ARIA:

1. **Run `/extract` before ending sessions** — stages insights, decisions, and feedback into backlogs while the full conversation is in context. Skip it, and knowledge only survives via raw pre-compact transcript snapshots (higher token cost to review later, lower fidelity). The Stop hook and `/wrapup` both prompt for this.

2. **Respond to audit prompts** — when "Knowledge audit due" appears at session start, pending backlog items are waiting for review. Until audited, they can't be surfaced by `/context`, theme clusters go undetected, and items grow stale. A few minutes of review keeps the pipeline flowing.

Everything else — Rule 22 enforcement, transcript capture, context surfacing, codemap reminders — runs automatically via hooks.

See [OVERVIEW.md](plugin/template/OVERVIEW.md) for the full explanation of why these matter.

## Install

### CLI

1. Copy the `plugin/` directory to your Claude Code plugins folder
2. Run `/setup` to configure your knowledge folder
3. Start working — the plugin captures knowledge automatically

### Desktop / IDE

1. Download the latest zip from [Releases](https://github.com/mikeprasad/aria-knowledge/releases)
2. In Claude Code, go to **Customize > Add Plugin > Local** and select the downloaded zip
3. Run `/setup` to configure your knowledge folder

After install, run `/help` anytime to see the full command catalog with model recommendations.

### Codex Port

A standalone Codex port now lives in [`plugin-codex/`](plugin-codex/). It keeps
the Claude-standard ARIA knowledge folder and content schema while adapting the
plugin manifest, hooks, and command entrypoints for Codex. See
[`plugin-codex/README.md`](plugin-codex/README.md) for current parity notes and
setup details.

### Cursor Port

A standalone Cursor port lives in [`cursor-template/`](cursor-template/). Unlike
the Claude and Codex ports, it is a **repo skeleton**, not a plugin install:
unzip the released artifact (or copy the folder contents) into the root of your
own project, then restart Cursor. The port keeps the same knowledge folder
schema, but compiles the 25 canonical skills into 5 `.cursor/rules/*.mdc` files
because Cursor's Rules system doesn't have a one-skill-per-folder concept.
See [`cursor-template/QUICKSTART.md`](cursor-template/QUICKSTART.md) for setup
and [`cursor-template/PORTING.md`](cursor-template/PORTING.md) for the parity
matrix, residual enforcement gaps, and the skill-to-`.mdc` mapping that needs
manual sync on canonical changes.

## Works Well With Obsidian

The knowledge folder is plain markdown — it works great as an Obsidian vault. We recommend using [Obsidian Web Clipper](https://obsidian.md/clipper) to save articles and references directly into `intake/clippings/`, where ARIA's audit process can review and promote them.

## Privacy-first by design

ARIA runs locally. It does not collect analytics, send telemetry, make network requests, use cookies, connect to external services, or share your knowledge base with the plugin author or third parties. Knowledge files, backlogs, indexes, config, transcript-derived artifacts, and project context all stay on your filesystem.

Audit logs and disposition history live alongside your knowledge folder under git, so every promotion and rejection is traceable in your own repo — not a vendor's database.

## Who ARIA is for

ARIA is for developers and teams using Claude Code who want:

- Persistent memory across sessions instead of starting from scratch
- Human-reviewed knowledge instead of automatic memory drift
- A structured way to capture decisions, lessons, and project context
- Safer AI-assisted code changes via edit-time decision discipline
- Better handoff after compaction or long sessions
- Codebase maps that reduce rediscovery
- Task specs grounded in real repository context
- Markdown knowledge that remains readable, portable, diffable, and versionable

It's especially useful when AI is not just answering questions but actively shaping code, architecture, tasks, and product decisions.

## Philosophy

ARIA takes the position that **the LLM captures, the human promotes, trusted knowledge acts.** AI is excellent at noticing and structuring knowledge during sessions. Deciding what's load-bearing vs. noise requires human judgment. And once trusted, that knowledge is most useful when it actively shapes the next decision — through context loading, rules surfacing, codebase mapping, task distillation, and Rule 22 edit-time discipline.

See [plugin/template/OVERVIEW.md](plugin/template/OVERVIEW.md) for the full design rationale.

## Evidence and limits

ARIA is shaped by real-failure data from the plugin author's projects, not controlled study. Behavioral effects are asserted from experience, not benchmarks. The strongest single calibration in the canonical retrospect-pattern library is a five-instance cs-builder cycle on 2026-05-05; most other patterns are seeded from one or two incidents. There are no before/after measurements of ARIA's effect on output quality across the broader developer population.

[The 4-line CLAUDE.md from `forrestchang/andrej-karpathy-skills`](https://github.com/forrestchang/andrej-karpathy-skills) — 60K+ stars on a single behavioral file derived from [Andrej Karpathy's January 2026 diagnosis](https://x.com/karpathy/status/2015883857489522876) — has the same evidence shape: strong resonance, no controlled study. ARIA shares that honest limit and now ships those 4 principles as the **Behavioral Foundation** preamble in `working-rules.md`, with the 34 rules positioned as the operationalized expansion below them.

**Where ARIA is most likely to help:**

- Multi-repo, multi-team operational work where decisions and rules need to persist across sessions
- Developers who have already accumulated knowledge files and want a discipline layer rather than just storage
- Codebases where confident-wrong AI output has measurable downstream cost (production users, regulated content, irreversible operations)

**Where ARIA may be overkill:**

- One-off scripts or single-file projects — the 4-line behavioral foundation alone is often sufficient
- Greenfield codebases without the recurring-context problem ARIA solves
- Teams that haven't yet experienced the AI-coding failure modes ARIA's rules target — discipline imposed before pain teaches it tends to be ignored

The 4-line foundation is the lightest path; the full 34 rules + lifecycle is the heaviest. Match the shape to your problem. ARIA's scope is justified by the operational context above, not added for its own sake.

## ARIA vs Other Memory Architectures

ARIA, Karpathy-style markdown wikis, graph-DB memory systems (mem0, Graphiti, Zep), Basic Memory, and MCP memory servers all solve "give the LLM persistent memory" — but they optimize different things. Understanding the axes helps you pick correctly.

| Axis | ARIA | Karpathy Wiki | Graph DB Memory |
|------|------|---------------|-----------------|
| **Storage** | Markdown + tag index | Markdown + backlinks | Vector + graph nodes |
| **Curation authority** | Human promotes | LLM auto-compiles + lints | LLM auto-updates |
| **Auditability** | High — diffable git history, every promotion is a human decision | High — files are source of truth, but LLM authorship obscures intent | Low — embedding space is opaque |
| **Freshness mechanism** | Audit cadences + staleness thresholds + Rule 22 edits | LLM linting passes ("self-healing") | Automatic updates on new inputs |
| **Process discipline** | Rule 22 change decision framework enforced at every edit | None formalized | None formalized |
| **Active application** | Rule 22 edits, /context, /rules, /codemap, /stitch, /distill | Wiki retrieval | Vector + graph retrieval |
| **Failure mode** | Slower curation (humans are the rate-limit) | Confident-wrong LLM rewrites compound silently across backlinks | Hallucinated updates cascade; can't trace back to source |
| **Ideal scale** | 100–1000 high-signal docs; operational knowledge | 100–10000 docs; personal research | Millions of docs; retrieval-heavy agent workloads |

The shared instinct with Karpathy is strong: markdown as source of truth, human-readable, diffable, no vendor lock-in. ARIA diverges on the central question — **who decides what becomes durable knowledge?** Karpathy's answer is the LLM, compiling and linting autonomously ("You rarely ever write or edit the wiki manually; it's the domain of the LLM"). ARIA's answer is the human, reviewing LLM-captured candidates during audit.

This reflects a domain difference, not a quality judgment. **Karpathy's model is excellent for automated research compilation** — synthesizing papers, building a personal wiki of evolving understanding, where the LLM's authorial speed is the point and occasional drift is acceptable because the artifact isn't load-bearing on daily decisions. **ARIA is built for operationally applied decision-making** — working rules, architecture decisions, team conventions, and project knowledge that feed into code and product decisions every day. In that domain, an LLM-promoted wrong rule cascading across backlinks degrades real output before anyone notices, which is why ADR 010 ("LLM captures, human promotes") keeps the human gate in place. Different tool for a different job.

Graph-DB memory systems win on retrieval quality — vector search + graph traversal beats grep at scale. They lose on provenance and curation discipline. If retrieval recall is your bottleneck, ARIA and graph DB aren't mutually exclusive: use ARIA as the capture and curation layer, pipe promoted markdown into a graph DB for retrieval.

**Basic Memory + MCP memory servers** give assistants persistent memory across sessions, often as entities/relations or local markdown notes. They optimize for general-purpose recall and broad compatibility. ARIA is more opinionated and developer-workflow specific: structured backlogs, promotion workflows, audits, codebase maps, cross-repo stitching, task distillation, and Rule 22 edit-time discipline. They can sit alongside ARIA — ARIA curates the trusted-decision tier, generic memory layers handle general recall.

Pick the tool that matches the actual pain:

- **Operational knowledge that drives decisions and code → ARIA.** Human gate prevents auto-accumulation of confident errors. Rule 22 prevents silent drift. Active application via /context, /rules, /codemap, /stitch, /distill.
- **Slow retrieval across thousands of docs → Graph DB.** Vector search solves what grep doesn't.
- **Automated research compilation and evolving personal wikis → Karpathy wiki.** LLM-authored synthesis is the strength; great when the artifact is read, not acted on.
- **General-purpose persistent memory for any assistant → Basic Memory or MCP memory servers.** Lower opinionation, broader compatibility, simpler scope.

## Context efficiency over time

ARIA is designed to improve context efficiency over time, not guarantee lower token usage in any single session. It adds structure in the moment — Rule 22 checks, hooks, extraction, audits, and context surfacing all consume tokens. For a one-off task, that overhead may exceed working without a knowledge system.

The benefit appears across repeated work. ARIA reduces context waste by replacing repeated rediscovery with compact, reviewed, task-relevant knowledge:

- Promoted rules instead of repeated explanations
- Decisions and guides instead of long chat history
- CODEMAP and STITCH files instead of repeated repository exploration
- `/context` and `/rules` instead of dumping broad documentation into every session
- `/extract` and `/audit-knowledge` instead of reviewing raw transcript snapshots later

The goal is not fewer tokens overall — it's fewer tokens spent re-learning the same things, and more tokens applying trusted knowledge to the next task, decision, and code change.

## Model Recommendations

ARIA skills vary in how much they benefit from stronger models. These are recommendations only — nothing is enforced. Switch per session via `/model` before running a skill.

- **Opus 4.6 (1M context), medium-to-high effort** — `/extract`, `/audit-knowledge`, `/audit-config`. Judgment-heavy: deciding what's load-bearing vs. noise, cross-referencing backlogs against the promoted index, detecting drift across configs. A weaker model over-captures (backlog noise) or under-captures (misses non-obvious feedback). ARIA's compliance discipline benefits from the extra reasoning budget (more reliable Low/High assessments, less tool-call skipping on audit skills).
- **Opus 4.6 (1M context) minimum** — `/codemap create`. Full-repo traversal needs the large context window so sections aren't truncated mid-generation.
- **Sonnet 4.6** — `/codemap update/section`, `/wrapup`, `/intake`, `/ask` (scoped lookups), `/distill`, `/stitch`, and all lightweight skills (`/index`, `/stats`, `/backlog`, `/rules`, `/context`, `/clip`, `/snapshot`, `/help`, `/setup`). Structured or retrieval-only work — higher models add no measurable lift.

Haiku is not recommended for any ARIA skill. See `/help` for the full table.

### Opus 4.7: batch manifests for multi-file work

Under Opus 4.7's tokenizer (1.0–1.35× inflation vs 4.6) and adaptive thinking token budgets, multi-file refactors benefit from declaring a **batch manifest** via `/distill` with the group loader. A batch manifest compresses each in-scope file's Rule 22 assessment to the `[Rule 22 · Batch N/M]` marker, preserving enforcement while significantly reducing per-edit token cost. Structural signals (auth, migration, model, routing, external-service paths) still override the batch low-impact declaration automatically. For 3+ file refactors, declare a batch manifest before starting edits.

See `knowledge/projects/aria/references/opus-4-7-aria-compatibility.md` for the full list of verified 4.7 behaviors ARIA is designed around.

## Known Issues

- **"hook error" label on Pre/PostToolUse hooks** — Claude Code displays "hook error" next to every tool call that triggers a hook, even when the hook exits successfully (exit code 0) with valid JSON output. This is a [known Claude Code UI bug](https://github.com/anthropics/claude-code/issues/17088) — the Rule 22 enforcement hooks are working correctly. The label is cosmetic and does not indicate a problem with ARIA.

## ARIA family

ARIA is a family of projects under the name **Applied Reasoning and Insight Architecture**. Each sibling targets a different surface; they're independent but share a knowledge-folder convention where it makes sense.

| Project | Scope | Audience | Repo |
|---------|-------|----------|------|
| **aria-knowledge** | Active knowledge + decision discipline for Claude Code | Individuals and teams using Claude Code | This repo |
| **aria-cowork** | Sibling plugin for Claude Cowork — the portable subset of aria-knowledge's discipline | Cowork users | Public release planned |

### License posture

Licenses differ across the family. **aria-knowledge** ships under [CC BY-NC-SA 4.0](LICENSE) — free for non-commercial use, copyleft on derivatives. Other family projects may carry different licenses; check each project's LICENSE before assuming inheritance.

## License

[CC BY-NC-SA 4.0](LICENSE) — Free to use and modify. Must be attributed, non-commercial, and derivatives must share alike.

## Support

If ARIA is useful to you, consider buying me Claude credits via [PayPal](https://www.paypal.biz/prasadmike) or [Venmo](https://venmo.com/mikeprasad).

## Try it

Install ARIA, run `/setup`, work normally. Rule 22 is active immediately. Run `/extract` before ending sessions. Run `/audit-knowledge` when prompted. Each session builds on the last.

**Memory is not enough. Trusted application is the goal.**
