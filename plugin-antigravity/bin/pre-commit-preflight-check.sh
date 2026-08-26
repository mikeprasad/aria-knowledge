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
# silently matches nothing. Same reasoning as bash-cd-check.sh.
# (This previously cited pre-bash-write-check.sh, retired 2026-08-26 for deciding
# from the command string rather than the resolved target — see bin/.archived/.)
COMMAND=$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//')
[ -z "$COMMAND" ] && exit 0

# Only `git commit` -- as an INVOCATION, not as a literal substring. Match `git`, then any
# number of option-like tokens (each starting with `-`, optionally followed by a non-`-`
# value), then `commit` as a whole word.
#
# WHY NOT `case`. This was `case "$COMMAND" in *"git commit"*)`, which was wrong in BOTH
# directions. It MISSED every `git -C <dir> commit` -- a real commit whose text never
# contains the substring `git commit` -- so any scripted or `git -C` commit bypassed the
# gate entirely, including in a repo named by preflight_deny_repos, the strongest setting
# available. And it MATCHED `git commit-tree`, which the old comment claimed it excluded:
# `git commit` is a prefix of `git commit-tree`, so the pattern never excluded it.
#
# `case` cannot express "only option-like tokens between `git` and `commit`", and that is
# exactly the distinction needed: any pattern loose enough to admit `git -C /d commit`
# (e.g. `*"git "*" commit"*`) also admits `git status -m "commit "`. Hence the ERE.
#
# The trailing `([[:space:]]|$)` is what rejects `commit-tree` / `commit-graph`. The leading
# `(^|[[:space:];&|(])` makes `git` start a word, so `mygit commit` does not match while a
# compound `cd /a && git commit` does.
#
# Accepted residual, unchanged from the previous behaviour: a command that merely QUOTES the
# phrase (`echo "run git commit later"`) still matches. That is the safe direction for a gate
# any single recorded /preflight satisfies for the whole session.
printf '%s' "$COMMAND" | grep -qE \
  '(^|[[:space:];&|(])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$)' \
  || exit 0

SCRIPT_DIR=$(dirname "$0")
[ -f "$SCRIPT_DIR/config.sh" ] && . "$SCRIPT_DIR/config.sh" 2>/dev/null

GATE="${KT_PREFLIGHT_GATE:-warn}"
[ "$GATE" = "off" ] && exit 0

# Resolve the repo the commit actually targets. A compound `cd /a && git commit`
# commits in /a, not in the hook's cwd -- reading the wrong repo's index would make
# every verdict meaningless rather than merely wrong.
REPO_DIR=$(printf '%s' "$COMMAND" | sed -n 's/^[[:space:]]*cd[[:space:]]\{1,\}\([^&;|]*\).*/\1/p' \
  | head -1 | sed 's/[[:space:]]*$//')
CD_NAMED="$REPO_DIR"
[ -n "$REPO_DIR" ] && [ ! -d "$REPO_DIR" ] && REPO_DIR=""
if [ -z "$REPO_DIR" ]; then
  REPO_DIR=$(printf '%s' "$COMMAND" | sed -n 's/.*git[[:space:]]\{1,\}-C[[:space:]]\{1,\}\([^ ]*\).*/\1/p' | head -1)
fi
# A cd target was named, it does not exist, and no `git -C` named an alternative.
# Abstain. Falling through to "." here would read the HOOK'S cwd -- a DIFFERENT
# repo from the one the commit names -- which is precisely the "meaningless rather
# than merely wrong" failure the comment above warns about, and it silently cited
# an unrelated repo's staged files in the denial message. This path was asserted by
# test [11] "nonexistent repo -> fail open", but that assertion compared against ""
# from a cwd that usually had nothing staged, so it passed without ever exercising
# the branch.
[ -z "$REPO_DIR" ] && [ -n "$CD_NAMED" ] && exit 0
[ -z "$REPO_DIR" ] && REPO_DIR="."
[ ! -d "$REPO_DIR" ] && exit 0

STAGED=$(git -C "$REPO_DIR" diff --cached --name-only 2>/dev/null) || exit 0
# Nothing staged: either a no-op commit or `-a`, which we cannot enumerate safely.
# Both fail open -- a gate that guesses at content is worse than one that abstains.
[ -z "$STAGED" ] && exit 0

# From here on, every list we iterate -- staged paths and configured deny patterns --
# is DATA. Unquoted `for x in $LIST` word-splits (wanted) but ALSO pathname-expands
# (never wanted): before this line existed, a `preflight_deny_paths` of `src/*` run
# from a repo root became the 17 literal names inside src/, and `*theme.css` run
# from the directory holding that file collapsed to the bare basename. Both stopped
# matching the staged paths -- the gate silently went quiet, and WHICH files were
# protected depended on the tool's cwd. `set -f` disables pathname expansion only;
# `case` glob-matching below is unaffected, which is exactly the split we want.
set -f

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

# --- should this commit be DENIED? ------------------------------------------
# Two independent reasons, not one mode. `preflight_gate` is the BASELINE for every
# code commit; `preflight_deny_paths` is an ESCALATION that applies from ANY baseline,
# exactly as `critical_paths` escalates Rule 22 severity regardless of the surrounding
# setting. Gating the path list behind gate=deny (the first shape of this hook) made
# the key silently inert at the default setting — a config the user sets, sees no
# effect from, and reasonably concludes is broken.
#
#   gate: off   -> never fires; paths and repos irrelevant
#   gate: warn  -> warn, EXCEPT deny on a deny_repos or deny_paths match  <- the common one
#   gate: deny  -> deny every code commit; paths and repos irrelevant
#
# `preflight_deny_repos` answers what the path list structurally cannot: "always gate
# THIS repository." Staged paths are repo-relative, so the repo name appears nowhere
# in the string a path pattern is matched against -- `*my-repo/*` matches nothing,
# ever. This arm matches the resolved absolute toplevel instead.
MATCHED=""
WHY_KEY=""
if [ "$GATE" = "deny" ]; then
  MATCHED="yes"; WHY_KEY="gate"
elif [ -n "$KT_PREFLIGHT_DENY_REPOS" ]; then
  # REPO_DIR is "." whenever the command carried no `cd` and no `git -C`, so it must
  # be RESOLVED before matching or the key would silently never fire in the common
  # already-in-the-repo case. Fall back to REPO_DIR if this is not a work tree.
  REPO_TOP=$(git -C "$REPO_DIR" rev-parse --show-toplevel 2>/dev/null)
  [ -z "$REPO_TOP" ] && REPO_TOP="$REPO_DIR"
  # Substring, not equality: `parent/child` can scope a nested repo, and one token can
  # cover a family of repos. It OVER-matches (a `-fork` sibling matches too) -- for a
  # gate that is the safe direction, since under-matching is a gate that goes quiet.
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
  # Name the ACTUAL reason. Blaming preflight_deny_paths when the baseline was what
  # denied sends the user to edit a key that had nothing to do with it. WHY_KEY is set
  # by whichever arm above actually decided, so the three reasons cannot drift apart.
  case "$WHY_KEY" in
    gate)  WHY="Your preflight_gate is set to deny." ;;
    repos) WHY="This repository matches your preflight_deny_repos." ;;
    *)     WHY="This commit touches a path listed in your preflight_deny_paths." ;;
  esac

  # Circuit breaker, same contract as pre-edit-check.sh: three consecutive denials
  # with no compliant commit between them degrade to allow-with-loud-warning. A gate
  # that can deadlock a session gets turned off permanently, which protects nothing.
  BREAKER="${TMPDIR:-/tmp}/aria-preflight-denies-$SESSION_ID"
  COUNT=$(cat "$BREAKER" 2>/dev/null || echo 0)
  COUNT=$((COUNT + 1))
  printf '%s' "$COUNT" > "$BREAKER" 2>/dev/null || true

  if [ "$COUNT" -le 3 ]; then
    REASON="PREFLIGHT REQUIRED — no preflight recorded this session for $N changed file(s): $UNCHECKED. Run /preflight, or record an explicit skip with a reason. $WHY (Denial $COUNT of 3 before this gate degrades to a warning.)"
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$REASON"
    exit 0
  fi
  MSG="PREFLIGHT: gate DEGRADED after 3 consecutive denials — allowing this commit. No preflight recorded this session for: $UNCHECKED. Run /preflight before reporting this work as done."
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$MSG"
  exit 0
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
