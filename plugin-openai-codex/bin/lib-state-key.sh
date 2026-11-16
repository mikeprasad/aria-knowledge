#!/bin/sh
# lib-state-key.sh — the per-agent suffix for session-keyed hook state (v2.54.1).
#
# A subagent's hooks receive the PARENT's session_id (measured 2026-09-24), so any
# state file keyed on session_id alone is shared between a session and every
# subagent it spawns. For a DENIAL COUNTER that is a defect: three denials inside a
# subagent open the parent's breaker and switch its enforcement off. Consumers append
#   kt_agent_suffix "$INPUT"
# to the key they already build, so every main-thread key is byte-identical to before.
#
# Output: ".agent-<agent_id sanitised to A-Za-z0-9._->", or empty when the input has
# no agent_id (the main thread). Sanitising removes "/" so an id can never address a
# path; the recorder (pre-bash-r22-carrier.sh) applies the same set in Python, and
# tests/repros/r22-carrier-side-channel.sh C12 fails if the two ever disagree.
#
# Deliberately NOT for session-level FACTS a subagent should inherit — the preflight
# "ran this session" marker and the external-fetch cooldown stay session-keyed.
#
# POSIX sh: every consumer is #!/bin/sh.

kt_agent_suffix() {
  # Fast path: no agent_id key at all -> main thread, no python spawn.
  case "$1" in *'"agent_id"'*) ;; *) return 0 ;; esac
  _kt_aid=$(printf '%s' "$1" | python3 -c 'import json, sys
try:
    print(json.load(sys.stdin).get("agent_id") or "")
except Exception:
    print("")' 2>/dev/null | tr -cd 'A-Za-z0-9._-')
  [ -n "$_kt_aid" ] && printf '.agent-%s' "$_kt_aid"
  return 0
}

# --- The private per-user state directory (2.58.0) ---------------------------------------------
# Every hook state name lives in ONE directory only this user can write, so a name another local
# user plants in a shared temp dir can never be read or written through:
#   <base>/aria-knowledge-<uid>, base = the first SET, NON-EMPTY of KT_STATE_BASE (tests only),
#   XDG_RUNTIME_DIR, TMPDIR, (Darwin) getconf DARWIN_USER_TEMP_DIR, /tmp — trailing "/" stripped.
# Created mode 700 if absent, then checked once: not a link, a directory, owned by us, mode
# exactly 700 and no ACL. Any failure refuses — and NEVER tries the next base: falling through
# would let whoever breaks the first choice pick our directory.
#
#   kt_state_resolve   sets KT_STATE_DIR (path or empty) and KT_STATE_REASON (empty, or one of
#                      "not created", "not a directory", "is a link", "not owned by you",
#                      "mode not 700", "has an ACL", "permissions not verifiable"); returns
#                      0/1. Runs in the caller's shell (no subshell).
#   kt_state_dir       kt_state_resolve, then prints the directory; exit 1 and silent on failure.
#   kt_state_path N    prints "$KT_STATE_DIR/N"; exit 1, nothing printed, when no directory was
#                      resolved or N is empty, ".", ".." or contains "/".
#   kt_state_base      prints the chosen base (no mkdir; uname/getconf run only when the three
#                      variables are unset or empty).
# The Codex hook (Python) implements the same contract as aria_state_*; a cross-port test pins them.
#
# An ACL can grant access the mode bits do not show, so it is refused as "has an ACL". GNU and
# BSD ls print "+" after the mode for an ACL; macOS prints "@" instead when the directory also has
# an extended attribute (a fresh directory often does), hiding the "+". So the one ls read is
# `ls -lden`, which on macOS prints one extra line per ACL entry; where -e is unknown it falls back
# to `ls -ldn`. An "@" it could not check, or an ls read that fails, is refused as "permissions not
# verifiable" — never "mode not 700", which would be false for a 0700 dir and invite a useless
# chmod. A "." (SELinux context) is accepted.
#
# Resolution is per process: an inherited KT_STATE_DIR is never trusted.
KT_STATE_DIR=
KT_STATE_REASON=
_kt_nl='
'

_kt_state_base_set() {
  if [ -n "${KT_STATE_BASE:-}" ]; then _kt_sb=$KT_STATE_BASE
  elif [ -n "${XDG_RUNTIME_DIR:-}" ]; then _kt_sb=$XDG_RUNTIME_DIR
  elif [ -n "${TMPDIR:-}" ]; then _kt_sb=$TMPDIR
  else
    _kt_sb=
    if [ "$(uname -s 2>/dev/null)" = Darwin ]; then
      _kt_sb=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)
    fi
    [ -n "$_kt_sb" ] || _kt_sb=/tmp
  fi
  while :; do
    case $_kt_sb in */) _kt_sb=${_kt_sb%/} ;; *) break ;; esac
  done
}

kt_state_base() {
  _kt_state_base_set
  printf '%s\n' "$_kt_sb"
}

kt_state_resolve() {
  KT_STATE_DIR=
  KT_STATE_REASON=
  _kt_uid=$(id -u 2>/dev/null)
  if [ -z "$_kt_uid" ]; then KT_STATE_REASON='not created'; return 1; fi
  _kt_state_base_set
  _kt_d="$_kt_sb/aria-knowledge-$_kt_uid"
  if [ ! -e "$_kt_d" ] && [ ! -L "$_kt_d" ]; then
    mkdir -m 700 "$_kt_d" 2>/dev/null   # failure (a racing creator, a read-only parent) is re-checked below
  fi
  if [ -L "$_kt_d" ]; then KT_STATE_REASON='is a link'; return 1; fi
  if [ ! -e "$_kt_d" ]; then KT_STATE_REASON='not created'; return 1; fi
  if [ ! -d "$_kt_d" ]; then KT_STATE_REASON='not a directory'; return 1; fi
  # One ls: `-e` (macOS) adds one line per ACL entry; where -e is unknown (GNU ls) fall back to -ldn,
  # and there an "@" mode is refused because its ACL could not be read.
  _kt_e=1
  _kt_l=$(ls -lden "$_kt_d" 2>/dev/null) || { _kt_e=; _kt_l=$(ls -ldn "$_kt_d" 2>/dev/null); }
  if [ -z "$_kt_l" ]; then KT_STATE_REASON='permissions not verifiable'; return 1; fi
  case $_kt_l in *"$_kt_nl"*) _kt_acl=1 ;; *) _kt_acl= ;; esac
  _kt_l=${_kt_l%%"$_kt_nl"*}
  # Split the ls line on spaces (runs collapse) without globbing it; restore the caller's IFS and -f.
  case $- in *f*) _kt_gf= ;; *) _kt_gf=1; set -f ;; esac
  _kt_ifs_set=${IFS+x}; _kt_ifs=${IFS-}
  IFS=' '
  set -- $_kt_l
  if [ -n "$_kt_ifs_set" ]; then IFS=$_kt_ifs; else unset IFS; fi
  if [ -n "$_kt_gf" ]; then set +f; fi
  if [ "${3-}" != "$_kt_uid" ]; then KT_STATE_REASON='not owned by you'; return 1; fi
  case ${1-} in
    drwx------|drwx------.) ;;
    drwx------@) [ -n "$_kt_e" ] || { KT_STATE_REASON='permissions not verifiable'; return 1; } ;;
    drwx------+|drwx------.+) KT_STATE_REASON='has an ACL'; return 1 ;;
    *) KT_STATE_REASON='mode not 700'; return 1 ;;
  esac
  if [ -n "$_kt_acl" ]; then KT_STATE_REASON='has an ACL'; return 1; fi
  KT_STATE_DIR=$_kt_d
  return 0
}

kt_state_dir() {
  kt_state_resolve || return 1
  printf '%s\n' "$KT_STATE_DIR"
}

kt_state_path() {
  [ -n "${KT_STATE_DIR:-}" ] || return 1
  case ${1-} in ''|.|..|*/*) return 1 ;; esac
  printf '%s/%s\n' "$KT_STATE_DIR" "$1"
}

# --- The session key: one accept-set, never rewritten (2.58.0 fix round 1) -----------------------------
# Every hook in every port that names a state file after a session or conversation id derives it here,
# so the ledger a session-start line STATES is the ledger every writer WRITES. An id is accepted only
# when it is non-empty and every character is in [A-Za-z0-9._-]; it is then used UNCHANGED. Anything
# else yields NO key, so that family keeps no state for the session (spec D3) — never a stripped id:
# stripping is not injective (`a+b` and `ab` would share one ledger across two sessions). The Codex hook
# (Python, codex-hook.py session_key) applies the identical rule; a cross-port test pins them.
#
#   kt_session_key_check ID      prints ID and returns 0 when it is accepted; prints nothing and
#                                returns 1 when ID is empty, 2 when it carries any other character.
#   kt_session_key JSON FIELD... the string value of the FIRST field present with a non-empty value,
#                                read whitespace-tolerantly ("f":"v" and "f": "v" alike, as jq reads
#                                them), then kt_session_key_check: 0 printed, 1 no field present,
#                                2 present but rejected — it never falls back past a rejected field.
#                                A value holding a JSON escape is rejected (its backslash is not in
#                                the set); field names are literals, never caller data.
kt_session_key_check() {
  case ${1-} in
    '') return 1 ;;
    *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*) return 2 ;;
  esac
  printf '%s' "$1"
}

kt_session_key() {
  _kt_sk_j=${1-}
  [ "$#" -gt 0 ] && shift
  for _kt_sk_f in "$@"; do
    _kt_sk_v=$(printf '%s' "$_kt_sk_j" | grep -oE "\"$_kt_sk_f\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 \
      | sed 's/^"[^"]*"[[:space:]]*:[[:space:]]*"//;s/"$//')
    if [ -n "$_kt_sk_v" ]; then
      kt_session_key_check "$_kt_sk_v"
      return $?
    fi
  done
  return 1
}

# --- Split retention for the state dir (2.58.0 spec D10) ------------------------------------------
# kt_state_sweep removes aged FILES from the top level of the resolved state dir, and it is the ONE
# place that find is written (every sweeping hook calls it; a census fails on an inline copy).
#   PROOF names keep 30 days (-mmin +43200): aria-preflight-* (this covers aria-preflight-skipped-* and
#     aria-preflight-repo-*) except aria-preflight-denies-*, aria-r22-bypass-*, aria-active-*,
#     aria-ag-surfaced-*. They are the evidence a gate ran or was bypassed; a 24 h sweep erased it.
#   CHURN names (everything else, aria-preflight-denies-* and aria-r22-denies-* included) go at 24 h
#     (-mmin +1440): cooldowns, breakers, carriers, caches, a killed writer's create temps.
# Does nothing (returns 0) when KT_STATE_DIR is empty — the dir did not resolve. Only regular files
# (-type f), top level only, no link-following (never -L/-H/-follow): a directory or a link is kept.
# ⛔ OPERATOR PRECEDENCE decides correctness: find binds -a tighter than -o, and an implicit -a joins
# the age tests to the name tests. The ungrouped form deletes a 2-day proof file, a FRESH file and
# matches a directory (measured 2026-11-15). Keep the grouping exactly as written.
kt_state_sweep() {
  [ -n "${KT_STATE_DIR:-}" ] || return 0
  find "$KT_STATE_DIR/" -mindepth 1 -maxdepth 1 -type f \( \
    \( \( \( -name 'aria-preflight-*' ! -name 'aria-preflight-denies-*' \) -o -name 'aria-r22-bypass-*' \
         -o -name 'aria-active-*' -o -name 'aria-ag-surfaced-*' \) -mmin +43200 \) \
    -o \( ! \( \( -name 'aria-preflight-*' ! -name 'aria-preflight-denies-*' \) -o -name 'aria-r22-bypass-*' \
         -o -name 'aria-active-*' -o -name 'aria-ag-surfaced-*' \) -mmin +1440 \) \
  \) -exec rm -f {} + 2>/dev/null
  return 0
}
