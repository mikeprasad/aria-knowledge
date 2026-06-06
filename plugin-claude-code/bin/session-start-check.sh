#!/bin/sh
# session-start-check.sh — SessionStart hook for aria-knowledge
# Checks audit cadences and prompts when audits are due.
#
# v2.10.6: RULE 22 ORDERING text rewritten to describe v2.10.5+ deny mechanism
# accurately (the v2.10.5 wording claimed "hook cannot enforce" which
# contradicted the new structural enforcement). Added TASK BUDGET guardrail
# (prompts Claude to surface strain symptoms to the user who has UI-side
# visibility) and MEMORY PATHWAY guardrail (routes recent models' enhanced
# file-system memory through ARIA's intake/extract/clip flow).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

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
  MSG=$(kt_json_escape "aria-knowledge: $KT_CONFIG_ERROR Run /setup to reconfigure.")
  echo '{"systemMessage":"'"$MSG"'"}'
  exit 0
fi

# If not configured, nudge setup
if [ "$KT_CONFIGURED" = "false" ]; then
  echo '{"systemMessage":"aria-knowledge is installed but not configured. Run /setup to configure your knowledge folder and start capturing knowledge automatically."}'
  exit 0
fi

# Check knowledge folder exists
if [ ! -d "$KT_KNOWLEDGE_FOLDER" ]; then
  MSG=$(kt_json_escape "aria-knowledge: configured knowledge folder does not exist at $KT_KNOWLEDGE_FOLDER. Run /setup to reconfigure.")
  echo '{"systemMessage":"'"$MSG"'"}'
  exit 0
fi

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
  echo '{"systemMessage":"aria-knowledge: failed to compute today'\''s date as epoch. Date commands may not be compatible with this platform."}'
  exit 0
fi

KNOWLEDGE_LOG="$KT_KNOWLEDGE_FOLDER/logs/knowledge-audit-log.md"
CONFIG_LOG="$KT_KNOWLEDGE_FOLDER/logs/config-audit-log.md"

MESSAGES=""

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
  MESSAGES="ARIA Knowledge Active: Auto insights collection, Rule 22 logic on edits, context surfacing, audit prompts, and precompact capture. Run /help for commands, see QUICKSTART.md for more."
  MESSAGES_ESCAPED=$(kt_json_escape "$MESSAGES")
  echo '{"systemMessage":"'"$MESSAGES_ESCAPED"'"}'
  echo "$(date +%Y-%m-%dT%H:%M:%S) session-start-check: first-run welcome" >> "$KT_KNOWLEDGE_FOLDER/logs/hook-debug.log" 2>/dev/null
  exit 0
fi

# Check knowledge audit cadence — OR-logic: entry-count threshold OR elapsed days.
# Entry count is the primary activity-driven signal; elapsed days is the safety net
# for low-activity weeks. Counts ^### entries across insights + decisions + extraction
# backlogs. intake/ideas/ (per-file since v2.11) is deliberately excluded — ideas route
# out, counting them would conflate staging with action.
KA_DUE=false
BACKLOG_COUNT=0
for _kt_bl in "$KT_KNOWLEDGE_FOLDER/intake/insights-backlog.md" \
              "$KT_KNOWLEDGE_FOLDER/intake/decisions-backlog.md" \
              "$KT_KNOWLEDGE_FOLDER/intake/extraction-backlog.md"; do
  if [ -f "$_kt_bl" ]; then
    _kt_n=$(awk '/^---$/{sep++; next} sep>=1 && /^### /{c++} END{print c+0}' "$_kt_bl" 2>/dev/null)
    case "$_kt_n" in
      ''|*[!0-9]*) _kt_n=0 ;;
    esac
    BACKLOG_COUNT=$((BACKLOG_COUNT + _kt_n))
  fi
done

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
  KA_COUNT_MSG="Knowledge audit overdue — ${BACKLOG_COUNT} entries, plan for multi-pass. "
elif [ "$BACKLOG_COUNT" -ge "$KA_TIER_RECOMMENDED" ]; then
  KA_COUNT_MSG="Knowledge audit recommended — ${BACKLOG_COUNT} entries, near one-pass ceiling. "
elif [ "$BACKLOG_COUNT" -ge "$KT_AUDIT_TRIGGER_THRESHOLD" ]; then
  KA_COUNT_MSG="Knowledge audit suggested — ${BACKLOG_COUNT} entries ready for review. "
fi

# Day-based safety net
KA_DAYS_FIRED=false
if [ -n "$DAYS_SINCE_KA" ] && [ "$DAYS_SINCE_KA" -ge "$KT_CADENCE_KNOWLEDGE" ]; then
  KA_DAYS_FIRED=true
fi

# Compose prompt — entry-tier message takes precedence; day-context appended if both fired.
if [ -n "$KA_COUNT_MSG" ]; then
  if [ "$KA_DAYS_FIRED" = "true" ]; then
    MESSAGES="${MESSAGES}${KA_COUNT_MSG}(trigger: count=${BACKLOG_COUNT} threshold=${KT_AUDIT_TRIGGER_THRESHOLD}; also ${DAYS_SINCE_KA}d since last audit) Run /audit-knowledge? "
  else
    MESSAGES="${MESSAGES}${KA_COUNT_MSG}(trigger: count=${BACKLOG_COUNT} threshold=${KT_AUDIT_TRIGGER_THRESHOLD}) Run /audit-knowledge? "
  fi
elif [ "$KA_DAYS_FIRED" = "true" ]; then
  MESSAGES="${MESSAGES}Knowledge audit due — ${DAYS_SINCE_KA} days since last audit. (trigger: days=${DAYS_SINCE_KA} threshold=${KT_CADENCE_KNOWLEDGE}; backlog=${BACKLOG_COUNT}) Run /audit-knowledge? "
fi

if [ "$KA_DUE" = "true" ]; then
  MESSAGES="${MESSAGES}No previous Knowledge Audit found. Run /audit-knowledge? "
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
        MESSAGES="${MESSAGES}Config audit due (${DAYS_SINCE_CA} days). Run /audit-config? "
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
  MESSAGES="${MESSAGES}No previous Config Audit found. Run /audit-config? "
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
  MESSAGES="${MESSAGES}ARIA was updated (last /setup ran on v${KT_LAST_SETUP_VERSION}, plugin is now v${INSTALLED_VERSION}). Run /setup to apply template diffs and surface any new config keys? "
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
        MESSAGES="${MESSAGES}ARIA Update check due (${DAYS_SINCE_SETUP} days). Run /setup? "
      fi
    fi
  fi
fi

# Rule 22 ordering — describes v2.10.6 structural enforcement accurately.
# Replaces the v2.10.4 text that claimed "hook cannot enforce" (historical
# artifact that contradicted the v2.10.5+ mechanism and misled Opus 4.7's
# literal reading, per the v2.10.6 change notes).
MESSAGES="${MESSAGES}RULE 22 ORDERING — The Low/High Impact block must appear ABOVE the Edit/Write tool call in the same assistant turn, never below. As of v2.10.5, the PreToolUse hook structurally enforces this: if the [Rule 22] marker is absent from a text block between the previous Edit/Write and this one, the hook returns permissionDecision: deny and blocks the tool call. Retrying without the marker will deny again. Emit the block prospectively, not retroactively — the only valid path is marker-then-edit. Arguments for skipping ('conversation already covered it', 'docs-only edit', 'routine change', 'too trivial') are all invalid — see rules/change-decision-framework.md 'Ordering (required)' and 'Rationalizations that do not apply'. "

# Task budget awareness (v2.10.6; usage-snapshot pointer added with the
# status-line meter). The status-line meter (/statusline) persists a fresh
# context/5h/7d usage snapshot per account to ~/.claude/aria-statusline-state-<accountUuid>.json;
# when it exists Claude can read its own budget on demand. When it doesn't, Claude still
# lacks direct visibility (only the user's UI shows it) — surface strain and let
# the user decide rather than wrapping up autonomously (avoids self-defeating
# /extract during depletion — raw transcript persists via PreCompact anyway).
# Resolve the CURRENT session's snapshot path via the shared runtime-aware resolver
# (config.sh kt_resolve_account) so Claude reads its OWN account's usage under both
# the CLI and Claude-Desktop-hosted runtimes — not the wrong runtime's account.
_uk=$(kt_resolve_account | cut -f1)
[ -z "$_uk" ] && _uk="default"
USAGE_SNAP="~/.claude/aria-statusline-state-${_uk}.json"
# Emit only the branch that matches reality. The usage snapshot is account-keyed
# and sticky (persists across sessions), so the presence of ANY such file means
# the status-line meter is installed. Emitting both the exists/not-exists branches
# every session wasted ~600B on the inapplicable counterfactual and read as
# self-contradictory ("you can see usage" + "you can't") — gate on installed.
if ls "$HOME"/.claude/aria-statusline-state-*.json >/dev/null 2>&1; then
  MESSAGES="${MESSAGES}TASK BUDGET — Read ${USAGE_SNAP} (written by the aria-knowledge status-line meter) for your current context-window %, 5-hour, and 7-day plan-usage; consult it when judging whether to keep going, and before /handoff, /wrapup, or compacting. Re-read it fresh at decision time (do not rely on usage numbers mentioned earlier in this conversation). Treat the 5-hour/7-day figures as STALE if the current time is past five_hour_resets_at / seven_day_resets_at, and treat context_pct as unknown if the snapshot's session_id doesn't match this session or is null/absent (just after /compact — not the old high value). If a figure is stale or unknown and a decision depends on it, say so and check the live status line rather than asserting the stored number. (A UserPromptSubmit hook also warns when any metric crosses usage_alert_threshold, default 80%.) "
else
  MESSAGES="${MESSAGES}TASK BUDGET — You do not see usage directly (only the user's UI shows it). If strain symptoms appear (responses cutting short, deep session length, compaction warnings), surface them and offer options (finish the current atomic task, call /aria-knowledge:extract, trigger compaction, or continue). Don't assume depletion or wrap up autonomously. "
fi

# Knowledge surfacing — passive (suggest /context) vs active (Read matches directly)
# branches on KT_ACTIVE_SURFACING (default true as of v2.15.0).
INDEX_FILE="$KT_KNOWLEDGE_FOLDER/index.md"
if [ -f "$INDEX_FILE" ]; then
  if [ "$KT_ACTIVE_SURFACING" = "true" ]; then
    MESSAGES="${MESSAGES}ARIA ACTIVE CONTEXT — Knowledge index at ${KT_KNOWLEDGE_FOLDER}/index.md. After the user states their first task, do this autonomously (do NOT wait for /context): (1) Read index.md and parse the ## Tag Index section for ### tagname headers; (2) tokenize the user's task text (lowercase, alnum-only, dedupe); (3) find tags whose names exactly match any token; (4) if ≥2 tags match, collect file lines under those tag sections, dedupe by path, cap at top-5; (5) Read each matched file; (6) before answering, output 1-2 sentences naming which files loaded and why each is relevant. Offer once per session and again on clear topic change. The TaskCreated / Bash-cd / PostCompact hooks will auto-surface for those triggers — this instruction covers the SessionStart→first-user-message gap. Honors a session ledger at /tmp/aria-active-\${session_id} (paths already there, don't re-Read). "
  else
    MESSAGES="${MESSAGES}ARIA CONTEXT — Knowledge index available at ${KT_KNOWLEDGE_FOLDER}/index.md. After user states task, check it for relevant tags and suggest a /context with any found relevant tags. Offer once per session and again when changing topics. Do not block. "
  fi
fi

# Project context suggestion — only if both opt-ins are enabled AND CWD matches a configured project
if [ "$KT_PROJECTS_ENABLED" = "true" ] && [ "$KT_AUTO_LOAD_PROJECT_CONTEXT" = "true" ]; then
  CURRENT_PROJECT=$(kt_project_for_path "$PWD")
  if [ -n "$CURRENT_PROJECT" ]; then
    MESSAGES="${MESSAGES}ARIA Project Context — You're working in project '${CURRENT_PROJECT}'. Suggest the user run /context ${CURRENT_PROJECT} to load project-specific knowledge (decisions, patterns) plus cross-project items tagged ${CURRENT_PROJECT}. Offer once per session. Do not block. "
  fi
fi

# SessionStart project picker — opt-in, non-blocking (spec 2026-06-06).
# Gated: projects_enabled + session_start_project_picker. Emits nothing unless both true.
# Suggests a project menu (generated from projects_list) only when CWD is NOT already
# inside a configured project (that CWD case is auto_load_project_context's job above).
if [ "$KT_PROJECTS_ENABLED" = "true" ] && [ "$KT_SESSION_START_PROJECT_PICKER" = "true" ]; then
  if [ -z "$(kt_project_for_path "$PWD")" ]; then
    PICKER_MENU=$(kt_project_menu)
    if [ -n "$PICKER_MENU" ]; then
      # Option 3 (ADR-pending unify): inline pm_projects_root read; same key as ARIA Assist.
      PICKER_ROOT=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^pm_projects_root:' | sed 's/^pm_projects_root: *//')
      [ -z "$PICKER_ROOT" ] && PICKER_ROOT="$HOME/Projects"
      case "$PICKER_ROOT" in "~"/*) PICKER_ROOT="$HOME/${PICKER_ROOT#\~/}" ;; esac
      MESSAGES="${MESSAGES}ARIA Project Picker — If the user's opening message does NOT already name a project (or a task within one), suggest ONCE: 'Which project today? ${PICKER_MENU} — or name one / just start working.' When the user picks or names a project, resolve its tag to the matching projects_list path, then read ${PICKER_ROOT}/<that-path>/CLAUDE.md and ${PICKER_ROOT}/<that-path>/PROGRESS.md if present. Do NOT block — if the user already named a project or task, proceed without asking. Offer once per session. "
    fi
  fi
fi

# v2.16.1: tracked-artifacts active load — fires when active_knowledge_surfacing
# is enabled AND PWD substring-matches a configured project. Surfaces CODEMAP
# directory + (if multi-repo) STITCH with staleness annotation. Complementary
# to the existing multi-project CODEMAP staleness report below (line 258+);
# for sessions started inside a project, this gives an active-load instruction
# alongside that report. For sessions started at ~/Projects (no project match),
# this silently skips and the existing block continues unchanged.
if [ "$KT_ACTIVE_SURFACING" = "true" ] && [ "$KT_PROJECTS_ENABLED" = "true" ]; then
  # session_id needed for ledger path
  TA_SESSION_ID=$(echo "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//' 2>/dev/null)
  . "$SCRIPT_DIR/lib-tracked-artifacts.sh"
  kt_artifact_compute_for_path "$PWD"
  if [ -n "$TA_SESSION_ID" ] && [ "$KT_ARTIFACTS_COUNT" -gt 0 ]; then
    TA_LEDGER="/tmp/aria-active-${TA_SESSION_ID}"
    kt_artifact_filter_ledger "$TA_LEDGER"
    if [ "$KT_ARTIFACTS_COUNT" -gt 0 ]; then
      kt_artifact_record_ledger "$TA_LEDGER"
      MESSAGES="${MESSAGES}${KT_ARTIFACTS_INSTRUCTION}"
    fi
  fi
fi

# SESSION.md re-entry offer (v2.22.0; in-progress write moved to PostToolUse in
# v2.23.0) — flag-gated on session_state. SessionStart fires before the project is
# named, so this emits a reactive resume-offer directive Claude executes once the
# project resolves. The in-progress MARK is now written deterministically by the
# PostToolUse hook (post-edit-check.sh) on the first edit — not by Claude here —
# because the soft-instruction write proved unreliable (Claude skipped it).
if [ "$KT_SESSION_STATE" = "true" ]; then
  MESSAGES="${MESSAGES}SESSION STATE — After the project/sub-project for this session is identified (by the PWD-based project match, or by what the user names in their opening message), locate SESSION.md at that project root (project root = nearest dir with CLAUDE.md/PROGRESS.md). If it exists with a non-empty '## Next session prompt' block: if the user's opening message included the word 'handoff', open the session by executing that prompt directly (no confirmation); otherwise tell the user a saved resume prompt exists (state its lastEvent + age from the 'at' field) and ask whether to start from it (y/n). If no such prompt exists, stay quiet. The 'in-progress' mark is now written automatically by the PostToolUse hook (post-edit-check.sh) on your first edit — do NOT write SESSION.md yourself here. Offer the resume once per session. "
fi

# Per-task insight batch capture — gated by auto_capture
if [ "$KT_AUTO_CAPTURE" != "false" ]; then
  MESSAGES="${MESSAGES}INSIGHT CAPTURE — After completing discrete tasks, batch-append any uncaptured \xe2\x98\x85 Insight blocks to ${KT_KNOWLEDGE_FOLDER}/intake/insights-backlog.md. Do not capture mid-task — only at task completion boundaries. "
fi

# Memory pathway guardrail (v2.10.6). Recent Claude models have enhanced
# file-system memory; route that capability through ARIA's pathways so
# the knowledge tree stays curated rather than fragmenting into ad-hoc notes.
MESSAGES="${MESSAGES}MEMORY PATHWAY — ARIA is the structured memory pathway for this session. For notes, use /clip (URLs/snippets), /extract (session insights), /intake (bulk imports), /audit-knowledge (promotion). Recent Claude models have enhanced file-system memory; route it through ARIA to keep the knowledge tree curated. "

# CODEMAP detection — find codemaps in project directories, annotate with
# staleness per /audit-knowledge Step 5d criteria so stale maps are visible
# at session start without running a full audit. Graceful on missing git,
# missing Last-updated header, or non-git paths — falls back to mtime and
# zero-files-changed respectively; worst case shows "(no date)".
CODEMAPS=$(find "$PWD" -maxdepth 2 -name "CODEMAP.md" 2>/dev/null | head -5)
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

        # Classification matches /audit-knowledge Step 5d exactly
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
    MESSAGES="${MESSAGES}CODEMAP Found: ${CM_FULL}. Before exploring a project's codebase, read its CODEMAP Directory section first. "
  fi
fi

# Output only if there are messages
if [ -n "$MESSAGES" ]; then
  MESSAGES_ESCAPED=$(kt_json_escape "$MESSAGES")
  echo '{"systemMessage":"'"$MESSAGES_ESCAPED"'"}'
fi

# Diagnostic log — confirms hook ran, distinguishes success from silent failure
echo "$(date +%Y-%m-%dT%H:%M:%S) session-start-check: messages=${#MESSAGES}" >> "$KT_KNOWLEDGE_FOLDER/logs/hook-debug.log" 2>/dev/null
