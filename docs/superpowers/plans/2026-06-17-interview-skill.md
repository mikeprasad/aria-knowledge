# `/interview` Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `/interview` skill to the aria-knowledge Claude Code plugin that elicits knowledge through dialogue (3 modes: project / knowledge / deep-dive), choosing cadence (socratic vs battery) in-session, and stages structured markdown into the `intake/` tree.

**Architecture:** A single prompt-skill (`plugin-claude-code/skills/interview/SKILL.md`) implementing a 9-step loop: resolve config → resolve mode + grounding gate → ingest grounding → ask cadence → interview → converge → confirm → stage. The skill is the elicit-side counterpart to the harvest-side intake family; it stages files for **manual review** (the `/meeting-notes` model), never auto-promotes.

**Tech Stack:** Markdown prompt-skill (no executable code). Conventions mirrored from `skills/meeting-notes/SKILL.md` and `skills/intake/SKILL.md`. Validation is a dogfood pass, not unit tests.

**Spec:** `docs/superpowers/specs/2026-06-17-interview-skill-design.md`
**Prospect:** `~/knowledge/logs/prospect/2026-06-17-file-interview-skill-design.md` — verdict PROCEED-WITH-CHANGES. Changes folded in below.

---

## Prospect-driven changes folded into this plan

1. **D3 (gate):** The deep-dive required-grounding gate is written as an **explicit early-return branch** in Step 2 of the skill, and is the **first** dogfood test (Task 6).
2. **D5 (file layout):** **Single `SKILL.md`** with question banks as a trailing section. No separate `question-banks.md` unless the banks exceed ~150 lines (they don't — see Task 3).
3. **D4 (review path) — CORRECTED:** `/audit-knowledge` scans a **fixed** set (4 backlog files + `intake/ideas/`); it does NOT glob `intake/` subfolders, and does not sweep `intake/meetings/` or `intake/docs/` either. Therefore `/interview` output is **manually reviewed staged material** (the `/meeting-notes` model), NOT auto-swept by `/audit-knowledge`. **No `/audit-knowledge` change is needed.** The skill's wording reflects this.

---

## File Structure

- **Create:** `plugin-claude-code/skills/interview/SKILL.md` — the entire skill (frontmatter + 9-step loop + 3 mode question banks + 3 output templates). One file; one responsibility (elicit → stage).
- **Modify:** `plugin-claude-code/skills/help/SKILL.md` — add `/interview` rows to the skill table + the model-routing table.
- **No other files.** No new `intake/` dirs created at plan time (lazy-created by the skill on first write). No `/audit-knowledge` change (per D4 correction).

---

### Task 1: Scaffold the skill file with frontmatter

**Files:**
- Create: `plugin-claude-code/skills/interview/SKILL.md`

- [ ] **Step 1: Create the skill directory and file with frontmatter + title**

```markdown
---
description: "Interview the user to ELICIT knowledge through dialogue, then stage it to the intake/ tree (the elicit-side counterpart to /extract /intake /clip which HARVEST existing sources). Three modes: '/interview project' (scope a new project/build), '/interview knowledge' (get a topic out of your head into the KB), '/interview deep-dive' (comprehensively extract the rationale behind an existing-but-undocumented system you built — REQUIRES a basis to review). Cadence (one-at-a-time socratic vs research-then-batch-of-questions) is chosen in-session. Use when user says '/interview', 'interview me about X', 'grill me on X', 'deep dive on X', 'scope this project', 'ask me questions about X'. Stages to intake/projects/ or intake/interviews/ for manual review; never auto-promotes. (Code port — ADR-094.)"
argument-hint: "<project|knowledge|deep-dive> [topic] [--ground=<path|glob|url>[,...]]"
allowed-tools: Read, Glob, Grep, Write, Edit, WebFetch, Bash
---

# /interview — Elicit Knowledge Through Dialogue

Interview the user to draw out knowledge that lives in their head (and in their artifacts), then stage it as structured markdown in the `intake/` tree. Unlike `/extract` (reads the current conversation), `/intake` (scans files/URLs), or `/clip` (saves a snippet), `/interview` *asks questions* — the answers become the knowledge. Output is staged for **manual review** (the `/meeting-notes` model), never auto-promoted.
```

- [ ] **Step 2: Commit**

```bash
git add plugin-claude-code/skills/interview/SKILL.md
git commit -m "feat(interview): scaffold skill with frontmatter + title"
```

---

### Task 2: Write the Runtime Gate + Step 0 (config resolution)

**Files:**
- Modify: `plugin-claude-code/skills/interview/SKILL.md` (append)

- [ ] **Step 1: Append the ADR-094 runtime gate + config resolution**

Mirror `/meeting-notes` exactly (verified pattern). Append:

```markdown
## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant. v1 ships Code-only — there is no Cowork variant of `/interview` yet (documented port follow-on). If `Bash` is NOT available (non-Code runtime), surface:

> ⚠️ **Runtime mismatch — `/interview` is a Claude Code skill and needs the `Bash` tool to resolve your knowledge folder.** This skill has no Cowork variant yet. Proceed anyway? (`y` / `n`)

On `y`, continue (config read may fail gracefully — ask the user to paste their knowledge-folder path). On `n` / no reply, exit cleanly.

## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md` and extract `knowledge_folder`. If the file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."
```

- [ ] **Step 2: Commit**

```bash
git add plugin-claude-code/skills/interview/SKILL.md
git commit -m "feat(interview): runtime gate + config resolution (Step 0)"
```

---

### Task 3: Write Step 1 (mode + grounding gate) — the D3 explicit early-return branch

**Files:**
- Modify: `plugin-claude-code/skills/interview/SKILL.md` (append)

- [ ] **Step 1: Append mode resolution + the explicit deep-dive grounding gate**

The gate is written as an explicit early-return — this is the prospect's D3 SHRINK.

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add plugin-claude-code/skills/interview/SKILL.md
git commit -m "feat(interview): mode resolution + explicit deep-dive grounding gate (Step 1)"
```

---

### Task 4: Write Steps 2–4 (ingest, cadence, the interview loop)

**Files:**
- Modify: `plugin-claude-code/skills/interview/SKILL.md` (append)

- [ ] **Step 1: Append ingest + cadence + loop**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add plugin-claude-code/skills/interview/SKILL.md
git commit -m "feat(interview): ingest + cadence + interview loop (Steps 2-4)"
```

---

### Task 5: Write Steps 5–6 (assemble + confirm + stage) and the question banks + templates

**Files:**
- Modify: `plugin-claude-code/skills/interview/SKILL.md` (append)

- [ ] **Step 1: Append assemble/confirm/stage + banks + templates**

```markdown
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

### project → frontmatter + body

(frontmatter: type: interview / mode / cadence / date / slug / grounding / status: staged)

# Project Intake: <name>
## Problem & motivation
## Users / who it's for
## Scope — in
## Scope — explicitly out
## Constraints
## Stack / approach leanings
## Success criteria
## Risks & open questions

### knowledge → frontmatter + body

# <topic>
## Claim / position
## Basis & evidence
## Confidence
## Contested points & counter-views
## Connections to existing knowledge
## What would change my mind

### deep-dive → frontmatter + body (preserve Q AND A)

# Deep-Dive: <system>
## Grounding reviewed
## Q&A by leverage cluster
## Load-bearing invariants
## Negative space
## What would force a rebuild
## Open threads
```

- [ ] **Step 2: Verify the file is under ~300 lines (single-file decision holds)**

Run: `wc -l plugin-claude-code/skills/interview/SKILL.md`
Expected: < 300 (in family range; confirms D5 single-file decision — no split needed).

- [ ] **Step 3: Commit**

```bash
git add plugin-claude-code/skills/interview/SKILL.md
git commit -m "feat(interview): assemble/confirm/stage + question banks + output templates (Steps 5-6)"
```

---

### Task 6: Dogfood validation — the deep-dive gate FIRST (D3)

**Files:** none (validation pass — exercise the skill in a scratch session)

- [ ] **Step 1: Test the deep-dive gate refuses (highest-value test)**

Invoke `/interview deep-dive` with NO `--ground` and no basis in the topic.
Expected: the skill STOPS and asks for a basis; it does NOT ask interview questions.
If it proceeds to questions → the gate branch is not firing; fix Step 1 of the skill before continuing.

- [ ] **Step 2: Test project mode (socratic, no grounding)**

Invoke `/interview project "scratch test project"`, choose socratic, answer 2-3 questions, say "done", confirm write.
Expected: stages `intake/projects/{date}-scratch-test-project.md` with the project body template.

- [ ] **Step 3: Test knowledge mode (battery)**

Invoke `/interview knowledge "some opinion I hold"`, accept battery, answer the clustered set, confirm write.
Expected: stages `intake/interviews/{date}-...md` with the knowledge body + clustered Q&A.

- [ ] **Step 4: Test deep-dive grounded on a real artifact**

Invoke `/interview deep-dive --ground=<a small real doc>`.
Expected: gate passes (basis present), questions cite evidence from the doc, stages to `intake/interviews/`.

- [ ] **Step 5: Clean up scratch files**

```bash
# remove the scratch test files created above (keep the deep-dive-on-real-artifact if useful)
```

---

### Task 7: Register the skill in /help

**Files:**
- Modify: `plugin-claude-code/skills/help/SKILL.md`

- [ ] **Step 1: Add /interview rows to the skill table**

Add near the intake-family rows (after the `/intake doc` row, ~line 57):

```markdown
| /interview <mode> | Elicit knowledge via dialogue (project / knowledge / deep-dive); stages to intake/ |
```

- [ ] **Step 2: Add /interview to the model-routing table**

Add to the mid-tier structured-work row (~line 82) alongside `/intake`, `/distill`:

```markdown
... /intake, /distill, /interview, /stitch | Sonnet (mid-tier), medium effort | ...
```

- [ ] **Step 3: Commit**

```bash
git add plugin-claude-code/skills/help/SKILL.md
git commit -m "docs(help): register /interview in skill + model-routing tables"
```

---

## Out of Scope (v1) — do NOT implement

- Codex / Cursor / Antigravity ports (follow-on).
- aria-core (`core.*`) write target.
- `/audit-knowledge` changes (per D4: it doesn't sweep these subfolders; manual-review model is intended).
- A `--cadence` flag (cadence is in-session).
- Mid-session cadence switching.
