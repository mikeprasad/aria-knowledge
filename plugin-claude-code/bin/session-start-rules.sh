#!/bin/sh
# session-start-rules.sh — SessionStart hook for aria-knowledge.
#
# Sole owner of the MODEL-directed session-start channel. Emits
# hookSpecificOutput.additionalContext, which reaches model context.
#
# Its sibling bin/session-start-check.sh emits systemMessage, which renders to
# the USER's terminal and never reaches the model. That split is deliberate:
# a nag asks a human to authorise something; the payload here instructs the
# model. Both hooks are registered under SessionStart and coexist — measured,
# four SessionStart hooks ran side by side in one session, two on each channel,
# all honoured.
#
# ⛔ Never emit systemMessage from this script.
# ⛔ Never migrate the TASK BUDGET long variant (session-start-check.sh:239)
#    here. It instructs the model to gate stopping/wrap-up decisions on usage
#    figures — a behaviour the maintainer has repeatedly corrected. Only the
#    short variant is in scope, and it lives in this file's Unit 1 payload.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

[ -n "$KT_CONFIG_ERROR" ] && exit 0
[ "$KT_CONFIGURED" = "false" ] && exit 0
[ ! -d "$KT_KNOWLEDGE_FOLDER" ] && exit 0

# Escape for a JSON string value, PRESERVING newlines as the two-character \n
# escape.
#
# ⛔ Deliberately NOT config.sh's kt_json_escape. That helper ends with
# `tr '\n' ' '` — it STRIPS newlines. Correct for the single-paragraph
# directives it was written for; wrong here, where it would collapse a
# multi-hundred-line structured digest into one run-on line, destroying every
# heading and bullet. The payload would still be valid JSON and the hook would
# still exit 0, so nothing would surface the damage.
# ⛔ Do NOT "fix" the shared helper instead — four other hooks depend on its
# current behaviour and none of them wants structure preserved.
kt_json_escape_multiline() {
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' -e 's/\r//g' \
    | awk 'BEGIN{ORS=""} NR>1{print "\\n"} {print}'
}

MESSAGES=""

# --- the always-on rules digest ---
DIGEST="$SCRIPT_DIR/../rules/aria-rules.md"
if [ -f "$DIGEST" ]; then
  MESSAGES="${MESSAGES}ARIA WORKING RULES — in force for this session. Apply them as you work; do not wait to be asked.

$(cat "$DIGEST")
"
fi

# --- Rule 22 ordering ---
# A rule, and the only one whose enforcement is a BLOCKING PreToolUse hook, so
# a model that never receives this is denied its first edit without knowing why.
MESSAGES="${MESSAGES}
RULE 22 ORDERING — The Low/High Impact block must appear ABOVE the Edit/Write tool call in the same assistant turn, never below. The PreToolUse hook structurally enforces this: if the [Rule 22] marker is absent from a text block between the previous Edit/Write and this one, the hook returns permissionDecision: deny and blocks the tool call. Retrying without the marker will deny again. Emit the block prospectively, not retroactively — the only valid path is marker-then-edit. Arguments for skipping ('conversation already covered it', 'docs-only edit', 'routine change', 'too trivial') are all invalid — see rules/change-decision-framework.md 'Ordering (required)' and 'Rationalizations that do not apply'.
"

# --- standing user rules (U-namespace) ---
# Two-tier index: titles are the always-loaded recognition layer, bodies are read
# on demand. A mature user-rules.md runs 50KB+, too large to inject, while the
# titles are self-describing enough to bind. Logic ported verbatim from
# session-start-check.sh:411-427 — same gate, same overflow fallback; only the
# destination channel changes. Absent file or zero rules injects nothing, which
# is the correct brand-new-user behaviour.
UR_FILE="$KT_KNOWLEDGE_FOLDER/rules/user-rules.md"
if [ -f "$UR_FILE" ]; then
  UR_N=$(grep -c '^### U' "$UR_FILE" 2>/dev/null)
  if [ "${UR_N:-0}" -gt 0 ]; then
    UR_HEADERS=$(grep '^### U' "$UR_FILE" 2>/dev/null | sed 's/^### //' | awk '{printf "%s%s", sep, $0; sep="; "}')
    if [ ${#UR_HEADERS} -gt 3000 ]; then
      MESSAGES="${MESSAGES}
STANDING USER RULES — ${UR_N} of the user's own rules are in force, at ${UR_FILE} (too many to index inline). Read that file before acting on anything it plausibly covers.
"
    else
      MESSAGES="${MESSAGES}
STANDING USER RULES (${UR_N}, always in force — the user's own rules, binding alongside the working rules above): ${UR_HEADERS}. These titles are the index; read ${UR_FILE} for the full text of any rule bearing on the task.
"
    fi
  fi
fi

if [ -n "$MESSAGES" ]; then
  # kt_json_escape_multiline, NOT kt_json_escape — see the comment above.
  ESCAPED=$(kt_json_escape_multiline "$MESSAGES")
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ESCAPED"
fi

exit 0
