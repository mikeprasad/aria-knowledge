#!/bin/sh
# Repro: the kt_resolve_account block inlined in statusline-meter.sh is byte-identical
# to the canonical one in config.sh (the meter is copied standalone, so it can't source
# config.sh — the two must not drift).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
BIN="$HERE/../../plugin-claude-code/bin"
fail() { echo "FAIL: $1"; exit 1; }
extract() { awk '/^# >>> kt_resolve_account/{f=1} f{print} /^# <<< kt_resolve_account/{f=0}' "$1"; }
a=$(extract "$BIN/config.sh")
b=$(extract "$BIN/statusline-meter.sh")
[ -n "$a" ] || fail "config.sh has no kt_resolve_account block"
[ -n "$b" ] || fail "statusline-meter.sh has no kt_resolve_account mirror"
[ "$a" = "$b" ] || fail "resolver mirror drifted from config.sh canonical"
echo "PASS statusline-resolver-sync"
