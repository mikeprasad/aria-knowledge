#!/usr/bin/env bats
# D8 — the Antigravity Rule 22 wrapper decides from the check's stdout (the canonical check always
# exits 0 and prints the deny JSON), not from the exit code. Fails closed on a non-zero exit or on
# stdout that is not exactly one JSON object. Runs a scratch copy of the plugin layout so stand-ins can replace the check.

setup() {
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME/.gemini/antigravity"
  touch "$HOME/.gemini/antigravity/.aria-probe-fired"   # skip the one-shot first-run probe
  export KT_STATE_BASE="${BATS_TEST_TMPDIR}/state-base"; mkdir -p "$KT_STATE_BASE"
  chmod -N "$KT_STATE_BASE" 2>/dev/null || :; command -v setfacl >/dev/null 2>&1 && setfacl -b "$KT_STATE_BASE" 2>/dev/null || :
  SRC="${BATS_TEST_DIRNAME}/.."
  ROOT="${BATS_TEST_TMPDIR}/plugin"
  mkdir -p "$ROOT"
  cp -R "$SRC/bin" "$ROOT/bin"
  WRAPPER="$ROOT/bin/antigravity/pre-edit-aria.sh"
  TDIR="${BATS_TEST_TMPDIR}/t"; mkdir -p "$TDIR"
}

# Transcript with one user turn then one MODEL step (index 1) holding $1 as its content.
make_transcript() {
  T="$TDIR/transcript.jsonl"
  printf '%s\n' '{"source":"USER_EXPLICIT","type":"USER_INPUT","content":"edit it"}' > "$T"
  jq -cn --arg c "$1" '{source:"MODEL",step_index:1,content:$c,tool_calls:[{name:"write_to_file"}]}' >> "$T"
}

run_wrapper() {
  PAYLOAD=$(jq -cn --arg t "$T" '{conversationId:"abc",workspacePaths:["/tmp"],transcriptPath:$t,artifactDirectoryPath:"/tmp/art",stepIdx:1,toolCall:{name:"write_to_file",args:{TargetFile:"/tmp/f.txt",CodeContent:"x"}}}')
  OUT=$(printf '%s' "$PAYLOAD" | bash "$WRAPPER" 2>/dev/null)
  DECISION=$(printf '%s' "$OUT" | jq -r '.decision')
  REASON=$(printf '%s' "$OUT" | jq -r '.reason // ""')
}

# Replace the canonical check with a stand-in script body ($1).
stand_in() {
  printf '#!/bin/sh\n%s\n' "$1" > "$ROOT/bin/pre-edit-check.sh"
  chmod +x "$ROOT/bin/pre-edit-check.sh"
}

@test "D8 (a): unmarked edit is denied with the check's reason" {
  make_transcript "no marker here"
  run_wrapper
  [ "$DECISION" = "deny" ]
  # The check's own deny text, not a wrapper fail-closed reason (which a broken parse would also give).
  [[ "$REASON" == *"compliance block missing"* ]]
}

@test "D8 (b): marked edit is allowed" {
  make_transcript "[Rule 22] Low Impact — probe"
  run_wrapper
  [ "$DECISION" = "allow" ]
}

@test "D8 (c): a check exiting non-zero is denied (fail closed)" {
  make_transcript "x"
  stand_in 'cat >/dev/null; exit 3'
  run_wrapper
  [ "$DECISION" = "deny" ]
}

@test "D8 (d): non-JSON stdout is denied (fail closed)" {
  make_transcript "x"
  stand_in 'cat >/dev/null; echo "this is not json"; exit 0'
  run_wrapper
  [ "$DECISION" = "deny" ]
}

@test "D8 (e): a systemMessage on stdout is allowed with that message as the reason" {
  make_transcript "x"
  stand_in 'cat >/dev/null; echo "{\"systemMessage\":\"could not verify\"}"; exit 0'
  run_wrapper
  [ "$DECISION" = "allow" ]
  [ "$REASON" = "could not verify" ]
}

@test "D8 (f): stderr noise from the check does not change a marked edit" {
  make_transcript "[Rule 22] Low Impact — probe"
  mv "$ROOT/bin/pre-edit-check.sh" "$ROOT/bin/real-check.sh"
  stand_in 'echo "noise on stderr" >&2; exec "$(dirname "$0")/real-check.sh"'
  run_wrapper
  [ "$DECISION" = "allow" ]
  [ "$REASON" = "" ]
}

@test "D8 (g): valid JSON that is not an object is denied (fail closed)" {
  make_transcript "x"
  stand_in 'cat >/dev/null; echo "\"x\""; exit 0'
  run_wrapper
  [ "$DECISION" = "deny" ]
  [[ "$REASON" == *"not a JSON object"* ]]
  stand_in 'cat >/dev/null; echo 42; exit 0'
  run_wrapper
  [ "$DECISION" = "deny" ]
  [[ "$REASON" == *"not a JSON object"* ]]
}

@test "D8 (h): more than one JSON value on stdout is denied (fail closed)" {
  make_transcript "x"
  stand_in 'cat >/dev/null; echo "\"x\""; echo "{}"; exit 0'
  run_wrapper
  [ "$DECISION" = "deny" ]
  [[ "$REASON" == *"not a JSON object"* ]]
  stand_in 'cat >/dev/null; echo "{}"; echo "{}"; exit 0'
  run_wrapper
  [ "$DECISION" = "deny" ]
  [[ "$REASON" == *"not a JSON object"* ]]
}
