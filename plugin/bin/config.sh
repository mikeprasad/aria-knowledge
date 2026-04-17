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
  KT_CRITICAL_PATHS=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^critical_paths:' | sed 's/^critical_paths: *//')
  KT_PROJECTS_ENABLED=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^projects_enabled:' | sed 's/^projects_enabled: *//')
  KT_PROJECTS_LIST=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^projects_list:' | sed 's/^projects_list: *//')
  KT_PROJECTS_REMOTES=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^projects_remotes:' | sed 's/^projects_remotes: *//')
  KT_PROJECTS_PROMOTION_THRESHOLD=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^projects_promotion_threshold:' | sed 's/^projects_promotion_threshold: *//')
  KT_AUTO_LOAD_PROJECT_CONTEXT=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^auto_load_project_context:' | sed 's/^auto_load_project_context: *//')
  KT_IDEAS_STALENESS_DAYS=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^ideas_staleness_threshold_days:' | sed 's/^ideas_staleness_threshold_days: *//')

  # Defaults if not set
  KT_CADENCE_KNOWLEDGE=${KT_CADENCE_KNOWLEDGE:-3}
  KT_CADENCE_CONFIG=${KT_CADENCE_CONFIG:-14}
  KT_EXPLANATORY=${KT_EXPLANATORY:-false}
  KT_FREEFORM_THRESHOLD=${KT_FREEFORM_THRESHOLD:-3}
  KT_STALENESS_MONTHS=${KT_STALENESS_MONTHS:-6}
  KT_CADENCE_UPDATE=${KT_CADENCE_UPDATE:-30}
  KT_AUTO_CAPTURE=${KT_AUTO_CAPTURE:-true}
  KT_PROJECTS_ENABLED=${KT_PROJECTS_ENABLED:-false}
  KT_PROJECTS_PROMOTION_THRESHOLD=${KT_PROJECTS_PROMOTION_THRESHOLD:-2}
  KT_AUTO_LOAD_PROJECT_CONTEXT=${KT_AUTO_LOAD_PROJECT_CONTEXT:-false}
  KT_IDEAS_STALENESS_DAYS=${KT_IDEAS_STALENESS_DAYS:-21}
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
    ''|*[!0-9]*) KT_CADENCE_KNOWLEDGE=3 ;;
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
fi

# kt_project_for_path PATH
# Returns the project tag for a given path, or empty if not in any configured project.
# Uses CWD-based substring matching first; falls back to git-remote-based matching
# if KT_PROJECTS_REMOTES is set and git is available.
# Early-returns silently if projects feature is disabled or unconfigured.
kt_project_for_path() {
  _kt_path="$1"
  [ -z "$_kt_path" ] && return
  [ "$KT_PROJECTS_ENABLED" = "true" ] || return
  [ -z "$KT_PROJECTS_LIST" ] && return

  # CWD-based: substring match against configured paths
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
      *"$_kt_proj_path"*) printf '%s' "$_kt_tag"; IFS="$_kt_old_ifs"; return ;;
    esac
  done
  IFS="$_kt_old_ifs"

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
