#!/bin/sh
# pre-bash-write-check.sh — Cursor beforeShellExecution hook: warn when a shell command
# modifies a tracked source file in place (sed -i, perl -i, awk inplace, an append-redirect).
#
# Ported from plugin-claude-code/bin/pre-bash-write-check.sh (v2.48.1 resolver design). The
# decision is made on the RESOLVED write target by pre-bash-write-resolve.py (shipped
# byte-identical to canonical), never on whether the command string mentions a temp path —
# the old string test went silent whenever a command merely referenced /tmp or a scratchpad,
# which is exactly the backup-then-mutate pattern careful work uses.
#
# Cursor delivers the command at the TOP LEVEL of the payload; the resolver reads
# tool_input.command, so the payload is reshaped before it is handed over.
# WARN-ONLY by design: it records each target to aria-r22-bypass-<sessionId> in the private state
# directory (lib-state-key.sh; read by /handoff and /wrapup) and never denies.

INPUT=$(cat)
case "$INPUT" in
  *sed*|*perl*|*awk*|*'>>'*) : ;;
  *) exit 0 ;;
esac
command -v python3 >/dev/null 2>&1 || exit 0
RESOLVER="$(dirname "$0")/pre-bash-write-resolve.py"
[ -f "$RESOLVER" ] || exit 0

TARGETS=$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    p = json.load(sys.stdin)
except Exception:
    sys.exit(0)
cmd = p.get("command") or (p.get("tool_input") or {}).get("command") or ""
print(json.dumps({"tool_input": {"command": cmd}}))
' 2>/dev/null | python3 "$RESOLVER" 2>/dev/null)
[ -z "$TARGETS" ] && exit 0

# kt_session_key (lib-state-key.sh): read whitespace-tolerantly, accepted only as [A-Za-z0-9._-]+ and
# never rewritten — the key every hook in this port names this family's state with. Rejected: no key, nothing recorded.
_bw_sid=
KT_STATE_DIR=   # an inherited value is never trusted: only the state-dir resolver sets it
[ -f "$(dirname "$0")/lib-state-key.sh" ] && . "$(dirname "$0")/lib-state-key.sh" \
  && _bw_sid=$(kt_session_key "$INPUT" sessionId session_id conversation_id)
# 2.58.0: the ledger lives in the private per-user state directory (lib-state-key.sh). The id goes
# through kt_state_path, which refuses one containing "/", so it can never address a path; with no
# directory (spec D3) nothing is recorded and the warning below is still emitted. Inside the
# directory it is still created only by kt_create_new and appended to only when it is a regular
# file of ours that is not a link (a second guard, spec D2; lib-tracked-artifacts.sh only defines
# functions; without it nothing is recorded).
if [ -n "$_bw_sid" ]; then
  _bw_rec=$(printf '%s\n' "$TARGETS" | grep -v '^$')
  _bw_f=
  if [ -f "$(dirname "$0")/lib-state-key.sh" ]; then
    . "$(dirname "$0")/lib-state-key.sh"
    kt_state_resolve && _bw_f=$(kt_state_path "aria-r22-bypass-$_bw_sid")
  fi
  . "$(dirname "$0")/lib-tracked-artifacts.sh" 2>/dev/null || true
  if [ -n "$_bw_rec" ] && [ -n "$_bw_f" ]; then
    [ -e "$_bw_f" ] || [ -L "$_bw_f" ] || kt_create_new "$_bw_f" 2>/dev/null || :
    if kt_is_ours "$_bw_f" 2>/dev/null; then
      printf '%s\n' "$_bw_rec" >> "$_bw_f" 2>/dev/null || true
    fi
  fi
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh" 2>/dev/null || true
LIST=$(printf '%s' "$TARGETS" | tr '\n' ' ')
MSG="ARIA: this command modifies a file in place: ${LIST}. A structural edit made through the shell bypasses Edit/Write, and therefore the Rule 22 pre-edit gate — the change lands with no scope assessment recorded. Use Edit or Write instead. If this is genuinely not a structural edit (a generated artifact, a disposable probe, a log), go ahead and say why."
MSG_ESCAPED=$(kt_json_escape "$MSG" 2>/dev/null || printf '%s' "$MSG" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ')
printf '{"agentMessage":"%s"}\n' "$MSG_ESCAPED"
exit 0
