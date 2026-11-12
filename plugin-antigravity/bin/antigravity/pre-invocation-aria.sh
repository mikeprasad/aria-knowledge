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
#   4. Rank the newest USER_INPUT from the transcript in code and inject
#      the result once per user turn (spec D4). Antigravity's PreInvocation
#      input carries no prompt, so the transcript is the only source; the
#      text reaches the matcher through jq and argv, never a shell string.

set -uo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The shared safe create (kt_create_new / kt_is_ours, spec §5) — one body in every library that
# writes a predictable name. lib-tracked-artifacts.sh has no top-level statement, so sourcing it
# only defines functions (tests/repros/safe-create-census.sh CC3); it is loaded here, before the
# first debug-log write below. If it is missing, every create and write here is refused.
# shellcheck source=../lib-tracked-artifacts.sh
. "$LIB_DIR/../lib-tracked-artifacts.sh" 2>/dev/null || true

# ag_debug_log STEP REASON — one `<UTC> antigravity <step> <reason>` line in the surfacing
# debug log, for the two failures that happen before lib-prompt-surface.sh (and its
# kt_ps_log) is loaded. The line is built first; an absent log is then created with
# kt_create_new, and the line is appended only to a regular file of ours that is not a link.
# Never stdout.
ag_debug_log() {
  local lf="${KT_SURFACE_CACHE_DIR:-${TMPDIR:-/tmp}}/aria-surface-hook.log" line
  line="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown-time) antigravity $1 $2"
  [ -e "$lf" ] || [ -L "$lf" ] || kt_create_new "$lf" 2>/dev/null || :
  kt_is_ours "$lf" 2>/dev/null || return 0
  printf '%s\n' "$line" >> "$lf" 2>/dev/null
  return 0
}

# C3: lib-antigravity-input.sh denies and exits when jq is missing, before
# responsibility 4 can say why. Record it in the surfacing debug log first.
# Output and exit status stay the lib's.
if ! command -v jq >/dev/null 2>&1; then
  ag_debug_log input jq-missing
fi

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
        KA_OFFLEVEL_NOTE=""
        # Shared counter (bin/count-backlog-entries.sh): all four backlogs, every live heading shape.
        # Any failure reads as 0, as the inline ^### loop this replaces did.
        _kt_cb=$(sh "$CLAUDE_PLUGIN_ROOT/bin/count-backlog-entries.sh" "$KT_KNOWLEDGE_FOLDER" 2>/dev/null | grep '^TOTAL:')
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
          KA_COUNT_MSG="Knowledge audit overdue — ${BACKLOG_COUNT} entries${KA_OFFLEVEL_NOTE}, plan for multi-pass. "
        elif [ "$BACKLOG_COUNT" -ge "$KA_TIER_RECOMMENDED" ]; then
          KA_COUNT_MSG="Knowledge audit recommended — ${BACKLOG_COUNT} entries${KA_OFFLEVEL_NOTE}, near one-pass ceiling. "
        elif [ "$BACKLOG_COUNT" -ge "$KT_AUDIT_TRIGGER_THRESHOLD" ]; then
          KA_COUNT_MSG="Knowledge audit suggested — ${BACKLOG_COUNT} entries${KA_OFFLEVEL_NOTE} ready for review. "
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
        # This port's ARIA ACTIVE CONTEXT directive. The ranking paragraph between the surfacing-ranking
        # markers is plugin-claude-code/scripts/surfacing-ranking.txt byte for byte; the clauses around it
        # are this port's: this hook's own responsibility 4 ranks the newest user turn in code and injects
        # `ARIA ACTIVE —`, so that injection is the only source and no instruction asks the model to run
        # anything on the task text. The model skips files it already read (this runtime never sets the
        # CLAUDE_CODE_SESSION_ID the Claude Code directive keys its ledger on). It sits in a QUOTED heredoc because it carries
        # backticks and apostrophes: inside a double-quoted string a backtick is command substitution and
        # deletes text silently. Do NOT escape it or move it into a double-quoted string —
        # tests/repros/surfacing-ranking-verbatim.sh runs this emitter and compares the text byte for byte.
        # read, not $(cat <<...): bash 3.2 (macOS /bin/sh) mis-parses an apostrophe in a heredoc that
        # sits inside a command substitution.
        IFS= read -r _aa_text <<'ARIA_ACTIVE_CONTEXT'
ARIA ACTIVE CONTEXT — Unasked, read each task's knowledge files before answering; say in one line which you used and why. Source: an `ARIA ACTIVE —` injection from the Antigravity PreInvocation hook, the only source (none = read nothing); the plugin ranks its files this way: <!-- surfacing-ranking:start -->Rank the candidate files: (1) a file carrying a matched project tag first; (2) then files carrying more of the matched tags; (3) then files whose path or index description contains more of the task's own words (lowercase, length over 2, common words dropped); (4) then authored files before files under `logs/`; (5) then the file whose rarest matched tag has the fewest files; (6) then index order. Fire when 2 or more tags match, or when 1 matched tag is a configured project. Keep the top 5.<!-- surfacing-ranking:end --> Skip files already read this session.
ARIA_ACTIVE_CONTEXT
        MESSAGES="${MESSAGES}${_aa_text} "
        # ARIA SURFACE value line, as plugin-claude-code/scripts/session-start-check.sh sends it: the
        # absolute, quoted CLI path and nothing else. Skills pass it references (--file, --git-range),
        # never task text. Double-quoted shell: keep backticks and dollar signs out of it.
        if [ -f "${CLAUDE_PLUGIN_ROOT}/bin/aria-surface.sh" ]; then
          MESSAGES="${MESSAGES}ARIA SURFACE — \"${CLAUDE_PLUGIN_ROOT}/bin/aria-surface.sh\" "
        fi
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
      MESSAGES="${MESSAGES}INSIGHT CAPTURE — After completing discrete tasks, batch-append any uncaptured ★ Insight blocks to ${KT_KNOWLEDGE_FOLDER}/intake/insights-backlog.md, each as one '### YYYY-MM-DD — <project> — <title>' heading with its body under it — never under a '## ' group header and never at '####', the level that means already processed. Do not capture mid-task — only at task completion boundaries. "
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

    # Autonomy posture directive (decision-routing, Rule 35)
    if [ "${KT_AUTONOMY:-}" = "balanced" ]; then
      MESSAGES="${MESSAGES}DECISION ROUTING (balanced) — Before asking OR auto-deciding, classify (per Rule 35): resolvable by read/grep/diff/git/config/web → investigate first, then act; objectively validatable → decide and show the validation; mechanical/already-decided → act; the user's intent/preference/judgment with no gainable visibility, or anything needing ungranted explicit approval → ask. Investigate the resolvable parts first; ask only the residual that's genuinely about the user. Either way, the option set is Rule 22 Step 4/5 output: enumerate the real alternatives, filter out any option with a provable defect (name it in one line rather than offering it), and when you decide, show what you rejected plus the validation. Asking is not an escape hatch from the analysis. "
    elif [ "${KT_AUTONOMY:-}" = "autonomous" ]; then
      MESSAGES="${MESSAGES}DECISION ROUTING (autonomous) — The user's decision budget is the scarce resource; your speed/context is cheap. Exhaust self-resolvable investigation before spending a human turn. Per Rule 35: decide objectively-validatable forks YOURSELF (checked against ground truth and the build-philosophy bar, Rules 13/14/18 — simplest/robust/clean, no unneeded abstraction). Run quality gates (/prospect pre-code, /retrospect post-ship) as checks, not stops. Stop and ask ONLY when it is a judgment call with no gainable visibility (and none can be gained), or it requires explicit approval not already granted (push, destructive op, scope change, credentials), or the foundational fix would change what the arc IS (its scope boundary, deliverable, or completion criteria) rather than merely make it bigger. Foundational-over-patch is NOT a fork at this setting: take the foundational fix and absorb the larger scope. Either way, the option set is Rule 22 Step 4/5 output: enumerate the real alternatives, filter out any option with a provable defect (name it in one line rather than offering it), and when you decide, show what you rejected plus the validation. Asking is not an escape hatch from the analysis. "
    fi

    # Standing user rules (U-namespace) — ALWAYS in force, never opt-in.
    UR_FILE="${KT_KNOWLEDGE_FOLDER:-}/rules/user-rules.md"
    if [ -f "$UR_FILE" ]; then
      UR_N=$(grep -c '^### U' "$UR_FILE" 2>/dev/null)
      if [ "${UR_N:-0}" -gt 0 ]; then
        UR_HEADERS=$(grep '^### U' "$UR_FILE" 2>/dev/null | sed 's/^### //' | awk '{printf "%s%s", sep, $0; sep="; "}')
        if [ ${#UR_HEADERS} -gt 3000 ]; then
          MESSAGES="${MESSAGES}STANDING USER RULES — ${UR_N} of the user's own rules are in force, at ${UR_FILE} (too many to index inline). Read that file before acting on anything it plausibly covers. "
        else
          MESSAGES="${MESSAGES}STANDING USER RULES (${UR_N}, always in force — the user's own rules, binding alongside working-rules.md): ${UR_HEADERS}. These titles are the index; read ${UR_FILE} for the full text of any rule bearing on the task. "
        fi
      fi
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

# --- Responsibility 4: rank the newest user input in code (spec D4) ---
# The ranking, ledger filter and "ARIA ACTIVE —" text are the shared capture core,
# bin/lib-prompt-surface.sh (byte-identical with the Claude Code and Cursor copies;
# build.sh copies it here). This block is only the Antigravity I/O adapter:
#   - text:  the newest USER_INPUT record in the LAST 400 lines of transcriptPath
#            (measured schema: type, content, source, status, step_index, created_at;
#            a user turn is type "USER_INPUT" with string content). Read by jq one line
#            at a time; a malformed line is skipped. The content is untrusted text: it
#            reaches the matcher only as a jq output and an argv item.
#   - once:  per conversation, per step_index — state file
#            ${KT_SURFACE_CACHE_DIR:-${TMPDIR:-/tmp}}/aria-ag-surfaced-<sanitised conversationId>,
#            one PROCESSED step_index per line: recorded on every decided outcome
#            (delivered, nothing-new, nofire), so a user turn is ranked at most once. An
#            error records nothing, so it is retried. A symlinked or foreign state file
#            is refused (and nothing is injected, since it could not be recorded).
#            The file is append-only: a lost race between writers only re-ranks a turn.
#   - ledger: /tmp/aria-active-<sanitised conversationId>, the same ledger as the
#            other hosts. It records delivered paths only, and only after the hook
#            output carrying the step was written (the lib's ledger contract); the
#            delivered step is marked processed at the same point. A failure before
#            delivery records nothing, so the next model call retries.
#   - timing: if Antigravity logs the user turn only after this hook fires, the
#            injection lands one model call later (still once).
# Failures go to the debug log (spec C3) as `<UTC> antigravity <step> <reason>`, never to
# model context. A missing or unreadable transcript is logged once per conversation and
# reason (marker aria-ag-logged-<id>.<reason>), since it persists across every model
# call. The model name is logged there when it changes (spec C2). Disabled or
# unconfigured surfacing does nothing and logs nothing. Responsibilities 1-3 never see
# any of this: it only appends one step to INJECT_STEPS_JSON.
AG_SURFACE_STEP=""
ag_surface() {
  local dir="${KT_SURFACE_CACHE_DIR:-${TMPDIR:-/tmp}}"
  if [ ! -f "$CLAUDE_PLUGIN_ROOT/bin/lib-prompt-surface.sh" ]; then
    ag_debug_log surface lib-missing
    return 0
  fi
  KT_PS_SCRIPT_DIR="$CLAUDE_PLUGIN_ROOT/bin"
  KT_PS_RUNTIME=antigravity
  # Same expression as config.sh's first assignment, so the lib's config cache keys on
  # the file without sourcing config.sh (~150 ms) on every model call.
  KT_CONFIG="${KT_CONFIG:-$HOME/.gemini/antigravity/aria-knowledge.local.md}"
  # shellcheck source=../lib-prompt-surface.sh
  . "$CLAUDE_PLUGIN_ROOT/bin/lib-prompt-surface.sh"

  # Housekeeping, once per conversation: state files, log-once markers and model-file /
  # create temps older than 24 h, ours only. `.aria-new.*` is kt_create_new's temp (here and in
  # /tmp, where the session ledger lives); `.aria-ag-new.*` is the pre-2.58.0 name, kept so a
  # leftover from an older release is still removed. `/tmp/`, not `/tmp`: on macOS /tmp is a
  # symlink and find does not follow a symlinked start point.
  if [ "$INVOCATION_NUM" = "0" ]; then
    find "$dir" -maxdepth 1 \( -name 'aria-ag-surfaced-*' -o -name 'aria-ag-logged-*' \
      -o -name '.aria-ag-model.*' -o -name '.aria-new.*' -o -name '.aria-ag-new.*' \) \
      -user "${USER:-$(id -u)}" -mmin +1440 -exec rm -f {} + 2>/dev/null
    find /tmp/ -maxdepth 1 -name '.aria-new.*' \
      -user "${USER:-$(id -u)}" -mmin +1440 -exec rm -f {} + 2>/dev/null
  fi

  # C2: the model name, logged when it differs from the last one logged. The last value is
  # read only from a regular file of ours that is not a link; the new one is written to a
  # temp file in the same directory and renamed over the name — rename replaces a planted
  # link, it never writes through one (as the lib's config cache does).
  local model last="" mf="$dir/aria-ag-model.last"
  model=$(jq -r '(.modelName // "") | tostring | gsub("[^A-Za-z0-9._+:/-]"; "") | .[0:60]' \
    <<<"$ARIA_HOOK_INPUT" 2>/dev/null) || model=""
  if [ -n "$model" ]; then
    if [ -f "$mf" ] && [ -O "$mf" ] && [ ! -L "$mf" ]; then
      IFS= read -r last < "$mf" 2>/dev/null || :
    fi
    if [ "$model" != "$last" ]; then
      kt_ps_log antigravity capture "modelName=$model"
      local mt
      if mt=$(mktemp "$dir/.aria-ag-model.XXXXXX" 2>/dev/null); then
        { printf '%s\n' "$model" > "$mt" && mv -f "$mt" "$mf"; } 2>/dev/null || rm -f "$mt" 2>/dev/null
      fi
    fi
  fi

  kt_ps_load_config
  if [ -z "$KT_CONFIG_ERROR" ] \
     && { [ "$KT_CONFIGURED" != "true" ] || [ "$KT_ACTIVE_SURFACING" != "true" ]; }; then
    return 0
  fi

  local sid
  sid=$(kt_ps_sanitize_id "$ARIA_CONVERSATION_ID")
  [ -n "$sid" ] || { kt_ps_log antigravity input no-conversation-id; return 0; }
  # m1: an invalid config persists across every model call — logged once per
  # conversation, and nothing is ranked.
  if [ -n "$KT_CONFIG_ERROR" ]; then ag_log_once "$dir" "$sid" surface config; return 0; fi
  local tp="$ARIA_TRANSCRIPT_PATH"
  [ -n "$tp" ] || { ag_log_once "$dir" "$sid" transcript no-transcript-path; return 0; }
  if [ ! -f "$tp" ] || [ ! -r "$tp" ]; then
    ag_log_once "$dir" "$sid" transcript unreadable; return 0
  fi

  # One jq call over the last 400 lines (gate-2 G3). Line 1 is a status; on "ok", line 2
  # is the step_index reduced to a filename-safe charset and the rest is the content plus
  # a closing "." ($( ) strips trailing newlines, which would change the text).
  local parsed status
  parsed=$(tail -n 400 -- "$tp" 2>/dev/null | jq -Rnr '
    [inputs] as $lines
    | [$lines[] | fromjson? | select(type == "object")] as $r
    | ([$r[] | select((.type | type) == "string")] | length) as $typed
    | ([$r[] | select(.type == "USER_INPUT" and ((.content | type) == "string"))] | last) as $u
    | if ($lines | length) == 0 then "empty"
      elif $typed == 0 then "schema-miss"
      elif $u == null then "none"
      else (($u.step_index // "") | tostring | gsub("[^A-Za-z0-9._-]"; "")) as $s
        | if $s == "" then "no-step-index" else "ok", $s, ($u.content + ".") end
      end
  ' 2>/dev/null) || { kt_ps_log antigravity transcript jq-failed; return 0; }
  local nl='
'
  status=${parsed%%"$nl"*}
  case $status in
    ok) ;;
    empty|none) return 0 ;;
    schema-miss|no-step-index) kt_ps_log antigravity transcript "$status"; return 0 ;;
    *) kt_ps_log antigravity transcript unexpected-parse; return 0 ;;
  esac
  local rest step content
  rest=${parsed#*"$nl"}
  step=${rest%%"$nl"*}
  content=""
  case $rest in *"$nl"*) content=${rest#*"$nl"} ;; esac
  content=${content%.}

  local state="$dir/aria-ag-surfaced-$sid"
  if [ -L "$state" ] || { [ -e "$state" ] && { [ ! -f "$state" ] || [ ! -O "$state" ]; }; }; then
    kt_ps_log antigravity state refused; return 0
  fi
  if [ -f "$state" ]; then
    local seen
    while IFS= read -r seen || [ -n "$seen" ]; do
      [ "$seen" = "$step" ] && return 0
    done < "$state"
  fi

  # The user's own words: pasted blocks removed (the strip runs only when there is one).
  # The state file marks a step PROCESSED on every decided outcome — delivered (after the
  # output is written, in ag_surface_commit), nothing-new and nofire — so a user turn is
  # ranked at most once. The session LEDGER records delivered paths only. An error records
  # nothing, so a transient failure is retried on the next model call.
  local text
  case $content in
    *'<pasted_content'*) text=$(printf '%s' "$content" | kt_ps_strip_pasted) ;;
    *) text=$content ;;
  esac
  [ -n "$text" ] || { ag_record_step "$state" "$step"; return 0; }   # nofire: nothing typed
  AG_SURFACE_LEDGER="/tmp/aria-active-$sid"
  kt_ps_surface "$text" "$AG_SURFACE_LEDGER" >/dev/null
  if [ -z "$KT_PS_TEXT" ]; then
    case $KT_PS_STATUS in
      nofire|nothing-new) ag_record_step "$state" "$step" ;;
    esac
    return 0
  fi
  # The whole hook output, built in one jq call: steps 1-3 unchanged, this one appended.
  AG_OUT=$(jq -cn --argjson s "$INJECT_STEPS_JSON" --arg m "$KT_PS_TEXT" \
    '{injectSteps: ($s + [{"ephemeralMessage": $m}])}' 2>/dev/null)
  [ -n "$AG_OUT" ] || { kt_ps_log antigravity emit jq-failed; return 0; }
  AG_SURFACE_STEP=$step
  AG_SURFACE_STATE=$state
}

# ag_record_step STATE STEP — append STEP as processed. An absent state file is created
# with kt_create_new (fails harmlessly when anything exists there). The line is then appended
# only to a regular file of ours that is not a link; anything else is logged and the step is
# not recorded (fail safe: the turn may be ranked again). Append, never rewrite, so concurrent
# writers lose no lines.
ag_record_step() {
  [ -e "$1" ] || [ -L "$1" ] || kt_create_new "$1" || :
  if ! kt_is_ours "$1"; then kt_ps_log antigravity state refused; return 0; fi
  printf '%s\n' "$2" >> "$1" 2>/dev/null || kt_ps_log antigravity state write-failed
}

# ag_log_once DIR SID STEP REASON — a failure that persists for the whole conversation
# (missing transcript, invalid config) would otherwise be logged before every model call,
# so it is logged once per (conversation, reason): marker DIR/aria-ag-logged-<SID>.<REASON>.
# Only a regular marker file of ours that is not a link counts as "already logged"; any
# other file at that name (a link, a directory, someone else's file) logs the line again
# and nothing is written. The marker is created with kt_create_new.
ag_log_once() {
  local m="$1/aria-ag-logged-$2.$4"
  if kt_is_ours "$m"; then return 0; fi
  kt_ps_log antigravity "$3" "$4"
  [ -e "$m" ] || [ -L "$m" ] || kt_create_new "$m" || :
  return 0
}

# After the output was written: record what was delivered, then the step as processed.
ag_surface_commit() {
  kt_ps_commit "$AG_SURFACE_LEDGER"
  ag_record_step "$AG_SURFACE_STATE" "$AG_SURFACE_STEP"
}

# The shared core is POSIX sh written for unset-tolerant shells; run it without -u.
set +u
ag_surface
set -u

# --- Emit response ---
if [ -n "$AG_SURFACE_STEP" ]; then
  # Responsibility 4 added a step: write, and only then record it. Written from a
  # subshell — a failed write in this shell stays in its stdout buffer and is flushed into
  # the next file opened on fd 1 (measured in the Cursor hook).
  if ( printf '%s\n' "$AG_OUT" ) 2>/dev/null; then
    set +u; ag_surface_commit; set -u
  else
    set +u; kt_ps_log antigravity emit write-failed; set -u
  fi
  exit 0
fi
STEP_COUNT=$(jq -r 'length' <<<"$INJECT_STEPS_JSON")
if [ "$STEP_COUNT" -gt 0 ]; then
  jq -cn --argjson steps "$INJECT_STEPS_JSON" '{injectSteps: $steps}'
else
  # No injection needed; return empty object (per docs/hooks PreInvocation output is optional).
  printf '{}\n'
fi
