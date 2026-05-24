#!/usr/bin/env bats

setup() {
  WRAPPER="${BATS_TEST_DIRNAME}/../bin/antigravity/bash-cd-aria.sh"
}

@test "wrapper allows a non-cd command" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":0,"toolCall":{"name":"run_command","args":{"CommandLine":"ls -la","Cwd":"/tmp"}}}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  decision=$(echo "$result" | jq -r '.decision')
  [ "$decision" = "allow" ]
}

@test "wrapper allows a cd command and surfaces path knowledge advisory" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":0,"toolCall":{"name":"run_command","args":{"CommandLine":"cd /Users/mikeprasad/Projects/cs","Cwd":"/tmp"}}}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  decision=$(echo "$result" | jq -r '.decision')
  [ "$decision" = "allow" ]
}
