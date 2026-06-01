#!/bin/sh
# tests/repros/auto-prospect.sh — assertions for post-plan-prospect-check.sh
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/plugin-claude-code/bin/post-plan-prospect-check.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert_contains() { if printf '%s' "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; fi; }
assert_empty()    { if [ -z "$2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: %s (got: %s)\n' "$1" "$2"; fi; }

cat > "$TMP/run.md" <<EOF
---
knowledge_folder: $TMP/kn
auto_prospect: run
---
EOF
mkdir -p "$TMP/kn"

PLAN_INPUT='{"tool_name":"Write","tool_input":{"file_path":"/x/docs/plans/2026-06-01-foo.md"}}'
NONPLAN_INPUT='{"tool_name":"Write","tool_input":{"file_path":"/x/src/foo.ts"}}'
SPEC_INPUT='{"tool_name":"Write","tool_input":{"file_path":"/x/docs/specs/2026-06-01-foo-design.md"}}'

OUT=$(printf '%s' "$PLAN_INPUT" | KT_CONFIG="$TMP/run.md" sh "$HOOK")
assert_contains "run+plan injects /prospect" "$OUT" "/prospect file"
assert_contains "run+plan says run inline" "$OUT" "Run "

cat > "$TMP/nudge.md" <<EOF
---
knowledge_folder: $TMP/kn
auto_prospect: nudge
---
EOF
SP_INPUT='{"tool_name":"Write","tool_input":{"file_path":"/x/docs/superpowers/plans/2026-06-01-bar.md"}}'
OUT=$(printf '%s' "$SP_INPUT" | KT_CONFIG="$TMP/nudge.md" sh "$HOOK")
assert_contains "nudge+plan offers /prospect" "$OUT" "/prospect file"
assert_contains "nudge wording is an offer" "$OUT" "Offer"

cat > "$TMP/off.md" <<EOF
---
knowledge_folder: $TMP/kn
auto_prospect: off
---
EOF
OUT=$(printf '%s' "$PLAN_INPUT" | KT_CONFIG="$TMP/off.md" sh "$HOOK")
assert_empty "off → silent" "$OUT"

OUT=$(printf '%s' "$SPEC_INPUT" | KT_CONFIG="$TMP/run.md" sh "$HOOK")
assert_empty "spec path excluded → silent" "$OUT"

OUT=$(printf '%s' "$NONPLAN_INPUT" | KT_CONFIG="$TMP/run.md" sh "$HOOK")
assert_empty "non-plan path → silent" "$OUT"

printf '%d pass, %d fail\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
