#!/bin/sh
# tests/repros/session-state-token-directive.sh — the SESSION STATE directive's TOKEN branch (D5)
# and the operator-precedence clause (D7), asserted on the hook's EMITTED output.
#
# ⛔ EMITTED, NOT SOURCE. Grepping session-start-check.sh for the clause would be a spell-check: it
# would pass for a clause sitting behind a gate that never fires. Driving the hook and reading stdout
# is the technique picker-gating.sh and autonomy-posture.sh already use, and it is what makes this a
# guard rather than a comment.
#
# ⚠ STATED BOUND: this proves what the hook PRODUCES. It cannot prove an agent OBEYS it. A prose
# contract is not testable past emission, and claiming otherwise would be the failure this file's
# own subject exists to avoid.
set -e
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$DIR/plugin-claude-code/bin/session-start-check.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
KN="$TMP/kn"; mkdir -p "$KN/logs"
printf -- '- **Date:** 2026-09-16 (seeded for test)\n' > "$KN/logs/knowledge-audit-log.md"
CFG="$TMP/aria-knowledge.local.md"
cat > "$CFG" <<EOF
---
knowledge_folder: $KN
knowledge_root: $KN
configured: true
session_state: true
active_knowledge_surfacing: false
---
EOF

out=$(cd "$TMP" && KT_CONFIG="$CFG" sh "$HOOK" 2>/dev/null || true)
fail=0
chk() { # $1 = label, $2 = needle
  if printf '%s' "$out" | grep -qF "$2"; then printf '  PASS  %s\n' "$1"
  else printf '  FAIL  %s — not in the emitted directive\n' "$1"; fail=1; fi
}
# D5 — the five outcomes, each asserted by the phrase that carries it.
chk "D5 token is scanned for"                "aria-handoff: <project>/<sid>@<at>"
chk "R1 the WHOLE message is scanned"        "ENTIRE opening message"
chk "D5 locate helper is named"              "kt_ss_ledger_token_locate"
chk "D5 consume passes the exact at"         "FIFTH argument"
chk "D5 archived is its own outcome"         "'|archived'"
chk "D5 empty result does not fabricate"     "do NOT fabricate an entry"
chk "D5 terminal entry stops the resume"     "SURFACE AND STOP"
# D7 — operator precedence.
chk "R2 operator text outranks the prompt"   "OUTRANKS the stored prompt"
chk "R2 names the gate shape"                "state-verify gate, not a preamble"
# Backwards compatibility — the word trigger survives for the 152 tokenless prompts.
chk "fallback word trigger retained"         "If no token is present"

# ⛔ CONTROL: with session_state off the directive must not be emitted at all. Without this, every
# assertion above could be matching a string that is always present regardless of the gate.
sed 's/session_state: true/session_state: false/' "$CFG" > "$CFG.off"
out2=$(cd "$TMP" && KT_CONFIG="$CFG.off" sh "$HOOK" 2>/dev/null || true)
if printf '%s' "$out2" | grep -qF "kt_ss_ledger_token_locate"; then
  printf '  FAIL  control — token branch emitted while session_state is off\n'; fail=1
else
  printf '  PASS  control — directive silent when session_state is off\n'
fi

[ "$fail" -eq 0 ] || { echo "session-state-token-directive: FAIL"; exit 1; }
echo "session-state-token-directive: PASS"
