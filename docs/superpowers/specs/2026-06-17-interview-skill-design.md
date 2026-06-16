# `/interview` Skill — Design Spec

**Date:** 2026-06-17
**Status:** Approved (brainstorming), pending implementation plan
**Author:** Mike + Claude (Opus 4.8)
**Repo:** `aria-knowledge` (the ARIA Claude Code plugin)
**Scope:** v1 — Claude Code canonical port only (`plugin-claude-code/`)

---

## 1. Summary

`/interview` is a new canonical skill that **elicits** knowledge through dialogue, rather than **harvesting** it from existing sources. It sits *upstream* of the existing intake family (`/extract`, `/intake`, `/clip`, `/meeting-notes`), which are all pull-based (they read a conversation, file, or URL). `/interview` is push-based: it interviews the user, and the answers *become* the knowledge — modeled on the `grill-with-docs` / `deep-interview` prior art and, more directly, on the 2026-05-01 Designframe strategic deep-dive session (`df/docs/session-transcript-2026-05-01-strategic-deep-dive.md`) that the user flagged as the gold standard.

The skill writes structured markdown into the `intake/` tree (exactly like `/meeting-notes`); it **never auto-promotes**. **Review path (verified 2026-06-17):** `/audit-knowledge` scans a *fixed* set — the four named backlog files + `intake/ideas/` — and does NOT glob `intake/` subfolders (it doesn't sweep `intake/meetings/` or `intake/docs/` either). So `/interview` output is **manually reviewed staged material** (the `/meeting-notes` model): the user promotes it later by hand or via `/extract`. It is not auto-swept. The skill's single job: get what's in the user's head (and in their artifacts) onto disk as reviewable raw material.

## 2. Placement in the knowledge family

```
ELICIT (new)          HARVEST (existing)              PROMOTE (existing)
/interview  ──stages──▶  intake/ tree  ◀──stages── /extract /intake /clip /meeting-notes
                              │
                              └──reviewed/promoted at──▶ /audit-knowledge ──▶ insights/ decisions/ approaches/ rules/
```

**Why one skill, not several:** "interview" is the umbrella term all cited prior art uses, so it wins skill-dispatch cleanly (ADR-092: descriptions are the dispatch mechanism). The three modes share one engine and one output mechanism, diverging only in question framing and target subfolder. A split (`/grill` + `/kickoff`) would fragment the trigger vocabulary and put two items on the skill-discovery surface the project has been actively trimming (v2.30.1).

**aria-core:** Out of v1 scope. Because output is "write a structured markdown file into `intake/`," any aria-core sync is a *downstream* concern owned by whatever already syncs `intake/` → Core (or `/sync-decisions`). The interview skill does not touch the `core.*` MCP. Documented as a possible later follow-on.

## 3. The three modes

Invoked as `/interview <mode>`. Same engine, distinct question bank + framing + target subfolder.

| Mode | Reach for it when… | Framing | Stages to |
|---|---|---|---|
| **`project`** | Starting/scoping a new project or build | *Forward-looking* — interrogates a thing that doesn't exist yet | `intake/projects/{YYYY-MM-DD}-{slug}.md` |
| **`knowledge`** | Getting a topic out of your head into the KB | *Topical* — a focused subject you hold a position on | `intake/interviews/{YYYY-MM-DD}-{slug}.md` |
| **`deep-dive`** | Comprehensively extracting an *existing-but-undocumented* system you built | *Archaeological* — reverse-engineers rationale behind something already built | `intake/interviews/{YYYY-MM-DD}-{slug}.md` |

**`deep-dive` signature moves** (from the DF transcript): cluster questions by leverage (highest-impact first), tie every question to observed evidence, and explicitly hunt **negative space** ("what was considered and deliberately NOT built?").

## 4. Grounding (`--ground`)

`/interview <mode> [--ground=<artifacts>]` — optional input pointing the skill at a basis to read *before* asking, so questions can cite evidence. Basis can be: source code / a directory / a glob, a design doc / plan / spec, a project folder (reads its CLAUDE.md + structure), a data file (e.g. the DF `.xlsx`), or a URL (via WebFetch).

| Mode | Grounding | If no `--ground` |
|---|---|---|
| `project` | Optional | Proceeds (project doesn't exist yet) |
| `knowledge` | Optional | Proceeds (pure elicitation, or grounds if pointed) |
| **`deep-dive`** | **Required** | **GATE: stops and asks "deep-dive needs a basis to review. Point me at code, docs, a plan, a project, data, or a URL." Does not proceed to questions until it has one.** |

The required-basis gate is what *gives deep-dive its identity* — without an artifact to anchor on, it degenerates into `knowledge` mode.

## 5. Cadence (asked in-session)

Cadence is **asked at the start of every interview**, after mode + grounding resolve — never a command flag (keeps the command surface minimal per ADR-092).

| Cadence | How it runs | Best for |
|---|---|---|
| **`socratic`** | One question at a time; next adapts to the last answer; live convergence | Focused topics; thinking *with* the AI; answers not yet known |
| **`battery`** | Researches + thinks, then presents a full **clustered, leverage-ordered, numbered** question set at once (the DF pattern); answered async in prose | Comprehensive extraction; knowledge already held; deep-dives |

**Auto-recommend with override** (decide-and-surface-the-fork): `deep-dive` → battery; `project`/`knowledge` with grounding or a broad topic → battery; focused + ungrounded → socratic. The skill states the recommendation in one line and accepts an override.

## 6. The shared loop

```
1. Resolve config: knowledge_folder from ~/.claude/aria-knowledge.local.md; if absent → stop "run /setup".
2. Resolve mode + slug. If deep-dive and no basis → GATE: ask what to review.
3. Ingest grounding artifacts if any (Read/Glob/Grep/WebFetch).
4. Ask cadence (recommend + accept override).
5. INTERVIEW:
     battery  → derive clustered, evidence-cited question set → present all → collect prose answers
     socratic → ask one Q → adapt → repeat, maintaining a running COVERAGE LEDGER
6. Converge (HYBRID stop): checklist floor + adaptive probing + "done" escape hatch.
     Surface running coverage: "Covered: X, Y. Still thin: Z. Say 'done' to stop early."
7. Assemble the staged file draft.
8. CONFIRM-BEFORE-WRITE: show the assembled draft, get y/n.
9. Write to intake/<subfolder>/{date}-{slug}.md (lazy-create subfolder). Report the path.
```

The **coverage ledger** (socratic) is one mechanism doing three jobs: the convergence signal, the escape-hatch prompt, and the skeleton of the staged file. In battery, the clustered question set plays the same role implicitly. Both cadences converge on the same staged-file shape.

## 7. Staged output file

New subfolders `intake/projects/` and `intake/interviews/`, lazy-created on first use (the `/meeting-notes` → `intake/meetings/` pattern). Structured markdown + frontmatter so `/audit-knowledge` can review and promote.

**Common frontmatter:**
```yaml
---
type: interview
mode: project | knowledge | deep-dive
cadence: socratic | battery
date: YYYY-MM-DD
slug: <kebab-topic>
grounding:            # artifacts ingested, if any (deep-dive always has ≥1)
  - df-input.css
  - docs/grid-calculator-v1.4.xlsx
status: staged        # not yet promoted; reviewed at /audit-knowledge
---
```

**Body — `project`:**
```
# Project Intake: <name>
## Problem & motivation
## Users / who it's for
## Scope — in
## Scope — explicitly out
## Constraints (technical, time, dependency)
## Stack / approach leanings
## Success criteria
## Risks & open questions
```

**Body — `knowledge`:**
```
# <topic>
## Claim / position
## Basis & evidence
## Confidence (firm / working / speculative)
## Contested points & counter-views
## Connections to existing knowledge   ← [[links]] to KB files where known
## What would change my mind
```

**Body — `deep-dive`** (mirrors the DF session structure):
```
# Deep-Dive: <system>
## Grounding reviewed            ← what was ingested + key observations
## Q&A by leverage cluster       ← clustered questions + answers, highest-impact first (Q AND A preserved)
## Load-bearing invariants       ← immovable vs revisable
## Negative space                ← considered and deliberately NOT built
## What would force a rebuild
## Open threads
```

`deep-dive` preserves **questions alongside answers** — the evidence-cited questions are themselves a re-runnable audit of the system, not throwaway scaffolding (decision-trail-preservation applied to elicitation).

## 8. File layout & conventions

```
plugin-claude-code/skills/interview/
├── SKILL.md                  # frontmatter + 9-step loop + mode/cadence routing (the mechanism)
└── question-banks.md         # the three mode question banks + deep-dive clustering method (the content)
```

Split rationale: SKILL.md owns mechanism; question banks are content that will grow. Same pattern as `/intake` and `/distill` referencing external schema/template files.

**Conventions (verified against existing skills):**
- **Config:** read `~/.claude/aria-knowledge.local.md` → `knowledge_folder`; absent → stop "run /setup" (`/meeting-notes` pattern).
- **Runtime:** Code-canonical skill. v1 is Code-only → no Cowork-redirect block yet (documented as a port follow-on).
- **`allowed-tools`:** `Read, Glob, Grep, Write, Edit, WebFetch, Bash` (matches `/intake`).
- **Lazy subfolder creation** on first write.
- **Description discipline (ADR-092):** one tight description owning "interview" + the three mode words + cited triggers ("grill me", "deep dive", "interview me about", "scope this project").
- **Registration:** add `/interview` wherever the plugin enumerates skills (help listing + any marketplace/README skill table — located during implementation).

## 9. Testing — dogfood validation

Prompt-skill (markdown), so validation = exercising each branch once with real inputs and reading staged output:
- `project` (socratic, no grounding) → stages a project file.
- `knowledge` (battery) → produces clustered output.
- `deep-dive` grounded on a real artifact (e.g. the DF spreadsheet or a small doc) → produces evidence-cited clustered questions.
- **Highest-value single test — the deep-dive gate:** invoke `/interview deep-dive` with **no** `--ground` and confirm it *refuses to proceed* and asks for a basis. That gate is the mode's whole identity; a prompt that only "mostly" enforces it is the classic prompt-skill regression.

## 10. Out of scope (v1)

- Codex / Cursor / Antigravity ports (follow-on; repo has a clean port-replication mechanism).
- aria-core (`core.*`) write target (downstream of `intake/` staging).
- Auto-promotion to `insights/` / `decisions/` / `approaches/` (owned by `/audit-knowledge`).
- A `--cadence` command flag (cadence is in-session by design).
- Turn-by-turn ↔ battery mid-session switching (pick once at start).
