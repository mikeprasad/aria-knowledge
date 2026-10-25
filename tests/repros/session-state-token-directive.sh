#!/bin/sh
# tests/repros/session-state-token-directive.sh — the SESSION STATE directive's TOKEN branch (D5)
# and the operator-precedence clause (D7), asserted on the DELIVERED copy.
#
# ⛔ RE-POINTED 2026-10-25. This used to drive session-start-check.sh and read its stdout. That
# stdout was a systemMessage, which renders to the user and never reaches the model (measured from
# a transcript's API request records), so the suite was guarding a copy nobody received — and the
# copy the model DID receive, the bundled digest, lacked one of these clauses the whole time.
# The digest is loaded verbatim as an instruction file, so reading it IS reading the payload.
#
# Scoped to the SESSION STATE section on purpose: the same phrases could appear elsewhere in the
# digest, and a whole-file grep would pass on a stray mention.
#
# ⚠ STATED BOUND: this proves what is DELIVERED. It cannot prove an agent OBEYS it.
set -e
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DIGEST="$DIR/plugin-claude-code/rules/aria-rules.md"
GATE='### When `session_state` is `true`'

# The section: from the gate heading to the next ### heading.
section=$(awk -v g="$GATE" '$0==g{f=1;next} f&&/^### /{exit} f' "$DIGEST")
fail=0
# Positive control FIRST: an empty extraction would make every grep below fail for the wrong reason.
if [ -n "$section" ] && printf '%s' "$section" | grep -q 'SESSION STATE —'; then
  printf '  PASS  control — the SESSION STATE directive sits under the session_state gate heading\n'
else
  printf '  FAIL  control — no SESSION STATE directive under %s\n' "$GATE"; fail=1
fi
chk() { # $1 = label, $2 = needle
  if printf '%s' "$section" | grep -qF "$2"; then printf '  PASS  %s\n' "$1"
  else printf '  FAIL  %s — not in the delivered directive\n' "$1"; fail=1; fi
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
# Backwards compatibility — the word trigger survives for tokenless prompts.
chk "fallback word trigger retained"         "If no token is present"

[ "$fail" -eq 0 ] || { echo "session-state-token-directive: FAIL"; exit 1; }
echo "session-state-token-directive: PASS"
