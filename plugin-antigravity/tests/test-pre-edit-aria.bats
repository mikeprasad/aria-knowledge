#!/usr/bin/env bats

setup() {
  WRAPPER="${BATS_TEST_DIRNAME}/../bin/antigravity/pre-edit-aria.sh"
}

@test "wrapper allows by default on write_to_file" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":0,"toolCall":{"name":"write_to_file","args":{"TargetFile":"/tmp/f.txt","CodeContent":"x"}}}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  decision=$(echo "$result" | jq -r '.decision')
  [ "$decision" = "allow" ]
}

@test "wrapper output is valid JSON" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":0,"toolCall":{"name":"write_to_file","args":{"TargetFile":"/tmp/f.txt"}}}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  echo "$result" | jq -e . >/dev/null
}

@test "wrapper sources lib successfully" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":0,"toolCall":{"name":"replace_file_content","args":{"TargetFile":"/tmp/f.txt"}}}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  [ -n "$result" ]
}
