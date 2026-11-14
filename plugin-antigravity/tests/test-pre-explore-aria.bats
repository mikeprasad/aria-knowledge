#!/usr/bin/env bats

setup() {
  # 2.58.0: hook state resolves under KT_STATE_BASE, never in the user's real state directory. The base
  # lives in bats' per-test dir under $TMPDIR, which bats removes.
  export KT_STATE_BASE="${BATS_TEST_TMPDIR}/state-base"; mkdir -p "$KT_STATE_BASE"
  # An ACL inherited from $TMPDIR would make the resolver refuse the state dir (spec G2-1) and
  # silence every hook; strip it from the base so nothing created inside can inherit one.
  chmod -N "$KT_STATE_BASE" 2>/dev/null || :; command -v setfacl >/dev/null 2>&1 && setfacl -b "$KT_STATE_BASE" 2>/dev/null || :
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
