---
description: "NOTE: this skill requires connected ~~docs MCPs with WRITE access (Notion, Confluence, Google Docs), which are typically only present in Cowork — the Code variant exists for parity but most users will want the Cowork variant. Mirror approved decisions from the knowledge folder out to a connected ~~docs MCP (Notion, Confluence, Google Docs). Use when user says '/sync-decisions', 'mirror decisions to Notion', 'push decisions to wiki', 'sync ADRs to Confluence', 'export decisions externally'. WRITE-side skill — embeds Rule 22 advisory preamble per ADR-016 and requires explicit per-write go-gate. Logs each sync to logs/sync-decisions.md."
---

# /sync-decisions — Mirror Decisions to External Docs

Read approved decisions from `{knowledge_folder}/decisions/` and write them out to a connected `~~docs` MCP destination (a Notion page, Confluence space, Google Doc, etc.). The only v2.18.0 skill that writes externally; embeds Rule 22 advisory preamble per [ADR-016](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/016-rule-22-advisory-preamble-for-external-writes.md).

## Step 0: Resolve Config

Read `~/.gemini/antigravity/aria-knowledge.local.md` and extract `knowledge_folder`. If the file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Verify `{knowledge_folder}/decisions/` exists. If not, stop: "No decisions/ folder found. Nothing to sync."

Lazily create `{knowledge_folder}/logs/sync-decisions.md` if it doesn't exist (used by Step 7 for sync history).

## Step 1: Probe Connected MCPs

Check Claude's available tool list for `~~docs` MCPs that support WRITE operations:

- **`~~docs`** (notion, atlassian, box, egnyte, google docs): if connected, check the MCP's exposed tools — `~~docs` MCPs that only expose `read_page` / `search_pages` are READ-ONLY for this skill's purpose. Need a write surface (`create_page`, `update_page`, `append_block_children`, or equivalent).

If NO `~~docs` MCP with write capability is connected, output the standard fallback notice and stop:

> No required MCPs connected for `/sync-decisions`. This skill writes externally — needs a `~~docs` MCP with write capability (page creation or block append). Connect Notion, Atlassian (Confluence), Box, Egnyte, or Google Docs via Claude Code's MCP config (or Cowork Settings → Connectors). See [CONNECTORS.md](../../CONNECTORS.md). Skipping this run.

Per [ADR-015](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/015-capability-probe-pattern.md).

## Step 2: Enumerate Decisions to Sync

Determine which decisions are candidates based on args:

| Arg | Candidates |
|---|---|
| (none) | All decisions whose `synced_to_~~docs:` frontmatter field is absent OR older than file's last-modified time |
| `<decision-slug>` | Just the named decision (e.g., `/sync-decisions 069-karpathy-4-line-foundation`) |
| `--all` | Every decision in `decisions/`, regardless of prior sync state |
| `--since YYYY-MM-DD` | Decisions modified or created on/after that date |

Read each candidate decision file from `{knowledge_folder}/decisions/`. Cache them in working memory.

If zero candidates: report "No decisions need syncing" and stop.

## Step 3: Resolve Sync Target

Determine the destination on the `~~docs` MCP side. Args + heuristics:

| Source of target | Used when |
|---|---|
| `--target <space-or-page-url>` from args | User specified |
| `sync_target:` frontmatter field on the decision | Decision specifies own target |
| `default_sync_target` from aria-knowledge.local.md (if set) | User has a global default |
| Ask user interactively | None of above resolved |

If target resolution requires asking the user, present:

```
Which destination?

- (a) Existing page URL: paste the ~~docs page URL where decisions should be appended
- (b) New top-level page: I'll create `aria-knowledge-decisions` (or a name you provide) in the workspace root
- (c) Cancel this sync run

Decision-specific syncs (where decisions/<slug>.md has its own `sync_target:` field) override this; this prompt only fires for decisions without a per-file target.
```

If no target resolvable + no interactive answer, abort with clear message: "No sync target resolvable. Set `default_sync_target` in aria-knowledge.local.md or invoke with `--target <url>`."

## Step 4: Rule 22 Advisory Preamble (per ADR-016)

For EACH candidate decision, walk through this checklist:

```
Before each external write — Rule 22 advisory checklist

This skill writes to an external system. aria-knowledge's PreToolUse hook gates Edit/Write but does NOT catch MCP write tools — Rule 22 here is text-only discipline per ADR-016.

1. **State the change in one sentence.** "Writing decision <slug> to <target-url-or-page-title>."

2. **Why this destination?** Is this the right audience for this decision content? Could it leak into a view the user didn't intend (public workspace, wrong project, wrong channel)?

3. **Reversibility check.** Can the user edit/delete the write from <vendor> after it lands? (For Notion / Confluence / Google Docs: YES, user can edit at destination. For Box / Egnyte: depends on workspace permissions. Note any constraint explicitly.)

4. **Surface for explicit go.** Present the full proposed write content + destination. Wait for explicit user `yes` / `go` before calling the write tool.
```

Concretely: for each decision, surface this block to the user:

```
Decision: <slug>
Source file: decisions/<slug>.md
Destination: <target-url-or-page-title> on <vendor>
Operation: <create new page | append to existing page | update existing page>
Reversibility: <user can edit at destination: yes/no/constrained>

--- Proposed write content (preview) ---

<the full decision content as it will appear externally — markdown if Notion/Confluence; plaintext if Google Doc; etc.>

--- End preview ---

Ready to write? (yes / no / edit)
```

## Step 5: Per-Decision Go-Gate

Wait for the user's explicit response:

- **`yes` / `go`:** proceed to Step 6 for THIS decision.
- **`no` / `skip`:** mark this decision as skipped in the sync log; move to the next candidate.
- **`edit`:** ask the user what to change in the preview content, regenerate, re-present, ask again.
- **`yes to all writes` (literal):** authorize this AND all remaining decisions in the candidate list without per-decision confirmation. This is the ONLY way to batch — explicit user opt-in per ADR-016. The exact phrase "yes to all writes" must appear in the user's reply; partial forms like "yes to all" or "yes all" do NOT trigger the batch carve-out (per the retro 2026-05-19 finding aligning SKILL.md to ADR-016's literal-phrase requirement).
- **`cancel`:** abort the entire sync run; nothing else gets written.
- **(silence or non-matching reply):** treat as `no`; re-prompt.

Per ADR-016: "Do NOT proceed on implicit consent. Do NOT batch multiple writes behind a single `yes` unless the user explicitly says 'yes to all writes' in this invocation."

## Step 6: Execute Write

Call the connected `~~docs` MCP's write tool with the resolved target + proposed content.

For each MCP:
- **Notion:** `pages.create` (new page) or `blocks.children.append` (append to existing page). Set `parent` to the target page; populate `properties.title` from decision title.
- **Atlassian (Confluence):** `confluence.pages.create` or `confluence.pages.update`. Set `space` + `parent` per target.
- **Google Docs:** `documents.batchUpdate` with InsertText requests appending to the target doc.
- **Box / Egnyte:** create a new doc file (typically `.md` or `.txt`) at the resolved path; vendor-specific tool name.

On success, capture:
- The destination URL / ID returned by the MCP
- The timestamp of the write
- The size of the write

On failure, surface the error and ask the user: continue with remaining decisions? Abort?

## Step 7: Update Frontmatter + Log

For each successfully synced decision:

**Update the decision file's frontmatter** to record the sync — add or update:

```yaml
synced_to_~~docs:
  - target: <destination URL>
    vendor: <notion|atlassian|box|egnyte|google docs>
    synced_at: <ISO timestamp>
    operation: <create|append|update>
```

This is the only modification to the source file — content is unchanged; only frontmatter records the sync state.

**Append to `logs/sync-decisions.md`:**

```markdown
## <YYYY-MM-DD HH:MM> — <vendor>

- **<decision-slug>** → [<destination URL>](<destination URL>) (<operation>)
  Source: `decisions/<slug>.md`
  Size: <N> chars

<repeat per synced decision>
```

If a decision was skipped (`no` response), log it too with `status: skipped` for audit traceability.

## Step 8: Report

Summary to user:

```
Sync complete: <N synced> / <N skipped> / <N failed>

Synced to <vendor> (<target>):
- <slug>: [<destination URL>](<destination URL>) <create|append>
- <slug>: ...

Skipped (user declined):
- <slug>
- <slug>

Failed (MCP errors):
- <slug>: <error message>

Sync log: logs/sync-decisions.md
```

## Rules

- **Never batch without explicit user opt-in.** The "yes to all writes" path requires the literal 4-word phrase per ADR-016. Partial forms (e.g., "yes to all", "yes all", "go all") do NOT trigger the batch carve-out.
- **Never modify the decision body.** Only the `synced_to_~~docs:` frontmatter field changes locally; the markdown body is untouched.
- **Never delete a destination page.** This skill creates / appends / updates only — destination cleanup is the user's responsibility at the vendor side.
- **Strip secrets if obvious** — same redaction rules as other skills. If a decision body contains what look like API keys / tokens, redact before write + surface in preview.
- **One sync target per invocation.** If the user wants different decisions to go to different targets, run `/sync-decisions <slug> --target <url1>` then `/sync-decisions <other-slug> --target <url2>`.
- **Log every attempt.** Success, skip, or failure — all go in `logs/sync-decisions.md` for audit traceability.

## Notes

- **First WRITE-side skill in either ARIA plugin.** Embedding the Rule 22 advisory preamble verbatim per [ADR-016](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/016-rule-22-advisory-preamble-for-external-writes.md). Future write-side skills MUST embed the same preamble.
- Bidirectional per [ADR-014](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/014-bidirectional-feature-flow.md) — aria-cowork v0.4.0 imports byte-faithfully. The advisory preamble template is identical across plugins; the only divergence is the Step 0 config path resolution.
- Output schema is byte-identical per [ADR-013](https://github.com/mikeprasad/knowledge/blob/main/projects/aria-cowork/decisions/013-cowork-modified-skills-schema-identical-outputs.md). Both plugins write to the same shared `logs/sync-decisions.md` + update the same `synced_to_~~docs:` frontmatter shape.
- The `synced_to_~~docs:` frontmatter convention is **new in v2.18.0**. Documented in `CONFIG.md` schema section (added in Phase 3a).
- Composes with `/audit-knowledge` — synced decisions are no different from unsynced for audit purposes. The `synced_to_~~docs:` field is informational, not consumed by audit routing.
- **Does NOT replace `_project-knowledge/` git-based team sharing.** That mechanism (v2.13.0) is for per-repo team-mate sharing; `/sync-decisions` is for org-wide wiki / docs publishing. Both can run in parallel.
- Future direction (post-v2.18.0): a `/sync-rules` or `/sync-references` skill could follow the same pattern if external mirroring of other knowledge artifacts is wanted. ADR-016's preamble template ports forward.
