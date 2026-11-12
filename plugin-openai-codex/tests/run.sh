#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 2.58.0: the session-start sweeps now reach the real /tmp, so hooks run by this suite sweep a scratch
# dir instead (KT_TMP_SWEEP_ROOT is the test-only override).
KT_TMP_SWEEP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/aria-sweep-root.XXXXXX")
export KT_TMP_SWEEP_ROOT
trap 'rm -rf "$KT_TMP_SWEEP_ROOT"' EXIT
python3 "$SCRIPT_DIR/test_codex_port.py"
