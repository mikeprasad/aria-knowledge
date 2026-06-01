#!/bin/sh
# tests/repros/auto-retrospect.sh — assertions for post-push-retrospect-check.sh
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/plugin-claude-code/bin/post-push-retrospect-check.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
assert_contains() { if printf '%s' "$2" | grep -q "$3"; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1"; fi; }
assert_empty()    { if [ -z "$2" ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); printf 'FAIL: %s (got: %s)\n' "$1" "$2"; fi; }

REPO="$TMP/repo"; mkdir -p "$REPO"; cd "$REPO"
git init -q; git config user.email t@t; git config user.name t
echo 0 > f; git add f; git commit -qm c0
OLD=$(git rev-parse HEAD)
for i in 1 2 3 4; do echo $i > f; git add f; git commit -qm c$i; done
NEW=$(git rev-parse HEAD)
cd "$ROOT"

cfg() { cat > "$1" <<EOF
---
knowledge_folder: $TMP/kn
auto_retrospect: $2
retrospect_min_commits: ${3:-3}
retrospect_branches: ${4:-main,master,production}
---
EOF
mkdir -p "$TMP/kn"; }

ff_input() { printf '{"tool_name":"Bash","tool_input":{"command":"git push origin main"},"tool_response":{"stdout":"","stderr":"To github.com:x/y.git\\n   %s..%s  main -> main\\n","exit_code":0}}' "$(echo "$OLD"|cut -c1-7)" "$(echo "$NEW"|cut -c1-7)"; }

cfg "$TMP/nudge.md" nudge 3 main,master,production
OUT=$(ff_input | KT_CONFIG="$TMP/nudge.md" sh -c "cd $REPO; sh $HOOK")
assert_contains "nudge offers /retrospect range" "$OUT" "/retrospect range"
assert_contains "range carries old..new" "$OUT" "$(echo "$OLD"|cut -c1-7)..$(echo "$NEW"|cut -c1-7)"

cfg "$TMP/off.md" off
OUT=$(ff_input | KT_CONFIG="$TMP/off.md" sh -c "cd $REPO; sh $HOOK")
assert_empty "off → silent" "$OUT"

cfg "$TMP/thresh.md" nudge 10
OUT=$(ff_input | KT_CONFIG="$TMP/thresh.md" sh -c "cd $REPO; sh $HOOK")
assert_empty "below threshold → silent" "$OUT"

FEAT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git push origin feature/x"},"tool_response":{"stdout":"","stderr":"To x\\n   %s..%s  feature/x -> feature/x\\n","exit_code":0}}' "$(echo "$OLD"|cut -c1-7)" "$(echo "$NEW"|cut -c1-7)")
OUT=$(printf '%s' "$FEAT" | KT_CONFIG="$TMP/nudge.md" sh -c "cd $REPO; sh $HOOK")
assert_empty "off-branch → silent" "$OUT"

UTD='{"tool_name":"Bash","tool_input":{"command":"git push"},"tool_response":{"stdout":"","stderr":"Everything up-to-date\n","exit_code":0}}'
OUT=$(printf '%s' "$UTD" | KT_CONFIG="$TMP/nudge.md" sh -c "cd $REPO; sh $HOOK")
assert_empty "up-to-date → silent" "$OUT"

FORCE=$(printf '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"},"tool_response":{"stdout":"","stderr":"To x\\n + %s...%s  main -> main (forced update)\\n","exit_code":0}}' "$(echo "$OLD"|cut -c1-7)" "$(echo "$NEW"|cut -c1-7)")
OUT=$(printf '%s' "$FORCE" | KT_CONFIG="$TMP/nudge.md" sh -c "cd $REPO; sh $HOOK")
assert_empty "force-push → silent" "$OUT"

NP='{"tool_name":"Bash","tool_input":{"command":"git status"},"tool_response":{"stdout":"clean","stderr":"","exit_code":0}}'
OUT=$(printf '%s' "$NP" | KT_CONFIG="$TMP/nudge.md" sh -c "cd $REPO; sh $HOOK")
assert_empty "non-push → silent" "$OUT"

# Annotated/new tag push — has a `-> ref` line but NO two-dot SHA range → skip
TAG='{"tool_name":"Bash","tool_input":{"command":"git push origin v1.0"},"tool_response":{"stdout":"","stderr":"To x\n * [new tag]         v1.0 -> v1.0\n","exit_code":0}}'
OUT=$(printf '%s' "$TAG" | KT_CONFIG="$TMP/nudge.md" sh -c "cd $REPO; sh $HOOK")
assert_empty "tag push (no range) → silent" "$OUT"

printf '%d pass, %d fail\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
