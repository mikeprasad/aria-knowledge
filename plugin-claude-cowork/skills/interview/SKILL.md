---
description: "ELICIT knowledge by interviewing the user, then stage to intake/ for manual review (elicit-side counterpart to /extract /intake /clip). Modes: 'project' (scope a build), 'knowledge' (a topic into the KB), 'deep-dive' (rationale behind something you built — needs a basis). Use when user says '/interview', 'interview me about X', 'grill me on X', 'deep dive on X', 'scope this project'. (Cowork variant — namespaced-only.)"
argument-hint: "<project|knowledge|deep-dive> [topic] [--ground=<path|glob|url>[,...]]"
allowed-tools: Read, Glob, Grep, Write, Edit, WebFetch
---

# /interview — Elicit Knowledge Through Dialogue

Interview the user to draw out knowledge that lives in their head (and in their artifacts), then stage it as structured markdown in the `intake/` tree. Unlike `/extract` (reads the current conversation), `/intake` (scans files/URLs), or `/clip` (saves a snippet), `/interview` *asks questions* — the answers become the knowledge. Output is staged for **manual review** (the `/meeting-notes` model), never auto-promoted.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Cowork variant — namespaced-only. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session, bare `/interview` resolves to aria-knowledge's variant — Code is the canonical owner of all dual-port skills per ADR-094 §Part 1. To reach this skill, use the namespaced form: `/aria-cowork:interview`. Do NOT match bare `/interview` — that belongs to aria-knowledge.

**Before Step 0:** Check whether the `Bash` tool is available in this session. If `Bash` IS available (you are running in Claude Code or another runtime with shell access), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-cowork's `/interview` from a runtime with shell access.**
>
> This variant runs conversationally and resolves your knowledge folder by reading the config file directly (no Bash). For the Code-native variant, use `/interview` (the aria-knowledge canonical).
>
> **Use `/interview` instead?** (`y` / `n`)

- **`y` / `yes`** — Use the `Skill` tool to invoke `interview` (the bare-slash canonical) with the same arguments. Do not proceed here; the aria-knowledge variant takes over. This is the default-yes path.
- **`n` / `no`** — Proceed with this (aria-cowork) variant anyway. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. If `Bash` is NOT available (normal Cowork runtime), proceed to Step 0.

## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md` with the `Read` tool and extract `knowledge_folder`. If the file is not reachable in this runtime (Cowork's attached-folder sandbox may not expose `~/.claude/`), do NOT stop — ask the user: "I can't reach your aria-knowledge config from here. Paste your knowledge-folder path (e.g. `~/Projects/knowledge`) and I'll use it for this session." Use the pasted path. If the user has never run `/setup`, point them there first.

## Step 1: Resolve Mode, Topic, Grounding

Parse arguments: first positional = **mode** (`project` | `knowledge` | `deep-dive`). Remaining text = **topic**. `--ground=<path|glob|url>[,...]` = optional grounding artifacts.

If no mode given, ask: "Which interview — `project` (scope a new build), `knowledge` (get a topic into the KB), or `deep-dive` (extract rationale behind something you already built)?"

**Derive the slug** from the topic (kebab-case, ≤6 words). If no topic yet, ask for a one-line subject.

### GATE — deep-dive requires a basis (explicit early-return)

**If mode is `deep-dive` AND no `--ground` was provided AND no basis is named in the topic:**

> STOP. Do not ask any interview questions. Emit:
>
> "`deep-dive` extracts the rationale behind something that already exists, so it needs a basis to review and build questions around. Point me at what to study — source code, a directory, a design doc / plan / spec, a project folder, a data file (e.g. a spreadsheet), or a URL."
>
> Wait for the user to supply a basis. Re-enter this gate with their answer. Do NOT proceed to Step 2 until `deep-dive` has at least one grounding artifact.

For `project` and `knowledge`, grounding is optional — proceed to Step 2 regardless.

## Step 2: Ingest Grounding (if any)

For each grounding artifact: file/dir/glob → Read/Glob/Grep; URL → WebFetch; project folder → read its CLAUDE.md + top-level structure; data file → read/parse. Record key observations — these become the evidence you cite in questions. (`deep-dive` always has ≥1; `project`/`knowledge` may have none.)

## Step 3: Choose Cadence (in-session)

Recommend a cadence in one line, then accept an override:
- `deep-dive` → recommend **battery**
- `project` / `knowledge` WITH grounding or a broad topic → recommend **battery**
- `project` / `knowledge`, focused + ungrounded → recommend **socratic**

> "This looks like a **battery** interview (grounded / broad): I research, then present a full clustered question set you answer at once. Or **socratic**: one question at a time, adapting as we go. [battery] — reply to switch."

## Step 4: Interview

**battery cadence:** Derive a question set for the mode (banks below), grounded with cited evidence where artifacts exist. Cluster by **leverage** (highest-impact first), number them, present all at once, invite answers in any order/prose.

**socratic cadence:** Ask ONE question, wait, adapt the next to the answer. Maintain a running **coverage ledger** (which mode-bank items are satisfied / thin / waved-off).

**Hybrid stop (both cadences):** cover the mode's checklist floor, probe where answers are thin, and always honor an early "done". Periodically surface coverage: "Covered: X, Y. Still thin: Z. Say 'done' to stop early."

## Step 5: Assemble & Confirm (confirm-before-write)

Assemble the staged-file draft (frontmatter + the mode's body template, filled from answers). Show the full draft and ask: "Here's what I captured — write it to `{path}`? (`y` to write, or tell me what to change)". Do not write until `y`.

## Step 6: Stage

Target by mode:
- `project` → `{knowledge_folder}/intake/projects/{YYYY-MM-DD}-{slug}.md`
- `knowledge` / `deep-dive` → `{knowledge_folder}/intake/interviews/{YYYY-MM-DD}-{slug}.md`

Lazy-create the subfolder if missing. Write the file. Report the path and note: "Staged for manual review — promote later via /extract or by hand (not auto-swept by /audit-knowledge)."

---

## Question Banks (by mode)

**project** — Problem & motivation · Users / who it's for · Scope (in) · Scope (explicitly out) · Constraints (technical/time/dependency) · Stack / approach leanings · Success criteria · Risks & open questions

**knowledge** — Claim / position · Basis & evidence · Confidence (firm/working/speculative) · Contested points & counter-views · Connections to existing knowledge ([[links]]) · What would change my mind

**deep-dive** (the DF-session method) — cluster by leverage, cite evidence per question, hunt negative space:
- Load-bearing invariants — what's immovable vs revisable, and why
- Origin of each decision — where did this come from (research / inheritance / invention)?
- **Negative space** — what was considered and deliberately NOT built?
- What would force a rebuild — name the scenarios that invalidate the current design
- Open threads

---

## Output Templates

Each file opens with this frontmatter (fill `mode`/`cadence`/`slug`; list `grounding` artifacts or omit if none):

```yaml
---
type: interview
mode: project | knowledge | deep-dive
cadence: socratic | battery
date: YYYY-MM-DD
slug: <kebab-topic>
grounding:
  - <artifact>
status: staged
---
```

### project → body

```markdown
# Project Intake: <name>
## Problem & motivation
## Users / who it's for
## Scope — in
## Scope — explicitly out
## Constraints
## Stack / approach leanings
## Success criteria
## Risks & open questions
```

### knowledge → body

```markdown
# <topic>
## Claim / position
## Basis & evidence
## Confidence
## Contested points & counter-views
## Connections to existing knowledge
## What would change my mind
```

### deep-dive → body (preserve Q AND A)

```markdown
# Deep-Dive: <system>
## Grounding reviewed
## Q&A by leverage cluster
## Load-bearing invariants
## Negative space
## What would force a rebuild
## Open threads
```
