#!/bin/sh
# config.sh — shared config reader for aria-knowledge hooks
# Sourced by session-start-check.sh and other hook scripts

KT_CONFIG="${KT_CONFIG:-$HOME/.claude/aria-knowledge.local.md}"
KT_CONFIGURED=false
KT_CONFIG_ERROR=""

# Escape a string for safe embedding in JSON values.
# Handles backslashes, double quotes, tabs, and strips newlines.
kt_json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' | tr '\n' ' '
}

if [ -f "$KT_CONFIG" ]; then
  KT_CONFIGURED=true

  # Parse YAML frontmatter between --- markers
  KT_KNOWLEDGE_FOLDER=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^knowledge_folder:' | sed 's/^knowledge_folder: *//')
  KT_CADENCE_KNOWLEDGE=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^audit_cadence_knowledge:' | sed 's/^audit_cadence_knowledge: *//')
  KT_CADENCE_CONFIG=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^audit_cadence_config:' | sed 's/^audit_cadence_config: *//')
  KT_EXPLANATORY=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^explanatory_plugin:' | sed 's/^explanatory_plugin: *//')
  KT_FREEFORM_THRESHOLD=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^freeform_promotion_threshold:' | sed 's/^freeform_promotion_threshold: *//')
  KT_STALENESS_MONTHS=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^staleness_threshold_months:' | sed 's/^staleness_threshold_months: *//')
  KT_CADENCE_UPDATE=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^audit_cadence_update:' | sed 's/^audit_cadence_update: *//')
  KT_AUTO_CAPTURE=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^auto_capture:' | sed 's/^auto_capture: *//')
  KT_ACTIVE_SURFACING=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^active_knowledge_surfacing:' | sed 's/^active_knowledge_surfacing: *//')
  KT_CRITICAL_PATHS=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^critical_paths:' | sed 's/^critical_paths: *//')
  KT_PROJECTS_ENABLED=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^projects_enabled:' | sed 's/^projects_enabled: *//')
  KT_PROJECTS_LIST=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^projects_list:' | sed 's/^projects_list: *//')
  KT_PROJECTS_REMOTES=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^projects_remotes:' | sed 's/^projects_remotes: *//')
  KT_PROJECTS_PROMOTION_THRESHOLD=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^projects_promotion_threshold:' | sed 's/^projects_promotion_threshold: *//')
  KT_AUTO_LOAD_PROJECT_CONTEXT=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^auto_load_project_context:' | sed 's/^auto_load_project_context: *//')
  KT_IDEAS_STALENESS_DAYS=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^ideas_staleness_threshold_days:' | sed 's/^ideas_staleness_threshold_days: *//')
  KT_AUDIT_TRIGGER_THRESHOLD=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^audit_trigger_threshold:' | sed 's/^audit_trigger_threshold: *//')
  KT_CODEMAP_STALENESS_DAYS=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^codemap_staleness_threshold_days:' | sed 's/^codemap_staleness_threshold_days: *//')
  KT_STITCH_STALENESS_DAYS=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^stitch_staleness_threshold_days:' | sed 's/^stitch_staleness_threshold_days: *//')
  KT_LAST_SETUP_VERSION=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^last_setup_version:' | sed 's/^last_setup_version: *//')

  # Defaults if not set
  KT_CADENCE_KNOWLEDGE=${KT_CADENCE_KNOWLEDGE:-7}
  KT_CADENCE_CONFIG=${KT_CADENCE_CONFIG:-14}
  KT_EXPLANATORY=${KT_EXPLANATORY:-false}
  KT_FREEFORM_THRESHOLD=${KT_FREEFORM_THRESHOLD:-3}
  KT_STALENESS_MONTHS=${KT_STALENESS_MONTHS:-6}
  KT_CADENCE_UPDATE=${KT_CADENCE_UPDATE:-30}
  KT_AUTO_CAPTURE=${KT_AUTO_CAPTURE:-true}
  KT_ACTIVE_SURFACING=${KT_ACTIVE_SURFACING:-true}
  KT_PROJECTS_ENABLED=${KT_PROJECTS_ENABLED:-false}
  KT_PROJECTS_PROMOTION_THRESHOLD=${KT_PROJECTS_PROMOTION_THRESHOLD:-2}
  KT_AUTO_LOAD_PROJECT_CONTEXT=${KT_AUTO_LOAD_PROJECT_CONTEXT:-false}
  KT_IDEAS_STALENESS_DAYS=${KT_IDEAS_STALENESS_DAYS:-21}
  KT_AUDIT_TRIGGER_THRESHOLD=${KT_AUDIT_TRIGGER_THRESHOLD:-20}
  KT_CODEMAP_STALENESS_DAYS=${KT_CODEMAP_STALENESS_DAYS:-14}
  KT_STITCH_STALENESS_DAYS=${KT_STITCH_STALENESS_DAYS:-30}
  # KT_CRITICAL_PATHS intentionally has no default — empty means no critical paths
  # KT_PROJECTS_LIST and KT_PROJECTS_REMOTES intentionally have no defaults — empty means "no projects configured"

  # Validate knowledge_folder is non-empty
  if [ -z "$KT_KNOWLEDGE_FOLDER" ]; then
    KT_CONFIGURED=false
    KT_CONFIG_ERROR="knowledge_folder could not be parsed from config file. Check for missing --- markers, Windows line endings, or malformed YAML."
  # Validate knowledge_folder is an absolute path
  elif case "$KT_KNOWLEDGE_FOLDER" in /*) false ;; *) true ;; esac; then
    KT_CONFIGURED=false
    KT_CONFIG_ERROR="knowledge_folder must be an absolute path (got: $KT_KNOWLEDGE_FOLDER)."
  # Validate knowledge_folder has no path traversal
  elif case "$KT_KNOWLEDGE_FOLDER" in *..*) true ;; *) false ;; esac; then
    KT_CONFIGURED=false
    KT_CONFIG_ERROR="knowledge_folder must not contain '..' (got: $KT_KNOWLEDGE_FOLDER)."
  fi

  # Validate cadence values are numeric, reset to defaults if not
  case "$KT_CADENCE_KNOWLEDGE" in
    ''|*[!0-9]*) KT_CADENCE_KNOWLEDGE=7 ;;
  esac
  case "$KT_CADENCE_CONFIG" in
    ''|*[!0-9]*) KT_CADENCE_CONFIG=14 ;;
  esac
  case "$KT_FREEFORM_THRESHOLD" in
    ''|*[!0-9]*) KT_FREEFORM_THRESHOLD=3 ;;
  esac
  case "$KT_STALENESS_MONTHS" in
    ''|*[!0-9]*) KT_STALENESS_MONTHS=6 ;;
  esac
  case "$KT_CADENCE_UPDATE" in
    ''|*[!0-9]*) KT_CADENCE_UPDATE=30 ;;
  esac
  case "$KT_AUTO_CAPTURE" in
    true|false) ;; # valid
    *) KT_AUTO_CAPTURE=true ;;
  esac
  case "$KT_ACTIVE_SURFACING" in
    true|false) ;; # valid
    *) KT_ACTIVE_SURFACING=true ;;
  esac
  case "$KT_PROJECTS_ENABLED" in
    true|false) ;; # valid
    *) KT_PROJECTS_ENABLED=false ;;
  esac
  case "$KT_PROJECTS_PROMOTION_THRESHOLD" in
    ''|*[!0-9]*) KT_PROJECTS_PROMOTION_THRESHOLD=2 ;;
  esac
  case "$KT_AUTO_LOAD_PROJECT_CONTEXT" in
    true|false) ;; # valid
    *) KT_AUTO_LOAD_PROJECT_CONTEXT=false ;;
  esac
  case "$KT_IDEAS_STALENESS_DAYS" in
    ''|*[!0-9]*) KT_IDEAS_STALENESS_DAYS=21 ;;
  esac
  case "$KT_AUDIT_TRIGGER_THRESHOLD" in
    ''|*[!0-9]*) KT_AUDIT_TRIGGER_THRESHOLD=20 ;;
  esac
  case "$KT_CODEMAP_STALENESS_DAYS" in
    ''|*[!0-9]*) KT_CODEMAP_STALENESS_DAYS=14 ;;
  esac
  case "$KT_STITCH_STALENESS_DAYS" in
    ''|*[!0-9]*) KT_STITCH_STALENESS_DAYS=30 ;;
  esac
fi

# kt_project_for_path PATH
# Returns the project tag for a given path, or empty if not in any configured project.
# Uses CWD-based substring matching first (longest-matching configured path wins —
# disambiguates nested sub-projects like aria + aria/aria-core); falls back to
# git-remote-based matching if KT_PROJECTS_REMOTES is set and git is available.
# Early-returns silently if projects feature is disabled or unconfigured.
kt_project_for_path() {
  _kt_path="$1"
  [ -z "$_kt_path" ] && return
  [ "$KT_PROJECTS_ENABLED" = "true" ] || return
  [ -z "$KT_PROJECTS_LIST" ] && return

  # CWD-based: longest-matching configured path wins. Walking all entries and
  # tracking the longest hit (instead of returning on first hit) ensures nested
  # sub-projects (e.g., aria-core at aria/aria-core nested under aria) get their
  # own tag rather than being shadowed by an earlier parent-tag entry.
  _kt_best_tag=""
  _kt_best_len=0
  _kt_old_ifs="$IFS"
  IFS=','
  for _kt_entry in $KT_PROJECTS_LIST; do
    [ -z "$_kt_entry" ] && continue
    # Skip malformed entries missing colon separator
    case "$_kt_entry" in *:*) ;; *) continue ;; esac
    _kt_tag="${_kt_entry%%:*}"
    _kt_proj_path="${_kt_entry#*:}"
    [ -z "$_kt_proj_path" ] && continue
    case "$_kt_path" in
      *"$_kt_proj_path"*)
        _kt_len=${#_kt_proj_path}
        if [ "$_kt_len" -gt "$_kt_best_len" ]; then
          _kt_best_tag="$_kt_tag"
          _kt_best_len="$_kt_len"
        fi
        ;;
    esac
  done
  IFS="$_kt_old_ifs"
  if [ -n "$_kt_best_tag" ]; then
    printf '%s' "$_kt_best_tag"
    return
  fi

  # Git-remote fallback: only if projects_remotes is configured AND git is available
  [ -z "$KT_PROJECTS_REMOTES" ] && return
  command -v git >/dev/null 2>&1 || return

  _kt_remote=$(cd "$_kt_path" 2>/dev/null && git config --get remote.origin.url 2>/dev/null)
  [ -z "$_kt_remote" ] && return

  _kt_old_ifs="$IFS"
  IFS=','
  for _kt_entry in $KT_PROJECTS_REMOTES; do
    [ -z "$_kt_entry" ] && continue
    # Skip malformed entries missing colon separator
    case "$_kt_entry" in *:*) ;; *) continue ;; esac
    _kt_tag="${_kt_entry%%:*}"
    _kt_remote_pattern="${_kt_entry#*:}"
    [ -z "$_kt_remote_pattern" ] && continue
    case "$_kt_remote" in
      *"$_kt_remote_pattern"*) printf '%s' "$_kt_tag"; IFS="$_kt_old_ifs"; return ;;
    esac
  done
  IFS="$_kt_old_ifs"
}

# kt_detect_signals FILE_PATH
# Detect structural signals from an edit's file path. Echoes comma-separated
# advisory labels to stdout. Empty string if no signals match. Used by
# pre-edit-check.sh to surface structural risk hints before the Rule 22
# HIGH/LOW classification — advisory only, never a classification override.
kt_detect_signals() {
  _kt_sp="$1"
  [ -z "$_kt_sp" ] && return
  _kt_sig=""
  _kt_bn=$(basename "$_kt_sp" 2>/dev/null)
  _kt_bnlow=$(printf '%s' "$_kt_bn" | tr '[:upper:]' '[:lower:]')

  _kt_append_signal() {
    if [ -z "$_kt_sig" ]; then
      _kt_sig="$1"
    else
      _kt_sig="${_kt_sig}, $1"
    fi
  }

  # Path-based: auth/permissions/security files
  case "$_kt_sp" in
    */auth/*|*/permissions/*|*/security/*|*/jwt/*|*/login/*) _kt_append_signal "auth" ;;
  esac

  # Path-based: data migrations
  case "$_kt_sp" in
    */migrations/*|*/migrate/*) _kt_append_signal "migration" ;;
  esac

  # Filename: data models / schemas
  case "$_kt_bn" in
    models.py|schema.ts|schema.prisma|*.prisma) _kt_append_signal "model" ;;
  esac

  # Filename: routing / middleware
  case "$_kt_bn" in
    urls.py|routes.ts|route.ts|middleware.ts) _kt_append_signal "routing" ;;
  esac

  # Filename: external-service integration (lowercased match)
  case "$_kt_bnlow" in
    *stripe*|*twilio*|*sendgrid*|*algolia*|*openai*|*vercel*|*supabase*|*auth0*|*firebase*|*segment*)
      _kt_append_signal "external-service" ;;
  esac

  printf '%s' "$_kt_sig"
}

# Batch-manifest support (v2.10.0)
# Per ADR 021 Plan A (Upgrades 1+2 bundled): skills and manual plan-execution
# declare an active batch by writing ~/.claude/active-batch.json. The pre-edit
# hook detects the manifest and, for matching low-impact ops, emits a compressed
# directive instead of the full Rule 22 format. Out-of-scope edits, high-impact
# declared ops, protected paths, and structural-signal-triggering files all
# still get full format — the safety floor.
#
# Manifest schema:
#   {
#     "batch_id": "unique-id",
#     "skill_name": "invoking-skill or 'manual-plan-execution'",
#     "plan_summary": "one-line description",
#     "started_at": "ISO-8601 UTC timestamp",
#     "expected_operations": [
#       { "file_path_pattern": "glob",
#         "operation_type": "create|update|delete",
#         "impact": "high|low",
#         "justification": "non-empty string" }
#     ]
#   }

KT_BATCH_MANIFEST="$HOME/.claude/active-batch.json"

# kt_batch_find_match FILE_PATH
# Check if file path matches an op in the active batch manifest.
# Stdout: pipe-separated "impact|justification|plan_summary|op_idx|op_total" on match.
# Stdout: empty if no active batch, no match, missing jq, or malformed manifest.
# Never fails or returns non-zero — callers interpret empty output as "no match."
kt_batch_find_match() {
  _kt_fp="$1"
  [ -z "$_kt_fp" ] && return

  # jq required for manifest parsing; graceful fallback if missing
  command -v jq >/dev/null 2>&1 || return

  [ -f "$KT_BATCH_MANIFEST" ] || return

  # Validate JSON parseable — malformed manifest falls back to full format
  jq empty "$KT_BATCH_MANIFEST" >/dev/null 2>&1 || return

  _kt_total=$(jq -r '.expected_operations | length' "$KT_BATCH_MANIFEST" 2>/dev/null)
  [ -z "$_kt_total" ] && return
  [ "$_kt_total" = "0" ] && return
  [ "$_kt_total" = "null" ] && return

  _kt_plan=$(jq -r '.plan_summary // ""' "$KT_BATCH_MANIFEST" 2>/dev/null)
  # Sanitize pipes in plan summary (would break output format)
  _kt_plan=$(printf '%s' "$_kt_plan" | tr '|' '_' | tr '\n' ' ')

  # Extract ops as one-per-line pipe-separated: pattern|impact|justification
  _kt_ops=$(jq -r '.expected_operations[] | "\(.file_path_pattern // "")\u00fe\(.impact // "")\u00fe\(.justification // "")"' "$KT_BATCH_MANIFEST" 2>/dev/null)

  _kt_idx=0
  _kt_old_ifs="$IFS"
  IFS='
'
  for _kt_line in $_kt_ops; do
    _kt_idx=$((_kt_idx + 1))
    # Use thorn (U+00FE) as delimiter — unlikely in paths/justifications
    _kt_pat="${_kt_line%%þ*}"
    _kt_rest="${_kt_line#*þ}"
    _kt_imp="${_kt_rest%%þ*}"
    _kt_just="${_kt_rest#*þ}"

    # Validation: all three required fields must be non-empty.
    # (b) — empty justification means the manifest author didn't articulate the
    # op's rationale; we fall back to full format by skipping this op.
    [ -z "$_kt_pat" ] && continue
    [ -z "$_kt_imp" ] && continue
    [ -z "$_kt_just" ] && continue
    # Impact must be literally "high" or "low" — anything else is invalid
    case "$_kt_imp" in
      high|low) ;;
      *) continue ;;
    esac

    # Glob match against file path — case pattern expansion uses unquoted $_kt_pat
    case "$_kt_fp" in
      $_kt_pat)
        IFS="$_kt_old_ifs"
        # Sanitize pipes in justification (would break output format)
        _kt_just_safe=$(printf '%s' "$_kt_just" | tr '|' '_' | tr '\n' ' ')
        printf '%s|%s|%s|%s|%s' "$_kt_imp" "$_kt_just_safe" "$_kt_plan" "$_kt_idx" "$_kt_total"
        return
        ;;
    esac
  done
  IFS="$_kt_old_ifs"
}

# kt_batch_begin SKILL_NAME PLAN_SUMMARY OPS_JSON
# Write active batch manifest. OPS_JSON must be a JSON array string where each
# element has file_path_pattern, operation_type, impact (high|low), and
# justification (all required, non-empty for declared-low ops).
# Returns non-zero and prints error to stderr on validation failure.
kt_batch_begin() {
  _kt_skill="$1"
  _kt_plan="$2"
  _kt_ops="$3"

  if ! command -v jq >/dev/null 2>&1; then
    echo "kt_batch_begin: jq is required for batch manifests. Install via 'brew install jq' (macOS) or your package manager. Falling back to no batch." >&2
    return 1
  fi

  [ -z "$_kt_skill" ] && { echo "kt_batch_begin: skill_name required" >&2; return 1; }
  [ -z "$_kt_plan" ] && { echo "kt_batch_begin: plan_summary required" >&2; return 1; }
  [ -z "$_kt_ops" ] && { echo "kt_batch_begin: expected_operations JSON array required" >&2; return 1; }

  # Validate ops JSON is a non-empty array with valid structure on each entry
  _kt_validation=$(printf '%s' "$_kt_ops" | jq -e '
    if type != "array" then error("expected_operations must be an array") else . end
    | if length == 0 then error("expected_operations must be non-empty") else . end
    | all(
        (.file_path_pattern | type == "string" and length > 0) and
        (.impact | (. == "high" or . == "low")) and
        (.justification | type == "string" and length > 0)
      )
  ' 2>&1)
  if [ "$_kt_validation" != "true" ]; then
    echo "kt_batch_begin: expected_operations validation failed — each op needs non-empty file_path_pattern, impact in {high,low}, and non-empty justification. Error: $_kt_validation" >&2
    return 1
  fi

  _kt_batch_id="batch-$(date +%Y%m%d-%H%M%S)-$$"
  _kt_now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  mkdir -p "$HOME/.claude" 2>/dev/null

  jq -n \
    --arg batch_id "$_kt_batch_id" \
    --arg skill_name "$_kt_skill" \
    --arg plan_summary "$_kt_plan" \
    --arg started_at "$_kt_now" \
    --argjson expected_operations "$_kt_ops" \
    '{batch_id: $batch_id, skill_name: $skill_name, plan_summary: $plan_summary, started_at: $started_at, expected_operations: $expected_operations}' \
    > "$KT_BATCH_MANIFEST" 2>/dev/null

  if [ ! -f "$KT_BATCH_MANIFEST" ]; then
    echo "kt_batch_begin: failed to write manifest at $KT_BATCH_MANIFEST" >&2
    return 1
  fi

  printf '%s\n' "$_kt_batch_id"
}

# kt_batch_end
# Remove the active batch manifest. Safe to call even if no manifest exists.
kt_batch_end() {
  [ -f "$KT_BATCH_MANIFEST" ] && rm -f "$KT_BATCH_MANIFEST"
  return 0
}

# kt_batch_clear_stale [MAX_AGE_SECONDS]
# Remove the active batch manifest if older than MAX_AGE_SECONDS (default 1800 = 30 min).
# Called from session-start-check.sh to clean up after crashed sessions that didn't
# reach their kt_batch_end call.
kt_batch_clear_stale() {
  _kt_max="${1:-1800}"
  [ -f "$KT_BATCH_MANIFEST" ] || return

  # Prefer started_at from manifest; fall back to file mtime if jq unavailable or field missing
  _kt_started_epoch=""
  if command -v jq >/dev/null 2>&1 && jq empty "$KT_BATCH_MANIFEST" >/dev/null 2>&1; then
    _kt_started=$(jq -r '.started_at // ""' "$KT_BATCH_MANIFEST" 2>/dev/null)
    if [ -n "$_kt_started" ] && [ "$_kt_started" != "null" ]; then
      # Parse ISO-8601 UTC timestamp to epoch — platform-dependent
      if date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$_kt_started" +%s >/dev/null 2>&1; then
        _kt_started_epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$_kt_started" +%s)
      elif date -d "$_kt_started" +%s >/dev/null 2>&1; then
        _kt_started_epoch=$(date -d "$_kt_started" +%s)
      fi
    fi
  fi

  # Fallback: file mtime
  if [ -z "$_kt_started_epoch" ]; then
    _kt_started_epoch=$(stat -f %m "$KT_BATCH_MANIFEST" 2>/dev/null || stat -c %Y "$KT_BATCH_MANIFEST" 2>/dev/null)
  fi

  [ -z "$_kt_started_epoch" ] && return

  _kt_now=$(date +%s)
  _kt_age=$((_kt_now - _kt_started_epoch))
  [ "$_kt_age" -gt "$_kt_max" ] && rm -f "$KT_BATCH_MANIFEST"
}
