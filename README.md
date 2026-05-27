<p align="left">
  <img src="aria-icon-rounded.png" width="120" alt="ARIA">
</p>

# ARIA — Applied Reasoning and Insight Architecture

> **Agent Memory · Context Engineering · Planning & Reasoning · Human-in-the-Loop Governance**
>
> ARIA is the missing infrastructure layer for production AI coding agents: persistent memory that survives context compaction, deliberate context engineering that loads the right knowledge before action, human-governed trust gates that keep AI from acting on noise, and structured session discipline that gives agents the continuity needed for long-horizon reasoning.

**The AI captures. The human promotes. Trusted knowledge acts.**

![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg)
![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-blueviolet)
![Claude Cowork](https://img.shields.io/badge/Claude%20Cowork-plugin-purple)
![OpenAI Codex](https://img.shields.io/badge/OpenAI%20Codex-plugin-black)
![Cursor](https://img.shields.io/badge/Cursor-template-blue)
![Antigravity](https://img.shields.io/badge/Antigravity-plugin-orange)
![Local First](https://img.shields.io/badge/local--first-yes-green)

> **New to ARIA?** See [QUICKSTART.md](QUICKSTART.md) — 5-minute setup + best practices by session phase.

ARIA is a local-first knowledge and execution-discipline layer for AI coding sessions. It ships as a family of ports — Claude Code (`plugin-claude-code/`), Claude Cowork (`plugin-claude-cowork/`), OpenAI Codex (`plugin-openai-codex/`), Antigravity (`plugin-antigravity/`), and Cursor (`plugin-cursor-template/`) — all sharing the same `~/Projects/knowledge/` folder. Insights captured in one tool flow into another. The folder itself is plain markdown — readable by any AI, any human, any editor, with or without ARIA installed.

ARIA manages a complete knowledge lifecycle: it captures insights, decisions, and feedback during sessions; stages them in backlogs for human review; promotes what matters into a searchable, tag-indexed knowledge base; and applies that trusted knowledge back into future tasks, edits, and handoffs. Session hooks prevent knowledge loss during context compaction, surface relevant knowledge when tasks are created, and enforce a visible change decision framework at every file edit.

## Why ARIA

Production AI coding agents do not usually fail because the model is incapable. They fail because the working system around the model is incomplete. ARIA addresses four failure modes that repeatedly break agentic work in practice.

### Agent Memory

Every session starts from zero. Context compaction erases decisions. Debugging discoveries disappear into transcripts. The next session reopens questions that were already settled.

ARIA gives your agent persistent, structured memory across sessions and across tools. It captures insights during work, stages them for review, and builds a durable knowledge base that survives session boundaries.

### Context Engineering

What the model sees determines what it does. Most teams still treat this as an ad hoc prompt-writing problem.

ARIA engineers context deliberately. It surfaces relevant knowledge at task creation time, loads project-specific rules and patterns before edits, and grounds work with artifacts like code maps, cross-repo stitch tables, and repository-aware task specs — so the model always acts on current, accurate context rather than assumptions.

### Planning & Reasoning

Long-horizon work fails when the agent loses continuity between decisions, constraints, and active workstreams.

ARIA does not implement planning algorithms. It solves the continuity layer planning depends on: `/distill` turns tickets into grounded task specs that cite real files, `/codemap` gives structural codebase awareness, `/stitch` builds cross-repo bindings, and `/handoff` preserves full session state so reasoning chains do not break at session boundaries.

### Human-in-the-Loop Governance

Auto-memory tools drift. They accumulate noise alongside signal, and the model eventually acts on unreviewed assumptions.

ARIA keeps humans in the loop. The AI captures candidate knowledge, but humans review and promote what becomes trusted. Audit logs and disposition history live in your own repo under git — not a vendor dashboard. Every promotion is explicit and traceable.

## The Core Idea

Most memory tools help an assistant remember more. ARIA goes further: it asks **what knowledge is worth trusting**, **how it should be reviewed**, and **how trusted knowledge should actively shape the next decision, task, and code change**.

That is the difference between passive memory and applied operational knowledge.

## How It Works

Knowledge moves through a five-phase lifecycle: **Capture → Govern → Promote → Apply → Refresh.**

### Capture

Preserve session knowledge before context evaporates.

- `/extract` — Scan conversations for uncaptured insights, decisions, feedback, references, and ideas. Deduplicates against existing entries.
- `/clip` — Quick-save URLs or text snippets to intake without leaving the session.
- `/clip-thread` (v2.18.0+) — Capture a chat or email thread from a connected `~~chat` or `~~email` MCP. Source-type detection (Slack archives / Teams messages / Gmail threads / MS365); per-message structure + reactions + attachment notes; user-fill reaction section.
- `/ask` — Research a question, check existing knowledge first, save the answer directly as a knowledge doc.
- `/intake` — Bulk import from files, directories, or URLs with preview before staging. Doc mode (v2.17.0+): `/intake doc <url-or-title>` captures one structured artifact per doc with 5-section body + user reaction.
- `/extract-doc` (v2.18.0+) — Pull insights from a single Notion / Confluence / Google Doc / Box / Egnyte page via a connected `~~docs` MCP.

### Govern

Convert raw capture into reviewable candidates.

- All captured knowledge stages in a backlog — nothing enters the trusted layer automatically.
- Human review is the gate between capture and promotion.
- Provenance is preserved so every piece of knowledge is inspectable and auditable.

### Promote

Move reviewed knowledge into the trusted layer.

- `/promote` — Promote a backlog entry into the indexed knowledge base.
- Organize by tag, project tier, and cross-project patterns.
- Optional project-specific tier (v2.8.0+) for architecture decisions and patterns.

### Apply

Make trusted knowledge shape real work.

- **TaskCreated hook** — Surfaces relevant knowledge files when tasks are created (tag index matching).
- **Rule 22** — Change decision framework enforced at every file edit. Requires visible impact assessment and scope verification before and after changes.
- `/context` — Load relevant knowledge into the current session for immediate use.
- `/rules` — Surface working rules that apply to the current task.

**Codebase and task mapping turn ambiguous surface area into structured artifacts the agent can ground decisions against.**

- `/codemap` — Feature-organized reference for any repository. Scans repos, detects frameworks, traces full-stack flows (routes → hooks → state → views → models → integrations). Four modes: `create` (full generation), `inventory` (quick index), `update` (incremental via git diff), `section` (rebuild one section).
- `/stitch` — Cross-repo binding artifact for product groups (backend + frontends). Tables for group identity, auth path, endpoint stitch, entity stitch, integration stitch, and a drift log.
- `/distill` — Turns raw ticket text into an executable task spec following a `TASK.schema.md` contract. Auto-tiers by complexity (micro / standard / full). Optional `--group` flag loads CODEMAP + STITCH context for cited-path specs.
- `/prospect` — Forward-looking pre-mortem on a plan before execution. Per-step actions: PROCEED / SHRINK / SPLIT / DEFER / KILL. Output saved to `logs/prospect/`.
- `/retrospect` — Structured retrospective on a shipped commit range, single commit, PR, release, or session. Enforces per-fix validation, surfaces simpler alternatives, runs failure-mode pattern checks. Output saved to `logs/retrospect/`.

**Hooks make application continuous in the background.**

- **PreToolUse hook on Glob/Grep** — Reminds to read CODEMAP.md before exploring a codebase directly. Fires once per project per session.
- **PreCompact hook** — Saves transcript snapshot before context compaction.
- **PostCompact hook** — Prompts to review captured snapshot after compaction.
- `auto_capture` toggle gates all automatic features.

### Refresh

Knowledge bases rot when nothing forces review. ARIA treats freshness as a first-class concern.

- `Last updated` frontmatter on every knowledge file enables mechanical staleness checks.
- Configurable staleness thresholds — `ideas_staleness_threshold_days` (default 7) for `intake/ideas/` entries; `staleness_threshold_months` for promoted knowledge files.
- Audit cadences enforce periodic review. SessionStart hook prompts when `/audit-knowledge` is due.
- `/audit-config` and `/audit-knowledge` detect drift, staleness, and gaps on configurable cadences.

## Ideas Lifecycle (since v2.12)

Ideas — feature proposals, bug reports, design suggestions — flow into `intake/ideas/` during `/extract`. They have a distinct lifecycle from the four knowledge backlogs because they describe **what should be different**, not **what is**.

1. **Capture** — `/extract` writes one file per idea to `intake/ideas/`, with YAML frontmatter and a Proposal/Motivation/Source body.
2. **Stale-first surfacing** — `/audit-knowledge` sorts stale ideas above fresh ones (default 7 days) and forces explicit disposition on stale entries.
3. **Seven-destination Accept submenu** — each accepted idea routes to one of: `tracker | roadmap | todo | adr | backlog | bundle | rule`.
4. **Detection-aware routing** — `roadmap` and `todo` only appear when `ROADMAP.md` / `TODO.md` exists; the submenu shrinks per idea.
5. **Bundle clustering** — when 2+ ideas in the same project share ≥2 significant title words, the audit offers to merge them.
6. **`ticketing_plugins` config** — declare your ticket-drafting plugin per project tag and `/audit-knowledge` prints a one-line hint at `Accept → tracker` time. Hint only — never auto-invokes another plugin.

Ideas never promote directly into `approaches/`, `decisions/`, or `rules/`. The `adr` and `rule` destinations route through their respective backlogs for normal audit-cycle review.

## Shared Knowledge Tier (since v2.13)

Personal knowledge captures stay on one developer's laptop. The Shared Knowledge tier adds a third level alongside personal (`~/Projects/knowledge/`) and project-specific (`projects/{tag}/`): selected items can be promoted to per-repo `_project-knowledge/` folders so teammates working in the same code repo can find and read them. Independent records, not a sync layer — personal copies stay where they are; team copies get committed through normal git/PR review.

1. **Per-project opt-in** — the `projects_shared_knowledge` config field is a comma-separated tag list; empty/missing means feature disabled.
2. **`/audit-share` (alias `/share-audit`)** — batch-review surface. Walks personal knowledge folders + IDEAS-BACKLOG.md entries, filters by enabled-project list, recommends destinations grouped by action. Public-repo targets get a sanitization warn-prompt before each write.
3. **Folder + filename convention** — `<project-root>/_project-knowledge/{YYYY-MM-DD}-{author}-{slug}.md`; cross-cutting items live in `_project-knowledge/cross/`. Tool-agnostic so non-ARIA teammates can read/write directly.
4. **Frontmatter back-pointers** — personal copies gain a `shared:` array; team copies carry `origin:`, `shared_by:`, `shared_at:`. Provenance both directions.
5. **CLAUDE.md reference offer at first-write** — `/audit-share` offers to append a "Team-Shared Knowledge" section so teammates not using ARIA can discover the convention. Three warning tiers based on git-tracked + remote-visibility detection.
6. **Read-side via `/index` + `/context`** — tag-based discovery composes naturally; `/context api` surfaces team-shared, project, and cross-project files together.

## How ARIA Differs

ARIA solves the same high-level problem as markdown wikis, graph-based memory systems, and MCP memory servers — persistent context across sessions — but optimizes for a different outcome: **trusted operational knowledge that actively shapes code and decisions**.

| Axis | ARIA | Karpathy Wiki | Graph DB Memory | Basic Memory / MCP Memory |
|------|------|---------------|-----------------|---------------------------|
| **Primary job** | Trusted operational knowledge for AI coding work | LLM-authored personal / research wiki | Retrieval-heavy large-scale memory | General-purpose persistent recall |
| **Agent Memory** | ✅ Strong | ✅ Strong | ✅ Strong | ✅ Strong |
| **Context Engineering** | ✅ Strong — grounded artifacts, task-aware surfacing | ⚡ Moderate — retrieval from markdown | ⚡ Moderate — retrieval-centric | ⚡ Low to moderate |
| **Planning & Reasoning support** | ✅ Strong — continuity layer for long-horizon work | ⚡ Low to moderate | ⚡ Moderate | ⚡ Low |
| **Human-in-the-loop governance** | ✅ Strong — human promotion gate | ❌ Low | ❌ Low | ⚡ Low to moderate |
| **Storage** | Markdown + tag index + backlogs | Markdown + backlinks | Vector + graph nodes | Varies |
| **Curation authority** | Human promotes | LLM auto-compiles + lints | LLM auto-updates | Usually automatic |
| **Auditability** | High — diffable git history, every promotion explicit | High — file-based, but LLM authorship can blur intent | Low — opaque embedding space | Varies |
| **Failure mode** | Slower curation (humans are the rate-limit) | Confident-wrong LLM rewrites compound silently | Hallucinated updates cascade without traceable source | Memory drift without discipline |
| **Ideal scale** | 100–1000 high-signal docs; operational knowledge | 100–10000 docs; personal synthesis | Millions of docs; retrieval-heavy workloads | Broad compatibility at any scale |

The shared instinct with Karpathy is strong: markdown as source of truth, human-readable, diffable, no vendor lock-in. ARIA diverges on the central question — **who decides what becomes durable knowledge?** Karpathy's answer is the LLM, compiling and linting autonomously. ARIA's answer is the human, reviewing LLM-captured candidates during audit.

**Basic Memory + MCP memory servers** give assistants persistent memory across sessions, often as entities/relations or local markdown notes. They optimize for general-purpose recall and broad compatibility. ARIA is more opinionated and developer-workflow specific: structured backlogs, promotion workflows, audits, codebase maps, cross-repo stitching, task distillation, and Rule 22 edit-time discipline. They can sit alongside ARIA — ARIA curates the trusted-decision tier, generic memory layers handle general recall.

## Context Efficiency Over Time

ARIA is designed to improve context efficiency over time, not guarantee lower token usage in any single session. It adds structure in the moment — Rule 22 checks, hooks, extraction, audits, and context surfacing all consume tokens. The benefit appears across repeated work: ARIA reduces context waste by replacing repeated rediscovery with compact, reviewed, task-relevant knowledge.

The goal is not fewer tokens overall — it is fewer tokens spent re-learning the same things, and more tokens applying trusted knowledge to the next task, decision, and code change.

## Model Recommendations

ARIA skills vary in how much they benefit from stronger models. These are recommendations only — nothing is enforced.

- **Opus 4.6 (1M context), medium-to-high effort** — `/extract`, `/audit-knowledge`, `/audit-config`. Judgment-heavy skills where a weaker model over-captures (backlog noise) or under-captures (misses non-obvious feedback).
- **Opus 4.6 (1M context) minimum** — `/codemap create`. Full-repo traversal needs the large context window.
- **Sonnet 4.6** — `/codemap update/section`, `/wrapup`, `/intake`, `/ask`, `/distill`, `/stitch`, and all lightweight skills. Structured or retrieval-only work — higher models add no measurable lift.

Haiku is not recommended for any ARIA skill. Run `/help` for the full table.

### Opus 4.7: batch manifests for multi-file work

Under Opus 4.7's tokenizer (1.0–1.35× inflation vs 4.6) and adaptive thinking token budgets, multi-file refactors benefit from declaring a **batch manifest** via `/distill` with the group loader. A batch manifest compresses each in-scope file's Rule 22 assessment to the `[Rule 22 · Batch N/M]` marker, preserving enforcement while significantly reducing per-edit token cost. Structural signals (auth, migration, model, routing, external-service paths) still override the batch low-impact declaration automatically. For 3+ file refactors, declare a batch manifest before starting edits.

## Known Issues

- **"hook error" label on Pre/PostToolUse hooks** — Claude Code displays "hook error" next to every tool call that triggers a hook, even when the hook exits successfully (exit code 0) with valid JSON output. This is a [known Claude Code UI bug](https://github.com/anthropics/claude-code/issues/17088). The Rule 22 enforcement hooks are working correctly. The label is cosmetic.

## Install

### CLI

1. Copy the `plugin-claude-code/` directory to your Claude Code plugins folder.
2. Run `/setup` to configure your knowledge folder.
3. Start working — ARIA begins capturing knowledge automatically.

### Desktop / IDE

1. Download the latest zip from [Releases](https://github.com/mikeprasad/aria-knowledge/releases).
2. In Claude Code, go to **Customize > Add Plugin > Local** and select the downloaded zip.
3. Run `/setup` to configure your knowledge folder.

After install, run `/help` anytime to see the full command catalog with model recommendations.

### Codex Port

A standalone Codex port lives in [`plugin-openai-codex/`](plugin-openai-codex/). It keeps the Claude-standard ARIA knowledge folder and content schema while adapting the plugin manifest, hooks, and command entrypoints for Codex. See [`plugin-openai-codex/README.md`](plugin-openai-codex/README.md) for current parity notes and setup details.

### Cursor Port

A standalone Cursor port lives in [`plugin-cursor-template/`](plugin-cursor-template/). Unlike the Claude and Codex ports, it is a **repo skeleton**, not a plugin install: unzip [`aria-knowledge-cursor-2.20.2.zip`](https://github.com/mikeprasad/aria-knowledge/releases) (or `aria-knowledge-cursor.zip` stable alias) into the root of your own project, then restart Cursor.

The port compiles **27 commands** (22 core + 5 MCP skills, plus `/help` and `/audit-share`) into 5 `.cursor/rules/*.mdc` files. Project instructions use root **`AGENTS.md`** (not `CLAUDE.md`). Config: `.cursor/aria-knowledge.local.md`. MCP skills require servers connected in **Cursor Settings → MCP**.

See [`plugin-cursor-template/QUICKSTART.md`](plugin-cursor-template/QUICKSTART.md) for setup and [`plugin-cursor-template/PORTING.md`](plugin-cursor-template/PORTING.md) for maintainer drift notes.

### Claude Cowork Port

A standalone Claude Cowork port lives in [`plugin-claude-cowork/`](plugin-claude-cowork/). Both ports share the same `~/Projects/knowledge/` folder — insights flow between Code and Cowork sessions without a sync layer. See [`plugin-claude-cowork/README.md`](plugin-claude-cowork/README.md) for full setup, MCP connector config, and skill reference.

> **Both ports installed?** When `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare slash commands (`/handoff`, `/wrapup`, `/extract`, etc.) deterministically resolve to **plugin-claude-code** (the Code-side canonical). For the Cowork variant of any skill, use the namespaced form: `/aria-cowork:handoff`, `/aria-cowork:wrapup`, etc. Each colliding skill carries a Runtime Gate that surfaces a notification if invoked from the wrong runtime. See [ADR 094](https://github.com/mikeprasad/knowledge/blob/main/projects/aria/decisions/094-bare-slash-canonical-owner-and-dual-runtime-gate.md) for the full design.

### Antigravity Port

A standalone Antigravity port lives in [`plugin-antigravity/`](plugin-antigravity/). Install to `~/.gemini/config/plugins/` or `.agents/plugins/`. See [`plugin-antigravity/README.md`](plugin-antigravity/README.md) for setup and parity notes.

## Installable Ports

All ports share the same `~/Projects/knowledge/` folder, working rules, change-decision framework, and audit-cadence model.

| Port | Runtime | Status | Install path |
|------|---------|--------|-------------|
| `plugin-claude-code/` | Claude Code (Anthropic) | Production — schema source-of-truth | `~/.claude/plugins/` or marketplace |
| `plugin-claude-cowork/` | Claude Cowork (Anthropic) | Production | Cowork install flow |
| `plugin-antigravity/` | Antigravity (Google) | Initial port + parity pass complete | `~/.gemini/config/plugins/` or `.agents/plugins/` |
| `plugin-openai-codex/` | Codex (OpenAI) | Production | Codex plugin marketplace or `.agents/plugins/marketplace.json` |
| `plugin-cursor-template/` | Cursor | Production — `2.20.2-cursor.0` (parity w/ Code v2.20.2) | Unzip `aria-knowledge-cursor-*.zip` into project root |

## Works Well With Obsidian

The knowledge folder is plain markdown — it works great as an Obsidian vault. Use [Obsidian Web Clipper](https://obsidian.md/clipper) to save articles and references directly into `intake/clippings/`, where ARIA's audit process can review and promote them.

## Privacy-First by Design

ARIA runs locally. It does not collect analytics, send telemetry, make network requests, use cookies, connect to external services, or share your knowledge base with the plugin author or third parties. Knowledge files, backlogs, indexes, config, transcript-derived artifacts, and project context all stay on your filesystem.

Audit logs and disposition history live alongside your knowledge folder under git, so every promotion and rejection is traceable in your own repo — not a vendor's database.

## Who ARIA Is For

ARIA is for developers and teams using AI coding tools who want:

- Persistent memory across sessions instead of starting from scratch
- Deliberate context engineering instead of ad hoc prompting
- Human-reviewed knowledge instead of automatic memory drift
- Better continuity for multi-step planning and long sessions
- Safer AI-assisted code changes via visible edit-time decision discipline
- Better handoff after compaction or long sessions
- Codebase maps that reduce rediscovery
- Task specs grounded in real repository context
- Markdown knowledge that remains readable, portable, diffable, and versionable

It is especially useful when AI is not just answering questions but actively shaping code, architecture, tasks, and product decisions.

## Philosophy

ARIA takes the position that **the LLM captures, the human promotes, trusted knowledge acts.** AI is excellent at noticing and structuring knowledge during sessions. Deciding what is load-bearing versus noise requires human judgment. And once trusted, that knowledge is most useful when it actively shapes the next decision — through context loading, rules surfacing, codebase mapping, task distillation, and Rule 22 edit-time discipline.

See [plugin-claude-code/template/OVERVIEW.md](plugin-claude-code/template/OVERVIEW.md) for the full design rationale.

## Evidence and Limits

ARIA is shaped by real-failure data from the plugin author's projects, not controlled study. Behavioral effects are asserted from experience, not benchmarks. ARIA shares the honest limit of the broader field: strong resonance from practitioners, no controlled before/after measurements across the developer population.

**Where ARIA is most likely to help:**

- Multi-repo, multi-team operational work where decisions and rules need to persist across sessions
- Developers who have accumulated knowledge files and want a discipline layer rather than just storage
- Codebases where confident-wrong AI output has measurable downstream cost

**Where ARIA may be overkill:**

- One-off scripts or single-file projects — the 4-line behavioral foundation alone is often sufficient
- Greenfield codebases without the recurring-context problem ARIA solves
- Teams that haven't yet experienced the AI-coding failure modes ARIA's rules target

## ARIA Family

ARIA is a family of projects under the name **Applied Reasoning and Insight Architecture**. Each member targets a different surface; the plugin ports above all live in this repo.

### License Posture

Licenses differ across the family. **aria-knowledge** (this repo, all ports) ships under [CC BY-NC-SA 4.0](LICENSE) — free for non-commercial use, copyleft on derivatives.

## License

[CC BY-NC-SA 4.0](LICENSE) — Free to use and modify. Must be attributed, non-commercial, and derivatives must share alike.

## Support

If ARIA is useful to you, consider buying me Claude credits via [PayPal](https://www.paypal.biz/prasadmike) or [Venmo](https://venmo.com/mikeprasad).

## Try It

Install ARIA, run `/setup`, work normally. Rule 22 is active immediately. Run `/extract` before ending sessions. Run `/audit-knowledge` when prompted. Each session builds on the last.

**Memory is not enough. Trusted application is the goal.**

---

*Last reviewed: 2026-05-27 — current as of plugin-claude-code v2.20.2 / plugin-claude-cowork v1.1.3 / plugin-cursor-template 2.20.2-cursor.0.*
