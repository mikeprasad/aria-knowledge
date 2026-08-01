#!/bin/sh
# pre-commit-preflight-check.sh — PreToolUse:Bash hook.
#
# Fires on `git commit`. Asks one question: has a preflight been recorded this
# session for the code about to be sealed?
#
# WHY THE COMMIT AND NOT THE CLAIM. The thing worth gating is "about to report this
# as done" — but that is PROSE, and a hook cannot see prose. Keying on completion
# language in the response was considered and rejected: it fires every turn, and it
# collides with a bare "Done." used as a deliberate completion signal. The commit is
# the nearest event that reliably accompanies the claim and happens roughly once per
# real unit of work.
#
# WARN BY DEFAULT. Escalation to deny is OPT-IN, per user config, because the paths
# where a missed check actually costs something vary per user and per codebase —
# hardcoding a risk list here would encode one team's shape into everyone's plugin.
#
#   preflight_gate:       off | warn | deny     (default warn)
#   preflight_deny_paths: <glob> <glob> ...     (only meaningful when gate=deny;
#                                                empty = deny on ALL code commits)
#
# Mirrors `critical_paths` / `planning_paths`: the user names the paths, the hook
# supplies the mechanism.
#
# Fail-open on anything unparseable, on any git error, and whenever the session id
# cannot be resolved. A gate that cannot read its inputs must not block work.

INPUT=$(cat)

# printf '%s', NOT echo -- `echo` in sh interprets backslash escapes, so JSON's \n
# becomes a real newline, the value splits across lines, and a single-line grep
# silently matches nothing. Same reasoning as pre-bash-write-check.sh.
COMMAND=$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//')
[ -z "$COMMAND" ] && exit 0

# Only `git commit`. Not `git commit-tree`, not a message that mentions committing.
case "$COMMAND" in
  *"git commit"*) : ;;
  *) exit 0 ;;
esac

SCRIPT_DIR=$(dirname "$0")
[ -f "$SCRIPT_DIR/config.sh" ] && . "$SCRIPT_DIR/config.sh" 2>/dev/null

GATE="${KT_PREFLIGHT_GATE:-warn}"
[ "$GATE" = "off" ] && exit 0

# Resolve the repo the commit actually targets. A compound `cd /a && git commit`
# commits in /a, not in the hook's cwd -- reading the wrong repo's index would make
# every verdict meaningless rather than merely wrong.
REPO_DIR=$(printf '%s' "$COMMAND" | sed -n 's/^[[:space:]]*cd[[:space:]]\{1,\}\([^&;|]*\).*/\1/p' \
  | head -1 | sed 's/[[:space:]]*$//')
[ -n "$REPO_DIR" ] && [ ! -d "$REPO_DIR" ] && REPO_DIR=""
if [ -z "$REPO_DIR" ]; then
  REPO_DIR=$(printf '%s' "$COMMAND" | sed -n 's/.*git[[:space:]]\{1,\}-C[[:space:]]\{1,\}\([^ ]*\).*/\1/p' | head -1)
fi
[ -z "$REPO_DIR" ] && REPO_DIR="."
[ ! -d "$REPO_DIR" ] && exit 0

STAGED=$(git -C "$REPO_DIR" diff --cached --name-only 2>/dev/null) || exit 0
# Nothing staged: either a no-op commit or `-a`, which we cannot enumerate safely.
# Both fail open -- a gate that guesses at content is worse than one that abstains.
[ -z "$STAGED" ] && exit 0

# Docs-only commits carry no code claim. Silent by design: this hook firing on a
# README edit is exactly the noise that gets a gate disabled wholesale.
CODE_FILES=""
for f in $STAGED; do
  case "$f" in
    *.md|*.txt|*.rst|docs/*|*/docs/*|CHANGELOG*|LICENSE*) continue ;;
    *) CODE_FILES="$CODE_FILES $f" ;;
  esac
done
[ -z "$CODE_FILES" ] && exit 0

SESSION_ID=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/"session_id":"//;s/"$//')
[ -z "$SESSION_ID" ] && exit 0

MARKER="${TMPDIR:-/tmp}/aria-preflight-$SESSION_ID"
# A recorded preflight -- of any verdict -- satisfies the gate. Recording a FAIL and
# proceeding anyway is a legitimate, visible choice; the failure this guards against
# is not running the checks at all.
[ -s "$MARKER" ] && exit 0

UNCHECKED=$(printf '%s' "$CODE_FILES" | tr ' ' '\n' | grep -v '^$' | head -5 | tr '\n' ' ')
N=$(printf '%s' "$CODE_FILES" | tr ' ' '\n' | grep -cv '^$')

# --- deny path: opt-in, and only for paths the user named -------------------
if [ "$GATE" = "deny" ]; then
  MATCHED=""
  if [ -z "$KT_PREFLIGHT_DENY_PATHS" ]; then
    MATCHED="yes"           # gate=deny with no paths named = deny on all code
  else
    for f in $CODE_FILES; do
      for pat in $KT_PREFLIGHT_DENY_PATHS; do
        # shellcheck disable=SC2254
        case "$f" in $pat) MATCHED="yes"; break 2 ;; esac
      done
    done
  fi

  if [ -n "$MATCHED" ]; then
    # Circuit breaker, same contract as pre-edit-check.sh: three consecutive denials
    # with no compliant commit between them degrade to allow-with-loud-warning. A gate
    # that can deadlock a session gets turned off permanently, which protects nothing.
    BREAKER="${TMPDIR:-/tmp}/aria-preflight-denies-$SESSION_ID"
    COUNT=$(cat "$BREAKER" 2>/dev/null || echo 0)
    COUNT=$((COUNT + 1))
    printf '%s' "$COUNT" > "$BREAKER" 2>/dev/null || true

    if [ "$COUNT" -le 3 ]; then
      REASON="PREFLIGHT REQUIRED — no preflight recorded this session for $N changed file(s): $UNCHECKED. Run /preflight, or record an explicit skip with a reason. This commit touches a path listed in your preflight_deny_paths. (Denial $COUNT of 3 before this gate degrades to a warning.)"
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$REASON"
      exit 0
    fi
    MSG="PREFLIGHT: gate DEGRADED after 3 consecutive denials — allowing this commit. No preflight recorded this session for: $UNCHECKED. Run /preflight before reporting this work as done."
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$MSG"
    exit 0
  fi
fi

# --- warn path (default) ----------------------------------------------------
# Recorded at warn time as well as deny time: a warning the model ignores otherwise
# leaves no trace, and an ignored gate is precisely the failure this exists to catch.
# /wrapup and /handoff can report the skips afterwards.
printf '%s\t%s\n' "$(date +%H:%M 2>/dev/null || echo '?')" "$UNCHECKED" \
  >> "${TMPDIR:-/tmp}/aria-preflight-skipped-$SESSION_ID" 2>/dev/null || true

MSG="PREFLIGHT: no preflight recorded this session for $N changed file(s): $UNCHECKED. Before reporting this as done, consider /preflight — P1 requirements diff, P2 consumer census, P3 reachability, P4 census bound, P5 non-vacuity, P6 mutation. If a check does not apply, say which and why; skipping silently is the failure mode."

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$MSG"
exit 0
