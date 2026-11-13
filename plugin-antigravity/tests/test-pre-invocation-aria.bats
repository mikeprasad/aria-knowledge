#!/usr/bin/env bats

setup() {
  export HOME="${BATS_TMPDIR}"
  WRAPPER="${BATS_TEST_DIRNAME}/../bin/antigravity/pre-invocation-aria.sh"
  CACHE_DIR="$HOME/.gemini/antigravity"
  CACHE_FILE="$CACHE_DIR/.last-transcript-path"
  LOG_FILE="$CACHE_DIR/aria-knowledge-scope-check.log"
  mkdir -p "$CACHE_DIR" 2>/dev/null || true
  # One fresh scratch dir per test. TMPDIR points inside it, so nothing this test runs (the hook's
  # mktemp scratch included) writes the user's real TMPDIR.
  SURF="$(mktemp -d "${BATS_TMPDIR}/ag-surf.XXXXXX")"
  export TMPDIR="$SURF/tmp"; mkdir -p "$TMPDIR"
  # The hook's /tmp sweeps reach the real /tmp (they start at "/tmp/"); every test sweeps a scratch
  # dir instead (KT_TMP_SWEEP_ROOT is the test-only override).
  export KT_TMP_SWEEP_ROOT="$SURF/sweep-tmp"; mkdir -p "$KT_TMP_SWEEP_ROOT"
  # 2.58.0: hook state resolves under KT_STATE_BASE, never in the user's real state directory. The base
  # lives in this test's mktemp dir (SURF, under $TMPDIR), which teardown removes.
  export KT_STATE_BASE="$SURF/state-base"; mkdir -p "$KT_STATE_BASE"
  # Responsibility 4's state — the session ledger, the surfaced / logged / model markers, the config
  # cache and the debug log — lives in the private state dir (2.58.0; KT_SURFACE_CACHE_DIR is retired).
  # Created here, mode 700 as the resolver requires, so a test can plant in it before the hook runs.
  SD="$KT_STATE_BASE/aria-knowledge-$(id -u)"; mkdir -m 700 "$SD"
  HOOKLOG="$SD/aria-surface-hook.log"
  FIXTURE="${BATS_TEST_DIRNAME}/fixtures/transcript-user-input.jsonl"
  # Every conversation id carries RUN_ID (pre-2.58.0 hooks wrote the ledger to /tmp; see teardown).
  RUN_ID="agpi$$t${BATS_TEST_NUMBER}x$(od -An -N4 -tx4 /dev/urandom 2>/dev/null | tr -d ' ')"
}

teardown() {
  rm -rf "$CACHE_DIR" "$SURF" 2>/dev/null || true
  # Pre-2.58.0 hooks wrote the ledger to the real /tmp; kept so a run against an older tree cleans up.
  rm -f /tmp/aria-active-"${RUN_ID}"* 2>/dev/null || true
}

# --- Responsibility 4 helpers (spec D4: rank the newest USER_INPUT in code) ---------

# A knowledge folder holding the shared surfacing fixture index, and an Antigravity
# config pointing at it with active surfacing on.
r4_configure() {
  KF="$SURF/kf"
  mkdir -p "$KF"
  cp "${BATS_TEST_DIRNAME}/../../tests/repros/fixtures/surfacing/index.md" "$KF/index.md"
  cat > "$CACHE_DIR/aria-knowledge.local.md" <<CFG
---
knowledge_folder: $KF
active_knowledge_surfacing: true
projects_enabled: true
projects_list: proj-a:proj-a,proj-b:proj-b,proj-c:proj-c
---
CFG
}

# r4_payload CONV TRANSCRIPT INVOCATION [MODEL] — a PreInvocation payload on $SURF/in.
r4_payload() {
  if [ -n "${4:-}" ]; then
    jq -cn --arg c "$1" --arg t "$2" --argjson n "$3" --arg m "$4" \
      '{conversationId:$c, workspacePaths:["/tmp"], transcriptPath:$t, artifactDirectoryPath:"/tmp/art",
        invocationNum:$n, initialNumSteps:5, modelName:$m}' > "$SURF/in"
  else
    jq -cn --arg c "$1" --arg t "$2" --argjson n "$3" \
      '{conversationId:$c, workspacePaths:["/tmp"], transcriptPath:$t, artifactDirectoryPath:"/tmp/art",
        invocationNum:$n, initialNumSteps:5}' > "$SURF/in"
  fi
}

r4_run() { bash "$WRAPPER" < "$SURF/in" > "$SURF/out" 2>/dev/null; }
# The R4 step (if any): the ephemeralMessage that starts with "ARIA ACTIVE —".
r4_active() { jq -r '(.injectSteps // [])[] | .ephemeralMessage | select(startswith("ARIA ACTIVE —"))' "$SURF/out" 2>/dev/null; }
r4_user_input() { # STEP CONTENT — one USER_INPUT record in the measured schema
  jq -cn --argjson s "$1" --arg c "$2" \
    '{type:"USER_INPUT", content:$c, source:"USER_EXPLICIT", status:"DONE", step_index:$s, created_at:"2026-11-08T00:01:00Z"}'
}

# r4_wrapped_bin — a copy of the plugin's bin/ (hook + libs from the CURRENT tree) at
# $SURF/plug, whose kt_index_match (a) appends one line to $KT_TEST_MATCH_COUNTER when set,
# and (b) plants a symlink $KT_TEST_PLANT_LINK → $KT_TEST_PLANT_TARGET when set — i.e.
# AFTER the hook's early state check and BEFORE it records the step, which is the only
# way a static test can put a link where the hook is about to write. Sets H to the hook.
r4_wrapped_bin() {
  P="$SURF/plug"
  mkdir -p "$P/bin/antigravity"
  cp "${BATS_TEST_DIRNAME}"/../bin/antigravity/*.sh "$P/bin/antigravity/"
  cp "${BATS_TEST_DIRNAME}/../bin/config.sh" "${BATS_TEST_DIRNAME}/../bin/lib-index-match.sh" \
     "${BATS_TEST_DIRNAME}/../bin/lib-prompt-surface.sh" \
     "${BATS_TEST_DIRNAME}/../bin/lib-tracked-artifacts.sh" \
     "${BATS_TEST_DIRNAME}/../bin/lib-state-key.sh" "$P/bin/"
  cat >> "$P/bin/lib-index-match.sh" <<'WRAP'
eval "_r4_counted_$(declare -f kt_index_match)"
kt_index_match() {
  [ -n "${KT_TEST_MATCH_COUNTER:-}" ] && printf 'x\n' >> "$KT_TEST_MATCH_COUNTER"
  [ -n "${KT_TEST_PLANT_LINK:-}" ] && ln -s "$KT_TEST_PLANT_TARGET" "$KT_TEST_PLANT_LINK" 2>/dev/null
  [ -n "${KT_TEST_PLANT_FIFO:-}" ] && mkfifo "$KT_TEST_PLANT_FIFO" 2>/dev/null
  _r4_counted_kt_index_match "$@"
}
WRAP
  H="$P/bin/antigravity/pre-invocation-aria.sh"
}

# r4_run_bounded SECONDS CMD... — runs CMD with stdin $SURF/in and stdout $SURF/out in the
# background; sets BOUNDED=ok if it finished within SECONDS, else BOUNDED=hung. On a hang
# every FIFO under $SURF is opened read-write (which never blocks) to release a writer
# stuck opening it, then the run is killed — so a hang fails the arm instead of the suite.
r4_run_bounded() {
  local secs=$1; shift
  "$@" < "$SURF/in" > "$SURF/out" 2>/dev/null &
  local p=$! i=0
  BOUNDED=ok
  while kill -0 "$p" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt $((secs * 10)) ]; then
      BOUNDED=hung
      for f in "$SURF"/* "$SURF"/.??* "$SD"/* "$SD"/.??*; do
        [ -p "$f" ] && { exec 9<>"$f"; exec 9>&-; }
      done
      kill "$p" 2>/dev/null
      break
    fi
    sleep 0.1
  done
  wait "$p" 2>/dev/null || true
}

# r4_farm — $SURF/farm: every tool in the system bin dirs except jq.
r4_farm() {
  FARM="$SURF/farm"; mkdir -p "$FARM"
  for d in /usr/bin /bin /usr/sbin /sbin; do
    for b in "$d"/*; do
      n=${b##*/}
      [ "$n" = jq ] && continue
      [ -e "$FARM/$n" ] || ln -s "$b" "$FARM/$n" 2>/dev/null || true
    done
  done
  ! (PATH="$FARM"; command -v jq >/dev/null 2>&1) || false
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

# --- Responsibility 4: the newest USER_INPUT, ranked in code (spec D4, AC4) ----------
# `[[ ]]` and `! cmd` do not trip errexit on every bash, so assertions use [ ] / grep.
has()   { printf '%s' "$1" | grep -qF -- "$2"; }
hasnt() { ! printf '%s' "$1" | grep -qF -- "$2"; }
logged() { grep -q -- " antigravity $1\$" "$HOOKLOG" 2>/dev/null; }

@test "R4 inject_once_per_user_input: newest USER_INPUT only, once per step_index" {
  r4_configure
  cp "$FIXTURE" "$SURF/t.jsonl"
  C="${RUN_ID}A"
  r4_payload "$C" "$SURF/t.jsonl" 3
  r4_run
  m=$(r4_active)
  has "$m" "$KF/projects/proj-b/deposits.md"
  hasnt "$m" "projects/proj-a/hooks.md"        # the OLDER USER_INPUT is not the one ranked
  grep -qxF 'projects/proj-b/deposits.md' "$SD/aria-active-$C"
  grep -qxF '4' "$SD/aria-ag-surfaced-$C"
  # Same newest USER_INPUT on the next model call: nothing.
  r4_run
  [ "$(cat "$SURF/out")" = "{}" ]
  # With the ledger gone, the state file alone still holds it to once.
  rm -f "$SD/aria-active-$C"
  r4_run
  [ "$(cat "$SURF/out")" = "{}" ]
}

@test "R4 new_user_input_injects_again: a newer USER_INPUT step is ranked and injected" {
  r4_configure
  cp "$FIXTURE" "$SURF/t.jsonl"
  C="${RUN_ID}B"
  r4_payload "$C" "$SURF/t.jsonl" 3
  r4_run
  has "$(r4_active)" "projects/proj-b/deposits.md"
  r4_user_input 7 "webhooks retry for proj-a hooks" >> "$SURF/t.jsonl"
  r4_run
  has "$(r4_active)" "$KF/projects/proj-a/hooks.md"
  grep -qxF '4' "$SD/aria-ag-surfaced-$C"
  grep -qxF '7' "$SD/aria-ag-surfaced-$C"
}

@test "R4 no_user_input_silent: no USER_INPUT → {} and no log line; fires once one appears" {
  r4_configure
  C="${RUN_ID}N"
  printf '%s\n' \
    '{"type":"SYSTEM_MESSAGE","content":"Session started.","source":"SYSTEM","status":"DONE","step_index":0,"created_at":"2026-11-08T00:00:00Z"}' \
    '{"type":"PLANNER_RESPONSE","content":"payments for proj-b deposits","source":"MODEL","status":"DONE","step_index":1,"created_at":"2026-11-08T00:00:01Z"}' \
    > "$SURF/t.jsonl"
  r4_payload "$C" "$SURF/t.jsonl" 3
  r4_run
  [ "$(cat "$SURF/out")" = "{}" ]
  [ "$(grep -c ' antigravity ' "$HOOKLOG" 2>/dev/null || true)" = "0" ] || [ ! -e "$HOOKLOG" ]
  # Positive control in the same arm: the hook is alive and reads this transcript.
  r4_user_input 2 "how do we handle payments for proj-b deposits" >> "$SURF/t.jsonl"
  r4_run
  has "$(r4_active)" "projects/proj-b/deposits.md"
}

@test "R4 malformed_line_ignored: bad lines are skipped, the valid USER_INPUT still ranks" {
  r4_configure
  cp "$FIXTURE" "$SURF/t.jsonl"
  printf '%s\n' 'not json {' '[1,2]' '"just a string"' \
    '{"type":"USER_INPUT","content":42,"source":"USER_EXPLICIT","step_index":9}' \
    '{"type":"USER_INPUT","content":"webhooks retry for proj-a hooks","step_index":10' \
    >> "$SURF/t.jsonl"
  C="${RUN_ID}M"
  r4_payload "$C" "$SURF/t.jsonl" 3
  r4_run
  m=$(r4_active)
  has "$m" "projects/proj-b/deposits.md"
  hasnt "$m" "projects/proj-a/hooks.md"
  grep -qxF '4' "$SD/aria-ag-surfaced-$C"
}

@test "R4 no_transcript_logged: missing transcript → debug-log line; other outputs unchanged" {
  r4_configure
  C="${RUN_ID}T"
  printf '%s\n' "--- 2026-05-24T08:00:00Z stepIdx=5 error=none" "[Rule 22 Scope] PASS — sample entry" > "$LOG_FILE"
  r4_payload "$C" "$SURF/missing.jsonl" 3
  r4_run
  [ "$(jq '.injectSteps | length' "$SURF/out")" = "1" ]
  jq -r '.injectSteps[0].ephemeralMessage' "$SURF/out" | grep -q 'Rule 22 scope-check feedback'
  logged 'transcript unreadable'
  r4_payload "$C" "" 3
  r4_run
  [ "$(cat "$SURF/out")" = "{}" ]
  logged 'transcript no-transcript-path'
}

@test "R4 existing_responsibilities_unchanged: session-start + drain byte-identical, R4 step appended last" {
  r4_configure
  cp "$FIXTURE" "$SURF/t.jsonl"
  # A: R4 has nothing to read. Both runs are ONE conversation: the session-start message states that
  # conversation's ledger (ARIA CONFIG — ledger=…, 2.58.0), which differs between two conversations.
  printf '%s\n' "--- 2026-05-24T08:00:00Z stepIdx=5 error=none" "[Rule 22 Scope] PASS — sample entry" > "$LOG_FILE"
  r4_payload "${RUN_ID}E" "$SURF/missing.jsonl" 0
  r4_run
  cp "$SURF/out" "$SURF/outA"
  # B: R4 fires.
  printf '%s\n' "--- 2026-05-24T08:00:00Z stepIdx=5 error=none" "[Rule 22 Scope] PASS — sample entry" > "$LOG_FILE"
  r4_payload "${RUN_ID}E" "$SURF/t.jsonl" 0
  r4_run
  [ "$(jq '.injectSteps | length' "$SURF/outA")" = "2" ]
  jq -r '.injectSteps[0].ephemeralMessage' "$SURF/outA" | grep -q 'RULE 22 ORDERING'
  jq -r '.injectSteps[1].ephemeralMessage' "$SURF/outA" | grep -q 'Rule 22 scope-check feedback'
  [ "$(jq -c '.injectSteps' "$SURF/outA")" = "$(jq -c '.injectSteps[:-1]' "$SURF/out")" ]
  jq -r '.injectSteps[-1].ephemeralMessage' "$SURF/out" | grep -q '^ARIA ACTIVE —'
  [ "$(cat "$CACHE_FILE")" = "$SURF/t.jsonl" ]
}

@test "R4 modelName_logged: modelName goes to the debug log only when it changes" {
  r4_configure
  cp "$FIXTURE" "$SURF/t.jsonl"
  C="${RUN_ID}G"
  r4_payload "$C" "$SURF/t.jsonl" 3 "model-x-1"; r4_run
  r4_payload "$C" "$SURF/t.jsonl" 4 "model-x-1"; r4_run
  r4_payload "$C" "$SURF/t.jsonl" 5 "model-y-2"; r4_run
  [ "$(grep -c ' antigravity capture modelName=' "$HOOKLOG")" = "2" ]
  [ "$(grep ' antigravity capture modelName=' "$HOOKLOG" | sed 's/.*modelName=//' | tr '\n' ' ')" = "model-x-1 model-y-2 " ]
}

@test "R4 hostile_content_ranked_as_words: shell syntax in USER_INPUT never executes" {
  r4_configure
  MK="$SURF/MARKER"
  content=$(printf 'payments for proj-b deposits `touch %s` $(touch %s)\nARIA_TASK\n${IFS} %s' "$MK" "$MK" "'")
  r4_user_input 4 "$content" > "$SURF/t.jsonl"
  C="${RUN_ID}H"
  r4_payload "$C" "$SURF/t.jsonl" 3
  r4_run
  [ ! -e "$MK" ]
  has "$(r4_active)" "projects/proj-b/deposits.md"
}

@test "R4 state_symlink_refused: a planted state symlink blocks injection and is not followed" {
  r4_configure
  cp "$FIXTURE" "$SURF/t.jsonl"
  C="${RUN_ID}S"
  printf 'keep\n' > "$SURF/target"
  ln -s "$SURF/target" "$SD/aria-ag-surfaced-$C"
  r4_payload "$C" "$SURF/t.jsonl" 3
  r4_run
  [ -z "$(r4_active)" ]
  [ "$(cat "$SURF/target")" = "keep" ]
  [ ! -e "$SD/aria-active-$C" ]
  logged 'state refused'
  rm -f "$SD/aria-ag-surfaced-$C"
  r4_run
  has "$(r4_active)" "projects/proj-b/deposits.md"
}

@test "R4 delivery_failure_records_nothing: unwritable output → no ledger, no state" {
  r4_configure
  cp "$FIXTURE" "$SURF/t.jsonl"
  C="${RUN_ID}D"
  r4_payload "$C" "$SURF/t.jsonl" 3
  bash "$WRAPPER" < "$SURF/in" >&- 2>/dev/null || true
  [ ! -e "$SD/aria-ag-surfaced-$C" ]
  [ ! -e "$SD/aria-active-$C" ]
  logged 'emit write-failed'
  r4_run
  has "$(r4_active)" "projects/proj-b/deposits.md"
  grep -qxF '4' "$SD/aria-ag-surfaced-$C"
}

@test "R4 window_is_last_400_lines: a USER_INPUT older than 400 lines is not read" {
  r4_configure
  C="${RUN_ID}W"
  r4_user_input 0 "how do we handle payments for proj-b deposits" > "$SURF/t.jsonl"
  i=1
  while [ "$i" -le 450 ]; do
    printf '{"type":"VIEW_FILE","content":"x","source":"MODEL","status":"DONE","step_index":%d,"created_at":"2026-11-08T00:00:00Z"}\n' "$i"
    i=$((i + 1))
  done >> "$SURF/t.jsonl"
  r4_payload "$C" "$SURF/t.jsonl" 3
  r4_run
  [ "$(cat "$SURF/out")" = "{}" ]
  # The same record inside the window is read.
  { r4_user_input 0 "how do we handle payments for proj-b deposits"; sed -n '1,300p' "$SURF/t.jsonl" | tail -n 299; } > "$SURF/t2.jsonl"
  r4_payload "$C" "$SURF/t2.jsonl" 3
  r4_run
  has "$(r4_active)" "projects/proj-b/deposits.md"
}

@test "R4 schema_miss_logged: records without the measured shape are logged, not injected" {
  r4_configure
  C="${RUN_ID}X"
  printf '%s\n' '{"kind":"USER_INPUT","text":"payments for proj-b deposits"}' '{"foo":1}' > "$SURF/t.jsonl"
  r4_payload "$C" "$SURF/t.jsonl" 3
  r4_run
  [ "$(cat "$SURF/out")" = "{}" ]
  logged 'transcript schema-miss'
  printf '%s\n' '{"type":"USER_INPUT","content":"payments for proj-b deposits","source":"USER_EXPLICIT"}' > "$SURF/t2.jsonl"
  r4_payload "$C" "$SURF/t2.jsonl" 3
  r4_run
  [ "$(cat "$SURF/out")" = "{}" ]
  logged 'transcript no-step-index'
}

@test "R4 conversation_id_sanitised: a path-shaped conversationId names one plain file" {
  r4_configure
  cp "$FIXTURE" "$SURF/t.jsonl"
  mkdir -p "$SURF/sub"
  r4_payload "${RUN_ID}x/../sub/y" "$SURF/t.jsonl" 3
  r4_run
  has "$(r4_active)" "projects/proj-b/deposits.md"
  grep -qxF '4' "$SD/aria-ag-surfaced-${RUN_ID}x..suby"
  grep -qxF 'projects/proj-b/deposits.md' "$SD/aria-active-${RUN_ID}x..suby"
  [ -z "$(ls -A "$SURF/sub")" ]
}

@test "R4 nofire_turn_ranked_once: a decided turn (nofire, nothing-new) is ranked at most once" {
  r4_configure
  # kt_index_match counts its calls: ranking is observed directly, not inferred from an
  # empty output.
  r4_wrapped_bin
  export KT_TEST_MATCH_COUNTER="$SURF/matches"
  ranked() { if [ -f "$KT_TEST_MATCH_COUNTER" ]; then wc -l < "$KT_TEST_MATCH_COUNTER" | tr -d ' '; else echo 0; fi; }
  # nofire: words that match no tag.
  C="${RUN_ID}F"
  r4_user_input 4 "hello there friend" > "$SURF/t.jsonl"
  r4_payload "$C" "$SURF/t.jsonl" 3
  bash "$H" < "$SURF/in" > "$SURF/out" 2>/dev/null
  [ "$(cat "$SURF/out")" = "{}" ]
  [ "$(ranked)" = "1" ]
  bash "$H" < "$SURF/in" > "$SURF/out" 2>/dev/null
  [ "$(cat "$SURF/out")" = "{}" ]
  [ "$(ranked)" = "1" ]
  grep -qxF '4' "$SD/aria-ag-surfaced-$C"
  [ ! -e "$SD/aria-active-$C" ]                 # the ledger records delivered paths only
  # nothing-new: deliver, lose only the state file (the ledger still holds the paths).
  C2="${RUN_ID}Q"
  cp "$FIXTURE" "$SURF/t2.jsonl"
  r4_payload "$C2" "$SURF/t2.jsonl" 3
  bash "$H" < "$SURF/in" > "$SURF/out" 2>/dev/null
  has "$(r4_active)" "projects/proj-b/deposits.md"
  [ "$(ranked)" = "2" ]
  rm -f "$SD/aria-ag-surfaced-$C2"
  bash "$H" < "$SURF/in" > "$SURF/out" 2>/dev/null
  [ "$(cat "$SURF/out")" = "{}" ]
  [ "$(ranked)" = "3" ]
  grep -qxF '4' "$SD/aria-ag-surfaced-$C2"
  bash "$H" < "$SURF/in" > "$SURF/out" 2>/dev/null
  [ "$(cat "$SURF/out")" = "{}" ]
  [ "$(ranked)" = "3" ]
}

@test "R4 unreadable_transcript_logged_once: one log line per conversation and reason" {
  r4_configure
  C="${RUN_ID}U"
  r4_payload "$C" "$SURF/missing.jsonl" 3
  r4_run; r4_run
  [ "$(grep -c ' antigravity transcript unreadable$' "$HOOKLOG")" = "1" ]
  r4_payload "$C" "" 3
  r4_run; r4_run
  [ "$(grep -c ' antigravity transcript no-transcript-path$' "$HOOKLOG")" = "1" ]
  r4_payload "${RUN_ID}V" "$SURF/missing.jsonl" 3
  r4_run
  [ "$(grep -c ' antigravity transcript unreadable$' "$HOOKLOG")" = "2" ]
  # A planted marker link is never created through. Dangling on purpose: `-e` follows a
  # link, so a link to an existing file already reads as "logged" and would prove nothing.
  ln -s "$SURF/planted-target" "$SD/aria-ag-logged-${RUN_ID}W.unreadable"
  r4_payload "${RUN_ID}W" "$SURF/missing.jsonl" 3
  r4_run
  [ ! -e "$SURF/planted-target" ]
  [ "$(grep -c ' antigravity transcript unreadable$' "$HOOKLOG")" = "3" ]
}

@test "R4 stale_state_pruned_on_first_call: state files older than 24 h go on invocationNum 0" {
  r4_configure
  printf '4\n' > "$SD/aria-ag-surfaced-${RUN_ID}old"
  : > "$SD/aria-ag-logged-${RUN_ID}old.unreadable"
  touch -t 202001010000 "$SD/aria-ag-surfaced-${RUN_ID}old" "$SD/aria-ag-logged-${RUN_ID}old.unreadable"
  printf '4\n' > "$SD/aria-ag-surfaced-${RUN_ID}new"
  r4_payload "${RUN_ID}P" "$SURF/missing.jsonl" 0
  r4_run
  [ ! -e "$SD/aria-ag-surfaced-${RUN_ID}old" ]
  [ ! -e "$SD/aria-ag-logged-${RUN_ID}old.unreadable" ]
  [ -e "$SD/aria-ag-surfaced-${RUN_ID}new" ]
}

@test "R4 lib_missing_logged: without lib-prompt-surface.sh → logged, output unchanged" {
  r4_configure
  cp "$FIXTURE" "$SURF/t.jsonl"
  P="$SURF/plug"
  mkdir -p "$P/bin/antigravity"
  cp "${BATS_TEST_DIRNAME}"/../bin/antigravity/*.sh "$P/bin/antigravity/"
  # The debug-log write uses the shared safe create in lib-tracked-artifacts.sh (spec §5), which
  # ships beside it; only lib-prompt-surface.sh is missing here.
  cp "${BATS_TEST_DIRNAME}/../bin/config.sh" "${BATS_TEST_DIRNAME}/../bin/lib-index-match.sh" \
     "${BATS_TEST_DIRNAME}/../bin/lib-tracked-artifacts.sh" "${BATS_TEST_DIRNAME}/../bin/lib-state-key.sh" "$P/bin/"
  r4_payload "${RUN_ID}L" "$SURF/t.jsonl" 3
  bash "$P/bin/antigravity/pre-invocation-aria.sh" < "$SURF/in" > "$SURF/out" 2>/dev/null
  [ "$(cat "$SURF/out")" = "{}" ]
  logged 'surface lib-missing'
}

@test "R4 model_file_link_refused: a planted model-file link is replaced, never written through" {
  r4_configure
  cp "$FIXTURE" "$SURF/t.jsonl"
  printf 'keep\n' > "$SURF/sentinel"
  ln -s "$SURF/sentinel" "$SD/aria-ag-model.last"
  r4_payload "${RUN_ID}ML" "$SURF/t.jsonl" 3 "model-z-9"
  r4_run
  [ "$(cat "$SURF/sentinel")" = "keep" ]
  logged 'capture modelName=model-z-9'
  [ ! -L "$SD/aria-ag-model.last" ]
  [ "$(cat "$SD/aria-ag-model.last")" = "model-z-9" ]
}

@test "R4 state_dangling_link_refused: a link planted at the state path mid-run is not written through" {
  r4_configure
  r4_wrapped_bin
  C="${RUN_ID}SD"
  r4_user_input 4 "hello there friend" > "$SURF/t.jsonl"   # nofire: the hook records the step
  r4_payload "$C" "$SURF/t.jsonl" 3
  KT_TEST_PLANT_LINK="$SD/aria-ag-surfaced-$C" KT_TEST_PLANT_TARGET="$SURF/planted-state" \
    bash "$H" < "$SURF/in" > "$SURF/out" 2>/dev/null
  [ "$(cat "$SURF/out")" = "{}" ]
  [ -L "$SD/aria-ag-surfaced-$C" ]        # instrument check: the link was planted
  [ ! -e "$SURF/planted-state" ]            # never created through the link
  logged 'state refused'                    # and the turn was not recorded
}

@test "R4 marker_existing_link_refused: a marker linked to an existing file is never written; the line still logs" {
  r4_configure
  printf 'keep\n' > "$SURF/sentinel"
  C="${RUN_ID}MK"
  ln -s "$SURF/sentinel" "$SD/aria-ag-logged-$C.unreadable"
  r4_payload "$C" "$SURF/missing.jsonl" 3
  r4_run; r4_run
  [ "$(cat "$SURF/sentinel")" = "keep" ]
  [ "$(grep -c ' antigravity transcript unreadable$' "$HOOKLOG")" = "2" ]
}

@test "R4 foreign_marker_does_not_silence: only a regular marker file of ours counts as logged" {
  r4_configure
  # A non-regular marker (a directory of ours) does not silence the line.
  C="${RUN_ID}FD"
  mkdir "$SD/aria-ag-logged-$C.unreadable"
  r4_payload "$C" "$SURF/missing.jsonl" 3
  r4_run
  [ "$(grep -c ' antigravity transcript unreadable$' "$HOOKLOG")" = "1" ]
  # A marker owned by someone else does not either: a hard link to a root-owned file on
  # the same filesystem (macOS permits it; skipped where the OS refuses).
  C2="${RUN_ID}FM"
  m="$SD/aria-ag-logged-$C2.unreadable"
  for f in /private/var/log/install.log /private/var/log/system.log /etc/passwd; do
    ln "$f" "$m" 2>/dev/null && break
  done
  [ -f "$m" ] && [ ! -O "$m" ] || skip "cannot create a non-owned file in $SURF on this OS"
  r4_payload "$C2" "$SURF/missing.jsonl" 3
  r4_run
  [ "$(grep -c ' antigravity transcript unreadable$' "$HOOKLOG")" = "2" ]
}

@test "R4 config_error_logged_once: an invalid config is logged once per conversation, no ranking" {
  r4_configure
  cat > "$CACHE_DIR/aria-knowledge.local.md" <<CFG
---
knowledge_folder: relative/kf
active_knowledge_surfacing: true
---
CFG
  cp "$FIXTURE" "$SURF/t.jsonl"
  r4_payload "${RUN_ID}CE" "$SURF/t.jsonl" 3
  r4_run; r4_run
  [ "$(cat "$SURF/out")" = "{}" ]
  [ "$(grep -c ' antigravity surface config$' "$HOOKLOG")" = "1" ]
}

@test "R4 debug_log_link_refused: the hook's own log writes never follow a link" {
  r4_farm
  r4_payload "${RUN_ID}DL" "$SURF/missing.jsonl" 3
  # jq missing (the header's write): a log linked to an existing file is not appended to.
  printf 'keep\n' > "$SURF/sentinel"
  ln -s "$SURF/sentinel" "$HOOKLOG"
  PATH="$FARM" /bin/bash "$WRAPPER" < "$SURF/in" > "$SURF/out" 2>/dev/null || true
  grep -q '"decision":"deny"' "$SURF/out"
  [ "$(cat "$SURF/sentinel")" = "keep" ]
  # A dangling log link: its target is never created.
  rm -f "$HOOKLOG"
  ln -s "$SURF/planted-log" "$HOOKLOG"
  PATH="$FARM" /bin/bash "$WRAPPER" < "$SURF/in" > "$SURF/out" 2>/dev/null || true
  [ ! -e "$SURF/planted-log" ]
  # lib missing (responsibility 4's write): same.
  P="$SURF/plug"
  mkdir -p "$P/bin/antigravity"
  cp "${BATS_TEST_DIRNAME}"/../bin/antigravity/*.sh "$P/bin/antigravity/"
  cp "${BATS_TEST_DIRNAME}/../bin/lib-state-key.sh" "$P/bin/"   # the log name resolves; only the libs are gone
  bash "$P/bin/antigravity/pre-invocation-aria.sh" < "$SURF/in" > "$SURF/out" 2>/dev/null
  [ ! -e "$SURF/planted-log" ]
}

@test "R4 fifo_at_create_does_not_hang: a FIFO at a name the hook creates never blocks it" {
  r4_configure
  r4_wrapped_bin
  # State file: a FIFO planted mid-run (after the early state check), on a nofire turn,
  # which records the step.
  C="${RUN_ID}FS"
  r4_user_input 4 "hello there friend" > "$SURF/t.jsonl"
  r4_payload "$C" "$SURF/t.jsonl" 3
  r4_run_bounded 5 env KT_TEST_PLANT_FIFO="$SD/aria-ag-surfaced-$C" bash "$H"
  [ "$BOUNDED" = ok ]
  [ "$(cat "$SURF/out")" = "{}" ]
  [ -p "$SD/aria-ag-surfaced-$C" ]          # instrument check: the FIFO was planted
  logged 'state refused'                      # and nothing was recorded through it
  # Log-once marker: a FIFO planted before the run.
  C2="${RUN_ID}FK"
  mkfifo "$SD/aria-ag-logged-$C2.unreadable"
  r4_payload "$C2" "$SURF/missing.jsonl" 3
  r4_run_bounded 5 bash "$WRAPPER"
  [ "$BOUNDED" = ok ]
  [ "$(cat "$SURF/out")" = "{}" ]
  [ -p "$SD/aria-ag-logged-$C2.unreadable" ]
  logged 'transcript unreadable'
  # Debug log, written before the lib loads (jq missing): a FIFO planted before the run.
  r4_farm
  rm -f "$HOOKLOG"
  mkfifo "$HOOKLOG"
  r4_run_bounded 5 env PATH="$FARM" /bin/bash "$WRAPPER"
  [ "$BOUNDED" = ok ]
  grep -q '"decision":"deny"' "$SURF/out"
  [ -p "$HOOKLOG" ]
  # Every failed create removed its temp.
  [ -z "$(ls -A "$SD" | grep '^\.aria-new\.' || true)" ]
}

@test "R4 marker_dir_link_not_entered: a create name that is a symlink to a directory gets nothing inside it" {
  r4_configure
  mkdir "$SURF/elsewhere"
  C="${RUN_ID}DK"
  ln -s "$SURF/elsewhere" "$SD/aria-ag-logged-$C.unreadable"
  r4_payload "$C" "$SURF/missing.jsonl" 3
  r4_run
  [ -z "$(ls -A "$SURF/elsewhere")" ]
  logged 'transcript unreadable'
}

@test "R4 steady_state_no_create_forks: recording into an existing state file makes no create call" {
  r4_configure
  # `link` is called only by the hook's create helper, so a counting shim on PATH counts
  # create attempts exactly (mktemp is also used by the matcher and the config cache).
  mkdir "$SURF/shim"
  real=$(command -v link)
  printf '#!/bin/sh\nprintf "x\\n" >> "%s"\nexec "%s" "$@"\n' "$SURF/links" "$real" > "$SURF/shim/link"
  chmod +x "$SURF/shim/link"
  links() { if [ -f "$SURF/links" ]; then wc -l < "$SURF/links" | tr -d ' '; else echo 0; fi; }
  C="${RUN_ID}SS"
  r4_user_input 4 "hello there friend" > "$SURF/t.jsonl"            # nofire: records step 4
  r4_payload "$C" "$SURF/t.jsonl" 3
  env PATH="$SURF/shim:$PATH" bash "$WRAPPER" < "$SURF/in" > "$SURF/out" 2>/dev/null
  [ "$(links)" = "1" ]                         # instrument check: the first record created the file
  grep -qxF '4' "$SD/aria-ag-surfaced-$C"
  r4_user_input 5 "good morning friend" >> "$SURF/t.jsonl"           # nofire: records step 5
  env PATH="$SURF/shim:$PATH" bash "$WRAPPER" < "$SURF/in" > "$SURF/out" 2>/dev/null
  grep -qxF '5' "$SD/aria-ag-surfaced-$C"
  [ "$(links)" = "1" ]                         # the second record made no create call
}

@test "R4 plant_in_create_window_is_harmless: a name planted between the fast path and link is never opened or entered" {
  r4_configure
  # A mktemp shim plants at the create name when it is asked for the helper's temp, i.e.
  # AFTER kt_create_new's existence test and BEFORE its link call — the only window left.
  mkdir "$SURF/shim" "$SURF/elsewhere"
  real=$(command -v mktemp)
  cat > "$SURF/shim/mktemp" <<SHIM
#!/bin/sh
case "\$*" in
  *.aria-new.*)
    if [ -n "\${KT_TEST_WINDOW_NAME:-}" ] && [ ! -e "\$KT_TEST_WINDOW_NAME" ] && [ ! -L "\$KT_TEST_WINDOW_NAME" ]; then
      case "\${KT_TEST_WINDOW_PLANT:-}" in
        fifo) mkfifo "\$KT_TEST_WINDOW_NAME" ;;
        dirlink) ln -s "$SURF/elsewhere" "\$KT_TEST_WINDOW_NAME" ;;
      esac
    fi ;;
esac
exec "$real" "\$@"
SHIM
  chmod +x "$SURF/shim/mktemp"
  r4_user_input 4 "hello there friend" > "$SURF/t.jsonl"            # nofire: records the step
  # FIFO in the window: no hang, nothing recorded.
  C="${RUN_ID}WF"
  r4_payload "$C" "$SURF/t.jsonl" 3
  r4_run_bounded 5 env PATH="$SURF/shim:$PATH" KT_TEST_WINDOW_PLANT=fifo \
    KT_TEST_WINDOW_NAME="$SD/aria-ag-surfaced-$C" bash "$WRAPPER"
  [ "$BOUNDED" = ok ]
  [ -p "$SD/aria-ag-surfaced-$C" ]           # instrument check: planted in the window
  # Symlink to a directory in the window: nothing is created inside the directory.
  C2="${RUN_ID}WD"
  r4_payload "$C2" "$SURF/t.jsonl" 3
  r4_run_bounded 5 env PATH="$SURF/shim:$PATH" KT_TEST_WINDOW_PLANT=dirlink \
    KT_TEST_WINDOW_NAME="$SD/aria-ag-surfaced-$C2" bash "$WRAPPER"
  [ "$BOUNDED" = ok ]
  [ -L "$SD/aria-ag-surfaced-$C2" ]
  [ -z "$(ls -A "$SURF/elsewhere")" ]
  [ "$(grep -c ' antigravity state refused$' "$HOOKLOG")" = "2" ]
  [ -z "$(ls -A "$SD" | grep '^\.aria-new\.' || true)" ]
}

@test "R4 orphan_new_temp_pruned: create temps older than 24 h go on invocationNum 0" {
  r4_configure
  : > "$SD/.aria-new.OLD123"
  touch -t 202001010000 "$SD/.aria-new.OLD123"
  : > "$SD/.aria-new.NEW123"
  r4_payload "${RUN_ID}O" "$SURF/missing.jsonl" 0
  r4_run
  [ ! -e "$SD/.aria-new.OLD123" ]
  [ -e "$SD/.aria-new.NEW123" ]
}

@test "R4 tmp_sweeps_reach_a_symlinked_root: stale ledgers and create temps in /tmp go on invocationNum 0" {
  # The session ledgers and their create temps live in /tmp. On macOS /tmp is a symlink, which find
  # does not follow as a start point unless it is written with a trailing slash. The sweep root is
  # a symlink to a scratch dir here (KT_TMP_SWEEP_ROOT, test-only), so the real /tmp is untouched.
  r4_configure
  mkdir -p "$SURF/realtmp"; ln -s "$SURF/realtmp" "$SURF/tmplink"
  export KT_TMP_SWEEP_ROOT="$SURF/tmplink"
  for n in "aria-active-${RUN_ID}OLD" "aria-session-inprogress-${RUN_ID}OLD" ".aria-new.${RUN_ID}OLD"; do
    : > "$SURF/realtmp/$n"; touch -t 202001010000 "$SURF/realtmp/$n"
  done
  : > "$SURF/realtmp/aria-active-${RUN_ID}NEW"
  r4_payload "${RUN_ID}T" "$SURF/missing.jsonl" 0
  r4_run
  [ ! -e "$SURF/realtmp/aria-active-${RUN_ID}OLD" ]
  [ ! -e "$SURF/realtmp/aria-session-inprogress-${RUN_ID}OLD" ]
  [ ! -e "$SURF/realtmp/.aria-new.${RUN_ID}OLD" ]
  [ -e "$SURF/realtmp/aria-active-${RUN_ID}NEW" ]
}

@test "R4 legacy_ag_new_temp_still_pruned: a pre-2.58.0 .aria-ag-new.* leftover still goes on invocationNum 0" {
  r4_configure
  : > "$SD/.aria-ag-new.OLD123"
  touch -t 202001010000 "$SD/.aria-ag-new.OLD123"
  : > "$SD/.aria-ag-new.NEW123"
  r4_payload "${RUN_ID}L" "$SURF/missing.jsonl" 0
  r4_run
  [ ! -e "$SD/.aria-ag-new.OLD123" ]
  [ -e "$SD/.aria-ag-new.NEW123" ]
}

@test "R4 create_helper_is_shared: the hook uses the libraries' kt_create_new, sourced before its first log write" {
  [ "$(grep -c 'ag_create_new' "$WRAPPER")" = "0" ]
  src=$(grep -n '^[^#]*\. .*lib-tracked-artifacts\.sh' "$WRAPPER" | head -1 | cut -d: -f1)
  first=$(grep -n '^[^#]*ag_debug_log [a-z]' "$WRAPPER" | grep -v 'ag_debug_log()' | head -1 | cut -d: -f1)
  [ -n "$src" ] && [ -n "$first" ]
  [ "$src" -lt "$first" ]
}

@test "R4 jq_missing_logged: no jq → the existing deny output, plus one debug-log line" {
  r4_farm
  r4_payload "${RUN_ID}J" "$SURF/missing.jsonl" 3
  rc=0
  PATH="$FARM" /bin/bash "$WRAPPER" < "$SURF/in" > "$SURF/out" 2>/dev/null || rc=$?
  [ "$rc" = "1" ]
  grep -q '"decision":"deny"' "$SURF/out"
  logged 'input jq-missing'
}

# --- 2.58.0 private state dir (spec D3, D4) ---------------------------------------------------------

@test "no state dir: responsibility 4 injects nothing and logs nothing" {
  r4_configure
  cp "$FIXTURE" "$SURF/t.jsonl"
  # No state dir: a regular file at the state-dir name (deterministic refusal, "not a directory").
  export KT_STATE_BASE="$SURF/broken-base"; mkdir -p "$KT_STATE_BASE"; : > "$KT_STATE_BASE/aria-knowledge-$(id -u)"
  C="${RUN_ID}NS"
  r4_payload "$C" "$SURF/t.jsonl" 3 "model-n-1"
  r4_run
  [ "$(cat "$SURF/out")" = "{}" ]
  r4_payload "${C}U" "$SURF/missing.jsonl" 3           # would be logged (once) with a state dir
  r4_run
  [ "$(cat "$SURF/out")" = "{}" ]
  # Nothing written anywhere: no ledger, step record, log-once marker, model file or debug log.
  [ -z "$(find "$SURF" \( -name 'aria-active-*' -o -name 'aria-ag-*' -o -name 'aria-surface-hook.log' \) -print | head -1)" ]
  [ ! -e "/tmp/aria-active-$C" ]
  # Positive control in the same arm: the same payload with a healthy state dir injects.
  export KT_STATE_BASE="$SURF/state-base"
  r4_payload "$C" "$SURF/t.jsonl" 3
  r4_run
  has "$(r4_active)" "projects/proj-b/deposits.md"
}

@test "surfaced and logged markers live in the state dir" {
  r4_configure
  cp "$FIXTURE" "$SURF/t.jsonl"
  C="${RUN_ID}SM"
  r4_payload "$C" "$SURF/t.jsonl" 3 "model-s-1"
  r4_run
  has "$(r4_active)" "projects/proj-b/deposits.md"
  grep -qxF '4' "$SD/aria-ag-surfaced-$C"
  grep -qxF 'projects/proj-b/deposits.md' "$SD/aria-active-$C"
  [ "$(cat "$SD/aria-ag-model.last")" = "model-s-1" ]
  r4_payload "${C}U" "$SURF/missing.jsonl" 3
  r4_run
  [ -f "$SD/aria-ag-logged-${C}U.unreadable" ]
  grep -q ' antigravity transcript unreadable$' "$SD/aria-surface-hook.log"
  # ...and nowhere else: not in the test's TMPDIR or scratch dir, not in /tmp.
  [ -z "$(find "$SURF" -path "$SD" -prune -o \( -name 'aria-active-*' -o -name 'aria-ag-*' -o -name 'aria-surface-hook.log' \) -print | head -1)" ]
  [ ! -e "/tmp/aria-active-$C" ]
}

@test "model file name that is a directory is never entered" {
  r4_configure
  cp "$FIXTURE" "$SURF/t.jsonl"
  # mv -f onto a directory moves the temp INTO it (measured), so the hook must not write there.
  mkdir "$SD/aria-ag-model.last"
  r4_payload "${RUN_ID}MD" "$SURF/t.jsonl" 3 "model-d-1"
  r4_run
  has "$(r4_active)" "projects/proj-b/deposits.md"
  logged 'capture modelName=model-d-1'
  [ -d "$SD/aria-ag-model.last" ]
  [ -z "$(ls -A "$SD/aria-ag-model.last")" ]
  [ -z "$(ls -A "$SD" | grep '^\.aria-ag-model\.' || true)" ]
}
