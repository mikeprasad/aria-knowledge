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

# Emission uses kt_json_escape_multiline (config.sh), NOT kt_json_escape.
# The latter ends with `tr '\n' ' '` and would collapse this digest into one
# run-on line — silently, since the payload stays valid JSON and the hook still
# exits 0. See the helper's own comment for why the two are kept separate.

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

# --- Unit 2: opt-in directives ---
# Only the two PURE-TEXT blocks are carried here. The other two Unit-2 blocks
# stay in session-start-check.sh deliberately:
#   - tracked artifacts: records to the session ledger. Putting it in a SECOND
#     SessionStart hook means both fire on the same trigger, the first records
#     the paths, and the second filters them out and emits nothing — so which
#     channel gets the directive depends on hook execution order, silently.
#   - CODEMAP staleness: ~70 lines of find/stat/date logic that would drift
#     between two copies.
# Both are resolved by the single-emitter collapse (spec §8), not by copying.
# Text below is copied VERBATIM from session-start-check.sh — do not reword here;
# a reworded directive is a behaviour change that reads as a copy.

# SESSION.md re-entry offer — gated on session_state (source: :308-309).
if [ "$KT_SESSION_STATE" = "true" ]; then
  MESSAGES="${MESSAGES}
SESSION STATE — After the project/sub-project for this session is identified (by the PWD-based project match, or by what the user names in their opening message), locate SESSION.md at that project root (project root = nearest dir with CLAUDE.md/PROGRESS.md). If it exists with a non-empty '## Next session prompt' block: if the user's opening message included the word 'handoff', open the session by executing that prompt directly (no confirmation); otherwise tell the user a saved resume prompt exists (state its lastEvent + age from the 'at' field) and ask whether to start from it (y/n). If the prompt's 'at' is older than session_stale_days (read from ~/.claude/aria-knowledge.local.md; default 7) days, do NOT present it as live — instead state its age and ask: still relevant? [resume / archive / keep]. 'archive' = move that entry under a '## Archived sessions' heading (atlas ignores it, same as '## Pending handoffs' and the legacy '## Prior sessions'); 'keep' = leave it as-is; 'resume' = execute it. Never auto-drop an aged entry — staleness prompts, it does not evict. ALSO: if a '## Pending handoffs' section (or legacy '## Prior sessions') holds entries still marked 'unconsumed', say how many and offer them alongside the active prompt — a SESSION.md may hold several still-valid next-session prompts, and one that is stored but never offered is lost in practice. If no such prompt exists, stay quiet. The 'in-progress' mark is now written automatically by the PostToolUse hook (post-edit-check.sh) on your first edit — do NOT write SESSION.md yourself here. Offer the resume once per session.
"
fi

# Autonomy posture — Rule 35's active per-session push (source: :404-408).
# autonomy = default (or unset/unknown) injects nothing: zero behaviour change,
# zero context cost, the safe failure mode.
if [ "$KT_AUTONOMY" = "balanced" ]; then
  MESSAGES="${MESSAGES}
DECISION ROUTING (balanced) — Before asking OR auto-deciding, classify (per Rule 35): resolvable by read/grep/diff/git/config/web → investigate first, then act; objectively validatable → decide and show the validation; mechanical/already-decided → act; the user's intent/preference/judgment with no gainable visibility, or anything needing ungranted explicit approval → ask. Investigate the resolvable parts first; ask only the residual that's genuinely about the user. Either way, the option set is Rule 22 Step 4/5 output: enumerate the real alternatives, filter out any option with a provable defect (name it in one line rather than offering it), and when you decide, show what you rejected plus the validation. Asking is not an escape hatch from the analysis.
"
elif [ "$KT_AUTONOMY" = "autonomous" ]; then
  MESSAGES="${MESSAGES}
DECISION ROUTING (autonomous) — The user's decision budget is the scarce resource; your speed/context is cheap. Exhaust self-resolvable investigation before spending a human turn. Per Rule 35: decide objectively-validatable forks YOURSELF (checked against ground truth and the build-philosophy bar, Rules 13/14/18 — simplest/robust/clean, no unneeded abstraction). Run quality gates (/prospect pre-code, /retrospect post-ship) as checks, not stops. Stop and ask ONLY when it is a judgment call with no gainable visibility (and none can be gained), or it requires explicit approval not already granted (push, destructive op, scope change, credentials), or the foundational fix would change what the arc IS (its scope boundary, deliverable, or completion criteria) rather than merely make it bigger. Foundational-over-patch is NOT a fork at this setting: take the foundational fix and absorb the larger scope. Either way, the option set is Rule 22 Step 4/5 output: enumerate the real alternatives, filter out any option with a provable defect (name it in one line rather than offering it), and when you decide, show what you rejected plus the validation. Asking is not an escape hatch from the analysis.
"
fi

if [ -n "$MESSAGES" ]; then
  # kt_json_escape_multiline, NOT kt_json_escape — see the comment above.
  ESCAPED=$(kt_json_escape_multiline "$MESSAGES")
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ESCAPED"
fi

exit 0
