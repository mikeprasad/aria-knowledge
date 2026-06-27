#!/bin/sh
# auto-runloop.sh — exercises bin/auto-runloop.sh, the external wrapper that relaunches a
# FRESH `claude` process each time /auto writes a context-restart signal file (Piece B of the
# /auto context-window self-restart mechanism; design: knowledge/logs/prospect/2026-06-27-file-auto-context-self-restart.md).
#
# Strategy (per prospect): NEVER spawn a real `claude` in CI. We shim `claude` on PATH with a
# stub that simulates the two exit reasons:
#   - context-handoff: the run writes the restart-signal file, then exits 0
#   - arc-done:        the run writes NO signal file, exits 0
# The wrapper's contract: loop while the signal file appears after a run; consume (delete) it
# before relaunching; stop when a run leaves no signal. The signal file's single line is the
# opener path the next run is launched with (prose-first; presence = restart requested).
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"     # tests/repros → repo root
LOOP="$REPO_ROOT/plugin-claude-code/bin/auto-runloop.sh"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

[ -f "$LOOP" ] && ok "A auto-runloop.sh exists" || bad "A exists" "no bin/auto-runloop.sh"
[ -x "$LOOP" ] && ok "A auto-runloop.sh is executable" || bad "A exec" "not chmod +x"

# --- Contract greps (documented behavior in the script header/usage) ---
grep -qiE 'self-restart|restart-signal|auto-restart' "$LOOP" && ok "B references the restart signal" || bad "B signal" "no signal-file concept"
grep -qiF -- '-p' "$LOOP" && ok "C relaunches HEADLESS (-p), not interactive" || bad "C headless" "does not use claude -p (interactive REPL never self-exits → loop hangs)"
grep -qiF 'dangerously-skip-permissions' "$LOOP" && ok "C unattended perms flag" || bad "C perms" "no --dangerously-skip-permissions for unattended run"
grep -qiE 'consume|rm |delete|unlink' "$LOOP" && ok "D consumes the signal before relaunch" || bad "D consume" "signal not consumed (would loop forever)"
grep -qiE 'SELFRESTART-PRE|prose|opener' "$LOOP" && ok "E prose-first opener launch" || bad "E opener" "no opener-launch concept"

# --- Behavioral test: a stubbed `claude` drives the loop ---
# We can only run this if the script exists (guards the RED phase from erroring out).
if [ -f "$LOOP" ]; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  BIN="$WORK/bin"; mkdir -p "$BIN"
  SIGNAL="$WORK/.auto-restart-requested"
  OPENER="$WORK/SESSION.md"
  RUNLOG="$WORK/runs.log"
  printf 'continue the arc, verify state first\n' > "$OPENER"

  # Stub claude: count invocations; on run #1 write the signal (simulate context handoff),
  # on run #2 write nothing (simulate arc-done). Record each invocation.
  cat > "$BIN/claude" <<STUB
#!/bin/sh
echo "claude-invoked" >> "$RUNLOG"
N=\$(wc -l < "$RUNLOG" | tr -d ' ')
if [ "\$N" -eq 1 ]; then
  printf '%s\n' "$OPENER" > "$SIGNAL"   # context handoff: request a restart
fi
exit 0
STUB
  chmod +x "$BIN/claude"

  # Run the loop with our stub on PATH, the signal path + initial goal injected via env.
  # The wrapper reads AUTO_RESTART_SIGNAL (override) and takes the goal as $1.
  OUT="$(PATH="$BIN:$PATH" AUTO_RESTART_SIGNAL="$SIGNAL" sh "$LOOP" "ship the thing" 2>&1)" && RC=0 || RC=$?

  RUNS="$( [ -f "$RUNLOG" ] && wc -l < "$RUNLOG" | tr -d ' ' || echo 0 )"
  [ "$RUNS" = "2" ] && ok "F loop ran exactly twice (handoff→relaunch→arc-done→stop)" || bad "F runs" "expected 2 claude runs, got $RUNS"
  [ ! -f "$SIGNAL" ] && ok "G signal consumed (none left at exit)" || bad "G leftover" "signal file still present after loop"
  [ "$RC" = "0" ] && ok "H loop exits 0 on clean completion" || bad "H rc" "loop exit code $RC"
else
  bad "F runs" "skipped — script absent (RED)"
  bad "G leftover" "skipped — script absent (RED)"
  bad "H rc" "skipped — script absent (RED)"
fi

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
