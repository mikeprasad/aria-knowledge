#!/bin/sh
# safe-create-census.sh — spec §5 Decision C / AC5: every shell write onto a predictable-name file
# (/tmp/aria-active-<sid>, the surfacing debug log aria-surface-hook.log, Antigravity's
# aria-ag-surfaced-* state and aria-ag-logged-* markers) goes through the shared safe create, and
# the helper pair is one body everywhere it is defined.
#
# Arms:
#   CC0  positive controls for the CC4 scanner: a scratch file with two unguarded writes
#        (`printf x >> /tmp/aria-active-x`, `tee -a "$_kt_ledger"`) is reported as exactly those 2
#        lines, while guarded writes, /dev/null and fd redirects in the same file are not; and a
#        variable whose assignment names a predictable file is followed to its write.
#   CC1  kt_create_new and kt_is_ours: one definition per library copy, and the extracted function
#        text (comments kept) has one cksum across all 11 copies. A MISSING copy fails.
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
CC_NAMES='aria-active-|aria-surface-hook\.log|aria-ag-surfaced-|aria-ag-logged-'
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

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
