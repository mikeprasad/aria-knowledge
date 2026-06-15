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

- `/audit-knowledge` (alias `/knowledge-audit`) — Review staged backlog entries and promote the ones worth trusting into the indexed knowledge base. Promotion happens *inside* the audit — there is no standalone `/promote` command.
- Organize by tag, project tier, and cross-project patterns.
- Optional project-specific tier (v2.8.0+) for architecture decisions and patterns.
- Optional non-blocking SessionStart project picker (v2.26.0+) — for multi-project parent dirs, suggests a project menu generated from `projects_list` and reads the chosen project's `CLAUDE.md`/`PROGRESS.md`.

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
- `/foundational-review` — The foundational review chain, run before an irreversible decision (version freeze, format/spec tag, public flip, major re-scope): verdict + named premises + sections A–F → design spec → cold-executable plan with owner routing → composed `/prospect` (amendments applied in place) → paste-ready executor kickoff. Requires a named irreversible decision (else redirects to `/prospect` or `/readiness-audit`). `--extend` adds the system-design assessment + roadmap chain.
- `/readiness-audit` — The recurring sibling: a checklist-against-a-surface audit answering "is it clean/legal/consistent to ship for THIS event?" Controller re-verifies every load-bearing agent claim (correction trail), read-only probes only with a mandatory artifact diff-check, tiered evidence-celled findings, phased remediation. No decision anchor needed.

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

## Recommended Setup

`/setup` runs ARIA with safe defaults. Below is the maintainer's own setup — the low-effort, high-outcome way ARIA is meant to be used day to day. All settings live in `~/.claude/aria-knowledge.local.md` and can change any time.

### Folder layout

Keep a single **`Projects/`** folder with your **`knowledge/` folder inside it** and **every project as a sibling** underneath:

```
Projects/
├── knowledge/          ← ARIA's corpus (back this up / version-control it)
├── project-a/
├── project-b/
└── ...
```

Run `/setup` with **projects enabled** and map each project in `projects_list`. This one-time layout is what makes `/context <tag>`, project-scoped knowledge, and CODEMAP/STITCH surfacing "just work" — knowledge is routed to the right project automatically instead of pooling into one undifferentiated heap.

### A session, start to finish

1. **Start at the `Projects/` folder level**, naming the project: `project-name` — or **`project-name handoff`** if you're continuing from a previous session (ARIA resumes from the `SESSION.md` it wrote last time).
2. **Spec & plan with [Superpowers](https://github.com/obra/superpowers)**, then **`/prospect`** the plan before executing. Superpowers brings the planning discipline; ARIA's pre-mortem catches the ~3-in-4 plans that need a correction before any code lands.
3. **Execute.** Rule 22 runs on every edit automatically — no action needed.
4. **`/retrospect`** after big or critical executions (auth, migrations, releases, anything with asymmetric cost). Skip it for trivial changes — match the ceremony to the risk.
5. **Close the session:**
   - **`/handoff auto`** if work continues next session — runs the full close-out (PROGRESS / CLAUDE / memory / commit) plus a paste-ready next-session opener, and captures knowledge via `/extract`. Silent, one command.
   - **`/wrapup auto`** if there's nothing to carry forward — same close-out, no handoff opener.

### Keep the corpus healthy

ARIA's value compounds only if the knowledge stays signal-dense:

- **`/audit-knowledge` + `/index`** regularly — about **weekly, or every 25+ sessions**. This promotes staged captures into the reviewed corpus and rebuilds the tag index. A corpus that's captured but never promoted is just noise with extra steps.
- **`/audit-config`** occasionally — catches drift and stale references in your setup and CLAUDE.md files.

ARIA prompts you on these cadences (`audit_cadence_knowledge`, `audit_cadence_config`) — don't dismiss them indefinitely.

### Worth enabling

- **`active_knowledge_surfacing: true`** (default) — surfaces relevant knowledge before plans and edits.
- **`/statusline`** — context-window + 5-hour / 7-day usage meter; worth it for long or back-to-back sessions.
- **`auto_prospect: nudge` + `auto_retrospect: nudge`** — surface the `/prospect` step when you write a plan to `docs/plans/`, and the `/retrospect` step after a qualifying push, so the disciplines become prompts rather than things to remember. Start with `nudge` before `run`.
- **Obsidian** — open `knowledge/` as a vault for graph navigation. See [Works Well With Obsidian](#works-well-with-obsidian).

## Model Recommendations

ARIA skills vary in how much they benefit from stronger models. These are recommendations only — nothing is enforced.

- **Opus-tier (1M context), high effort** — `/extract`, `/audit-knowledge`, `/audit-config`, `/foundational-review`, `/prospect`, `/retrospect`. Judgment-heavy skills where a weaker model over-captures (backlog noise) or under-captures (misses non-obvious feedback). Opus 4.8 is the current default.
- **Opus-tier (1M context) minimum** — `/codemap create`. Full-repo traversal needs the large context window.
- **Sonnet 4.6** — `/codemap update/section`, `/wrapup`, `/intake`, `/ask`, `/distill`, `/stitch`, and all lightweight skills. Structured or retrieval-only work — higher models add no measurable lift.

Haiku is not recommended for any ARIA skill. The runtime is model-agnostic (statusline reads the live model name; usage/context hooks are percentage-based), so these are guidance, not gates. Run `/help` for the full table.

### Batch manifests for multi-file work

On the current Opus tier, multi-file refactors benefit from declaring a **batch manifest** via `/distill` with the group loader. A batch manifest compresses each in-scope file's Rule 22 assessment to the `[Rule 22 · Batch N/M]` marker, preserving enforcement while significantly reducing per-edit token cost. Structural signals (auth, migration, model, routing, external-service paths) still override the batch low-impact declaration automatically. For 3+ file refactors, declare a batch manifest before starting edits.

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

## Works Well With Superpowers

ARIA is the **knowledge and edit-discipline** layer; [Superpowers](https://github.com/obra/superpowers) is the **process-discipline** layer — and they interlock into a full plan → build → verify → learn loop. Superpowers' `writing-plans` produces a plan; ARIA's `/prospect` pre-mortems it before any file is touched; Superpowers' `executing-plans` / `subagent-driven-development` / TDD build it; ARIA's `/retrospect` closes the loop with per-fix validation and feeds the failure-pattern library. ARIA even stores plans and specs in the `docs/superpowers/{plans,specs}/` convention.

**Strongly recommended, though optional** — ARIA works standalone and never depends on Superpowers being present, but the two together are the intended full discipline. `/setup` checks for it and points you to the install if it's missing.

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

## Feature Map

Everything ARIA ships, organized by the four problems it solves — plus the operational layer that keeps the system itself healthy. **Skills** are slash commands you invoke; **hooks** run automatically in the background (Claude Code only — other ports vary); **features** are config-gated behaviors. Aliases are noted inline. MCP-consuming skills are marked `(MCP)` and degrade gracefully when no connector is present.

### Agent Memory — persistent capture across sessions and tools

| Capability | Type | What it does |
|------------|------|--------------|
| `/extract` | Skill | Scan the conversation for uncaptured insights, decisions, feedback, references, and ideas; deduplicate against existing entries. |
| `/clip` | Skill | Quick-save a URL or text snippet to intake without leaving the session. |
| `/clip-thread` `(MCP)` | Skill | Capture a Slack / Teams / Gmail / MS365 thread with per-message structure, reactions, and attachment notes. |
| `/intake` (+ `/intake doc`) | Skill | Bulk import from files, directories, or URLs with preview; `doc` mode captures one structured artifact per page. |
| `/extract-doc` `(MCP)` | Skill | Pull insights from a single Notion / Confluence / Google Doc / Box / Egnyte page. |
| `/meeting-notes` `(MCP)` | Skill | Fold a meeting transcript or notes into structured intake (paste-text fallback works without an MCP). |
| `/ask` | Skill | Research a question, check existing knowledge first, save the answer as a knowledge doc. |
| `/backlog` | Skill | View and manage pending intake items across the four backlogs. |
| `/snapshot` | Skill | Save the current session transcript to `intake/pre-compact-captures/` on demand. |
| PreCompact hook | Hook | Save a transcript snapshot before context compaction erases it. |
| PostCompact hook | Hook | Prompt to review the captured snapshot after compaction. |
| SubagentStop capture | Hook | Archive heavyweight subagent transcripts to `intake/subagent-captures/` (sticky retention). |
| SubagentStart self-report | Hook | Nudge routine subagents to self-report capturable knowledge. |
| Ideas Lifecycle | Feature | One file per idea in `intake/ideas/`; stale-first surfacing; seven-destination accept submenu (v2.12+). |
| `auto_capture` toggle | Feature | Master gate for all automatic capture behaviors. |

### Context Engineering — load the right knowledge before action

| Capability | Type | What it does |
|------------|------|--------------|
| `/context [tags]` | Skill | Load relevant knowledge files into the session by topic (AND/OR, project expansion). |
| `/rules [number]` | Skill | Surface working rules that apply to the current task, by number or keyword. |
| `/index` | Skill | Rebuild the tag-based knowledge index with cross-references — the retrieval substrate `/context` reads. |
| `/codemap [mode]` | Skill | Feature-organized `CODEMAP.md` for any repo; traces routes → hooks → state → views → models → integrations. Modes: create / inventory / update / section. |
| `/stitch <mode> <group>` | Skill | Cross-repo binding artifact for a product group (auth, endpoints, entities, integrations, drift log). |
| TaskCreated hook | Hook | Surface matching knowledge files when a task is created (tag-index match). |
| PreToolUse (Glob/Grep) hook | Hook | Remind to read `CODEMAP.md` before exploring a codebase directly; fires once per project per session. |
| Shared Knowledge Tier | Feature | Per-repo `_project-knowledge/` folders so teammates discover team-promoted knowledge (v2.13+). |

### Planning & Reasoning — continuity for long-horizon work

| Capability | Type | What it does |
|------------|------|--------------|
| `/distill [text or path]` | Skill | Turn raw ticket text into an executable task spec (`TASK.schema.md`); auto-tiers micro / standard / full; `--group` loads CODEMAP + STITCH for cited-path specs. |
| `/prospect` | Skill | Forward-looking pre-mortem on a plan before execution. Per-step verdicts: PROCEED / SHRINK / SPLIT / DEFER / KILL. Saved to `logs/prospect/`. |
| `/retrospect` | Skill | Structured retrospective on a commit range, PR, release, or session; per-fix validation, simpler-alternative discipline, failure-mode pattern check. Saved to `logs/retrospect/`. |
| `/foundational-review <scope-root>` | Skill | Foundational review chain before an irreversible decision: verdict + premises + A–F → design spec → cold-executable plan → composed `/prospect` → kickoff. Requires a named irreversible decision; `--extend` adds the system-design chain. |
| `/readiness-audit <scope-root>` | Skill | Recurring surface readiness audit (sibling of `/foundational-review`): controller-verified agent claims, read-only probes + artifact diff-check, tiered evidence-celled findings, phased remediation. |
| `/handoff [auto\|brief]` | Skill | Express session handoff with the same coverage as `/wrapup`; always emits a paste-ready next-session opener (`brief` produces a coworker prose brief instead). |
| `/wrapup [auto]` | Skill | End-of-session closeout — update PROGRESS / CLAUDE.md, prompt for commit, capture knowledge, verify continuity. No passoff opener. |
| `/digest` `(MCP)` | Skill | Cross-tool rollup of what's pending / shipped / blocked across chat, email, project tracker, and docs. |
| auto-prospect hook | Hook | Offer/run `/prospect file <path>` when a plan is written to a plans folder (opt-in, default off). |
| auto-retrospect hook | Hook | Offer/run `/retrospect range <old>..<new>` on a qualifying `git push` (opt-in, default off). |
| SESSION.md producer | Feature | `/wrapup` + `/handoff` write a per-project `SESSION.md` across an in-progress / handoff / wrapup lifecycle (gated on `session_state`). |

### Human-in-the-Loop Governance — review, promote, audit, trust

| Capability | Type | What it does |
|------------|------|--------------|
| `/audit-knowledge` (alias `/knowledge-audit`) | Skill | Review backlogs, **promote** reviewed candidates into the indexed knowledge base, rebuild the index. |
| `/audit-config` (alias `/config-audit`) | Skill | Check project configs and CLAUDE.md files for drift, staleness, and broken references. |
| `/audit-share` (alias `/share-audit`) | Skill | Batch-review personal knowledge for promotion to per-repo team-shared knowledge; sanitization warn-prompt before public-repo writes. |
| `/sync-decisions` `(MCP)` | Skill | Mirror approved decisions out to a connected docs MCP (write-side; Rule 22 advisory preamble + per-write go-gate). |
| Rule 22 enforcement | Hook | Pre-edit + post-edit change-decision framework — visible impact assessment and scope verification before and after every file edit. |
| Govern phase (backlog gate) | Feature | Nothing enters the trusted layer automatically; human review is the gate between capture and promotion, with provenance preserved. |
| Audit cadences | Feature | SessionStart hook prompts when `/audit-knowledge` or `/audit-config` is due; staleness thresholds force review of aging entries. |

### Setup, Health & Observability — keeping the system itself healthy

| Capability | Type | What it does |
|------------|------|--------------|
| `/setup` | Skill | Create or validate the knowledge folder, check dependencies, set audit cadences, write config. |
| `/stats` | Skill | Knowledge-base health dashboard — file counts, backlog depth, audit status, codemap dates, tag stats, coverage gaps. |
| `/statusline [on\|off\|status]` | Skill | Install/remove the CLI status-line meter — context-window bar + 5h/7d plan-usage % (Claude Code only). |
| `/help` | Skill | The command reference with per-skill model recommendations. |
| statusline meter | Hook | Renders model · context bar · 5h · 7d usage; persists per-account usage state for threshold alerts. |
| usage-threshold alert | Hook | Inject a usage warning when plan usage crosses `usage_alert_threshold` (default 80; per-account scoped). |

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

*Last reviewed: 2026-06-11 — current as of plugin-claude-code **v2.30.0** / plugin-openai-codex **2.30.0-codex.0** / plugin-claude-cowork v1.2.0 / plugin-antigravity **2.30.0** / plugin-cursor-template **2.30.0-cursor.0**. Sibling ports are parity-aligned for supported runtime surfaces, including `/foundational-review` and `/readiness-audit`; `/statusline` and `/aria-assist` remain explicit non-equivalents on Cursor/Codex.*
