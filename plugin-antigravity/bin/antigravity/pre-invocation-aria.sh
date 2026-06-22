#!/bin/bash
# pre-invocation-aria.sh — Antigravity PreInvocation wrapper.
#
# Fires before every model call. Three responsibilities:
#   1. Cache transcriptPath every turn — /snapshot reads it later.
#   2. On invocationNum == 0 (first call of conversation), inject
#      session-start ephemeralMessage with audit-cadence + knowledge-
#      surfacing prompts. Replaces Claude Code's SessionStart hook.
#   3. Drain pending scope-check log entries from post-edit-aria.sh
#      and inject as ephemeralMessage. Restores PostToolUse → agent
#      feedback channel that Antigravity's PostToolUse {} return
#      cannot deliver inline.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib-antigravity-input.sh
source "$LIB_DIR/lib-antigravity-input.sh"

# PreInvocation-specific field (lib doesn't extract this — extract inline).
INVOCATION_NUM=$(jq -r '.invocationNum // 0' <<<"$ARIA_HOOK_INPUT")

CACHE_DIR="$HOME/.gemini/antigravity"
CACHE_FILE="$CACHE_DIR/.last-transcript-path"
LOG_FILE="$CACHE_DIR/aria-knowledge-scope-check.log"

mkdir -p "$CACHE_DIR" 2>/dev/null || true

# --- Responsibility 1: cache transcriptPath + artifactDirectoryPath every turn ---
if [ -n "$ARIA_TRANSCRIPT_PATH" ]; then
  printf '%s' "$ARIA_TRANSCRIPT_PATH" > "$CACHE_FILE"
fi
if [ -n "$ARIA_ARTIFACT_DIR" ]; then
  printf '%s' "$ARIA_ARTIFACT_DIR" > "$CACHE_DIR/.last-artifact-dir"
fi

# Build up injectSteps array
INJECT_STEPS_JSON='[]'

# --- Responsibility 2: session-start ephemeralMessage on first call ---
if [ "$INVOCATION_NUM" = "0" ]; then
  # Source config to read user's config and export variables.
  if [ -f "$CLAUDE_PLUGIN_ROOT/bin/config.sh" ]; then
    # shellcheck source=../config.sh
    source "$CLAUDE_PLUGIN_ROOT/bin/config.sh"
  fi

  # 1. Clear stale batch manifests and ledgers (matches canonical session-start-check.sh)
  if command -v kt_batch_clear_stale >/dev/null 2>&1; then
    kt_batch_clear_stale 1800
  fi
  find /tmp -maxdepth 1 -name 'aria-active-*' -mtime +1 -delete 2>/dev/null || true
  find /tmp -maxdepth 1 -name 'aria-session-inprogress-*' -mtime +1 -delete 2>/dev/null || true

  # 2. Dynamic message building
  MESSAGES=""

  if [ "${KT_CONFIGURED:-false}" = "false" ]; then
    MESSAGES="aria-knowledge is installed but not configured. Run /setup to configure your knowledge folder and start capturing knowledge automatically. "
  elif [ -n "${KT_CONFIG_ERROR:-}" ]; then
    MESSAGES="aria-knowledge: ${KT_CONFIG_ERROR} Run /setup to reconfigure. "
  elif [ ! -d "${KT_KNOWLEDGE_FOLDER:-}" ]; then
    MESSAGES="aria-knowledge: configured knowledge folder does not exist at ${KT_KNOWLEDGE_FOLDER:-}. Run /setup to reconfigure. "
  else
    # Configured and folder exists — safe to evaluate audit cadence
    date_to_epoch() {
      date -j -f "%Y-%m-%d" "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null
    }

    TODAY=$(date +%Y-%m-%d)
    TODAY_EPOCH=$(date_to_epoch "$TODAY")

    if [ -n "$TODAY_EPOCH" ]; then
      KNOWLEDGE_LOG="$KT_KNOWLEDGE_FOLDER/logs/knowledge-audit-log.md"
      CONFIG_LOG="$KT_KNOWLEDGE_FOLDER/logs/config-audit-log.md"

      # Welcome first-run vs cadence checks
      IS_FIRST_RUN=false
      if [ -f "$KNOWLEDGE_LOG" ]; then
        if grep -q '(no audits yet)' "$KNOWLEDGE_LOG"; then
          IS_FIRST_RUN=true
        fi
      else
        IS_FIRST_RUN=true
      fi

      if [ "$IS_FIRST_RUN" = "true" ]; then
        MESSAGES="ARIA Knowledge Active: Auto insights collection, Rule 22 logic on edits, context surfacing, audit prompts, and precompact capture. Run /help for commands, see QUICKSTART.md for more. "
      else
        # Knowledge audit cadence
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

        KA_TIER_RECOMMENDED=$((KT_AUDIT_TRIGGER_THRESHOLD + 15))
        KA_TIER_OVERDUE=$((KT_AUDIT_TRIGGER_THRESHOLD + 30))

        KA_DUE=false
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

        KA_COUNT_MSG=""
        if [ "$BACKLOG_COUNT" -ge "$KA_TIER_OVERDUE" ]; then
          KA_COUNT_MSG="Knowledge audit overdue — ${BACKLOG_COUNT} entries, plan for multi-pass. "
        elif [ "$BACKLOG_COUNT" -ge "$KA_TIER_RECOMMENDED" ]; then
          KA_COUNT_MSG="Knowledge audit recommended — ${BACKLOG_COUNT} entries, near one-pass ceiling. "
        elif [ "$BACKLOG_COUNT" -ge "$KT_AUDIT_TRIGGER_THRESHOLD" ]; then
          KA_COUNT_MSG="Knowledge audit suggested — ${BACKLOG_COUNT} entries ready for review. "
        fi

        KA_DAYS_FIRED=false
        if [ -n "$DAYS_SINCE_KA" ] && [ "$DAYS_SINCE_KA" -ge "$KT_CADENCE_KNOWLEDGE" ]; then
          KA_DAYS_FIRED=true
        fi

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

        # Config audit cadence
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

        # Plugin version check
        INSTALLED_VERSION=""
        if [ -f "${CLAUDE_PLUGIN_ROOT}/version.txt" ]; then
          INSTALLED_VERSION=$(cat "${CLAUDE_PLUGIN_ROOT}/version.txt" | tr -d '[:space:]')
        fi

        VERSION_PROMPTED=false
        if [ -n "$INSTALLED_VERSION" ] && [ -n "${KT_LAST_SETUP_VERSION:-}" ] && [ "$INSTALLED_VERSION" != "$KT_LAST_SETUP_VERSION" ]; then
          MESSAGES="${MESSAGES}ARIA was updated (last /setup ran on v${KT_LAST_SETUP_VERSION}, plugin is now v${INSTALLED_VERSION}). Run /setup to apply template diffs and surface any new config keys? "
          VERSION_PROMPTED=true
        fi

        # Update check cadence
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
      fi
    fi

    # Add Rule 22 ordering
    MESSAGES="${MESSAGES}RULE 22 ORDERING — The Low/High Impact block must appear ABOVE the Edit/Write tool call in the same assistant turn, never below. As of v2.10.5, the PreToolUse hook structurally enforces this: if the [Rule 22] marker is absent from a text block between the previous Edit/Write and this one, the hook returns permissionDecision: deny and blocks the tool call. Retrying without the marker will deny again. Emit the block prospectively, not retroactively — the only valid path is marker-then-edit. Arguments for skipping ('conversation already covered it', 'docs-only edit', 'routine change', 'too trivial') are all invalid — see rules/change-decision-framework.md 'Ordering (required)' and 'Rationalizations that do not apply'. "

    # Task budget awareness (account-keyed resolve)
    _uk=$(kt_resolve_account | cut -f1)
    [ -z "$_uk" ] && _uk="default"
    USAGE_SNAP="~/.gemini/antigravity/aria-statusline-state-${_uk}.json"
    if ls "$HOME"/.gemini/antigravity/aria-statusline-state-*.json >/dev/null 2>&1; then
      MESSAGES="${MESSAGES}TASK BUDGET — Read ${USAGE_SNAP} (written by the aria-knowledge status-line meter) for your current context-window %, 5-hour, and 7-day plan-usage; consult it when judging whether to keep going, and before /handoff, /wrapup, or compacting. Re-read it fresh at decision time (do not rely on usage numbers mentioned earlier in this conversation). Treat the 5-hour/7-day figures as STALE if the current time is past five_hour_resets_at / seven_day_resets_at, and treat context_pct as unknown if the snapshot's session_id doesn't match this session or is null/absent (just after /compact — not the old high value). If a figure is stale or unknown and a decision depends on it, say so and check the live status line rather than asserting the stored number. (A UserPromptSubmit hook also warns when any metric crosses usage_alert_threshold, default 80%.) "
    else
      MESSAGES="${MESSAGES}TASK BUDGET — You do not see usage directly (only the user's UI shows it). If strain symptoms appear (responses cutting short, deep session length, compaction warnings), surface them and offer options (finish the current atomic task, call /aria-knowledge:extract, trigger compaction, or continue). Don't assume depletion or wrap up autonomously. "
    fi

    # Knowledge surfacing
    if [ -f "${KT_KNOWLEDGE_FOLDER:-}/index.md" ]; then
      if [ "${KT_ACTIVE_SURFACING:-}" = "true" ]; then
        MESSAGES="${MESSAGES}ARIA ACTIVE CONTEXT — Knowledge index at ${KT_KNOWLEDGE_FOLDER}/index.md. After the user states their first task, do this autonomously (do NOT wait for /context): (1) Read index.md and parse the ## Tag Index section for ### tagname headers; (2) tokenize the user's task text (lowercase, alnum-only, dedupe); (3) find tags whose names exactly match any token; (4) if ≥2 tags match, collect file lines under those tag sections, dedupe by path, cap at top-5; (5) Read each matched file; (6) before answering, output 1-2 sentences naming which files loaded and why each is relevant. Offer once per session and again on clear topic change. The TaskCreated / Bash-cd / PostCompact hooks will auto-surface for those triggers — this instruction covers the SessionStart→first-user-message gap. Honors a session ledger at /tmp/aria-active-\${session_id} (paths already there, don't re-Read). "
      else
        MESSAGES="${MESSAGES}ARIA CONTEXT — Knowledge index available at ${KT_KNOWLEDGE_FOLDER}/index.md. After user states task, check it for relevant tags and suggest a /context with any found relevant tags. Offer once per session and again when changing topics. Do not block. "
      fi
    fi

    # Project context suggestion
    if [ "${KT_PROJECTS_ENABLED:-}" = "true" ] && [ "${KT_AUTO_LOAD_PROJECT_CONTEXT:-}" = "true" ]; then
      CURRENT_PROJECT=$(kt_project_for_path "$PWD")
      if [ -n "$CURRENT_PROJECT" ]; then
        MESSAGES="${MESSAGES}ARIA Project Context — You're working in project '${CURRENT_PROJECT}'. Suggest the user run /context ${CURRENT_PROJECT} to load project-specific knowledge (decisions, patterns) plus cross-project items tagged ${CURRENT_PROJECT}. Offer once per session. Do not block. "
      fi
    fi

    # SessionStart project picker
    if [ "${KT_PROJECTS_ENABLED:-}" = "true" ] && [ "${KT_SESSION_START_PROJECT_PICKER:-}" = "true" ]; then
      if [ -z "$(kt_project_for_path "$PWD")" ]; then
        PICKER_MENU=$(kt_project_menu)
        if [ -n "$PICKER_MENU" ]; then
          PICKER_ROOT=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^pm_projects_root:' | sed 's/^pm_projects_root: *//')
          [ -z "$PICKER_ROOT" ] && PICKER_ROOT="$HOME/Projects"
          case "$PICKER_ROOT" in "~"/*) PICKER_ROOT="$HOME/${PICKER_ROOT#\~/}" ;; esac
          MESSAGES="${MESSAGES}ARIA Project Picker — If the user's opening message does NOT already name a project (or a task within one), suggest ONCE: 'Which project today? ${PICKER_MENU} — or name one / just start working.' When the user picks or names a project, resolve its tag to the matching projects_list path, then read ${PICKER_ROOT}/<that-path>/CLAUDE.md and ${PICKER_ROOT}/<that-path>/PROGRESS.md if present. Do NOT block — if the user already named a project or task, proceed without asking. Offer once per session. "
        fi
      fi
    fi

    # Tracked artifacts active load
    if [ "${KT_ACTIVE_SURFACING:-}" = "true" ] && [ "${KT_PROJECTS_ENABLED:-}" = "true" ]; then
      TA_SESSION_ID=$(echo "$ARIA_HOOK_INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"//' 2>/dev/null)
      if [ -f "$CLAUDE_PLUGIN_ROOT/bin/lib-tracked-artifacts.sh" ]; then
        # shellcheck source=../lib-tracked-artifacts.sh
        source "$CLAUDE_PLUGIN_ROOT/bin/lib-tracked-artifacts.sh"
        kt_artifact_compute_for_path "$PWD"
        if [ -n "$TA_SESSION_ID" ] && [ "${KT_ARTIFACTS_COUNT:-0}" -gt 0 ]; then
          TA_LEDGER="/tmp/aria-active-${TA_SESSION_ID}"
          kt_artifact_filter_ledger "$TA_LEDGER"
          if [ "$KT_ARTIFACTS_COUNT" -gt 0 ]; then
            kt_artifact_record_ledger "$TA_LEDGER"
            MESSAGES="${MESSAGES}${KT_ARTIFACTS_INSTRUCTION}"
          fi
        fi
      fi
    fi

    # Session state re-entry offer
    if [ "${KT_SESSION_STATE:-}" = "true" ]; then
      MESSAGES="${MESSAGES}SESSION STATE — After the project/sub-project for this session is identified (by the PWD-based project match, or by what the user names in their opening message), locate SESSION.md at that project root (project root = nearest dir with CLAUDE.md/PROGRESS.md). If it exists with a non-empty '## Next session prompt' block: if the user's opening message included the word 'handoff', open the session by executing that prompt directly (no confirmation); otherwise tell the user a saved resume prompt exists (state its lastEvent + age from the 'at' field) and ask whether to start from it (y/n). If the prompt's 'at' is older than session_stale_days (${KT_SESSION_STALE_DAYS:-7} days by current config), do NOT present it as live — instead state its age and ask: still relevant? [resume / archive / keep]. 'archive' = move that entry under a '## Archived sessions' heading (atlas ignores it, same as '## Prior sessions'); 'keep' = leave it as-is; 'resume' = execute it. Never auto-drop an aged entry — staleness prompts, it does not evict. If no such prompt exists, stay quiet. The 'in-progress' mark is now written automatically by the PostToolUse hook (post-edit-check.sh) on your first edit — do NOT write SESSION.md yourself here. Offer the resume once per session. "
    fi

    # Insight batch capture
    if [ "${KT_AUTO_CAPTURE:-}" != "false" ]; then
      MESSAGES="${MESSAGES}INSIGHT CAPTURE — After completing discrete tasks, batch-append any uncaptured ★ Insight blocks to ${KT_KNOWLEDGE_FOLDER}/intake/insights-backlog.md. Do not capture mid-task — only at task completion boundaries. "
    fi

    # Memory pathway
    MESSAGES="${MESSAGES}MEMORY PATHWAY — ARIA is the structured memory pathway for this session. For notes, use /intake (URLs/snippets, threads, docs, bulk imports), /extract (session insights), and /audit-knowledge (promotion). Route file-system memory through ARIA to keep the knowledge tree curated. "

    # CODEMAP detection
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
          CM_EPOCH=$(date_to_epoch "$CM_DATE")
          if [ -z "$CM_EPOCH" ]; then
            CM_ENTRY="$CM_REL (unparseable date: $CM_DATE)"
          else
            CM_DAYS=$(( (CM_TODAY_EPOCH - CM_EPOCH) / 86400 ))

            # Count files changed in git since last-updated
            CM_FILES=0
            if command -v git >/dev/null 2>&1; then
              CM_DIR=$(dirname "$cm")
              CM_FILES=$(cd "$CM_DIR" 2>/dev/null && git log --name-only --since="$CM_DATE" --pretty=format:"" 2>/dev/null \
                | grep -v '^$' | sort -u | wc -l | tr -d ' ')
              [ -z "$CM_FILES" ] && CM_FILES=0
            fi

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

    # Autonomy posture directive
    if [ "${KT_AUTONOMY:-}" = "balanced" ]; then
      MESSAGES="${MESSAGES}DECISION ROUTING (balanced) — Before asking OR auto-deciding, classify (per Rule 35): resolvable by read/grep/diff/git/config/web → investigate first, then act; objectively validatable → decide and show the validation; mechanical/already-decided → act; the user's intent/preference/judgment with no gainable visibility, or anything needing ungranted explicit approval → ask. Investigate the resolvable parts first; ask only the residual that's genuinely about the user. "
    elif [ "${KT_AUTONOMY:-}" = "autonomous" ]; then
      MESSAGES="${MESSAGES}DECISION ROUTING (autonomous) — The user's decision budget is the scarce resource; your speed/context is cheap. Exhaust self-resolvable investigation before spending a human turn. Per Rule 35: decide objectively-validatable forks YOURSELF (checked against ground truth and the build-philosophy bar, Rules 13/14/18 — simplest/robust/clean, no unneeded abstraction). Run quality gates (/prospect pre-code, /retrospect post-ship) as checks, not stops. Stop and ask ONLY when it is a judgment call with no gainable visibility (and none can be gained), or it requires explicit approval not already granted (push, destructive op, scope change, credentials). "
    fi
  fi

  if [ -n "$MESSAGES" ]; then
    INJECT_STEPS_JSON=$(jq -c --arg msg "$MESSAGES" '. + [{"ephemeralMessage": $msg}]' <<<"$INJECT_STEPS_JSON")
  fi
fi

# --- Responsibility 3: drain pending scope-check log entries ---
if [ -s "$LOG_FILE" ]; then
  # Atomic move-then-process to avoid race with concurrent post-edit-aria.sh writes.
  DRAIN_FILE="${LOG_FILE}.draining.$$"
  if mv "$LOG_FILE" "$DRAIN_FILE" 2>/dev/null; then
    SCOPE_CONTENT=$(cat "$DRAIN_FILE" 2>/dev/null || echo "")
    rm -f "$DRAIN_FILE" 2>/dev/null
    if [ -n "$SCOPE_CONTENT" ]; then
      SCOPE_MSG="[ARIA Rule 22 scope-check feedback from prior edits]
$SCOPE_CONTENT
(Review these scope assessments. If any flag FAIL, address before continuing.)"
      INJECT_STEPS_JSON=$(jq -c --arg msg "$SCOPE_MSG" '. + [{"ephemeralMessage": $msg}]' <<<"$INJECT_STEPS_JSON")
    fi
  fi
fi

# --- Emit response ---
STEP_COUNT=$(jq -r 'length' <<<"$INJECT_STEPS_JSON")
if [ "$STEP_COUNT" -gt 0 ]; then
  jq -cn --argjson steps "$INJECT_STEPS_JSON" '{injectSteps: $steps}'
else
  # No injection needed; return empty object (per docs/hooks PreInvocation output is optional).
  printf '{}\n'
fi
