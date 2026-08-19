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

REPO_DIR=$(printf '%s' "$COMMAND" | sed -n 's/^[[:space:]]*cd[[:space:]]\{1,\}\([^&;|]*\).*/\1/p' \
  | head -1 | sed 's/[[:space:]]*$//')
[ -n "$REPO_DIR" ] && [ ! -d "$REPO_DIR" ] && REPO_DIR=""
if [ -z "$REPO_DIR" ]; then
  REPO_DIR=$(printf '%s' "$COMMAND" | sed -n 's/.*git[[:space:]]\{1,\}-C[[:space:]]\{1,\}\([^ ]*\).*/\1/p' | head -1)
fi
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

SESSION_ID=$(printf '%s' "$INPUT" | grep -o '"sessionId":"[^"]*"' | head -1 | sed 's/"sessionId":"//;s/"$//')
[ -z "$SESSION_ID" ] && SESSION_ID=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"$//')
[ -z "$SESSION_ID" ] && exit 0

MARKER="${TMPDIR:-/tmp}/aria-preflight-$SESSION_ID"
[ -s "$MARKER" ] && exit 0

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

  BREAKER="${TMPDIR:-/tmp}/aria-preflight-denies-$SESSION_ID"
  COUNT=$(cat "$BREAKER" 2>/dev/null || echo 0)
  COUNT=$((COUNT + 1))
  printf '%s' "$COUNT" > "$BREAKER" 2>/dev/null || true

  if [ "$COUNT" -le 3 ]; then
    REASON="PREFLIGHT REQUIRED — no preflight recorded this session for $N changed file(s): $UNCHECKED. Run /preflight, or record an explicit skip with a reason. $WHY (Denial $COUNT of 3 before this gate degrades to a warning.)"
    REASON_ESC=$(kt_json_escape "$REASON")
    printf '{"permission":"deny","user_message":"%s","agent_message":"%s","agentMessage":"%s"}\n' "$REASON_ESC" "$REASON_ESC" "$REASON_ESC"
    exit 0
  fi
  MSG="PREFLIGHT: gate DEGRADED after 3 consecutive denials — allowing this commit. No preflight recorded this session for: $UNCHECKED. Run /preflight before reporting this work as done."
  MSG_ESC=$(kt_json_escape "$MSG")
  printf '{"agentMessage":"%s"}\n' "$MSG_ESC"
  exit 0
fi

printf '%s\t%s\n' "$(date +%H:%M 2>/dev/null || echo '?')" "$UNCHECKED" \
  >> "${TMPDIR:-/tmp}/aria-preflight-skipped-$SESSION_ID" 2>/dev/null || true

MSG="PREFLIGHT: no preflight recorded this session for $N changed file(s): $UNCHECKED. Before reporting this as done, consider /preflight — P1 requirements diff, P2 consumer census, P3 reachability, P4 census bound, P5 non-vacuity, P6 mutation. If a check does not apply, say which and why; skipping silently is the failure mode."
MSG_ESC=$(kt_json_escape "$MSG")
printf '{"agentMessage":"%s"}\n' "$MSG_ESC"
exit 0
