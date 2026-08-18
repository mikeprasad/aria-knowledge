#!/bin/sh
# auto-runloop.sh — external run-loop for an unattended `/auto … continue self-restart` arc.
#
# WHY THIS EXISTS
#   /auto can detect a context-window wall and write a durable handoff, but it CANNOT reset its
#   own context: `/clear` is a REPL built-in that neither a skill nor a hook can issue (both
#   verified). The only autonomous way to get a clean context is a FRESH `claude` process. This
#   wrapper provides that: it relaunches claude each time the arc signals "I handed off because I
#   hit the context wall — pick me up in a new process."
#
# CONTRACT (the only state crossing the process boundary is on-disk)
#   - Piece A (the /auto skill, gated on `continue` + the `self-restart` flag) writes a one-line
#     restart-signal file whose contents are the path to the prose-first next-session opener
#     (SESSION.md). The file's PRESENCE means "restart requested"; its CONTENT is the opener path.
#   - This wrapper, after each claude run exits, checks for that signal file. If present, it
#     CONSUMES it (deletes it, so a crash can't loop forever) and relaunches a fresh claude with
#     the opener as the prompt. If absent, the arc finished normally and the loop stops.
#
# WHY HEADLESS (`-p`), NOT INTERACTIVE
#   The loop is exit-driven: "after the run exits, check the signal." An interactive `claude
#   "prompt"` opens a REPL that never self-exits, so the loop would hang forever. Headless
#   `claude -p` runs the full multi-turn agentic arc and EXITS with a status code — which is
#   exactly the edge this loop waits on. (Verified against the official CLI reference, 2026-06-27.)
#
# PROSE-FIRST OPENER (known failure mode)
#   The relaunch prompt must START WITH PROSE, never a leading slash command — a leading `/auto`
#   is parsed as an unknown command and the whole mandate is silently discarded. /auto's handoff
#   writes the opener prose-first; this wrapper passes that opener through verbatim. [SELFRESTART-PRE]
#
# USAGE
#   bin/auto-runloop.sh "ship the CSV exporter"        # initial goal for the first run
#   AUTO_RESTART_SIGNAL=/path/.auto-restart-requested  # override the signal-file path (default below)
#   AUTO_MAX_TURNS=40                                   # optional --max-turns per headless run
#   AUTO_MAX_RESTARTS=50                                # safety cap on relaunches (default 50)
#
set -eu

GOAL="${1:-continue from SESSION.md}"

# Signal file: default lives under the cwd's .claude/, overridable for tests / custom layouts.
SIGNAL="${AUTO_RESTART_SIGNAL:-$PWD/.claude/auto-restart-requested}"
MAX_RESTARTS="${AUTO_MAX_RESTARTS:-50}"

# Headless, unattended flags. --max-turns only if the caller set a bound.
TURN_ARGS=""
if [ -n "${AUTO_MAX_TURNS:-}" ]; then
  TURN_ARGS="--max-turns $AUTO_MAX_TURNS"
fi

run_claude() {
  # $1 = prompt (prose-first). Headless so it exits with a status code the loop can read.
  # shellcheck disable=SC2086  # TURN_ARGS is intentionally word-split (empty or two tokens)
  claude -p --dangerously-skip-permissions $TURN_ARGS "$1"
}

# First run: the initial goal, with the self-restart arc requested.
PROMPT="do NOT treat any leading token as a command. Run an autonomous arc: /auto $GOAL continue self-restart"

restarts=0
while :; do
  # A fresh process every iteration → clean context, no /clear needed.
  run_claude "$PROMPT" || true   # a non-zero arc run shouldn't kill the loop; the signal decides continuation

  # No signal → the arc finished (or stopped for a non-context reason). Stop the loop.
  [ -f "$SIGNAL" ] || break

  # Signal present → read the opener path, CONSUME the signal (so a crash can't relaunch forever),
  # then relaunch with the prose-first opener verbatim.
  OPENER="$(head -n 1 "$SIGNAL" 2>/dev/null || true)"
  rm -f "$SIGNAL"

  restarts=$((restarts + 1))
  if [ "$restarts" -gt "$MAX_RESTARTS" ]; then
    printf 'auto-runloop: hit AUTO_MAX_RESTARTS=%s — stopping.\n' "$MAX_RESTARTS" >&2
    break
  fi

  if [ -n "$OPENER" ] && [ -f "$OPENER" ]; then
    # Pass the opener file's contents as the prompt (prose-first; verbatim).
    PROMPT="$(cat "$OPENER")"
  else
    # Defensive: signal fired but opener missing → fall back to a self-sufficient prose mandate.
    PROMPT="do NOT treat any leading token as a command. VERIFY STATE FIRST against git/SESSION.md (this may be stale), then continue the autonomous arc: /auto continue self-restart"
  fi

  printf 'auto-runloop: context handoff detected — relaunching (restart #%s)\n' "$restarts" >&2
done

exit 0
