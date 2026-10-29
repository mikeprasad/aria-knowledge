#!/bin/sh
# session-start-check.sh — the single SessionStart hook for aria-knowledge.
#
# ROUTES EACH MESSAGE BY AUDIENCE (2026-10-25,
# docs/superpowers/specs/2026-10-25-session-start-single-emitter-spec.md):
#
#   asks a HUMAN to act (audit due, config due, run /setup, welcome, config errors)
#     → systemMessage. Renders to the user's terminal; it NEVER reaches the model.
#   instructs the MODEL
#     → hookSpecificOutput.additionalContext.
#
# Both go out in ONE JSON object. Measured on Claude Code 2.1.308 (desktop) and 2.1.310 (CLI):
# one hook may emit both fields and both are honoured — the banner reaches no API request, the
# context does. Re-measure if a later version changes hook output handling.
#
# This script absorbed session-start-rules.sh (archived under scripts/.archived/). Before the
# merge this script built ~10 KB of model instructions into the systemMessage, where no model
# ever read them; the picker, CODEMAP and project-context directives existed nowhere else.
#
# ⛔ Emit with printf only. `echo` under macOS sh halves backslashes, and the old banner failed a
#    strict JSON parse because of it. In one object, a malformed banner would take the model
#    context down with it.
# ⛔ The model channel carries VALUES. Behaviour lives in the bundled digest
#    (rules/aria-rules.md), keyed on each value line having arrived, so a truncated payload costs
#    "which values", never "which rules".
# ⛔ On source=compact there is no banner: the human saw the nags at startup.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"
. "$SCRIPT_DIR/lib-user-rules.sh"

# Hook input. `source` is startup | resume | clear | compact | fork. ⛔ Read stdin only when it is
# NOT a terminal: the harness always pipes JSON, but tests and manual runs may not, and a bare
# `cat` on a terminal blocks. Every caller that pipes must close the pipe (`</dev/null`), or this
# blocks until the timeout.
INPUT=""
[ -t 0 ] || INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//')
HOOK_SOURCE=$(printf '%s' "$INPUT" | grep -o '"source":"[^"]*"' | head -1 | sed 's/"source":"//;s/"//')

USER_MESSAGES=""
MODEL_MESSAGES=""

# Print the one JSON object, holding only the non-empty fields.
emit() {
  [ "$HOOK_SOURCE" = "compact" ] && USER_MESSAGES=""
  _ss_out=""
  if [ -n "$USER_MESSAGES" ]; then
    _ss_out="\"systemMessage\":\"$(kt_json_escape "$USER_MESSAGES")\""
  fi
  if [ -n "$MODEL_MESSAGES" ]; then
    # kt_json_escape_multiline, NOT kt_json_escape — the latter ends with `tr '\n' ' '` and
    # would collapse a structured payload into one run-on line, silently.
    _ss_model="\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$(kt_json_escape_multiline "$MODEL_MESSAGES")\"}"
    if [ -n "$_ss_out" ]; then _ss_out="${_ss_out},${_ss_model}"; else _ss_out="$_ss_model"; fi
  fi
  [ -n "$_ss_out" ] && printf '{%s}\n' "$_ss_out"
  return 0
}
emit_and_exit() { emit; exit 0; }

# Clear stale batch manifest (>30 min old) left over from crashed sessions.
# Prevents stale manifests from silently suppressing Rule 22 on subsequent
# unrelated edits. Safe no-op if no manifest exists or jq is unavailable.
kt_batch_clear_stale 1800

# Clear stale active-surfacing ledgers (>1 day old) from prior sessions.
# The ledger is session-scoped (fresh per session per D4), so anything older
# than ~24h is debris from crashed/abandoned sessions. Safe no-op if none exist.
find /tmp -maxdepth 1 -name 'aria-active-*' -mtime +1 -delete 2>/dev/null
# Clear stale session-inprogress ledgers (>1 day) from prior/crashed sessions
# (written by post-edit-check.sh's first-edit in-progress marking, v2.23.0).
find /tmp -maxdepth 1 -name 'aria-session-inprogress-*' -mtime +1 -delete 2>/dev/null

# If config file exists but failed validation, report the specific error
if [ -n "$KT_CONFIG_ERROR" ]; then
  USER_MESSAGES="aria-knowledge: $KT_CONFIG_ERROR Run /setup to reconfigure."
  emit_and_exit
fi

# If not configured, nudge setup
if [ "$KT_CONFIGURED" = "false" ]; then
  USER_MESSAGES="aria-knowledge is installed but not configured. Run /setup to configure your knowledge folder and start capturing knowledge automatically."
  emit_and_exit
fi

# Check knowledge folder exists
if [ ! -d "$KT_KNOWLEDGE_FOLDER" ]; then
  USER_MESSAGES="aria-knowledge: configured knowledge folder does not exist at $KT_KNOWLEDGE_FOLDER. Run /setup to reconfigure."
  emit_and_exit
fi

# =============================================================================
# MODEL CHANNEL — the rules files and the resolved configuration.
# Moved verbatim from session-start-rules.sh. Computed here, BEFORE every later exit, so each
# of them carries it.
# =============================================================================
#
# The rules and directives are delivered in full through the instruction-file channel, by
# ENSURING two user-scope rules files exist — that channel also reaches SUBAGENTS, which the
# hook channel does not:
#
#   ~/.claude/rules/aria-rules.md       working rules + every standing directive
#   ~/.claude/rules/aria-user-rules.md  the user's own U-rules, as a digest
#
# What is emitted here is only what a static file CANNOT know: the resolved configuration
# values and the per-session value lines below.
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

if [ "$DIGEST_WAS_PRESENT" = "yes" ]; then
  # STEADY STATE. The rules and directives are delivered in full through the file
  # channel, so re-emitting them here would duplicate ~20 KB the model already has.
  MODEL_MESSAGES="${CONFIG_LINE}
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
  MODEL_MESSAGES="ARIA WORKING RULES — in force for this session. Apply them as you work; do not wait to be asked.

$(cat "$BUNDLED_DIGEST")
"
  kt_user_rules_block
  MODEL_MESSAGES="${MODEL_MESSAGES}${KT_USER_RULES_BLOCK}"
  MODEL_MESSAGES="${MODEL_MESSAGES}
${CONFIG_LINE}
"
fi

# --- after compaction --------------------------------------------------------
# SessionStart with source "compact" is the ONLY hook channel that reaches the model
# after compaction. PreCompact and PostCompact have no hookSpecificOutput variant in
# the harness schema and both discard systemMessage, so everything they printed was
# rejected or dropped (2.1.305; error recorded 2026-10-08). The post-compaction
# context therefore lives here. It goes FIRST because the hook channel delivers about
# the first 2,000 characters, and the rules pointer is the part whose loss does damage.
if [ "$HOOK_SOURCE" = "compact" ]; then
  COMPACT_BLOCK=""
  # Rules pointer — a pointer, never the digest body (see post-compact history in
  # scripts/.archived/post-compact-check.sh: re-sending ~20 KB got truncated mid-rule).
  if [ -f "$INSTALLED_DIGEST" ]; then
    COMPACT_BLOCK="ARIA WORKING RULES — still in force after compaction. The 38 working rules and every standing directive are at ${INSTALLED_DIGEST}, and the user's own standing rules at ${HOME}/.claude/rules/aria-user-rules.md. If either is no longer in your context, Read it before your next tool call rather than proceeding from memory of it.
"
  fi
  # Active-surfacing ledger: knowledge files surfaced earlier this session.
  if [ "$KT_ACTIVE_SURFACING" = "true" ] && [ -n "$SESSION_ID" ]; then
    LEDGER="/tmp/aria-active-${SESSION_ID}"
    if [ -s "$LEDGER" ]; then
      LEDGER_COUNT=$(wc -l < "$LEDGER" | tr -d ' ')
      LEDGER_LIST=$(head -5 "$LEDGER" | sed 's/^/  - /' | tr '\n' ';' | sed 's/;$//;s/;/ /g')
      COMPACT_BLOCK="${COMPACT_BLOCK}ARIA ACTIVE — Compaction wiped context. ${LEDGER_COUNT} knowledge file(s) were previously surfaced this session: ${LEDGER_LIST}. Re-Read the relevant ones (prefer recently-active topic; skip if no longer applicable) and summarize what reloaded in 1-2 sentences before continuing. Ledger preserved at ${LEDGER}.
"
    fi
  fi
  # This session's pre-compaction snapshot, written by pre-compact-check.sh. Matched
  # by session id, so another session's snapshot is never offered as this one's.
  if [ "$KT_AUTO_CAPTURE" != "false" ] && [ -n "$SESSION_ID" ]; then
    SID8=$(printf '%s' "$SESSION_ID" | cut -c1-8)
    SNAP=$(ls -t "$KT_KNOWLEDGE_FOLDER/intake/pre-compact-captures/"*"_${SID8}.md" 2>/dev/null | head -1)
    if [ -n "$SNAP" ]; then
      COMPACT_BLOCK="${COMPACT_BLOCK}ARIA CAPTURE — this session's transcript was saved before compaction to ${SNAP}. Uncaptured knowledge from the prior conversation may exist; offer the user /extract on it before continuing.
"
    fi
  fi
  MODEL_MESSAGES="${COMPACT_BLOCK}${MODEL_MESSAGES}"
fi

# =============================================================================
# MODEL CHANNEL — per-session value lines. Each line's behaviour is a directive in the digest
# ("Conditional on a session-start value line"); a line that is not sent means that directive
# is off. These are values, not instructions, so they stay small.
# =============================================================================

# Project context — only if both opt-ins are enabled AND CWD matches a configured project
if [ "$KT_PROJECTS_ENABLED" = "true" ] && [ "$KT_AUTO_LOAD_PROJECT_CONTEXT" = "true" ]; then
  CURRENT_PROJECT=$(kt_project_for_path "$PWD")
  if [ -n "$CURRENT_PROJECT" ]; then
    MODEL_MESSAGES="${MODEL_MESSAGES}ARIA PROJECT — this session started inside configured project '${CURRENT_PROJECT}'.
"
  fi
fi

# v2.16.1: tracked-artifacts active load — fires when active_knowledge_surfacing
# is enabled AND PWD substring-matches a configured project. Surfaces CODEMAP
# directory + (if multi-repo) STITCH with staleness annotation.
# ⚠ Dead until 2026-10-25: it read the session id from "$INPUT", which this script never set,
# so it never fired from SessionStart. INPUT is now read at the top.
if [ "$KT_ACTIVE_SURFACING" = "true" ] && [ "$KT_PROJECTS_ENABLED" = "true" ]; then
  TA_SESSION_ID="$SESSION_ID"
  . "$SCRIPT_DIR/lib-tracked-artifacts.sh"
  kt_artifact_compute_for_path "$PWD"
  if [ -n "$TA_SESSION_ID" ] && [ "$KT_ARTIFACTS_COUNT" -gt 0 ]; then
    TA_LEDGER="/tmp/aria-active-${TA_SESSION_ID}"
    kt_artifact_filter_ledger "$TA_LEDGER"
    if [ "$KT_ARTIFACTS_COUNT" -gt 0 ]; then
      kt_artifact_record_ledger "$TA_LEDGER"
      MODEL_MESSAGES="${MODEL_MESSAGES}${KT_ARTIFACTS_INSTRUCTION}
"
    fi
  fi
fi

# SessionStart project picker — opt-in, non-blocking (spec 2026-06-06).
# Gated: projects_enabled + session_start_project_picker. Sends a project menu (generated from
# projects_list) only when CWD is NOT already inside a configured project (that CWD case is
# auto_load_project_context's job above). Not on compact: the offer is once per session and
# belongs to the opening message.
if [ "$KT_PROJECTS_ENABLED" = "true" ] && [ "$KT_SESSION_START_PROJECT_PICKER" = "true" ] \
   && [ "$HOOK_SOURCE" != "compact" ]; then
  if [ -z "$(kt_project_for_path "$PWD")" ]; then
    PICKER_MENU=$(kt_project_menu)
    if [ -n "$PICKER_MENU" ]; then
      # Option 3 (ADR-pending unify): inline pm_projects_root read; same key as ARIA Assist.
      PICKER_ROOT=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^pm_projects_root:' | sed 's/^pm_projects_root: *//')
      [ -z "$PICKER_ROOT" ] && PICKER_ROOT="$HOME/Projects"
      case "$PICKER_ROOT" in "~"/*) PICKER_ROOT="$HOME/${PICKER_ROOT#\~/}" ;; esac
      MODEL_MESSAGES="${MODEL_MESSAGES}ARIA PROJECTS — menu: ${PICKER_MENU}; projects root: ${PICKER_ROOT}.
"
    fi
  fi
fi

# CODEMAP detection — find codemaps in project directories, annotate with
# staleness per /audit knowledge Step 5d criteria so stale maps are visible
# at session start without running a full audit. Graceful on missing git,
# missing Last-updated header, or non-git paths — falls back to mtime and
# zero-files-changed respectively; worst case shows "(no date)".
# Skip maps under hidden directories (.wt-* worktrees, scratch copies): they are duplicates of a
# real repo's map, and with the 5-map cap they crowded the real ones out. Measured 2026-10-29 at a
# multi-repo root: the first maps found were all `.wt-*` copies. The test is on the path RELATIVE
# to $PWD, so a session that itself starts inside a hidden directory still sees its own maps.
CODEMAPS=$(find "$PWD" -maxdepth 2 -name "CODEMAP.md" 2>/dev/null \
  | while IFS= read -r _cm_p; do
      # Leading-paren pattern form on purpose: inside $( ) bash 3.2 reads a bare `pattern)` as the
      # end of the command substitution and fails to parse.
      case "${_cm_p#"$PWD"/}" in (.*/*) ;; (*) printf '%s\n' "$_cm_p" ;; esac
    done | head -5)
if [ -n "$CODEMAPS" ]; then
  CM_MSG=""
  CM_CUR_NAMES=""
  CM_CUR_N=0
  CM_TODAY_EPOCH=$(date +%s)
  _cm_old_ifs="$IFS"
  IFS='
'
  for cm in $CODEMAPS; do
    CM_REL=$(echo "$cm" | sed "s|$PWD/||")
    CM_IS_CURRENT=0

    # Parse "> Last updated: YYYY-MM-DD" from CODEMAP header; fall back to mtime
    CM_DATE=$(grep -m1 -E '^> Last updated: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$cm" 2>/dev/null \
      | sed -E 's/^> Last updated: ([0-9]{4}-[0-9]{2}-[0-9]{2}).*/\1/')
    if [ -z "$CM_DATE" ]; then
      CM_DATE=$(stat -f "%Sm" -t "%Y-%m-%d" "$cm" 2>/dev/null)
    fi

    if [ -z "$CM_DATE" ]; then
      CM_ENTRY="$CM_REL (no date)"
    else
      CM_EPOCH=$(date -j -f "%Y-%m-%d" "$CM_DATE" +%s 2>/dev/null)
      if [ -z "$CM_EPOCH" ]; then
        CM_ENTRY="$CM_REL (unparseable date: $CM_DATE)"
      else
        CM_DAYS=$(( (CM_TODAY_EPOCH - CM_EPOCH) / 86400 ))

        # Count files changed in the codemap's directory since its last-updated date
        CM_FILES=0
        if command -v git >/dev/null 2>&1; then
          CM_DIR=$(dirname "$cm")
          CM_FILES=$(cd "$CM_DIR" 2>/dev/null && git log --name-only --since="$CM_DATE" --pretty=format:"" 2>/dev/null \
            | grep -v '^$' | sort -u | wc -l | tr -d ' ')
          [ -z "$CM_FILES" ] && CM_FILES=0
        fi

        # Classification matches /audit knowledge Step 5d exactly
        if [ "$CM_DAYS" -gt 30 ] && [ "$CM_FILES" -gt 0 ]; then
          CM_CLASS="stale"
        elif [ "$CM_DAYS" -gt 14 ] && [ "$CM_FILES" -gt 20 ]; then
          CM_CLASS="possibly stale"
        else
          CM_CLASS="current"
          CM_IS_CURRENT=1
        fi

        CM_ENTRY="$CM_REL (updated ${CM_DAYS}d ago, ${CM_FILES} files changed — ${CM_CLASS})"
      fi
    fi

    # Current codemaps need no action — collapse them to a name-only tail and
    # show full staleness detail only for stale/possibly-stale/unknown-date maps.
    if [ "$CM_IS_CURRENT" = "1" ]; then
      CM_CUR_N=$((CM_CUR_N + 1))
      [ -z "$CM_CUR_NAMES" ] && CM_CUR_NAMES="$CM_REL" || CM_CUR_NAMES="$CM_CUR_NAMES, $CM_REL"
    else
      [ -z "$CM_MSG" ] && CM_MSG="$CM_ENTRY" || CM_MSG="$CM_MSG, $CM_ENTRY"
    fi
  done
  IFS="$_cm_old_ifs"

  CM_FULL="$CM_MSG"
  if [ "$CM_CUR_N" -gt 0 ]; then
    [ -n "$CM_FULL" ] && CM_FULL="${CM_FULL}; +${CM_CUR_N} current: ${CM_CUR_NAMES}" || CM_FULL="${CM_CUR_N} current: ${CM_CUR_NAMES}"
  fi
  if [ -n "$CM_FULL" ]; then
    MODEL_MESSAGES="${MODEL_MESSAGES}ARIA CODEMAPS — ${CM_FULL}.
"
  fi
fi

# Usage snapshot path. The status-line meter (/statusline) persists a context/5h/7d usage
# snapshot per account to ~/.claude/aria-statusline-state-<accountUuid>.json. Resolve the
# CURRENT session's snapshot via the shared runtime-aware resolver (config.sh
# kt_resolve_account) so the model reads its OWN account's usage under both the CLI and
# Claude-Desktop-hosted runtimes. The behaviour (answer usage questions from it; never decide
# to stop from it) is the TASK BUDGET directive in the digest.
if ls "$HOME"/.claude/aria-statusline-state-*.json >/dev/null 2>&1; then
  _uk=$(kt_resolve_account | cut -f1)
  [ -z "$_uk" ] && _uk="default"
  MODEL_MESSAGES="${MODEL_MESSAGES}ARIA USAGE — this account's usage snapshot: ~/.claude/aria-statusline-state-${_uk}.json.
"
fi

# =============================================================================
# USER CHANNEL — things a human must decide or authorise.
# =============================================================================

# Date arithmetic helper — returns epoch seconds for a YYYY-MM-DD date
# Supports macOS (date -j -f) and Linux (date -d)
# Returns empty string on failure (caller must check)
date_to_epoch() {
  date -j -f "%Y-%m-%d" "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null
}

TODAY=$(date +%Y-%m-%d)
TODAY_EPOCH=$(date_to_epoch "$TODAY")

# Guard: if we can't compute today's epoch, date commands are incompatible
if [ -z "$TODAY_EPOCH" ]; then
  USER_MESSAGES="aria-knowledge: failed to compute today's date as epoch. Date commands may not be compatible with this platform."
  emit_and_exit
fi

KNOWLEDGE_LOG="$KT_KNOWLEDGE_FOLDER/logs/knowledge-audit-log.md"
CONFIG_LOG="$KT_KNOWLEDGE_FOLDER/logs/config-audit-log.md"

# First-run detection — show welcome instead of audit prompts for new users
IS_FIRST_RUN=false
if [ -f "$KNOWLEDGE_LOG" ]; then
  if grep -q '(no audits yet)' "$KNOWLEDGE_LOG"; then
    IS_FIRST_RUN=true
  fi
else
  IS_FIRST_RUN=true
fi

if [ "$IS_FIRST_RUN" = "true" ]; then
  # The welcome replaces the audit nags. It no longer exits early: the first run is usually the
  # first-install session, which is exactly when the model channel's fallback arm matters.
  USER_MESSAGES="ARIA Knowledge Active: Auto insights collection, Rule 22 logic on edits, context surfacing, audit prompts, and precompact capture. Run /help for commands, see QUICKSTART.md for more."
  emit
  echo "$(date +%Y-%m-%dT%H:%M:%S) session-start-check: first-run welcome model=${#MODEL_MESSAGES}" >> "$KT_KNOWLEDGE_FOLDER/logs/hook-debug.log" 2>/dev/null
  exit 0
fi

# Check knowledge audit cadence — OR-logic: entry-count threshold OR elapsed days.
# Entry count is the primary activity-driven signal; elapsed days is the safety net
# for low-activity weeks. The count comes from scripts/count-backlog-entries.sh, the one counter
# /audit knowledge also uses: all four action-eligible backlogs (insights, decisions,
# extraction, rules), every live heading shape — not just `### `, which under-reported the
# 127th pass by 35%. intake/ideas/ (per-file since v2.11) is deliberately excluded — ideas
# route out, counting them would conflate staging with action. Any failure reads as 0, as the
# inline loop this replaces did.
KA_DUE=false
BACKLOG_COUNT=0
KA_OFFLEVEL_NOTE=""
_kt_cb=$(sh "$SCRIPT_DIR/count-backlog-entries.sh" "$KT_KNOWLEDGE_FOLDER" 2>/dev/null | grep '^TOTAL:')
case "$_kt_cb" in
  TOTAL:*)
    _kt_live=$(printf '%s' "$_kt_cb" | sed -n 's/.* live=\([0-9][0-9]*\).*/\1/p')
    _kt_canon=$(printf '%s' "$_kt_cb" | sed -n 's/.*canonical=\([0-9][0-9]*\).*/\1/p')
    case "$_kt_live" in ''|*[!0-9]*) _kt_live=0 ;; esac
    case "$_kt_canon" in ''|*[!0-9]*) _kt_canon=$_kt_live ;; esac
    BACKLOG_COUNT=$_kt_live
    [ "$_kt_live" -gt "$_kt_canon" ] && KA_OFFLEVEL_NOTE=" ($((_kt_live - _kt_canon)) not at ### level)"
    ;;
esac

# Tier boundaries (derived from threshold via fixed +15/+30 offsets).
KA_TIER_RECOMMENDED=$((KT_AUDIT_TRIGGER_THRESHOLD + 15))
KA_TIER_OVERDUE=$((KT_AUDIT_TRIGGER_THRESHOLD + 30))

DAYS_SINCE_KA=""
if [ -f "$KNOWLEDGE_LOG" ]; then
  LAST_KA_DATE=$(grep '^\- \*\*Date:\*\*' "$KNOWLEDGE_LOG" | head -1 | sed 's/.*\*\*Date:\*\* //' | sed 's/ .*//')
  if [ -n "$LAST_KA_DATE" ] && echo "$LAST_KA_DATE" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    LAST_KA_EPOCH=$(date_to_epoch "$LAST_KA_DATE")
    if [ -n "$LAST_KA_EPOCH" ]; then
      DAYS_SINCE_KA=$(( (TODAY_EPOCH - LAST_KA_EPOCH) / 86400 ))
    else
      KA_DUE=true
    fi
  else
    KA_DUE=true
  fi
else
  KA_DUE=true
fi

# Entry-count tier (primary trigger)
KA_COUNT_MSG=""
if [ "$BACKLOG_COUNT" -ge "$KA_TIER_OVERDUE" ]; then
  KA_COUNT_MSG="Knowledge audit overdue — ${BACKLOG_COUNT} entries${KA_OFFLEVEL_NOTE}, plan for multi-pass. "
elif [ "$BACKLOG_COUNT" -ge "$KA_TIER_RECOMMENDED" ]; then
  KA_COUNT_MSG="Knowledge audit recommended — ${BACKLOG_COUNT} entries${KA_OFFLEVEL_NOTE}, near one-pass ceiling. "
elif [ "$BACKLOG_COUNT" -ge "$KT_AUDIT_TRIGGER_THRESHOLD" ]; then
  KA_COUNT_MSG="Knowledge audit suggested — ${BACKLOG_COUNT} entries${KA_OFFLEVEL_NOTE} ready for review. "
fi

# Day-based safety net
KA_DAYS_FIRED=false
if [ -n "$DAYS_SINCE_KA" ] && [ "$DAYS_SINCE_KA" -ge "$KT_CADENCE_KNOWLEDGE" ]; then
  KA_DAYS_FIRED=true
fi

# Compose prompt — entry-tier message takes precedence; day-context appended if both fired.
if [ -n "$KA_COUNT_MSG" ]; then
  if [ "$KA_DAYS_FIRED" = "true" ]; then
    USER_MESSAGES="${USER_MESSAGES}${KA_COUNT_MSG}(trigger: count=${BACKLOG_COUNT} threshold=${KT_AUDIT_TRIGGER_THRESHOLD}; also ${DAYS_SINCE_KA}d since last audit) Run /audit knowledge? (or /audit for the full menu) "
  else
    USER_MESSAGES="${USER_MESSAGES}${KA_COUNT_MSG}(trigger: count=${BACKLOG_COUNT} threshold=${KT_AUDIT_TRIGGER_THRESHOLD}) Run /audit knowledge? (or /audit for the full menu) "
  fi
elif [ "$KA_DAYS_FIRED" = "true" ]; then
  USER_MESSAGES="${USER_MESSAGES}Knowledge audit due — ${DAYS_SINCE_KA} days since last audit. (trigger: days=${DAYS_SINCE_KA} threshold=${KT_CADENCE_KNOWLEDGE}; backlog=${BACKLOG_COUNT}) Run /audit knowledge? (or /audit for the full menu) "
fi

if [ "$KA_DUE" = "true" ]; then
  USER_MESSAGES="${USER_MESSAGES}No previous Knowledge Audit found. Run /audit knowledge? (or /audit for the full menu) "
fi

# Check config audit cadence
CA_DUE=false
if [ -f "$CONFIG_LOG" ]; then
  LAST_CA_DATE=$(grep '^\- \*\*Date:\*\*' "$CONFIG_LOG" | head -1 | sed 's/.*\*\*Date:\*\* //' | sed 's/ .*//')
  if [ -n "$LAST_CA_DATE" ] && echo "$LAST_CA_DATE" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    LAST_CA_EPOCH=$(date_to_epoch "$LAST_CA_DATE")
    if [ -n "$LAST_CA_EPOCH" ]; then
      DAYS_SINCE_CA=$(( (TODAY_EPOCH - LAST_CA_EPOCH) / 86400 ))
      if [ "$DAYS_SINCE_CA" -ge "$KT_CADENCE_CONFIG" ]; then
        USER_MESSAGES="${USER_MESSAGES}Config audit due (${DAYS_SINCE_CA} days). Run /audit config? (or /audit for the full menu) "
      fi
    else
      CA_DUE=true
    fi
  else
    CA_DUE=true
  fi
else
  CA_DUE=true
fi
if [ "$CA_DUE" = "true" ]; then
  USER_MESSAGES="${USER_MESSAGES}No previous Config Audit found. Run /audit config? (or /audit for the full menu) "
fi

# Check for plugin version upgrade — version-mismatch takes precedence over cadence.
# Read installed plugin version from the manifest and compare against the version
# recorded in config the last time /setup ran. Mismatch means the user upgraded the
# plugin (or downgraded) without re-running /setup, so template diffs and any new
# config keys haven't been applied yet.
INSTALLED_VERSION=""
if [ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ]; then
  INSTALLED_VERSION=$(grep '"version"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')
fi

VERSION_PROMPTED=false
if [ -n "$INSTALLED_VERSION" ] && [ -n "$KT_LAST_SETUP_VERSION" ] && [ "$INSTALLED_VERSION" != "$KT_LAST_SETUP_VERSION" ]; then
  USER_MESSAGES="${USER_MESSAGES}ARIA was updated (last /setup ran on v${KT_LAST_SETUP_VERSION}, plugin is now v${INSTALLED_VERSION}). Run /setup to apply template diffs and surface any new config keys? "
  VERSION_PROMPTED=true
fi

# Check update cadence — parse last /setup date from config file.
# Only fires if the version-mismatch prompt above did not fire (mismatch is the
# stronger signal; cadence is the safety-net for users who don't upgrade often).
if [ "$VERSION_PROMPTED" = "false" ]; then
  LAST_SETUP_DATE=$(grep '/setup on ' "$KT_CONFIG" | tail -1 | sed 's|.*/setup on ||' | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
  if [ -n "$LAST_SETUP_DATE" ]; then
    LAST_SETUP_EPOCH=$(date_to_epoch "$LAST_SETUP_DATE")
    if [ -n "$LAST_SETUP_EPOCH" ]; then
      DAYS_SINCE_SETUP=$(( (TODAY_EPOCH - LAST_SETUP_EPOCH) / 86400 ))
      if [ "$DAYS_SINCE_SETUP" -ge "$KT_CADENCE_UPDATE" ]; then
        USER_MESSAGES="${USER_MESSAGES}ARIA Update check due (${DAYS_SINCE_SETUP} days). Run /setup? "
      fi
    fi
  fi
fi

emit

# Diagnostic log — confirms hook ran, distinguishes success from silent failure
echo "$(date +%Y-%m-%dT%H:%M:%S) session-start-check: messages=${#USER_MESSAGES} model=${#MODEL_MESSAGES} source=${HOOK_SOURCE:-none}" >> "$KT_KNOWLEDGE_FOLDER/logs/hook-debug.log" 2>/dev/null
