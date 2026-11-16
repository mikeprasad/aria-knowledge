#!/bin/sh
# pre-bash-r22-carrier.sh — PreToolUse hook for Bash (v2.54.0).
#
# Records a Rule 22 CARRIER — a Bash call whose input has a `[Rule 22…]` marker at
# the start of a line (recommended form: a `cat <<'R22'` heredoc) — the moment the
# call runs, so pre-edit-check.sh can authorise the NEXT Edit/Write without reading
# the transcript.
#
# Why a side channel: Claude Code writes a response to the transcript all at once,
# when the model finishes streaming it, while each tool call's PreToolUse hook runs
# during streaming (measured 2026-09-24: 5 calls created +0.00..+2.93 s all reached
# disk at +3.06 s). An edit early in a response therefore cannot see the marker
# above it in the transcript for however long the model keeps generating — p50 3.1 s,
# max 30.9 s over 402 such edits. Recording at hook time removes that dependency.
#
# Semantics (ADR 062 / ADR 036), enforced by the consumer, not here:
#   one carrier -> one edit; same session + same agent + same prompt_id.
# A second carrier before the next edit simply overwrites the record (still one).
#
# Contract: never blocks, never prints, always exits 0. Every Bash call pays this
# hook, so non-carrier calls take the shell fast path and never start python.
# Input goes to python via printf '%s', never echo (tests/repros/hook-json-extraction.sh:
# POSIX echo mangles backslash escapes and a guard then fails open silently).

INPUT=$(cat)

case "$INPUT" in
  *'[Rule 22'*) ;;
  *) exit 0 ;;
esac

# 2.58.0: the record lives in the private per-user state directory (lib-state-key.sh), so a record
# another local user plants in a shared temp dir can never authorise an edit. With no directory
# (spec D3) nothing is recorded and pre-edit-check.sh decides from the transcript (tail mode).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/lib-state-key.sh" ] || exit 0
. "$SCRIPT_DIR/lib-state-key.sh"
kt_state_resolve || exit 0

printf '%s' "$INPUT" | ARIA_R22_TMP="$KT_STATE_DIR" python3 -c '
import json, os, re, sys, time
try:
    d = json.load(sys.stdin)

    def strings(v):
        if isinstance(v, str):
            yield v
        elif isinstance(v, dict):
            for x in v.values():
                yield from strings(x)
        elif isinstance(v, list):
            for x in v:
                yield from strings(x)

    # Same anchored form pre-edit-check.sh accepts in tool inputs: a mention
    # mid-line (e.g. grep for the marker) is not a carrier.
    MARK = re.compile(r"(?m)^[ \t]*\[Rule 22(\s\xb7(?!\s*(?i:scope)\b)\s[^\]]+)?\]")  # v2.54.2: a Scope line is post-edit, not a carrier
    if not any(MARK.search(s) for s in strings(d.get("tool_input") or {})):
        sys.exit(0)

    # The session key follows kt_session_key (lib-state-key.sh), which pre-edit-check.sh reads the
    # carrier with: accepted only as [A-Za-z0-9._-]+ and never rewritten (stripping let two sessions
    # share one key); the transcript-basename fallback only when there is NO session_id. agent_id
    # keeps the strip kt_agent_suffix applies (tests/repros/r22-carrier-side-channel.sh C12).
    VALID = re.compile(r"[A-Za-z0-9._-]+")
    chk = lambda s: s if isinstance(s, str) and VALID.fullmatch(s) else ""
    san = lambda s: re.sub(r"[^A-Za-z0-9._-]", "", s or "")
    sid = d.get("session_id")
    if isinstance(sid, str) and sid != "":
        key = chk(sid)
    else:
        base = os.path.basename(d.get("transcript_path") or "")
        key = chk(base[:-6] if base.endswith(".jsonl") else base)
    if not key:
        sys.exit(0)
    agent = san(d.get("agent_id"))
    if agent:
        key += ".agent-" + agent

    path = os.path.join(os.environ["ARIA_R22_TMP"], "aria-r22-carrier-" + key)
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w") as f:
        json.dump({"prompt_id": d.get("prompt_id") or "",
                   "tool_use_id": d.get("tool_use_id") or "",
                   "recorded_at": time.time()}, f)
    os.replace(tmp, path)
except Exception:
    pass
' >/dev/null 2>&1

exit 0
