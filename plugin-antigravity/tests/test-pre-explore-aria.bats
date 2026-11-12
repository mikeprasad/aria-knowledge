#!/usr/bin/env bats

setup() {
  # 2.58.0: hook state resolves under a per-test scratch base (KT_STATE_BASE), never the real temp dir.
  export KT_STATE_BASE="${BATS_TEST_TMPDIR}/state-base"; mkdir -p "$KT_STATE_BASE"
  WRAPPER="${BATS_TEST_DIRNAME}/../bin/antigravity/pre-explore-aria.sh"
}

@test "wrapper allows grep_search by default" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":0,"toolCall":{"name":"grep_search","args":{"SearchPath":"/tmp","Query":"foo"}}}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  decision=$(echo "$result" | jq -r '.decision')
  [ "$decision" = "allow" ]
}

@test "wrapper allows find_by_name by default" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":0,"toolCall":{"name":"find_by_name","args":{"SearchDirectory":"/tmp","Pattern":"*.py"}}}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  decision=$(echo "$result" | jq -r '.decision')
  [ "$decision" = "allow" ]
}
