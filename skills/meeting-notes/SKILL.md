---
name: meeting-notes
description: Fold a meeting transcript or notes into structured intake. Use when user says "/meeting-notes", "/aria-cowork:meeting-notes", "capture meeting notes", "fold this meeting transcript", "process this Granola export", "archive this standup". Accepts a ~~docs URL (Notion meeting page, Confluence) OR pasted transcript text — unique among MCP-consuming.
argument-hint: <doc-url-or-paste-marker> [meeting-title]
---

# /meeting-notes — Capture Meeting Transcript to Intake

Save a meeting transcript or notes to `intake/meetings/{YYYY-MM-DD}-{slug}.md` with structured participants / topics / action items / decisions sections. Source can be a `~~docs` MCP (Notion meeting page, Confluence meeting doc) OR pasted transcript text (Granola export, raw transcript, hand-written notes).

## Step 0: Resolve config

The default knowledge folder is `~/Projects/knowledge/` (expand `~` to your home directory's absolute path). Read `<knowledge_folder>/aria-config.md` and extract `knowledge_folder` (the absolute path).

If `aria-config.md` doesn't exist, stop with: *"aria-cowork is not configured. Run `/aria-setup` to get started."*

Verify `<knowledge_folder>/intake/meetings/` exists. If not, create it (lazy creation for first-time use of this skill).

For all subsequent file operations in this skill, use the absolute path from `knowledge_folder` directly. Cowork resolves absolute paths via the persistent grant from `claude_desktop_config.json` per ADR-008. aria-knowledge in Code uses the same absolute path to reach the same files.

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

Write the composed meeting note to `<knowledge_folder>/intake/meetings/{date}-{slug}.md`.

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

- The Reaction section pattern matches `/intake doc` (v0.3.0) and `/clip-thread` (v1.0.0) — capture artifacts ship with a user-fillable "why this matters" slot that Claude never autocompletes.
- Bidirectional per [ADR-014](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/014-bidirectional-feature-flow.md) — aria-knowledge v2.18.0 ships an identical body.
- Output schema is byte-identical per [ADR-013](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/013-cowork-modified-skills-schema-identical-outputs.md). Both plugins write to `intake/meetings/` in the shared knowledge folder.
- **Paste-fallback divergence** documented in [ADR-015](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/015-capability-probe-pattern.md) §"Application across the 5 MCP-consuming skills" — this is the one skill that doesn't hard-stop on missing MCPs.
- The skill is **intake-only** — it doesn't promote meeting notes to `references/` or `decisions/`. That's `/audit-knowledge`'s job at next audit, or the user can manually promote via `/extract-doc` on this file to split out decisions/action items.
- Composes naturally with Granola exports — Granola's Markdown format already includes participants + transcript + (optionally) extracted action items. The paste branch picks this up cleanly.
