#!/bin/sh
# safe-create-census.sh — spec §5 Decision C / AC5: every shell write onto a predictable-name file
# (/tmp/aria-active-<sid>, the surfacing debug log aria-surface-hook.log, Antigravity's
# aria-ag-surfaced-* state and aria-ag-logged-* markers, post-edit-check.sh's
# /tmp/aria-session-inprogress-<sid>, and — fix round 2 — the hook markers
# ${TMPDIR}/aria-r22-bypass-<sid> and ${TMPDIR}/aria-preflight-skipped-<sid> and Cursor's
# /tmp/aria-hook-debug.log) goes through the shared safe create, and
# the helper pair is one body everywhere it is defined.
#
# Arms:
#   CC0  positive controls for the CC4 scanner: a scratch file with two unguarded writes
#        (`printf x >> /tmp/aria-active-x`, `tee -a "$_kt_ledger"`) is reported as exactly those 2
#        lines, while guarded writes, /dev/null and fd redirects in the same file are not; and a
#        variable whose assignment names a predictable file is followed to its write.
#   CC1  kt_create_new and kt_is_ours: one definition per library copy, and the extracted function
#        text (comments kept) has one cksum across all 11 copies. A MISSING copy fails. CC1b: the
#        same for Cursor's aria_hook_dbg across its 4 hook scripts.
#   CC2  the 4 lib-tracked-artifacts.sh copies are byte-identical (the other two libraries are
#        pinned in surfacing-ranking-verbatim.sh).
#   CC3  lib-tracked-artifacts.sh is side-effect-free at source time (the Antigravity hook sources
#        it before anything else): sourcing prints nothing, and no statement sits outside a
#        function.
#   CC4  write-idiom census (AC5) over every shell file in the four hooked ports' script dirs
#        (archived scripts excluded: they ship nowhere): a line writing with `>>`, `>` (not `>&`,
#        not /dev/null, not `2>`), `tee` or `tee -a`, whose target is a predictable name, a
#        variable assigned one in the same file, `_kt_ledger`, or `$1` inside `_kt_ps_append_kept`
#        / `ag_record_step`, must have a `kt_is_ours` test on the previous non-blank, non-comment
#        line. A census that examined zero writes FAILS (a dead scanner is not a pass).
# The Python half of the census (Codex's codex-hook.py) is CC5, added with spec §6.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/aria-safe-create-census.XXXXXX") || exit 1
trap 'rm -rf "$SCRATCH"' EXIT

LIBS="plugin-claude-code/scripts/lib-prompt-surface.sh
plugin-cursor-template/scripts/aria/lib-prompt-surface.sh
plugin-antigravity/bin/lib-prompt-surface.sh
plugin-claude-code/scripts/lib-index-match.sh
plugin-cursor-template/scripts/aria/lib-index-match.sh
plugin-antigravity/bin/lib-index-match.sh
plugin-openai-codex/bin/lib-index-match.sh
plugin-claude-code/scripts/lib-tracked-artifacts.sh
plugin-cursor-template/scripts/aria/lib-tracked-artifacts.sh
plugin-antigravity/bin/lib-tracked-artifacts.sh
plugin-openai-codex/bin/lib-tracked-artifacts.sh"

# --- the CC4 scanner ---------------------------------------------------------------------------
# cc_scan FILE... — prints `FILE:LINE: text` for every unguarded write onto a predictable name, and
# on stderr one `examined N` line per file (the number of such writes it looked at).
CC_NAMES='aria-active-|aria-surface-hook\.log|aria-ag-surfaced-|aria-ag-logged-|aria-session-inprogress-|aria-r22-bypass-|aria-preflight-skipped-|aria-hook-debug\.log'
cc_scan() {
  for _cs_f in "$@"; do
    # Variables assigned a predictable name anywhere in this file (shell has no other scope rule
    # a static reader can apply; over-matching only adds writes to check).
    _cs_vars=$(awk -v names="$CC_NAMES" '
      /^[ \t]*#/ { next }
      $0 ~ names {
        s = $0
        while (match(s, /(^|[ \t;(])[A-Za-z_][A-Za-z0-9_]*=/)) {
          v = substr(s, RSTART, RLENGTH); sub(/^[ \t;(]/, "", v); sub(/=$/, "", v)
          printf "%s ", v
          s = substr(s, RSTART + RLENGTH)
        }
      }' "$_cs_f")
    awk -v names="$CC_NAMES" -v vars="_kt_ledger $_cs_vars" -v file="$_cs_f" '
      function sensitive(tok,   i, n, a) {
        if (tok ~ names) return 1
        n = split(vars, a, " ")
        for (i = 1; i <= n; i++) if (a[i] != "" && tok ~ ("\\$\\{?" a[i] "([^A-Za-z0-9_]|$)")) return 1
        if ((fn == "_kt_ps_append_kept" || fn == "ag_record_step") && tok ~ /^"?\$\{?1\}?"?$/) return 1
        return 0
      }
      # targets(line) — space-separated redirect / tee targets on the line.
      function targets(s,   out, rest, op, pre, tok) {
        out = ""; rest = s
        while (match(rest, /(>>|>|tee[ \t]+-a[ \t]+|tee[ \t]+)/)) {
          op = substr(rest, RSTART, RLENGTH); pre = substr(rest, 1, RSTART - 1)
          rest = substr(rest, RSTART + RLENGTH)
          if (op ~ /^>/) { if (pre ~ /[0-9&<>]$/) continue; if (rest ~ /^&/) continue }
          else if (pre ~ /[A-Za-z0-9_.-]$/) continue
          sub(/^[ \t]*/, "", rest)
          tok = ""
          if (match(rest, /^"[^"]*"/)) tok = substr(rest, 1, RLENGTH)
          else if (match(rest, /^[^ \t;|&)]+/)) tok = substr(rest, 1, RLENGTH)
          if (tok == "" || tok == "/dev/null") continue
          out = out " " tok
        }
        return out
      }
      {
        line = $0
        if (match(line, /^[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/)) {
          fn = substr(line, RSTART, RLENGTH); sub(/^[ \t]*/, "", fn); sub(/[ \t]*\(\)$/, "", fn)
        }
        if (line ~ /^[ \t]*(#|$)/) next
        n = split(targets(line), t, " ")
        hit = 0
        for (i = 1; i <= n; i++) if (sensitive(t[i])) hit = 1
        if (hit) { examined++; if (prev !~ /kt_is_ours/) printf "%s:%d: %s\n", file, FNR, line }
        prev = line
        if (line ~ /^}/) fn = ""
      }
      END { printf "examined %d\n", examined + 0 > "/dev/stderr" }' "$_cs_f"
  done
}

# --- CC0 positive controls ---------------------------------------------------------------------
cat > "$SCRATCH/control.sh" <<'CTRL'
printf x >> /tmp/aria-active-x
f() {
  _kt_ledger=$1
  printf y | tee -a "$_kt_ledger"
}
g() {
  kt_is_ours "$1" || return 0
  printf z >> /tmp/aria-active-y
}
echo hi > /dev/null
echo hi >&2
echo hi 2>/dev/null
CTRL
CC0_OUT=$(cc_scan "$SCRATCH/control.sh" 2>/dev/null)
CC0_LINES=$(printf '%s\n' "$CC0_OUT" | grep -c . )
if [ "$CC0_LINES" = 2 ] \
   && printf '%s\n' "$CC0_OUT" | grep -qF ':1: printf x >> /tmp/aria-active-x' \
   && printf '%s\n' "$CC0_OUT" | grep -qF ':4:   printf y | tee -a "$_kt_ledger"'; then
  ok "CC0 control: the scanner reports exactly the 2 unguarded writes (guarded, /dev/null, fd redirects not reported)"
else
  bad "CC0 control: the scanner reports exactly the 2 unguarded writes" "got $CC0_LINES: $CC0_OUT"
fi
cat > "$SCRATCH/control-var.sh" <<'CTRL'
h() {
  _x_lf="${TMPDIR:-/tmp}/aria-surface-hook.log"
  printf '%s\n' "$line" >> "$_x_lf" 2>/dev/null
}
CTRL
CC0B=$(cc_scan "$SCRATCH/control-var.sh" 2>/dev/null | grep -c .)
if [ "$CC0B" = 1 ]; then ok "CC0 control: a variable assigned a predictable name is followed to its write"
else bad "CC0 control: a variable assigned a predictable name is followed to its write" "reported $CC0B (want 1)"; fi
# The in-progress ledger, in post-edit-check.sh's own shape (top level, not in a function): the
# unguarded append is reported, the guarded one is not.
cat > "$SCRATCH/control-inprogress.sh" <<'CTRL'
SS_LEDGER="/tmp/aria-session-inprogress-${SS_KEY}"
if true; then
  printf '%s\n' "$SS_ROOT" >> "$SS_LEDGER" 2>/dev/null || true
  if kt_is_ours "$SS_LEDGER" 2>/dev/null; then
    printf '%s\n' "$SS_ROOT" >> "$SS_LEDGER" 2>/dev/null || true
  fi
fi
CTRL
CC0C=$(cc_scan "$SCRATCH/control-inprogress.sh" 2>/dev/null)
if [ "$(printf '%s\n' "$CC0C" | grep -c .)" = 1 ] && printf '%s\n' "$CC0C" | grep -q ':3: '; then
  ok "CC0 control: the in-progress ledger name is covered (unguarded append reported, guarded one not)"
else bad "CC0 control: the in-progress ledger name is covered" "got: $CC0C"; fi

# The hook markers (fix round 2), each in its writer's own shape: lines 2, 6 and 10 are the
# unguarded appends and must be the only ones reported (the guard is on the previous line, which is
# the census's contract).
cat > "$SCRATCH/control-markers.sh" <<'CTRL'
_bw_f="${TMPDIR:-/tmp}/aria-r22-bypass-$_bw_sid"
printf '%s\n' "$_bw_rec" >> "$_bw_f" 2>/dev/null || true
if kt_is_ours "$_bw_f" 2>/dev/null; then
  printf '%s\n' "$_bw_rec" >> "$_bw_f" 2>/dev/null || true
fi
printf '%s\n' "$_pf_line" >> "${TMPDIR:-/tmp}/aria-preflight-skipped-$SESSION_ID" 2>/dev/null || true
kt_is_ours "$_pf_f" || exit 0
printf '%s\n' "$_pf_line" >> "${TMPDIR:-/tmp}/aria-preflight-skipped-$SESSION_ID" 2>/dev/null || true
:
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $0 fired" >> /tmp/aria-hook-debug.log 2>/dev/null
kt_is_ours /tmp/aria-hook-debug.log || exit 0
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $0 fired" >> /tmp/aria-hook-debug.log 2>/dev/null
CTRL
CC0M=$(cc_scan "$SCRATCH/control-markers.sh" 2>/dev/null)
if [ "$(printf '%s\n' "$CC0M" | grep -c .)" = 3 ] && printf '%s\n' "$CC0M" | grep -q ':2: ' \
   && printf '%s\n' "$CC0M" | grep -q ':6: ' && printf '%s\n' "$CC0M" | grep -q ':10: '; then
  ok "CC0 control: the r22-bypass, preflight-skipped and hook-debug names are covered (3 unguarded reported, guarded not)"
else bad "CC0 control: the r22-bypass, preflight-skipped and hook-debug names are covered" "got: $CC0M"; fi

# --- CC1 helper body parity --------------------------------------------------------------------
# cc_extract FILE NAME — the function's text from its opening line to its closing `}`.
cc_extract() {
  awk -v n="$2" '
    !on && $0 ~ ("^" n "\\(\\) *\\{") { on = 1; print; if ($0 !~ /\{[ \t]*$/) exit; next }
    on { print; if ($0 ~ /^\}/) exit }' "$1"
}
for CC_FN in kt_create_new kt_is_ours; do
  CC_REF=""; CC_BAD=""
  for CC_L in $LIBS; do
    CC_P="$ROOT/$CC_L"
    if [ ! -f "$CC_P" ]; then CC_BAD="$CC_BAD $CC_L(missing-file)"; continue; fi
    CC_N=$(grep -c "^$CC_FN() *{" "$CC_P")
    if [ "$CC_N" != 1 ]; then CC_BAD="$CC_BAD $CC_L(defs=$CC_N)"; continue; fi
    CC_SUM=$(cc_extract "$CC_P" "$CC_FN" | cksum)
    if [ -z "$CC_REF" ]; then CC_REF=$CC_SUM
    elif [ "$CC_SUM" != "$CC_REF" ]; then CC_BAD="$CC_BAD $CC_L(differs)"; fi
  done
  if [ -z "$CC_BAD" ]; then ok "CC1 $CC_FN: one definition per copy, one body across all 11 libraries ($CC_REF)"
  else bad "CC1 $CC_FN: one definition per copy, one body across all 11 libraries" "$CC_BAD"; fi
done

# CC1b — Cursor's aria_hook_dbg: one definition per hook script, one body across the four.
CC_REF=""; CC_BAD=""
for CC_L in pre-edit-check.sh post-edit-check.sh capture-task-boundary.sh record-edit-intent.sh; do
  CC_P="$ROOT/plugin-cursor-template/scripts/aria/$CC_L"
  if [ ! -f "$CC_P" ]; then CC_BAD="$CC_BAD $CC_L(missing-file)"; continue; fi
  CC_N=$(grep -c "^aria_hook_dbg() *{" "$CC_P")
  if [ "$CC_N" != 1 ]; then CC_BAD="$CC_BAD $CC_L(defs=$CC_N)"; continue; fi
  CC_SUM=$(cc_extract "$CC_P" aria_hook_dbg | cksum)
  if [ -z "$CC_REF" ]; then CC_REF=$CC_SUM
  elif [ "$CC_SUM" != "$CC_REF" ]; then CC_BAD="$CC_BAD $CC_L(differs)"; fi
done
if [ -z "$CC_BAD" ]; then ok "CC1b aria_hook_dbg: one definition per Cursor hook, one body across the 4 ($CC_REF)"
else bad "CC1b aria_hook_dbg: one definition per Cursor hook, one body across the 4" "$CC_BAD"; fi

# --- CC2 tracked-artifacts byte identity -------------------------------------------------------
CC_REF=$(cksum < "$ROOT/plugin-claude-code/scripts/lib-tracked-artifacts.sh" 2>/dev/null)
CC_BAD=""
for CC_L in plugin-cursor-template/scripts/aria plugin-antigravity/bin plugin-openai-codex/bin; do
  CC_SUM=$(cksum < "$ROOT/$CC_L/lib-tracked-artifacts.sh" 2>/dev/null)
  [ -n "$CC_SUM" ] && [ "$CC_SUM" = "$CC_REF" ] || CC_BAD="$CC_BAD $CC_L"
done
if [ -n "$CC_REF" ] && [ -z "$CC_BAD" ]; then ok "CC2 the 4 lib-tracked-artifacts.sh copies are byte-identical"
else bad "CC2 the 4 lib-tracked-artifacts.sh copies are byte-identical" "differ or missing:$CC_BAD"; fi

# --- CC3 side-effect-free at source time -------------------------------------------------------
CC_TA="$ROOT/plugin-claude-code/scripts/lib-tracked-artifacts.sh"
CC_SRC_OUT=$(sh -c '. "$1"' sh "$CC_TA" </dev/null 2>&1)
CC_TOP=$(awk '/^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { inf = 1; if ($0 !~ /\{[ \t]*$/) inf = 0; next }
  inf && /^\}/ { inf = 0; next }
  !inf && $0 !~ /^[ \t]*(#|$)/ { printf "%d: %s\n", FNR, $0 }' "$CC_TA")
if [ -f "$CC_TA" ] && [ -z "$CC_SRC_OUT" ] && [ -z "$CC_TOP" ]; then
  ok "CC3 lib-tracked-artifacts.sh: sourcing prints nothing and no statement sits outside a function"
else
  bad "CC3 lib-tracked-artifacts.sh is side-effect-free at source time" "output=[$CC_SRC_OUT] top-level=[$CC_TOP]"
fi

# --- CC4 write-idiom census --------------------------------------------------------------------
CC_FILES=$(find "$ROOT/plugin-claude-code/scripts" "$ROOT/plugin-cursor-template/scripts" \
  "$ROOT/plugin-openai-codex/bin" "$ROOT/plugin-antigravity/bin" -type f -name '*.sh' \
  -not -path '*/.archived/*' 2>/dev/null | sort)
CC_NFILES=$(printf '%s\n' "$CC_FILES" | grep -c .)
# shellcheck disable=SC2086
CC4_OUT=$(cc_scan $CC_FILES 2>"$SCRATCH/examined")
CC_EXAMINED=$(awk '{ s += $2 } END { print s + 0 }' "$SCRATCH/examined")
if [ "$CC_NFILES" -gt 0 ] && [ "$CC_EXAMINED" -gt 0 ] && [ -z "$CC4_OUT" ]; then
  ok "CC4 every write onto a predictable name is guarded by kt_is_ours ($CC_EXAMINED writes in $CC_NFILES files)"
else
  bad "CC4 every write onto a predictable name is guarded by kt_is_ours" \
    "files=$CC_NFILES examined=$CC_EXAMINED unguarded:
$(printf '%s\n' "$CC4_OUT" | sed "s|$ROOT/||")"
fi

# === 2.58.0: no hook, lib, CLI or skill names an old shared location (spec D6, AC1) =============
# Since 2.58.0 every hook state name lives in the private per-user state dir and is built by
# kt_state_path (lib-state-key.sh) or aria_state_path (codex-hook.py). These arms keep it that way.
#
# CC6 no_legacy_location — every *.sh / *.py / *.bash, recursively, in every plugin-* port (tests and
#   .archived excluded: they ship nowhere or are not hooks), plus every fenced shell block of a
#   SKILL.md or Cursor .mdc. A code line naming /tmp/aria-, ${TMPDIR…}/aria-, $TMPDIR/aria-,
#   KT_SURFACE_CACHE_DIR, Python Path("/tmp") or tempfile.gettempdir() FAILS — except a full-line
#   comment, a mktemp template (the token carries XXX: a random name nobody can pre-plant) and a line
#   inside a marked LEGACY-TMP-SWEEP-2.58 block. Zero files examined FAILS.
# CC7 state_lib_parity — lib-state-key.sh ×4 byte-identical, each defining kt_state_base,
#   kt_state_resolve, kt_state_dir and kt_state_path exactly once.
# CC8 resolve_before_use — every non-lib script that calls kt_state_path, or sources
#   lib-index-match.sh / lib-prompt-surface.sh (which read KT_STATE_DIR from the caller) and then
#   calls one of their functions, sources lib-state-key.sh and calls kt_state_resolve BEFORE that first
#   use (earlier line, or earlier on the same line, as in `kt_state_resolve && f=$(kt_state_path …)`).
#   "Use" is the first CALL, not the source line: sourcing only defines functions, and the brief's
#   literal "before the source line" flagged 8 correct sites (4 × aria-surface.sh, prompt-context-check.sh,
#   3 × pre-bash-write-check.sh). The library entry points are read from the libraries themselves.
# CC9 one_name_builder — "$KT_STATE_DIR/<name>" (any spelling of the variable followed by "/" and a
#   name) appears only in lib-state-key.sh. The bare directory as a find start point ("$KT_STATE_DIR/"
#   closed by its quote) builds no name and is allowed. (pre-bash-r22-carrier.sh's inline Python joins
#   its carrier name itself; that key is accepted only as [A-Za-z0-9._-]+ — not this arm's form.)
# CC0 controls (scratch files): one plant per CC6 form, in shell, Python, a SKILL.md block and an .mdc
#   block, plus a comment, a mktemp template, a marked legacy line and SKILL.md prose (none reported);
#   a script calling kt_state_path without resolving and one calling a lib function before resolving
#   (CC8 reports each, not the well-ordered control); `printf x > "$KT_STATE_DIR/aria-x"` (CC9 reports
#   it, not the bare start point) — each reported exactly once.

# The awk programs go to scratch files through plain heredocs: bash 3.2 (macOS /bin/sh) mis-parses a
# quote inside a heredoc nested in $(…), and the CC6 regex carries one.
CC6_AWK="$SCRATCH/cc6.awk"
cat > "$CC6_AWK" <<'AWK'
FNR == 1 { md = (FILENAME ~ /\.(md|mdc)$/); infence = 0; inleg = 0; nfiles++ }
{
  line = $0
  if (md) {
    if (line ~ /^[ \t]*(```|~~~)/) {
      if (!infence) {
        info = line; sub(/^[ \t]*(```|~~~)[ \t]*/, "", info); infence = 1
        shell = (info ~ /^(bash|sh|shell|zsh|console)?([ \t{].*)?$/)
      } else infence = 0
      next
    }
    if (!infence || !shell) next
  }
  if (line ~ /LEGACY-TMP-SWEEP-2\.58 begin/) { inleg = 1; next }
  if (line ~ /LEGACY-TMP-SWEEP-2\.58 end/) { inleg = 0; next }
  if (inleg) next
  if (line ~ /^[ \t]*#/) next
  s = line; hit = 0
  while (match(s, /\/tmp\/\.?aria-|\$\{TMPDIR[^}]*\}"?\/\.?aria-|\$TMPDIR"?\/\.?aria-|KT_SURFACE_CACHE_DIR|Path\([ \t]*["']\/tmp\/?["'][ \t]*\)|gettempdir\(\)/)) {
    tok = substr(s, RSTART); rest = substr(s, RSTART + RLENGTH)
    match(tok, /^[^ \t()]*([(][)])?[^ \t()]*/); tok = substr(tok, 1, RLENGTH)
    if (!(line ~ /mktemp/ && tok ~ /XXX/)) { hit = 1; break }
    s = rest
  }
  if (hit) printf "%s:%d: %s\n", FILENAME, FNR, line
}
END { printf "examined %d\n", nfiles + 0 > "/dev/stderr" }
AWK
# cc6_scan FILE... — stdout: offending lines; stderr: `examined N`.
cc6_scan() { [ "$#" -gt 0 ] || { echo "examined 0" >&2; return 0; }; awk -f "$CC6_AWK" "$@"; }

CC8_AWK="$SCRATCH/cc8.awk"
cat > "$CC8_AWK" <<'AWK'
BEGIN { n = split(fns, F, " "); for (i = 1; i <= n; i++) isf[F[i]] = 1 }
FNR == 1 { src = libsrc = res = use = 0 }
/^[ \t]*#/ { next }
{
  line = $0
  if (!src && line ~ /(^|[;&|( \t])(\.|source)[ \t]+[^#]*lib-state-key\.sh/) src = FNR
  if (!libsrc && line ~ /(^|[;&|( \t])(\.|source)[ \t]+[^#]*lib-(index-match|prompt-surface)\.sh/) libsrc = FNR
  if (!res && (p = index(line, "kt_state_resolve")) && line !~ /kt_state_resolve\(\)/) { res = FNR; rescol = p }
  if (!use) {
    if ((p = index(line, "kt_state_path")) && line !~ /kt_state_path\(\)/) { use = FNR; usecol = p; ul = line }
    else if (libsrc && FNR > libsrc) {
      s = line
      while (match(s, /[A-Za-z_][A-Za-z0-9_]*/)) {
        w = substr(s, RSTART, RLENGTH)
        if ((w in isf) && line !~ ("^[ \t]*" w "\\(\\)")) { use = FNR; usecol = 1; ul = line; break }
        s = substr(s, RSTART + RLENGTH)
      }
    }
  }
}
END {
  if (use && !(src && res && src <= res && (res < use || (res == use && rescol < usecol))))
    printf "%s:%d: %s\n", FILENAME, use, ul
}
AWK
# BWK awk has no ENDFILE, so cc8_scan runs this program once per file.
CC8_FNS=$(sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)() *{.*/\1/p' \
  "$ROOT/plugin-claude-code/scripts/lib-index-match.sh" "$ROOT/plugin-claude-code/scripts/lib-prompt-surface.sh" | sort -u | tr '\n' ' ')
cc8_scan() { for _c8 in "$@"; do awk -v fns="$CC8_FNS" -f "$CC8_AWK" "$_c8"; done; }

# cc9_scan FILE... — a name built on $KT_STATE_DIR outside the library.
cc9_scan() {
  [ "$#" -gt 0 ] || return 0
  awk '/^[ \t]*#/ { next }
    /\$\{?KT_STATE_DIR\}?"?\/[^"]/ { printf "%s:%d: %s\n", FILENAME, FNR, $0 }' "$@"
}

# --- CC0 controls for CC6, CC8, CC9 ------------------------------------------------------------
mkdir -p "$SCRATCH/cc6/skills/x" "$SCRATCH/cc6/rules" "$SCRATCH/cc8" "$SCRATCH/cc9"
cat > "$SCRATCH/cc6/hook.sh" <<'CTRL'
LEDGER="/tmp/aria-active-$S"
B="${TMPDIR:-/tmp}/aria-r22-bypass-$S"
F="$TMPDIR/aria-extfetch-$S"
C=${KT_SURFACE_CACHE_DIR:-$HOME}
# a comment naming /tmp/aria-active-x and ${TMPDIR:-/tmp}/aria-x is not code
T=$(mktemp "${TMPDIR:-/tmp}/aria-match-raw.XXXXXX")
# LEGACY-TMP-SWEEP-2.58 begin — control
rm -f /tmp/aria-active-old
# LEGACY-TMP-SWEEP-2.58 end
CTRL
# Fix round 2: TMPDIR quoted alone, and dot-prefixed names (create temps, Antigravity's model file).
cat > "$SCRATCH/cc6/hook2.sh" <<'CTRL'
Q="$TMPDIR"/aria-preflight-$S
D=/tmp/.aria-new.x
E="${TMPDIR:-/tmp}/.aria-ag-model.last"
F="$TMPDIR"/.aria-new.y
M=$(mktemp "$TMPDIR"/.aria-new.XXXXXX)
CTRL
cat > "$SCRATCH/cc6/hook.py" <<'CTRL'
p = Path("/tmp") / "aria-x"
q = "/tmp/aria-y"
r = Path(tempfile.gettempdir()) / "aria-z"
# Path("/tmp") in a comment is not code
CTRL
cat > "$SCRATCH/cc6/skills/x/SKILL.md" <<'CTRL'
Prose naming /tmp/aria-active-x is not a shell block.

```bash
cat "/tmp/aria-active-$ID"
```
CTRL
cat > "$SCRATCH/cc6/rules/x.mdc" <<'CTRL'
```sh
ls "$TMPDIR/aria-preflight-$ID"
```
CTRL
CC6C=$(cc6_scan "$SCRATCH/cc6/hook.sh" "$SCRATCH/cc6/hook2.sh" "$SCRATCH/cc6/hook.py" "$SCRATCH/cc6/skills/x/SKILL.md" "$SCRATCH/cc6/rules/x.mdc" 2>/dev/null | sed "s|$SCRATCH/cc6/||")
CC6_WANT='hook.sh:1:
hook.sh:2:
hook.sh:3:
hook.sh:4:
hook2.sh:1:
hook2.sh:2:
hook2.sh:3:
hook2.sh:4:
hook.py:1:
hook.py:2:
hook.py:3:
skills/x/SKILL.md:4:
rules/x.mdc:2:'
if [ "$(printf '%s\n' "$CC6C" | sed 's/^\([^:]*:[0-9]*:\).*/\1/')" = "$CC6_WANT" ]; then
  ok "CC0 control (CC6): each of the 13 plants (8 shell forms incl. quoted-alone TMPDIR and dot-prefixed names, 3 Python, a SKILL.md and an .mdc block) is reported exactly once; comments, the mktemp templates, the marked legacy line and skill prose are not"
else
  bad "CC0 control (CC6): each plant reported exactly once, nothing else" "got:
$CC6C"
fi
cat > "$SCRATCH/cc8/unresolved.sh" <<'CTRL'
. "$SCRIPT_DIR/lib-state-key.sh"
f=$(kt_state_path aria-x)
CTRL
cat > "$SCRATCH/cc8/lib-call-first.sh" <<'CTRL'
. "$SCRIPT_DIR/lib-prompt-surface.sh"
kt_ps_log x y z
. "$SCRIPT_DIR/lib-state-key.sh"
kt_state_resolve || exit 0
CTRL
cat > "$SCRATCH/cc8/ordered.sh" <<'CTRL'
. "$SCRIPT_DIR/lib-prompt-surface.sh"
. "$SCRIPT_DIR/lib-state-key.sh"
kt_state_resolve && f=$(kt_state_path aria-x)
kt_ps_log x y z
CTRL
CC8C=$(cc8_scan "$SCRATCH/cc8/unresolved.sh" "$SCRATCH/cc8/lib-call-first.sh" "$SCRATCH/cc8/ordered.sh" | sed "s|$SCRATCH/cc8/||")
if [ "$(printf '%s\n' "$CC8C" | sed 's/^\([^:]*:[0-9]*:\).*/\1/')" = 'unresolved.sh:2:
lib-call-first.sh:2:' ]; then
  ok "CC0 control (CC8): kt_state_path without a resolve and a lib call before the resolve are each reported once; the well-ordered script is not"
else
  bad "CC0 control (CC8): exactly the two unordered scripts reported" "got:
$CC8C"
fi
cat > "$SCRATCH/cc9/hook.sh" <<'CTRL'
printf x > "$KT_STATE_DIR/aria-x"
find "$KT_STATE_DIR/" -mindepth 1 -maxdepth 1 -type f -mmin +1440 -exec rm -f {} +
CTRL
CC9C=$(cc9_scan "$SCRATCH/cc9/hook.sh" | sed "s|$SCRATCH/cc9/||")
if [ "$(printf '%s\n' "$CC9C" | sed 's/^\([^:]*:[0-9]*:\).*/\1/')" = 'hook.sh:1:' ]; then
  ok "CC0 control (CC9): a name built on \$KT_STATE_DIR is reported once; the bare find start point is not"
else
  bad "CC0 control (CC9): exactly the built name reported" "got: $CC9C"
fi

# --- CC6 no_legacy_location --------------------------------------------------------------------
CC6_FILES=$(cd "$ROOT" && find plugin-* -type f \( -name '*.sh' -o -name '*.py' -o -name '*.bash' \
  -o -name 'SKILL.md' -o -name '*.mdc' \) -not -path '*/tests/*' -not -path '*/.archived/*' \
  -not -path '*/node_modules/*' 2>/dev/null | sort | sed "s|^|$ROOT/|")
# shellcheck disable=SC2086
CC6_OUT=$(cc6_scan $CC6_FILES 2>"$SCRATCH/cc6-examined")
CC6_N=$(awk '{ s += $2 } END { print s + 0 }' "$SCRATCH/cc6-examined")
CC6_HAS_H=$(printf '%s\n' "$CC6_FILES" | grep -c 'plugin-antigravity/bin/antigravity/pre-invocation-aria\.sh$')
CC6_HAS_PY=$(printf '%s\n' "$CC6_FILES" | grep -c 'plugin-openai-codex/bin/codex-hook\.py$')
if [ "$CC6_N" -gt 0 ] && [ "$CC6_HAS_H" = 1 ] && [ "$CC6_HAS_PY" = 1 ] && [ -z "$CC6_OUT" ]; then
  ok "CC6 no_legacy_location: no hook, lib, CLI, codex-hook.py or skill shell block names an old shared location ($CC6_N files)"
else
  bad "CC6 no_legacy_location" "examined=$CC6_N antigravity-hook=$CC6_HAS_H codex-hook.py=$CC6_HAS_PY offending:
$(printf '%s\n' "$CC6_OUT" | sed "s|$ROOT/||")"
fi

# --- CC7 state_lib_parity ----------------------------------------------------------------------
CC_REF=$(cksum < "$ROOT/plugin-claude-code/scripts/lib-state-key.sh" 2>/dev/null)
CC_BAD=""
for CC_L in plugin-claude-code/scripts plugin-cursor-template/scripts/aria plugin-openai-codex/bin plugin-antigravity/bin; do
  CC_P="$ROOT/$CC_L/lib-state-key.sh"
  if [ ! -f "$CC_P" ]; then CC_BAD="$CC_BAD $CC_L(missing)"; continue; fi
  [ "$(cksum < "$CC_P")" = "$CC_REF" ] || CC_BAD="$CC_BAD $CC_L(differs)"
  for CC_FN in kt_state_base kt_state_resolve kt_state_dir kt_state_path; do
    CC_N=$(grep -c "^$CC_FN() *{" "$CC_P")
    [ "$CC_N" = 1 ] || CC_BAD="$CC_BAD $CC_L:$CC_FN(defs=$CC_N)"
  done
done
if [ -n "$CC_REF" ] && [ -z "$CC_BAD" ]; then
  ok "CC7 state_lib_parity: lib-state-key.sh ×4 byte-identical, each defining the 4 resolver functions once"
else bad "CC7 state_lib_parity" "$CC_BAD"; fi

# --- CC8 resolve_before_use / CC9 one_name_builder (shell, non-test, non-archived) --------------
CC89_FILES=$(cd "$ROOT" && find plugin-* -type f \( -name '*.sh' -o -name '*.bash' \) -not -path '*/tests/*' \
  -not -path '*/.archived/*' -not -path '*/node_modules/*' 2>/dev/null | sort | sed "s|^|$ROOT/|")
CC8_FILES=$(printf '%s\n' "$CC89_FILES" | grep -v '/lib-[^/]*\.sh$')
CC9_FILES=$(printf '%s\n' "$CC89_FILES" | grep -v '/lib-state-key\.sh$')
CC8_N=$(printf '%s\n' "$CC8_FILES" | grep -c .)
# shellcheck disable=SC2086
CC8_OUT=$(cc8_scan $CC8_FILES)
if [ "$CC8_N" -gt 0 ] && [ -n "$CC8_FNS" ] && [ -z "$CC8_OUT" ]; then
  ok "CC8 resolve_before_use: every state path and every surfacing-lib call follows a kt_state_resolve ($CC8_N scripts)"
else
  bad "CC8 resolve_before_use" "scripts=$CC8_N lib-fns=[$CC8_FNS] unresolved:
$(printf '%s\n' "$CC8_OUT" | sed "s|$ROOT/||")"
fi
# shellcheck disable=SC2086
CC9_OUT=$(cc9_scan $CC9_FILES)
if [ "$(printf '%s\n' "$CC9_FILES" | grep -c .)" -gt 0 ] && [ -z "$CC9_OUT" ]; then
  ok "CC9 one_name_builder: no name is built on \$KT_STATE_DIR outside lib-state-key.sh"
else
  bad "CC9 one_name_builder" "$(printf '%s\n' "$CC9_OUT" | sed "s|$ROOT/||")"
fi

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
