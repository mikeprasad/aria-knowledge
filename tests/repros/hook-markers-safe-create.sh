#!/bin/sh
# hook-markers-safe-create.sh — spec §5, Task 3 fix round 2 (Rule 38: close the class). Every hook
# that appends to a predictable-name marker or log creates it only with kt_create_new and appends
# only when kt_is_ours says it is a regular file of ours that is not a link:
#   bypass    <state dir>/aria-r22-bypass-<sid>        pre-bash-write-check.sh (claude-code, codex, cursor)
#   preflight <state dir>/aria-preflight-skipped-<sid> pre-commit-preflight-check.sh (4 ports)
#   dbg       /tmp/aria-hook-debug.log               cursor pre-edit / post-edit / capture-task-boundary /
#                                                    record-edit-intent (path via the test-only
#                                                    KT_HOOK_DEBUG_LOG, so the real file is never touched)
# Arms per writer:
#   positive  nothing planted → the file is created, regular, ours, and holds the line (guard)
#   link      a link to a file planted at the name → target unchanged, name still a link
#   fifo      a FIFO planted at the name → the hook finishes (bounded), the FIFO is never opened
#   window    a mktemp shim plants a link at the name when asked for the create temp (after the
#             existence test, before `link`) → shim fired (the instrument check), target unchanged
# RED on 9a50ca8: link (write-through), fifo (hang) and window (no create step, the shim never
# fires) for every writer. Everything runs under a scratch TMPDIR, HOME and state base (2.58.0: the
# bypass and preflight names live in <base>/aria-knowledge-<uid>, lib-state-key.sh).

DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2] got [$3]"; fi; }

T=$(mktemp -d "${TMPDIR:-/tmp}/aria-hook-markers.XXXXXX") || exit 1
# The bash-write resolver treats a target under a temp dir as scratch and never fires, so the
# bypass arms edit a file in a work dir inside the repo (as bash-write-target-resolution.sh does).
WORK=$(mktemp -d "${HM_WORK_ROOT:-$DIR/tests}/.hm-work.XXXXXX") || exit 1
trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T" "$WORK"' EXIT
REAL_MKTEMP=$(command -v mktemp)
export TMPDIR="$T/tmp" HOME="$T/home"
mkdir -p "$TMPDIR" "$HOME" "$T/shim"
export KT_STATE_BASE="$T/state-base"; SD="$KT_STATE_BASE/aria-knowledge-$(id -u)"
mkdir -p "$KT_STATE_BASE"; mkdir -m 700 "$SD"
printf 'x\n' > "$WORK/f"

# A staged code file, so the preflight hook reaches its warn path (gate defaults to warn).
REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q . 2>/dev/null; git -C "$REPO" config user.email t@t.t; git -C "$REPO" config user.name t
printf 'code\n' > "$REPO/app.py"; git -C "$REPO" add . 2>/dev/null

cat > "$T/shim/mktemp" <<SHIM
#!/bin/sh
case "\$*" in
  *.aria-new.*)
    : > "\$HM_WIN_FIRED"
    if [ -n "\${HM_WIN_NAME:-}" ] && [ ! -e "\$HM_WIN_NAME" ] && [ ! -L "\$HM_WIN_NAME" ]; then
      ln -s "\$HM_WIN_TGT" "\$HM_WIN_NAME"
    fi ;;
esac
exec "$REAL_MKTEMP" "\$@"
SHIM
chmod +x "$T/shim/mktemp"

# bounded SECONDS CMD... — runs CMD in the background from $T with stdin $T/in; BOUNDED=ok|hung.
# On a hang every FIFO under $T is opened read-write (never blocks) and the run is killed.
bounded() {
  _b_s=$1; shift
  ( cd "$T" && "$@" < "$T/in" > /dev/null 2>&1 ) &
  _b_p=$!; _b_i=0; BOUNDED=ok
  while kill -0 "$_b_p" 2>/dev/null; do
    _b_i=$((_b_i + 1))
    if [ "$_b_i" -gt $((_b_s * 10)) ]; then
      BOUNDED=hung
      for _b_f in $(find "$T" -type p 2>/dev/null); do exec 9<>"$_b_f"; exec 9>&-; done
      kill "$_b_p" 2>/dev/null
      break
    fi
    sleep 0.1
  done
  wait "$_b_p" 2>/dev/null
}

# wr KIND PORTDIR-OR-SCRIPT CASE [ENV…] — runs one writer for case CASE (its own session id or
# log path); sets NAME to the file it writes.
wr() {
  _w_k=$1; _w_h=$2; _w_c=$3; shift 3
  _w_sid="hm$_w_c"
  case $_w_k in
    bypass)
      NAME="$SD/aria-r22-bypass-$_w_sid"
      python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]},"session_id":sys.argv[2]}))' \
        "sed -i '' s/a/b/ $WORK/f" "$_w_sid" > "$T/in"
      bounded 10 env KT_CONFIG="$T/none.md" "$@" sh "$DIR/$_w_h/pre-bash-write-check.sh" ;;
    preflight)
      NAME="$SD/aria-preflight-skipped-$_w_sid"
      printf '{"session_id":"%s","tool_input":{"command":"cd %s && git commit -m x"}}' "$_w_sid" "$REPO" > "$T/in"
      bounded 10 env KT_CONFIG="$T/none.md" "$@" sh "$DIR/$_w_h/pre-commit-preflight-check.sh" ;;
    dbg)
      mkdir -p "$T/dbg-$_w_c"; NAME="$T/dbg-$_w_c/aria-hook-debug.log"
      printf '{"filePath":"%s"}' "$WORK/f" > "$T/in"
      _w_s="$DIR/plugin-cursor-template/scripts/aria/$_w_h"
      if [ "$_w_h" = record-edit-intent.sh ]; then
        bounded 10 env KT_CONFIG="$T/none.md" KT_HOOK_DEBUG_LOG="$NAME" KT_EDIT_INTENT_FILE="$T/intent-$_w_c.json" \
          "$@" sh "$_w_s" "$WORK/f" rule22-low
      else
        bounded 10 env KT_CONFIG="$T/none.md" KT_HOOK_DEBUG_LOG="$NAME" KT_EDIT_INTENT_FILE="$T/intent-$_w_c.json" \
          "$@" sh "$_w_s"
      fi ;;
  esac
}

# arms KIND HOOK LABEL — the four arms for one writer.
arms() {
  _a_k=$1; _a_h=$2; _a_l=$3; _a_n=$(printf '%s' "$_a_l" | tr -c 'A-Za-z0-9' 'x')
  # positive
  wr "$_a_k" "$_a_h" "${_a_n}p"
  check "$_a_l positive: created regular, ours, holding a line; bounded" "1|1|ok" \
    "$( [ -f "$NAME" ] && [ ! -L "$NAME" ] && [ -O "$NAME" ] && echo 1 || echo 0)|$( [ -s "$NAME" ] && echo 1 || echo 0)|$BOUNDED"
  # link to a file
  printf 'keep\n' > "$T/${_a_n}l.tgt"
  _a_name=$(wr_name "$_a_k" "${_a_n}l"); ln -s "$T/${_a_n}l.tgt" "$_a_name"
  wr "$_a_k" "$_a_h" "${_a_n}l"
  check "$_a_l planted link: target intact, still a link, bounded" "keep|1|ok" \
    "$(cat "$T/${_a_n}l.tgt" | tr '\n' ' ' | sed 's/ $//')|$( [ -L "$NAME" ] && echo 1 || echo 0)|$BOUNDED"
  # FIFO
  _a_name=$(wr_name "$_a_k" "${_a_n}f"); mkfifo "$_a_name"
  wr "$_a_k" "$_a_h" "${_a_n}f"
  check "$_a_l planted FIFO: bounded, still a FIFO" "ok|1" "$BOUNDED|$( [ -p "$NAME" ] && echo 1 || echo 0)"
  # link planted in the create window
  printf 'keep\n' > "$T/${_a_n}w.tgt"; rm -f "$T/fired"
  _a_name=$(wr_name "$_a_k" "${_a_n}w")
  wr "$_a_k" "$_a_h" "${_a_n}w" PATH="$T/shim:$PATH" HM_WIN_FIRED="$T/fired" HM_WIN_NAME="$_a_name" \
    HM_WIN_TGT="$T/${_a_n}w.tgt"
  check "$_a_l link planted in the create window: shim fired, target intact, bounded" "1|keep|ok" \
    "$( [ -e "$T/fired" ] && echo 1 || echo 0)|$(cat "$T/${_a_n}w.tgt" | tr '\n' ' ' | sed 's/ $//')|$BOUNDED"
}
wr_name() { # KIND CASE → the name wr will write (the dbg dir is created here, as wr does)
  case $1 in
    bypass) echo "$SD/aria-r22-bypass-hm$2" ;;
    preflight) echo "$SD/aria-preflight-skipped-hm$2" ;;
    dbg) mkdir -p "$T/dbg-$2"; echo "$T/dbg-$2/aria-hook-debug.log" ;;
  esac
}

for p in plugin-claude-code/scripts plugin-openai-codex/bin plugin-cursor-template/scripts/aria; do
  arms bypass "$p" "bypass[$p]"
done
for p in plugin-claude-code/scripts plugin-antigravity/bin plugin-openai-codex/bin plugin-cursor-template/scripts/aria; do
  arms preflight "$p" "preflight[$p]"
done
for s in pre-edit-check.sh post-edit-check.sh capture-task-boundary.sh record-edit-intent.sh; do
  arms dbg "$s" "dbg[$s]"
done

# capture-task-boundary.sh also READS the debug log into its boundary note: never through a link.
printf 'SECRET-TARGET-LINE\n' > "$T/ctb.tgt"
mkdir -p "$T/kf" "$T/dbg-ctbread"; ln -s "$T/ctb.tgt" "$T/dbg-ctbread/aria-hook-debug.log"
printf -- '---\nknowledge_folder: %s\n---\n' "$T/kf" > "$T/ctb.md"
printf '{}' > "$T/in"
bounded 10 env KT_CONFIG="$T/ctb.md" KT_HOOK_DEBUG_LOG="$T/dbg-ctbread/aria-hook-debug.log" \
  sh "$DIR/plugin-cursor-template/scripts/aria/capture-task-boundary.sh"
check "dbg[capture-task-boundary.sh] reads no linked log into its note" "0" \
  "$(grep -rl 'SECRET-TARGET-LINE' "$T/kf" 2>/dev/null | grep -c .)"
# Control: the same content as a regular log of ours IS read into the note — so the arm above
# refuses the link, rather than passing because no note was written.
mkdir -p "$T/kf2" "$T/dbg-ctbctl"; cp "$T/ctb.tgt" "$T/dbg-ctbctl/aria-hook-debug.log"
printf -- '---\nknowledge_folder: %s\n---\n' "$T/kf2" > "$T/ctb2.md"
bounded 10 env KT_CONFIG="$T/ctb2.md" KT_HOOK_DEBUG_LOG="$T/dbg-ctbctl/aria-hook-debug.log" \
  sh "$DIR/plugin-cursor-template/scripts/aria/capture-task-boundary.sh"
check "dbg[capture-task-boundary.sh] control: a regular log of ours is read into the note" "1" \
  "$(grep -rl 'SECRET-TARGET-LINE' "$T/kf2" 2>/dev/null | grep -c .)"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
