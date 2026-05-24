#!/bin/bash
# pre-invocation-aria.sh — Antigravity PreInvocation wrapper.
#
# Fires before every model call. Three responsibilities:
#   1. Cache transcriptPath every turn — /snapshot reads it later.
#   2. On invocationNum == 0 (first call of conversation), inject
#      session-start ephemeralMessage with audit-cadence + knowledge-
#      surfacing prompts. Replaces Claude Code's SessionStart hook.
#   3. Drain pending scope-check log entries from post-edit-aria.sh
#      and inject as ephemeralMessage. Restores PostToolUse → agent
#      feedback channel that Antigravity's PostToolUse {} return
#      cannot deliver inline.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-antigravity-input.sh
source "$LIB_DIR/lib-antigravity-input.sh"

# PreInvocation-specific field (lib doesn't extract this — extract inline).
INVOCATION_NUM=$(jq -r '.invocationNum // 0' <<<"$ARIA_HOOK_INPUT")

CACHE_DIR="$HOME/.gemini/antigravity"
CACHE_FILE="$CACHE_DIR/.last-transcript-path"
LOG_FILE="$CACHE_DIR/aria-knowledge-scope-check.log"

mkdir -p "$CACHE_DIR" 2>/dev/null || true

# --- Responsibility 1: cache transcriptPath every turn ---
if [ -n "$ARIA_TRANSCRIPT_PATH" ]; then
  printf '%s' "$ARIA_TRANSCRIPT_PATH" > "$CACHE_FILE"
fi

# Build up injectSteps array
INJECT_STEPS_JSON='[]'

# --- Responsibility 2: session-start ephemeralMessage on first call ---
if [ "$INVOCATION_NUM" = "0" ]; then
  SESSION_START_MSG='[ARIA] First call of session. Run these checks before responding to the user:

1. **Audit cadence check.** Read ~/.gemini/antigravity/aria-knowledge.local.md. Parse `audit_cadence_knowledge` (default 7) and `audit_trigger_threshold` (default 20). Read {knowledge_folder}/logs/knowledge-audit-log.md and compute days since last audit + count unaudited backlog entries in intake/*-backlog.md. If cadence exceeded OR threshold reached, surface: "Knowledge audit due — want me to run /audit-knowledge?"

2. **Stale batch cleanup.** If ~/.gemini/antigravity/active-batch.json exists and its expires_at is in the past, delete it silently.

3. **Knowledge surfacing.** If `active_knowledge_surfacing: true` and the user prompt contains project tags or topic keywords, suggest /context <tags> before answering substantively.

Do these checks at most once per session, in your first response.'
  INJECT_STEPS_JSON=$(jq -c --arg msg "$SESSION_START_MSG" '. + [{"ephemeralMessage": $msg}]' <<<"$INJECT_STEPS_JSON")
fi

# --- Responsibility 3: drain pending scope-check log entries ---
if [ -s "$LOG_FILE" ]; then
  # Atomic move-then-process to avoid race with concurrent post-edit-aria.sh writes.
  DRAIN_FILE="${LOG_FILE}.draining.$$"
  if mv "$LOG_FILE" "$DRAIN_FILE" 2>/dev/null; then
    SCOPE_CONTENT=$(cat "$DRAIN_FILE" 2>/dev/null || echo "")
    rm -f "$DRAIN_FILE" 2>/dev/null
    if [ -n "$SCOPE_CONTENT" ]; then
      SCOPE_MSG="[ARIA Rule 22 scope-check feedback from prior edits]
$SCOPE_CONTENT
(Review these scope assessments. If any flag FAIL, address before continuing.)"
      INJECT_STEPS_JSON=$(jq -c --arg msg "$SCOPE_MSG" '. + [{"ephemeralMessage": $msg}]' <<<"$INJECT_STEPS_JSON")
    fi
  fi
fi

# --- Emit response ---
STEP_COUNT=$(jq -r 'length' <<<"$INJECT_STEPS_JSON")
if [ "$STEP_COUNT" -gt 0 ]; then
  jq -cn --argjson steps "$INJECT_STEPS_JSON" '{injectSteps: $steps}'
else
  # No injection needed; return empty object (per docs/hooks PreInvocation output is optional).
  printf '{}\n'
fi
