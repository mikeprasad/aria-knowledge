#!/bin/sh
# lib-tracked-artifacts.sh — shared CODEMAP/STITCH directory + full-file load primitive
# Sourced by hook scripts (bash-cd-check, session-start-check, task-context-check)
# and indirectly by skills (/prospect Step 0.5, /retrospect Step 0.5).
#
# Implements the v2.16.1 trigger-based-loading design (see ADR 083 +
# approaches/codemap-stitch-trigger-loading.md).
#
# Usage:
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   . "$SCRIPT_DIR/config.sh"            # provides KT_PROJECTS_LIST, KT_*_STALENESS_DAYS, etc.
#   . "$SCRIPT_DIR/lib-tracked-artifacts.sh"
#
#   kt_artifact_compute_for_path "/abs/path/inside/a/project"
#   if [ "$KT_ARTIFACTS_COUNT" -gt 0 ]; then
#     # KT_ARTIFACTS_INSTRUCTION  — user-facing instruction string (embed in additionalContext)
#     # KT_ARTIFACT_PATHS         — newline-separated absolute paths (for ledger record)
#     # KT_ARTIFACTS_COUNT        — integer (1 or 2: CODEMAP only, or CODEMAP + STITCH)
#     # KT_ARTIFACTS_PROJECT_TAG  — matched project tag (or empty)
#     #
#     # Caller embeds INSTRUCTION in additionalContext message, then calls
#     # kt_artifact_record_ledger to append PATHS to the session ledger.
#   fi
#
# Contract:
#   - Skip-conditions: projects feature disabled | input path not in any KT_PROJECTS_LIST
#     entry | file doesn't exist | grossly stale (>2x configured threshold).
#   - Honors KT_ACTIVE_SURFACING — active mode emits "Loaded …" instructions,
#     passive mode emits "consider …" suggestions.
#   - Honors KT_CODEMAP_STALENESS_DAYS (default 14) + KT_STITCH_STALENESS_DAYS
#     (default 30). Adds [STALE — …] annotation when age > threshold but
#     ≤ 2x threshold.
#   - STITCH presence is the multi-repo signal — if STITCH.md exists in the
#     resolved project root, it loads alongside CODEMAP.
#   - CODEMAP load uses boundary-detected directory only (~600-1200 tokens);
#     fallback to limit=50 if no boundary detected.
#   - STITCH load is full-file (~4K tokens; files are 188-200 lines typical).
#
# Inputs (environment):
#   KT_PROJECTS_ENABLED        — must be "true"
#   KT_PROJECTS_LIST           — comma-separated tag:path entries
#   KT_ACTIVE_SURFACING        — "true" enables Loaded-now wording
#   KT_CODEMAP_STALENESS_DAYS  — threshold, default 14
#   KT_STITCH_STALENESS_DAYS   — threshold, default 30
#
# What this does NOT cover (caller's responsibility):
#   - Cooldown gating per session/per-project (existing per-hook pattern)
#   - Ledger record (call kt_artifact_record_ledger after embedding instruction)
#   - Message-emission shape (additionalContext vs systemMessage etc.)

# ---------------------------------------------------------------------------
# kt_artifact_compute_for_path INPUT_PATH
#
# Given an absolute path inside (or equal to) a configured project root,
# computes load instruction + path list for CODEMAP + STITCH.
# Sets KT_ARTIFACTS_INSTRUCTION, KT_ARTIFACT_PATHS, KT_ARTIFACTS_COUNT,
# KT_ARTIFACTS_PROJECT_TAG.
# ---------------------------------------------------------------------------
kt_artifact_compute_for_path() {
  KT_ARTIFACTS_INSTRUCTION=""
  KT_ARTIFACT_PATHS=""
  KT_ARTIFACTS_COUNT=0
  KT_ARTIFACTS_PROJECT_TAG=""

  _kt_input_path="$1"
  [ -z "$_kt_input_path" ] && return 0
  [ "$KT_PROJECTS_ENABLED" = "true" ] || return 0
  [ -z "$KT_PROJECTS_LIST" ] && return 0

  # Resolve project root: iterate projects_list looking for first tag:path
  # entry whose path_part appears as substring in input_path. First match wins
  # (same semantics as config.sh's kt_project_for_path). projects_list
  # ordering matters — put more-specific entries (e.g., webapp:web/web-app)
  # BEFORE less-specific ones (web:web) to disambiguate sub-projects.
  _kt_proj_tag=""
  _kt_proj_root=""
  _kt_old_ifs="$IFS"
  IFS=','
  for _kt_entry in $KT_PROJECTS_LIST; do
    [ -z "$_kt_entry" ] && continue
    case "$_kt_entry" in *:*) ;; *) continue ;; esac
    _kt_tag="${_kt_entry%%:*}"
    _kt_proj_path_part="${_kt_entry#*:}"
    [ -z "$_kt_proj_path_part" ] && continue
    case "$_kt_input_path" in
      *"$_kt_proj_path_part"*)
        _kt_proj_tag="$_kt_tag"
        # Reconstruct project root: prefix of input_path up through the
        # first occurrence of project_path_part. Uses %% (longest greedy)
        # to strip the suffix, then re-append project_path_part.
        _kt_before="${_kt_input_path%%${_kt_proj_path_part}*}"
        _kt_proj_root="${_kt_before}${_kt_proj_path_part}"
        break
        ;;
    esac
  done
  IFS="$_kt_old_ifs"

  [ -z "$_kt_proj_tag" ] && return 0
  [ -z "$_kt_proj_root" ] && return 0
  [ ! -d "$_kt_proj_root" ] && return 0

  KT_ARTIFACTS_PROJECT_TAG="$_kt_proj_tag"

  _kt_codemap_path="$_kt_proj_root/CODEMAP.md"
  _kt_stitch_path="$_kt_proj_root/STITCH.md"
  _kt_codemap_thresh=${KT_CODEMAP_STALENESS_DAYS:-14}
  _kt_stitch_thresh=${KT_STITCH_STALENESS_DAYS:-30}
  _kt_grossly_codemap=$((_kt_codemap_thresh * 2))
  _kt_grossly_stitch=$((_kt_stitch_thresh * 2))

  _kt_now=$(date +%s)
  _kt_instructions=""
  _kt_paths=""
  _kt_count=0

  # --- CODEMAP -------------------------------------------------------------
  if [ -f "$_kt_codemap_path" ]; then
    # Portable mtime: macOS uses -f%m, Linux uses -c%Y
    _kt_mtime=$(stat -f%m "$_kt_codemap_path" 2>/dev/null || stat -c%Y "$_kt_codemap_path" 2>/dev/null)
    if [ -n "$_kt_mtime" ]; then
      _kt_age_days=$(( (_kt_now - _kt_mtime) / 86400 ))
      if [ "$_kt_age_days" -gt "$_kt_grossly_codemap" ]; then
        # Grossly stale — refuse to surface as reference, warn instead
        _kt_instructions="${_kt_instructions}[aria] CODEMAP for ${_kt_proj_tag} is ${_kt_age_days} days old (>${_kt_grossly_codemap}-day refusal threshold) — refused to load as reference; run /codemap update first. "
      else
        # Detect directory section end via boundary-line regex.
        # Pattern: first "## N." section header OR standalone "---" after line 5.
        _kt_dir_end=$(awk '/^## [0-9]+\.|^---$/ && NR>5 {print NR; exit}' "$_kt_codemap_path" 2>/dev/null)
        if [ -z "$_kt_dir_end" ]; then
          # Fallback: no boundary found, use safe over-read cap
          _kt_dir_limit=50
        else
          _kt_dir_limit=$((_kt_dir_end - 1))
        fi
        # Staleness label
        if [ "$_kt_age_days" -gt "$_kt_codemap_thresh" ]; then
          _kt_codemap_label="${_kt_age_days} days — STALE; consider /codemap update"
        else
          _kt_codemap_label="${_kt_age_days} days fresh"
        fi
        if [ "$KT_ACTIVE_SURFACING" = "true" ]; then
          _kt_instructions="${_kt_instructions}[aria] Loaded CODEMAP directory for ${_kt_proj_tag} (${_kt_codemap_label}). Read ${_kt_codemap_path} offset=0 limit=${_kt_dir_limit} — Directory only; specific feature sections load on-demand via offset+limit per the directory's line-number entries. "
        else
          _kt_instructions="${_kt_instructions}[aria] CODEMAP directory available for ${_kt_proj_tag} (${_kt_codemap_label}) at ${_kt_codemap_path}. Consider Read offset=0 limit=${_kt_dir_limit}. "
        fi
        _kt_paths="${_kt_paths}${_kt_codemap_path}
"
        _kt_count=$((_kt_count + 1))
      fi
    fi
  else
    # Missing CODEMAP — only nudge in active mode (passive shouldn't add noise)
    if [ "$KT_ACTIVE_SURFACING" = "true" ]; then
      _kt_instructions="${_kt_instructions}[aria] No CODEMAP found at ${_kt_codemap_path} — consider /codemap create for ${_kt_proj_tag}. "
    fi
  fi

  # --- STITCH (multi-repo signal: STITCH.md exists in project root) --------
  if [ -f "$_kt_stitch_path" ]; then
    _kt_mtime=$(stat -f%m "$_kt_stitch_path" 2>/dev/null || stat -c%Y "$_kt_stitch_path" 2>/dev/null)
    if [ -n "$_kt_mtime" ]; then
      _kt_age_days=$(( (_kt_now - _kt_mtime) / 86400 ))
      if [ "$_kt_age_days" -gt "$_kt_grossly_stitch" ]; then
        _kt_instructions="${_kt_instructions}[aria] STITCH for ${_kt_proj_tag} is ${_kt_age_days} days old (>${_kt_grossly_stitch}-day refusal threshold) — refused to load as reference; run /stitch verify ${_kt_proj_tag} first. "
      else
        if [ "$_kt_age_days" -gt "$_kt_stitch_thresh" ]; then
          _kt_stitch_label="${_kt_age_days} days — STALE; consider /stitch verify ${_kt_proj_tag}"
        else
          _kt_stitch_label="${_kt_age_days} days fresh"
        fi
        if [ "$KT_ACTIVE_SURFACING" = "true" ]; then
          _kt_instructions="${_kt_instructions}[aria] Loaded STITCH for ${_kt_proj_tag} (${_kt_stitch_label}). Read ${_kt_stitch_path} (full file — cross-repo binding tables). "
        else
          _kt_instructions="${_kt_instructions}[aria] STITCH available for ${_kt_proj_tag} (${_kt_stitch_label}) at ${_kt_stitch_path}. Consider Read (full file). "
        fi
        _kt_paths="${_kt_paths}${_kt_stitch_path}
"
        _kt_count=$((_kt_count + 1))
      fi
    fi
  fi
  # No "missing STITCH" nudge — STITCH absence is the normal case for
  # single-repo projects; nudging would be noise.

  KT_ARTIFACTS_INSTRUCTION="$_kt_instructions"
  KT_ARTIFACT_PATHS="$_kt_paths"
  KT_ARTIFACTS_COUNT=$_kt_count
  return 0
}

# ---------------------------------------------------------------------------
# kt_artifact_filter_ledger LEDGER_PATH
#
# If ANY currently-computed artifact path is already in the ledger, treat
# the project as already activated this session — clear everything (silent
# skip). Match-once-skip-all semantics. Different from lib-index-match's
# per-file filter because tracked artifacts cluster as a project unit.
# ---------------------------------------------------------------------------
kt_artifact_filter_ledger() {
  _kt_ledger="$1"
  [ -z "$_kt_ledger" ] && return 0
  [ ! -f "$_kt_ledger" ] && return 0
  # A link, a non-regular file or a file this user does not own at the ledger's predictable /tmp name is
  # not ours (final fix wave F7): never read it, never write through it.
  [ -L "$_kt_ledger" ] && return 0
  [ ! -O "$_kt_ledger" ] && return 0
  [ ! -s "$_kt_ledger" ] && return 0
  [ "$KT_ARTIFACTS_COUNT" -eq 0 ] && return 0

  _kt_old_ifs="$IFS"
  IFS='
'
  for _kt_p in $KT_ARTIFACT_PATHS; do
    [ -z "$_kt_p" ] && continue
    if grep -qF "$_kt_p" "$_kt_ledger" 2>/dev/null; then
      # Found at least one — clear everything (already activated this session)
      KT_ARTIFACTS_INSTRUCTION=""
      KT_ARTIFACT_PATHS=""
      KT_ARTIFACTS_COUNT=0
      IFS="$_kt_old_ifs"
      return 0
    fi
  done
  IFS="$_kt_old_ifs"
}

# --- safe create (spec §5) -----------------------------------------------------
# kt_create_new NAME — make NAME a new, empty regular file of ours (status 0), or fail (status 1)
# because something already exists there in any form, mktemp failed, or `link` is missing or
# failed. A temp file is made in NAME's directory and hard-linked to NAME with the POSIX `link`
# utility (link(2)), which fails on ANY existing name — file, directory, symlink (dangling or
# not), FIFO — and never opens or follows it. Not `ln`: given a symlink to a directory, `ln`
# creates the file INSIDE that directory. Not `set -C`: noclobber opens an existing FIFO without
# O_EXCL and blocks. The temp is removed either way; one left by a killed run is swept after 24 h
# (session-start-check.sh; Antigravity's housekeeping).
# kt_is_ours NAME — true iff NAME is not a link, is a regular file, and is owned by the caller.
# Every writer of a predictable name: compute the content, then
#   [ -e "$N" ] || [ -L "$N" ] || kt_create_new "$N" || :
#   kt_is_ours "$N" || return 0
#   <append to "$N">        (the very next line: no command in between)
# The existence test keeps steady state fork-free; a name planted after it only makes `link`
# fail. Bound: once created the file is ours, and in a sticky (/tmp) or private directory no
# other user can replace it before the append; in a non-sticky world-writable directory nothing
# at this layer helps. Identical in lib-prompt-surface.sh, lib-index-match.sh and
# lib-tracked-artifacts.sh (11 copies), pinned by tests/repros/safe-create-census.sh CC1.
kt_create_new() {
  if [ -e "$1" ] || [ -L "$1" ]; then return 1; fi
  case $1 in */*) _kt_cn_d=${1%/*}; [ -n "$_kt_cn_d" ] || _kt_cn_d=/ ;; *) _kt_cn_d=. ;; esac
  _kt_cn_t=$(mktemp "$_kt_cn_d/.aria-new.XXXXXX" 2>/dev/null) || return 1
  _kt_cn_rc=0; link "$_kt_cn_t" "$1" 2>/dev/null || _kt_cn_rc=1
  rm -f "$_kt_cn_t" 2>/dev/null
  return $_kt_cn_rc
}
kt_is_ours() { [ ! -L "$1" ] && [ -f "$1" ] && [ -O "$1" ]; }

# ---------------------------------------------------------------------------
# kt_artifact_record_ledger LEDGER_PATH
#
# Append currently-computed artifact paths to the session ledger. No-op if
# no artifacts. Idempotent at session level (grep filter in compute prevents
# duplicate-path appends when used correctly).
# ---------------------------------------------------------------------------
kt_artifact_record_ledger() {
  _kt_ledger="$1"
  [ -z "$_kt_ledger" ] && return 0
  [ "$KT_ARTIFACTS_COUNT" -eq 0 ] && return 0
  # The ledger's /tmp name is predictable: it is created only by kt_create_new, and appended to
  # only when it is a regular file of ours that is not a link (final fix wave F7, spec §5).
  [ -e "$_kt_ledger" ] || [ -L "$_kt_ledger" ] || kt_create_new "$_kt_ledger" || :
  kt_is_ours "$_kt_ledger" || return 0
  printf '%s' "$KT_ARTIFACT_PATHS" >> "$_kt_ledger" 2>/dev/null
}
