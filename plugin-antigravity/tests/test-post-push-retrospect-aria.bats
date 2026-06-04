#!/usr/bin/env bats

setup() {
  WRAPPER="${BATS_TEST_DIRNAME}/../bin/antigravity/post-push-retrospect-aria.sh"
  export KT_CONFIG="${BATS_TMPDIR}/aria-knowledge-retrospect-test.local.md"
  
  # Get 2 real commit SHAs from the current repository history to build a valid range
  # so that git rev-list --count can succeed.
  SHA_NEW=$(git rev-parse HEAD)
  SHA_OLD=$(git rev-parse HEAD~2 2>/dev/null || git rev-parse HEAD~1 2>/dev/null || echo "")
  
  export SHA_NEW
  export SHA_OLD

  ABS_KNOWLEDGE_FOLDER=$(cd "${BATS_TEST_DIRNAME}/.." && pwd)
  # Write a mock config pointing to the current repository directory as the knowledge folder
  # (which is a valid git repository, so git commands in post-push-retrospect-check.sh will succeed).
  cat > "$KT_CONFIG" <<EOF
---
knowledge_folder: $ABS_KNOWLEDGE_FOLDER
auto_retrospect: nudge
retrospect_min_commits: 1
retrospect_branches: main
---
EOF
}

teardown() {
  rm -f "$KT_CONFIG" 2>/dev/null || true
}

@test "retrospect wrapper returns empty JSON object {} on success" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","stepIdx":5,"toolCall":{"name":"run_command","args":{"CommandLine":"git push origin main"}},"toolResponse":{"stderr":"   a1b2c3d..e5f6g7h  main -> main\n"}}'
  export HOME="${BATS_TMPDIR}"
  mkdir -p "${BATS_TMPDIR}/.gemini/antigravity"
  
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  parsed=$(echo "$result" | jq -c .)
  [ "$parsed" = "{}" ]
}

@test "retrospect wrapper logs retrospect check context on valid git push" {
  # Skip if we couldn't get a valid old commit SHA
  [ -n "$SHA_OLD" ] || skip "Test requires a git history of at least 2 commits"

  RANGE="${SHA_OLD}..${SHA_NEW}"
  # Simulate git push stderr output containing the real range
  STDERR_OUT="   ${SHA_OLD:0:7}..${SHA_NEW:0:7}  main -> main\n"
  
  # Construct payload
  PAYLOAD=$(jq -n \
    --arg cmd "git push origin main" \
    --arg err "$STDERR_OUT" \
    '{conversationId: "abc", workspacePaths: ["/tmp"], transcriptPath: "/tmp/t", artifactDirectoryPath: "/tmp/art", stepIdx: 5, toolCall: {name: "run_command", args: {CommandLine: $cmd}}, toolResponse: {stderr: $err}}')

  export HOME="${BATS_TMPDIR}"
  mkdir -p "${BATS_TMPDIR}/.gemini/antigravity"
  LOG_PATH="${BATS_TMPDIR}/.gemini/antigravity/aria-knowledge-scope-check.log"
  rm -f "$LOG_PATH"

  echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null >/dev/null

  [ -f "$LOG_PATH" ]
  content=$(cat "$LOG_PATH")
  [[ "$content" =~ "AUTO-RETROSPECT" ]]
}

@test "retrospect wrapper skips force pushes" {
  [ -n "$SHA_OLD" ] || skip "Test requires a git history of at least 2 commits"

  RANGE="${SHA_OLD}..${SHA_NEW}"
  STDERR_OUT="   ${SHA_OLD:0:7}..${SHA_NEW:0:7}  main -> main\n"
  
  # Construct payload with a force push command line
  PAYLOAD=$(jq -n \
    --arg cmd "git push origin main -f" \
    --arg err "$STDERR_OUT" \
    '{conversationId: "abc", workspacePaths: ["/tmp"], transcriptPath: "/tmp/t", artifactDirectoryPath: "/tmp/art", stepIdx: 5, toolCall: {name: "run_command", args: {CommandLine: $cmd}}, toolResponse: {stderr: $err}}')

  export HOME="${BATS_TMPDIR}"
  mkdir -p "${BATS_TMPDIR}/.gemini/antigravity"
  LOG_PATH="${BATS_TMPDIR}/.gemini/antigravity/aria-knowledge-scope-check.log"
  rm -f "$LOG_PATH"

  echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null >/dev/null

  # Log file should be empty or not exist because force push is skipped
  if [ -f "$LOG_PATH" ]; then
    content=$(cat "$LOG_PATH")
    [ -z "$content" ]
  fi
}
