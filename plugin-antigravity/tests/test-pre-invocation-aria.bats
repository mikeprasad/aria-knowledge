#!/usr/bin/env bats

setup() {
  WRAPPER="${BATS_TEST_DIRNAME}/../bin/antigravity/pre-invocation-aria.sh"
  CACHE_DIR="$HOME/.gemini/antigravity"
  CACHE_FILE="$CACHE_DIR/.last-transcript-path"
  LOG_FILE="$CACHE_DIR/aria-knowledge-scope-check.log"
  mkdir -p "$CACHE_DIR" 2>/dev/null || true
}

teardown() {
  rm -f "$CACHE_FILE" "$LOG_FILE" "$CACHE_DIR/.last-artifact-dir" 2>/dev/null || true
}

@test "wrapper output is valid JSON for any invocationNum" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t.jsonl","artifactDirectoryPath":"/tmp/art","invocationNum":5,"initialNumSteps":10}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  echo "$result" | jq -e . >/dev/null
}

@test "wrapper caches transcriptPath on every call" {
  rm -f "$CACHE_FILE"
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/some/transcript.jsonl","artifactDirectoryPath":"/tmp/art","invocationNum":7,"initialNumSteps":15}'
  echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null >/dev/null
  [ -f "$CACHE_FILE" ]
  cached=$(cat "$CACHE_FILE")
  [ "$cached" = "/some/transcript.jsonl" ]
}

@test "wrapper caches artifactDirectoryPath on every call" {
  ARTIFACT_FILE="$CACHE_DIR/.last-artifact-dir"
  rm -f "$ARTIFACT_FILE"
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/some/t.jsonl","artifactDirectoryPath":"/some/artifacts","invocationNum":7,"initialNumSteps":15}'
  echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null >/dev/null
  [ -f "$ARTIFACT_FILE" ]
  cached=$(cat "$ARTIFACT_FILE")
  [ "$cached" = "/some/artifacts" ]
}

@test "first-call (invocationNum=0) injects session-start ephemeralMessage" {
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","invocationNum":0,"initialNumSteps":0}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  # Should have injectSteps with at least one ephemeralMessage containing "ARIA" or "aria-knowledge"
  steps=$(echo "$result" | jq -r '.injectSteps[0].ephemeralMessage // ""')
  [[ "$steps" =~ ARIA || "$steps" =~ aria-knowledge ]]
}

@test "subsequent calls (invocationNum>0) with empty log do not inject anything" {
  rm -f "$LOG_FILE"
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","invocationNum":3,"initialNumSteps":5}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  # Either {} or {"injectSteps": []}
  steps_count=$(echo "$result" | jq -r '(.injectSteps // []) | length')
  [ "$steps_count" = "0" ]
}

@test "subsequent calls with pending scope-check log entries drain and inject" {
  printf '%s\n' "--- 2026-05-24T08:00:00Z stepIdx=5 error=none" "[Rule 22 Scope] PASS — sample entry" > "$LOG_FILE"
  PAYLOAD='{"conversationId":"abc","workspacePaths":["/tmp"],"transcriptPath":"/tmp/t","artifactDirectoryPath":"/tmp/art","invocationNum":3,"initialNumSteps":5}'
  result=$(echo "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  msg=$(echo "$result" | jq -r '.injectSteps[0].ephemeralMessage // ""')
  [[ "$msg" =~ "Rule 22" ]] || [[ "$msg" =~ "scope" ]]
  # Log file should be truncated/removed after drain
  [ ! -s "$LOG_FILE" ]
}
