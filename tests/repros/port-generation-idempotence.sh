#!/bin/sh
# tests/repros/port-generation-idempotence.sh
#
# Enforces the standing rule "run the generator; never hand-patch a generated
# port". Before this existed NOTHING enforced it: no test ran build.sh, and the
# ported scripts are tracked by no PORT-LEDGER surface, so a hand-edit to
# plugin-antigravity/ passed every check and survived until the next generator
# run silently overwrote it.
#
# WHY NOT THE LEDGER: PORT-LEDGER.json guards surfaces by sha256 parity against
# canonical, but build.sh deliberately rewrites $HOME/.claude ->
# $HOME/.gemini/antigravity. A path-adapted generated file therefore can NEVER
# hash-match canonical — tracking it there would pin it permanently "drifted".
# The answerable question is not "does it match canonical?" but "does
# regenerating it change anything?", which is what this asserts.
#
# ⛔ THE GENERATOR IS RUN AGAINST AN ISOLATED COPY, NEVER THE LIVE WORKTREE, and
# that is load-bearing rather than tidy: build.sh does `rm -rf` on
# $DST/{skills,template,rules}. This tree is shared with parallel sessions, so an
# in-place run would destroy a peer's uncommitted port work — the same hazard
# that put another session's uncommitted statusline fix into this port on
# 2026-09-16. AC-B3 below asserts the live tree is untouched.
#
# ⚠ BOUND (recorded at the code, not only in the retrospective): the comparison
# TARGET is the real committed port, so the composition that actually ships is
# what gets judged — but the generator's INPUT is a replica. An unfaithful copy
# would produce a difference unrelated to the subject, so copy fidelity is
# asserted first (AC-B7) and a mismatch is VOID, not a failure of the port.
#
# ⛔ A SKIP IS A PASS to tests/run.sh, which counts `sh <suite>` exit 0 as a
# passing suite. So an unrunnable generator must print VOID and exit NON-ZERO,
# and the verdict must rest on positive evidence that build.sh executed — never
# on an empty diff, which is also exactly what a never-executed generator
# produces.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$ROOT/plugin-antigravity/build.sh"
SRC="$ROOT/plugin-claude-code"
PORT="$ROOT/plugin-antigravity"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; }
void() { printf 'VOID: %s\n' "$1"; printf 'port-generation-idempotence: VOID (not a pass)\n'; exit 1; }

# --- AC-B5 / F2: the generator must exist and be runnable, or VOID ------------
[ -f "$BUILD" ] || void "generator absent at plugin-antigravity/build.sh — cannot verify"
[ -d "$SRC" ]   || void "canonical plugin-claude-code/ absent — cannot verify"
[ -d "$PORT" ]  || void "plugin-antigravity/ absent — cannot verify"

# --- AC-B3 (first half): fingerprint the live dirs BEFORE anything -----------
# Compared again at the end. Deliberately a filesystem manifest rather than
# `git status`: a git-conditional check would fall back to a branch that CANNOT
# FAIL where git is unavailable, and an assertion that cannot fail advertises a
# guarantee it does not provide. A manifest is also scoped exactly to what
# build.sh could touch.
manifest() { ( cd "$1" && find . -type f | LC_ALL=C sort | while read -r f; do
                 printf '%s  %s\n' "$(cksum < "$f" | awk '{print $1"-"$2}')" "$f"; done ) ; }
manifest "$SRC"  > "$TMP/live-src-before.txt"
manifest "$PORT" > "$TMP/live-port-before.txt"

# --- copy both plugin dirs into an isolated repo root ------------------------
# build.sh derives REPO from its own $SCRIPT_DIR/.., and reads nothing outside
# these two directories, so this layout is sufficient.
mkdir -p "$TMP/repo"
cp -R "$SRC"  "$TMP/repo/plugin-claude-code"
cp -R "$PORT" "$TMP/repo/plugin-antigravity"

# --- AC-B7 / F3: assert the copy is faithful before trusting any verdict -----
manifest "$SRC"                          > "$TMP/m-src-orig.txt"
manifest "$TMP/repo/plugin-claude-code"  > "$TMP/m-src-copy.txt"
if cmp -s "$TMP/m-src-orig.txt" "$TMP/m-src-copy.txt"; then ok
else void "canonical copy is not faithful — $(diff "$TMP/m-src-orig.txt" "$TMP/m-src-copy.txt" | grep -c '^[<>]') differing entries; verdict would be meaningless"; fi
manifest "$PORT"                         > "$TMP/m-port-orig.txt"
manifest "$TMP/repo/plugin-antigravity"  > "$TMP/m-port-copy.txt"
if cmp -s "$TMP/m-port-orig.txt" "$TMP/m-port-copy.txt"; then ok
else void "port copy is not faithful — verdict would be meaningless"; fi

# --- run the generator in the copy -------------------------------------------
BOUT="$TMP/build.out"
if sh "$TMP/repo/plugin-antigravity/build.sh" > "$BOUT" 2>&1; then BEXIT=0; else BEXIT=$?; fi
[ "$BEXIT" = "0" ] || void "generator exited $BEXIT — see output:
$(tail -12 "$BOUT")"

# --- AC-B5 / F2: positive evidence the generator actually RAN ----------------
# An empty diff is also what a generator that never executed produces, so the
# verdict is gated on the generator's own terminator line, not on the diff.
if grep -q 'Antigravity port build complete' "$BOUT"; then ok
else void "generator produced no completion marker — it may not have run; refusing to report a pass.
$(tail -12 "$BOUT")"; fi

# --- AC-B1/B2/B4: the regenerated port must equal the committed port ---------
# Named differences, not a bare boolean: a guard that says "drift" without
# saying WHERE costs the next reader the entire diff.
DIFFOUT="$TMP/diff.txt"
if diff -rq "$PORT" "$TMP/repo/plugin-antigravity" > "$DIFFOUT" 2>&1; then
  ok
else
  bad "the committed port is NOT what build.sh produces — regenerating changed $(grep -c . "$DIFFOUT") path(s):"
  # Print each differing path ONCE, relative to the repo root. `diff -rq` emits
  # "Files A and B differ" (two paths for one file) and "Only in D: name"; a naive
  # prefix-strip renders the first as the same path twice, which reads as noise.
  awk -v root="$ROOT/" -v tmp="$TMP/repo/" '
    /^Files / { p=$2; sub(root,"",p); sub(tmp,"",p); printf "    %s  (content differs)\n", p; next }
    /^Only in / { l=$0; sub(root,"",l); sub(tmp,"",l); printf "    %s\n", l; next }
    { printf "    %s\n", $0 }
  ' "$DIFFOUT" | head -20
  printf '    => run `sh plugin-antigravity/build.sh` and commit the result.\n'
  printf '    => if you hand-edited a ported file, move the change to plugin-claude-code/ instead.\n'
fi

# --- AC-B3 (second half): the live dirs must be byte-untouched ---------------
# If this repro ever mutates the shared tree, that is a defect in the REPRO, not
# a finding about the port — and on a tree shared with parallel sessions it would
# destroy a peer's uncommitted work, because build.sh does `rm -rf` on
# $DST/{skills,template,rules}.
manifest "$SRC"  > "$TMP/live-src-after.txt"
manifest "$PORT" > "$TMP/live-port-after.txt"
if cmp -s "$TMP/live-src-before.txt" "$TMP/live-src-after.txt" \
   && cmp -s "$TMP/live-port-before.txt" "$TMP/live-port-after.txt"; then ok
else
  bad "this repro MUTATED the live worktree — defect in the repro, not the port:"
  diff "$TMP/live-port-before.txt" "$TMP/live-port-after.txt" 2>/dev/null | sed 's/^/    /' | head -8
  diff "$TMP/live-src-before.txt" "$TMP/live-src-after.txt" 2>/dev/null | sed 's/^/    /' | head -8
fi

printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
printf 'PASS port-generation-idempotence\n'
