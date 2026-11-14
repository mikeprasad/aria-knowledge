#!/bin/sh
# prompt-context-check.sh — UserPromptSubmit hook for aria-knowledge (spec D1a).
#
# On every prompt: rank the knowledge index against the words the USER typed, drop
# files this session has already surfaced (the shared ledger <state dir>/aria-active-<session_id>,
# also used by task-context-check.sh and bash-cd-check.sh), and inject the remaining
# ranked PATHS as hookSpecificOutput.additionalContext. The model no longer runs the
# selection algorithm itself; it reads what this hook hands it.
#
# This file is only the Claude Code I/O ADAPTER (2.58.0, spec C1). The work — the
# config-value cache, paste stripping, ranking, the ledger, the injection text and its
# 10,000-char bound — lives in lib-prompt-surface.sh, shared with the Cursor and
# Antigravity capture hooks. Read that file for the input rules (pasted blocks), the
# output bound and the latency budget.
#
# Silent to the model (no output, exit 0) unless a not-yet-surfaced file ranks. Never
# blocks the prompt. A FAILURE — jq missing, empty or unparseable stdin, no session_id,
# an invalid config, a missing index — also appends one line to the debug log
# <state dir>/aria-surface-hook.log (spec C3), so a dead hook can be told from one that had
# nothing to say. Not configured, surfacing turned off, and "nothing new to surface" are not
# failures and log nothing.
#
# State (2.58.0): the ledger, the debug log and the caches live in the private per-user state
# dir (lib-state-key.sh). With none (spec D3) this hook surfaces nothing and logs nothing:
# without the ledger the same files would be injected on every prompt.

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0

# Drain stdin before ANY early exit. The host writes the prompt into a pipe; a hook
# that exits without reading can leave the writer blocked or failing. Read only when
# fd 0 is OPEN: with it closed, the pipe $( ) creates takes fd 0 and cat reads its own
# output pipe forever (measured hang). `(exec 3<&0)` fails on a closed fd; `: <&0` does
# not, so it cannot be the test.
INPUT=""
if (exec 3<&0) 2>/dev/null; then INPUT=$(cat 2>/dev/null); fi

[ -f "$SCRIPT_DIR/lib-prompt-surface.sh" ] || exit 0
KT_PS_SCRIPT_DIR=$SCRIPT_DIR
KT_PS_RUNTIME=claude-code
. "$SCRIPT_DIR/lib-prompt-surface.sh"
# No state directory (spec D3): surface nothing and log nothing (the log is state too).
. "$SCRIPT_DIR/lib-state-key.sh"
kt_state_resolve || exit 0

command -v jq >/dev/null 2>&1 || { kt_ps_log claude-code input jq-missing; exit 0; }
[ -n "$INPUT" ] || { kt_ps_log claude-code input stdin-empty; exit 0; }

# Location expression identical to config.sh's first assignment. Set here, not in the
# shared lib, because each port's default differs (see lib-prompt-surface.sh).
KT_CONFIG="${KT_CONFIG:-$HOME/.claude/aria-knowledge.local.md}"

# --- Input: session id + the prompt ------------------------------------------------
# One jq call: line 1 is the session id with every newline removed (only the framing needs
# that), the rest is the prompt. Not JSON or not an object => jq fails => exit. The KEY is then
# kt_session_key on the raw input (lib-state-key.sh): accepted only as [A-Za-z0-9._-]+ and never
# rewritten, the same key session-start-check.sh states in ARIA CONFIG (stated = written).
_pcc_nl='
'
_pcc_parsed=$(jq -r '
  ((.session_id // "") | tostring | gsub("[\r\n]"; "")),
  ((.prompt // "") | tostring)
' 2>/dev/null <<PCC_INPUT
$INPUT
PCC_INPUT
) || { kt_ps_log claude-code input not-a-json-object; exit 0; }

_pcc_sid=${_pcc_parsed%%"$_pcc_nl"*}
_pcc_raw=""
case $_pcc_parsed in *"$_pcc_nl"*) _pcc_raw=${_pcc_parsed#*"$_pcc_nl"} ;; esac
[ -n "$_pcc_sid" ] || { kt_ps_log claude-code input no-session-id; exit 0; }
_pcc_sid=$(kt_session_key "$INPUT" session_id) || { kt_ps_log claude-code input session-id-rejected; exit 0; }

# The user's own words: pasted blocks removed. An empty result is a nofire, not a failure.
_pcc_text=$(printf '%s' "$_pcc_raw" | kt_ps_strip_pasted)
[ -n "$_pcc_text" ] || exit 0

# --- Rank, filter, format (shared core); then emit in Claude Code's shape -----------
# Output (C4, Claude Code 2.1.319): hookSpecificOutput.additionalContext — a top-level
# field is ignored. The ledger is committed only once the output is printed: a file the
# model never received must not be marked as surfaced (lib header, "The ledger contract").
LEDGER=$(kt_state_path "aria-active-${_pcc_sid}") || exit 0
kt_ps_surface "$_pcc_text" "$LEDGER" >/dev/null
[ -n "$KT_PS_TEXT" ] || exit 0
_pcc_out=$(jq -cn --arg c "$KT_PS_TEXT" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}' 2>/dev/null) \
  || { kt_ps_log claude-code emit jq-failed; exit 0; }
printf '%s\n' "$_pcc_out" || { kt_ps_log claude-code emit write-failed; exit 0; }
kt_ps_commit "$LEDGER"
exit 0
