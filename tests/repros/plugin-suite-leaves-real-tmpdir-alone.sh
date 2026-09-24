#!/bin/sh
# plugin-suite-leaves-real-tmpdir-alone.sh — v2.54.2: the plugin test suite must not
# read, write or delete anything in the TMPDIR it inherits.
#
# Why (measured 2026-09-24/25): plugin-claude-code/tests/run.sh did not isolate
# TMPDIR, so seven test files wrote under ${TMPDIR:-/tmp} — and
# test-external-fetch-gate.sh's ef_reset runs `rm -f ${TMPDIR:-/tmp}/aria-extfetch-*`,
# deleting every LIVE session's external-fetch cooldowns and breaker counters on
# each run. Residue measured: aria-r22-denies-pp2..pp5.
#
# The inherited TMPDIR here is a fresh sandbox standing in for the real one — this
# test never touches the user's real $TMPDIR. It runs the REAL suite through the
# REAL runner; only the inherited TMPDIR differs. Cost: one suite run (~34 s).
#
# Old code, declared before running: B1-sentinels RED (the fetch sentinel is
# deleted) · B1-no-new-entries RED (pp* files appear) · B1-suite-green green.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

OUTER=$(mktemp -d)
trap 'rm -rf "$OUTER"' EXIT
printf 'live\n' > "$OUTER/aria-extfetch-SENTINEL"
printf '1' > "$OUTER/aria-r22-denies-SENTINEL"
before=$(ls -A "$OUTER" | sort)

set +e
TMPDIR="$OUTER" sh "$REPO_ROOT/plugin-claude-code/tests/run.sh" > "$OUTER.log" 2>&1
suite_rc=$?
set -e
after=$(ls -A "$OUTER" | sort)

[ "$suite_rc" -eq 0 ] && ok "B1-suite-green" || bad "B1-suite-green" "suite exit $suite_rc — $(tail -1 "$OUTER.log")"
if [ -f "$OUTER/aria-extfetch-SENTINEL" ] && [ -f "$OUTER/aria-r22-denies-SENTINEL" ]; then
  ok "B1-sentinels-survive"
else
  bad "B1-sentinels-survive" "left: $(printf '%s' "$after" | tr '\n' ' ')"
fi
if [ "$before" = "$after" ]; then
  ok "B1-no-new-entries"
else
  bad "B1-no-new-entries" "new: $(printf '%s\n' "$after" | grep -vxF "$before" | head -5 | tr '\n' ' ')"
fi
rm -f "$OUTER.log"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
