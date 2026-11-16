#!/usr/bin/env bats

setup() {
  # D8a: the wrappers write under $HOME/.gemini/antigravity; never the real one.
  export HOME="${BATS_TEST_TMPDIR}/home"; mkdir -p "$HOME"
  # Skip the wrapper's one-shot first-run probe (scratch HOME only). Without the flag every test takes
  # the probe branch, prints a fixed allow, and never reaches the wrapper's real logic (vacuous suite).
  mkdir -p "$HOME/.gemini/antigravity"; touch "$HOME/.gemini/antigravity/.aria-probe-fired"
  # 2.58.0: hook state resolves under KT_STATE_BASE, never in the user's real state directory. The base
  # lives in bats' per-test dir under $TMPDIR, which bats removes.
  export KT_STATE_BASE="${BATS_TEST_TMPDIR}/state-base"; mkdir -p "$KT_STATE_BASE"
  # An ACL inherited from $TMPDIR would make the resolver refuse the state dir (spec G2-1) and
  # silence every hook; strip it from the base so nothing created inside can inherit one.
  chmod -N "$KT_STATE_BASE" 2>/dev/null || :; command -v setfacl >/dev/null 2>&1 && setfacl -b "$KT_STATE_BASE" 2>/dev/null || :
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
