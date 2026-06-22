---
name: snapshot
description: "Save the current Codex or shared ARIA session transcript snapshot to the knowledge intake for later audit. Trigger on /snapshot, snapshot the session, or save this conversation."
allowed-tools: Bash
---

# /snapshot — On-Demand Transcript Snapshot

Archive the current session's raw transcript to `intake/pre-compact-captures/` for later review. This is the same artifact the pre-compact hook produces — just invoked by the user instead of waiting for compaction.

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
