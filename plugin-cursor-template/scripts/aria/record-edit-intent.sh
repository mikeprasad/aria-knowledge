#!/bin/sh
# record-edit-intent.sh — write an "edit intent" marker before an Edit/Write.
#
# Cursor parity equivalent for the Rule 22 pre-edit declaration: the agent
# calls this *before* invoking an Edit/Write tool to record that it has
# done the Rule 22 assessment for a specific file. The pre-edit hook then
# verifies a recent matching marker exists for the file being edited;
# stale, missing, or mismatched markers cause a strong advisory reminder
# (and, for protected files, a stronger nudge) — Cursor's hooks plan does
# not document a stable agent-side deny path for beforeFileEdit, so we
# stay advisory by default.
#
# Output: writes .cursor/aria-edit-intent.json relative to repo root.
#
# Inputs (any of):
#   $1 = filePath                            (or env ARIA_FILE_PATH / ARIA_FILEPATH)
#   $2 = marker type: rule22-low|rule22-high (or env ARIA_RULE22_MARKER)
#   $3 = rationale string                    (or env ARIA_RATIONALE)
#   env ARIA_SESSION_ID                      (else "manual")
#
# All fields optional except filePath — the hook checks file+session+age.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"
# Hook debug log at a fixed /tmp name (spec §5): aria_hook_dbg builds the line first, creates the
# log only with kt_create_new, and appends only when it is a regular file of ours that is not a
# link (lib-tracked-artifacts.sh only defines functions; without it nothing is logged).
# KT_HOOK_DEBUG_LOG is a TEST-ONLY override of the path. Identical in pre-edit-check.sh,
# post-edit-check.sh, capture-task-boundary.sh and record-edit-intent.sh
# (tests/repros/safe-create-census.sh CC1).
. "$SCRIPT_DIR/lib-tracked-artifacts.sh" 2>/dev/null || true
ARIA_HOOK_DEBUG_LOG=${KT_HOOK_DEBUG_LOG:-/tmp/aria-hook-debug.log}
aria_hook_dbg() {
  _ahd_l="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) $*"
  [ -e "$ARIA_HOOK_DEBUG_LOG" ] || [ -L "$ARIA_HOOK_DEBUG_LOG" ] || kt_create_new "$ARIA_HOOK_DEBUG_LOG" 2>/dev/null || :
  kt_is_ours "$ARIA_HOOK_DEBUG_LOG" 2>/dev/null || return 0
  printf '%s\n' "$_ahd_l" >> "$ARIA_HOOK_DEBUG_LOG" 2>/dev/null
  return 0
}

FILE_PATH="${1:-${ARIA_FILE_PATH:-${ARIA_FILEPATH:-}}}"
MARKER_TYPE="${2:-${ARIA_RULE22_MARKER:-rule22-low}}"
RATIONALE="${3:-${ARIA_RATIONALE:-}}"
SESSION_ID="${ARIA_SESSION_ID:-manual}"

if [ -z "$FILE_PATH" ]; then
  echo "record-edit-intent.sh: filePath required (arg 1 or ARIA_FILE_PATH)" >&2
  exit 2
fi

case "$MARKER_TYPE" in
  rule22-low|rule22-high|rule22-planning|rule22-batch) ;;
  *) MARKER_TYPE="rule22-low" ;;
esac

OUT="${KT_EDIT_INTENT_FILE:-$KT_ROOT/.cursor/aria-edit-intent.json}"
mkdir -p "$(dirname "$OUT")" 2>/dev/null

NOW_EPOCH=$(date +%s)
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Escape strings for JSON
esc_sid=$(kt_json_escape "$SESSION_ID")
esc_fp=$(kt_json_escape "$FILE_PATH")
esc_marker=$(kt_json_escape "$MARKER_TYPE")
esc_rat=$(kt_json_escape "$RATIONALE")

# Compact single-line JSON so the shell-side readers in pre-edit-check.sh /
# post-edit-check.sh (grep + sed, no jq) can extract fields with the same
# `"key":"value"` regex they use for the Cursor stdin payload.
printf '{"sessionId":"%s","filePath":"%s","timestamp":%s,"timestampIso":"%s","marker":"%s","rationale":"%s"}\n' \
  "$esc_sid" "$esc_fp" "$NOW_EPOCH" "$NOW_ISO" "$esc_marker" "$esc_rat" \
  > "$OUT"

aria_hook_dbg "$0 wrote intent for $FILE_PATH ($MARKER_TYPE)"
exit 0
