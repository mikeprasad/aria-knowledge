---
name: snapshot
description: 'Save a snapshot of the current Cowork conversation to the knowledge intake on demand. Use when user says "/aria-cowork:snapshot", "snapshot the session", "save this conversation", "capture the transcript", "archive this session". Schema-identical to aria-knowledge''s /snapshot output, but with cowork-specific source acquisition (no. (Cowork variant — namespaced-only.)'
---

# /snapshot — On-Demand Session Snapshot (cowork variant)

Archive a snapshot of the current Cowork conversation to `intake/pre-compact-captures/` for later review. Same on-disk shape as aria-knowledge's /snapshot output — both plugins' `/audit-knowledge` can read snapshots from this directory regardless of which plugin wrote them.

**Cowork variant of aria-knowledge's `/snapshot`.** Output schema (path, frontmatter, body format) byte-aligned where possible. Source acquisition differs significantly — Cowork has no `~/.claude/projects/{cwd-encoded}/{session-id}.jsonl` access per probe 12 + Cowork-runtime constraints. Item #14 locks define a **3-path source acquisition chain**:

1. **Cowork transcript MCP** (if exposed at invocation time) — verbatim transcript
2. **User-paste** — verbatim user-supplied content
3. **Claude-recall fallback** — Claude writes a structured recall-based snapshot from current context

Path 1 is preferred when available. Path 2 is the typical case. Path 3 is the last-resort fallback when paste is declined or impractical.

**No hook companion in cowork.** aria-knowledge's `/snapshot` has a pre-compact-check.sh hook that auto-invokes /snapshot before context compaction. Cowork has no hook layer (per ADR-001 + ADR-004), so /snapshot is manual-invoke only. Invoke before expected compaction events, before risky operations, before switching context, or any time you want the conversation preserved.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Cowork variant — namespaced-only. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/snapshot` resolves to aria-knowledge's variant — Code is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. To reach this skill, use the namespaced form: `/aria-cowork:snapshot`. Do NOT match bare `/snapshot` — that belongs to aria-knowledge.

**Before Step 0:** Check whether the `Bash` tool is available in this session. If `Bash` IS available (you are running in Claude Code or another runtime with shell access), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-cowork's `/snapshot` from a runtime with shell access.**
>
> This variant uses 3-path source acquisition (transcript MCP → user-paste → Claude-recall) because Cowork lacks the `~/.claude/projects/.../jsonl` path. For the Code-native variant (reads raw transcript directly via `save-transcript.sh`), use `/snapshot` (the aria-knowledge canonical).
>
> **Use `/snapshot` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `snapshot` (the bare-slash canonical, which routes to aria-knowledge when both ports are loaded) with the same arguments the user provided to this invocation. Do not proceed with this skill's steps; the aria-knowledge variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-cowork) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args.

If `Bash` is NOT available (normal Cowork runtime), proceed to Step 0.

## When to use this vs `/extract` vs `/clip`

- **/snapshot** — raw archive (or structured recall when raw unavailable), no synthesis. Use before switching context, before a risky operation, or any time you want the full conversation preserved.
- **/extract** — synthesizes knowledge from the current conversation into backlogs/ideas. Use when you want captured *insights*, not the full transcript.
- **/clip** — saves a single URL or snippet. Unrelated to session transcripts.

`/snapshot` is intentionally orthogonal: it preserves the raw record (or best-available approximation) so `/extract` (or a human review) can work from it later.

## Step 0: Resolve config

The default knowledge folder is `~/Projects/knowledge/` (expand `~` to your home directory's absolute path). Read `<knowledge_folder>/aria-config.md` and extract `knowledge_folder`. If `aria-config.md` doesn't exist, stop: *"aria-cowork is not configured. Run `/aria-setup` to get started."*

Use `<knowledge_folder>` for all file operations during this session.

## Step 1: Determine snapshot identifier

Compute the snapshot filename: `<knowledge_folder>/intake/pre-compact-captures/{YYYY-MM-DD}_{identifier}.md`.

- `{YYYY-MM-DD}` — today's date.
- `{identifier}` — pick the first available of:
  - **Cowork session ID** (if reachable via MCP — typically 8-character truncated form like `a1b2c3d4`)
  - **Unix timestamp suffix** (e.g., `1715990400`) when no session ID is available
  - **Manual user-provided label** if the user supplies one via natural-language prompt (e.g., *"snapshot as 'stakeholder-prep-q3'"*)

**Collision handling:** if the target file already exists for the same date + identifier, append `-2`, `-3`, etc. to the identifier until unique. Mirrors aria-knowledge's overwrite-same-session behavior except cowork preserves prior snapshots (cowork has fewer snapshots due to no hook auto-creation; preserving them avoids accidental loss).

**Folder creation:** if `<knowledge_folder>/intake/pre-compact-captures/` does not exist, create it lazily on first /snapshot invocation. This folder was historically Code-only (aria-knowledge's hook wrote there exclusively); v0.3.0 makes it a shared folder both plugins can write to.

## Step 2: Source acquisition (3-path chain)

### Path 1: Cowork transcript MCP (preferred — if exposed)

Probe at invocation time for a Cowork MCP tool that exposes the current session's transcript. Common candidate names: `mcp__session_info__read_transcript`, `mcp__session_info__get_current`, or similar.

- **If a current-session transcript MCP is found:** invoke it; capture the returned transcript verbatim. Record the source as Path 1 (MCP). Skip to Step 3.
- **If the MCP returns "Session not found" or similar for current session** (per the 2026-04-30 probe finding): fall through to Path 2.
- **If no such MCP is available:** fall through to Path 2.

This probe is invocation-time, not setup-time — Cowork's MCP catalog may evolve, and this skill is meant to opportunistically use newer surfaces as they ship.

### Path 2: User-paste (typical case)

Prompt the user:

> *"Cowork doesn't expose a current-session transcript MCP from this conversation. To capture the verbatim conversation, paste it below. Or press enter to use a structured recall-based snapshot instead.*
>
> *Paste conversation here (or press enter to skip):*"

If the user pastes content:
- Capture the pasted content verbatim. Record the source as Path 2 (user-paste). Skip to Step 3.
- Don't validate paste content — accept whatever the user provides (could be partial, could be JSON-shaped, could be plain text). The user knows what they want preserved.

If the user presses enter without pasting (or replies "no" / "skip"):
- Fall through to Path 3.

### Path 3: Claude-recall fallback

When neither MCP nor paste produces content, Claude writes a structured recall-based snapshot from current context. This is approximation — Claude's working memory of the conversation, not a verbatim transcript.

Compose a structured snapshot body with these sections (per #14n):

```markdown
## Conversation Summary
{2-3 sentence overview of what was discussed and the outcome.}

## Decisions Surfaced
- {Each significant decision made or surfaced in the conversation, one bullet per decision.}
- {If none, omit this section entirely.}

## Action Items / Next Steps
- {Each concrete next-step or action item flagged during conversation.}
- {If none, omit this section entirely.}

## Open Questions / Unresolved Threads
- {Each open question or unresolved item flagged during conversation.}
- {If none, omit this section entirely.}

## Knowledge Candidates Noticed
- {Topics worth /extract'ing — pointer to /extract for downstream capture.}
- {If none, omit this section entirely.}
```

Record the source as Path 3 (Claude-recall). This is approximation by nature; downstream consumers should treat the snapshot as lossy.

## Step 3: Write snapshot file

Write to `<knowledge_folder>/intake/pre-compact-captures/{YYYY-MM-DD}_{identifier}.md` with this shape:

```markdown
---
captured_at: {ISO 8601 timestamp at invocation}
session_id: {Cowork session ID if Path 1 succeeded; otherwise omit}
cwd: {Cowork attached folder path if available; else "cowork-attached-folder"}
claude_version: {model identifier if accessible via MCP; else omit}
---

> Source: {Cowork transcript MCP | user-paste | Claude-recall fallback}

# Session snapshot — {YYYY-MM-DD}

{Body content per source path above.}
```

**Schema-identical guarantee (per #14i):** the frontmatter + body shape match aria-knowledge's /snapshot output where possible. Downstream consumers (cowork's `/audit-knowledge` Step 2d, aria-knowledge's `/audit-knowledge` Step 2d) see the same file structure regardless of source. Optional fields (`session_id`, `claude_version`) are omitted when not available — this matches aria-knowledge's tolerance for optional frontmatter fields.

**No `capture_source:` frontmatter field** (per #14e + v0.2.4 precedent): the body-source attribution lives in the body header (visible to human readers), not in frontmatter (no current consumer requires it; item #4d's full-archive policy makes the source distinction irrelevant for audit routing).

## Step 4: Report

Output a brief confirmation:

```
## Snapshot saved

- **Path:** <knowledge_folder>/intake/pre-compact-captures/{YYYY-MM-DD}_{identifier}.md
- **Source:** {Path label}
- **Size:** {byte-count or line-count if computable}

To synthesize knowledge from this snapshot, run `/aria-cowork:extract` now (in this session) or `/aria-cowork:audit-knowledge` later (will review the snapshot at the next audit cycle via digest mode).
```

If `intake/pre-compact-captures/` was just lazy-created, note that in the report: *"First snapshot in this knowledge folder — created `intake/pre-compact-captures/` directory."*

## Failure modes and recovery

- **Cowork's persistent grant doesn't cover the knowledge folder:** /snapshot stops with the same diagnostic as `/aria-setup` Step 1b's access probe. User re-runs `/aria-setup` to verify grant.
- **User pastes content that's clearly not a conversation** (e.g., a single URL, random text): accept it anyway — `/audit-knowledge` will dispose it at next audit. Don't second-guess paste content.
- **All 3 source paths fail** (rare — Claude-recall always succeeds in principle): fall back to writing a minimal placeholder snapshot noting all 3 paths were unavailable. This shouldn't happen in practice; if it does, flag as a bug.

## Rules

- **Manual-invoke only** — no hook companion in cowork. Develop the habit of running /snapshot before context switches, before risky operations, or at session-end.
- **Schema-identical output** — same on-disk shape as aria-knowledge's /snapshot. Both plugins' /audit-knowledge can audit snapshots from this directory.
- **Source attribution in body, not frontmatter** — the body's first non-frontmatter line is `> Source: {path}` so human readers know whether the snapshot is verbatim (Path 1/2) or approximate (Path 3). No metadata frontmatter field for this.
- **Never overwrite** — if a snapshot for the same date+identifier exists, append `-2`, `-3` etc. to the identifier. Cowork snapshots are rarer than aria-knowledge's (no hook auto-creation); preserve each one explicitly.
- **Lazy folder creation** — `intake/pre-compact-captures/` is created on first /snapshot invocation, not bootstrapped on `/aria-setup`. This avoids creating empty folders for users who never invoke /snapshot.
- **Approximation honesty** — when Path 3 (Claude-recall) is used, the body sections describe approximation, not verbatim record. Don't pretend recall content is a transcript.
- **Use Cowork's native I/O** — never invoke a Filesystem MCP connector (per ADR-003). Transcript MCPs (Path 1 probe) are a different category — they're session-state surfaces, not filesystem.
