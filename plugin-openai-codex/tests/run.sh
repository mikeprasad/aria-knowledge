#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 2.58.0: the session-start sweeps now reach the real /tmp, so hooks run by this suite sweep a scratch
# dir instead (KT_TMP_SWEEP_ROOT is the test-only override).
KT_TMP_SWEEP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/aria-sweep-root.XXXXXX")
export KT_TMP_SWEEP_ROOT
# 2.58.0: hook state lives in <base>/aria-knowledge-<uid>; the suite resolves it under this scratch
# base (KT_STATE_BASE is the test-only override), never the real one.
KT_STATE_BASE=$(mktemp -d "${TMPDIR:-/tmp}/aria-state-base.XXXXXX")
export KT_STATE_BASE
trap 'rm -rf "$KT_TMP_SWEEP_ROOT" "$KT_STATE_BASE"' EXIT
python3 "$SCRIPT_DIR/test_codex_port.py"
