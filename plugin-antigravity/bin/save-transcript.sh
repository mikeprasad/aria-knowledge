#!/bin/sh
# save-transcript.sh — on-demand transcript snapshot for the /snapshot skill.
# Antigravity port: reads transcript path from cache file written by the
# aria-pre-invocation hook (pre-invocation-aria.sh), which captures
# transcriptPath from hook stdin on every model call. The canonical Claude Code
# variant walks ~/.claude/projects/ for the most-recently-modified *.jsonl —
# that directory layout doesn't exist in Antigravity.
# Mirrors the archival logic from the canonical but uses the cached path.
# Bypasses KT_AUTO_CAPTURE — that gate scopes to hook-driven auto capture,
# not explicit user invocation.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

if [ "$KT_CONFIGURED" = "false" ] || [ -n "$KT_CONFIG_ERROR" ]; then
  echo "aria-knowledge is not configured. Run /setup first." >&2
  [ -n "$KT_CONFIG_ERROR" ] && echo "Config error: $KT_CONFIG_ERROR" >&2
  exit 1
fi

if [ ! -d "$KT_KNOWLEDGE_FOLDER" ]; then
  echo "Knowledge folder not found: $KT_KNOWLEDGE_FOLDER" >&2
  exit 1
fi

# Antigravity port: locate transcript via the cache file written by the
# aria-pre-invocation hook on every model call. If the cache doesn't exist,
# the hook hasn't fired yet — user needs to let the agent respond once first.
TRANSCRIPT_CACHE="$HOME/.gemini/antigravity/.last-transcript-path"
if [ ! -f "$TRANSCRIPT_CACHE" ]; then
  echo "Transcript cache not found at $TRANSCRIPT_CACHE" >&2
  echo "The aria-pre-invocation hook writes this file before each model call." >&2
  echo "Let the agent respond to one message first, then re-run /snapshot." >&2
  exit 1
fi

TRANSCRIPT_PATH=$(cat "$TRANSCRIPT_CACHE")
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo "Transcript file not found at ${TRANSCRIPT_PATH:-<empty>} (cache may be stale)" >&2
  echo "Cache: $TRANSCRIPT_CACHE" >&2
  exit 1
fi

# Derive a short identifier from the transcript filename for the snapshot name.
# Antigravity transcript files are typically named transcript.jsonl or include
# a conversation id; fall back to a timestamp if neither yields a clean id.
SESSION_ID=$(basename "$TRANSCRIPT_PATH" .jsonl)
SESSION_SHORT=$(printf '%s' "$SESSION_ID" | cut -c1-8)
TODAY=$(date +%Y-%m-%d)

CAPTURES_DIR="$KT_KNOWLEDGE_FOLDER/intake/pre-compact-captures"
mkdir -p "$CAPTURES_DIR" 2>/dev/null

SNAPSHOT_FILE="$CAPTURES_DIR/${TODAY}_${SESSION_SHORT}.md"

if ! cp "$TRANSCRIPT_PATH" "$SNAPSHOT_FILE" 2>/dev/null; then
  echo "Failed to write snapshot to $SNAPSHOT_FILE" >&2
  exit 1
fi

echo "Transcript snapshot saved → $SNAPSHOT_FILE"
echo "Source: $TRANSCRIPT_PATH"
echo "Run /extract now (in-context), or /audit-knowledge will review this snapshot at the next audit cycle."
