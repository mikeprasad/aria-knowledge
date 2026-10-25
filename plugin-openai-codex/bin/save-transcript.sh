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

# Locate THIS session's transcript by its thread id. Codex stores each thread as
#   ${CODEX_HOME:-~/.codex}/sessions/YYYY/MM/DD/rollout-<timestamp>-<thread id>.jsonl
# whose first record is {"type":"session_meta","payload":{"id":"<thread id>",...}},
# and sets CODEX_THREAD_ID in every shell command it runs. An id passed as $1 is
# tried second. Codex documents that label as one it may remove, so the no-id
# path below falls back to the newest rollout and says it guessed.
#
# Never "the newest rollout" when an id is known: with several sessions live,
# that is another session's as often as not, and the copy still reports success.
if [ -n "${CODEX_HOME:-}" ] && [ ! -d "$CODEX_HOME" ]; then
  echo "CODEX_HOME is set but is not a directory: $CODEX_HOME" >&2
  exit 1
fi
SESSIONS_DIR="${CODEX_HOME:-$HOME/.codex}/sessions"
TRANSCRIPT_PATH=""
TRIED_IDS=""
GUESSED=""

# Rollouts sit exactly at sessions/YYYY/MM/DD/, so stay at depth 4.
find_by_id() {
  find "$SESSIONS_DIR" -mindepth 4 -maxdepth 4 -type f -name "rollout-*-$1.jsonl" 2>/dev/null | head -1
}

for CANDIDATE in "${CODEX_THREAD_ID:-}" "${1:-}"; do
  [ -n "$CANDIDATE" ] || continue
  case "$CANDIDATE" in
    *[!A-Za-z0-9-]*)
      echo "Refusing malformed session id: $CANDIDATE" >&2
      exit 1 ;;
  esac
  TRIED_IDS="$TRIED_IDS $CANDIDATE"
  TRANSCRIPT_PATH=$(find_by_id "$CANDIDATE")
  if [ -n "$TRANSCRIPT_PATH" ]; then
    # The filename is only a claim; the session_meta record is the thread's own.
    if ! head -n 1 "$TRANSCRIPT_PATH" | grep -q "\"id\":\"$CANDIDATE\""; then
      echo "Rollout $TRANSCRIPT_PATH does not record thread id $CANDIDATE in its session_meta." >&2
      echo "Nothing was written." >&2
      exit 1
    fi
    break
  fi
done

if [ -z "$TRANSCRIPT_PATH" ] && [ -n "$TRIED_IDS" ]; then
  echo "No transcript found for session id(s):$TRIED_IDS under $SESSIONS_DIR" >&2
  echo "Nothing was written. Not falling back to the newest transcript — that is usually another session's." >&2
  exit 1
fi

if [ -z "$TRANSCRIPT_PATH" ]; then
  # No thread id at all. Take the most recently written rollout, and say
  # plainly that this is a guess. `ls -t` is POSIX; `-exec … +` keeps paths
  # with spaces intact.
  TRANSCRIPT_PATH=$(find "$SESSIONS_DIR" -mindepth 4 -maxdepth 4 -type f -name 'rollout-*.jsonl' \
    -exec ls -t {} + 2>/dev/null | head -1)
  GUESSED=1
fi

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo "No transcript file found under $SESSIONS_DIR" >&2
  exit 1
fi

# The thread id is the last 36 characters of the rollout's basename.
SESSION_ID=$(basename "$TRANSCRIPT_PATH" .jsonl | awk '{ n = length($0); print (n > 36 ? substr($0, n - 35) : $0) }')
SESSION_SHORT=$(kt_codex_id_short "$SESSION_ID")
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
  echo "⚠ GUESSED: no thread id was available, so this is the most recently written rollout (session $SESSION_ID). If that is not your session, it captured another one."
fi
echo "Run /extract now (in-context), or /audit knowledge will review this snapshot at the next audit cycle."
