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
# <conv>/<gen> are conversation_id/generation_id reduced by kt_ps_sanitize_id to
# [A-Za-z0-9._-]; `=` cannot occur in either, so "<conv>=" names one conversation exactly.
# A new prompt replaces the conversation's older pair (that generation is over: Cursor
# changes generation_id with every user message), and pairs older than 24 h are pruned
# for every conversation (gate-2 G2).
#
# Output: ALWAYS exactly {"continue":true}, printed first with plain printf so that no
# later failure — no jq, malformed or empty stdin, a missing lib, an invalid config —
# can block the user's prompt. Failures go to the debug log
# ${KT_SURFACE_CACHE_DIR:-${TMPDIR:-/tmp}}/aria-surface-hook.log (spec C3); every capture
# also logs the Cursor version it ran under (spec C2), so a host change is diagnosable.

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

# Same location expressions as config.sh's first two assignments (repo-relative config),
# set here so the lib's config cache can key on the file without sourcing config.sh.
KT_ROOT="${KT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
KT_CONFIG="${KT_CONFIG:-$KT_ROOT/.cursor/aria-knowledge.local.md}"

# --- Input: one jq call. Lines 1-3 are the ids and the version, each kept to one line;
# the rest is the prompt plus a closing "." — $( ) strips trailing newlines, and without
# the sentinel an empty version + empty prompt would shift the framing by a line.
# Not JSON, or not an object => jq fails => logged, done.
_pcc_nl='
'
_pcc_parsed=$(jq -r '
  if type != "object" then error("not an object") else . end
  | ((.conversation_id // "") | tostring | gsub("[^A-Za-z0-9._-]"; "")),
    ((.generation_id // "") | tostring | gsub("[^A-Za-z0-9._-]"; "")),
    ((.cursor_version // "") | tostring | gsub("[^A-Za-z0-9._+-]"; "") | .[0:40]),
    (((.prompt // "") | tostring) + ".")
' 2>/dev/null <<PCC_INPUT
$INPUT
PCC_INPUT
) || { kt_ps_log cursor input not-a-json-object; exit 0; }
_pcc_parsed=${_pcc_parsed%.}

_pcc_conv_raw=${_pcc_parsed%%"$_pcc_nl"*};  _pcc_rest=${_pcc_parsed#*"$_pcc_nl"}
_pcc_gen_raw=${_pcc_rest%%"$_pcc_nl"*};     _pcc_rest=${_pcc_rest#*"$_pcc_nl"}
_pcc_ver=${_pcc_rest%%"$_pcc_nl"*}
_pcc_prompt=""
case $_pcc_rest in *"$_pcc_nl"*) _pcc_prompt=${_pcc_rest#*"$_pcc_nl"} ;; esac

kt_ps_log cursor capture "cursor_version=${_pcc_ver:-unknown}"

# The ids name files. jq above already reduced them to kt_ps_sanitize_id's charset
# ([A-Za-z0-9._-]; same result, without two more processes on a hook that blocks the send).
_pcc_conv=$_pcc_conv_raw
_pcc_gen=$_pcc_gen_raw
[ -n "$_pcc_conv" ] || { kt_ps_log cursor input no-conversation-id; exit 0; }
[ -n "$_pcc_gen" ] || { kt_ps_log cursor input no-generation-id; exit 0; }

_pcc_dir=${KT_SURFACE_CACHE_DIR:-${TMPDIR:-/tmp}}
_pcc_base="$_pcc_dir/aria-cursor-pending-${_pcc_conv}=${_pcc_gen}"

# --- G2: this conversation's older pair goes (its generation can no longer receive a
# postToolUse); any pair older than 24 h goes. rm on a symlink removes the link only, and
# find is limited to this user's files.
for _pcc_f in "$_pcc_dir/aria-cursor-pending-${_pcc_conv}="*; do
  { [ -e "$_pcc_f" ] || [ -L "$_pcc_f" ]; } && rm -f "$_pcc_f" 2>/dev/null
done
find "$_pcc_dir" -maxdepth 1 -name 'aria-cursor-pending-*' -user "${USER:-$(id -u)}" -mmin +1440 \
  -exec rm -f {} + 2>/dev/null

# --- Rank (shared core). The user's own words only: pasted blocks removed.
_pcc_text=$(printf '%s' "$_pcc_prompt" | kt_ps_strip_pasted)
[ -n "$_pcc_text" ] || exit 0
kt_ps_surface "$_pcc_text" "/tmp/aria-active-${_pcc_conv}" >/dev/null
[ -n "$KT_PS_TEXT" ] || exit 0

# --- Store the pending pair: temp file in the same dir, then mv (a reader never sees half
# a file, and rename replaces a planted link instead of following it). Paths first, so a
# text file never exists without its paths file.
_pcc_write() { # DEST CONTENT
  _pcc_tmp=$(mktemp "$_pcc_dir/.aria-cursor-pending.XXXXXX" 2>/dev/null) || return 1
  if printf '%s\n' "$2" > "$_pcc_tmp" 2>/dev/null && mv -f "$_pcc_tmp" "$1" 2>/dev/null; then
    return 0
  fi
  rm -f "$_pcc_tmp" 2>/dev/null
  return 1
}
if ! { _pcc_write "$_pcc_base.paths" "$KT_PS_PENDING" && _pcc_write "$_pcc_base.text" "$KT_PS_TEXT"; }; then
  rm -f "$_pcc_base.paths" "$_pcc_base.text" 2>/dev/null
  kt_ps_log cursor capture write-failed
fi
exit 0
