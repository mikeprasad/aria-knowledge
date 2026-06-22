#!/bin/sh
# lib-index-match.sh — shared tag-match helper for aria-knowledge
# Sourced by hook scripts and (indirectly via skill-driven Bash) by skills
# that surface knowledge-index matches. Refactored out of the inline matcher
# previously living in task-context-check.sh (v2.14.x → v2.15.0).
#
# Usage:
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   . "$SCRIPT_DIR/config.sh"           # provides KT_KNOWLEDGE_FOLDER
#   . "$SCRIPT_DIR/lib-index-match.sh"  # provides kt_index_match
#
#   kt_index_match "fix stripe webhook timeout"
#   if [ "$KT_MATCH_COUNT" -gt 0 ]; then
#     # KT_MATCH_TAGS       — space-separated matched known-tag list
#     # KT_MATCH_COUNT      — integer, files matched (≤5, post-dedupe)
#     # KT_MATCH_FILES_TMP  — path to temp file; one "path — description" per line
#     do_something_with "$KT_MATCH_FILES_TMP"
#   fi
#   kt_match_cleanup
#
# Contract:
#   - Sets/resets KT_MATCH_TAGS, KT_MATCH_COUNT, KT_MATCH_FILES_TMP on entry.
#   - Returns 0 in all states; callers branch on KT_MATCH_COUNT.
#   - Caller MUST invoke kt_match_cleanup to remove the temp file when done.
#   - Honors the ≥2-tag-match threshold and 5-file emission cap historically
#     enforced by task-context-check.sh. Changing those is a deliberate
#     cross-cutting policy change, not a per-caller knob.
#
# Inputs (environment):
#   KT_KNOWLEDGE_FOLDER  — absolute path to the knowledge root (required)
#
# What this does NOT cover (caller's responsibility):
#   - Cooldowns / throttling — per-trigger policy, not shared mechanism.
#   - Output formatting — each caller formats matched paths its own way.
#   - Per-session dedup ledger (/tmp/aria-active-{session_id}) — added in
#     checkpoint 2 across active-mode hooks.
#   - Active vs passive wording — caller branches on KT_ACTIVE_SURFACING.

kt_index_match() {
  KT_MATCH_TAGS=""
  KT_MATCH_COUNT=0
  KT_MATCH_FILES_TMP=""

  _kt_query="$1"
  [ -z "$_kt_query" ] && return 0
  [ -z "$KT_KNOWLEDGE_FOLDER" ] && return 0

  _kt_index="$KT_KNOWLEDGE_FOLDER/index.md"
  [ ! -f "$_kt_index" ] && return 0

  # Tokenize: lowercase, then emit TWO kinds of tokens, deduped together:
  #   1. hyphen-preserving whole tokens — so a multi-word directory/tag name
  #      like `web-app` survives as ONE token and can match its exact
  #      `### web-app` known tag (otherwise the hyphen is destroyed and only
  #      the broad parent token `web` matches → wrong files surface).
  #   2. fully-split alnum words — preserves the original single-word matching
  #      (`web`, `app`) for backward compatibility.
  # Both passes feed one deduped set; the matcher still does exact word==tag.
  _kt_lower=$(printf '%s' "$_kt_query" | tr '[:upper:]' '[:lower:]')
  _kt_whole=$(printf '%s' "$_kt_lower" | tr -cs '[:alnum:]-' ' ' | tr ' ' '\n')
  _kt_split=$(printf '%s' "$_kt_lower" | tr -cs '[:alnum:]' ' ' | tr ' ' '\n')
  _kt_words=$(printf '%s\n%s\n' "$_kt_whole" "$_kt_split" | grep -v '^-*$' | sort -u)
  [ -z "$_kt_words" ] && return 0

  # Extract "### tagname" headers from the ## Tag Index section only.
  # ## Other Tags (freeform tier) is intentionally excluded — only promoted
  # known tags participate in auto-surfacing.
  _kt_tags=$(sed -n '/^## Tag Index$/,/^## /p' "$_kt_index" \
             | grep '^### ' \
             | sed 's/^### //' \
             | tr '[:upper:]' '[:lower:]')
  [ -z "$_kt_tags" ] && return 0

  # Exact word-vs-tag match (no substring, no fuzzy). Each tag can match
  # at most once; inner loop breaks on first hit.
  _kt_matched=""
  _kt_match_count=0
  for _kt_tag in $_kt_tags; do
    for _kt_word in $_kt_words; do
      if [ "$_kt_word" = "$_kt_tag" ]; then
        _kt_matched="${_kt_matched} ${_kt_tag}"
        _kt_match_count=$((_kt_match_count + 1))
        break
      fi
    done
  done

  # Precision floor: ≥2 distinct tag hits required. Single-tag matches
  # generate too many false positives given ~670 freeform tags in play.
  [ "$_kt_match_count" -lt 2 ] && return 0

  # Collect file lines under matched tag headers, dedupe by path, cap at 5.
  _kt_raw=$(mktemp /tmp/aria-match-raw.XXXXXX) || return 0
  _kt_files=$(mktemp /tmp/aria-match-files.XXXXXX) || { rm -f "$_kt_raw"; return 0; }

  # Most-specific-tag-first: a longer tag name is a more specific match
  # (`web-app` > `web`/`app`), so its files should fill the 5-cap BEFORE a
  # broad parent tag dilutes them. Sort matched tags by length desc.
  _kt_ordered=$(printf '%s\n' $_kt_matched \
                | awk '{ print length, $0 }' | sort -rn -k1,1 | cut -d' ' -f2-)

  for _kt_tag in $_kt_ordered; do
    awk "/^### ${_kt_tag}\$/{found=1; next} /^##/{found=0} found && /^- /" "$_kt_index" \
      | sed 's/^- //' >> "$_kt_raw"
  done

  if [ -s "$_kt_raw" ]; then
    awk -F ' — ' '!seen[$1]++' "$_kt_raw" | head -5 > "$_kt_files"
  fi
  rm -f "$_kt_raw" 2>/dev/null

  if [ ! -s "$_kt_files" ]; then
    rm -f "$_kt_files" 2>/dev/null
    return 0
  fi

  KT_MATCH_COUNT=$(wc -l < "$_kt_files" | tr -d ' ')
  KT_MATCH_TAGS=$(printf '%s' "$_kt_matched" | sed 's/^ //')
  KT_MATCH_FILES_TMP="$_kt_files"
  return 0
}

# Release the temp file allocated by kt_index_match. Idempotent.
kt_match_cleanup() {
  if [ -n "$KT_MATCH_FILES_TMP" ] && [ -f "$KT_MATCH_FILES_TMP" ]; then
    rm -f "$KT_MATCH_FILES_TMP" 2>/dev/null
  fi
  KT_MATCH_FILES_TMP=""
}

# Filter currently-matched files against a session ledger: drop any line whose
# path-part (text before " — ") appears in the ledger file. Updates the temp
# file in place and refreshes KT_MATCH_COUNT. No-op if ledger missing/empty
# or no current matches. Used by active-mode hooks to avoid re-surfacing the
# same file twice across triggers within one session.
kt_match_filter_ledger() {
  _kt_ledger="$1"
  [ -z "$_kt_ledger" ] && return 0
  [ ! -f "$_kt_ledger" ] && return 0
  [ ! -s "$_kt_ledger" ] && return 0
  [ -z "$KT_MATCH_FILES_TMP" ] && return 0
  [ ! -f "$KT_MATCH_FILES_TMP" ] && return 0

  _kt_filtered=$(mktemp /tmp/aria-match-filtered.XXXXXX) || return 0
  # awk: build a set of ledger paths, then emit only current-match lines whose
  # path-before-em-dash is not in the set. Ledger entries are bare paths
  # (one per line); current-match lines are "path — description".
  awk -F ' — ' '
    NR==FNR { seen[$0]=1; next }
    !($1 in seen) { print }
  ' "$_kt_ledger" "$KT_MATCH_FILES_TMP" > "$_kt_filtered"

  if [ -s "$_kt_filtered" ]; then
    mv "$_kt_filtered" "$KT_MATCH_FILES_TMP"
    KT_MATCH_COUNT=$(wc -l < "$KT_MATCH_FILES_TMP" | tr -d ' ')
  else
    rm -f "$_kt_filtered" 2>/dev/null
    rm -f "$KT_MATCH_FILES_TMP" 2>/dev/null
    KT_MATCH_FILES_TMP=""
    KT_MATCH_COUNT=0
  fi
}

# Append currently-matched paths (before " — ") to the session ledger. Creates
# parent directory if needed. Used by active-mode hooks after a successful
# surfacing, so subsequent triggers in the same session can dedup against it.
kt_match_record_ledger() {
  _kt_ledger="$1"
  [ -z "$_kt_ledger" ] && return 0
  [ -z "$KT_MATCH_FILES_TMP" ] && return 0
  [ ! -f "$KT_MATCH_FILES_TMP" ] && return 0
  awk -F ' — ' '{print $1}' "$KT_MATCH_FILES_TMP" >> "$_kt_ledger" 2>/dev/null
}
