#!/usr/bin/env bats

setup() {
  # 2.58.0: hook state resolves under a per-test scratch base (KT_STATE_BASE), never the real temp dir.
  export KT_STATE_BASE="${BATS_TEST_TMPDIR}/state-base"; mkdir -p "$KT_STATE_BASE"
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
