#!/bin/sh
# lib-prompt-surface.sh — the shared capture core for knowledge surfacing (spec C1).
#
# "Prompt text → ledger-filtered, ranked injection text", in ONE place. The Claude Code
# UserPromptSubmit hook (prompt-context-check.sh), the Cursor capture hook and the
# Antigravity PreInvocation responsibility each keep only an I/O adapter around it:
# read the host's payload, call kt_ps_strip_pasted + kt_ps_surface, wrap the printed
# text in the host's own output shape. Moved out of prompt-context-check.sh (2.58.0).
#
# Byte-identical in every port that carries it (claude-code scripts/, cursor-template
# scripts/aria/, antigravity bin/ via build.sh). For that reason it names NO port's
# config location: build.sh rewrites the claude config directory in bin/*.sh, and
# Cursor's default is repo-relative. The adapter supplies KT_CONFIG instead (below).
#
# Usage (POSIX sh, sourced):
#   KT_PS_SCRIPT_DIR=<dir holding this port's config.sh + lib-index-match.sh>
#   KT_PS_RUNTIME=<claude-code|cursor|antigravity>   # names the runtime in the debug log
#   KT_CONFIG=${KT_CONFIG:-<this port's config.sh default>}  # see kt_ps_load_config
#   . "$KT_PS_SCRIPT_DIR/lib-prompt-surface.sh"
#   . "$KT_PS_SCRIPT_DIR/lib-state-key.sh"; kt_state_resolve || exit 0   # no state: surface nothing
#   text=$(printf '%s' "$raw" | kt_ps_strip_pasted)
#   sid=$(kt_session_key "$INPUT" session_id) || exit 0   # lib-state-key.sh: validated, never rewritten
#   ledger=$(kt_state_path "aria-active-$sid") || exit 0
#   kt_ps_surface "$text" "$ledger" >/dev/null     # no $( ): keeps the variables below
#
# State (2.58.0): every name this file keeps — the debug log, the config-value cache — is built
# with kt_state_path in the caller's private state dir (lib-state-key.sh, spec D4). When it cannot
# name one (no state dir, or the caller never resolved) nothing is cached and nothing is logged.
# The caller decides what "no state" means for surfacing: every hook surfaces nothing (spec D3),
# because without the ledger the same files would be injected on every prompt.
#   [ -n "$KT_PS_TEXT" ] || exit 0
#   <deliver $KT_PS_TEXT in the host's shape> && kt_ps_commit "$ledger"
#
# Interface:
#   kt_ps_load_config            sets KT_CONFIGURED, KT_CONFIG_ERROR, KT_KNOWLEDGE_FOLDER,
#                                KT_ACTIVE_SURFACING, KT_PROJECTS_ENABLED, KT_PROJECTS_LIST
#   kt_ps_strip_pasted           stdin → stdout, <pasted_content …> … </pasted_content …> removed
#   kt_ps_surface TEXT LEDGER    ranks TEXT, drops what LEDGER already holds, and prints the
#                                injection text or nothing. Sets KT_PS_STATUS to
#                                injected | nothing-new | nofire | disabled | error:<step>,
#                                KT_PS_TEXT to what it printed (empty otherwise), and
#                                KT_PS_PENDING to the knowledge-folder-relative paths that
#                                text names, one per line. It does NOT record the ledger.
#                                A ranked entry that is not a plain relative path (the
#                                ledger could never record it) is dropped before delivery
#                                and logged once per call as `dropped-unsafe-entry`.
#                                Every error:<step> also appends one line to the debug log.
#   kt_ps_commit LEDGER          appends KT_PS_PENDING to LEDGER, then clears it (a second
#                                call adds nothing). Same line filter as kt_ps_commit_paths
#                                (one shared function): only plain relative paths are kept.
#   kt_ps_commit_paths LEDGER FILE  appends FILE's non-blank lines to LEDGER. For a host that
#                                delivers in a LATER process: store KT_PS_PENDING in a file at
#                                rank time, commit from it once delivered. A FILE that is a
#                                symlink, not owned by the caller, or holds a NUL byte is
#                                refused; of the rest, only plain relative paths are kept
#                                (a line with a control character, CR included, a leading
#                                `/`, or a `..` segment is dropped) — ledger lines are later
#                                shown to the model.
#   kt_ps_log RUNTIME STEP REASON  appends `<UTC> <runtime> <step> <reason>` to
#                                <state dir>/aria-surface-hook.log (nothing without a state
#                                dir); never writes stdout.
#
# The ledger contract: it records ONLY what the model was actually handed. Ranking is not
# delivery — Cursor ranks in beforeSubmitPrompt and delivers in a later postToolUse, which
# may never fire — so recording at rank time would mark files as seen that the model never
# received and suppress them for the rest of the session. Commit after delivery succeeded,
# never before, and not at all when delivery failed.
#
# KT_PS_STATUS, KT_PS_TEXT and KT_PS_PENDING are set in the CALLING shell. Calling
# kt_ps_surface inside $( ) runs it in a subshell and loses all three (the log line still
# happens) — call it directly with stdout redirected, as above.
#
# Latency (spec C2/C4: p95 <= 150 ms warm on a ~45k-line index). Sourcing config.sh
# costs ~150 ms on its own (42 sed|grep|sed pipelines), so kt_ps_load_config reads the
# six values it needs from a cache that config.sh ITSELF fills: on a miss it sources
# config.sh and writes the resulting values; on a hit it READS them back as data (never
# sourced). The cache key is the cksum (content + size + path) of the config file AND of
# config.sh, so editing either one is a miss. config.sh stays the only parser — nothing
# here interprets the config file's syntax.

KT_PS_STATUS=""

_kt_ps_nl='
'

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

# --- debug log ----------------------------------------------------------------
# Failures only, never stdout, never model context (spec C3). The line is built first (the
# `date` fork included); only then is the log created with kt_create_new and appended to, and
# only when it is a regular file of ours that is not a link (a second guard inside the private
# state dir, spec D2). No state dir, or a caller that never resolved one: nothing is written.
kt_ps_log() {
  _kt_ps_logf=$(kt_state_path aria-surface-hook.log 2>/dev/null) || return 0
  _kt_ps_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _kt_ps_ts="unknown-time"
  _kt_ps_line=$(printf '%s %s %s %s' "$_kt_ps_ts" "${1:-unknown}" "${2:-unknown}" "${3:-unknown}" \
    | tr '\r\n' '  ' 2>/dev/null)
  [ -e "$_kt_ps_logf" ] || [ -L "$_kt_ps_logf" ] || kt_create_new "$_kt_ps_logf" || :
  kt_is_ours "$_kt_ps_logf" || return 0
  printf '%s\n' "$_kt_ps_line" >> "$_kt_ps_logf" 2>/dev/null
  return 0
}

_kt_ps_fail() { # STEP — record an error status and log it
  KT_PS_STATUS="error:$1"
  kt_ps_log "${KT_PS_RUNTIME:-unknown}" surface "$1"
}

# --- session id ----------------------------------------------------------------
# 2.58.0: the ledger id is kt_session_key / kt_session_key_check (lib-state-key.sh) — accepted only
# as [A-Za-z0-9._-]+ and never rewritten. kt_ps_sanitize_id, which STRIPPED every other byte, is
# retired: stripping is not injective (`a+b` and `ab` named one ledger for two sessions).

# --- input: the user's own words ---------------------------------------------------
# Pasted text is not the user's words. Every line from one that opens a
# `<pasted_content` block through the line holding its closing `</pasted_content` is
# dropped; a block that opens and closes on one line drops that line; an unterminated
# block drops everything after it. Text with no opener passes through untouched (no
# jq run). Without jq the paste branch prints nothing (fails closed: nothing to rank).
kt_ps_strip_pasted() {
  _kt_ps_in=$(cat 2>/dev/null) || _kt_ps_in=""
  case $_kt_ps_in in
    *'<pasted_content'*) ;;
    *) [ -n "$_kt_ps_in" ] && printf '%s\n' "$_kt_ps_in"; return 0 ;;
  esac
  printf '%s' "$_kt_ps_in" | jq -Rrs '
    def scan($p):
      if $p then
        (if test("</pasted_content") then sub("^.*?</pasted_content"; "") | scan(false) else true end)
      else
        (if test("<pasted_content") then sub("^.*?<pasted_content"; "") | scan(true) else false end)
      end;
    split("\n")
    | reduce .[] as $l ({p: false, k: []};
        .p as $p
        | if $p or ($l | test("<pasted_content")) then .p = ($l | scan($p))
          else .k += [$l] end)
    | .k | join("\n")
  ' 2>/dev/null
}

# --- config, via the config.sh-filled cache ----------------------------------------
# KT_CONFIG names the config file. The adapter sets it to its port's config.sh default
# when the user has not (the same expression as config.sh's first assignment), so the
# cache can be keyed before config.sh runs. With KT_CONFIG empty this sources config.sh
# every call and caches nothing: correct, only slower.
#
# The cache is DATA, never shell code: it is read back with `read`, so nothing in it
# can execute even if something unexpected sits at the name. It lives in the private
# state dir (2.58.0; before that, a shared temp dir where another user could pre-create
# it). Layout, one value per line:
#   aria-prompt-config 1 · <key> · KT_CONFIGURED · KT_CONFIG_ERROR ·
#   KT_KNOWLEDGE_FOLDER · KT_ACTIVE_SURFACING · KT_PROJECTS_ENABLED ·
#   KT_PROJECTS_LIST · end
# A value is used only after the header, the key and the end sentinel all match. A
# symlink is refused before the ownership test, which follows links. A key or value
# holding a newline cannot be stored this way and is simply not cached (a miss every
# call: correct, only slower).
#
# The file NAME carries a cksum of the config path (gate-2 G1): the ports read different
# configs, and one fixed name would thrash between runtimes and Cursor workspaces. The
# path is also inside the key (cksum prints it), so a name collision is only a miss.
kt_ps_load_config() {
  KT_CONFIGURED=false; KT_CONFIG_ERROR=""
  [ -n "${KT_PS_SCRIPT_DIR:-}" ] && [ -f "$KT_PS_SCRIPT_DIR/config.sh" ] || return 0
  _kt_ps_cfg=${KT_CONFIG:-}
  if [ -z "$_kt_ps_cfg" ]; then
    . "$KT_PS_SCRIPT_DIR/config.sh" >/dev/null 2>&1
    return 0
  fi
  # No file there: config.sh would report KT_CONFIGURED=false, which is this return.
  [ -f "$_kt_ps_cfg" ] || return 0

  _kt_ps_hdr="aria-prompt-config 1"
  # One cksum process for both: line 1 hashes the config PATH (read from /dev/stdin) and
  # names the cache file; lines 2-3 are the key. Any other shape leaves the key empty,
  # which only means "do not cache" — never a wrong hit.
  _kt_ps_key=$(printf '%s' "$_kt_ps_cfg" \
    | cksum /dev/stdin "$_kt_ps_cfg" "$KT_PS_SCRIPT_DIR/config.sh" 2>/dev/null) || _kt_ps_key=""
  _kt_ps_pk=${_kt_ps_key%% *}
  case $_kt_ps_pk in ''|*[!0-9]*) _kt_ps_pk=0 ;; esac
  # The cache lives in the private state dir. No name (no state dir, or the caller never
  # resolved one), or something at the name that is not a regular file (a FIFO would block the
  # read; `mv -f` onto a directory moves the temp INTO it): no cache — config.sh every call.
  _kt_ps_cache=$(kt_state_path "aria-prompt-config.${_kt_ps_pk}.cache" 2>/dev/null) || _kt_ps_cache=""
  if [ -z "$_kt_ps_cache" ] || { [ -e "$_kt_ps_cache" ] && [ ! -f "$_kt_ps_cache" ]; }; then
    _kt_ps_cache=""; _kt_ps_key=""
  fi
  _kt_ps_key=${_kt_ps_key#*"$_kt_ps_nl"}
  # cksum prints one line per file; join the two key lines into one line.
  _kt_ps_k2=${_kt_ps_key#*"$_kt_ps_nl"}
  case $_kt_ps_k2 in
    *"$_kt_ps_nl"*|"$_kt_ps_key") _kt_ps_key="" ;;
    *) _kt_ps_key="${_kt_ps_key%%"$_kt_ps_nl"*} | $_kt_ps_k2" ;;
  esac
  if [ -n "$_kt_ps_key" ] && [ ! -L "$_kt_ps_cache" ] && [ -f "$_kt_ps_cache" ] && [ -O "$_kt_ps_cache" ] 2>/dev/null; then
    if { IFS= read -r _kt_ps_h && IFS= read -r _kt_ps_k \
         && IFS= read -r _kt_ps_v1 && IFS= read -r _kt_ps_v2 && IFS= read -r _kt_ps_v3 \
         && IFS= read -r _kt_ps_v4 && IFS= read -r _kt_ps_v5 && IFS= read -r _kt_ps_v6 \
         && IFS= read -r _kt_ps_end; } < "$_kt_ps_cache" 2>/dev/null \
       && [ "$_kt_ps_h" = "$_kt_ps_hdr" ] && [ "$_kt_ps_k" = "$_kt_ps_key" ] && [ "$_kt_ps_end" = "end" ]; then
      KT_CONFIGURED=$_kt_ps_v1; KT_CONFIG_ERROR=$_kt_ps_v2; KT_KNOWLEDGE_FOLDER=$_kt_ps_v3
      KT_ACTIVE_SURFACING=$_kt_ps_v4; KT_PROJECTS_ENABLED=$_kt_ps_v5; KT_PROJECTS_LIST=$_kt_ps_v6
      return 0
    fi
  fi
  . "$KT_PS_SCRIPT_DIR/config.sh" >/dev/null 2>&1
  # Cache only when config.sh read the file this key was computed for, and only values
  # that fit on one line each.
  case "$_kt_ps_key$KT_CONFIGURED$KT_CONFIG_ERROR$KT_KNOWLEDGE_FOLDER$KT_ACTIVE_SURFACING$KT_PROJECTS_ENABLED$KT_PROJECTS_LIST" in
    *"$_kt_ps_nl"*) _kt_ps_key="" ;;
  esac
  if [ -n "$_kt_ps_key" ] && [ "$KT_CONFIG" = "$_kt_ps_cfg" ]; then
    # Temp file in the cache's own dir, then mv: a reader never sees half a file. ⚠ mv is
    # NOT a safe replace of whatever sits at the name: `mv -f` onto a directory (or a link to
    # one) moves the temp INTO it (measured). That is why a non-regular entry at the name
    # disabled the cache above; inside the private state dir only our own mistake can put one.
    _kt_ps_tmp=$(mktemp "${_kt_ps_cache%/*}/.aria-prompt-config.XXXXXX" 2>/dev/null) || _kt_ps_tmp=""
    if [ -n "$_kt_ps_tmp" ]; then
      if printf '%s\n' "$_kt_ps_hdr" "$_kt_ps_key" "$KT_CONFIGURED" "$KT_CONFIG_ERROR" \
           "$KT_KNOWLEDGE_FOLDER" "$KT_ACTIVE_SURFACING" "$KT_PROJECTS_ENABLED" \
           "$KT_PROJECTS_LIST" end > "$_kt_ps_tmp" 2>/dev/null \
         && mv -f "$_kt_ps_tmp" "$_kt_ps_cache" 2>/dev/null; then :
      else rm -f "$_kt_ps_tmp" 2>/dev/null; fi
    fi
  fi
  return 0
}

# --- rank, drop what this session has already seen, format -------------------------
# Output (C4, Claude Code 2.1.319): the host replaces a value over 10,000 chars with a
# file path + preview, so this prints paths only (never file bodies or descriptions)
# and keeps the path list under 9,000 chars.
kt_ps_surface() {
  KT_PS_STATUS="error:incomplete"; KT_PS_TEXT=""; KT_PS_PENDING=""
  _kt_ps_text=$1
  _kt_ps_ledger=${2:-}
  if [ -z "${KT_PS_SCRIPT_DIR:-}" ] || [ ! -f "$KT_PS_SCRIPT_DIR/config.sh" ] \
     || [ ! -f "$KT_PS_SCRIPT_DIR/lib-index-match.sh" ]; then
    _kt_ps_fail scripts-missing; return 0
  fi
  kt_ps_load_config
  if [ -n "$KT_CONFIG_ERROR" ]; then _kt_ps_fail config; return 0; fi
  if [ "$KT_CONFIGURED" != "true" ] || [ "$KT_ACTIVE_SURFACING" != "true" ]; then
    KT_PS_STATUS="disabled"; return 0
  fi
  if [ ! -f "$KT_KNOWLEDGE_FOLDER/index.md" ]; then _kt_ps_fail no-index; return 0; fi
  if [ -z "$_kt_ps_text" ]; then KT_PS_STATUS="nofire"; return 0; fi
  if [ -z "$_kt_ps_ledger" ]; then _kt_ps_fail no-ledger; return 0; fi

  if [ -z "${_kt_ps_match_loaded:-}" ]; then
    . "$KT_PS_SCRIPT_DIR/lib-index-match.sh"
    _kt_ps_match_loaded=1
  fi
  kt_index_match "$_kt_ps_text" 2>/dev/null
  case ${KT_MATCH_STATUS:-} in
    ok) ;;
    nofire) kt_match_cleanup; KT_PS_STATUS="nofire"; return 0 ;;
    error:?*) kt_match_cleanup; _kt_ps_fail "${KT_MATCH_STATUS#error:}"; return 0 ;;
    *) kt_match_cleanup; _kt_ps_fail "match-status-${KT_MATCH_STATUS:-unset}"; return 0 ;;
  esac
  kt_match_filter_ledger "$_kt_ps_ledger" 2>/dev/null
  if ! [ "${KT_MATCH_COUNT:-0}" -gt 0 ] 2>/dev/null || [ ! -f "$KT_MATCH_FILES_TMP" ]; then
    kt_match_cleanup
    KT_PS_STATUS="nothing-new"
    return 0
  fi

  # Pending = the path part of each INJECTED entry (text before the first " — ", exactly
  # what kt_match_record_ledger writes), so an entry cut by the bound is never pending.
  # Delivered must equal recordable: an entry the ledger would refuse (_kt_ps_plain_rel) is
  # dropped HERE, before it reaches the model, or it would be re-delivered on every prompt.
  _kt_ps_list=""; _kt_ps_pend=""; _kt_ps_n=0; _kt_ps_dropped=0
  while IFS= read -r _kt_ps_line || [ -n "$_kt_ps_line" ]; do
    _kt_ps_rel=${_kt_ps_line%% — *}
    if ! _kt_ps_plain_rel "$_kt_ps_rel"; then _kt_ps_dropped=1; continue; fi
    _kt_ps_try="$_kt_ps_list$_kt_ps_nl- $KT_KNOWLEDGE_FOLDER/$_kt_ps_rel"
    if [ "${#_kt_ps_try}" -gt 9000 ]; then break; fi
    _kt_ps_list=$_kt_ps_try; _kt_ps_n=$((_kt_ps_n + 1))
    _kt_ps_pend="$_kt_ps_pend$_kt_ps_rel$_kt_ps_nl"
  done < "$KT_MATCH_FILES_TMP"
  kt_match_cleanup
  [ "$_kt_ps_dropped" -eq 1 ] && kt_ps_log "${KT_PS_RUNTIME:-unknown}" surface dropped-unsafe-entry
  if [ "$_kt_ps_n" -eq 0 ]; then
    if [ "$_kt_ps_dropped" -eq 1 ]; then KT_PS_STATUS="nothing-new"; else _kt_ps_fail too-long; fi
    return 0
  fi

  _kt_ps_out="ARIA ACTIVE — ${_kt_ps_n} knowledge file(s) for this task (tags: ${KT_MATCH_TAGS}). Read them before answering and say in one line which you used and why:${_kt_ps_list}"
  if ! printf '%s\n' "$_kt_ps_out" 2>/dev/null; then _kt_ps_fail write; return 0; fi
  KT_PS_TEXT=$_kt_ps_out
  KT_PS_PENDING=${_kt_ps_pend%"$_kt_ps_nl"}
  KT_PS_STATUS="injected"
  return 0
}

# --- record what was DELIVERED --------------------------------------------------
# Separate from kt_ps_surface on purpose: see "The ledger contract" in the header.

# _kt_ps_plain_rel PATH — the ONE shape test for a knowledge-folder-relative path: true
# unless PATH is empty, starts with `/`, has a `..` segment, or holds a control character
# (CR and tab included; a NUL cannot reach a shell variable). kt_ps_surface applies it to
# what it DELIVERS and _kt_ps_append_kept to what the ledger RECORDS, so the two sets are
# the same set: an entry that could not be recorded is never delivered.
_kt_ps_plain_rel() {
  case $1 in
    ''|/*|..|../*|*/../*|*/..|*[[:cntrl:]]*) return 1 ;;
  esac
  return 0
}

# _kt_ps_append_kept LEDGER — the ONE ledger writer, shared by both commits. Reads lines on
# stdin and appends, in one write, only those _kt_ps_plain_rel accepts. Ledger lines are
# shown to the model again (session start after compaction), so nothing else may reach it.
_kt_ps_append_kept() { # LEDGER
  _kt_ps_add=""
  while IFS= read -r _kt_ps_l || [ -n "$_kt_ps_l" ]; do
    _kt_ps_plain_rel "$_kt_ps_l" || continue
    _kt_ps_add="$_kt_ps_add$_kt_ps_l$_kt_ps_nl"
  done
  [ -n "$_kt_ps_add" ] || return 0
  # The ledger (in the private state dir) is created only by kt_create_new, and appended to only
  # when it is a regular file of ours that is not a link (final fix wave F7, spec §5; kept as a
  # second guard, spec D2).
  [ -e "$1" ] || [ -L "$1" ] || kt_create_new "$1" || :
  kt_is_ours "$1" || return 0
  printf '%s' "$_kt_ps_add" >> "$1" 2>/dev/null
  return 0
}

kt_ps_commit() { # LEDGER
  [ -n "${1:-}" ] && [ -n "${KT_PS_PENDING:-}" ] || return 0
  _kt_ps_append_kept "$1" <<KT_PS_PENDING_EOF
$KT_PS_PENDING
KT_PS_PENDING_EOF
  KT_PS_PENDING=""
  return 0
}

kt_ps_commit_paths() { # LEDGER FILE
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 0
  [ ! -L "$2" ] && [ -f "$2" ] && [ -O "$2" ] 2>/dev/null || return 0
  # A shell `read` silently drops NUL bytes, so a line holding one would be recorded as a
  # DIFFERENT path. Refuse the whole file instead: this host did not write it.
  _kt_ps_n1=$(wc -c < "$2" 2>/dev/null) || return 0
  _kt_ps_n2=$(LC_ALL=C tr -d '\000' < "$2" 2>/dev/null | wc -c) || return 0
  [ "$_kt_ps_n1" -eq "$_kt_ps_n2" ] 2>/dev/null || return 0
  _kt_ps_append_kept "$1" < "$2"
}
