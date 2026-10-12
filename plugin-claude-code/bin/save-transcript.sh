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

# Locate THIS session's transcript by its session id. Claude Code sets
# CLAUDE_CODE_SESSION_ID in Bash tool subprocesses; the /snapshot skill also
# passes its ${CLAUDE_SESSION_ID} substitution as $1. Both are tried, env first:
# on --continue / --resume without an id the env var may hold the startup id,
# whose transcript does not exist.
#
# Never "the newest *.jsonl": with several sessions live, that is another
# session's transcript as often as not, and the copy still reports success.
PROJECTS_DIR="$HOME/.claude/projects"
TRANSCRIPT_PATH=""
TRIED_IDS=""
GUESSED=""

# A top-level <project>/<id>.jsonl is a session transcript. Deeper .jsonl files
# (<sid>/subagents/agent-*.jsonl, plugin logs) are not, so stay at depth 2.
find_by_id() {
  find "$PROJECTS_DIR" -mindepth 2 -maxdepth 2 -type f -name "$1.jsonl" 2>/dev/null \
    | while IFS= read -r f; do stat -f "%Fm %N" "$f" 2>/dev/null; done \
    | sort -rn | head -1 | cut -d' ' -f2-
}

for CANDIDATE in "${CLAUDE_CODE_SESSION_ID:-}" "${1:-}"; do
  [ -n "$CANDIDATE" ] || continue
  case "$CANDIDATE" in
    *[!A-Za-z0-9-]*)
      echo "Refusing malformed session id: $CANDIDATE" >&2
      exit 1 ;;
  esac
  TRIED_IDS="$TRIED_IDS $CANDIDATE"
  TRANSCRIPT_PATH=$(find_by_id "$CANDIDATE")
  [ -n "$TRANSCRIPT_PATH" ] && break
done

if [ -z "$TRANSCRIPT_PATH" ] && [ -n "$TRIED_IDS" ]; then
  echo "No transcript found for session id(s):$TRIED_IDS under $PROJECTS_DIR" >&2
  echo "Nothing was written. Not falling back to the newest transcript — that is usually another session's." >&2
  exit 1
fi

if [ -z "$TRANSCRIPT_PATH" ]; then
  # No session id at all (older Claude Code). Fall back to the newest top-level
  # session transcript, and say plainly that this is a guess.
  TRANSCRIPT_PATH=$(find "$PROJECTS_DIR" -mindepth 2 -maxdepth 2 -type f -name '*.jsonl' 2>/dev/null \
    | while IFS= read -r f; do stat -f "%Fm %N" "$f" 2>/dev/null; done \
    | sort -rn | head -1 | cut -d' ' -f2-)
  GUESSED=1
fi

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo "No transcript file found under $PROJECTS_DIR" >&2
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
if [ -n "$GUESSED" ]; then
  echo "⚠ GUESSED: no session id was available, so this is the most recently written transcript (session $SESSION_SHORT). If that is not your session, it captured another one."
fi
echo "Run /extract now (in-context), or /audit knowledge will review this snapshot at the next audit cycle."
