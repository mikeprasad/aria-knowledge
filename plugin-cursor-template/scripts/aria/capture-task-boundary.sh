#!/bin/sh
# capture-task-boundary.sh — stop-hook companion for Cursor.
#
# Cursor parity equivalent to the Claude Code pre-compact capture path:
# fires at task-boundary (the `stop` event) and writes a small markdown
# snapshot of session state under {knowledge_folder}/intake/task-boundary-captures/.
#
# This is NOT a raw transcript capture — Cursor does not expose transcripts
# to hooks. It captures the surrounding repo + session signals an agent or
# future audit can use to reconstruct what was happening at task end:
#   - session id, cwd, timestamp
#   - git branch + `git status --short` + changed files + `git diff --stat`
#   - active batch manifest, if present
#   - config path + knowledge_folder
#   - recent hook debug log lines (from the private state directory)
#
# All long sections (status, diff, log) are truncated to bounded byte sizes.
# Fail-open: never block, never error to stdout/stderr in a way Cursor sees.

INPUT=$(cat 2>/dev/null || true)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"
# Hook debug log (spec §5; 2.58.0 D4): <state dir>/aria-hook-debug.log, in the private per-user state
# directory from lib-state-key.sh. With no state directory nothing is logged (spec D3) and the
# path is empty. aria_hook_dbg builds the line first, creates the log only with kt_create_new,
# and appends only when it is a regular file of ours that is not a link (lib-tracked-artifacts.sh
# only defines functions; without it nothing is logged). KT_HOOK_DEBUG_LOG is a TEST-ONLY override
# of the path. Identical in pre-edit-check.sh, post-edit-check.sh, capture-task-boundary.sh and
# record-edit-intent.sh (tests/repros/safe-create-census.sh CC1b).
. "$SCRIPT_DIR/lib-tracked-artifacts.sh" 2>/dev/null || true
. "$SCRIPT_DIR/lib-state-key.sh" 2>/dev/null || true
ARIA_HOOK_DEBUG_LOG=${KT_HOOK_DEBUG_LOG:-}
if [ -z "$ARIA_HOOK_DEBUG_LOG" ] && kt_state_resolve 2>/dev/null; then
  ARIA_HOOK_DEBUG_LOG=$(kt_state_path aria-hook-debug.log) || ARIA_HOOK_DEBUG_LOG=
fi
aria_hook_dbg() {
  [ -n "$ARIA_HOOK_DEBUG_LOG" ] || return 0
  _ahd_l="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) $*"
  [ -e "$ARIA_HOOK_DEBUG_LOG" ] || [ -L "$ARIA_HOOK_DEBUG_LOG" ] || kt_create_new "$ARIA_HOOK_DEBUG_LOG" 2>/dev/null || :
  kt_is_ours "$ARIA_HOOK_DEBUG_LOG" 2>/dev/null || return 0
  printf '%s\n' "$_ahd_l" >> "$ARIA_HOOK_DEBUG_LOG" 2>/dev/null
  return 0
}

aria_hook_dbg "$0 fired"

# Skip silently if no knowledge folder is configured — there's nowhere to write.
if [ "$KT_CONFIGURED" != "true" ] || [ -z "$KT_KNOWLEDGE_FOLDER" ] || [ ! -d "$KT_KNOWLEDGE_FOLDER" ]; then
  exit 0
fi

# sessionId / session_id fallback
SESSION_ID=$(printf '%s' "$INPUT" | grep -o '"sessionId":"[^"]*"' | head -1 | sed 's/"sessionId":"//;s/"$//')
[ -z "$SESSION_ID" ] && SESSION_ID=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"$//')
[ -z "$SESSION_ID" ] && SESSION_ID="unknown"

CAPTURE_DIR="${KT_TASK_CAPTURE_DIR:-$KT_KNOWLEDGE_FOLDER/intake/task-boundary-captures}"
mkdir -p "$CAPTURE_DIR" 2>/dev/null || exit 0

TS_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TS_FILE=$(date -u +%Y%m%d-%H%M%S)
SAFE_SID=$(printf '%s' "$SESSION_ID" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-40)
OUT="$CAPTURE_DIR/${TS_FILE}-${SAFE_SID}.md"

CWD_VAL="$(pwd 2>/dev/null)"

# Git context — all optional, fail silently if not a repo
GIT_BRANCH=""
GIT_STATUS=""
GIT_CHANGED=""
GIT_DIFFSTAT=""
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  GIT_STATUS=$(git status --short 2>/dev/null | head -200 | cut -c1-400)
  GIT_CHANGED=$(git status --short 2>/dev/null | awk '{print $NF}' | head -50)
  GIT_DIFFSTAT=$(git diff --stat 2>/dev/null | head -100)
fi

# Truncate diffstat to ~4 KB just in case
GIT_DIFFSTAT=$(printf '%s' "$GIT_DIFFSTAT" | head -c 4096)
GIT_STATUS=$(printf '%s' "$GIT_STATUS" | head -c 4096)

# Active batch manifest
BATCH_INFO="(none)"
if [ -f "$KT_BATCH_MANIFEST" ]; then
  BATCH_INFO=$(head -c 2048 "$KT_BATCH_MANIFEST" 2>/dev/null)
fi

# Recent debug log — last 40 lines, capped to ~4 KB
DEBUG_LOG=""
if [ -z "$ARIA_HOOK_DEBUG_LOG" ]; then
  DEBUG_LOG="(state directory unavailable)"
elif kt_is_ours "$ARIA_HOOK_DEBUG_LOG" 2>/dev/null; then
  DEBUG_LOG=$(tail -n 40 "$ARIA_HOOK_DEBUG_LOG" 2>/dev/null | head -c 4096)
fi

{
  printf '# Task-boundary capture\n\n'
  printf -- '- timestamp: %s\n' "$TS_UTC"
  printf -- '- session_id: %s\n' "$SESSION_ID"
  printf -- '- cwd: %s\n' "$CWD_VAL"
  printf -- '- git_branch: %s\n' "${GIT_BRANCH:-(not a git repo)}"
  printf -- '- config_path: %s\n' "$KT_CONFIG"
  printf -- '- knowledge_folder: %s\n' "$KT_KNOWLEDGE_FOLDER"
  printf '\n## git status --short (truncated)\n\n```\n%s\n```\n' "$GIT_STATUS"
  printf '\n## changed files\n\n```\n%s\n```\n' "$GIT_CHANGED"
  printf '\n## git diff --stat (truncated)\n\n```\n%s\n```\n' "$GIT_DIFFSTAT"
  printf '\n## active batch manifest\n\n```\n%s\n```\n' "$BATCH_INFO"
  printf '\n## recent hook debug log (last 40 lines, truncated)\n\n```\n%s\n```\n' "$DEBUG_LOG"
} > "$OUT" 2>/dev/null

aria_hook_dbg "$0 wrote $OUT"

exit 0
