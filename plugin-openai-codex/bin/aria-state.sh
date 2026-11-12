#!/bin/sh
# aria-state.sh — name a file inside the private per-user state directory (2.58.0).
#
#   aria-state.sh path <name>
#
# Prints "<state dir>/<name>" and exits 0. When there is no usable state directory it prints
# "aria-state: <reason>" to stderr and exits 1 (reasons: not created, not a directory, is a link,
# not owned by you, mode not 700, has an ACL); a name that is empty, ".", ".." or contains "/" gives
# "aria-state: invalid name", exit 1. Any other usage: a usage line on stderr, exit 2.
#
# Skills use it to write state where the hooks read it, never a guessed temp path. The location
# rule lives in lib-state-key.sh beside this script.

case $0 in */*) _aria_state_here=${0%/*} ;; *) _aria_state_here=. ;; esac
. "$_aria_state_here/lib-state-key.sh"

if [ "$#" -ne 2 ] || [ "$1" != path ]; then
  echo 'usage: aria-state.sh path <name>' >&2
  exit 2
fi

if ! kt_state_resolve; then
  printf 'aria-state: %s\n' "$KT_STATE_REASON" >&2
  exit 1
fi
if ! kt_state_path "$2"; then
  echo 'aria-state: invalid name' >&2
  exit 1
fi
exit 0
