#!/bin/sh
# state-dir-resolver.sh — 2.58.0: the private per-user state directory resolver.
#
# Every predictable-name hook state file moves into ONE directory only the user can write:
#   <first set, non-empty of KT_STATE_BASE, XDG_RUNTIME_DIR, TMPDIR, (Darwin) getconf
#    DARWIN_USER_TEMP_DIR, /tmp; trailing / stripped>/aria-knowledge-<uid>
# created mode 700 and checked once: not a link, a directory, ours, mode exactly 700, no ACL.
# Any failure refuses (prints nothing, exit 1) and NEVER tries the next base.
#
# Implementations under test: kt_state_* in lib-state-key.sh (4 byte-identical shell ports),
# aria-state.sh (the CLI, 4 copies), aria_state_* in the Codex hook (Python, parity arms).
#
# Every arm runs in its own scratch base under a mktemp root, with KT_STATE_BASE / TMPDIR /
# XDG_RUNTIME_DIR set explicitly, so no state directory is ever created in the user's real one. The
# scratch root itself is a unique mktemp dir under $TMPDIR, removed by the EXIT trap.
#
# Declared before running on the pre-resolver tree (7644150): every arm RED (functions and the
# CLI absent) except two GUARDS that are green by construction there: R_parity_sh_lib (the four
# lib copies were already byte-identical; its own mutation proves it can go red) and
# R_guard_tmpdir_untouched (nothing may escape into the guard TMPDIR). R_launch_count (added in
# fix round 3, a cost ratchet: process launches per resolve) is red there because the resolve fails;
# its own mutation proves it goes red on an extra launch. R_timing_report prints timings only and
# asserts just that every timed resolve exited 0.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
L="$REPO/plugin-claude-code/scripts/lib-state-key.sh"
CLI="$REPO/plugin-claude-code/scripts/aria-state.sh"
HOOKPY="$REPO/plugin-openai-codex/bin/codex-hook.py"
PASS=0; FAIL=0; SKIP=0
ok()   { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad()  { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
skip() { printf "SKIP  %s — %s\n" "$1" "$2"; SKIP=$((SKIP + 1)); }

_t=${TMPDIR:-/tmp}; _t=${_t%/}
ROOT=$(mktemp -d "$_t/state-dir-resolver.XXXXXX") || { echo "cannot make scratch root"; exit 1; }
trap 'chmod -R u+rwx "$ROOT" 2>/dev/null; rm -rf "$ROOT"' EXIT
GUARD="$ROOT/tmpdir-guard"; mkdir "$GUARD"   # TMPDIR for every child that is not testing TMPDIR
MYUID=$(id -u)
NAME="aria-knowledge-$MYUID"
IS_DARWIN=; [ "$(uname -s)" = Darwin ] && IS_DARWIN=1

# Run sh code ($2) with the lib as $1, under base $1-arg. XDG_RUNTIME_DIR unset, TMPDIR = GUARD.
in_base() { _ib=$1; shift; env -u XDG_RUNTIME_DIR KT_STATE_BASE="$_ib" TMPDIR="$GUARD" sh -c "$1" _ "$L"; }
# rc|printed|reason — kt_state_dir's exit and output, then kt_state_resolve's reason.
PROBE='. "$1"; out=$(kt_state_dir); rc=$?; kt_state_resolve; printf "%s|%s|%s" "$rc" "$out" "$KT_STATE_REASON"'
mode_of()  { ls -ldn "$1" 2>/dev/null | awk '{print $1}'; }
owner_of() { ls -ldn "$1" 2>/dev/null | awk '{print $3}'; }
# Exactly 700: drwx------ with at most a macOS xattr marker (@) or a Linux SELinux marker (.).
is700()    { case $(mode_of "$1") in drwx------|drwx------@|drwx------.) return 0;; esac; return 1; }
newbase()  { mkdir "$ROOT/$1" && printf '%s' "$ROOT/$1"; }

# --- R_fresh ------------------------------------------------------------------------------------
b=$(newbase fresh); r=$(in_base "$b" "$PROBE")
if [ "$r" = "0|$b/$NAME|" ] && is700 "$b/$NAME" && [ "$(owner_of "$b/$NAME")" = "$MYUID" ]; then
  ok R_fresh
else bad R_fresh "got '$r' mode $(mode_of "$b/$NAME") owner $(owner_of "$b/$NAME")"; fi

# --- R_link_at_dir: a symlink at the name to a perfect 0700 dir is still refused ----------------
mkdir -m 700 "$ROOT/link-target"; b=$(newbase link); ln -s "$ROOT/link-target" "$b/$NAME"
r=$(in_base "$b" "$PROBE")
[ "$r" = "1||is a link" ] && ok R_link_at_dir || bad R_link_at_dir "got '$r'"

# --- R_mode_755: refused, and never chmod-ed into acceptance -------------------------------------
b=$(newbase m755); mkdir -m 755 "$b/$NAME"
r=$(in_base "$b" "$PROBE")
case $(mode_of "$b/$NAME") in drwxr-xr-x*) m_ok=1;; *) m_ok=;; esac
if [ "$r" = "1||mode not 700" ] && [ -n "$m_ok" ]; then ok R_mode_755
else bad R_mode_755 "got '$r', mode now $(mode_of "$b/$NAME") (must stay 755)"; fi

# --- R_file_at_name -----------------------------------------------------------------------------
b=$(newbase file); : > "$b/$NAME"
r=$(in_base "$b" "$PROBE")
[ "$r" = "1||not a directory" ] && ok R_file_at_name || bad R_file_at_name "got '$r'"

# --- R_unwritable_parent ------------------------------------------------------------------------
if [ "$MYUID" = 0 ]; then
  skip R_unwritable_parent "running as root: mode 500 does not stop root"
else
  b=$(newbase ro); chmod 500 "$b"
  r=$(in_base "$b" "$PROBE"); chmod 700 "$b"
  [ "$r" = "1||not created" ] && ok R_unwritable_parent || bad R_unwritable_parent "got '$r'"
fi

# --- R_foreign_owner: a stub id says we are uid 99999; the dir we create is owned by our real uid
STUB="$ROOT/stub"; mkdir "$STUB"; printf '#!/bin/sh\nprintf "99999\\n"\n' > "$STUB/id"; chmod +x "$STUB/id"
b=$(newbase foreign)
r=$(env -u XDG_RUNTIME_DIR PATH="$STUB:$PATH" KT_STATE_BASE="$b" TMPDIR="$GUARD" sh -c "$PROBE" _ "$L")
if [ "$r" = "1||not owned by you" ] && [ -d "$b/aria-knowledge-99999" ]; then ok R_foreign_owner
else bad R_foreign_owner "got '$r'"; fi
# (Real foreign ownership needs a second uid: argued in spec AC3, not tested.)

# --- R_no_fallthrough: a broken first base never moves state to the next healthy base ------------
b=$(newbase nf); : > "$b/$NAME"
NFX="$ROOT/nf-xdg"; NFT="$ROOT/nf-tmp"; mkdir "$NFX" "$NFT"
r=$(env KT_STATE_BASE="$b" XDG_RUNTIME_DIR="$NFX" TMPDIR="$NFT" sh -c "$PROBE" _ "$L")
if [ "$r" = "1||not a directory" ] && [ -z "$(ls -A "$NFX")" ] && [ -z "$(ls -A "$NFT")" ]; then
  ok R_no_fallthrough
else bad R_no_fallthrough "got '$r'; xdg: $(ls -A "$NFX" | tr '\n' ' ') tmpdir: $(ls -A "$NFT" | tr '\n' ' ')"; fi

# --- R_base_order -------------------------------------------------------------------------------
B1=$(newbase bo1); B2=$(newbase bo2); B3=$(newbase bo3)
BASE='. "$1"; kt_state_base'
ra=$(env KT_STATE_BASE="$B1" XDG_RUNTIME_DIR="$B2" TMPDIR="$B3" sh -c "$BASE" _ "$L")
rb=$(env -u KT_STATE_BASE XDG_RUNTIME_DIR="$B2" TMPDIR="$B3" sh -c "$BASE" _ "$L")
rc_=$(env -u KT_STATE_BASE -u XDG_RUNTIME_DIR TMPDIR="$B3" sh -c "$BASE" _ "$L")
rd=$(env -u KT_STATE_BASE -u XDG_RUNTIME_DIR TMPDIR="$B3///" sh -c "$BASE" _ "$L")
rdd=$(env -u KT_STATE_BASE -u XDG_RUNTIME_DIR TMPDIR="$B3///" sh -c '. "$1"; kt_state_dir' _ "$L")
re=$(env KT_STATE_BASE= XDG_RUNTIME_DIR="$B2" TMPDIR="$B3" sh -c "$BASE" _ "$L")
case $rdd in *//*) dd_ok=;; "$B3/$NAME") dd_ok=1;; *) dd_ok=;; esac
if [ "$ra" = "$B1" ] && [ "$rb" = "$B2" ] && [ "$rc_" = "$B3" ] && [ "$rd" = "$B3" ] && [ -n "$dd_ok" ] && [ "$re" = "$B2" ]; then
  ok R_base_order
else bad R_base_order "a='$ra' b='$rb' c='$rc_' d='$rd' d-dir='$rdd' e='$re'"; fi

# --- R_base_tmpdir_unset (Review Focus 1): base only — never resolves into the real temp dir ------
if [ -n "$IS_DARWIN" ]; then
  want=$(getconf DARWIN_USER_TEMP_DIR); while :; do case $want in */) want=${want%/};; *) break;; esac; done
  got=$(env -u KT_STATE_BASE -u XDG_RUNTIME_DIR -u TMPDIR sh -c "$BASE" _ "$L")
  [ -n "$want" ] && [ "$got" = "$want" ] && ok R_base_tmpdir_unset || bad R_base_tmpdir_unset "got '$got' want '$want'"
else
  skip R_base_tmpdir_unset "not Darwin"
fi

# --- R_concurrent_create (RF2) ------------------------------------------------------------------
b=$(newbase conc); i=1
while [ $i -le 8 ]; do
  ( in_base "$b" '. "$1"; kt_state_dir' > "$ROOT/cc.out.$i"; echo $? > "$ROOT/cc.rc.$i" ) &
  i=$((i + 1))
done
wait
rcs=$(cat "$ROOT"/cc.rc.* | sort -u | tr '\n' ' '); outs=$(cat "$ROOT"/cc.out.* | sort -u)
if [ "$rcs" = "0 " ] && [ "$outs" = "$b/$NAME" ] && is700 "$b/$NAME"; then ok R_concurrent_create
else bad R_concurrent_create "rcs='$rcs' outs='$(printf '%s' "$outs" | tr '\n' ' ')' mode $(mode_of "$b/$NAME")"; fi

# --- R_recreate_after_delete (RF3) --------------------------------------------------------------
b=$(newbase recreate)
r1=$(in_base "$b" "$PROBE"); rm -rf "$b/$NAME"; r2=$(in_base "$b" "$PROBE")
if [ "$r1" = "0|$b/$NAME|" ] && [ "$r2" = "0|$b/$NAME|" ] && is700 "$b/$NAME"; then ok R_recreate_after_delete
else bad R_recreate_after_delete "first '$r1' second '$r2' mode $(mode_of "$b/$NAME")"; fi

# --- R_umask_000 / R_umask_077 (RF4) ------------------------------------------------------------
for um in 000 077; do
  b=$(newbase "um$um")
  r=$(in_base "$b" "umask $um; $PROBE")
  if [ "$r" = "0|$b/$NAME|" ] && is700 "$b/$NAME"; then ok "R_umask_$um"
  else bad "R_umask_$um" "got '$r' mode $(mode_of "$b/$NAME")"; fi
done

# --- R_name_with_slash_refused (RF5) ------------------------------------------------------------
b=$(newbase names)
r=$(in_base "$b" '. "$1"; kt_state_resolve || { printf "resolve-failed"; exit 0; }; d=$KT_STATE_DIR
for n in "a/../../x" ".." "." ""; do
  o=$(kt_state_path "$n"); rc=$?
  if [ "$rc" -ne 1 ] || [ -n "$o" ]; then printf "accepted:[%s]rc=%s:out=%s" "$n" "$rc" "$o"; exit 0; fi
done
o=$(kt_state_path aria-active-x); [ "$o" = "$d/aria-active-x" ] || { printf "good-name:%s" "$o"; exit 0; }
KT_STATE_DIR=; o=$(kt_state_path aria-active-x); rc=$?
[ "$rc" -eq 1 ] && [ -z "$o" ] || { printf "no-dir-accepted:%s" "$o"; exit 0; }
printf OK')
[ "$r" = OK ] && ok R_name_with_slash_refused || bad R_name_with_slash_refused "$r"

# --- R_source_resets: an inherited KT_STATE_DIR / KT_STATE_REASON is never trusted ---------------
r=$(env KT_STATE_DIR=/elsewhere KT_STATE_REASON=planted sh -c '. "$1"; printf "%s|%s" "$KT_STATE_DIR" "$KT_STATE_REASON"' _ "$L")
[ "$r" = "|" ] && ok R_source_resets || bad R_source_resets "got '$r'"

# --- R_cli --------------------------------------------------------------------------------------
cli() { _cb=$1; shift; env -u XDG_RUNTIME_DIR KT_STATE_BASE="$_cb" TMPDIR="$GUARD" sh "$CLI" "$@" 2>"$ROOT/cli.err"; }
b=$(newbase cli); bb=$(newbase clibroken); : > "$bb/$NAME"
o1=$(cli "$b" path aria-active-x); c1=$?; e1=$(cat "$ROOT/cli.err")
o2=$(cli "$bb" path aria-active-x); c2=$?; e2=$(cat "$ROOT/cli.err")
o3=$(cli "$b" path 'a/b'); c3=$?; e3=$(cat "$ROOT/cli.err")
o4=$(cli "$b"); c4=$?; e4=$(cat "$ROOT/cli.err")
if [ "$c1" = 0 ] && [ "$o1" = "$b/$NAME/aria-active-x" ] && [ -z "$e1" ] \
   && [ "$c2" = 1 ] && [ -z "$o2" ] && [ "$e2" = "aria-state: not a directory" ] \
   && [ "$c3" = 1 ] && [ -z "$o3" ] && [ "$e3" = "aria-state: invalid name" ] \
   && [ "$c4" = 2 ] && [ -z "$o4" ] && [ -n "$e4" ]; then
  ok R_cli
else bad R_cli "ok:$c1:'$o1':'$e1' broken:$c2:'$o2':'$e2' slash:$c3:'$o3':'$e3' noargs:$c4:'$o4'"; fi

# --- R_acl (G2-1): an ACL on the directory is refused, fail safe ---------------------------------
# macOS: `ls -ldn` shows "@" (not "+") when the dir also has an xattr, and a fresh mkdir under a
# sandboxed parent already carries one (measured 2026-11-12) — so the "+" alone is blind there.
b=$(newbase acl); mkdir -m 700 "$b/$NAME"
if [ -n "$IS_DARWIN" ]; then
  if chmod +a "everyone allow list" "$b/$NAME" 2>/dev/null; then
    r=$(in_base "$b" "$PROBE")
    [ "$r" = "1||has an ACL" ] && ok R_acl || bad R_acl "got '$r' ($(ls -lden "$b/$NAME" | tr '\n' ' '))"
  else skip R_acl "chmod +a refused on this filesystem"; fi
elif command -v setfacl >/dev/null 2>&1 && setfacl -m u:nobody:rx "$b/$NAME" 2>/dev/null; then
  r=$(in_base "$b" "$PROBE")
  [ "$r" = "1||has an ACL" ] && ok R_acl || bad R_acl "got '$r'"
else
  skip R_acl "no way to set an ACL here (reasoned: GNU/BSD ls print '+' after the mode)"
fi

# --- R_xattr_only_accepted: the positive half — an xattr (macOS "@") without an ACL is accepted --
if [ -n "$IS_DARWIN" ]; then
  b=$(newbase xattr); mkdir -m 700 "$b/$NAME"
  if xattr -w user.aria-probe 1 "$b/$NAME" 2>/dev/null; then
    r=$(in_base "$b" "$PROBE")
    [ "$r" = "0|$b/$NAME|" ] && ok R_xattr_only_accepted || bad R_xattr_only_accepted "got '$r' mode $(mode_of "$b/$NAME")"
  else skip R_xattr_only_accepted "xattr -w refused"; fi
else
  skip R_xattr_only_accepted "not Darwin"
fi

# --- R_unverifiable: when the permissions cannot be read, say so (never "mode not 700") -----------
# (a) `ls` fails outright; (b, Darwin) only `ls -lden` fails, so an "@" mode cannot be checked for
# an ACL. Both dirs are a perfect 0700 dir of ours, so "mode not 700" would be false there.
LSF="$ROOT/stub-ls-fail"; mkdir "$LSF"; printf '#!/bin/sh\nexit 1\n' > "$LSF/ls"; chmod +x "$LSF/ls"
b=$(newbase unv-a); mkdir -m 700 "$b/$NAME"
r=$(env -u XDG_RUNTIME_DIR PATH="$LSF:$PATH" KT_STATE_BASE="$b" TMPDIR="$GUARD" sh -c "$PROBE" _ "$L")
[ "$r" = "1||permissions not verifiable" ] && ok R_unverifiable_ls_fails || bad R_unverifiable_ls_fails "got '$r'"
if [ -z "$IS_DARWIN" ]; then
  skip R_unverifiable_no_e "not Darwin (an \"@\" mode is BSD/macOS ls only)"
else
  LSE="$ROOT/stub-ls-no-e"; mkdir "$LSE"
  printf '#!/bin/sh\n[ "$1" = -lden ] && exit 1\nexec /bin/ls "$@"\n' > "$LSE/ls"; chmod +x "$LSE/ls"
  b=$(newbase unv-b); mkdir -m 700 "$b/$NAME"
  if xattr -w user.aria-probe 1 "$b/$NAME" 2>/dev/null; then
    r=$(env -u XDG_RUNTIME_DIR PATH="$LSE:$PATH" KT_STATE_BASE="$b" TMPDIR="$GUARD" sh -c "$PROBE" _ "$L")
    [ "$r" = "1||permissions not verifiable" ] && ok R_unverifiable_no_e || bad R_unverifiable_no_e "got '$r'"
  else
    skip R_unverifiable_no_e "xattr -w refused, so no \"@\" mode to read"
  fi
fi

# --- R_parity_sh_lib (GUARD) / R_parity_sh_cli: one cksum per file set (C X U G) ------------------
sums() { for p in plugin-claude-code/scripts plugin-openai-codex/bin plugin-cursor-template/scripts/aria plugin-antigravity/bin; do
  if [ -f "$REPO/$p/$1" ]; then cksum < "$REPO/$p/$1"; else echo "missing:$p"; fi; done | sort -u; }
s=$(sums lib-state-key.sh); [ "$(printf '%s\n' "$s" | wc -l | tr -d ' ')" = 1 ] && ok R_parity_sh_lib || bad R_parity_sh_lib "$(printf '%s' "$s" | tr '\n' ' ')"
s=$(sums aria-state.sh); [ "$(printf '%s\n' "$s" | wc -l | tr -d ' ')" = 1 ] && case $s in missing:*) false;; esac && ok R_parity_sh_cli || bad R_parity_sh_cli "$(printf '%s' "$s" | tr '\n' ' ')"

# --- R_parity_py (AC4): the Codex Python resolver agrees with the shell one ------------------------
PYDRV='import importlib.util, sys
spec = importlib.util.spec_from_file_location("aria_codex_hook", sys.argv[1])
m = importlib.util.module_from_spec(spec); sys.dont_write_bytecode = True; spec.loader.exec_module(m)
op = sys.argv[2]
if op == "dir":
    d = m.aria_state_dir(); print("" if d is None else str(d))
elif op == "reason":
    print(m.aria_state_resolve()[1])
else:
    print(m.aria_state_base())'
py() { ARIA_CODEX_PLUGIN_ROOT="$REPO/plugin-openai-codex" python3 -I -c "$PYDRV" "$HOOKPY" "$1" 2>&1; }
shdir() { sh -c '. "$1"; kt_state_dir' _ "$L"; }
shreason() { sh -c '. "$1"; kt_state_resolve; printf "%s" "$KT_STATE_REASON"' _ "$L"; }
Pa=$(newbase pya); Pb=$(newbase pyb); Pb2=$(newbase pyb2); Pc=$(newbase pyc)
pa_s=$(env -u XDG_RUNTIME_DIR KT_STATE_BASE="$Pa" TMPDIR="$GUARD" sh -c '. "$1"; kt_state_dir' _ "$L")
pa_p=$(env -u XDG_RUNTIME_DIR KT_STATE_BASE="$Pa" TMPDIR="$GUARD" ARIA_CODEX_PLUGIN_ROOT="$REPO/plugin-openai-codex" python3 -I -c "$PYDRV" "$HOOKPY" dir 2>&1)
pb_s=$(env -u KT_STATE_BASE XDG_RUNTIME_DIR="$Pb" TMPDIR="$Pb2" sh -c '. "$1"; kt_state_dir' _ "$L")
pb_p=$(env -u KT_STATE_BASE XDG_RUNTIME_DIR="$Pb" TMPDIR="$Pb2" ARIA_CODEX_PLUGIN_ROOT="$REPO/plugin-openai-codex" python3 -I -c "$PYDRV" "$HOOKPY" dir 2>&1)
pc_s=$(env -u KT_STATE_BASE -u XDG_RUNTIME_DIR TMPDIR="$Pc" sh -c '. "$1"; kt_state_dir' _ "$L")
pc_p=$(env -u KT_STATE_BASE -u XDG_RUNTIME_DIR TMPDIR="$Pc" ARIA_CODEX_PLUGIN_ROOT="$REPO/plugin-openai-codex" python3 -I -c "$PYDRV" "$HOOKPY" dir 2>&1)
pd_s=; pd_p=
if [ -n "$IS_DARWIN" ]; then
  pd_s=$(env -u KT_STATE_BASE -u XDG_RUNTIME_DIR -u TMPDIR sh -c "$BASE" _ "$L")
  pd_p=$(env -u KT_STATE_BASE -u XDG_RUNTIME_DIR -u TMPDIR ARIA_CODEX_PLUGIN_ROOT="$REPO/plugin-openai-codex" python3 -I -c "$PYDRV" "$HOOKPY" base 2>&1)
fi
Pf=$(newbase pyf); : > "$Pf/$NAME"
Pm=$(newbase pym); mkdir -m 755 "$Pm/$NAME"
rf_s=$(env -u XDG_RUNTIME_DIR KT_STATE_BASE="$Pf" TMPDIR="$GUARD" sh -c '. "$1"; kt_state_resolve; printf "%s" "$KT_STATE_REASON"' _ "$L")
rf_p=$(env -u XDG_RUNTIME_DIR KT_STATE_BASE="$Pf" TMPDIR="$GUARD" ARIA_CODEX_PLUGIN_ROOT="$REPO/plugin-openai-codex" python3 -I -c "$PYDRV" "$HOOKPY" reason 2>&1)
rm_s=$(env -u XDG_RUNTIME_DIR KT_STATE_BASE="$Pm" TMPDIR="$GUARD" sh -c '. "$1"; kt_state_resolve; printf "%s" "$KT_STATE_REASON"' _ "$L")
rm_p=$(env -u XDG_RUNTIME_DIR KT_STATE_BASE="$Pm" TMPDIR="$GUARD" ARIA_CODEX_PLUGIN_ROOT="$REPO/plugin-openai-codex" python3 -I -c "$PYDRV" "$HOOKPY" reason 2>&1)
ra_s=x; ra_p=x
if [ -n "$IS_DARWIN" ]; then
  Pacl=$(newbase pyacl); mkdir -m 700 "$Pacl/$NAME"
  if chmod +a "everyone allow list" "$Pacl/$NAME" 2>/dev/null; then
    ra_s=$(env -u XDG_RUNTIME_DIR KT_STATE_BASE="$Pacl" TMPDIR="$GUARD" sh -c '. "$1"; kt_state_resolve; printf "%s" "$KT_STATE_REASON"' _ "$L")
    ra_p=$(env -u XDG_RUNTIME_DIR KT_STATE_BASE="$Pacl" TMPDIR="$GUARD" ARIA_CODEX_PLUGIN_ROOT="$REPO/plugin-openai-codex" python3 -I -c "$PYDRV" "$HOOKPY" reason 2>&1)
  fi
fi
if [ -n "$pa_s" ] && [ "$pa_s" = "$pa_p" ] && [ "$pa_s" = "$Pa/$NAME" ] \
   && [ -n "$pb_s" ] && [ "$pb_s" = "$pb_p" ] && [ "$pb_s" = "$Pb/$NAME" ] \
   && [ -n "$pc_s" ] && [ "$pc_s" = "$pc_p" ] && [ "$pc_s" = "$Pc/$NAME" ] \
   && [ "$pd_s" = "$pd_p" ] \
   && [ "$rf_s" = "not a directory" ] && [ "$rf_p" = "$rf_s" ] \
   && [ "$rm_s" = "mode not 700" ] && [ "$rm_p" = "$rm_s" ] \
   && [ "$ra_s" = "$ra_p" ] && { [ "$ra_s" = x ] || [ "$ra_s" = "has an ACL" ]; }; then
  ok R_parity_py
else
  bad R_parity_py "a sh='$pa_s' py='$pa_p' | b sh='$pb_s' py='$pb_p' | c sh='$pc_s' py='$pc_p' | d sh='$pd_s' py='$pd_p' | file sh='$rf_s' py='$rf_p' | 755 sh='$rm_s' py='$rm_p' | acl sh='$ra_s' py='$ra_p'"
fi

# --- R_launch_count (AC5, deterministic): the resolver's cost is COUNTED, not timed ---------------
# Timing is load-sensitive (one gate run read p50 +12.03 ms on an unchanged path), so the assertion
# is on process launches: each external the resolver can run, and common ones it must not, is a PATH
# stub that appends its name to a counter and execs the real program. Measured 2026-11-12 (macOS,
# `ls -lden` supported): steady resolve = 2 (id, ls), fresh create = 3 (+ mkdir), kt_state_base with
# KT_STATE_BASE/XDG_RUNTIME_DIR/TMPDIR all unset = 2 (uname, getconf). The bound is those numbers,
# plus one ls where `-lden` is unsupported (the GNU fallback makes a second read). Subshell forks for
# command substitution are not counted (no exec). Positive control: the stubs must have been hit.
CNT="$ROOT/count-stubs"; mkdir "$CNT"
for c in id ls mkdir uname getconf chmod chown stat cat rm mv cp awk sed grep tr cut head tail find \
         readlink realpath dirname basename touch date env xattr python3 perl; do
  real=$(command -v "$c" 2>/dev/null) || continue
  case $real in /*) ;; *) continue ;; esac   # a builtin wins over PATH anyway; nothing to count
  printf '#!/bin/sh\nprintf "%%s\\n" %s >> "$ARIA_COUNT_FILE"\nexec %s "$@"\n' "$c" "$real" > "$CNT/$c"
  chmod +x "$CNT/$c"
done
GNU_EXTRA=0; ls -lden "$ROOT" >/dev/null 2>&1 || GNU_EXTRA=1
count_run() {   # count_run <label> <base-or-empty> <sh code>; prints "rc|count|names"
  : > "$ROOT/count.$1"
  if [ -n "$2" ]; then
    env -u XDG_RUNTIME_DIR ARIA_COUNT_FILE="$ROOT/count.$1" PATH="$CNT:$PATH" KT_STATE_BASE="$2" TMPDIR="$GUARD" sh -c "$3" _ "$L" >/dev/null; _crc=$?
  else
    env -u XDG_RUNTIME_DIR -u KT_STATE_BASE -u TMPDIR ARIA_COUNT_FILE="$ROOT/count.$1" PATH="$CNT:$PATH" sh -c "$3" _ "$L" >/dev/null; _crc=$?
  fi
  printf '%s|%s|%s' "$_crc" "$(wc -l < "$ROOT/count.$1" | tr -d ' ')" "$(sort "$ROOT/count.$1" | tr '\n' ' ')"
}
b=$(newbase count)
cf=$(count_run fresh "$b" '. "$1"; kt_state_resolve')
cs=$(count_run steady "$b" '. "$1"; kt_state_resolve')
cu=$(count_run unset "" '. "$1"; kt_state_base')
max_s=$((2 + GNU_EXTRA)); max_f=$((3 + GNU_EXTRA))
n_f=$(printf '%s' "$cf" | cut -d'|' -f2); n_s=$(printf '%s' "$cs" | cut -d'|' -f2); n_u=$(printf '%s' "$cu" | cut -d'|' -f2)
names_s=" ${cs##*|}"
case $names_s in *" id "*) hit_id=1 ;; *) hit_id= ;; esac
case $names_s in *" ls "*) hit_ls=1 ;; *) hit_ls= ;; esac
if [ "${cf%%|*}" = 0 ] && [ "${cs%%|*}" = 0 ] && [ -n "$hit_id" ] && [ -n "$hit_ls" ] \
   && [ "$n_f" -le "$max_f" ] && [ "$n_s" -le "$max_s" ] && [ "$n_u" -le 2 ]; then
  ok "R_launch_count — steady $n_s (<= $max_s: ${cs##*|}), fresh $n_f (<= $max_f: ${cf##*|}), base-unset $n_u (<= 2: ${cu##*|})"
else
  bad R_launch_count "steady '$cs' (max $max_s) | fresh '$cf' (max $max_f) | base-unset '$cu' (max 2)"
fi

# --- R_timing_report: timing is REPORTED ONLY; asserts just that every timed resolve exited 0 -------
b=$(newbase lat); in_base "$b" '. "$1"; kt_state_dir' >/dev/null
LATPY='import os, subprocess, sys, time
lib = sys.argv[1]; n = 100
res, bare, rcs = [], [], set()
def run(cmd):
    s = time.perf_counter(); p = subprocess.run(cmd, stderr=subprocess.DEVNULL, check=False); return (time.perf_counter() - s) * 1000, p.returncode
for _ in range(n):
    t, rc = run(["sh", "-c", ". \"$1\"; kt_state_resolve", "_", lib]); res.append(t); rcs.add(rc)
    t, _ = run(["sh", "-c", ":"]); bare.append(t)
def pct(xs, p):
    xs = sorted(xs); return xs[max(0, -(-p * len(xs) // 100) - 1)]
m50 = pct(res, 50) - pct(bare, 50)
m95 = pct(res, 95) - pct(bare, 95)
print(f"REPORT ONLY: added p50 {m50:.2f} ms, added p95 {m95:.2f} ms; resolver p50/p95 {pct(res, 50):.2f}/{pct(res, 95):.2f}, bare {pct(bare, 50):.2f}/{pct(bare, 95):.2f} (n={n}), resolver exits {sorted(rcs)}")
sys.exit(0 if rcs == {0} else 1)'
lat=$(env -u XDG_RUNTIME_DIR KT_STATE_BASE="$b" TMPDIR="$GUARD" python3 -I -c "$LATPY" "$L" 2>&1); lrc=$?
[ "$lrc" -eq 0 ] && ok "R_timing_report — $lat" || bad R_timing_report "$lat"

# --- nothing escaped into the guard TMPDIR ------------------------------------------------------
[ -z "$(ls -A "$GUARD")" ] && ok R_guard_tmpdir_untouched || bad R_guard_tmpdir_untouched "$(ls -A "$GUARD" | tr '\n' ' ')"

printf "\n%d passed, %d failed, %d skipped\n" "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
