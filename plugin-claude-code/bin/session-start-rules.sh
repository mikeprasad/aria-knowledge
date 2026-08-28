#!/bin/sh
# session-start-rules.sh — SessionStart hook for aria-knowledge.
#
# Sole owner of the MODEL-directed session-start channel. Its sibling
# bin/session-start-check.sh emits systemMessage, which renders to the USER's
# terminal and never reaches the model. That split is deliberate: a nag asks a
# human to authorise something; the payload here instructs the model.
#
# ⛔ Never emit systemMessage from this script.
# ⛔ Never add a new hook to do work this one can do. It already runs once per
#    session and already resolves config — a PostToolUse sibling would fire on
#    every edit in every project to achieve the same one-session lag (§10.6: the
#    instruction-file set is snapshotted at session start, so NOTHING written
#    mid-session reaches the current session, whichever hook writes it).
#
# WHAT THIS DOES, AND WHY IT NO LONGER CARRIES THE DIRECTIVES.
# The rules and directives used to be emitted here, and the harness delivers only
# the first ~2,000 characters of a hook payload — measured, 2 of 38 rules and 0 of
# 8 directives arrived, in every session since install. So this hook now ENSURES
# two user-scope rules files exist, and those are delivered in full through the
# instruction-file channel, which additionally reaches SUBAGENTS (the hook channel
# does not — every delegated agent previously ran with zero ARIA rules).
#
#   ~/.claude/rules/aria-rules.md       working rules + every standing directive
#   ~/.claude/rules/aria-user-rules.md  the user's own U-rules, as a digest
#
# What remains emitted here is only what a static file CANNOT know: the resolved
# configuration values. The file states each directive's condition; this supplies
# the values those conditions read. A truncated emission therefore costs only
# "which posture is selected", for which the file states a safe default — the
# design is degradation-tolerant rather than sized against a cap that is per-tool
# and can change with no client release.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"
. "$SCRIPT_DIR/lib-user-rules.sh"

[ -n "$KT_CONFIG_ERROR" ] && exit 0
[ "$KT_CONFIGURED" = "false" ] && exit 0
[ ! -d "$KT_KNOWLEDGE_FOLDER" ] && exit 0

BUNDLED_DIGEST="$SCRIPT_DIR/../rules/aria-rules.md"
RULES_DIR="$HOME/.claude/rules"
INSTALLED_DIGEST="$RULES_DIR/aria-rules.md"
INSTALLED_URULES="$RULES_DIR/aria-user-rules.md"
SOURCE_URULES="$KT_KNOWLEDGE_FOLDER/rules/user-rules.md"

# --- ensure the user-scope rules files exist and are current -----------------
# Every write is guarded, so the number of times this hook fires is irrelevant:
# the first fire writes, every later one costs a `cmp` and a timestamp test. That
# guard, not the firing count, is what keeps this cheap — SessionStart registers
# with no matcher, so it fires on startup, resume, clear and compact alike.
#
# ⛔ Failure here must never break the hook. A read-only HOME, a full disk or a
# missing mkdir leaves the files absent, which the fallback arm below handles.
kt_ensure_rules_files() {
  [ -f "$BUNDLED_DIGEST" ] || return 0
  mkdir -p "$RULES_DIR" 2>/dev/null || return 0

  # Digest: byte-compare against the bundled copy. Exact, self-healing across
  # plugin upgrades, and no version marker to keep in sync. This file is a plugin
  # artifact — the user-editable surface is working-rules.md in their knowledge
  # folder — and the file says so in its own header.
  if ! cmp -s "$BUNDLED_DIGEST" "$INSTALLED_DIGEST" 2>/dev/null; then
    cp "$BUNDLED_DIGEST" "$INSTALLED_DIGEST" 2>/dev/null || return 0
  fi

  # U-rules: regenerate whenever the RENDERED CONTENT differs from what is installed.
  #
  # ⛔ This was a source-vs-output timestamp test — `$SOURCE_URULES -nt $INSTALLED_URULES`
  # — and it was BLIND TO THE GENERATOR CHANGING. A plugin upgrade that altered how a rule
  # renders left every existing user on their OLD rendering until they happened to edit
  # user-rules.md, so the fix shipped and did nothing. Measured 2026-08-28 while releasing
  # the four-rendering change: the regeneration produced a byte-identical file through this
  # guard, and only a T6 acceptance criterion that could not pass revealed it.
  #
  # ⚠ Adding the generator to the timestamp test does NOT repair it: the plugin ships as a
  # zip and unzip preserves stored mtimes, so a freshly-installed generator is routinely
  # OLDER than the user's existing rendering — the guard would stay silent on the commonest
  # upgrade path. Content is the only sound instrument, which is exactly what the digest arm
  # above already uses and for the reason its own comment gives. Cost measured at ~12 ms per
  # session start against this hook's 10 s timeout.
  #
  # The temp-then-mv shape is a consequence, not a flourish: comparing content requires
  # rendering it somewhere first, and it makes the write atomic, where the old in-place `>`
  # truncated the live always-on file and could leave it partial. The temp sits in the same
  # directory so the mv cannot cross filesystems, and its name does not end in `.md`, so the
  # instruction-file glob cannot pick it up mid-write.
  if [ -f "$SOURCE_URULES" ]; then
    kt_user_rules_block
    if [ -n "$KT_USER_RULES_BLOCK" ]; then
      _kt_ur_tmp="${INSTALLED_URULES}.tmp$$"
      {
        printf '# ARIA — Your Standing Rules\n\n'
        printf 'Generated by aria-knowledge from %s. Do not edit this file; edit that one.\n' "$SOURCE_URULES"
        printf '%s' "$KT_USER_RULES_BLOCK"
      } > "$_kt_ur_tmp" 2>/dev/null || { rm -f "$_kt_ur_tmp" 2>/dev/null; return 0; }
      if cmp -s "$_kt_ur_tmp" "$INSTALLED_URULES" 2>/dev/null; then
        rm -f "$_kt_ur_tmp" 2>/dev/null
      else
        mv -f "$_kt_ur_tmp" "$INSTALLED_URULES" 2>/dev/null || rm -f "$_kt_ur_tmp" 2>/dev/null
      fi
    fi
  fi
  return 0
}
# ⛔ CAPTURE PRESENCE BEFORE ENSURING, and do not "tidy" this ordering away.
# The arm below must branch on whether the file was there when this session's
# instruction-file snapshot was taken — i.e. BEFORE this hook ran. Testing after
# the ensure step makes the fallback arm unreachable whenever the write succeeds,
# which is nearly always, and the first session after install then receives the
# config line and NOTHING ELSE: the file exists on disk but §10.6's snapshot has
# already been taken, so it is not delivered until the next session.
# Measured, before this guard existed: arm 1 emitted 270 chars, 0 of 38 rules.
if [ -f "$INSTALLED_DIGEST" ]; then
  DIGEST_WAS_PRESENT=yes
else
  DIGEST_WAS_PRESENT=no
fi

kt_ensure_rules_files

# --- the resolved configuration values --------------------------------------
# The ONLY thing a byte-identical bundled file cannot carry. Each directive's
# condition lives in the file, keyed on these names.
CONFIG_LINE="ARIA CONFIG — knowledge_folder=${KT_KNOWLEDGE_FOLDER} autonomy=${KT_AUTONOMY:-default} session_state=${KT_SESSION_STATE:-false} auto_capture=${KT_AUTO_CAPTURE:-true} active_surfacing=${KT_ACTIVE_SURFACING:-false}. These are the values the standing directives in ~/.claude/rules/aria-rules.md are keyed on."

MESSAGES=""

if [ "$DIGEST_WAS_PRESENT" = "yes" ]; then
  # STEADY STATE. The rules and directives are delivered in full through the file
  # channel, so re-emitting them here would duplicate ~20 KB the model already has.
  MESSAGES="${CONFIG_LINE}
"
else
  # FALLBACK, one session only. The ensure step above just wrote the file (or
  # could not), so this arm covers the gap before the instruction-file snapshot
  # picks it up. It carries the bundled digest — which now contains every standing
  # directive, so there is nothing to inline separately — plus the U-rule block.
  #
  # ⛔ Do NOT re-add inline directive blocks here. They were deleted when the
  # digest absorbed them; a copy would be a second source with nothing comparing
  # the two. The digest leads deliberately: the harness delivers the first ~2,000
  # characters, so whichever block is first is the only one that arrives.
  MESSAGES="ARIA WORKING RULES — in force for this session. Apply them as you work; do not wait to be asked.

$(cat "$BUNDLED_DIGEST")
"
  kt_user_rules_block
  MESSAGES="${MESSAGES}${KT_USER_RULES_BLOCK}"
  MESSAGES="${MESSAGES}
${CONFIG_LINE}
"
fi

if [ -n "$MESSAGES" ]; then
  # kt_json_escape_multiline, NOT kt_json_escape — the latter ends with
  # `tr '\n' ' '` and would collapse the payload into one run-on line, silently,
  # since the result stays valid JSON and the hook still exits 0.
  ESCAPED=$(kt_json_escape_multiline "$MESSAGES")
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ESCAPED"
fi

exit 0
