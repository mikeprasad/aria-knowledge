---
name: ask
description: "Research a question, check existing ARIA knowledge first, draft a knowledge note, and save it to the right knowledge category. Trigger on /ask, research and save, or ask about a pattern."
argument-hint: "<question>"
allowed-tools: Read, Write, Glob, Grep, WebSearch, WebFetch
---

# /ask — Query-Driven Knowledge Creation

Research a question, check if the answer already exists in the knowledge base, and if not, draft a knowledge doc that saves directly to promoted files after user review. Fast path from question to knowledge — no backlog intermediary.

## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md` and extract `knowledge_folder`. If the file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Use `{knowledge_folder}` as the base path for all file operations in subsequent steps.

## Step 1: Parse Question

The user provides a question as the argument. If no argument is provided, ask: "What would you like to know?"

Extract the core topic and likely tags from the question for use in Step 2.

## Step 2: Check Existing Knowledge

Before researching, check if the answer already exists:

1. **Resolve aliases first (added 2.16.0):** if `{knowledge_folder}/aliases.md` exists, parse the alias→canonical map and replace any tag token in the question that matches an alias with its canonical form before the index lookup. No notification line needed — this is internal to `/ask`'s coarse check (`/context` is the surface that surfaces resolution notifications).

   If `{knowledge_folder}/index.md` exists, extract tags from the (post-alias-resolution) question and check for matching files in both the `## Tag Index` section AND the `## Semantic Hints Index` section. Tag matching is exact equality (existing behavior); hint matching is substring (case-insensitive, hyphen-normalized) — same rule as `/context` Step 4. A hint match counts the same as a tag match for partial-match detection. (Added 2.16.0.)
2. Scan headings of files in `approaches/`, `guides/`, `references/`, `decisions/` for topic overlap
3. Check `intake/` backlogs for pending items on the same topic

**If a strong match is found:** Present the existing file(s) to the user:
> "This may already be covered in [filename]. Want me to load it? Or research fresh?"

- If user says load: read and present the file, done
- If user says research: proceed to Step 3
- If partial match: note it for Step 5 ("related existing doc found — consider updating instead of creating new")

**If no match:** Proceed to Step 3.

## Step 3: Research

Answer the question using available sources:

1. **Knowledge base** — scan relevant files for partial answers or related context
2. **Codebase** — if the question relates to the current project, check code, configs, and project docs
3. **Web** — use WebSearch and WebFetch for external information (APIs, frameworks, best practices)

Synthesize a clear, complete answer. Focus on practical, actionable knowledge — not textbook definitions.

## Step 4: Determine Category

Based on the answer content, suggest where it belongs:

| Content type | Category | Example |
|---|---|---|
| How to do X (proven method) | `approaches/` | API pagination patterns |
| How X works (operational) | `guides/` | Supabase auth setup |
| What others say about X | `references/` | Stripe webhook best practices |
| We chose X because Y | `decisions/` | Why cursor over offset pagination |
| X must/must not (principle) | `rules/` | Rare — usually via `/audit-knowledge` |

## Step 5: Draft Knowledge Doc

Write a draft in the standard format for the suggested category:

```markdown
---
tags: [detected tags from question and answer]
---

# [Title]

**Last updated:** YYYY-MM-DD

[Answer content — structured with sections as appropriate]

## Related
[Links to any existing knowledge files that connect to this topic]
```

If Step 2 found a partial match, note: "Related: [existing file] — consider whether this should update that file instead of creating a new one."

## Step 6: Present for Review

Show the draft with metadata:

```
## /ask Result

**Question:** [original question]
**Category:** [suggested category]
**File:** [suggested filename in kebab-case]
**Tags:** [detected tags]

[Draft content]

Save to {knowledge_folder}/[category]/[filename]? (yes / edit / change category / reject)
```

## Step 7: Save or Discard

Based on user response:
- **"yes"** — write the file to the suggested location
- **"edit"** — user provides edits, then save
- **"change category"** — user specifies different category/filename, then save
- **"update [existing file]"** — merge content into the specified existing file instead of creating new
- **"reject"** — discard, nothing saved

After saving, confirm: "Saved to [path]. Run /index to update the tag index."

## Rules

- **Check existing first** — never create a duplicate when an update would serve better
- **Skip backlogs** — the user is reviewing in real-time, no need for staging
- **Respect copyright** — for web-sourced answers, synthesize in your own words. Include source URLs in a References section but don't copy content.
- **Practical over theoretical** — answers should help future sessions, not read like documentation. "Here's how to do X" over "X is defined as..."
- **Tag detection** — match question keywords against known tags from index.md. Add new freeform tags if no known tag fits.
- **One question, one doc** — if the question spans multiple topics, suggest splitting into separate `/ask` invocations.
