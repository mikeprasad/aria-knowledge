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
bash ${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/bin/save-transcript.sh
```

The script:
1. Reads `~/.claude/aria-knowledge.local.md` via `config.sh` — stops with a setup message if unconfigured.
2. Locates **this** session's transcript by session id: `$CLAUDE_CODE_SESSION_ID` (set by Claude Code in Bash tool shells), then the id passed as the argument above, matched to `~/.claude/projects/<project>/<id>.jsonl`. If an id is known but no transcript matches, it exits 1 and writes nothing — it never falls back to another session's file. Only when no id is available at all (older Claude Code) does it take the most recently written top-level transcript, and then it prints a `⚠ GUESSED` line.
3. Copies it to `{knowledge_folder}/intake/pre-compact-captures/{YYYY-MM-DD}_{session-id-8-chars}.md`.
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

Concurrent Claude Code sessions are safe: the script copies the transcript whose filename is this session's id, not the most recently written one. (Before this, it picked the newest `*.jsonl`, which with several sessions live was often another session's — and it still reported success.)

If the output contains `⚠ GUESSED`, no session id reached the script and it fell back to the newest transcript. Compare the `Source:` id with your own session; if they differ, relay that to the user and do not delete the captured file — it is a valid snapshot of another session that may have no other record. To capture the right one, copy `~/.claude/projects/<project>/<your-session-id>.jsonl` to `intake/pre-compact-captures/<YYYY-MM-DD>_<first-8-chars>.md`.
