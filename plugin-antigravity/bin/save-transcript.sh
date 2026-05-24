#!/bin/sh
# save-transcript.sh — on-demand transcript snapshot for the /snapshot skill.
# Mirrors the archival logic from pre-compact-check.sh but is invoked
# explicitly by the user. Bypasses KT_AUTO_CAPTURE — that gate scopes to
# hook-driven auto capture, not explicit user invocation.

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

# Locate the current session's transcript. Claude Code does not expose session
# id or transcript path to skill-invoked shells, so we pick the most recently
# modified *.jsonl under ~/.claude/projects. ls -t is seconds-granular, which
# is ambiguous when multiple Claude Code windows write in the same second;
# stat -f "%Fm" gives fractional seconds on macOS and reliably disambiguates.
TRANSCRIPT_PATH=$(find "$HOME/.claude/projects" -name '*.jsonl' -type f 2>/dev/null \
  | while IFS= read -r f; do stat -f "%Fm %N" "$f" 2>/dev/null; done \
  | sort -rn | head -1 | cut -d' ' -f2-)

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo "No transcript file found under ~/.claude/projects" >&2
  exit 1
fi

# Claude Code names transcript files by session UUID, so the basename is the
# session id — matches the hook's SESSION_ID format.
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
