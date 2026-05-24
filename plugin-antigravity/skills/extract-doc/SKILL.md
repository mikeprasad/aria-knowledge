---
description: "NOTE: this skill requires connected ~~docs MCPs (Notion, Google Docs, Confluence, Box, Egnyte), which are typically only present in Cowork — the Code variant exists for parity but most users will want the Cowork variant. Pull insights from a single doc or page (Notion, Google Doc, Confluence, etc.) into the standard intake backlog. Use when user says '/extract-doc', 'extract insights from this doc', 'pull learnings from this page', 'mine this Notion page for knowledge', 'extract from this Confluence'. Differs from /intake doc (which captures one structured doc artifact with reaction) — extract-doc decomposes a doc into multiple intake-backlog entries for audit routing."
---

# /extract-doc — Extract Insights from a Doc to Intake Backlog

Pull knowledge-worthy items from a single connected `~~docs` source (Notion page, Google Doc, Confluence page, Box doc, Egnyte file) into `intake/insights-backlog.md`. Unlike `/intake doc` (which captures the doc itself as one structured artifact for later reaction), `/extract-doc` **decomposes** the doc into N intake entries — one per insight, decision, or question worth surfacing at audit.

## Step 0: Resolve Config

Read `~/.gemini/antigravity/aria-knowledge.local.md` and extract `knowledge_folder`. If the file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Verify `{knowledge_folder}/intake/insights-backlog.md` exists. If not, stop: "Insights backlog not found. Run /setup to repair the knowledge folder structure."

## Step 1: Probe Connected MCPs

Check Claude's available tool list for `~~docs` MCPs:

- **`~~docs`** (notion, atlassian, box, egnyte, google docs): if connected, available for doc fetch.

If NO `~~docs` MCP is connected, output the standard fallback notice and stop:

> No required MCPs connected for `/extract-doc`. Connect one of: Notion, Atlassian (Confluence), Box, Egnyte, or Google Docs (when available) via Claude Code's MCP config (or Cowork Settings → Connectors). See [CONNECTORS.md](../../CONNECTORS.md). Skipping this run.

Per [ADR-015](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/015-capability-probe-pattern.md).

## Step 2: Parse Input

The user provides one of:

- **A Notion page URL** — `https://www.notion.so/<workspace>/<title>-<id>` or `notion.so/<id>`
- **A Confluence page URL** — `https://<org>.atlassian.net/wiki/spaces/<space>/pages/<id>/<title>`
- **A Google Docs URL** — `https://docs.google.com/document/d/<doc-id>/...` (if google docs MCP wired; placeholder URL in v2.18.0 .mcp.json)
- **A Box file URL** — `https://app.box.com/file/<file-id>`
- **An Egnyte file URL** — `https://<org>.egnyte.com/...`
- **A bare doc/page ID** — opaque string the connected MCP can resolve

Optionally followed by tags (e.g., `engineering postmortem`, `cs onboarding`).

**Source-type detection:**

| Input shape | Routes to |
|---|---|
| Contains `notion.so` or `www.notion.so` | `~~docs` (notion) |
| Contains `atlassian.net/wiki` | `~~docs` (atlassian) |
| Contains `docs.google.com/document` | `~~docs` (google docs) |
| Contains `app.box.com/file` | `~~docs` (box) |
| Contains `egnyte.com` | `~~docs` (egnyte) |
| Ambiguous | Ask user which `~~docs` MCP holds the doc |

If the detected-source's MCP is not connected, output a specific fallback notice:

> This doc looks like a [Notion / Confluence / etc.] page but the [vendor] MCP is not connected. Connect [vendor] via your MCP config and retry, or paste the doc URL of a different format. Skipping this run.

## Step 3: Fetch Doc Content

Call the connected MCP's page/doc-fetch tool with the resolved ID:

- **Notion:** `notion.fetch` or `pages.retrieve` + `blocks.children.list` for body.
- **Atlassian:** `confluence.pages.get` (or equivalent) — request body in storage/representation that preserves headings + lists.
- **Google Docs:** `documents.get` — extract text content + structure.
- **Box / Egnyte:** file content fetch + text extraction (skip binary attachments).

Gather:
- Doc title
- Author (last editor) + last-edited timestamp (if exposed)
- Workspace / space / parent context (e.g., "Notion → Engineering → 2026 Q2")
- Body content as structured text (preserve headings, lists, links — flatten complex blocks)

**Limit:** if the doc is >20KB of extracted text, fetch the first 20KB + note the truncation in the entry metadata. The user can re-invoke with a section anchor (`#heading`) for the tail.

## Step 4: Extract Insights

Read the doc body and identify **knowledge-worthy items** — discrete propositions worth surfacing at next `/audit-knowledge`. Each candidate should be a single self-contained claim, decision, lesson, or question.

For each candidate, classify into one of the standard intake categories:

| Category | Use when |
|---|---|
| `insight` | Observation about how something works, or a learning |
| `decision` | A choice that was made + rationale |
| `extraction` | A pattern, recipe, or how-to worth promoting later |
| `idea` | A "we should consider X" proposition |
| `reference` | A useful URL or external resource named in the doc |

Quality bar: skip items that are project-status updates, ephemeral context, or items already obviously in the knowledge folder. Default to **fewer-but-stronger** — extracting 3 strong items beats 12 weak ones.

## Step 5: Stage to Backlog + Report

For each extracted item, append a new entry to `{knowledge_folder}/intake/insights-backlog.md` (or `decisions-backlog.md` / `extraction-backlog.md` per category; ideas go to `intake/ideas/<date>-<slug>.md` per v2.11.0 per-file convention).

Standard intake entry format (mirrors `/extract` skill output):

```markdown
## <one-line claim or title>

- **Source:** [<doc-title>](<doc-url>) ([<vendor>])
- **Date captured:** <YYYY-MM-DD>
- **Project tags:** <from input args + auto-detected from doc workspace>
- **Original context:** <2-3 sentence excerpt from the doc giving the surrounding context>

<the insight itself, 1-3 sentences, in the user's voice as inferred from the doc>
```

For `idea` candidates (per v2.11.0 per-file convention), write `{knowledge_folder}/intake/ideas/{date}-{slug}.md`:

```markdown
---
date: <YYYY-MM-DD>
project: <tag>
type: <category>
title: <slug-shaped title>
source: <doc-url>
---

**Proposal:** <the idea>

**Motivation:** <why this matters per the doc context>

**Source:** [<doc-title>](<doc-url>) via /extract-doc
```

Report to user:

```
Extracted <N> items from <doc-title> (<vendor>):

| Category | Count | Routed to |
|---|---|---|
| insight | <n> | intake/insights-backlog.md |
| decision | <n> | intake/decisions-backlog.md |
| extraction | <n> | intake/extraction-backlog.md |
| idea | <n> | intake/ideas/<date>-*.md |
| reference | <n> | intake/insights-backlog.md (will route to references/ at audit) |

Next: review at next /audit-knowledge run. The standard disposition vocabulary (Accept → tracker / roadmap / todo / adr / plan / bundle / rule / Defer / Reject) applies.
```

## Rules

- **Never auto-promote.** Items stay in `intake/*-backlog.md` until `/audit-knowledge` routes them.
- **Never modify the source doc.** Read-only externally.
- **Strip secrets if obvious** — same redaction rules as `/clip-thread`.
- **One doc per invocation.** For bulk, use `/intake` with a directory or glob of doc URLs.
- **Default fewer-but-stronger.** Better to surface 3 substantial items for audit than 15 trivial ones — audit cycles cost user attention.

## Notes

- Bidirectional per [ADR-014](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/014-bidirectional-feature-flow.md) — aria-cowork v0.4.0 imports byte-faithfully.
- Output schema is byte-identical across plugins per [ADR-013](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/013-cowork-modified-skills-schema-identical-outputs.md). Both plugins write to the same `insights-backlog.md` / `decisions-backlog.md` / `extraction-backlog.md` / `intake/ideas/*.md` files in the shared knowledge folder.
- Probe semantics per [ADR-015](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/015-capability-probe-pattern.md).
- Composes with `/audit-knowledge` — extracted items follow the same disposition vocabulary as any other intake entry. The `Source:` field is preserved through routing.
- Differs from `/intake doc` mode (v2.17.0+): `/intake doc` captures ONE structured artifact per doc with user-fillable reaction section; `/extract-doc` decomposes a doc into MULTIPLE intake entries for audit routing. Use `/intake doc` when you want to react to a doc as a whole; use `/extract-doc` when the doc contains many discrete items worth surfacing separately.
