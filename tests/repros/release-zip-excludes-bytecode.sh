#!/bin/sh
# release-zip-excludes-bytecode.sh — no release zip may ship Python bytecode.
#
# The published 2.56.2 zip carried skills/audit-style/__pycache__/*.pyc, and a plugin-suite run
# writes scripts/__pycache__/*.pyc (a test imports the backfill tool via importlib). rsync copies
# from the WORKING TREE, so .gitignore has no say: an un-excluded __pycache__/ ships, with the
# builder's absolute path embedded in every .pyc. Two layers, both pinned here for every release
# script (canonical + 4 ports):
#   (a) the copy step excludes __pycache__/ and *.pyc (the fix);
#   (b) the zip verification FAILS the build if one gets through anyway (the guard).
# (b) is proven by running each script's own marked check block in isolation — the same lines
# the release runs — against a planted zip (must die) and a clean zip (must pass).
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/aria-bytecode.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Planted zip: the exact shape that shipped in 2.56.2 (flat path, like antigravity) plus the
# shape a test run produces under a wrapper dir. Clean zip: a .py source must NOT be flagged.
mkdir -p "$WORK/p/skills/audit-style/__pycache__" "$WORK/p/aria-knowledge/scripts/__pycache__" "$WORK/c/scripts"
printf 'x' > "$WORK/p/skills/audit-style/__pycache__/extract-user-prose.cpython-312.pyc"
printf 'x' > "$WORK/p/aria-knowledge/scripts/__pycache__/backfill-gate-effort.cpython-312.pyc"
printf 'print(1)\n' > "$WORK/c/scripts/tool.py"
(cd "$WORK/p" && zip -rXq "$WORK/planted.zip" .)
(cd "$WORK/c" && zip -rXq "$WORK/clean.zip" .)

for rel in release.sh release-codex.sh release-cursor.sh release-antigravity.sh plugin-claude-cowork/release.sh; do
  f="$REPO_ROOT/$rel"
  # (a) the copy step excludes both forms
  n_dir=$(grep -c -- "--exclude='__pycache__" "$f" || :)
  n_pyc=$(grep -c -- "--exclude='\*\.pyc'" "$f" || :)
  want=1; [ "$rel" = plugin-claude-cowork/release.sh ] && want=2   # rsync + its tar fallback
  if [ "$n_dir" -ge "$want" ] && [ "$n_pyc" -ge "$want" ]; then ok "$rel excludes __pycache__ and *.pyc ($n_dir/$n_pyc copy steps)"
  else bad "$rel excludes" "__pycache__ in $n_dir, *.pyc in $n_pyc copy step(s); want $want each"; fi

  # (b) the zip check, run in isolation
  block="$(sed -n '/^# >>> bytecode-check/,/^# <<< bytecode-check/p' "$f")"
  if [ -z "$block" ]; then bad "$rel bytecode-check block" "no '# >>> bytecode-check' block found"; continue; fi
  run_block() { # $1 = zip; prints the die message, exits as the block does
    bash -c 'set -euo pipefail; die() { printf "DIE %s\n" "$*"; exit 1; }; ZIP_PATH="$1"; '"$block" _ "$1"
  }
  rc=0; out="$(run_block "$WORK/planted.zip" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q '^DIE .*Python bytecode'; then ok "$rel check fails a zip carrying bytecode"
  else bad "$rel planted" "rc=$rc out=$out"; fi
  rc=0; out="$(run_block "$WORK/clean.zip" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ]; then ok "$rel check passes a clean zip (a .py source is not bytecode)"
  else bad "$rel clean" "rc=$rc out=$out"; fi
done

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
