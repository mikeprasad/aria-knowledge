---
name: help
description: "Show the ARIA command reference and model guidance for this Codex port. Trigger on /help, aria help, what commands are available, or what can ARIA do."
argument-hint: ""
allowed-tools:
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
| /retrospect [<scope>] [<scope-arg>] | Structured retrospective on a commit, range, PR, release, deployment, or session — per-fix validation, simpler-alternative discipline, re-diagnosis, action verdicts, failure-mode pattern check |
| /prospect [<scope>] [<scope-arg>] | Structured pre-mortem on a plan, task, branch, file, ticket, or session before execution |
| /readiness-audit <scope-root> --for "<event>" | Readiness audit for release, public flip, handover, or other ship-readiness events; verifies every finding with evidence and phases remediation |
| /foundational-review <scope-root> --decision "<decision>" | Foundational review before an irreversible decision; produces verdict, premises, irreversibility inventory, specs, prospect-hardened plans, and kickoff |
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
| /wrapup | End-of-session close-out — update PROGRESS/AGENTS/CLAUDE docs, prompt for commit, verify continuity |
| /handoff [auto\|brief] | Express handoff — same coverage as /wrapup, one combined-go review (or `auto` for silent), always emits a paste-ready next-session opener. `brief` mode produces a copy/paste coworker brief (Hey [coworker]-style prose, 80-150 words) instead of next-session opener — no PROGRESS/CLAUDE/memory/commit/extract side effects |
| /snapshot | Save the current session transcript to intake/pre-compact-captures/ on demand |
| /help | This command reference |

Run /setup to configure. See QUICKSTART.md for a walkthrough of your first 3 sessions.

## Model Recommendations

These are recommendations only — ARIA does not force a model. In Codex, choose the model and reasoning effort for the session based on the skill you're about to run.

| Skill | Recommended Codex posture | Why |
|-------|-------------------|-----|
| /extract | Highest-capability Codex model, medium-to-high effort | Judgment-heavy: distinguishing reusable signal from ephemeral noise, writing non-obvious Why/How-to-apply lines. |
| /audit-knowledge | Highest-capability Codex model, high effort | Cross-references backlogs against the promoted index, decides promotion vs. discard, detects emerging themes. |
| /audit-config | Highest-capability Codex model, medium-to-high effort | Reads across AGENTS/CLAUDE docs and configs to detect drift and broken references. |
| /prospect, /retrospect, /readiness-audit, /foundational-review | Highest-capability Codex model, high or xhigh effort | Multi-stage judgment: validation status assignment, simpler-alternative identification, hypothesis generation, failure-mode pattern matching, action verdict synthesis, and decision-quality review. |
| /ask | Highest-capability Codex model, medium-to-high effort for ambiguous topics; current default Codex model for scoped lookups | Research + draft + categorize. Drop effort when the question is narrow. |
| /codemap create | Highest-capability Codex model, high effort | Full-repo traversal needs sustained context and synthesis so sections aren't truncated mid-generation. |
| /codemap update, /codemap section, /wrapup, /handoff, /intake, /distill, /stitch | Current default Codex model, medium effort | Structured work with clear prescribed output. |
| /index, /stats, /backlog, /rules, /context, /clip, /snapshot, /help, /setup | Current default Codex model, low effort | Mechanical or retrieval-only — higher effort usually adds no measurable lift. |

Use a fast/light model only for trivial lookups, status checks, and purely mechanical reference output.

The honest test: will a stronger model change what ends up in the knowledge base? For `/extract` and `/audit-knowledge`, yes, measurably. For `/index` and `/stats`, no.
```
