#!/bin/sh
# session-start-check.sh — SessionStart hook for aria-knowledge
# Checks audit cadences and prompts when audits are due

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

# Clear stale batch manifest (>30 min old) left over from crashed sessions.
# Prevents stale manifests from silently suppressing Rule 22 on subsequent
# unrelated edits. Safe no-op if no manifest exists or jq is unavailable.
kt_batch_clear_stale 1800

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
# backlogs. Ideas-backlog is deliberately excluded — ideas route out, counting them
# would conflate staging with action.
KA_DUE=false
BACKLOG_COUNT=0
for _kt_bl in "$KT_KNOWLEDGE_FOLDER/intake/insights-backlog.md" \
              "$KT_KNOWLEDGE_FOLDER/intake/decisions-backlog.md" \
              "$KT_KNOWLEDGE_FOLDER/intake/extraction-backlog.md"; do
  if [ -f "$_kt_bl" ]; then
    # Count ^### entries below the first --- separator. Matches the counting
    # convention used by /stats and /backlog skills (entries live after the
    # frontmatter/intro separator). awk's `print c+0` always emits a single
    # numeric value (0 if no matches) and exits 0 — avoids the grep -c pitfall
    # where zero-match exit-1 combined with `|| echo 0` produced two-line output
    # and crashed arithmetic expansion.
    _kt_n=$(awk '/^---$/{sep++; next} sep>=1 && /^### /{c++} END{print c+0}' "$_kt_bl" 2>/dev/null)
    case "$_kt_n" in
      ''|*[!0-9]*) _kt_n=0 ;;
    esac
    BACKLOG_COUNT=$((BACKLOG_COUNT + _kt_n))
  fi
done

# Tier boundaries (derived from threshold via fixed +15/+30 offsets). Matches capacity
# regimes observed empirically: comfortable (<T), workable (T to T+14), cliff (T+15
# to T+29), must-split (T+30+). Default threshold 20 → 20/35/50.
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
# Trigger hint (count/threshold/days) is embedded so audit-log Step 1 can record it for tuning.
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

# Check update cadence — parse last /setup date from config file
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

# Rule 22 ordering — preventive reminder so the rule is in context before the first edit.
# The PreToolUse hook fires alongside the tool result and cannot block the edit, so ordering
# discipline is Claude-side. This line states the rule once, up front, so proactive output
# becomes the default rather than retroactive hook-driven correction.
MESSAGES="${MESSAGES}RULE 22 ORDERING — The Low/High Impact block must appear ABOVE the Edit/Write tool call in the same assistant turn, never below. The PreToolUse hook cannot enforce this; discipline is Claude-side. Arguments for skipping the block (\"conversation already covered it\", \"docs-only edit\", \"only way to satisfy hook is retroactively\") are all invalid — see rules/change-decision-framework.md sections \"Ordering (required)\" and \"Rationalizations that do not apply\". "

# Knowledge surfacing — prompt Claude to suggest /context after user states task
INDEX_FILE="$KT_KNOWLEDGE_FOLDER/index.md"
if [ -f "$INDEX_FILE" ]; then
  MESSAGES="${MESSAGES}ARIA CONTEXT — Knowledge index available at ${KT_KNOWLEDGE_FOLDER}/index.md. After user states task, check it for relevant tags and suggest a /context with any found relevant tags. Offer once per session and again when changing topics. Do not block. "
fi

# Project context suggestion — only if both opt-ins are enabled AND CWD matches a configured project
if [ "$KT_PROJECTS_ENABLED" = "true" ] && [ "$KT_AUTO_LOAD_PROJECT_CONTEXT" = "true" ]; then
  CURRENT_PROJECT=$(kt_project_for_path "$PWD")
  if [ -n "$CURRENT_PROJECT" ]; then
    MESSAGES="${MESSAGES}ARIA Project Context — You're working in project '${CURRENT_PROJECT}'. Suggest the user run /context ${CURRENT_PROJECT} to load project-specific knowledge (decisions, patterns) plus cross-project items tagged ${CURRENT_PROJECT}. Offer once per session. Do not block. "
  fi
fi

# Per-task insight batch capture — gated by auto_capture
if [ "$KT_AUTO_CAPTURE" != "false" ]; then
  MESSAGES="${MESSAGES}INSIGHT CAPTURE — After completing discrete tasks, batch-append any uncaptured ★ Insight blocks to ${KT_KNOWLEDGE_FOLDER}/intake/insights-backlog.md. Do not capture mid-task — only at task completion boundaries. "
fi

# CODEMAP detection — find codemaps in project directories
CODEMAPS=$(find "$PWD" -maxdepth 2 -name "CODEMAP.md" 2>/dev/null | head -5)
if [ -n "$CODEMAPS" ]; then
  CODEMAP_LIST=$(echo "$CODEMAPS" | sed "s|$PWD/||g" | tr '\n' ', ' | sed 's/, $//' | sed 's/,$//')
  MESSAGES="${MESSAGES}CODEMAP Found: ${CODEMAP_LIST}. Before exploring a project's codebase, read its CODEMAP Directory section first. "
fi

# Output only if there are messages
if [ -n "$MESSAGES" ]; then
  MESSAGES_ESCAPED=$(kt_json_escape "$MESSAGES")
  echo '{"systemMessage":"'"$MESSAGES_ESCAPED"'"}'
fi

# Diagnostic log — confirms hook ran, distinguishes success from silent failure
echo "$(date +%Y-%m-%dT%H:%M:%S) session-start-check: messages=${#MESSAGES}" >> "$KT_KNOWLEDGE_FOLDER/logs/hook-debug.log" 2>/dev/null
