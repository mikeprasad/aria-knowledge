---
description: "Save a URL or text snippet to the knowledge intake for later review. Use when user says '/clip', '/save', 'clip this', 'save this link', 'save this snippet', 'capture this URL'. Quick capture without leaving the session — clipped items are reviewed at the next /audit-knowledge run. (Code port — ADR-094.)"
argument-hint: "<url or text> [tags]"
allowed-tools: Read, Write, WebFetch, Glob
---

# /clip — Quick Capture to Intake

> **RETIRED 2026-06-21 (v2.33.0).** Folded into `/intake`: clip → `/intake <url|text>` (auto clip-whole). Kept for reference only — not a live skill (archived under `skills/.archived/`, excluded from discovery).

Save a URL or text snippet to `intake/clippings/` for later review and promotion.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/clip` resolves to this skill — aria-knowledge (Code) is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. The Cowork variant is namespaced-only: `/aria-cowork:clip`.

**Before Step 0:** Check that the `Bash` tool is available in this session. If `Bash` is NOT available (you are running in Claude Cowork or another non-Code runtime), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/clip` from a non-Code runtime.**
>
> Behavior is largely the same in both runtimes; for the Cowork-native variant (writes to `intake/clippings/` in the attached knowledge folder via persistent-grant), use `/aria-cowork:clip`.
>
> **Use `/aria-cowork:clip` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `aria-cowork:clip` with the same arguments the user provided to this invocation. Do not proceed with this skill's steps; the cowork variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-knowledge) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args.

If `Bash` is available, proceed to Step 0.

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
