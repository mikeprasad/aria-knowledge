---
description: "Save a URL or text snippet to the knowledge intake for later review. Use when user says '/clip', '/save', 'clip this', 'save this link', 'save this snippet', 'capture this URL'. Quick capture without leaving the session — clipped items are reviewed at the next /audit-knowledge run."
argument-hint: "<url or text> [tags]"
allowed-tools: Read, Write, WebFetch, Glob
---

# /clip — Quick Capture to Intake

Save a URL or text snippet to `intake/clippings/` for later review and promotion.

## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md` and extract `knowledge_folder`. If the file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Verify `{knowledge_folder}/intake/clippings/` exists. If not, stop: "Clippings directory not found. Run /setup to repair the knowledge folder structure."

## Step 1: Parse Input

The user provides one of:
- **A URL** — starts with `http://` or `https://`
- **Pasted text** — anything else
- **Optional tags** — words after the main content that look like tags (short, no spaces, comma-separated)

If no input is provided, ask: "What would you like to clip? Paste a URL or text snippet."

## Step 2: Fetch Content (URL only)

If the input is a URL:
1. Use WebFetch to retrieve the page
2. Extract the page title for the filename and heading
3. Extract a brief summary (first 2-3 paragraphs or the main content) — do NOT copy the full page content (respect copyright)
4. Note the URL as the source

If WebFetch fails, save the URL itself as the content with a note that the page could not be fetched.

## Step 3: Generate Filename

Create a kebab-case slug from:
- The page title (for URLs)
- The first 5-6 meaningful words (for text snippets)

Filename format: `{YYYY-MM-DD}-{slug}.md`

Check if the file already exists in `intake/clippings/`. If so, append a numeric suffix: `{date}-{slug}-2.md`.

## Step 4: Write the Clipping

Write to `{knowledge_folder}/intake/clippings/{filename}`:

```markdown
---
source: [URL or "manual"]
date: YYYY-MM-DD
tags: [user-provided tags, or auto-detected from content, or empty array]
---

# [Title or first line of text]

[Content — summary for URLs, full text for snippets]
```

**Tag detection:** If the user didn't provide tags, check if any words in the title or content match known tags from `{knowledge_folder}/index.md` (if it exists). Only suggest tags with high confidence — don't guess.

## Step 5: Confirm

Output:
```
Clipped to intake/clippings/{filename}
Tags: [tags or "none"]
Will be reviewed at next /audit-knowledge run.
```

## Rules

- **Never copy full page content** — for URLs, capture title + brief summary + the URL itself. The URL is the reference; the clipping is a pointer with context.
- **Don't over-tag** — empty tags are fine. The audit process will tag properly during promotion.
- **One clipping per invocation** — if the user wants to clip multiple items, they run /clip multiple times.
- **No confirmation needed** — just clip and confirm. This should be fast.
