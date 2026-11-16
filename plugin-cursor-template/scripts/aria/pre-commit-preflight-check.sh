#!/bin/sh
# pre-commit-preflight-check.sh — beforeShellExecution hook (Cursor port of
# Claude Code's PreToolUse:Bash preflight gate).
#
# Fires on `git commit`. Asks: has a /preflight been recorded this session for
# the code about to be sealed?
#
# WARN BY DEFAULT. Escalation to deny is OPT-IN via preflight_gate /
# preflight_deny_paths / preflight_deny_repos. Cursor beforeShellExecution
# CAN deny (`permission: deny`); that is the native equivalent of Claude's
# permissionDecision deny. Circuit breaker (3 consecutive denials → warn)
# is kept — a gate that deadlocks a session gets turned off permanently.
#
# Fail-open on anything unparseable, on any git error, and whenever the
# session id cannot be resolved.

INPUT=$(cat)

COMMAND=$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//')
[ -z "$COMMAND" ] && exit 0

# Only `git commit` — as an INVOCATION, not as a literal substring. Match `git`,
# then any number of option-like tokens (each starting with `-`, optionally
# followed by a non-`-` value), then `commit` as a whole word.
#
# WHY NOT `case`. This was `case "$COMMAND" in *"git commit"*)`, which was wrong
# in BOTH directions (v2.46.1). It MISSED every `git -C <dir> commit` — a real
# commit whose text never contains the substring `git commit` — so any scripted
# or `git -C` commit bypassed the gate entirely, including in a repo named by
# preflight_deny_repos. And it MATCHED `git commit-tree`, which the old comment
# claimed it excluded: `git commit` is a prefix of `git commit-tree`.
#
# `case` cannot express "only option-like tokens between `git` and `commit`".
# The trailing `([[:space:]]|$)` rejects `commit-tree` / `commit-graph`. The
# leading `(^|[[:space:];&|(])` makes `git` start a word, so `mygit commit`
# does not match while a compound `cd /a && git commit` does.
#
# Accepted residual: a command that merely QUOTES the phrase still matches.
# That is the safe direction for a gate any single recorded /preflight satisfies
# for the whole session.
printf '%s' "$COMMAND" | grep -qE \
  '(^|[[:space:];&|(])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$)' \
  || exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/config.sh" ] && . "$SCRIPT_DIR/config.sh" 2>/dev/null

GATE="${KT_PREFLIGHT_GATE:-warn}"
[ "$GATE" = "off" ] && exit 0

REPO_DIR=$(printf '%s' "$COMMAND" | sed -n 's/^[[:space:]]*(\{0,1\}[[:space:]]*cd[[:space:]]\{1,\}\([^&;|]*\).*/\1/p' \
  | head -1 | sed 's/[[:space:]]*$//')
CD_NAMED="$REPO_DIR"
[ -n "$REPO_DIR" ] && [ ! -d "$REPO_DIR" ] && REPO_DIR=""
if [ -z "$REPO_DIR" ]; then
  REPO_DIR=$(printf '%s' "$COMMAND" | sed -n 's/.*git[[:space:]]\{1,\}-C[[:space:]]\{1,\}\([^ ]*\).*/\1/p' | head -1)
fi
# A `cd` that named a directory which does not exist: never fall back to checking `.`.
[ -z "$REPO_DIR" ] && [ -n "$CD_NAMED" ] && exit 0
[ -z "$REPO_DIR" ] && REPO_DIR="."
[ ! -d "$REPO_DIR" ] && exit 0

STAGED=$(git -C "$REPO_DIR" diff --cached --name-only 2>/dev/null) || exit 0
[ -z "$STAGED" ] && exit 0

# DATA lists must not pathname-expand (v2.44.1: unquoted `src/*` became the
# 17 literal names inside src/ and the gate silently stopped denying).
set -f

CODE_FILES=""
for f in $STAGED; do
  case "$f" in
    *.md|*.txt|*.rst|docs/*|*/docs/*|CHANGELOG*|LICENSE*) continue ;;
    *) CODE_FILES="$CODE_FILES $f" ;;
  esac
done
[ -z "$CODE_FILES" ] && exit 0

# kt_session_key (lib-state-key.sh): read whitespace-tolerantly, accepted only as [A-Za-z0-9._-]+ and
# never rewritten — the key every hook in this port names this family's state with. No id at all:
# abstain, as before. Rejected: no key, so no marker and no breaker (spec D3) — the commit gets the
# no-marker response. A missing lib is the same "no state", NOT an abstain: this is a deny gate, so
# `exit 0` here would fail OPEN. Without the lib kt_session_key fails with 127 (not 1), and the
# commit gets the no-marker response.
KT_STATE_DIR=   # an inherited value is never trusted: only the state-dir resolver sets it
if [ -f "$SCRIPT_DIR/lib-state-key.sh" ]; then . "$SCRIPT_DIR/lib-state-key.sh"; fi
SESSION_ID=$(kt_session_key "$INPUT" sessionId session_id 2>/dev/null)
[ "$?" = 1 ] && exit 0

# 2.58.0: the breaker and the marker live in the private per-user state directory (lib-state-key.sh),
# so a counter or a FIFO another local user plants in a shared temp dir is never read. With no
# directory (spec D3) the marker reads as absent and the breaker never trips: every code commit gets
# the no-marker response. The session id goes through kt_state_path, which refuses one with a "/".
BREAKER=""
MARKER=""
if [ -f "$SCRIPT_DIR/lib-state-key.sh" ]; then
  . "$SCRIPT_DIR/lib-state-key.sh"
  if [ -n "$SESSION_ID" ] && kt_state_resolve; then
    BREAKER=$(kt_state_path "aria-preflight-denies-$SESSION_ID")
    MARKER=$(kt_state_path "aria-preflight-$SESSION_ID")
  fi
fi
# A compliant commit also resets the breaker (v2.57.9): the contract is three CONSECUTIVE
# denials with no compliant commit between them; before, nothing removed the counter.
[ -n "$MARKER" ] && [ -s "$MARKER" ] && { [ -n "$BREAKER" ] && rm -f "$BREAKER" 2>/dev/null; exit 0; }

UNCHECKED=$(printf '%s' "$CODE_FILES" | tr ' ' '\n' | grep -v '^$' | head -5 | tr '\n' ' ')
N=$(printf '%s' "$CODE_FILES" | tr ' ' '\n' | grep -cv '^$')

MATCHED=""
WHY_KEY=""
if [ "$GATE" = "deny" ]; then
  MATCHED="yes"; WHY_KEY="gate"
elif [ -n "$KT_PREFLIGHT_DENY_REPOS" ]; then
  REPO_TOP=$(git -C "$REPO_DIR" rev-parse --show-toplevel 2>/dev/null)
  [ -z "$REPO_TOP" ] && REPO_TOP="$REPO_DIR"
  OLD_IFS="$IFS"; IFS=','
  for tok in $KT_PREFLIGHT_DENY_REPOS; do
    [ -z "$tok" ] && continue
    case "$REPO_TOP" in *"$tok"*) MATCHED="yes"; WHY_KEY="repos"; break ;; esac
  done
  IFS="$OLD_IFS"
fi
if [ -z "$MATCHED" ] && [ -n "$KT_PREFLIGHT_DENY_PATHS" ]; then
  for f in $CODE_FILES; do
    for pat in $KT_PREFLIGHT_DENY_PATHS; do
      # shellcheck disable=SC2254
      case "$f" in $pat) MATCHED="yes"; WHY_KEY="paths"; break 2 ;; esac
    done
  done
fi

if [ -n "$MATCHED" ]; then
  case "$WHY_KEY" in
    gate)  WHY="Your preflight_gate is set to deny." ;;
    repos) WHY="This repository matches your preflight_deny_repos." ;;
    *)     WHY="This commit touches a path listed in your preflight_deny_paths." ;;
  esac

  # A name that exists but is not a regular file counts as no state: a FIFO would block the read,
  # and a killed hook prints nothing, which reads as allow.
  if [ -n "$BREAKER" ] && { [ -f "$BREAKER" ] || { [ ! -e "$BREAKER" ] && [ ! -L "$BREAKER" ]; }; }; then
    COUNT=0
    [ -f "$BREAKER" ] && COUNT=$(cat "$BREAKER" 2>/dev/null || echo 0)
    COUNT=$((COUNT + 1))
    printf '%s' "$COUNT" > "$BREAKER" 2>/dev/null || true
    TALLY="(Denial $COUNT of 3 before this gate degrades to a warning.)"
  else
    # No usable state (D3): no state directory, or a non-file at the breaker name. The breaker
    # cannot count, so it never trips.
    COUNT=1
    TALLY="(The private state directory is unavailable or unusable, so this gate cannot count denials and will not degrade.)"
  fi

  if [ "$COUNT" -le 3 ]; then
    REASON="PREFLIGHT REQUIRED — no preflight recorded this session for $N changed file(s): $UNCHECKED. Run /preflight, or record an explicit skip with a reason. $WHY $TALLY"
    REASON_ESC=$(kt_json_escape "$REASON")
    printf '{"permission":"deny","user_message":"%s","agent_message":"%s","agentMessage":"%s"}\n' "$REASON_ESC" "$REASON_ESC" "$REASON_ESC"
    exit 0
  fi
  MSG="PREFLIGHT: gate DEGRADED after 3 consecutive denials — allowing this commit. No preflight recorded this session for: $UNCHECKED. Run /preflight before reporting this work as done."
  MSG_ESC=$(kt_json_escape "$MSG")
  printf '{"agentMessage":"%s"}\n' "$MSG_ESC"
  exit 0
fi

# 2.58.0: the record lives in the private per-user state directory (lib-state-key.sh); with no
# directory (spec D3) nothing is recorded and the warning below is still emitted. Inside the
# directory the line is built first, the file is created only by kt_create_new, and appended to
# only when it is a regular file of ours that is not a link (a second guard, spec D2;
# lib-tracked-artifacts.sh only defines functions; without it nothing is recorded).
_pf_line=$(printf '%s\t%s' "$(date +%H:%M 2>/dev/null || echo '?')" "$UNCHECKED")
_pf_f=
[ -n "${KT_STATE_DIR:-}" ] && [ -n "$SESSION_ID" ] && _pf_f=$(kt_state_path "aria-preflight-skipped-$SESSION_ID" 2>/dev/null)
. "$SCRIPT_DIR/lib-tracked-artifacts.sh" 2>/dev/null || true
if [ -n "$_pf_f" ]; then
  [ -e "$_pf_f" ] || [ -L "$_pf_f" ] || kt_create_new "$_pf_f" 2>/dev/null || :
  if kt_is_ours "$_pf_f" 2>/dev/null; then
    printf '%s\n' "$_pf_line" >> "$_pf_f" 2>/dev/null || true
  fi
fi

MSG="PREFLIGHT: no preflight recorded this session for $N changed file(s): $UNCHECKED. Before reporting this as done, consider /preflight — P1 requirements diff, P2 consumer census, P3 reachability, P4 census bound, P5 non-vacuity, P6 mutation. If a check does not apply, say which and why; skipping silently is the failure mode."
MSG_ESC=$(kt_json_escape "$MSG")
printf '{"agentMessage":"%s"}\n' "$MSG_ESC"
exit 0
