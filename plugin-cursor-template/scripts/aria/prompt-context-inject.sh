#!/bin/sh
# prompt-context-inject.sh — Cursor postToolUse hook for aria-knowledge (spec D3).
#
# Delivers what prompt-capture-check.sh ranked for this generation: if a pending pair
# exists for this conversation_id + generation_id, print {"additional_context": <text>}
# ONCE, then record its paths in the session ledger /tmp/aria-active-<conv> and delete
# the pair. Otherwise print {}. See prompt-capture-check.sh for the pending-pair layout.
#
# ⚠ Known limit (spec D3): Cursor offers no prompt-time injection, so delivery waits for
# the generation's first tool call — a prompt answered without any tool gets nothing.
#
# Once per generation, even with parallel tool calls: the pair is CLAIMED by renaming its
# text file to a name only this process knows. rename is atomic, so exactly one hook
# wins; every other one finds no text file and prints {}.
#
# The ledger records only what was delivered (lib-prompt-surface.sh, "The ledger
# contract"): if the output cannot be printed, nothing is committed and the claim is put
# back for the next tool call — but only while its .paths still exists (a newer capture
# may have replaced the pair); otherwise the claim is deleted. Failures go to the debug
# log, never to stdout.
#
# Runs after EVERY tool call, so the common case — no pending pair anywhere — returns {}
# before jq or the lib are touched. ⚠ Any undelivered pending file (any conversation)
# moves every tool call onto the slow path (jq + lib, ~20 ms) until it is delivered,
# replaced, or pruned after 24 h.

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || { printf '{}\n'; exit 0; }

INPUT=""
if (exec 3<&0) 2>/dev/null; then INPUT=$(cat 2>/dev/null); fi

_pci_none() { printf '{}\n'; exit 0; }

_pci_dir=${KT_SURFACE_CACHE_DIR:-${TMPDIR:-/tmp}}
set -- "$_pci_dir"/aria-cursor-pending-*.text
[ -e "$1" ] || [ -L "$1" ] || _pci_none

# Without the lib there is no kt_ps_log either, so this one failure is logged inline, to the
# same debug log and in the same shape (a symlinked log is refused, as kt_ps_log does).
if [ ! -f "$SCRIPT_DIR/lib-prompt-surface.sh" ]; then
  _pci_lf="$_pci_dir/aria-surface-hook.log"
  [ -L "$_pci_lf" ] || printf '%s cursor inject lib-missing\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown-time)" >> "$_pci_lf" 2>/dev/null
  _pci_none
fi
KT_PS_SCRIPT_DIR=$SCRIPT_DIR
KT_PS_RUNTIME=cursor
. "$SCRIPT_DIR/lib-prompt-surface.sh"

command -v jq >/dev/null 2>&1 || { kt_ps_log cursor inject jq-missing; _pci_none; }
[ -n "$INPUT" ] || { kt_ps_log cursor inject stdin-empty; _pci_none; }

_pci_nl='
'
_pci_parsed=$(jq -r '
  if type != "object" then error("not an object") else . end
  | ((.conversation_id // "") | tostring | gsub("[\r\n]"; "")),
    ((.generation_id // "") | tostring | gsub("[\r\n]"; "")),
    "."
' 2>/dev/null <<PCI_INPUT
$INPUT
PCI_INPUT
) || { kt_ps_log cursor inject not-a-json-object; _pci_none; }
_pci_conv=$(kt_ps_sanitize_id "${_pci_parsed%%"$_pci_nl"*}")
_pci_rest=${_pci_parsed#*"$_pci_nl"}
_pci_gen=$(kt_ps_sanitize_id "${_pci_rest%%"$_pci_nl"*}")
[ -n "$_pci_conv" ] && [ -n "$_pci_gen" ] || _pci_none

_pci_base="$_pci_dir/aria-cursor-pending-${_pci_conv}=${_pci_gen}"
_pci_claim="$_pci_base.text.claim.$$"
{ [ -e "$_pci_base.text" ] || [ -L "$_pci_base.text" ]; } || _pci_none
mv "$_pci_base.text" "$_pci_claim" 2>/dev/null || _pci_none   # another hook won the claim

# Undelivered: put the claim back for the next tool call only while its paths file still
# exists; a text restored without its paths could be delivered but never recorded.
_pci_restore() {
  if [ -e "$_pci_base.paths" ]; then
    mv -f "$_pci_claim" "$_pci_base.text" 2>/dev/null
  else
    rm -f "$_pci_claim" 2>/dev/null
  fi
}

# Only a regular file this user owns is delivered; a planted link or foreign file is not.
if [ -L "$_pci_claim" ] || [ ! -f "$_pci_claim" ] || [ ! -O "$_pci_claim" ]; then
  rm -f "$_pci_claim" 2>/dev/null
  kt_ps_log cursor inject pending-refused
  _pci_none
fi
_pci_text=$(cat "$_pci_claim" 2>/dev/null)
if [ -z "$_pci_text" ]; then
  rm -f "$_pci_claim" "$_pci_base.paths" 2>/dev/null
  kt_ps_log cursor inject pending-empty
  _pci_none
fi

_pci_out=$(jq -cn --arg c "$_pci_text" '{additional_context: $c}' 2>/dev/null) || {
  _pci_restore
  kt_ps_log cursor emit jq-failed
  _pci_none
}
# Written from a subshell: when a write fails, bash keeps it in the shell's own stdout
# buffer and flushes it into the next file that briefly lands on fd 1 (kt_ps_log's
# append, measured). A subshell's buffer dies with it.
if ! ( printf '%s\n' "$_pci_out" ) 2>/dev/null; then
  _pci_restore
  kt_ps_log cursor emit write-failed
  exit 0
fi

# Delivered: record exactly the paths that text named, then drop the pair.
kt_ps_commit_paths "/tmp/aria-active-${_pci_conv}" "$_pci_base.paths"
rm -f "$_pci_claim" "$_pci_base.paths" 2>/dev/null
exit 0
