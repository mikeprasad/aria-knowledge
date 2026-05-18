---
name: digest
description: Cross-tool rollup of what's pending, what shipped, and what's blocked across chat / email / project tracker / docs. Use when user says "/digest", "/aria-cowork:digest", "weekly digest", "cross-tool rollup", "what's pending across my tools", "summarize this week", "standup digest". Probes all 4 ~~categories and degrades gracefully — produces a.
argument-hint: '[--week | --since YYYY-MM-DD | --until YYYY-MM-DD]'
---

# /digest — Cross-Tool Weekly Rollup

Synthesize a digest of activity across connected MCPs into `intake/digests/{YYYY-MM-DD}.md`. Pulls from `~~chat` + `~~email` + `~~project tracker` + `~~docs` to produce a "what's pending / what shipped / what's blocked" rollup. Composite of all 4 categories — the most cross-tool of the v1.0.0 skills.

## Step 0: Resolve config

The default knowledge folder is `~/Projects/knowledge/` (expand `~` to your home directory's absolute path). Read `<knowledge_folder>/aria-config.md` and extract `knowledge_folder` (the absolute path).

If `aria-config.md` doesn't exist, stop with: *"aria-cowork is not configured. Run `/aria-setup` to get started."*

Lazily create `<knowledge_folder>/intake/digests/` if it doesn't exist.

For all subsequent file operations in this skill, use the absolute path from `knowledge_folder` directly. Cowork resolves absolute paths via the persistent grant from `claude_desktop_config.json` per ADR-008. aria-knowledge in Code uses the same absolute path to reach the same files.

## Step 1: Probe Connected MCPs (all 4 categories)

Check Claude's available tool list for each `~~category`. The digest runs with ANY non-zero set of connected MCPs — gather from whichever are connected, surface gaps for the rest.

| Category | MCP options | Status |
|---|---|---|
| `~~chat` | slack, ms365 | <connected: list / not connected> |
| `~~email` | gmail, ms365 | <connected: list / not connected> |
| `~~project tracker` | linear, asana, atlassian, monday, clickup, notion | <connected: list / not connected> |
| `~~docs` | notion, atlassian, box, egnyte, google docs | <connected: list / not connected> |

If NO MCPs in ANY category are connected, output the standard fallback notice and stop:

> No required MCPs connected for `/digest`. Connect at least one of: Slack/MS365 (~~chat), Gmail/MS365 (~~email), Linear/Asana/etc. (~~project tracker), or Notion/Confluence/etc. (~~docs) via Cowork Settings → Connectors (or Claude Code's `.mcp.json` for the Code surface). See [CONNECTORS.md](../../CONNECTORS.md). Skipping this run.

Per [ADR-015](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/015-capability-probe-pattern.md) — degrade gracefully for missing categories; don't fabricate.

## Step 2: Parse Time Window

Determine the digest window from args:

| Arg | Window |
|---|---|
| (none) or `--week` | Last 7 days (today minus 7) |
| `--since YYYY-MM-DD` | From that date to today |
| `--since YYYY-MM-DD --until YYYY-MM-DD` | Closed range |
| `--month` | Last 30 days |
| `--quarter` | Last 90 days |

Default: 7-day window. State the window explicitly in the digest header.

## Step 3: Gather per Connected Category

For each CONNECTED category, run the appropriate fetch. Skip disconnected categories (note as gaps in the digest output).

### 3a. `~~chat` (if connected)

For Slack: search for messages where the user is mentioned (`@user`) OR is the author, in the time window. Also fetch unresolved threads (the user posted and got no response after 24+ hours).

For MS365 Teams: similar — channel mentions + direct messages.

Gather:
- Mention count per channel
- Top 5-10 threads ranked by reply count or recency
- Threads where the user owes a response (last message is not theirs + question mark or @-mention)

### 3b. `~~email` (if connected)

For Gmail or MS365: search inbox for unread messages in the window, sent items in the window, and emails flagged/starred.

Gather:
- Top 10 sent emails by reply-count (active threads the user drove)
- Unread count by sender
- Flagged / starred items

### 3c. `~~project tracker` (if connected)

For Linear / Asana / Atlassian / Monday / ClickUp / Notion-as-tracker: query for issues assigned to the user with status changes in the window.

Gather (per tool, format-normalized):
- **Pending:** open issues assigned, sorted by priority + last-update
- **Shipped:** issues moved to Done/Closed/Shipped in the window
- **Blocked:** issues with Blocked status, or stale (no update in 7+ days while still Open)
- **Mentions:** issues where the user was mentioned in comments

### 3d. `~~docs` (if connected)

For Notion / Confluence / etc.: list docs touched by the user (created OR edited) in the window. List docs the user was @-mentioned in.

Gather:
- Recently touched (top 10, ordered by edit time)
- Mentions / pages the user was tagged in

## Step 4: Synthesize the Digest

Compose a unified narrative from the gathered data. Sections:

1. **Window & sources** — explicit time window + which MCPs were available + which were not
2. **What's pending** — open items needing the user's action (from project tracker + threads owed responses + unread flagged emails)
3. **What shipped** — closed/completed/moved items in the window (from project tracker + sent emails noting completion + docs marked done)
4. **What's blocked** — items in Blocked status, stale items, threads waiting on others
5. **Cross-tool patterns** — observations that span sources (e.g., "3 mentions of Project Phoenix across chat + tracker but no doc in `~~docs` for it; consider creating one")
6. **Gaps surfaced** — categories that weren't connected + what would be added by connecting them

Be conservative: rank by signal, not volume. A digest with 12 strong items beats 47 noisy ones.

## Step 5: Write + Report

Filename: `intake/digests/{YYYY-MM-DD}.md`. Use today's date (the digest's *creation* date, not the window's end date). If a file with that name exists, append `-2`, `-3` for multiple digests in one day.

Body template:

```markdown
---
date: <YYYY-MM-DD>
window_start: <YYYY-MM-DD>
window_end: <YYYY-MM-DD>
sources_connected: [<list of connected MCP names>]
sources_unavailable: [<list of disconnected categories>]
tags: [digest, weekly|monthly|quarterly]
---

# Digest — <window_start> → <window_end>

## Sources

**Connected:** <list of MCPs that contributed data>
**Not connected:** <list of categories that would have added value> — to fill these gaps, connect the relevant MCP via Cowork Settings → Connectors or Claude Code's `.mcp.json`.

## What's pending

<bulleted list, grouped by source-of-priority. Each item includes a link back to the source if a URL is exposed by the MCP.>

## What shipped

<bulleted list of completed items in the window.>

## What's blocked

<bulleted list of stuck items + brief why.>

## Cross-tool patterns

<observations that span 2+ sources. Skip section if nothing notable.>

## Gaps surfaced

<categories that weren't connected + what they would have added. Skip if all 4 connected.>

---

## Reaction

<intentionally left empty — the user's reaction. /audit-knowledge surfaces this for review.>
```

Report to user:

```
Digest written to intake/digests/<date>.md.

- Window: <start> → <end>
- Sources connected: <N>/4
- Pending items: <n>
- Shipped items: <n>
- Blocked items: <n>

Disconnected categories surfaced N gap callouts in the digest. Connect more MCPs to enrich next week's digest.
```

## Rules

- **Never auto-act on digest content.** This skill READS from MCPs; it does not write back. (For external writes, see `/sync-decisions` — that's the only v1.0.0 skill that writes externally.)
- **Always surface gaps.** If `~~docs` wasn't connected, the digest must say so — don't silently omit categories.
- **Default conservative ranking.** Better 5 strong items per section than 30 weak ones. The digest is for *Mike-reading-on-Sunday-night*, not exhaustive audit.
- **Strip secrets if obvious** — same redaction rules as other skills.
- **Window defaults to 7 days.** Re-invoke with `--month` or `--quarter` for longer rollups (rare; weekly is the standard cadence).

## Notes

- Most expensive of the v1.0.0 skills in terms of MCP calls — calls 4 categories' worth of tools in one invocation. Run cadence: weekly (Sunday or Monday morning), not on every session.
- Bidirectional per [ADR-014](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/014-bidirectional-feature-flow.md) — aria-knowledge v2.18.0 ships an identical body. The Cowork-side context (conversational sessions, more cross-tool synthesis built into the workflow) makes this skill particularly load-bearing on the Cowork side.
- Output schema is byte-identical per [ADR-013](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/013-cowork-modified-skills-schema-identical-outputs.md).
- Probe semantics per [ADR-015](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/015-capability-probe-pattern.md) — graceful degradation built-in for partial-connection scenarios.
- Composes with `/audit-knowledge` — digests are intake artifacts and route through standard audit disposition. Most digests will be `Defer` (interesting but not promotion-worthy) or `Bundle` (cluster patterns across multiple digests for a cross-week insight).
- Inspired by Anthropic's productivity plugin `update --comprehensive` mode, adapted for ARIA's intake-then-audit model rather than productivity's TASKS.md sync model.
