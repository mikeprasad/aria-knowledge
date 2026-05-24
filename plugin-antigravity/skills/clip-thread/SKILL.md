---
description: "NOTE: this skill requires ~~chat or ~~email MCPs, which are typically only connected in Cowork — the Code variant exists for parity but most users will want the Cowork variant. Capture a chat or email thread from a connected MCP to the knowledge intake. Use when user says '/clip-thread', 'clip this thread', 'save this Slack thread', 'capture this email chain', 'archive this conversation'. Pulls thread content from ~~chat (Slack, Teams) or ~~email (Gmail, MS365) MCP, composes a clipping with thread metadata + body, writes to intake/clippings/ for review at next /audit-knowledge."
---

# /clip-thread — Capture Chat/Email Thread to Intake

Save a chat thread or email conversation to `intake/clippings/{YYYY-MM-DD}-{slug}.md` for review and promotion. Unlike `/clip` (URL/snippet) or `/intake` (bulk/doc-anchored), `/clip-thread` is shaped specifically for *threaded* conversations — Slack threads, Teams channel discussions, Gmail conversation chains, MS365 email threads.

## Step 0: Resolve Config

Read `~/.gemini/antigravity/aria-knowledge.local.md` and extract `knowledge_folder`. If the file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Verify `{knowledge_folder}/intake/clippings/` exists. If not, stop: "Clippings directory not found. Run /setup to repair the knowledge folder structure."

## Step 1: Probe Connected MCPs

Check Claude's available tool list for `~~chat` and `~~email` MCPs. The skill needs at least ONE of these connected to proceed.

- **`~~chat`** (slack, ms365): if connected, available for Slack threads or Teams channel messages.
- **`~~email`** (gmail, ms365): if connected, available for Gmail or MS365 email threads.

If NEITHER category has a connected MCP, output the standard fallback notice and stop:

> No required MCPs connected for `/clip-thread`. Connect one of: Slack, Microsoft 365 Teams (for ~~chat) or Gmail, Microsoft 365 Outlook (for ~~email) via Claude Code's MCP config (or Cowork Settings → Connectors). See [CONNECTORS.md](../../CONNECTORS.md). Skipping this run.

Per [ADR-015](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/015-capability-probe-pattern.md), the runtime tool list IS the probe — no explicit API call needed.

## Step 2: Parse Input

The user provides one of:

- **A Slack thread URL** — `https://<workspace>.slack.com/archives/<channel>/<message-ts>` or thread permalink
- **A Teams message link** — `https://teams.microsoft.com/l/message/...`
- **A Gmail thread ID or URL** — `https://mail.google.com/mail/u/0/#inbox/<thread-id>` or just the thread ID
- **An MS365 message ID** — opaque ID from Outlook
- **A bare thread/conversation identifier** — opaque string the connected MCP can resolve

Optionally followed by tags (e.g., `slack #engineering`, `email customer-feedback`).

**Source-type detection:**

| Input shape | Routes to |
|---|---|
| Contains `slack.com/archives/` | `~~chat` (slack) |
| Contains `teams.microsoft.com` | `~~chat` (ms365) |
| Contains `mail.google.com` or matches Gmail thread-ID pattern | `~~email` (gmail) |
| Outlook-shaped ID | `~~email` (ms365) |
| Ambiguous | Ask user which category to route through |

If the detected category's MCP is NOT connected, output the category-specific fallback notice and stop:

> This thread looks like a [Slack thread / Gmail thread / etc.] but the `~~chat` / `~~email` MCP for that source is not connected. Connect [vendor] via your MCP config and retry. Skipping this run.

## Step 3: Fetch Thread Content

Call the appropriate MCP tool to retrieve the thread:

- **Slack:** use the connected slack MCP's `conversations.replies` (or equivalent) tool with the channel + thread_ts derived from the URL. Retrieve all messages in the thread.
- **Teams:** use the connected ms365 MCP's message-thread tool.
- **Gmail:** use the connected gmail MCP's `messages.get` for each message in the thread (or `threads.get` if exposed).
- **MS365 Outlook:** use the ms365 MCP's email-thread tool.

For each message in the thread, gather:
- Author (display name + handle/email)
- Timestamp (ISO format)
- Body (plaintext if available, markdown if the source supports it)
- Reactions / attachments (if exposed — note their presence but don't fetch attachment bodies in this skill)

**Limit:** if the thread has more than 50 messages, fetch the first 50 + note the truncation in the clipping. The user can run `/clip-thread` again with a refined identifier for the tail.

## Step 4: Compose Clipping

Slug-ify the thread for the filename: use the first message's first ~6 significant words, lowercased, hyphen-separated, ASCII-only.

Generate the date stamp as `YYYY-MM-DD` (local time).

Filename: `intake/clippings/{date}-{slug}.md`

If a file with that name already exists, append `-2`, `-3`, etc. to deduplicate.

Body template:

```markdown
---
source: <thread-url-or-id>
source_type: <slack|teams|gmail|ms365>
date: <YYYY-MM-DD>
participants: [<list of unique authors>]
message_count: <N>
tags: [<from input args, plus auto-detected like 'slack' or 'email'>]
---

# <thread topic — extracted from first message's first line or the channel name>

## Context

- **Source:** <source URL or "Slack thread in #channel" / "Gmail thread with N replies">
- **Participants:** <N authors>: <list>
- **Spans:** <first-message-date> → <last-message-date>
- **Message count:** <N> (or "<N> of <total> — truncated at 50")

## Thread

<for each message:>

### <Author> — <timestamp>

<message body, lightly cleaned (remove Slack/MS markup if obvious, preserve markdown)>

<reactions if present: e.g., "Reactions: 👍 ×3, 🎉 ×1">

<attachment notes if present: e.g., "[attachment: deploy-logs.txt (45KB)]">

---

## Reaction

<intentionally left empty — the user's reaction / why this is worth keeping. /audit-knowledge surfaces this for review at next audit pass.>
```

## Step 5: Write + Report

Write the composed clipping to `{knowledge_folder}/intake/clippings/{date}-{slug}.md`.

Report to user:

```
Clipped <N> messages from <source-type> thread to intake/clippings/<date>-<slug>.md.

- Participants: <list, max 5 + "and N more" if truncated>
- Spans: <date range>
- Tags: <from input>

Next: review at next /audit-knowledge run. Add a reaction in the "## Reaction" section if you want to lock in the why-it-matters context now.
```

## Rules

- **Never auto-promote.** Clippings stay in `intake/clippings/` until `/audit-knowledge` routes them. This skill is intake-only.
- **Never delete the source.** Reading a thread via MCP doesn't modify it; this is read-only externally.
- **Respect 50-message truncation cap.** Do NOT loop and fetch all pages. If user wants the full thread, they can re-invoke with a refined scope or use the source platform's native export.
- **Strip secrets if obvious** — if the thread contains what look like API keys, OAuth tokens, or passwords (regex match against common patterns), replace with `[REDACTED]` in the body and add a `redactions: true` field to frontmatter. Surface in the report.
- **One thread per invocation.** If the user wants multiple threads, suggest `/intake` bulk mode.

## Notes

- Composes with `/audit-knowledge` — clippings written here are routed at next audit per the standard intake-disposition vocabulary (Accept → tracker / roadmap / todo / adr / plan / bundle / rule, or Reject / Defer).
- The `## Reaction` section is the user's voice slot. `/clip-thread` never fills it (the same precedent `/intake doc` set in v2.17.0).
- This skill is **bidirectional** per [ADR-014](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/014-bidirectional-feature-flow.md) — aria-cowork v0.4.0 ships an identical port. Output schema is byte-identical per [ADR-013](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/013-cowork-modified-skills-schema-identical-outputs.md).
- Probe semantics per [ADR-015](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/015-capability-probe-pattern.md).
