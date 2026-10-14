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
# WARN-ONLY by design: it records each target to ${TMPDIR}/aria-r22-bypass-<sessionId>
# (read by /handoff and /wrapup) and never denies.

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

_bw_sid=$(printf '%s' "$INPUT" | grep -oE '"(sessionId|session_id|conversation_id)"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//')
if [ -n "$_bw_sid" ]; then
  printf '%s\n' "$TARGETS" | while IFS= read -r _t; do
    [ -n "$_t" ] && printf '%s\n' "$_t" >> "${TMPDIR:-/tmp}/aria-r22-bypass-$_bw_sid" 2>/dev/null || true
  done
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh" 2>/dev/null || true
LIST=$(printf '%s' "$TARGETS" | tr '\n' ' ')
MSG="ARIA: this command modifies a file in place: ${LIST}. A structural edit made through the shell bypasses Edit/Write, and therefore the Rule 22 pre-edit gate — the change lands with no scope assessment recorded. Use Edit or Write instead. If this is genuinely not a structural edit (a generated artifact, a disposable probe, a log), go ahead and say why."
MSG_ESCAPED=$(kt_json_escape "$MSG" 2>/dev/null || printf '%s' "$MSG" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ')
printf '{"agentMessage":"%s"}\n' "$MSG_ESCAPED"
exit 0
