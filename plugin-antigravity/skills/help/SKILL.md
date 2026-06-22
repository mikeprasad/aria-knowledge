---
description: "Show available aria-knowledge commands. Use when user says '/help', 'aria help', 'what commands are available', 'list commands', 'what can aria do'. (Code port — ADR-094.)"
---

# /help — aria-knowledge Commands

Print the command reference table. No config or file access needed.

## Output

```
## aria-knowledge Commands

| Command | Description |
|---------|-------------|
| /setup | Configure knowledge folder, audit cadences, and plugin settings |
| /extract | Capture insights, decisions, and feedback from the current conversation |
| /audit-knowledge (alias: /knowledge-audit) | Review backlogs, promote to knowledge files, rebuild index |
| /audit-config (alias: /config-audit) | Check project configs and docs for drift and broken references |
| /audit-share | Promote personal knowledge to the team-shared `_project-knowledge/` tier |
| /prospect [plan/session/todos/file/linear/branch] | Forward-looking pre-mortem on a plan before any code — per-step risk verdicts (PROCEED/SHRINK/SPLIT/DEFER/KILL), evidence-sourcing pass, simpler-alternative discipline |
| /retrospect [--range/--pr/--session/--commit] | Structured retrospective on a shipped commit range — per-fix validation, simpler-alternative discipline, re-diagnosis, action verdicts, failure-mode pattern check |
| /recap [arc\|commit\|push\|pull] | Read-only orientation — a scannable What/Where/Status table of recent work (this session by default; or the last arc/commit/push/pull). Summarizes, never validates; writes nothing |
| /foundational-review <scope-root> [--decision "..."] [--extend] | Foundational review chain before an irreversible decision (freeze/tag/flip/re-scope): verdict + premises + A–F → design spec → cold-executable plan → composed /prospect → kickoff. Requires a named irreversible decision (else redirects). |
| /readiness-audit <scope-root> [--for "<event>"] | Surface readiness audit (sibling of /foundational-review): parallel exploration → controller re-verification of agent claims → tiered evidence-celled findings → phased remediation. Read-only probes; no decision anchor needed. |
| /context [tags] | Load relevant knowledge files by topic (supports AND/OR, project expansion) |
| /index | Rebuild the tag-based knowledge index with cross-references |
| /rules [number] | Look up a working rule by number or keyword |
| /backlog [type] | View and manage pending intake items |
| /stats | Knowledge base health dashboard — file counts, backlogs, audit status |
| /ask [question] | Research a question, check existing knowledge, save answer as a knowledge doc |
| /intake [url or text] | Clip a single URL/snippet whole → intake/clippings/ (reviewed at next /audit-knowledge) |
| /intake [path or dir or glob] | Bulk import knowledge from files, directories, or globs into the backlogs |
| /intake extract [source] | Decompose a source (URL/file/doc via ~~docs MCP) into backlog entries |
| /intake doc [url or title] | Capture a single doc with 5-section structured body (claims/keeping/contested/action/reaction) → intake/docs/ |
| /intake thread [id] | Pull a chat/email thread via ~~chat/~~email MCP → intake/clippings/ |
| /interview <mode> | Elicit knowledge via dialogue (project / knowledge / deep-dive); chooses cadence in-session; stages to intake/ for manual review |
| /codemap [mode] | Feature-organized CODEMAP.md for any codebase (create/inventory/update/section) |
| /distill [text or path] | Tiered task spec from raw text; optional --group for CODEMAP-loaded context |
| /stitch <mode> <group> | Cross-repo binding (auth/endpoints/entities/drift) for a product group |
| /wrapup [auto\|snap] | End-of-session close-out — update PROGRESS/CLAUDE.md, prompt for commit, verify continuity. `auto` runs silently; `snap` runs like auto but archives the transcript via /snapshot for later extraction instead of /extract (use when context is high) |
| /handoff [auto\|brief\|snap] | Express handoff — same coverage as /wrapup, one combined-go review (or `auto` for silent), always emits a paste-ready next-session opener. `brief` mode produces a copy/paste coworker brief (Hey [coworker]-style prose, 80-150 words) instead of next-session opener — no PROGRESS/CLAUDE/memory/commit/extract side effects. `snap` mode runs like auto but archives the transcript via /snapshot for later extraction instead of /extract (use when context is high) |
| /snapshot | Save the current session transcript to intake/pre-compact-captures/ on demand |
| /statusline [on\|off\|status] | Install/remove the CLI status-line meter — context-window bar + 5h/7d plan-usage % (Claude Code only) |
| /help | This command reference |

Run /setup to configure. See QUICKSTART.md for a walkthrough of your first 3 sessions.

## Model Recommendations

These are recommendations only — ARIA does not force a model. Switch per session via `/model` based on the skill you're about to run.

| Skill | Recommended Model | Why |
|-------|-------------------|-----|
| /extract | Highest-capability Opus, medium-to-high effort | Judgment-heavy: distinguishing reusable signal from ephemeral noise, writing non-obvious Why/How-to-apply lines. |
| /audit-knowledge | Highest-capability Opus, medium-to-high effort | Cross-references backlogs against the promoted index, decides promotion vs. discard, detects emerging themes. |
| /audit-config | Highest-capability Opus, medium-to-high effort | Reads across CLAUDE.md files and configs to detect drift and broken references. |
| /retrospect | Highest-capability Opus, medium-to-high effort | Multi-stage judgment per fix: validation status assignment, simpler-alternative identification, hypothesis generation, failure-mode pattern matching, action verdict synthesis. Highest leverage from stronger models. |
| /foundational-review, /readiness-audit | Highest-ceiling available (Fable at extreme stakes, else Opus), xhigh effort | The reviewer model is spent on alternatives-steelmanning, portfolio/product judgment, and the irreversibility inventory; semi-agentic read-trace-reason loop benefits from xhigh. Executor tasks the chain emits route to Opus by default. |
| /ask | Highest-capability Opus, medium-to-high effort (ambiguous topics) or Sonnet (mid-tier) for scoped lookups | Research + draft + categorize. Drop to Sonnet when the question is narrow. |
| /interview | Highest-capability Opus for deep-dive/battery (ambiguous, evidence-cited, leverage-clustered question generation) or Sonnet (mid-tier) for focused socratic project/knowledge runs | The deep-dive battery cadence is judgment-heavy (cite evidence, cluster by leverage, hunt negative space); focused socratic elicitation is lighter. Spans tiers like /ask. |
| /codemap create | Highest-capability Opus (large-context variant preferred) | Full-repo traversal benefits from a large context window so sections aren't truncated mid-generation. |
| /codemap update, /codemap section, /wrapup, /handoff, /intake, /distill, /stitch | Sonnet (mid-tier), medium effort | Structured work with clear prescribed output. |
| /index, /stats, /backlog, /rules, /context, /intake, /snapshot, /statusline, /help, /setup | Sonnet (mid-tier), low effort | Mechanical or retrieval-only — higher models add no measurable lift. |

Always pick the latest release within each tier — ARIA pins capability *tiers*, not version numbers, so this guidance survives model updates.

`Fable` (displayed "Fable 5") is the tier above Opus. Its edge is raw capability/judgment, **not** context size — Fable and Opus share the same 1M-token window. Treat it as a step-up only for the most judgment-heavy, high-stakes runs where a wrong or shallow answer is costly (`/extract`, `/audit-knowledge`, `/retrospect` on genuinely hard sessions). It costs ~2× Opus, so reach for it when difficulty — not data volume — justifies the spend; the Opus rows otherwise stand. (Note: the "large-context variant preferred" qualifier on `/codemap create` above is legacy — any current top-tier model, Opus 4.8 included, already carries the 1M window, so full-repo traversal no longer needs a special variant.)

Any model below Sonnet-equivalent capability is not recommended for any ARIA skill — the judgment/cross-reference demands exceed its strengths.

The honest test: will a stronger model change what ends up in the knowledge base? For `/extract` and `/audit-knowledge`, yes, measurably. For `/index` and `/stats`, no.
```
