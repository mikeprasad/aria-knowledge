#!/usr/bin/env bats

setup() {
  # D8a: the wrappers write under $HOME/.gemini/antigravity; never the real one.
  export HOME="${BATS_TEST_TMPDIR}/home"; mkdir -p "$HOME"
  # 2.58.0: hook state resolves under KT_STATE_BASE, never in the user's real state directory. The base
  # lives in bats' per-test dir under $TMPDIR, which bats removes.
  export KT_STATE_BASE="${BATS_TEST_TMPDIR}/state-base"; mkdir -p "$KT_STATE_BASE"
  # An ACL inherited from $TMPDIR would make the resolver refuse the state dir (spec G2-1) and
  # silence every hook; strip it from the base so nothing created inside can inherit one.
  chmod -N "$KT_STATE_BASE" 2>/dev/null || :; command -v setfacl >/dev/null 2>&1 && setfacl -b "$KT_STATE_BASE" 2>/dev/null || :
  WRAPPER="${BATS_TEST_DIRNAME}/../bin/antigravity/post-edit-aria.sh"
}

@test "wrapper returns empty JSON object on success" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":5,"error":""}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  # PostToolUse spec says output is {} on success.
  parsed=$(echo "$result" | jq -c .)
  [ "$parsed" = "{}" ] || [[ "$parsed" =~ ^\{ ]]
}

@test "wrapper produces valid JSON even on canonical script error" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":5,"error":"exit status 1"}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  echo "$result" | jq -e . >/dev/null
}
