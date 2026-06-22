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
| /audit-share | Promote personal knowledge to the team-shared `_project-knowledge/` tier |
| /prospect [plan/session/todos/file/branch] | Forward-looking pre-mortem before execution — risk verdicts, evidence sourcing, simpler-alternative discipline |
| /retrospect [range/commit/session] | Structured retrospective on shipped work — per-fix validation, simpler-alternative discipline, re-diagnosis, action verdicts |
| /recap [arc\|commit\|push\|pull] | Read-only orientation — a scannable What/Where/Status table of recent work. Summarizes, never validates, writes nothing |
| /readiness-audit <scope-root> --for "<event>" | Readiness audit for release, public flip, handover, or other ship-readiness events; verifies every finding with evidence and phases remediation |
| /foundational-review <scope-root> --decision "<decision>" | Foundational review before an irreversible decision; produces verdict, premises, irreversibility inventory, specs, prospect-hardened plans, and kickoff |
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
| /wrapup [auto\|snap] | End-of-session close-out — update PROGRESS/AGENTS/CLAUDE docs, prompt for commit, verify continuity. `snap` archives the transcript via /snapshot for later extraction instead of /extract |
| /handoff [auto\|brief\|snap] | Express handoff — same coverage as /wrapup, always emits a paste-ready next-session opener. `brief` produces a coworker brief; `snap` archives the transcript via /snapshot |
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
| /interview | Highest-capability Codex model for deep-dive/battery interviews; current default Codex model for focused socratic project/knowledge runs | Deep dives require evidence-cited, leverage-clustered question generation; focused elicitation is lighter. |
| /codemap create | Highest-capability Codex model, high effort | Full-repo traversal needs sustained context and synthesis so sections aren't truncated mid-generation. |
| /codemap update, /codemap section, /wrapup, /handoff, /intake, /distill, /stitch | Current default Codex model, medium effort | Structured work with clear prescribed output. |
| /index, /stats, /backlog, /rules, /context, /recap, /snapshot, /help, /setup | Current default Codex model, low effort | Mechanical or retrieval-only — higher effort usually adds no measurable lift. |

Use a fast/light model only for trivial lookups, status checks, and purely mechanical reference output.

The honest test: will a stronger model change what ends up in the knowledge base? For `/extract` and `/audit-knowledge`, yes, measurably. For `/index` and `/stats`, no.
```
