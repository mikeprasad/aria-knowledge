---
description: "Save the current Antigravity transcript to the knowledge intake on demand. Use when user says '/snapshot', 'snapshot the session', 'save this conversation', 'capture the transcript', or 'archive this session'. Same archival output as the canonical pre-compact hook, but explicit because Antigravity has no PreCompact event. Distinct from /extract and /intake."
---

# /snapshot — On-Demand Transcript Snapshot (Antigravity)

Archive the current Antigravity conversation transcript to `intake/pre-compact-captures/` for later review. The mechanism differs from the Claude Code variant: Antigravity puts the conversation transcript at a single known path delivered via hook stdin (`transcriptPath`), not in a per-cwd directory of jsonl files.

## How the transcript is located

The `aria-pre-invocation` hook (fires before every model call) caches `transcriptPath` from its stdin payload to `~/.gemini/antigravity/.last-transcript-path`. This skill reads that cache.

If the cache doesn't exist yet, the most likely cause is that the agent hasn't completed a model call in this session — `transcriptPath` only becomes available once the pre-invocation hook has fired at least once. Solution: have the agent respond to one message first, then re-run `/snapshot`.

## When to use this vs. /extract vs. /intake

- **/snapshot** — raw archive, no synthesis. Use before switching context, before a risky operation, or any time you want the full conversation preserved.
- **/extract** — synthesizes knowledge from the current conversation into backlogs/ideas. Use when you want captured *insights*, not the full transcript.
- **/intake** — captures a single URL or snippet (clip-whole), or scans files/URLs. Unrelated to session transcripts.

`/snapshot` is intentionally orthogonal: it preserves the raw record so `/extract` (or a human review) can work from it later.

## Step 1: Run the Helper

Execute:

```
bash ${CLAUDE_PLUGIN_ROOT}/bin/save-transcript.sh
```

The script (port-specific behavior):
1. Reads `~/.gemini/antigravity/aria-knowledge.local.md` via `config.sh` — stops with a setup message if unconfigured.
2. Reads `~/.gemini/antigravity/.last-transcript-path` to locate the current conversation transcript. If the cache file doesn't exist, exits with a clear "no transcript cached yet — let the pre-invocation hook fire first" message.
3. Copies the transcript to `{knowledge_folder}/intake/pre-compact-captures/{YYYY-MM-DD}_{conversationId-8-chars}.md` (using the conversationId from the transcript itself, or falling back to a timestamp).
4. Prints the snapshot path, the source transcript path, and pointers to the two review paths — `/extract` for in-context synthesis now, or `/audit-knowledge` which will review the snapshot at the next audit cycle.

## Step 2: Relay the Output

Print the script's stdout to the user verbatim. The path and source filename are both useful for verification.

If the script exits non-zero, relay the stderr message. Common causes:
- `aria-knowledge is not configured` → user needs to run `/setup`
- `Knowledge folder not found` → folder was moved or deleted; `/setup` repairs it
- `Transcript cache not found at ~/.gemini/antigravity/.last-transcript-path` → pre-invocation hook hasn't fired yet (let the agent respond once, then re-try) OR the hook is disabled (check Customizations panel)
- `Transcript file not found at <path>` → cache points to a file that no longer exists; the conversation may have been compacted or moved

## Rules

- **Bypasses `auto_capture`.** The `auto_capture` config key in the canonical port scopes to the pre-compact hook (which doesn't exist in Antigravity). `/snapshot` is explicit user intent and always runs.
- **Overwrites same-conversation repeats.** Re-running `/snapshot` in the same conversation overwrites the previous snapshot (same `{date}_{conv-id-8}.md` filename). If you need multiple snapshots, copy the file aside manually before re-running.
- **One invocation, one file.** No arguments, no options.

## Antigravity vs. Claude Code parity note

In Claude Code, `/snapshot` walks `~/.claude/projects/{cwd-encoded}/*.jsonl` and picks the most-recently-modified file — this distinguishes concurrent windows. In Antigravity, each workspace has one persistent `transcript.jsonl` so the disambiguation isn't needed; the cached transcriptPath always points to *this* conversation's transcript.
