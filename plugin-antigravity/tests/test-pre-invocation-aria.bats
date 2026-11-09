#!/usr/bin/env bats

setup() {
  export HOME="${BATS_TMPDIR}"
  WRAPPER="${BATS_TEST_DIRNAME}/../bin/antigravity/pre-invocation-aria.sh"
  CACHE_DIR="$HOME/.gemini/antigravity"
  CACHE_FILE="$CACHE_DIR/.last-transcript-path"
  LOG_FILE="$CACHE_DIR/aria-knowledge-scope-check.log"
  mkdir -p "$CACHE_DIR" 2>/dev/null || true
  # Responsibility 4 (spec D4) keeps its state, config cache and debug log under
  # KT_SURFACE_CACHE_DIR: one fresh dir per test, never the user's TMPDIR.
  SURF="$(mktemp -d "${BATS_TMPDIR}/ag-surf.XXXXXX")"
  export KT_SURFACE_CACHE_DIR="$SURF"
  HOOKLOG="$SURF/aria-surface-hook.log"
  FIXTURE="${BATS_TEST_DIRNAME}/fixtures/transcript-user-input.jsonl"
  # The ledger path is fixed by contract (/tmp/aria-active-<id>), so every id carries RUN_ID.
  RUN_ID="agpi$$t${BATS_TEST_NUMBER}x$(od -An -N4 -tx4 /dev/urandom 2>/dev/null | tr -d ' ')"
}

teardown() {
  rm -rf "$CACHE_DIR" "$SURF" 2>/dev/null || true
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
  grep -qxF 'projects/proj-b/deposits.md' "/tmp/aria-active-$C"
  grep -qxF '4' "$SURF/aria-ag-surfaced-$C"
  # Same newest USER_INPUT on the next model call: nothing.
  r4_run
  [ "$(cat "$SURF/out")" = "{}" ]
  # With the ledger gone, the state file alone still holds it to once.
  rm -f "/tmp/aria-active-$C"
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
  grep -qxF '4' "$SURF/aria-ag-surfaced-$C"
  grep -qxF '7' "$SURF/aria-ag-surfaced-$C"
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
  grep -qxF '4' "$SURF/aria-ag-surfaced-$C"
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
  # A: R4 has nothing to read.
  printf '%s\n' "--- 2026-05-24T08:00:00Z stepIdx=5 error=none" "[Rule 22 Scope] PASS — sample entry" > "$LOG_FILE"
  r4_payload "${RUN_ID}E1" "$SURF/missing.jsonl" 0
  r4_run
  cp "$SURF/out" "$SURF/outA"
  # B: R4 fires.
  printf '%s\n' "--- 2026-05-24T08:00:00Z stepIdx=5 error=none" "[Rule 22 Scope] PASS — sample entry" > "$LOG_FILE"
  r4_payload "${RUN_ID}E2" "$SURF/t.jsonl" 0
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
  ln -s "$SURF/target" "$SURF/aria-ag-surfaced-$C"
  r4_payload "$C" "$SURF/t.jsonl" 3
  r4_run
  [ -z "$(r4_active)" ]
  [ "$(cat "$SURF/target")" = "keep" ]
  [ ! -e "/tmp/aria-active-$C" ]
  logged 'state refused'
  rm -f "$SURF/aria-ag-surfaced-$C"
  r4_run
  has "$(r4_active)" "projects/proj-b/deposits.md"
}

@test "R4 delivery_failure_records_nothing: unwritable output → no ledger, no state" {
  r4_configure
  cp "$FIXTURE" "$SURF/t.jsonl"
  C="${RUN_ID}D"
  r4_payload "$C" "$SURF/t.jsonl" 3
  bash "$WRAPPER" < "$SURF/in" >&- 2>/dev/null || true
  [ ! -e "$SURF/aria-ag-surfaced-$C" ]
  [ ! -e "/tmp/aria-active-$C" ]
  logged 'emit write-failed'
  r4_run
  has "$(r4_active)" "projects/proj-b/deposits.md"
  grep -qxF '4' "$SURF/aria-ag-surfaced-$C"
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
  grep -qxF '4' "$SURF/aria-ag-surfaced-${RUN_ID}x..suby"
  grep -qxF 'projects/proj-b/deposits.md' "/tmp/aria-active-${RUN_ID}x..suby"
  [ -z "$(ls -A "$SURF/sub")" ]
}

@test "R4 nofire_turn_ranked_once: a decided turn (nofire, nothing-new) is ranked at most once" {
  r4_configure
  # A copy of the plugin's bin/ whose kt_index_match counts its calls: ranking is observed
  # directly, not inferred from an empty output.
  P="$SURF/plug"
  mkdir -p "$P/bin/antigravity"
  cp "${BATS_TEST_DIRNAME}"/../bin/antigravity/*.sh "$P/bin/antigravity/"
  cp "${BATS_TEST_DIRNAME}/../bin/config.sh" "${BATS_TEST_DIRNAME}/../bin/lib-index-match.sh" \
     "${BATS_TEST_DIRNAME}/../bin/lib-prompt-surface.sh" "$P/bin/"
  cat >> "$P/bin/lib-index-match.sh" <<'WRAP'
eval "_r4_counted_$(declare -f kt_index_match)"
kt_index_match() { printf 'x\n' >> "$KT_TEST_MATCH_COUNTER"; _r4_counted_kt_index_match "$@"; }
WRAP
  export KT_TEST_MATCH_COUNTER="$SURF/matches"
  H="$P/bin/antigravity/pre-invocation-aria.sh"
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
  grep -qxF '4' "$SURF/aria-ag-surfaced-$C"
  [ ! -e "/tmp/aria-active-$C" ]                 # the ledger records delivered paths only
  # nothing-new: deliver, lose only the state file (the ledger still holds the paths).
  C2="${RUN_ID}Q"
  cp "$FIXTURE" "$SURF/t2.jsonl"
  r4_payload "$C2" "$SURF/t2.jsonl" 3
  bash "$H" < "$SURF/in" > "$SURF/out" 2>/dev/null
  has "$(r4_active)" "projects/proj-b/deposits.md"
  [ "$(ranked)" = "2" ]
  rm -f "$SURF/aria-ag-surfaced-$C2"
  bash "$H" < "$SURF/in" > "$SURF/out" 2>/dev/null
  [ "$(cat "$SURF/out")" = "{}" ]
  [ "$(ranked)" = "3" ]
  grep -qxF '4' "$SURF/aria-ag-surfaced-$C2"
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
  ln -s "$SURF/planted-target" "$SURF/aria-ag-logged-${RUN_ID}W.unreadable"
  r4_payload "${RUN_ID}W" "$SURF/missing.jsonl" 3
  r4_run
  [ ! -e "$SURF/planted-target" ]
  [ "$(grep -c ' antigravity transcript unreadable$' "$HOOKLOG")" = "3" ]
}

@test "R4 stale_state_pruned_on_first_call: state files older than 24 h go on invocationNum 0" {
  r4_configure
  printf '4\n' > "$SURF/aria-ag-surfaced-${RUN_ID}old"
  : > "$SURF/aria-ag-logged-${RUN_ID}old.unreadable"
  touch -t 202001010000 "$SURF/aria-ag-surfaced-${RUN_ID}old" "$SURF/aria-ag-logged-${RUN_ID}old.unreadable"
  printf '4\n' > "$SURF/aria-ag-surfaced-${RUN_ID}new"
  r4_payload "${RUN_ID}P" "$SURF/missing.jsonl" 0
  r4_run
  [ ! -e "$SURF/aria-ag-surfaced-${RUN_ID}old" ]
  [ ! -e "$SURF/aria-ag-logged-${RUN_ID}old.unreadable" ]
  [ -e "$SURF/aria-ag-surfaced-${RUN_ID}new" ]
}

@test "R4 lib_missing_logged: without lib-prompt-surface.sh → logged, output unchanged" {
  r4_configure
  cp "$FIXTURE" "$SURF/t.jsonl"
  P="$SURF/plug"
  mkdir -p "$P/bin/antigravity"
  cp "${BATS_TEST_DIRNAME}"/../bin/antigravity/*.sh "$P/bin/antigravity/"
  cp "${BATS_TEST_DIRNAME}/../bin/config.sh" "${BATS_TEST_DIRNAME}/../bin/lib-index-match.sh" "$P/bin/"
  r4_payload "${RUN_ID}L" "$SURF/t.jsonl" 3
  bash "$P/bin/antigravity/pre-invocation-aria.sh" < "$SURF/in" > "$SURF/out" 2>/dev/null
  [ "$(cat "$SURF/out")" = "{}" ]
  logged 'surface lib-missing'
}

@test "R4 jq_missing_logged: no jq → the existing deny output, plus one debug-log line" {
  FARM="$SURF/farm"; mkdir -p "$FARM"
  for d in /usr/bin /bin /usr/sbin /sbin; do
    for b in "$d"/*; do
      n=${b##*/}
      [ "$n" = jq ] && continue
      [ -e "$FARM/$n" ] || ln -s "$b" "$FARM/$n" 2>/dev/null || true
    done
  done
  ! (PATH="$FARM"; command -v jq >/dev/null 2>&1) || false
  r4_payload "${RUN_ID}J" "$SURF/missing.jsonl" 3
  rc=0
  PATH="$FARM" /bin/bash "$WRAPPER" < "$SURF/in" > "$SURF/out" 2>/dev/null || rc=$?
  [ "$rc" = "1" ]
  grep -q '"decision":"deny"' "$SURF/out"
  logged 'input jq-missing'
}
