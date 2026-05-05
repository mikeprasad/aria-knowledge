<!-- plugin-managed: /setup diffs this file on plugin updates. Customize it freely — your edits appear as diff prompts on future `/setup` runs (this is how you receive plugin improvements). For customizations you want ARIA to leave alone, use `rules/user-rules.md` or `LOCAL.md` (both user-owned, never diffed). See the "Plugin-Managed vs User-Owned Files" section below for details. -->

# ARIA Knowledge

**Applied Reasoning and Insight Architecture**

An active knowledge and development discipline system for AI-assisted development. Built for developers and teams using Claude Code who want each session to build on the last — capturing knowledge, enforcing structured decisions, and mapping codebases and tasks so context compounds instead of disappearing.

## The Problem

Every time an AI session ends, context disappears. Your insights, decisions, and corrections vanish into compacted conversation history. The next session starts from scratch — or worse, repeats the same mistakes you already corrected.

Over time, valuable knowledge accumulates in scattered places: CLAUDE.md files, auto-memory, session plans, Slack threads, mental notes. Some of it contradicts other parts of it. None of it gets reviewed. The knowledge that matters most — the hard-won lessons from debugging, the architectural decisions made under pressure, the feedback you gave three sessions ago — has no durable home.

This isn't a tooling problem. It's a knowledge lifecycle problem. You need a system that captures knowledge when it's fresh, stages it for governance review, promotes the good stuff into durable findable documents, applies trusted knowledge back into future work, and refreshes the base before staleness rots its value — while letting the rest fade naturally.

## The Approach

Knowledge Repository treats knowledge like code: it moves through a pipeline with clear stages, review gates, promotion criteria, application paths, and freshness checks. Five phases: **Capture → Govern → Promote → Apply → Refresh.** The "Applied" in ARIA's acronym lives in phase four — trusted knowledge actively shapes the next decision rather than just sitting in storage.

### Capture

During work sessions, knowledge is captured automatically and on-demand:

- **Insight blocks** surface non-obvious technical observations as they happen
- **Extraction** (`/extract`) scans conversations before context compaction destroys them, dumping findings into staging backlogs
- **Session cleanup** prompts you to capture decisions and insights before ending a session

Nothing captured at this stage is canonical. It's raw signal waiting for review.

### Govern

On a configurable cadence, the knowledge audit (`/audit-knowledge`) scans your backlogs, memory files, and plans. It categorizes everything it finds:

- **Already captured** — knowledge that's already in your docs or CLAUDE.md files
- **Implementation-specific** — session plans, debug steps, one-time fixes (valuable in the moment, not reusable)
- **Worth extracting** — validated approaches, cross-project decisions, patterns that will save time next month

The audit also detects **emerging themes** — clusters of related insights that individually don't justify a knowledge file but together reveal a pattern worth documenting. This is how the knowledge base grows organically rather than through forced curation.

Nothing gets promoted without your explicit approval. Govern is the trust gate: confident-wrong knowledge cannot quietly become permanent.

### Promote

Approved knowledge moves to its permanent home based on what type it is. Each type has a specific purpose, format, and location:

| Type | Purpose | Example |
|------|---------|---------|
| **Rules** | Principles and constraints that govern how you work | "Decisions must be logically justified" |
| **Approaches** | Validated methodologies confirmed through real use | "How we structure Linear tickets" |
| **Decisions** | Architectural choices with context, alternatives, and consequences | "We chose cursor pagination over offset" |
| **Guides** | Operational knowledge about how things work in your environment | "How to set up Claude Code for the team" |
| **References** | External research, evaluations, and bookmarked resources | "Stripe vs Paddle comparison" |

This taxonomy is complete — every type of reusable knowledge fits into exactly one category. If it doesn't fit any of them, it's either ephemeral (belongs in session notes) or not yet validated (stays in the backlog until it is).

### Apply

A knowledge base only matters if it shapes future work. Apply is where ARIA's "Applied" framing earns its name — promoted knowledge actively guides reasoning, planning, and code changes rather than just being stored.

- **Rule 22 — change decision framework** enforced at every Edit/Write via PreToolUse + PostToolUse hooks. Pre-edit: assess impact (HIGH/LOW), state alternatives, define scope. Post-edit: verify scope wasn't exceeded, check secondary impact on parents/siblings/dependents.
- **`/context`** loads relevant knowledge by topic using the tag index, with project expansion (`/context {project-tag}` adds project-tier files).
- **`/rules`** surfaces working rules by number or keyword during reasoning.
- **`/codemap`** turns a repository into a feature-organized reference; `/stitch` builds cross-repo binding tables for product groups; `/distill` turns raw ticket text into tiered executable task specs that cite real files via optional CODEMAP/STITCH context.
- **TaskCreated hook** surfaces relevant knowledge files when tasks are created (tag index matching).
- **PreCompact / PostCompact hooks** preserve transcripts before context compaction and prompt to review snapshots after.

This phase is what separates ARIA from passive memory systems. Storage answers "what did we learn?" Apply answers "which trusted knowledge applies to this task, this edit, this decision — right now."

### Refresh

Knowledge bases rot when nothing forces a review. Refresh keeps the base from quietly going stale.

- **`Last updated` frontmatter on every knowledge file** enables mechanical staleness checks.
- **Configurable thresholds** — `ideas_staleness_threshold_days` (default 7) for `intake/ideas/` entries; `staleness_threshold_months` for promoted knowledge files.
- **Audit cadences** — SessionStart hook prompts when `/audit-knowledge` or `/audit-config` is overdue.
- **Stale-first surfacing** during audits — stale items sort above fresh ones and demand explicit disposition; fresh items pass through informationally.
- **Drift detection** — `/audit-config` scans CLAUDE.md files and configs for broken references; `/audit-knowledge` Step 5b3 checks skill-knowledge connections; `/codemap update` refreshes incrementally via git diff; `/index` flags untagged or stale files and suggests cross-references.
- **Rule 22 enforcement** — every Edit/Write requires a visible impact assessment and post-edit scope check. No silent drift because no silent edits.
- **`/stats`** dashboard surfaces backlog depth, audit status, codemap dates, tag coverage, and gaps at a glance.

Format determines auditability; process determines freshness. Plain markdown for auditability + layered review cadences for freshness + humans in the promotion loop so wrong knowledge doesn't accumulate silently.

### Ideas Backlog (capture vs. track boundary)

ARIA captures observations about **what IS** (knowledge) and stages proposals about **what SHOULD BE different** (ideas). The five knowledge types above are observations; ideas are a separate bucket with a distinct disposition.

Feature proposals, bug reports, and design ideas all flow into `intake/ideas/` during `/extract` — one markdown file per idea, since v2.11 (prior versions used a single `intake/ideas-backlog.md`; see `intake/ideas/README.md` for the migration path if you're upgrading). The audit surfaces them in their own section: ideas never promote directly into knowledge files. Since v2.12 each accepted idea routes via an Accept submenu — `tracker | roadmap | todo | adr | backlog | bundle | rule` — picking only the destinations available for that project (e.g., `roadmap` only when `ROADMAP.md` exists at the project root or under `docs/`). The `adr` and `rule` paths stage entries in their respective backlogs (`decisions-backlog.md`, `rules-backlog.md`) for normal audit-cycle review rather than promoting straight to `decisions/` or `rules/`. Rejected ideas are discarded; deferred ideas stay in `intake/ideas/` for the next audit.

**ARIA captures; you choose where each proposal lives.** This boundary keeps ARIA tool-agnostic — no single destination is mandatory — and prevents a common drift mode where proposals get misfiled as documentation of features that don't exist yet. Set `ticketing_plugins` in your local config to have the audit hint at a ticket-drafting plugin when an idea takes the tracker route.

### Project-Specific Tier (opt-in, since v2.8.0)

The five-type taxonomy above is for **cross-project** knowledge — patterns and decisions validated across multiple projects, applicable beyond a single codebase. But not all valuable knowledge clears that bar.

Some architecture decisions are important for a specific project but have no evidence of broader applicability. The choice was right for this codebase but might not generalize. Forcing it into the cross-project tree creates noise; leaving it uncaptured loses durable context.

The optional `projects/` tier solves this. When enabled via `/setup`, ARIA scaffolds:

```
projects/
├── README.md              (plugin-managed)
├── {project-tag}/
│   ├── README.md          (per-project, user-owned)
│   ├── decisions/         (project ADRs)
│   ├── patterns/          (reusable within this project)
│   ├── guides/            (optional)
│   └── references/        (optional)
└── {another-project}/
```

Files under `projects/{tag}/**` are automatically tagged with the project tag (path-derived), surfaced via `/context {tag}` alongside cross-project files, and considered for cross-project promotion when patterns appear in ≥`projects_promotion_threshold` projects (default 2).

The promotion ladder extends to three tiers: **project pattern → cross-project approach → universal rule**. `/audit-knowledge` Step 5e detects when project-specific patterns deserve promotion to the cross-project tree, synthesizes the merged content with provenance preservation (`originally_at:` frontmatter), and offers stub-and-reference disposition for the source files.

This tier is fully opt-in — `projects_enabled: false` by default. Existing users see no behavior change unless they explicitly enable it. New users can opt in during `/setup` Advanced Options.

### Shared Knowledge Tier (opt-in, since v2.13.0)

Personal knowledge captures stay on one developer's laptop. The Shared Knowledge tier closes that loop: selected personal knowledge can be **promoted to a per-repo team-visible folder** so teammates working in the same code repo can find and read what you've learned.

When `projects_shared_knowledge` is set to a comma-separated tag list in config (alongside `projects_enabled: true`), each enabled project repo gains a conventional folder:

```
<project-root>/
└── _project-knowledge/
    ├── README.md                                    (auto-created on first share — convention explainer for non-ARIA teammates)
    ├── IDEAS-BACKLOG.md                             (the project's idea queue moves here; routed via /audit-knowledge → Accept→backlog)
    ├── {YYYY-MM-DD}-{author}-{slug}.md              (repo-scoped insights, decisions, approaches, rules)
    └── cross/
        ├── IDEAS-BACKLOG.md                         (cross-repo idea queue)
        └── {YYYY-MM-DD}-{author}-{slug}.md          (cross-cutting items)
```

The new `/audit-share` skill (alias `/share-audit`) is the batch-review surface for promotion. Walk personal knowledge folders, review recommendations grouped by destination, approve all/numbers/modify/skip per item. Personal copies stay in your knowledge folder; team copies are independent records committed through normal git/PR review. Files in both places carry frontmatter back-pointers (`shared:` on personal copies, `origin:`/`shared_by:`/`shared_at:` on team copies) for provenance.

Read-side: `/index` (Phase 5) scans `_project-knowledge/` folders into the tag index; `/context` surfaces team-shared files as a third grouping in query results (above project-specific and cross-project). Tag-based discovery works seamlessly across all three tiers.

Cross-cutting knowledge that applies across multiple repos in the same product group lands in any one repo's `_project-knowledge/cross/` (federated; aggregation handled at read time via the index).

This tier is fully opt-in and **per-project** — `projects_shared_knowledge` defaults to empty (feature disabled, no projects enabled). It requires `projects_enabled: true` to take effect. Users explicitly pick which projects to enable during `/setup` (the field is a comma-separated tag list, e.g., `cs,ss`); projects not in the list stay personal-tier only. Existing users see no behavior change unless they explicitly enable specific projects.

## The Plugin

Knowledge Repository is powered by **aria-knowledge**, a Claude Code plugin that automates the capture–govern–promote–apply–refresh lifecycle.

### Skills

| Skill | What it does |
|-------|-------------|
| `/setup` | Configure knowledge folder, validate structure, set audit cadences |
| `/extract` | Scan conversation for uncaptured knowledge and stage to backlogs |
| `/wrapup` | End-of-session handoff — runs `/extract`, updates PROGRESS.md/CLAUDE.md, prompts for commit |
| `/audit-knowledge` | Review backlogs and memory for promotable knowledge, detect themes, check integrity |
| `/audit-config` | Check CLAUDE.md files, configs, and docs for drift, broken references, staleness |
| `/context [tags]` | Load relevant knowledge by topic with project tag expansion |
| `/index` | Rebuild tag index with cross-references, entity detection, and skill-knowledge connections |
| `/codemap [mode]` | Generate feature-organized codebase maps (create/inventory/update/section) |
| `/stitch <mode> <group>` | Cross-repo binding artifact (auth/endpoints/entities/drift) for a product group |
| `/distill [text or path]` | Turn raw task text into a tiered executable spec (micro/standard/full); optional --group loads CODEMAP + STITCH context |
| `/ask [question]` | Research a question, check existing knowledge, save answer directly |
| `/intake [path/url]` | Bulk import knowledge from files, directories, or URLs |
| `/clip [url/text]` | Quick-save a URL or snippet to intake |
| `/rules [number]` | Quick lookup into working rules by number or keyword |
| `/backlog [type]` | View and manage pending intake items |
| `/stats` | Knowledge base health dashboard |
| `/help` | Command reference |

### Hooks

The plugin includes hooks that fire automatically during sessions:

- **Session start** — checks audit cadences and prompts when reviews are overdue; injects per-task insight capture instruction; first-run welcome for new users
- **Pre-edit (Edit/Write)** — enforces structured decision-making before every code change (impact assessment, alternatives considered, scope defined). Detects planning paths for abbreviated assessment. Protects critical files.
- **Post-edit (Edit/Write)** — verifies changes stayed within decided scope, checks for secondary impact on parents/siblings/dependents
- **Pre-compact** — saves transcript snapshot before context compaction to prevent knowledge loss
- **Post-compact** — prompts to review captured snapshots after compaction
- **Task created** — matches task keywords against the tag index and surfaces relevant knowledge files

The pre/post edit hooks implement a change decision framework that prevents common failure modes: rewriting code that should have been extended, touching files outside the decision scope, skipping alternatives analysis. The enforcement is prompt-based — it shapes reasoning at the moment of action rather than blocking execution.

> **Note:** Claude Code displays a "hook error" label next to tool calls that trigger these hooks. This is a [known Claude Code UI bug](https://github.com/anthropics/claude-code/issues/17088) — the hooks exit successfully and work correctly. The label is cosmetic.

### Enforcement Philosophy

The plugin uses a layered enforcement model, from softest to hardest:

1. **CLAUDE.md rules** — loaded at session start, set expectations
2. **Hook prompts** — injected at tool boundaries, enforce process at the point of action
3. **Required output format** — forces every reasoning step to be visible and auditable
4. **Permission deny lists** — hard blocks for operations that should never happen

Most enforcement lives at layers 2-3. The goal isn't to prevent mistakes through restriction — it's to make the decision process visible so mistakes are caught before they're committed.

## Plugin-Managed vs User-Owned Files

ARIA template files fall into two classes with different update behavior on `/setup`. Understanding the split prevents surprise when the plugin ships updates and your customized files appear in diff prompts.

**Plugin-managed files** are authored by the plugin and kept current via `/setup` diffs. When a plugin update ships a new version of a managed file, `/setup` shows you the diff and lets you keep your version, adopt the plugin version, or review the full change. If you customize a managed file (e.g., add a custom rule directly into `working-rules.md`), your edits appear as diff prompts on every future `/setup` until reconciled. This is intentional — it's how you receive plugin improvements without silent overwrites. Managed files include `README.md`, `OVERVIEW.md` (this file), `rules/working-rules.md`, `rules/change-decision-framework.md`, `rules/enforcement-mechanisms.md`, `rules/retrospect-patterns.md`, and `projects/README.md` (when the project tier is enabled).

**User-owned files** are yours entirely. `/setup` creates them once from a template on first install, then never touches them again — no diffs, no overwrites, no merges. Use these for customizations you want the plugin to stay out of. Key user-owned files include `LOCAL.md` (your local guide), `rules/user-rules.md` (your custom rules), the intake backlogs (`intake/insights-backlog.md`, `decisions-backlog.md`, `extraction-backlog.md`, `rules-backlog.md`) and the `intake/ideas/` directory (per-file ideas since v2.11, plus the directory's `README.md`), audit logs under `logs/`, directory README stubs (`guides/README.md`, `approaches/README.md`, `decisions/README.md`, `references/README.md`, `archive/README.md`), and per-project READMEs under `projects/{tag}/`.

The authoritative classification lives in `plugin/skills/setup/SKILL.md` (Step 3 lists user-owned files; Step 4 lists managed files). Managed files also carry an HTML comment header at the top of the raw markdown signaling their class at the point of customization, and on first-setup the `/setup` skill surfaces a one-time educational note about the split.

**Rule of thumb:** if your customization is content-specific to your project or team (custom rules, per-project READMEs, local conventions, session captures), put it in a user-owned file. If you want to modify plugin-shipped core guidance (working rules, change-decision framework, enforcement mechanisms, top-level README/OVERVIEW), expect diff prompts on updates and reconcile during `/setup`.

## Batch Manifests for Ceremony Reduction

Rule 22 (change decision framework) fires full CHANGE DECISION CHECK on every Edit/Write by default — this is load-bearing for safety (ADR 006: full format every edit, post-compaction safe) but non-linear in ceremony cost for bulk operations. A single audit that promotes 30 files produces ~30 near-identical "Low Impact — new doc, no dependents" assessments; the one edit that mattered (an integrity fix) is visually indistinguishable from the noise.

v2.10.0 adds **batch manifests** as a narrow, file-based exception that compresses ceremony for declared-mechanical operations while preserving full scrutiny for genuinely high-impact work.

### Mechanism

A batch manifest is a JSON file at `~/.claude/active-batch.json` declaring expected operations for a bulk task. The `pre-edit-check.sh` hook reads it and emits a compressed directive for declared-low-impact matches; everything else falls through to the full CHANGE DECISION CHECK.

```json
{
  "batch_id": "batch-20260417-120000-12345",
  "skill_name": "audit-knowledge",
  "plan_summary": "Eleventh-pass audit promotion: 4 approaches + 2 decisions + backlog clears",
  "started_at": "2026-04-17T12:00:00Z",
  "expected_operations": [
    {"file_path_pattern": "/abs/knowledge/approaches/*.md", "operation_type": "create", "impact": "low", "justification": "New approach files per approved Step 7 plan"},
    {"file_path_pattern": "/abs/knowledge/decisions/*.md", "operation_type": "create", "impact": "high", "justification": "New ADRs — architectural commitments require full scrutiny"},
    {"file_path_pattern": "/abs/knowledge/intake/*-backlog.md", "operation_type": "update", "impact": "low", "justification": "Clear promoted entries"}
  ]
}
```

### Safety floor (multi-layer defense)

The manifest compresses ceremony **only** when every safety layer clears:

1. **Protected paths always win** — `CLAUDE.md`, `working-rules.md`, `change-decision-framework.md`, `enforcement-mechanisms.md`, `settings.local.json`, `plugin.json`, the knowledge folder itself, and user-configured critical paths always get full Rule 22 regardless of manifest declaration.
2. **Structural signals override declared-low** — if the file has auth, migration, model, routing, or external-service signals detected by `kt_detect_signals`, the hook escalates a declared-low op to full Rule 22 with a `BATCH SIGNAL OVERRIDE` prefix. Signals are ground truth from the filesystem; they can't be self-declared away.
3. **Declared-high ops always get full Rule 22** — `impact: high` in the manifest fires the full format with a `BATCH DECLARED-HIGH` prefix, preserving scrutiny for architecturally-load-bearing edits within a batch.
4. **Scope-drift detection** — any edit to a file not matched by any manifest op gets full Rule 22. The manifest is both a compression signal and a declared-scope boundary; wandering outside that boundary fires the full format automatically.
5. **Post-edit scope check unchanged** — every edit still runs `post-edit-check.sh` for "did you stay in scope? any secondary impact?" — aggregate-drift detection (many individually-small edits that collectively constitute an architectural change) surfaces here.
6. **Justification validation** — manifest entries with empty `justification` fall back to full Rule 22 (enforces articulated intent, not just silent compression).
7. **Stale-manifest auto-clear** — `session-start-check.sh` removes manifests older than 30 minutes, recovering from crashed sessions that didn't reach their `kt_batch_end`.

**Residual risk** — a HIGH-impact edit with no structural signal, mis-declared as LOW, inside a declared-scope pattern. Layers 1-4 don't catch this because signal detection doesn't cover all HIGH cases (e.g., a business-logic change to non-auth non-routing code). Only layer 5 (post-edit scope check) provides backstop. **Guidance: when in doubt about impact classification, declare HIGH — full Rule 22 is always the safe choice for an individual op inside a batch.**

### Who writes the manifest

Two consumers:

**(a) Skills with structured bulk flows.** `/audit-knowledge` writes a manifest after user approval of its promotion plan (Step 7a) and clears it after the audit log is written (Step 8b). The skill's instructions tell Claude how to classify each approved op. This is the primary v2.10.0 consumer. Future releases may extend `/wrapup` and `/extract` as `intake/ideas/` entries indicate demand.

**(b) Claude executing a user plan.** When Claude is about to perform a declared multi-file task (e.g., user shares `docs/plans/feature-x.md` listing 10 files to create + modify), Claude can write the manifest itself before starting:

```bash
. ${CLAUDE_PLUGIN_ROOT}/bin/config.sh
kt_batch_begin "manual-plan-execution" "Implement feature X per docs/plans/feature-x.md" '[
  {"file_path_pattern": "src/feature-x/**/*.ts", "operation_type": "create", "impact": "low", "justification": "New module files per plan Section 2 — mechanical scaffolding"},
  {"file_path_pattern": "src/routing/routes.ts", "operation_type": "update", "impact": "high", "justification": "Add new route handler — routing signal, full assessment required"},
  {"file_path_pattern": "tests/feature-x/**/*.ts", "operation_type": "create", "impact": "low", "justification": "Test files per plan Section 4"}
]'
```

After the plan executes, clear the manifest:

```bash
kt_batch_end
```

The hook doesn't care who wrote the manifest — mechanisms are identical. Use (b) whenever a declared multi-file task would otherwise produce many similar Rule 22 assessments that a reader would recognize as ceremony rather than substance.

### Three-tier ceremony calibration

With v2.10.0 the framework has three ceremony tiers, each triggered by a file-based signal:

| Tier | Trigger | Output |
|------|---------|--------|
| **Planning** | Edit to `*/docs/plans/*` or `*/docs/specs/*` | Abbreviated ("Planning edit — [filename]") |
| **Batch declared-low** | Edit matches manifest op + impact:low + no signals + not protected | Compressed directive (acknowledge-only) |
| **Default** | Everything else (no batch; batch-declared-high; signal override; scope drift; protected) | Full CHANGE DECISION CHECK |

All three tiers use file-based signals (path patterns, manifest matching) — no session-history-based self-judgment. Post-compaction safe because the hook re-derives the tier from filesystem state on every fire.

### Dependencies

The batch mechanism requires `jq` on the system PATH for JSON parsing. Without jq, the hook gracefully degrades to full Rule 22 format — batch compression is never a correctness requirement. Install with `brew install jq` (macOS) or your package manager.

## Design Principles

### Opinionated defaults, easy customization

The plugin ships with a complete set of working rules, a change decision framework, and enforcement mechanisms. These are real rules refined through real projects — not generic placeholders. You can use them as-is, modify them, or replace them entirely. The `/setup` wizard diffs your files against new plugin versions so you can selectively adopt updates.

### Human review gates

Nothing is auto-promoted. Extraction dumps to backlogs; audits present findings; you decide what to keep. This prevents knowledge base bloat and ensures everything that gets promoted has been validated by a human.

### Signal accumulation over forced curation

Individual insights rarely justify a standalone document. But patterns of insights do. The audit process watches for thematic clusters across backlog entries and proposes synthesis documents when evidence reaches a threshold. Knowledge files emerge from accumulated evidence, not from premature formalization.

### Stable identifiers

Rules use permanent numeric IDs — they're never renumbered. When a rule is retired, it keeps its number and gets marked `[RETIRED]`. This prevents reference drift across the many files that cite rule numbers.

### Archive, don't delete

When knowledge is superseded, the old version moves to `archive/` with a pointer from the original location. Nothing is lost, and the decision trail remains auditable.

## Why Human-Anchored Knowledge

LLMs have an extraordinary ability to intake, synthesize, and organize information at scale. This is genuinely powerful — and it's the basis for approaches like Andrej Karpathy's "LLM Knowledge Base" pattern, where the LLM acts as a librarian that compiles raw sources into a structured wiki, maintains it through linting passes, and surfaces connections across hundreds of documents. In that model, "you rarely ever write or edit the wiki manually; it's the domain of the LLM."

That approach works well for **research and exploration** — domains where breadth matters, where false connections are cheap to discard, and where the goal is surfacing patterns across large bodies of information. The LLM's ability to read everything and find non-obvious links is genuinely its superpower.

But operational knowledge is different.

When you're building software with a team, the knowledge that governs your work — your rules, your architectural decisions, your validated approaches — has consequences. A wrong rule gets enforced on every edit. A bad architectural decision shapes months of implementation. An inaccurate guide sends a new team member down the wrong path. The cost of a false positive in your operational knowledge base isn't "oh, that connection wasn't useful" — it's real work built on a wrong foundation.

This is the core problem with LLM-compiled knowledge for operational use: **LLMs are confident synthesizers, not reliable validators.** They will find patterns, write articulate summaries, and create convincing connections — even when the underlying observation was a one-time anomaly, a misunderstood edge case, or an outdated practice. At research scale, this is noise that washes out. At operational scale, it becomes load-bearing misinformation.

Knowledge Repository takes a different position: **the LLM captures, the human promotes.**

The intake pipeline is deliberately broad — insights, decisions, feedback, project context, and references all flow into backlogs during work sessions. The LLM is excellent at this: noticing what was discussed, structuring it consistently, deduplicating against what's already captured. This is high-volume, low-stakes work where LLM judgment is reliable.

But the promotion boundary — where something moves from "captured observation" to "canonical knowledge that shapes future work" — requires human judgment. Not because the LLM can't write a convincing rule, but because it can't reliably distinguish between:

- A pattern that worked once vs. a pattern that should be applied everywhere
- A decision that was contextually correct vs. a decision that should set precedent
- An observation that was insightful vs. an observation that was coincidental

This makes the system slower than a fully LLM-maintained wiki. Backlogs accumulate. Reviews happen on a cadence, not in real-time. Knowledge files emerge over days and weeks, not minutes.

But what gets promoted is **anchored** — validated by someone who understands the operational context, who knows which observations are load-bearing and which are noise, who can judge whether a pattern from Project A actually applies to Project B.

But human review alone isn't enough either. Humans bring their own biases — intuition that feels right but isn't validated, preferences mistaken for principles, decisions driven by familiarity rather than merit. The system accounts for this too: **both the LLM and the human can be wrong.**

This is why the change decision framework exists. Before any change, the LLM must identify alternatives, present them with objective criteria, and rank options with explicit reasoning — not just execute the first idea. The human reviews the analysis, not a recommendation served on a platter. Decisions must be logically or empirically justified, not just intuitively appealing. The framework enforces this at the tool boundary: every edit requires a visible impact assessment, and every assessment requires options considered.

The result is a system where the LLM's breadth of intake is filtered through structured analysis, and the human's contextual judgment is anchored by objective criteria. Neither party gets to shortcut the process.

Both systems contain knowledge. The difference is what the knowledge is organized for.

Karpathy's system is a **library** — an AI librarian that organizes, indexes, cross-references, and surfaces connections across a growing collection of documents. Its knowledge is organized for **exploration**: making information findable, revealing non-obvious relationships, scaling to large bodies of research. You go to it when you need to understand a topic. The more it knows, the better it works.

Knowledge Repository is closer to a **trained mind**. It also holds knowledge — rules, approaches, decisions, guides — but that knowledge is organized for **execution**. The rules encode how you think about changes. The decision framework structures how you evaluate options. The enforcement hooks embed that discipline into the moment of action, not just the moment of reflection. The more validated it is, the better it works.

In technical terms: Karpathy's system builds a **knowledge graph** — a rich model of a domain optimized for retrieval and connection. Knowledge Repository builds an **inference engine** — a system of validated rules and decision patterns optimized for making correct choices under real constraints. Both contain knowledge, but one measures success by "did I find the right information?" and the other by "did I make the right decision?"

Consider two surgeons. One has read every paper on a procedure — she can cite studies, compare techniques, explain the history of each approach. Her knowledge is organized for understanding. The other has performed the procedure a hundred times and learned from each outcome — she knows that when she sees a particular complication, she does this specific thing, because the last three times she tried the alternative, it failed. Her knowledge is organized for action. Both surgeons are knowledgeable. But you want the second one in the operating room.

The tradeoff is explicit: **breadth and speed for accuracy and trust.** In a research context, you'd choose the library. In an operational context — where your knowledge base actively shapes how code gets written, decisions get made, and teams get onboarded — you'd choose the trained mind.

Crucially, the trained mind **develops with the user.** Rules emerge from real mistakes — when something fails, the system captures why and encodes the lesson so it doesn't repeat. Feedback corrections compound across sessions. The decision framework gets sharper through use as edge cases get documented and patterns get validated. Over time, the system becomes more reliable and more contextually accurate, not just larger. It's an expert system that grows expertise, not just volume.

And the two approaches aren't competing — they're complementary. You can use Karpathy's pattern, Obsidian Web Clipper, or any research tool to build broad topical knowledge, then feed the valuable parts into `intake/clippings/` or `references/` for this system to review, validate, and promote. The library feeds the mind. Research exploration generates raw signal; the knowledge repository filters it into operational knowledge you can build on.

Neither system is universally better. They solve different problems. The question is whether you need to explore a topic, or execute on one.

## Getting Started

1. Install the aria-knowledge plugin in Claude Code
2. Run `/setup` to configure your knowledge folder and preferences
3. Start working — the plugin captures knowledge automatically via hooks
4. Run `/extract` when you finish a task or before switching context
5. Run `/audit-knowledge` when prompted (or any time) to review and promote

The knowledge folder is plain markdown — it works great as an [Obsidian](https://obsidian.md) vault. We recommend using [Obsidian Web Clipper](https://obsidian.md/clipper) to save articles and references directly into `intake/clippings/`, where ARIA's audit process can review and promote them.

See [README.md](README.md) for the folder structure, conventions, and operational details. See [LOCAL.md](LOCAL.md) for format templates and detailed usage guidance.

## Getting the Most from ARIA

ARIA's value compounds over time, but only if knowledge moves through the full pipeline. Two habits make the biggest difference:

### Run `/extract` before ending sessions

`/extract` scans your conversation for insights, decisions, feedback, and references — and stages them in backlogs for later review. **Insight blocks are now auto-captured at task completion boundaries** via a best-effort session-start instruction (Claude may occasionally miss a boundary under context pressure), but decisions, feedback, project context, and references still require `/extract` to capture.

`/wrapup` includes `/extract` as part of its flow. The important thing is that knowledge gets staged while the full conversation is still in context.

### Respond to audit prompts

When ARIA prompts "Knowledge audit due" at session start, that means backlogs have accumulated items waiting for your review. Until you run the audit and promote (or clear) those items:

- **`/context` can't surface them** — only promoted knowledge files are indexed and retrievable by topic. Backlog items are invisible to `/context`.
- **Emerging themes go undetected** — the audit's cluster detection only runs during review. Patterns across multiple sessions won't be identified until you audit.
- **Backlogs grow stale** — insights captured weeks ago lose context. Reviewing them while they're still fresh produces better promotion decisions.

You don't need to audit every session — the configurable cadence (default: every 3 days) balances review frequency against interruption. But when the prompt appears, it means there's pending knowledge worth a few minutes of review.

### Everything else is automatic

The hooks handle the rest without user action: Rule 22 enforcement on every edit, transcript capture before compaction, context surfacing when tasks are created, codemap reminders before codebase exploration, and `/context` suggestions at session start. These features work passively as long as the plugin is installed and configured.
