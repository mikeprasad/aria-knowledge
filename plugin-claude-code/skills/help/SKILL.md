---
description: "**Bare-slash canonical (Claude Code).** `/help` resolves to this skill (aria-knowledge's command reference) when both aria-knowledge and aria-cowork are loaded in the same session. RUNTIME GATE: if invoked from a non-Code runtime (no Bash tool available, e.g., Claude Cowork), surface a notification suggesting `/aria-cowork:help` (aria-cowork's command reference) and require explicit user confirmation — even in `auto` mode (ADR-094 §Part 3). Show available aria-knowledge commands. Use when user says '/help', 'aria help', 'what commands are available', 'list commands', 'what can aria do'."
argument-hint: ""
allowed-tools:
---

# /help — aria-knowledge Commands

Print the command reference table. No config or file access needed.

## Runtime Gate (per ADR-094)

**Before printing:** Check that `Bash` is available. If `Bash` is NOT available (e.g., Cowork), surface:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/help` from a non-Code runtime.**
>
> This prints aria-knowledge's command reference (Code-side commands). For aria-cowork's reference, use `/aria-cowork:help`.
>
> Proceed and show aria-knowledge's commands anyway? (`y` / `n`)

Wait for `y` / `yes`. **Gate applies even in `auto`** (ADR-094 §Part 3). If `Bash` is available, proceed to Output.

## Output

```
## aria-knowledge Commands

| Command | Description |
|---------|-------------|
| /setup | Configure knowledge folder, audit cadences, and plugin settings |
| /extract | Capture insights, decisions, and feedback from the current conversation |
| /audit-knowledge (alias: /knowledge-audit) | Review backlogs, promote to knowledge files, rebuild index |
| /audit-config (alias: /config-audit) | Check project configs and docs for drift and broken references |
| /retrospect [--range/--pr/--session/--commit] | Structured retrospective on a shipped commit range — per-fix validation, simpler-alternative discipline, re-diagnosis, action verdicts, failure-mode pattern check |
| /context [tags] | Load relevant knowledge files by topic (supports AND/OR, project expansion) |
| /index | Rebuild the tag-based knowledge index with cross-references |
| /rules [number] | Look up a working rule by number or keyword |
| /backlog [type] | View and manage pending intake items |
| /stats | Knowledge base health dashboard — file counts, backlogs, audit status |
| /ask [question] | Research a question, check existing knowledge, save answer as a knowledge doc |
| /clip [url or text] | Quick-save a URL or text snippet to intake for later review |
| /intake [path or url] | Bulk import knowledge from files, directories, or URLs |
| /intake doc [url or title] | Capture a single doc with 5-section structured body (claims/keeping/contested/action/reaction) → intake/docs/ |
| /codemap [mode] | Feature-organized CODEMAP.md for any codebase (create/inventory/update/section) |
| /distill [text or path] | Tiered task spec from raw text; optional --group for CODEMAP-loaded context |
| /stitch <mode> <group> | Cross-repo binding (auth/endpoints/entities/drift) for a product group |
| /wrapup | End-of-session handoff — update PROGRESS/CLAUDE.md, prompt for commit, verify continuity |
| /handoff [auto\|brief] | Express handoff — same coverage as /wrapup, one combined-go review (or `auto` for silent), always emits a paste-ready next-session opener. `brief` mode produces a copy/paste coworker brief (Hey [coworker]-style prose, 80-150 words) instead of next-session opener — no PROGRESS/CLAUDE/memory/commit/extract side effects |
| /snapshot | Save the current session transcript to intake/pre-compact-captures/ on demand |
| /help | This command reference |

Run /setup to configure. See QUICKSTART.md for a walkthrough of your first 3 sessions.

## Model Recommendations

These are recommendations only — ARIA does not force a model. Switch per session via `/model` based on the skill you're about to run.

| Skill | Recommended Model | Why |
|-------|-------------------|-----|
| /extract | Opus 4.6 (1M context), medium-to-high effort | Judgment-heavy: distinguishing reusable signal from ephemeral noise, writing non-obvious Why/How-to-apply lines. |
| /audit-knowledge | Opus 4.6 (1M context), medium-to-high effort | Cross-references backlogs against the promoted index, decides promotion vs. discard, detects emerging themes. |
| /audit-config | Opus 4.6 (1M context), medium-to-high effort | Reads across CLAUDE.md files and configs to detect drift and broken references. |
| /retrospect | Opus 4.6 (1M context), medium-to-high effort | Multi-stage judgment per fix: validation status assignment, simpler-alternative identification, hypothesis generation, failure-mode pattern matching, action verdict synthesis. Highest leverage from stronger models. |
| /ask | Opus 4.6 (1M context), medium-to-high effort (ambiguous topics) or Sonnet 4.6 (scoped lookups) | Research + draft + categorize. Drop to Sonnet when the question is narrow. |
| /codemap create | Opus 4.6 (1M context) minimum | Full-repo traversal needs the large context window so sections aren't truncated mid-generation. |
| /codemap update, /codemap section, /wrapup, /handoff, /intake, /distill, /stitch | Sonnet 4.6, medium effort | Structured work with clear prescribed output. |
| /index, /stats, /backlog, /rules, /context, /clip, /snapshot, /help, /setup | Sonnet 4.6, low effort | Mechanical or retrieval-only — higher models add no measurable lift. |

Haiku is not recommended for any ARIA skill — the judgment/cross-reference demands exceed its strengths.

The honest test: will a stronger model change what ends up in the knowledge base? For `/extract` and `/audit-knowledge`, yes, measurably. For `/index` and `/stats`, no.
```
