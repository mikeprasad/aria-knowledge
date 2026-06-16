---
description: "Show available aria-knowledge commands. Use when user says '/help', 'aria help', 'what commands are available', 'list commands', 'what can aria do'. (Code port — ADR-094.)"
argument-hint: ""
allowed-tools:
---

# /help — aria-knowledge Commands

Print the command reference table. No config or file access needed.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/help` resolves to this skill — aria-knowledge (Code) is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. The Cowork variant is namespaced-only: `/aria-cowork:help`.

**Before Step 0:** Check that the `Bash` tool is available in this session. If `Bash` is NOT available (you are running in Claude Cowork or another non-Code runtime), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/help` from a non-Code runtime.**
>
> This prints aria-knowledge's command reference (Code-side commands). For aria-cowork's reference, use `/aria-cowork:help`.
>
> **Use `/aria-cowork:help` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `aria-cowork:help` with the same arguments the user provided to this invocation. Do not proceed with this skill's steps; the cowork variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-knowledge) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args.

If `Bash` is available, proceed to Step 0.

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
| /foundational-review <scope-root> [--decision "..."] [--extend] | Foundational review chain before an irreversible decision (freeze/tag/flip/re-scope): verdict + premises + A–F → design spec → cold-executable plan → composed /prospect → kickoff. Requires a named irreversible decision (else redirects). |
| /readiness-audit <scope-root> [--for "<event>"] | Surface readiness audit (sibling of /foundational-review): parallel exploration → controller re-verification of agent claims → tiered evidence-celled findings → phased remediation. Read-only probes; no decision anchor needed. |
| /context [tags] | Load relevant knowledge files by topic (supports AND/OR, project expansion) |
| /index | Rebuild the tag-based knowledge index with cross-references |
| /rules [number] | Look up a working rule by number or keyword |
| /backlog [type] | View and manage pending intake items |
| /stats | Knowledge base health dashboard — file counts, backlogs, audit status |
| /ask [question] | Research a question, check existing knowledge, save answer as a knowledge doc |
| /clip [url or text] | Quick-save a URL or text snippet to intake for later review |
| /intake [path or url] | Bulk import knowledge from files, directories, or URLs |
| /intake doc [url or title] | Capture a single doc with 5-section structured body (claims/keeping/contested/action/reaction) → intake/docs/ |
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
| /index, /stats, /backlog, /rules, /context, /clip, /snapshot, /statusline, /help, /setup | Sonnet (mid-tier), low effort | Mechanical or retrieval-only — higher models add no measurable lift. |

Always pick the latest release within each tier — ARIA pins capability *tiers*, not version numbers, so this guidance survives model updates.

`Fable` (displayed "Fable 5") is the tier above Opus. Its edge is raw capability/judgment, **not** context size — Fable and Opus share the same 1M-token window. Treat it as a step-up only for the most judgment-heavy, high-stakes runs where a wrong or shallow answer is costly (`/extract`, `/audit-knowledge`, `/retrospect` on genuinely hard sessions). It costs ~2× Opus, so reach for it when difficulty — not data volume — justifies the spend; the Opus rows otherwise stand. (Note: the "large-context variant preferred" qualifier on `/codemap create` above is legacy — any current top-tier model, Opus 4.8 included, already carries the 1M window, so full-repo traversal no longer needs a special variant.)

Any model below Sonnet-equivalent capability is not recommended for any ARIA skill — the judgment/cross-reference demands exceed its strengths.

The honest test: will a stronger model change what ends up in the knowledge base? For `/extract` and `/audit-knowledge`, yes, measurably. For `/index` and `/stats`, no.
```
