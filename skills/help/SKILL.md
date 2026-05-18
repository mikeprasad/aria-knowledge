---
name: help
description: >
  Show available aria-cowork commands. Use when user says "/help", "/aria-cowork:help", "aria help", "what commands are available", "list commands", "what can aria-cowork do".
---

# /help — aria-cowork Commands

Print the command reference. No config or file access needed.

## Output

```markdown
## aria-cowork Commands (v0.3.0)

| Command | Description |
|---------|-------------|
| /aria-setup | First-run scaffold: attach folder, write aria-config.md, seed structure (now with access probe, alias validation, advanced-options, self-validation audit) |
| /help | This command reference |
| /clip [url or text] | Quick-save a URL or text snippet to intake for later review |
| /intake [path or url] | Bulk import knowledge from files, URLs, or pasted content |
| /ask [question] | Research a question, check existing knowledge, save answer as a knowledge doc |
| /context [tags] | Load relevant knowledge files by topic (supports AND/OR, alias resolution, semantic-hint matching) |
| /index | Rebuild the tag-based knowledge index with aliases + semantic hints + cross-references |
| /stats | Knowledge base health: file counts, backlog depth, audit dates, semantic-hints coverage |
| /rules [number] | Look up a working rule by number or keyword (auto-discovers matching `## Rule N` examples from user-examples.md) |
| /backlog [type] | View and manage pending intake items (insights, decisions, rules); /backlog clear archives-then-removes per audit-cohort conventions |
| **/extract** | Capture insights, decisions, feedback, project context, references, and ideas from the current conversation |
| **/snapshot** | Save a snapshot of the current Cowork conversation to intake/pre-compact-captures/ (3-path source: MCP / user-paste / Claude-recall fallback) |
| **/wrapup** | End-of-session handoff: review work, update PROGRESS/CLAUDE/memory, generate commit message, prompt /extract |
| **/audit-knowledge** (alias: **/knowledge-audit**) | Review intake backlogs, route ideas via Accept submenu, archive cleared content per audit-cohort conventions, rebuild index |
| **/audit-config** (alias: **/config-audit**) | Check the knowledge folder for drift, broken references, version-stamp ripple, adoption-state cascade, and missing config fields |
| **/intake doc [url or title]** | Capture a single doc with 5-section structured body (claims/keeping/contested/action/reaction) → intake/docs/ (v2.17.0 doc mode) |
| **/handoff [auto\|brief]** | Express handoff with three modes — combined-go default, silent auto, copy/paste coworker brief (`brief` mode is parity with aria-knowledge v2.17.0) |
| **/prospect [scope] [arg]** | Forward-looking pre-mortem on a plan before execution. Per-step risk enforcement, Evidence-Sourcing Pass, action verdicts. Scopes: plan / session / todos / file / linear / branch |
| **/retrospect [scope] [arg]** | Retrospective on shipped work. Per-fix validation, Evidence-Sourcing Pass, simpler-alternative discipline. Scopes: session / decision (native) / commit / range / pr / release / deployment (cowork uses user-paste fallback for git-bound scopes) |

**Bold rows = new in v0.3.0** (parity with aria-knowledge v2.14.1+ / v2.15.0+ / v2.16.0+ / v2.17.0).

## Companion: aria-knowledge in Claude Code

aria-cowork shares its knowledge folder with aria-knowledge in Code. If you also use Code, install aria-knowledge there too — both plugins read and write the same files (per `aria-config.md` at your knowledge folder root). Cross-plugin parity is byte-identical for output schemas (PROGRESS.md entries, audit-cohort archives, intake backlogs); input-discovery paths differ where Cowork's persistent-grant model can't reach surfaces aria-knowledge can (e.g., `~/.claude/projects/.../memory/`, `~/.claude/plans/`).

See `template/TEMPLATE-PARITY.md` for the shared-template registry + sync status.

## What's coming (future releases)

**Cowork-native skills (planned):**

| Command | Description |
|---------|-------------|
| /digest | Cross-tool weekly rollup (chat + email + tracker + docs → intake/digests/) |
| /clip-thread | Capture a Slack/Teams/email thread to intake |
| /extract-doc | Pull insights from a Notion/Google Doc/Confluence page |
| /sync-decisions | Mirror approved decisions out to your team docs/wiki |
| /meeting-notes | Fold a meeting transcript into intake |
| /daily-audit | First-message audit substitute (covers what aria-knowledge's SessionStart hook does in Code) |

These six skills are Cowork-specific (they leverage Cowork's conversational + multi-tool MCP context in ways aria-knowledge doesn't need). They land in a post-v0.3.0 release once MCP integrations are wired (`.mcp.json` + `CONNECTORS.md`).

## Code-only skills (NOT in aria-cowork — use aria-knowledge in Code)

`/codemap`, `/stitch`, `/distill`, `/audit-share`, `/share-audit` — these depend on git, repos, and layered code architecture. They live in aria-knowledge for Code. Per [ADR-005](#).

## Roadmap

Spec, ADRs, and validation history live in your knowledge folder at `projects/aria-cowork/`:

- `OVERVIEW.md` — full design
- `decisions/001-008-*.md` — 8 architectural decisions
- `VALIDATION.md` — Cowork environment validation results

Run `/aria-cowork:context aria-cowork` to load the spec by tag once it's promoted in your knowledge index.
```

## Notes for the agent

- Output the markdown block above verbatim. Do not summarize or rewrite.
- This is a static reference; no file reads, no MCP calls, no decision-making.
- If the user asks about a deferred command (e.g., "/digest"), point them at the v0.3.0 line and offer to file it as a feature request in `intake/ideas/`.
