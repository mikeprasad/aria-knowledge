---
description: "ELICIT knowledge by interviewing the user, then stage to intake/ for manual review (elicit-side counterpart to /extract /intake /clip). Modes: 'project' (scope a build), 'knowledge' (a topic into the KB), 'deep-dive' (rationale behind something you built — needs a basis). Use when user says '/aria-cowork:interview', 'interview me about X', 'grill me on X', 'deep dive on X', 'scope this project'. (Cowork variant — namespaced-only.)"
argument-hint: "<project|knowledge|deep-dive> [topic] [--ground=<path|glob|url>[,...]] [--socratic|--battery]"
allowed-tools: Read, Glob, Grep, Write, Edit, WebFetch
---

# /interview — Elicit Knowledge Through Dialogue

Interview the user to draw out knowledge that lives in their head (and in their artifacts), then stage it as structured markdown in the `intake/` tree. Unlike `/extract` (reads the current conversation) or `/intake` (captures external sources — a URL or snippet clipped whole, files and globs scanned, a doc or thread pulled in), `/interview` *asks questions* — the answers become the knowledge. Output is staged for **manual review** (the `/meeting-notes` model), never auto-promoted.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Cowork variant — namespaced-only. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session, bare `/interview` resolves to aria-knowledge's variant — Code is the canonical owner of all dual-port skills per ADR-094 §Part 1. To reach this skill, use the namespaced form: `/aria-cowork:interview`. Do NOT match bare `/interview` — that belongs to aria-knowledge.

**Before Step 0 — runtime self-correction.** Check whether the `Bash` tool is available in this session. If `Bash` IS available (you are running in Claude Code or another runtime with shell access), this invocation reached the wrong variant for the runtime. **Do not ask — redirect.** Announce it in one line, then use the `Skill` tool to invoke `interview` with the same arguments the user provided, and do not run this skill's steps:

> ↪️ **Redirecting to `/interview` — you invoked the aria-cowork variant, but you are running in Claude Code or another runtime with shell access.**
>
> This variant runs conversationally and resolves your knowledge folder by reading the config file directly (no Bash). For the Code-native variant, use `/interview` (the aria-knowledge canonical).

⛔ **The redirect is unconditional** — every mode including `auto`, and no opt-out. Reaching this variant under that condition is always a mis-invocation, so there is nothing for the user to decide. Design record: `docs/superpowers/specs/2026-08-28-runtime-gate-auto-redirect-design.md` (D2 auto-redirect, D3 no escape hatch, D6 announce-don't-swap-silently).

If `Bash` is NOT available (normal Cowork runtime), proceed to Step 0.


## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md` with the `Read` tool and extract `knowledge_folder`. If the file is not reachable in this runtime (Cowork's attached-folder sandbox may not expose `~/.claude/`), do NOT stop — ask the user: "I can't reach your aria-knowledge config from here. Paste your knowledge-folder path (e.g. `~/Projects/knowledge`) and I'll use it for this session." Use the pasted path. If the user has never run `/setup`, point them there first.

## Step 1: Resolve Mode, Topic, Grounding

Parse arguments: first positional = **mode** (`project` | `knowledge` | `deep-dive`). Remaining text = **topic**. `--ground=<path|glob|url>[,...]` = optional grounding artifacts. `--socratic` and `--battery` = cadence overrides (Step 3); both are also accepted bare (`socratic`, `battery`). They are **mutually exclusive** — if both appear, take `--socratic` (the more conservative grain) and say in one line that you did.

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

## Step 3: Cadence — `guided` by default, `--battery` to opt out

**`guided` is the default for all three modes.** Do not recommend a cadence, do not ask which one — just run `guided` unless `--battery` was passed. The old behavior (recommend `battery` for anything grounded or broad) made the all-at-once path the effective default, which is the wrong default: a numbered wall of questions has to be answered by scrolling and referencing numbers, and because a batch is derived before any answer arrives, it necessarily keeps asking things an earlier answer already made irrelevant.

**`--battery` is the escape hatch, not a co-equal option.** Mention it **once, in one line, and only** when the derived question set is large enough that sequential dialogs would genuinely be worse than a list (roughly >12 questions — in practice a broad `deep-dive`). Then proceed with `guided` without waiting for a reply:

> "This derives ~N questions. Staying guided — small dialogs, adapting as we go. Reply `--battery` any time if you'd rather take the whole set at once as a list."

**`--socratic` pins the grain, it is not a third cadence.** There are two cadences, and they differ on **when the questions are derived**, not on how many appear at once: `guided` re-derives after every answer, `battery` derives the whole set before the first one. `--socratic` is `guided` with the dialog grain pinned to exactly one question — same adaptive loop, no clustering. Reach for it when the user has said they want one at a time, or when they distrust the clustering judgment; `guided` already collapses to one question wherever the independence test fails, so this is a manual override of that judgment, not a different process. Record it in Step 6 as `cadence: socratic` — the artifact then states the grain the answers were given at, which a later reader needs.

## Step 4: Interview

### `guided` cadence (the default)

Ask in **small dialogs of 1-4 questions** — one dialog, wait, then derive the next from what came back. Never present a numbered list the user has to answer by number.

**Cowork has no picker affordance**, so a dialog is simply the questions asked conversationally in one message. Keep them visually separable (a short bold lead-in each) so a reply can address them in any order, and never number them for reference — numbering is what turns a dialog back into a battery.

**Every question carries suggested answers.** Offer 2-4 concrete candidate answers per question, drawn from the mode's question bank and — where grounding artifacts exist — from the evidence itself (a real value read out of a document beats an invented placeholder). Free-text is always available, so a suggestion set is a **shortcut, never a constraint**; say so once at the start and don't repeat it per question. **Never invent a suggestion to fill a slot** — two real candidates are better than four with two fabricated, and a fabricated option in an elicitation interview is worse than none because it can be picked.

**Cluster size is contextual, not fixed.** Put 2-4 questions in one dialog only when they are **mutually independent** — no answer to one can change the wording, the options, or the relevance of another in the same dialog. Anything that branches goes alone. When unsure, ask it alone: the cost of an extra dialog is one round-trip, while the cost of a batched question its neighbour invalidated is precisely the failure this cadence exists to remove.

**`--socratic` pins the grain to one.** When it was passed, ask exactly one question per dialog for the whole interview and skip the independence test entirely — there is nothing to cluster. Everything else is unchanged: same suggested answers, same custom fill, same re-derive-after-each-dialog loop, same coverage ledger. Do not batch "just these two, they're obviously independent" — the flag exists precisely to take that call away from you.

**Adapt, and drop what died.** After each dialog, re-derive before asking again: strike questions the last answers made irrelevant, add the ones they opened, re-cluster the remainder. Never carry a pre-derived list forward unchanged — that is `battery` wearing `guided`'s clothes.

Maintain a running **coverage ledger** (which mode-bank items are satisfied / thin / waved-off).

### `battery` cadence (only when `--battery` was passed)

Derive a question set for the mode (banks below), grounded with cited evidence where artifacts exist. Cluster by **leverage** (highest-impact first), number them, present all at once, invite answers in any order/prose. **State the known limitation once, up front:** the set is fixed before your first answer, so some questions will read as irrelevant by the time you reach them — skip those outright rather than answering around them.

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
cadence: guided | socratic | battery   # socratic = guided pinned to one question per dialog
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
