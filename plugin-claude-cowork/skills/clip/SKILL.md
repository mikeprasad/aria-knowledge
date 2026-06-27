---
name: clip
description: 'Save a URL or text snippet to the knowledge intake for later review. Use when user says "/aria-cowork:clip" or "/aria-cowork:save". Quick capture without leaving the session — clipped items are reviewed at the next /aria-cowork:audit-knowledge run. (Cowork variant — namespaced-only.)'
argument-hint: <url or text> [tags]
---

# /clip — Quick Capture to Intake

Save a URL or text snippet to `intake/clippings/` for later review and promotion.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Cowork variant — namespaced-only. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/clip` resolves to aria-knowledge's variant — Code is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. To reach this skill, use the namespaced form: `/aria-cowork:clip`. Do NOT match bare `/clip` — that belongs to aria-knowledge.

**Before Step 0:** Check whether the `Bash` tool is available in this session. If `Bash` IS available (you are running in Claude Code or another runtime with shell access), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-cowork's `/clip` from a runtime with shell access.**
>
> Behavior is largely the same in both runtimes; for the Code-native variant (uses WebFetch via Code's tool surface for URL content), use `/clip` (the aria-knowledge canonical).
>
> **Use `/clip` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `clip` (the bare-slash canonical, which routes to aria-knowledge when both ports are loaded) with the same arguments the user provided to this invocation. Do not proceed with this skill's steps; the aria-knowledge variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-cowork) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args.

If `Bash` is NOT available (normal Cowork runtime), proceed to Step 0.

## Step 0: Resolve config

The default knowledge folder is `~/Projects/knowledge/` (expand `~` to your home directory's absolute path). Read `<knowledge_folder>/aria-config.md` and extract `knowledge_folder` (the absolute path).

If `aria-config.md` doesn't exist, stop with: *"aria-cowork is not configured. Run `/aria-setup` to get started."*

Verify `<knowledge_folder>/intake/clippings/` exists. If not, stop with: *"Clippings directory not found. Run `/aria-setup` to repair the knowledge folder structure."*

For all subsequent file operations in this skill, use the absolute path from `knowledge_folder` directly. Cowork resolves absolute paths via the persistent grant from `claude_desktop_config.json` per ADR-008. aria-knowledge in Code uses the same absolute path to reach the same files.

## Step 1: Parse input

The user provides one of:
- **A URL** — starts with `http://` or `https://`
- **Pasted text** — anything else
- **Optional tags** — words after the main content that look like tags (short, no spaces, comma-separated)

If no input is provided, ask: *"What would you like to clip? Paste a URL or text snippet."*

## Step 2: Fetch content (URL only)

If the input is a URL:
1. Use Cowork's WebFetch (or equivalent) to retrieve the page.
2. Extract the page title for the filename and heading.
3. Extract a brief summary (first 2-3 paragraphs or the main content). **Do NOT copy the full page content** — respect copyright; the URL is the reference.
4. Note the URL as the source.

If WebFetch fails, save the URL itself as the content with a note that the page could not be fetched.

## Step 3: Generate filename

Create a kebab-case slug from:
- The page title (for URLs)
- The first 5-6 meaningful words (for text snippets)

Filename format: `{YYYY-MM-DD}-{slug}.md`

Check if the file already exists in `intake/clippings/`. If so, append a numeric suffix: `{date}-{slug}-2.md`.

## Step 4: Write the clipping

Write to `<knowledge_folder>/intake/clippings/{filename}`:

```markdown
---
source: [URL or "manual"]
date: YYYY-MM-DD
tags: [user-provided tags, or auto-detected from content, or empty]
---

# [Title or first line of text]

[Content — summary for URLs, full text for snippets]

[For URLs, end with: "Source: <URL>"]
```

**Tag detection:** If the user didn't provide tags, check if any words in the title or content match known tags from `<knowledge_folder>/index.md` (if it exists). Only suggest tags with high confidence — don't guess.

## Step 5: Confirm

Output:

```
Clipped to intake/clippings/{filename}
Tags: [tags or "none"]
Will be reviewed at next /audit-knowledge run (coming in v0.2.0).
```

## Rules

- **Never copy full page content** — for URLs, capture title + brief summary + the URL itself.
- **Don't over-tag** — empty tags are fine. The audit process will tag properly during promotion.
- **One clipping per invocation** — if the user wants to clip multiple items, they run /clip multiple times. (Bulk capture is `/intake`, not `/clip`.)
- **No confirmation needed** — just clip and confirm. This should be fast.
- **Use Cowork's native I/O for filesystem operations** — never invoke a Filesystem MCP connector (per ADR-003).
