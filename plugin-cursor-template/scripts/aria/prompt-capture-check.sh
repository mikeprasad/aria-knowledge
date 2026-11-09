#!/bin/sh
# prompt-capture-check.sh — Cursor beforeSubmitPrompt hook for aria-knowledge (spec D3).
#
# Cursor's beforeSubmitPrompt sees the prompt but cannot inject context (its output is
# only `continue` + `user_message`). So this hook RANKS the prompt in code and stores the
# result; prompt-context-inject.sh (postToolUse, which can inject) delivers it on the
# first tool call of the same generation. Nothing the model composes reaches a shell.
#
# This file is only the Cursor I/O ADAPTER. Ranking, the ledger filter, the injection
# text and its 10,000-char bound live in lib-prompt-surface.sh (byte-identical with the
# Claude Code and Antigravity copies). Read its header for the ledger contract: ranking is
# not delivery, so this hook records NOTHING in the ledger — the inject hook commits the
# paths only after Cursor has been handed the text.
#
# Pending pair, one per conversation (the newest generation's):
#   ${KT_SURFACE_CACHE_DIR:-${TMPDIR:-/tmp}}/aria-cursor-pending-<conv>=<gen>.text  injection text
#   …/aria-cursor-pending-<conv>=<gen>.paths  knowledge-folder-relative paths it names
# <conv>/<gen> are conversation_id/generation_id reduced to kt_ps_sanitize_id's charset
# [A-Za-z0-9._-]; `=` cannot occur in either, so "<conv>=" names one conversation exactly.
# A new prompt replaces the conversation's older pair (that generation is over: Cursor
# changes generation_id with every user message). Pairs older than 24 h are pruned for
# every conversation (gate-2 G2), at most once an hour, by a capture that stores a pair —
# only such a capture creates pending files, so none can pile up in between.
#
# Repo root: workspace_roots[0] from the hook input (a common field on every Cursor hook)
# when it is an absolute directory holding .cursor/; otherwise `git rev-parse
# --show-toplevel`, as config.sh does. Cursor does not specify a hook's working directory.
#
# Output: ALWAYS exactly {"continue":true}, printed first so that no later failure — no
# jq, malformed or empty stdin, a missing lib, an invalid config — can block the user's
# prompt. Failures go to the debug log
# ${KT_SURFACE_CACHE_DIR:-${TMPDIR:-/tmp}}/aria-surface-hook.log (spec C3), which also
# records the Cursor version each time it changes (spec C2), so a host change is
# diagnosable without a log line per prompt.
#
# Latency (spec C4, this hook blocks the send): no process is spent on anything but the
# ranking in the common case — root from the input, version and prune checks by shell
# tests on small state files.

# Written from a subshell: if the write fails (stdout closed, reader gone), bash keeps it
# in the shell's stdout buffer and flushes it into the next file opened on fd 1 — a
# pending file or the debug log (measured). A subshell's buffer dies with it.
( printf '{"continue":true}\n' ) 2>/dev/null

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || exit 0

# Drain stdin before any early exit (the host writes the payload into a pipe). Read only
# when fd 0 is OPEN: with it closed, cat would read the $( ) pipe's own output forever.
INPUT=""
if (exec 3<&0) 2>/dev/null; then INPUT=$(cat 2>/dev/null); fi

[ -f "$SCRIPT_DIR/lib-prompt-surface.sh" ] || exit 0
KT_PS_SCRIPT_DIR=$SCRIPT_DIR
KT_PS_RUNTIME=cursor
. "$SCRIPT_DIR/lib-prompt-surface.sh"

command -v jq >/dev/null 2>&1 || { kt_ps_log cursor input jq-missing; exit 0; }
[ -n "$INPUT" ] || { kt_ps_log cursor input stdin-empty; exit 0; }

_pcc_dir=${KT_SURFACE_CACHE_DIR:-${TMPDIR:-/tmp}}

# DEST CONTENT — temp file in the same dir, then mv: a reader never sees half a file, and
# rename replaces a planted link instead of following it.
_pcc_write() {
  _pcc_tmp=$(mktemp "$_pcc_dir/.aria-cursor-pending.XXXXXX" 2>/dev/null) || return 1
  if printf '%s\n' "$2" > "$_pcc_tmp" 2>/dev/null && mv -f "$_pcc_tmp" "$1" 2>/dev/null; then
    return 0
  fi
  rm -f "$_pcc_tmp" 2>/dev/null
  return 1
}

# --- Input: one jq call. Lines 1-4 are the ids, the version and workspace_roots[0], each
# kept to one line; the rest is the prompt plus a closing "." — $( ) strips trailing
# newlines, and without the sentinel empty trailing fields would shift the framing.
# Not JSON, or not an object => jq fails => logged, done.
_pcc_nl='
'
_pcc_parsed=$(jq -r '
  if type != "object" then error("not an object") else . end
  | ((.conversation_id // "") | tostring | gsub("[^A-Za-z0-9._-]"; "")),
    ((.generation_id // "") | tostring | gsub("[^A-Za-z0-9._-]"; "")),
    ((.cursor_version // "") | tostring | gsub("[^A-Za-z0-9._+-]"; "") | .[0:40]),
    ((.workspace_roots // []) | (if type == "array" then (.[0] // "") else "" end)
       | tostring | gsub("[\r\n]"; "")),
    (((.prompt // "") | tostring) + ".")
' 2>/dev/null <<PCC_INPUT
$INPUT
PCC_INPUT
) || { kt_ps_log cursor input not-a-json-object; exit 0; }
_pcc_parsed=${_pcc_parsed%.}

_pcc_conv=${_pcc_parsed%%"$_pcc_nl"*};   _pcc_rest=${_pcc_parsed#*"$_pcc_nl"}
_pcc_gen=${_pcc_rest%%"$_pcc_nl"*};      _pcc_rest=${_pcc_rest#*"$_pcc_nl"}
_pcc_ver=${_pcc_rest%%"$_pcc_nl"*};      _pcc_rest=${_pcc_rest#*"$_pcc_nl"}
_pcc_wroot=${_pcc_rest%%"$_pcc_nl"*}
_pcc_prompt=""
case $_pcc_rest in *"$_pcc_nl"*) _pcc_prompt=${_pcc_rest#*"$_pcc_nl"} ;; esac
_pcc_ver=${_pcc_ver:-unknown}

# --- C2: the Cursor version, logged when it differs from the last one logged. The state
# file is read only when it is a regular file of ours (never a planted link).
_pcc_vf="$_pcc_dir/aria-cursor-version.last"
_pcc_last=""
if [ -f "$_pcc_vf" ] && [ ! -L "$_pcc_vf" ] && [ -O "$_pcc_vf" ]; then
  IFS= read -r _pcc_last < "$_pcc_vf" 2>/dev/null || :
fi
if [ "$_pcc_ver" != "$_pcc_last" ]; then
  kt_ps_log cursor capture "cursor_version=$_pcc_ver"
  _pcc_write "$_pcc_vf" "$_pcc_ver" || :
fi

# The ids name files; jq above already reduced them to kt_ps_sanitize_id's charset.
[ -n "$_pcc_conv" ] || { kt_ps_log cursor input no-conversation-id; exit 0; }
[ -n "$_pcc_gen" ] || { kt_ps_log cursor input no-generation-id; exit 0; }

# --- Config location: the same expressions as config.sh's first two assignments (a
# repo-relative config), with the root taken from the input when it is valid. Set here so
# the lib's config cache can key on the file without sourcing config.sh.
if [ -z "${KT_ROOT:-}" ]; then
  case $_pcc_wroot in
    /*) [ -d "$_pcc_wroot/.cursor" ] && KT_ROOT=$_pcc_wroot ;;
  esac
  [ -n "${KT_ROOT:-}" ] || KT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
fi
KT_CONFIG="${KT_CONFIG:-$KT_ROOT/.cursor/aria-knowledge.local.md}"

_pcc_base="$_pcc_dir/aria-cursor-pending-${_pcc_conv}=${_pcc_gen}"

# --- G2, part 1: this conversation's older pair goes (its generation can no longer
# receive a postToolUse). rm on a symlink removes the link only.
for _pcc_f in "$_pcc_dir/aria-cursor-pending-${_pcc_conv}="*; do
  { [ -e "$_pcc_f" ] || [ -L "$_pcc_f" ]; } && rm -f "$_pcc_f" 2>/dev/null
done

# --- Rank (shared core). The user's own words only: pasted blocks removed.
_pcc_text=$(printf '%s' "$_pcc_prompt" | kt_ps_strip_pasted)
[ -n "$_pcc_text" ] || exit 0
kt_ps_surface "$_pcc_text" "/tmp/aria-active-${_pcc_conv}" >/dev/null
[ -n "$KT_PS_TEXT" ] || exit 0

# --- Store the pending pair. Paths first, so a text file never exists without its paths.
if ! { _pcc_write "$_pcc_base.paths" "$KT_PS_PENDING" && _pcc_write "$_pcc_base.text" "$KT_PS_TEXT"; }; then
  rm -f "$_pcc_base.paths" "$_pcc_base.text" 2>/dev/null
  kt_ps_log cursor capture write-failed
  exit 0
fi

# --- G2, part 2: pairs older than 24 h go, for any conversation, at most once an hour.
# The stamp's mtime is the time the next prune may run (set one hour ahead each time), and
# the .text just written carries the current time — so "due" is one shell test, no
# process. A missing, linked or foreign stamp counts as due. find is limited to our files.
_pcc_stamp="$_pcc_dir/aria-cursor-prune.stamp"
if [ ! -e "$_pcc_stamp" ] || [ -L "$_pcc_stamp" ] || [ ! -O "$_pcc_stamp" ] \
   || [ "$_pcc_base.text" -nt "$_pcc_stamp" ]; then
  find "$_pcc_dir" -maxdepth 1 -name 'aria-cursor-pending-*' -user "${USER:-$(id -u)}" -mmin +1440 \
    -exec rm -f {} + 2>/dev/null
  _pcc_next=$(date -v+1H +%Y%m%d%H%M.%S 2>/dev/null || date -d '+1 hour' +%Y%m%d%H%M.%S 2>/dev/null)
  if _pcc_write "$_pcc_stamp" "" && [ -n "$_pcc_next" ]; then
    touch -t "$_pcc_next" "$_pcc_stamp" 2>/dev/null
  fi
fi
exit 0
