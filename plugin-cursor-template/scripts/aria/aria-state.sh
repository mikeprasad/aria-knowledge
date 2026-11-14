#!/bin/sh
# aria-state.sh — name a file inside the private per-user state directory (2.58.0).
#
#   aria-state.sh path <name>
#   aria-state.sh key <id>
#
# path: prints "<state dir>/<name>" and exits 0. When there is no usable state directory it prints
# "aria-state: <reason>" to stderr and exits 1 (reasons: not created, not a directory, is a link,
# not owned by you, mode not 700, has an ACL, permissions not verifiable); a name that is empty,
# ".", ".." or contains "/" gives
# "aria-state: invalid name", exit 1.
# key: the session-id rule the hooks key their state by (kt_session_key_check). Prints the id and
# exits 0 when it is accepted ([A-Za-z0-9._-]+, used unchanged); otherwise prints
# "aria-state: session id not accepted (<why>)" to stderr and exits 1, so a skill never names a
# file the hooks will not read. It does not need the state directory.
# Any other usage: a usage line on stderr, exit 2.
# A missing lib-state-key.sh beside it: "aria-state: lib-state-key.sh missing", exit 1.
#
# Skills use it to write state where the hooks read it, never a guessed temp path. The location
# rule lives in lib-state-key.sh beside this script.

case $0 in */*) _aria_state_here=${0%/*} ;; *) _aria_state_here=. ;; esac
if [ -f "$_aria_state_here/lib-state-key.sh" ]; then
  . "$_aria_state_here/lib-state-key.sh"
else
  echo 'aria-state: lib-state-key.sh missing' >&2
  exit 1
fi

if [ "$#" -eq 2 ] && [ "$1" = key ]; then
  kt_session_key_check "$2" && { echo; exit 0; }
  case $? in
    1) echo 'aria-state: session id not accepted (empty)' >&2 ;;
    *) echo 'aria-state: session id not accepted (a character outside A-Za-z0-9._-)' >&2 ;;
  esac
  exit 1
fi
if [ "$#" -ne 2 ] || [ "$1" != path ]; then
  echo 'usage: aria-state.sh path <name> | aria-state.sh key <id>' >&2
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
