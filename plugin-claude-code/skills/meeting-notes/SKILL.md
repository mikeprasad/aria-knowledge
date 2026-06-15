---
description: "NOTE: paste-text fallback works without MCPs, but ~~docs MCPs (Notion, Confluence, Granola) are typically only connected in Cowork — the Cowork variant has better fidelity for MCP-sourced meetings. Fold a meeting transcript or notes into structured intake. Use when user says '/meeting-notes', 'capture meeting notes', 'fold this meeting transcript', 'process this Granola export', 'archive this standup'. Accepts a ~~docs URL (Notion meeting page, Confluence) OR pasted transcript text — unique among MCP-consuming skills in offering a paste fallback when no ~~docs MCP is connected. (Code port — ADR-094.)"
argument-hint: "<doc-url-or-paste-marker> [meeting-title]"
allowed-tools: Read, Write, Grep
---

# /meeting-notes — Capture Meeting Transcript to Intake

Save a meeting transcript or notes to `intake/meetings/{YYYY-MM-DD}-{slug}.md` with structured participants / topics / action items / decisions sections. Source can be a `~~docs` MCP (Notion meeting page, Confluence meeting doc) OR pasted transcript text (Granola export, raw transcript, hand-written notes).

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/meeting-notes` resolves to this skill — aria-knowledge (Code) is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. The Cowork variant is namespaced-only: `/aria-cowork:meeting-notes`.

**Before Step 0:** Check that the `Bash` tool is available in this session. If `Bash` is NOT available (you are running in Claude Cowork or another non-Code runtime), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/meeting-notes` from a non-Code runtime.**
>
> This skill works in either runtime via paste-text fallback, but MCP-sourced meetings (Notion, Confluence, Granola) require ~~docs MCPs typically only present in Cowork. For the Cowork-native variant with better MCP fidelity, use `/aria-cowork:meeting-notes`.
>
> **Use `/aria-cowork:meeting-notes` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `aria-cowork:meeting-notes` with the same arguments the user provided to this invocation. Do not proceed with this skill's steps; the cowork variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-knowledge) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args.

If `Bash` is available, proceed to Step 0.

## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md` and extract `knowledge_folder`. If the file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Verify `{knowledge_folder}/intake/meetings/` exists. If not, create it (lazy creation for first-time use of this skill).

## Step 1: Probe Connected MCPs (with paste fallback)

Check Claude's available tool list for `~~docs` MCPs:

- **`~~docs`** (notion, atlassian, box, egnyte, google docs): if connected, available for MCP-sourced meeting docs.

**Branching logic** (this skill diverges from other MCP-consuming skills here — see [ADR-015](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/015-capability-probe-pattern.md) §"Application across the 5 MCP-consuming skills"):

- **If `~~docs` IS connected AND input looks like a URL/ID:** route through MCP fetch (Step 2 MCP branch).
- **If `~~docs` IS NOT connected OR input is `paste` (or empty):** offer paste fallback (Step 2 paste branch).
- **If input is `paste` even with `~~docs` connected:** respect the explicit paste choice; skip MCP fetch.

Unlike `/extract-doc`, `/clip-thread`, `/digest`, and `/sync-decisions`, this skill does NOT hard-stop when no `~~docs` MCP is present. Meeting transcripts often arrive via paste (from Granola, from a meeting tool's export button, from hand-typed notes) — closing that path would defeat the skill's primary use case.

## Step 2 (MCP branch): Parse + Fetch from ~~docs

Same as `/extract-doc` Step 2-3. Routing table:

| Input shape | Routes to |
|---|---|
| Contains `notion.so` | notion (`~~docs`) |
| Contains `atlassian.net/wiki` | atlassian (`~~docs`) |
| Contains `docs.google.com/document` | google docs (`~~docs`) |
| Bare ID + known MCP | use the connected one |

Fetch the doc body. Proceed to Step 3.

## Step 2 (paste branch): Prompt for transcript

If no MCP fetch is possible (or the user passed `paste`), prompt:

```
Paste the meeting transcript or notes below. End with a blank line + `---END---` on its own line. Common sources:

- Granola export (Markdown)
- Slack thread copy-paste
- Hand-typed notes
- Zoom / Teams / Meet auto-transcript export
- Any plaintext or Markdown

I'll structure it into participants / topics / action items / decisions.
```

Wait for the paste. Read the content until `---END---` marker. Proceed to Step 3.

## Step 3: Structure the Transcript

Parse the transcript body to identify these sections (Claude infers from content; this is NOT a strict parser — handle informal transcripts):

1. **Participants** — names + roles if present. Look for lists at the top, "@" mentions, speaker labels.
2. **Date + duration** — if not explicit, ask user or default to today.
3. **Topics discussed** — section headings, bullet points, "we talked about" markers.
4. **Action items** — "TODO", "[ ]", "@person will", "action:" markers. Extract assignee + description + due date if present.
5. **Decisions** — "we decided", "agreed to", "going with X over Y" patterns. Extract the decision + rationale if stated.
6. **Open questions** — "?", "unresolved", "follow-up", "need to figure out" markers.
7. **Topic-level summary** — 1-2 sentences per major topic.

Be conservative: if a section can't be reliably extracted, mark it `(none identified)` rather than fabricating.

## Step 4: Compose Meeting Note

Slug-ify the meeting title for the filename (from input arg, or extracted from first heading, or "meeting" as fallback). Lowercase, hyphen-separated, ASCII-only, max ~50 chars.

Filename: `intake/meetings/{YYYY-MM-DD}-{slug}.md`. If a file with that name exists, append `-2`, `-3` to deduplicate.

Body template:

```markdown
---
date: <YYYY-MM-DD>
title: <meeting title>
source: <doc-url OR "pasted transcript">
source_type: <notion|atlassian|box|egnyte|google docs|paste>
participants: [<name list>]
duration: <if known>
tags: [meeting, <project-tag-if-inferable>]
---

# <Meeting title>

## Context

- **Date:** <YYYY-MM-DD>
- **Source:** <doc-url OR "pasted transcript">
- **Participants:** <comma-separated list>
- **Duration:** <if known, else omit>

## Topics

<for each major topic, with 1-2 sentence summary:>

### <Topic name>

<summary>

## Action Items

<for each action item:>

- [ ] **<assignee>** — <action description> <(due: <date> if present)>

<or: "(none identified)" if section is empty>

## Decisions

<for each decision:>

- **<decision>** — <rationale if stated, else "no rationale captured">

<or: "(none identified)">

## Open Questions

- <question>

<or: "(none identified)">

## Raw Transcript

<the original transcript body, preserved verbatim for reference. If from MCP fetch, include source-doc URL at top of this section.>

---

## Reaction

<intentionally left empty — the user's reaction / why this meeting is worth keeping in knowledge. /audit-knowledge surfaces this for review.>
```

## Step 5: Write + Report

Write the composed meeting note to `{knowledge_folder}/intake/meetings/{date}-{slug}.md`.

Report to user:

```
Captured meeting "<title>" to intake/meetings/<date>-<slug>.md.

- Source: <vendor or "pasted">
- Participants: <N>: <list, max 5 + "and N more">
- Topics: <N>
- Action items: <N>
- Decisions: <N>
- Open questions: <N>

Next: add a reaction in the "## Reaction" section (or wait for /audit-knowledge to surface it). Action items + decisions may be worth extracting separately via /extract-doc on this file if you want them in the standard intake backlogs.
```

## Rules

- **Never delete the source doc.** Read-only on the MCP side.
- **Preserve the raw transcript verbatim.** The structured sections are derived; the raw transcript is the source-of-truth. Both ship in the same file so audit / future re-extraction has the source.
- **Strip secrets if obvious** — same redaction rules as `/clip-thread`. Note redactions in frontmatter.
- **Default `(none identified)` over fabrication.** If a section can't be reliably parsed, mark it empty rather than guess.
- **One meeting per invocation.** Multiple meetings = multiple `/meeting-notes` calls.

## Notes

- The Reaction section pattern matches `/intake doc` (v2.17.0) and `/clip-thread` (v2.18.0) — capture artifacts ship with a user-fillable "why this matters" slot that Claude never autocompletes.
- Bidirectional per [ADR-014](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/014-bidirectional-feature-flow.md) — aria-cowork v0.4.0 imports byte-faithfully.
- Output schema is byte-identical per [ADR-013](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/013-cowork-modified-skills-schema-identical-outputs.md). Both plugins write to `intake/meetings/` in the shared knowledge folder.
- **Paste-fallback divergence** documented in [ADR-015](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/015-capability-probe-pattern.md) §"Application across the 5 MCP-consuming skills" — this is the one skill that doesn't hard-stop on missing MCPs.
- The skill is **intake-only** — it doesn't promote meeting notes to `references/` or `decisions/`. That's `/audit-knowledge`'s job at next audit, or the user can manually promote via `/extract-doc` on this file to split out decisions/action items.
- Composes naturally with Granola exports — Granola's Markdown format already includes participants + transcript + (optionally) extracted action items. The paste branch picks this up cleanly.
