#!/usr/bin/env bats

setup() {
  # 2.58.0: hook state resolves under KT_STATE_BASE, never in the user's real state directory. The base
  # lives in bats' per-test dir under $TMPDIR, which bats removes.
  export KT_STATE_BASE="${BATS_TEST_TMPDIR}/state-base"; mkdir -p "$KT_STATE_BASE"
  # An ACL inherited from $TMPDIR would make the resolver refuse the state dir (spec G2-1) and
  # silence every hook; strip it from the base so nothing created inside can inherit one.
  chmod -N "$KT_STATE_BASE" 2>/dev/null || :; command -v setfacl >/dev/null 2>&1 && setfacl -b "$KT_STATE_BASE" 2>/dev/null || :
  WRAPPER="${BATS_TEST_DIRNAME}/../bin/antigravity/bash-cd-aria.sh"
}

@test "wrapper allows a non-cd command" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":0,"toolCall":{"name":"run_command","args":{"CommandLine":"ls -la","Cwd":"/tmp"}}}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  decision=$(echo "$result" | jq -r '.decision')
  [ "$decision" = "allow" ]
}

@test "wrapper allows a cd command and surfaces path knowledge advisory" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":0,"toolCall":{"name":"run_command","args":{"CommandLine":"cd /Users/you/Projects/proj-a","Cwd":"/tmp"}}}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  decision=$(echo "$result" | jq -r '.decision')
  [ "$decision" = "allow" ]
}
