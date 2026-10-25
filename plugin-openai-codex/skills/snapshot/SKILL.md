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
bash "${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/bin/save-transcript.sh"
```

The script:
1. Reads `~/.claude/aria-knowledge.local.md` via `config.sh` — stops with a setup message if unconfigured.
2. Locates **this** session's rollout by thread id: `$CODEX_THREAD_ID` (set by Codex in every shell command it runs), then an id passed as an argument, matched to `${CODEX_HOME:-~/.codex}/sessions/YYYY/MM/DD/rollout-<timestamp>-<id>.jsonl`, and confirmed against that file's first `session_meta` record. If an id is known but no rollout matches (or its `session_meta` names another thread), it exits 1 and writes nothing — it never falls back to another session's file. Only when no id is available at all does it take the most recently written rollout, and then it prints a `⚠ GUESSED` line.
3. Copies it to `{knowledge_folder}/intake/pre-compact-captures/{YYYY-MM-DD}_{last-8-chars-of-thread-id}.md`. Codex thread ids are UUIDv7 and begin with a timestamp, so sessions started close together share their first characters; the last 8 are random, which keeps two sessions from overwriting each other's capture. The pre-compact and subagent capture hooks name files the same way.
4. Prints the snapshot path, the source transcript path, and pointers to the two review paths — `/extract` for in-context synthesis now, or `/audit knowledge` which will review the snapshot at the next audit cycle via digest mode.

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

Concurrent Codex sessions are safe: the script copies the rollout whose filename and `session_meta` carry this thread's id, not the most recently written one. (Before 2.57.4-codex.1 it searched Claude Code's `~/.claude/projects`, found nothing for a Codex thread, and fell back to the newest Claude Code transcript.)

If the output contains `⚠ GUESSED`, no thread id reached the script and it fell back to the newest rollout. Compare the `Source:` id with your own thread (`echo "$CODEX_THREAD_ID"`); if they differ, relay that to the user and do not delete the captured file — it is a valid snapshot of another session that may have no other record. To capture the right one, copy `~/.codex/sessions/YYYY/MM/DD/rollout-*-<your-thread-id>.jsonl` to `intake/pre-compact-captures/<YYYY-MM-DD>_<last-8-chars>.md`.
