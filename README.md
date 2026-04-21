<p align="left">
  <img src="aria-icon-rounded.png" width="120" alt="ARIA">
</p>

# ARIA — Anchored Reasoning and Insight Architecture

ARIA is a Claude Code plugin that gives AI coding sessions persistent memory and structured discipline. It manages a complete knowledge lifecycle — capturing insights, decisions, and feedback during sessions, staging them in backlogs for human review, and promoting what matters into a searchable, tag-indexed knowledge base. Session hooks prevent knowledge loss during context compaction, surface relevant knowledge when tasks are created, and enforce a change decision framework at every file edit, requiring visible impact assessment and scope verification before and after changes. The result is that each session builds on the last instead of starting from scratch.

Beyond knowledge capture, ARIA provides active tooling for codebase & task mapping and session workflow. `/codemap` generates feature-organized maps that trace full-stack flows across entire repositories; `/stitch` builds cross-repo binding tables (auth paths, endpoint stitch, drift logs) for product groups spanning a backend and one or more frontends; `/distill` turns raw ticket text into tiered executable task specs that cite real files via optional CODEMAP + STITCH context. `/ask` researches questions and saves answers directly as knowledge docs. `/intake` bulk-imports from files, URLs, or directories. `/audit-config` and `/audit-knowledge` detect drift, staleness, and gaps on configurable cadences. `/wrapup` handles end-of-session handoff — updating progress files, prompting for commits, and ensuring the next session can pick up cleanly. An optional project-specific knowledge tier (v2.8.0+) organizes architecture decisions and patterns by project, with automatic cross-project promotion detection when patterns validate across multiple projects. Everything is plain markdown, works as an Obsidian vault, and follows a core philosophy: the AI captures, the human promotes.

## How It Works

### Knowledge Lifecycle

Knowledge moves through a pipeline: **Capture → Review → Promote.**

- `/extract` — Scan conversations for uncaptured insights, decisions, feedback, and references. Deduplicates against existing entries.
- `/clip` — Quick-save URLs or text snippets to intake without leaving the session.
- `/ask` — Research a question, check existing knowledge first, save the answer directly as a knowledge doc.
- `/intake` — Bulk import from files, directories, or URLs with preview before staging.
- `/backlog` — View and manage pending items across all three backlogs.
- `/audit-knowledge` — Review backlogs and memory for promotable knowledge. Detects emerging themes across entries. Checks codemap staleness.
- `/index` — Rebuild the tag index. Normalizes tags, flags untagged files, suggests cross-references, updates project mappings.
- `/context` — Load relevant knowledge by topic using the tag index with project expansion. When a project tier is configured, `/context {project-tag}` also loads project-specific files from `projects/{tag}/**`, grouped separately from cross-project results.
- `/rules` — Quick lookup into the 31 working rules by number or keyword.
- `/stats` — Knowledge base health dashboard — file counts, backlog depth, audit status, tag coverage, gaps.

### Decision Discipline

A change decision framework (Rule 22) is enforced at every Edit/Write via hooks.

- **PreToolUse hook** — Before every file edit: assess impact (HIGH/LOW), state alternatives considered, define scope.
- **PostToolUse hook** — After every edit: verify scope wasn't exceeded, check for secondary impact on parents/siblings/dependents.
- **Structural signal surfacing** — edits touching auth, migrations, models/schemas, routing, or external-service integrations get advisory labels on the hook output so risk signals are visible even when the content classifies as Low impact.
- **Batch-manifest ceremony reduction** — skills (or manual plan execution) driving declared-scope multi-file work can write a batch manifest that compresses Rule 22 ceremony for low-impact ops in-scope. Protected paths, declared-high ops, structural signals, and out-of-scope drift all still get the full assessment. Requires `jq`. `/audit-knowledge` uses this to run 15–30-edit promotion passes without per-edit ceremony.
- Configurable critical paths that always require full impact assessment.
- Ships 31 working rules, a 7-step change decision framework with real examples, and enforcement mechanisms documentation.

### Codebase & Task Mapping

Skills that turn ambiguous surface area — a repo, a set of repos, a raw ticket — into structured artifacts Claude can ground decisions against. All three produce a navigable map of something that was previously tribal knowledge.

- `/codemap` — Feature-organized reference document for any repository. Scans repos, detects frameworks, traces full-stack flows (routes → hooks → state → views → models → integrations). Four modes: `create` (full generation), `inventory` (quick index), `update` (incremental via git diff), `section` (rebuild one section). Produces navigable CODEMAP.md with a directory table for selective section loading. Stack-aware cross-cutting candidates (URLConf tree, signal registry, env matrix, route tree) surface as explicit gap prompts during generation — feature-organized codemaps systematically under-document these because they span all features rather than attaching to one.
- `/stitch` — Cross-repo binding artifact for product groups (backend + one or more frontends). Produces STITCH.md with tables for group identity, auth path, endpoint stitch, entity stitch, integration stitch, and a drift log. Modes: `create`, `verify`, `diff`, `section`. Drift detection follows a precedence ladder: user-supplied analyze-stitch script → CODEMAP-based endpoint diff → explicit prompt when CODEMAPs lack endpoint sections → opt-in grep fallback. Output labels its drift source so you can trust or distrust accordingly.
- `/distill` — Turns raw ticket text into an executable task spec following a `TASK.schema.md` contract. Auto-tiers by complexity (micro / standard / full) via a point system; explicit `--tier` overrides. Conditional layers (Frontend / Backend / Database) appear only when the task touches them. Optional `--group` flag loads CODEMAP + STITCH context for cited-path specs so the distilled spec references real files instead of speculating.
- **PreToolUse hook** on Glob/Grep — Reminds to read CODEMAP.md (and sibling STITCH.md when present) before exploring a codebase directly. Fires once per project per session.

### Session Workflow

Hooks and skills that keep sessions continuous across compaction and between conversations.

- `/wrapup` — End-of-session handoff: reviews work, updates PROGRESS.md/CLAUDE.md/memory, prompts for commit and `/extract`, verifies the next session can pick up.
- `/setup` — Configure knowledge folder, validate structure, diff managed files against plugin version, detect companion plugins.
- `/audit-config` — Scan CLAUDE.md files, configs, and docs for drift, broken references, and staleness.
- `/help` — Quick command reference.
- **SessionStart hook** — Checks audit cadences, prompts when review is overdue. First-run welcome for new users. Periodic update check.
- **PreCompact hook** — Saves transcript snapshot before context compaction.
- **PostCompact hook** — Prompts to review captured snapshot after compaction.
- **TaskCreated hook** — Surfaces relevant knowledge files when tasks are created (tag index matching).
- `auto_capture` toggle gates all automatic features.

## Staleness & Freshness

Knowledge bases rot when nothing forces a review. ARIA treats freshness as a first-class concern and solves it through **process**, not storage format.

- **`Last updated` frontmatter on every knowledge file** enables mechanical staleness checks.
- **Configurable staleness thresholds** — `ideas_staleness_threshold_days` (default 21) for ideas-backlog entries; `staleness_threshold_months` for promoted knowledge files. Tune per install in `~/.claude/aria-knowledge.local.md`.
- **Audit cadences** enforce periodic review. SessionStart hook prompts when `/audit-knowledge` or `/audit-config` is overdue.
- **Stale-first surfacing** — `/audit-knowledge` sorts stale ideas above fresh ones and demands explicit Accept/Reject/Defer/Reclassify disposition. Fresh items pass through informationally, so ceremony cost tracks urgency. The asymmetry prevents the accumulation failure mode where implicit Defer silently buries items that have survived a full review cycle without action.
- **Drift detection** — `/audit-config` scans CLAUDE.md files and configs for broken references; `/audit-knowledge` Step 5b3 checks skill-knowledge connections; `/codemap update` refreshes incrementally via git diff; `/index` flags untagged or stale files and suggests cross-references.
- **Rule 22 enforcement** — every Edit/Write requires a visible impact assessment and post-edit scope check. No silent drift because no silent edits.

Format determines auditability; process determines freshness. ARIA's answer is plain markdown for auditability + layered review cadences for freshness + humans in the promotion loop so wrong knowledge doesn't accumulate silently.

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

## Works Well With Obsidian

The knowledge folder is plain markdown — it works great as an Obsidian vault. We recommend using [Obsidian Web Clipper](https://obsidian.md/clipper) to save articles and references directly into `intake/clippings/`, where ARIA's audit process can review and promote them.

## Philosophy

ARIA takes the position that **the LLM captures, the human promotes.** AI is excellent at noticing and structuring knowledge during sessions. But deciding what's load-bearing vs. noise requires human judgment.

See [plugin/template/OVERVIEW.md](plugin/template/OVERVIEW.md) for the full design rationale.

## ARIA vs Other Memory Architectures

ARIA, Karpathy-style markdown wikis, and graph-DB memory systems (mem0, Graphiti) all solve "give the LLM persistent memory" — but they optimize different things. Understanding the axes helps you pick correctly.

| Axis | ARIA | Karpathy Wiki | Graph DB Memory |
|------|------|---------------|-----------------|
| **Storage** | Markdown + tag index | Markdown + backlinks | Vector + graph nodes |
| **Curation authority** | Human promotes | LLM auto-compiles + lints | LLM auto-updates |
| **Auditability** | High — diffable git history, every promotion is a human decision | High — files are source of truth, but LLM authorship obscures intent | Low — embedding space is opaque |
| **Freshness mechanism** | Audit cadences + staleness thresholds + Rule 22 edits | LLM linting passes ("self-healing") | Automatic updates on new inputs |
| **Process discipline** | Rule 22 change decision framework enforced at every edit | None formalized | None formalized |
| **Failure mode** | Slower curation (humans are the rate-limit) | Confident-wrong LLM rewrites compound silently across backlinks | Hallucinated updates cascade; can't trace back to source |
| **Ideal scale** | 100–1000 high-signal docs; operational knowledge | 100–10000 docs; personal research | Millions of docs; retrieval-heavy agent workloads |

The shared instinct with Karpathy is strong: markdown as source of truth, human-readable, diffable, no vendor lock-in. ARIA diverges on the central question — **who decides what becomes durable knowledge?** Karpathy's answer is the LLM, compiling and linting autonomously ("You rarely ever write or edit the wiki manually; it's the domain of the LLM"). ARIA's answer is the human, reviewing LLM-captured candidates during audit.

This reflects a domain difference, not a quality judgment. **Karpathy's model is excellent for automated research compilation** — synthesizing papers, building a personal wiki of evolving understanding, where the LLM's authorial speed is the point and occasional drift is acceptable because the artifact isn't load-bearing on daily decisions. **ARIA is built for operationally applied decision-making** — working rules, architecture decisions, team conventions, and project knowledge that feed into code and product decisions every day. In that domain, an LLM-promoted wrong rule cascading across backlinks degrades real output before anyone notices, which is why ADR 010 ("LLM captures, human promotes") keeps the human gate in place. Different tool for a different job.

Graph-DB memory systems win on retrieval quality — vector search + graph traversal beats grep at scale. They lose on provenance and curation discipline. If retrieval recall is your bottleneck, ARIA and graph DB aren't mutually exclusive: use ARIA as the capture and curation layer, pipe promoted markdown into a graph DB for retrieval.

Pick the tool that matches the actual pain:

- **Operational knowledge that drives decisions and code → ARIA.** Human gate prevents auto-accumulation of confident errors. Rule 22 prevents silent drift.
- **Slow retrieval across thousands of docs → Graph DB.** Vector search solves what grep doesn't.
- **Automated research compilation and evolving personal wikis → Karpathy wiki.** LLM-authored synthesis is the strength; great when the artifact is read, not acted on.

## Model Recommendations

ARIA skills vary in how much they benefit from stronger models. These are recommendations only — nothing is enforced. Switch per session via `/model` before running a skill.

- **Opus 4.6 (1M context), medium-to-high effort** — `/extract`, `/audit-knowledge`, `/audit-config`. Judgment-heavy: deciding what's load-bearing vs. noise, cross-referencing backlogs against the promoted index, detecting drift across configs. A weaker model over-captures (backlog noise) or under-captures (misses non-obvious feedback). ARIA's compliance discipline benefits from the extra reasoning budget (more reliable Low/High assessments, less tool-call skipping on audit skills).
- **Opus 4.6 (1M context) minimum** — `/codemap create`. Full-repo traversal needs the large context window so sections aren't truncated mid-generation.
- **Sonnet 4.6** — `/codemap update/section`, `/wrapup`, `/intake`, `/ask` (scoped lookups), `/distill`, `/stitch`, and all lightweight skills (`/index`, `/stats`, `/backlog`, `/rules`, `/context`, `/clip`, `/help`, `/setup`). Structured or retrieval-only work — higher models add no measurable lift.

Haiku is not recommended for any ARIA skill. See `/help` for the full table.

### Opus 4.7: batch manifests for multi-file work

Under Opus 4.7's tokenizer (1.0–1.35× inflation vs 4.6) and adaptive thinking token budgets, multi-file refactors benefit from declaring a **batch manifest** via `/distill` with the group loader. A batch manifest compresses each in-scope file's Rule 22 assessment to the `[Rule 22 · Batch N/M]` marker, preserving enforcement while significantly reducing per-edit token cost. Structural signals (auth, migration, model, routing, external-service paths) still override the batch low-impact declaration automatically. For 3+ file refactors, declare a batch manifest before starting edits.

See `knowledge/projects/aria/references/opus-4-7-aria-compatibility.md` for the full list of verified 4.7 behaviors ARIA is designed around.


## Known Issues

- **"hook error" label on Pre/PostToolUse hooks** — Claude Code displays "hook error" next to every tool call that triggers a hook, even when the hook exits successfully (exit code 0) with valid JSON output. This is a [known Claude Code UI bug](https://github.com/anthropics/claude-code/issues/17088) — the Rule 22 enforcement hooks are working correctly. The label is cosmetic and does not indicate a problem with ARIA.

## License

[CC BY-NC-SA 4.0](LICENSE) — Free to use and modify. Must be attributed, non-commercial, and derivatives must share alike.

## Support

If ARIA is useful to you, consider buying me Claude credits via [PayPal](https://www.paypal.biz/prasadmike) or [Venmo](https://venmo.com/mikeprasad).
