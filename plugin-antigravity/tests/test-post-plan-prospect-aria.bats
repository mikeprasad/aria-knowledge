#!/usr/bin/env bats

setup() {
  WRAPPER="${BATS_TEST_DIRNAME}/../bin/antigravity/post-plan-prospect-aria.sh"
  export KT_CONFIG="${BATS_TMPDIR}/aria-knowledge-prospect-test.local.md"
  export LOG_FILE="${BATS_TMPDIR}/aria-knowledge-scope-check-test.log"
  # Clean up logs
  rm -f "$LOG_FILE" 2>/dev/null || true

  # Write a mock config pointing to /tmp as knowledge folder
  cat > "$KT_CONFIG" <<EOF
---
knowledge_folder: /tmp
auto_prospect: nudge
---
EOF
}

teardown() {
  rm -f "$KT_CONFIG" "$LOG_FILE" 2>/dev/null || true
}

@test "prospect wrapper returns empty JSON object {} on success" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":5,"toolCall":{"name":"write_to_file","args":{"TargetFile":"/tmp/docs/plans/test-plan.md"}}}'
  # Set the LOG_FILE variable to redirect output during the test
  export HOME="${BATS_TMPDIR}"
  mkdir -p "${BATS_TMPDIR}/.gemini/antigravity"
  
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  parsed=$(echo "$result" | jq -c .)
  [ "$parsed" = "{}" ]
}

@test "prospect wrapper logs prospect check context when a plan is written" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":5,"toolCall":{"name":"write_to_file","args":{"TargetFile":"/tmp/docs/plans/test-plan.md"}}}'
  
  # Override HOME to redirect the log file to BATS_TMPDIR/.gemini/antigravity/
  export HOME="${BATS_TMPDIR}"
  mkdir -p "${BATS_TMPDIR}/.gemini/antigravity"
  LOG_PATH="${BATS_TMPDIR}/.gemini/antigravity/aria-knowledge-scope-check.log"
  rm -f "$LOG_PATH"

  # We need the canonical script to exist and be executable.
  # Let's run the wrapper. Since /tmp/docs/plans/test-plan.md matches the plan path,
  # the canonical script should trigger and output a nudge.
  echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null >/dev/null

  # Verify that the log file was created and contains the prospect nudge
  [ -f "$LOG_PATH" ]
  content=$(cat "$LOG_PATH")
  [[ "$content" =~ "AUTO-PROSPECT" ]]
}

@test "prospect wrapper skips non-plan files" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":5,"toolCall":{"name":"write_to_file","args":{"TargetFile":"/tmp/docs/some-file.md"}}}'
  
  export HOME="${BATS_TMPDIR}"
  mkdir -p "${BATS_TMPDIR}/.gemini/antigravity"
  LOG_PATH="${BATS_TMPDIR}/.gemini/antigravity/aria-knowledge-scope-check.log"
  rm -f "$LOG_PATH"

  echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null >/dev/null

  # Log file should not exist or be empty
  if [ -f "$LOG_PATH" ]; then
    content=$(cat "$LOG_PATH")
    [ -z "$content" ]
  fi
}
