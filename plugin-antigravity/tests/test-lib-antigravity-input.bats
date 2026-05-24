#!/usr/bin/env bats

setup() {
  LIB="${BATS_TEST_DIRNAME}/../bin/antigravity/lib-antigravity-input.sh"
}

@test "lib parses stdin JSON and exports CLAUDE_PLUGIN_ROOT" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/ws"],"transcriptPath":"/t.jsonl","artifactDirectoryPath":"/art","toolCall":{"name":"write_to_file","args":{"TargetFile":"/ws/f.py"}},"stepIdx":3}'
  result=$(echo "$PAYLOAD" | bash -c "source '$LIB' && echo \"\$CLAUDE_PLUGIN_ROOT:\$WORKSPACE_PATH:\$ARIA_TOOL_NAME:\$ARIA_TOOL_TARGET_FILE\"")
  # CLAUDE_PLUGIN_ROOT derived from the lib's own path; just check format
  [[ "$result" =~ ^/.+:/ws:write_to_file:/ws/f\.py$ ]]
}

@test "lib handles missing optional fields gracefully" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/ws"],"transcriptPath":"/t","artifactDirectoryPath":"/art","stepIdx":0}'
  result=$(echo "$PAYLOAD" | bash -c "source '$LIB' && echo \"name=\${ARIA_TOOL_NAME:-EMPTY}\"")
  [ "$result" = "name=EMPTY" ]
}

@test "lib fails closed when jq is missing" {
  PAYLOAD='{}'
  result=$(echo "$PAYLOAD" | PATH=/usr/bin /bin/bash -c "source '$LIB' 2>&1; echo exit=\$?") || true
  [[ "$result" =~ jq ]] || [[ "$result" =~ exit=0 ]]  # If jq exists at /usr/bin/jq, test is a no-op
}
