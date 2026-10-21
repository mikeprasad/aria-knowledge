#!/bin/sh
# lib-state-key.sh — the per-agent suffix for session-keyed hook state (v2.54.1).
#
# A subagent's hooks receive the PARENT's session_id (measured 2026-09-24), so any
# state file keyed on session_id alone is shared between a session and every
# subagent it spawns. For a DENIAL COUNTER that is a defect: three denials inside a
# subagent open the parent's breaker and switch its enforcement off. Consumers append
#   kt_agent_suffix "$INPUT"
# to the key they already build, so every main-thread key is byte-identical to before.
#
# Output: ".agent-<agent_id sanitised to A-Za-z0-9._->", or empty when the input has
# no agent_id (the main thread). Sanitising removes "/" so an id can never address a
# path; the recorder (pre-bash-r22-carrier.sh) applies the same set in Python, and
# tests/repros/r22-carrier-side-channel.sh C12 fails if the two ever disagree.
#
# Deliberately NOT for session-level FACTS a subagent should inherit — the preflight
# "ran this session" marker and the external-fetch cooldown stay session-keyed.
#
# POSIX sh: every consumer is #!/bin/sh.

kt_agent_suffix() {
  # Fast path: no agent_id key at all -> main thread, no python spawn.
  case "$1" in *'"agent_id"'*) ;; *) return 0 ;; esac
  _kt_aid=$(printf '%s' "$1" | python3 -c 'import json, sys
try:
    print(json.load(sys.stdin).get("agent_id") or "")
except Exception:
    print("")' 2>/dev/null | tr -cd 'A-Za-z0-9._-')
  [ -n "$_kt_aid" ] && printf '.agent-%s' "$_kt_aid"
  return 0
}
