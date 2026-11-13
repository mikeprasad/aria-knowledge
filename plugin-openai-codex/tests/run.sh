#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 2.58.0: the session-start sweeps now reach the real /tmp, so hooks run by this suite sweep a scratch
# dir instead (KT_TMP_SWEEP_ROOT is the test-only override).
KT_TMP_SWEEP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/aria-sweep-root.XXXXXX")
export KT_TMP_SWEEP_ROOT
# 2.58.0: hook state lives in <base>/aria-knowledge-<uid>; the suite resolves it under this scratch
# base (KT_STATE_BASE is the test-only override), never in the user's real state directory. The base
# itself is a unique mktemp dir under $TMPDIR, removed by the trap.
KT_STATE_BASE=$(mktemp -d "${TMPDIR:-/tmp}/aria-state-base.XXXXXX")
export KT_STATE_BASE
LEAK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/aria-leak-check.XXXXXX")
trap 'rm -rf "$KT_TMP_SWEEP_ROOT" "$KT_STATE_BASE" "$LEAK_DIR"' EXIT

# Leak arm (2.58.0): the suite must not create state in the real /tmp or $TMPDIR. Before 2.58.0 every
# run left ~12 files there named for its fake session ids (session-tmp<random>, from the
# TemporaryDirectory names; session-t5<label>-<hex> are the Task 5 arms' keys). The check lists only
# entries with those names: a raw count of aria-* would be flaky, because live sessions on older
# releases keep writing /tmp/aria-* while the suite runs. That name filter is the bound of this check.
leak_list() {
  for _d in "$@"; do
    ls -A "$_d/" 2>/dev/null | grep -E '^aria-.*session-(tmp|t5)' | sed "s|^|$_d/|" || :
  done | sort -u
}
# Positive control: the filter finds a planted entry of the leak shape, and only that one.
mkdir "$LEAK_DIR/control"
: > "$LEAK_DIR/control/aria-active-session-tmpcontrol1"
: > "$LEAK_DIR/control/aria-unrelated-file"
if [ "$(leak_list "$LEAK_DIR/control")" != "$LEAK_DIR/control/aria-active-session-tmpcontrol1" ]; then
  echo "FAIL leak arm control: the name filter did not find the planted entry" >&2
  exit 1
fi
leak_list /tmp "${TMPDIR:-/tmp}" > "$LEAK_DIR/before"

suite_rc=0
python3 "$SCRIPT_DIR/test_codex_port.py" || suite_rc=$?

leak_list /tmp "${TMPDIR:-/tmp}" > "$LEAK_DIR/after"
new=$(comm -13 "$LEAK_DIR/before" "$LEAK_DIR/after")
if [ -n "$new" ]; then
  echo "FAIL leak arm: the suite created state in the real /tmp or \$TMPDIR:" >&2
  printf '%s\n' "$new" >&2
  exit 1
fi
echo "PASS leak arm: no new aria-*session-(tmp|t5)* entry in /tmp or \$TMPDIR"
exit "$suite_rc"
