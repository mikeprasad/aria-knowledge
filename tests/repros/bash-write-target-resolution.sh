#!/bin/sh
# bash-write-target-resolution.sh — controls for the restored pre-bash-write-check.sh (v2.48.1).
#
# The guard this covers was RETIRED in v2.48.0 as "provably wrong in both directions": it decided
# from the command STRING instead of resolving the mutation TARGET. Both defects are stated here as
# executable controls, so the acceptance criteria ARE the bug reports:
#
#   AC1  FALSE NEGATIVE — `cp f /tmp/bak && sed -i … f` was SILENT, because the exemption matched
#        the command merely MENTIONING a temp path. Backup-then-mutate is the careful pattern this
#        project mandates, so doing the safe thing disarmed the check.
#   AC2  FALSE POSITIVE — a `git commit` whose MESSAGE quoted `sed -i` was flagged, because the
#        idiom match was unanchored.
#
# ⛔ POSITIVE/NEGATIVE PAIRING IS LOAD-BEARING. Against an inert stub every SILENCE control is
# GREEN — a hook that does nothing is indistinguishable from a hook that correctly stays quiet.
# Those controls are meaningful ONLY paired with a positive sibling (AC1, AC6b) that is RED against
# the stub and GREEN after. Never read a silence control alone as evidence the hook works.
#
# ⛔ EVERY SILENCE CONTROL MUST BE SILENT FOR ITS OWN REASON. The hook only reports targets that
# EXIST, so a fixture that does not exist would make AC4 and AC6a pass by non-existence rather than
# by the temp rule and the extension rule they are drawn around. All such fixtures are therefore
# created as real files below. AC5's `newfile.py` is deliberately NOT created — creation is the
# thing it tests.
#
# Run from any directory; resolves its own paths.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/plugin-claude-code/bin/pre-bash-write-check.sh"

# Isolate the per-session bypass ledger so repeated runs never accumulate, and so AC9 counts only
# this run's appends.
export TMPDIR=$(mktemp -d)
WORK=$(mktemp -d)
TMPFIX="/tmp/aria-bwchk-fixture-$$.py"
trap 'rm -rf "$TMPDIR" "$WORK" "$TMPFIX"' EXIT

# Real fixtures — see the header note on silent-for-its-own-reason.
printf 'a\n' > "$WORK/f"
printf 'a\n' > "$WORK/mod.py"
printf 'a\n' > "$WORK/notes.md"
printf 'a\n' > "$TMPFIX"

PASS=0
FAIL=0
SID="testsession"

# Build the payload with python3 so a command containing quotes, newlines or backslashes is encoded
# correctly. ⛔ Hand-rolled printf JSON is how the archived hook's multi-line heredoc bug survived:
# JSON \n became a real newline and a single-line grep silently matched nothing.
payload() { # $1=command
  python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]},"session_id":sys.argv[2]}))' "$1" "$SID"
}

run_case() { # $1=name  $2=command  $3=expect(warn|silent)
  name="$1"; cmd="$2"; expect="$3"
  out=$(payload "$cmd" | sh "$HOOK" 2>/dev/null || true)
  case "$out" in
    *additionalContext*) got="warn" ;;
    *)                   got="silent" ;;
  esac
  if [ "$got" = "$expect" ]; then
    PASS=$((PASS + 1)); printf 'PASS  %s\n' "$name"
  else
    FAIL=$((FAIL + 1)); printf 'FAIL  %s (got %s want %s)\n' "$name" "$got" "$expect"
  fi
}

# --- AC1: the FALSE NEGATIVE. The archived guard exempted this because the command string mentions
# /tmp. The resolved target is $WORK/f, which is NOT in /tmp, so it must fire.
run_case "AC1  backup-then-mutate WARNS (resolved target, not string mention)" \
  "cp $WORK/f /tmp/bak && sed -i '' s/a/b/ $WORK/f" warn

# --- AC2/AC3: the FALSE POSITIVE, both forms. A heredoc BODY is data; a quoted argument is one
# token whose basename is not `sed`. Neither may fire.
# ⛔ The heredoc body must name a REAL EXISTING file, or this control passes for the wrong reason.
# Measured: with a body of ordinary words, removing heredoc stripping entirely left AC2 GREEN,
# because the body's tokens are not files and the existence rule filtered them anyway — so the one
# mechanism defect 2 actually rests on was never proven. Naming $WORK/mod.py makes the mutation
# faithful: unstripped, the body resolves to a real file and this control goes red.
run_case "AC2  git commit with a heredoc body naming a real file after sed -i is SILENT" \
  "git commit -F - <<EOF
fix: sed -i $WORK/mod.py was the wrong approach
EOF" silent

run_case "AC3  git commit -m quoting sed -i is SILENT" \
  "git commit -m \"use sed -i on $WORK/mod.py\"" silent

# --- AC4: temp exemption by RESOLVED path. The fixture EXISTS, so the only thing that can make
# this silent is the temp rule.
run_case "AC4  sed -i on an existing /tmp path is SILENT (temp rule, not non-existence)" \
  "sed -i '' s/a/b/ $TMPFIX" silent

# --- AC5: creation is OUT of scope. Measured across 25,508 calls: `cat > newfile` is
# overwhelmingly a throwaway probe. Widening here turns the hook into noise.
# ⛔ Targets an EXISTING source file, not a new name. With `$WORK/newfile.py` this control passed
# because the file does not exist — i.e. it tested the existence rule, not the scope rule, and a
# mutation adding `>` to scope SURVIVED it. Overwriting an existing source file is the strongest
# form of the case: `>` is out of scope even then.
run_case "AC5  overwrite of an EXISTING source file via > is SILENT (scope rule, not existence)" \
  "cat > $WORK/mod.py" silent

# --- AC6a/AC6b: the append rule is extension-sensitive. TWO-SIDED on the same idiom, and AC6a's
# fixture EXISTS so only the extension rule can silence it.
run_case "AC6a append to an existing .md backlog is SILENT (extension rule)" \
  "echo x >> $WORK/notes.md" silent
run_case "AC6b append into an existing source file WARNS" \
  "echo x >> $WORK/mod.py" warn

# --- AC11: THE PRE-FILTER INVARIANT. Trips the cheap sh pre-filter (contains the literal `sed -i`)
# but resolves to NO target. Must be silent — proving a warning can only originate in the resolver.
run_case "AC11 pre-filter hit with no resolved target is SILENT" \
  'echo "sed -i is just a string here"' silent

# --- AC7: never exits non-zero, for any input.
for bad in '{not json' '{"tool_input":{"command":"sed -i \" unbalanced"}}' ''; do
  printf '%s' "$bad" | sh "$HOOK" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    PASS=$((PASS + 1)); printf 'PASS  AC7  malformed input exits 0\n'
  else
    FAIL=$((FAIL + 1)); printf 'FAIL  AC7  malformed input exited %s want 0\n' "$rc"
  fi
done

# --- AC8: python3 absent must degrade silently. PATH is stripped, so the wrapper must reach the
# interpreter gate using builtins only — otherwise this breaks the wrapper instead of exercising
# the missing-interpreter branch, and passes for the wrong reason.
# 2>/dev/null on the PRODUCER too: with PATH stripped the hook cannot run `cat`, so it exits before
# draining stdin and python3 reports a harmless BrokenPipeError. Cosmetic, but noise in a suite's
# output is how a real message gets skimmed past.
out=$(payload "sed -i '' s/a/b/ $WORK/f" 2>/dev/null | PATH=/nonexistent sh "$HOOK" 2>/dev/null || true)
if [ -z "$out" ]; then
  PASS=$((PASS + 1)); printf 'PASS  AC8  python3 absent degrades silently\n'
else
  FAIL=$((FAIL + 1)); printf 'FAIL  AC8  python3 absent still emitted output\n'
fi

# --- AC9: the session-scoped bypass ledger. Keyed by session id IN THE FILENAME, so cross-session
# attribution is unrepresentable rather than filtered.
LEDGER="$TMPDIR/aria-r22-bypass-$SID"
rm -f "$LEDGER"
payload "sed -i '' s/a/b/ $WORK/f" | sh "$HOOK" >/dev/null 2>&1 || true
if [ -f "$LEDGER" ]; then n_fire=$(wc -l < "$LEDGER" | tr -d ' '); else n_fire=0; fi
payload 'git commit -m "use sed -i somewhere"' | sh "$HOOK" >/dev/null 2>&1 || true
if [ -f "$LEDGER" ]; then n_silent=$(wc -l < "$LEDGER" | tr -d ' '); else n_silent=0; fi
if [ "$n_fire" = "1" ] && [ "$n_silent" = "1" ]; then
  PASS=$((PASS + 1)); printf 'PASS  AC9  a fire appends one ledger line; a silent call appends none\n'
else
  FAIL=$((FAIL + 1)); printf 'FAIL  AC9  ledger lines fire=%s silent=%s want 1 and 1\n' "$n_fire" "$n_silent"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
