---
description: "Save the current Claude Code transcript to the knowledge intake on demand. Use when user says '/snapshot', 'snapshot the session', 'save this conversation', 'capture the transcript', 'archive this session'. Same archival output as the pre-compact hook, but triggered explicitly. Distinct from /extract (which synthesizes knowledge) and /intake (which captures a URL or snippet). (Code port — ADR-094.)"
allowed-tools: Bash
---

# /snapshot — On-Demand Transcript Snapshot

Archive the current session's raw transcript to `intake/pre-compact-captures/` for later review. This is the same artifact the pre-compact hook produces — just invoked by the user instead of waiting for compaction.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/snapshot` resolves to this skill — aria-knowledge (Code) is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. The Cowork variant is namespaced-only: `/aria-cowork:snapshot`.

**Before Step 0:** Check that the `Bash` tool is available in this session. If `Bash` is NOT available (you are running in Claude Cowork or another non-Code runtime), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/snapshot` from a non-Code runtime.**
>
> This variant requires Bash to run `save-transcript.sh` against `~/.claude/projects/{cwd-encoded}/{session-id}.jsonl` — Cowork has neither shell access nor that transcript path. For the Cowork-native variant (uses 3-path source acquisition: transcript MCP → user-paste → Claude-recall fallback), use `/aria-cowork:snapshot`.
>
> **Use `/aria-cowork:snapshot` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `aria-cowork:snapshot` with the same arguments the user provided to this invocation. Do not proceed with this skill's steps; the cowork variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-knowledge) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args.

If `Bash` is available, proceed to Step 0.

## When To Use This vs. /extract vs. /intake

- **/snapshot** — raw archive, no synthesis. Use before switching context, before a risky operation, or any time you want the full conversation preserved.
- **/extract** — synthesizes knowledge from the current conversation into backlogs/ideas. Use when you want captured *insights*, not the full transcript.
- **/intake** — captures a single URL or snippet (clip-whole), or scans files/URLs. Unrelated to session transcripts.

`/snapshot` is intentionally orthogonal: it preserves the raw record so `/extract` (or a human review) can work from it later.

## Step 1: Run The Helper

Execute:

```
bash ${CLAUDE_PLUGIN_ROOT}/bin/save-transcript.sh
```

The script:
1. Reads `~/.claude/aria-knowledge.local.md` via `config.sh` — stops with a setup message if unconfigured.
2. Locates the current session's transcript by picking the most recently modified `*.jsonl` under `~/.claude/projects` (fractional-second mtime, to disambiguate concurrent Claude Code windows).
3. Copies it to `{knowledge_folder}/intake/pre-compact-captures/{YYYY-MM-DD}_{session-id-8-chars}.md`.
4. Prints the snapshot path, the source transcript path, and pointers to the two review paths — `/extract` for in-context synthesis now, or `/audit-knowledge` which will review the snapshot at the next audit cycle via digest mode.

## Step 2: Relay The Output

Print the script's stdout to the user verbatim. Do not paraphrase — the path and source filename are both useful for verification (see "Concurrent Sessions" below).

If the script exits non-zero, relay the stderr message. Common causes:
- `aria-knowledge is not configured` → user needs to run `/setup`
- `Knowledge folder not found` → folder was moved or deleted; `/setup` repairs it
- `No transcript file found` → shouldn't happen in a live session; surface it verbatim

## Rules

- **Bypasses `auto_capture`.** The `auto_capture` config key scopes to hook-driven auto capture. `/snapshot` is explicit user intent and always runs regardless of that flag.
- **Overwrites same-session repeats.** Re-running `/snapshot` in the same session and date overwrites the previous snapshot (same `{date}_{sid8}.md` filename). This matches the pre-compact hook behavior. If you need multiple snapshots, copy the file aside manually before re-running.
- **One invocation, one file.** No arguments, no options. The script picks the transcript; the user verifies via the output path.

## Concurrent Sessions

If you have multiple Claude Code windows open on the same machine, the script picks the most-recently-written transcript. In practice this is the window you invoked `/snapshot` in, because the tool call itself just wrote to that file. The source path is shown in the output so you can verify the right session was captured. If it picked the wrong one, the fix is to run `/snapshot` again from the intended window after a small new interaction (to make that session's transcript the newest).
