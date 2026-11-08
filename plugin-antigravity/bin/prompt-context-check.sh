#!/bin/sh
# prompt-context-check.sh — UserPromptSubmit hook for aria-knowledge (spec D1a).
#
# On every prompt: rank the knowledge index against the words the USER typed
# (kt_index_match), drop files this session has already surfaced (the shared
# ledger /tmp/aria-active-<session_id>, also used by task-context-check.sh and
# bash-cd-check.sh), and inject the remaining ranked PATHS as
# hookSpecificOutput.additionalContext. The model no longer runs the selection
# algorithm itself; it reads what this hook hands it.
#
# Silent (no output, exit 0) unless a not-yet-surfaced file ranks. Also silent
# when: jq is missing · stdin is empty, not JSON, not an object, or has no
# session_id · there is no config, it is invalid, or active_knowledge_surfacing
# is false · the knowledge folder has no index.md. Never blocks the prompt.
#
# Input (C1): pasted text is not the user's words. Every line from one that
# opens a `<pasted_content` block through the line holding its closing
# `</pasted_content` is dropped before matching; a block that opens and closes
# on one line drops that line; an unterminated block drops everything after it.
#
# Output (C4, Claude Code 2.1.319): hookSpecificOutput.additionalContext — a
# top-level field is ignored, and a value over 10,000 chars is replaced by a
# file path + preview, so this injects paths only (never file bodies or
# descriptions) and keeps the text under 9,000 chars.
#
# Latency (C2: p95 <= 150 ms warm on a ~45k-line index). Sourcing config.sh
# costs ~150 ms on its own (42 sed|grep|sed pipelines), so this hook reads the
# six values it needs from a cache that config.sh ITSELF fills: on a miss the
# hook sources config.sh and writes the resulting values; on a hit it READS
# them back as data (never sourced). The cache key is the cksum (content + size + path) of the config
# file AND of config.sh, so editing either one is a miss. config.sh stays the
# only parser — nothing here interprets the config file's syntax.

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0

# Drain stdin before ANY early exit. The host writes the prompt into a pipe; a
# hook that exits without reading can leave the writer blocked or failing.
# Read only when fd 0 is OPEN: with it closed, the pipe $( ) creates takes fd 0
# and cat reads its own output pipe forever (measured hang). `(exec 3<&0)` fails
# on a closed fd; `: <&0` does not, so it cannot be the test.
INPUT=""
if (exec 3<&0) 2>/dev/null; then INPUT=$(cat 2>/dev/null); fi

command -v jq >/dev/null 2>&1 || exit 0
[ -n "$INPUT" ] || exit 0
[ -f "$SCRIPT_DIR/config.sh" ] && [ -f "$SCRIPT_DIR/lib-index-match.sh" ] || exit 0

# --- Config, via the config.sh-filled cache ---------------------------------
# Location expression identical to config.sh's first assignment; with no file
# there config.sh reports KT_CONFIGURED=false, which is this exit.
_pcc_cfg="${KT_CONFIG:-$HOME/.gemini/antigravity/aria-knowledge.local.md}"
[ -f "$_pcc_cfg" ] || exit 0

_pcc_nl='
'
# The cache is DATA, never shell code: it is read back with `read`, so nothing
# in it can execute even if the name is planted by someone else (in a shared
# /tmp, another user can pre-create it). Layout, one value per line:
#   aria-prompt-config 1 · <key> · KT_CONFIGURED · KT_CONFIG_ERROR ·
#   KT_KNOWLEDGE_FOLDER · KT_ACTIVE_SURFACING · KT_PROJECTS_ENABLED ·
#   KT_PROJECTS_LIST · end
# A value is used only after the header, the key and the end sentinel all
# match. A symlink is refused before the ownership test, which follows links.
# A key or value holding a newline cannot be stored this way and is simply not
# cached (a miss every call: correct, only slower).
_pcc_hdr="aria-prompt-config 1"
_pcc_cache="${KT_SURFACE_CACHE_DIR:-${TMPDIR:-/tmp}}/aria-prompt-config.cache"
_pcc_key=$(cksum "$_pcc_cfg" "$SCRIPT_DIR/config.sh" 2>/dev/null) || _pcc_key=""
# cksum prints one line per file; join the two into one line.
_pcc_k2=${_pcc_key#*"$_pcc_nl"}
case $_pcc_k2 in
  *"$_pcc_nl"*|"$_pcc_key") _pcc_key="" ;;
  *) _pcc_key="${_pcc_key%%"$_pcc_nl"*} | $_pcc_k2" ;;
esac
_pcc_hit=0
if [ -n "$_pcc_key" ] && [ ! -L "$_pcc_cache" ] && [ -f "$_pcc_cache" ] && [ -O "$_pcc_cache" ] 2>/dev/null; then
  if { IFS= read -r _pcc_h && IFS= read -r _pcc_k \
       && IFS= read -r _pcc_v1 && IFS= read -r _pcc_v2 && IFS= read -r _pcc_v3 \
       && IFS= read -r _pcc_v4 && IFS= read -r _pcc_v5 && IFS= read -r _pcc_v6 \
       && IFS= read -r _pcc_end; } < "$_pcc_cache" 2>/dev/null \
     && [ "$_pcc_h" = "$_pcc_hdr" ] && [ "$_pcc_k" = "$_pcc_key" ] && [ "$_pcc_end" = "end" ]; then
    KT_CONFIGURED=$_pcc_v1; KT_CONFIG_ERROR=$_pcc_v2; KT_KNOWLEDGE_FOLDER=$_pcc_v3
    KT_ACTIVE_SURFACING=$_pcc_v4; KT_PROJECTS_ENABLED=$_pcc_v5; KT_PROJECTS_LIST=$_pcc_v6
    _pcc_hit=1
  fi
fi
if [ "$_pcc_hit" -eq 0 ]; then
  . "$SCRIPT_DIR/config.sh" >/dev/null 2>&1
  # Cache only when config.sh read the file this key was computed for, and
  # only values that fit on one line each.
  case "$_pcc_key$KT_CONFIGURED$KT_CONFIG_ERROR$KT_KNOWLEDGE_FOLDER$KT_ACTIVE_SURFACING$KT_PROJECTS_ENABLED$KT_PROJECTS_LIST" in
    *"$_pcc_nl"*) _pcc_key="" ;;
  esac
  if [ -n "$_pcc_key" ] && [ "$KT_CONFIG" = "$_pcc_cfg" ]; then
    # Temp file in the cache's own dir, then mv: rename replaces the directory
    # entry (a planted link included) and a reader never sees half a file.
    _pcc_tmp=$(mktemp "${_pcc_cache%/*}/.aria-prompt-config.XXXXXX" 2>/dev/null) || _pcc_tmp=""
    if [ -n "$_pcc_tmp" ]; then
      if printf '%s\n' "$_pcc_hdr" "$_pcc_key" "$KT_CONFIGURED" "$KT_CONFIG_ERROR" \
           "$KT_KNOWLEDGE_FOLDER" "$KT_ACTIVE_SURFACING" "$KT_PROJECTS_ENABLED" \
           "$KT_PROJECTS_LIST" end > "$_pcc_tmp" 2>/dev/null \
         && mv -f "$_pcc_tmp" "$_pcc_cache" 2>/dev/null; then :
      else rm -f "$_pcc_tmp" 2>/dev/null; fi
    fi
  fi
fi

[ "$KT_CONFIGURED" = "true" ] && [ -z "$KT_CONFIG_ERROR" ] || exit 0
[ "$KT_ACTIVE_SURFACING" = "true" ] || exit 0
[ -f "$KT_KNOWLEDGE_FOLDER/index.md" ] || exit 0

# --- Input: session id + the user's own words --------------------------------
# One jq call: line 1 is the session id (reduced to a filename-safe charset —
# it names the ledger file), the rest is the prompt with pasted blocks removed.
# Not JSON, not an object, or no jq output => exit.
_pcc_parsed=$(jq -r '
  def scan($p):
    if $p then
      (if test("</pasted_content") then sub("^.*?</pasted_content"; "") | scan(false) else true end)
    else
      (if test("<pasted_content") then sub("^.*?<pasted_content"; "") | scan(true) else false end)
    end;
  ((.session_id // "") | tostring | gsub("[^A-Za-z0-9._-]"; "")),
  ((.prompt // "") | tostring | split("\n")
    | reduce .[] as $l ({p: false, k: []};
        .p as $p
        | if $p or ($l | test("<pasted_content")) then .p = ($l | scan($p))
          else .k += [$l] end)
    | .k | join("\n"))
' 2>/dev/null <<PCC_INPUT
$INPUT
PCC_INPUT
) || exit 0

_pcc_sid=${_pcc_parsed%%"$_pcc_nl"*}
_pcc_text=""
case $_pcc_parsed in *"$_pcc_nl"*) _pcc_text=${_pcc_parsed#*"$_pcc_nl"} ;; esac
[ -n "$_pcc_sid" ] || exit 0
[ -n "$_pcc_text" ] || exit 0

# --- Rank, then drop what this session has already seen ---------------------
. "$SCRIPT_DIR/lib-index-match.sh"
kt_index_match "$_pcc_text" 2>/dev/null
LEDGER="/tmp/aria-active-${_pcc_sid}"
if [ "${KT_MATCH_COUNT:-0}" -gt 0 ] 2>/dev/null; then
  kt_match_filter_ledger "$LEDGER" 2>/dev/null
fi
if ! [ "${KT_MATCH_COUNT:-0}" -gt 0 ] 2>/dev/null || [ ! -f "$KT_MATCH_FILES_TMP" ]; then
  kt_match_cleanup
  exit 0
fi

# --- Emit paths only ----------------------------------------------------------
_pcc_list=""; _pcc_n=0; _pcc_cut=0
while IFS= read -r _pcc_line || [ -n "$_pcc_line" ]; do
  _pcc_p=${_pcc_line%% — *}
  [ -n "$_pcc_p" ] || continue
  case $_pcc_p in /*) ;; *) _pcc_p="$KT_KNOWLEDGE_FOLDER/$_pcc_p" ;; esac
  _pcc_try="$_pcc_list$_pcc_nl- $_pcc_p"
  if [ "${#_pcc_try}" -gt 9000 ]; then _pcc_cut=1; break; fi
  _pcc_list=$_pcc_try; _pcc_n=$((_pcc_n + 1))
done < "$KT_MATCH_FILES_TMP"
if [ "$_pcc_n" -eq 0 ]; then kt_match_cleanup; exit 0; fi
# Record only what is injected (the ledger records every line of the file).
if [ "$_pcc_cut" -eq 1 ]; then
  head -n "$_pcc_n" "$KT_MATCH_FILES_TMP" > "$KT_MATCH_FILES_TMP.cut" 2>/dev/null \
    && mv -f "$KT_MATCH_FILES_TMP.cut" "$KT_MATCH_FILES_TMP" 2>/dev/null
fi

_pcc_ctx="ARIA ACTIVE — ${_pcc_n} knowledge file(s) for this task (tags: ${KT_MATCH_TAGS}). Read them before answering and say in one line which you used and why:${_pcc_list}"
_pcc_out=$(jq -cn --arg c "$_pcc_ctx" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}' 2>/dev/null) \
  || { kt_match_cleanup; exit 0; }
printf '%s\n' "$_pcc_out"
kt_match_record_ledger "$LEDGER" 2>/dev/null
kt_match_cleanup
exit 0
