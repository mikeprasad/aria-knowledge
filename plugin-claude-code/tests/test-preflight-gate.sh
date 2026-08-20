# shellcheck shell=sh
# test-preflight-gate.sh — pre-commit-preflight-check.sh fires on `git commit` and
# warns when no preflight was recorded this session; escalation to deny is opt-in
# via preflight_gate + preflight_deny_paths, and every unreadable input fails OPEN.
#
# The fail-open cases are not padding. This hook can block a commit, so "the gate
# could not read its inputs" must be indistinguishable from "the gate approved" —
# a guard that denies on garbage input is worse than no guard at all.
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$ROOT/bin/pre-commit-preflight-check.sh"

PF_TMP="${APM_TMP:-/tmp}/preflight-gate"; rm -rf "$PF_TMP"; mkdir -p "$PF_TMP"

# Two throwaway repos: one with code staged, one with docs only.
pf_repo() { # DIR
  git -C "$1" init -q . 2>/dev/null
  git -C "$1" config user.email t@t.t; git -C "$1" config user.name t
}
PF_CODE="$PF_TMP/code"; mkdir -p "$PF_CODE/docs"; pf_repo "$PF_CODE"
echo code > "$PF_CODE/app.py"; echo doc > "$PF_CODE/docs/a.md"
git -C "$PF_CODE" add . 2>/dev/null

PF_DOCS="$PF_TMP/docsonly"; mkdir -p "$PF_DOCS/docs"; pf_repo "$PF_DOCS"
echo doc > "$PF_DOCS/docs/a.md"; echo doc > "$PF_DOCS/README.md"
git -C "$PF_DOCS" add . 2>/dev/null

pf_cfg() { # GATE DENY_PATHS [DENY_REPOS] -> path to a config fixture
  printf -- '---\nknowledge_folder: %s/kf\npreflight_gate: %s\npreflight_deny_paths: %s\npreflight_deny_repos: %s\n---\n' \
    "$PF_TMP" "$1" "$2" "${3:-}" > "$PF_TMP/cfg.md"
  printf '%s' "$PF_TMP/cfg.md"
}

pf_run() { # CFG SESSION_ID COMMAND
  printf '{"session_id":"%s","tool_input":{"command":"%s"}}' "$2" "$3" \
    | KT_CONFIG="$1" sh "$HOOK" 2>/dev/null
}

pf_has() { case "$2" in *"$1"*) echo 1 ;; *) echo 0 ;; esac; }
pf_fresh() { rm -f "${TMPDIR:-/tmp}/aria-preflight-$1" "${TMPDIR:-/tmp}/aria-preflight-denies-$1"; }

CFG_WARN=$(pf_cfg warn "")

# [1] a command that is not a commit is none of this hook's business
pf_fresh pf1
out=$(pf_run "$CFG_WARN" pf1 "ls -la")
assert_eq "non-commit command is silent" "" "$out"

# [2] code commit with no recorded preflight -> warn (never deny at default)
pf_fresh pf2
out=$(pf_run "$CFG_WARN" pf2 "cd $PF_CODE && git commit -m x")
assert_eq "no marker -> warns" "1" "$(pf_has 'additionalContext' "$out")"
assert_eq "default gate never denies" "0" "$(pf_has '"deny"' "$out")"

# [3] the docs file is excluded from the count, so the warning names only real code
assert_eq "docs excluded from changed-file count" "1" "$(pf_has '1 changed file(s)' "$out")"

# [4] a recorded preflight satisfies the gate — ANY verdict, including NOT READY.
# Recording a FAIL and committing anyway is a visible choice; not running the
# checks at all is the failure being guarded against.
pf_fresh pf4
printf '12:00\tNOT READY\tapp.py\n' > "${TMPDIR:-/tmp}/aria-preflight-pf4"
out=$(pf_run "$CFG_WARN" pf4 "cd $PF_CODE && git commit -m x")
assert_eq "recorded NOT READY still satisfies the gate" "" "$out"
rm -f "${TMPDIR:-/tmp}/aria-preflight-pf4"

# [5] docs-only commit is silent even under the strictest configuration
pf_fresh pf5
out=$(pf_run "$(pf_cfg deny "")" pf5 "cd $PF_DOCS && git commit -m x")
assert_eq "docs-only silent even at gate=deny" "" "$out"

# [6] gate=off disables it entirely
pf_fresh pf6
out=$(pf_run "$(pf_cfg off "")" pf6 "cd $PF_CODE && git commit -m x")
assert_eq "gate=off is silent" "" "$out"

# --- baseline and escalation are INDEPENDENT --------------------------------
# preflight_gate is the baseline for every code commit; preflight_deny_paths escalates
# from ANY baseline, exactly as critical_paths escalates Rule 22 severity regardless of
# the surrounding setting. The first shape of this hook gated the path list behind
# gate=deny, which made the key silently inert at the DEFAULT setting — a config the
# user sets, sees no effect from, and reasonably concludes is broken.

# [7] gate=deny denies every code commit; the path list is irrelevant to it
pf_fresh pf7
out=$(pf_run "$(pf_cfg deny "")" pf7 "cd $PF_CODE && git commit -m x")
assert_eq "deny + no paths -> denies" "1" "$(pf_has '"deny"' "$out")"

pf_fresh pf8
out=$(pf_run "$(pf_cfg deny "payments/*")" pf8 "cd $PF_CODE && git commit -m x")
assert_eq "deny still denies a NON-matching path" "1" "$(pf_has '"deny"' "$out")"
assert_eq "deny cites the gate, not the path list" "1" "$(pf_has 'preflight_gate is set to deny' "$out")"

# [8] THE COMMON CASE — warn baseline, deny on the paths the user named.
# This combination could not deny at all under the previous semantics.
pf_fresh pf9
out=$(pf_run "$(pf_cfg warn "*.py")" pf9 "cd $PF_CODE && git commit -m x")
assert_eq "warn + MATCHING path -> denies" "1" "$(pf_has '"deny"' "$out")"
assert_eq "warn+path deny cites the path list" "1" "$(pf_has 'preflight_deny_paths' "$out")"

pf_fresh pf9b
out=$(pf_run "$(pf_cfg warn "payments/*")" pf9b "cd $PF_CODE && git commit -m x")
assert_eq "warn + non-matching path -> warns" "1" "$(pf_has 'additionalContext' "$out")"
assert_eq "warn + non-matching path does NOT deny" "0" "$(pf_has '"deny"' "$out")"

# [9] an unrecognized gate value falls back to WARN, never to off. A typo in config
# must not silently disable a gate the user believed was on.
pf_fresh pf10
out=$(pf_run "$(pf_cfg dney "")" pf10 "cd $PF_CODE && git commit -m x")
assert_eq "typo'd gate value -> warn, not off" "1" "$(pf_has 'additionalContext' "$out")"

# [10] circuit breaker: 3 denials, then degrade to allow-with-warning. Same contract
# as pre-edit-check.sh — a gate that can deadlock a session gets disabled for good.
pf_fresh pf11
CFG_DENY=$(pf_cfg deny "")
d1=$(pf_run "$CFG_DENY" pf11 "cd $PF_CODE && git commit -m x")
d2=$(pf_run "$CFG_DENY" pf11 "cd $PF_CODE && git commit -m x")
d3=$(pf_run "$CFG_DENY" pf11 "cd $PF_CODE && git commit -m x")
d4=$(pf_run "$CFG_DENY" pf11 "cd $PF_CODE && git commit -m x")
assert_eq "breaker: denial 3 still denies" "1" "$(pf_has '"deny"' "$d3")"
assert_eq "breaker: denial 4 degrades to allow" "0" "$(pf_has '"deny"' "$d4")"
assert_eq "breaker: degraded state says so loudly" "1" "$(pf_has 'DEGRADED' "$d4")"

# [11] fail-open — every input the hook cannot read must behave as approval
pf_fresh pf12
out=$(printf '{"tool_input":{"command":"cd %s && git commit -m x"}}' "$PF_CODE" | KT_CONFIG="$CFG_DENY" sh "$HOOK" 2>/dev/null)
assert_eq "no session_id -> fail open" "" "$out"

out=$(printf 'not json at all' | KT_CONFIG="$CFG_DENY" sh "$HOOK" 2>/dev/null)
assert_eq "garbage stdin -> fail open" "" "$out"

# Run this one from INSIDE a repo that has staged code, so the assertion can
# actually fail. Previously it ran from the test runner's cwd -- the real
# aria-knowledge checkout -- and the hook's cwd fallback enumerated whatever the
# developer happened to have staged. That made "" ambiguous: it meant BOTH "the
# hook failed open on the nonexistent repo" AND "the hook read cwd and found
# nothing staged", so the assertion was vacuous whenever it passed and produced a
# spurious failure whenever someone had files staged. With cwd = $PF_CODE (which
# has app.py staged), a cwd fallback would DENY, so "" now proves the hook
# resolved /nonexistent-repo-xyz and failed open.
out=$(cd "$PF_CODE" && pf_run "$CFG_DENY" pf13 "cd /nonexistent-repo-xyz && git commit -m x")
assert_eq "nonexistent repo -> fail open" "" "$out"

# fixture-armed control: from that same cwd, a commit with NO `cd` must be seen,
# or the assertion above passes for the wrong reason (an unarmed fixture).
pf_fresh pf13b
out=$(cd "$PF_CODE" && pf_run "$CFG_DENY" pf13b "git commit -m x")
assert_eq "fixture armed: staged code in cwd does deny" 1 "$(pf_has 'PREFLIGHT REQUIRED' "$out")"

# [12] nothing staged (e.g. `git commit -a`, which cannot be enumerated safely)
PF_EMPTY="$PF_TMP/empty"; mkdir -p "$PF_EMPTY"; pf_repo "$PF_EMPTY"
pf_fresh pf14
out=$(pf_run "$CFG_DENY" pf14 "cd $PF_EMPTY && git commit -m x")
assert_eq "nothing staged -> fail open" "" "$out"

# --- deny patterns are DATA, not a glob to expand against the hook's cwd -----
# `for pat in $KT_PREFLIGHT_DENY_PATHS` is an unquoted expansion, so without `set -f`
# each pattern word is PATHNAME-EXPANDED before `case` ever sees it. Measured before
# the fix: from a dir holding `decoy.py`, the pattern `*.py` became the literal word
# `decoy.py` and stopped matching the staged `app.py` — the gate silently stopped
# denying, and which files were protected depended on where the tool happened to be.
#
# Case [8] above is the same bug lying dormant: it configures `*.py` and passes only
# because the runner's cwd happens to hold no .py file. These cases make it explicit.

PF_DECOY="$PF_TMP/decoy"; mkdir -p "$PF_DECOY"
: > "$PF_DECOY/decoy.py"; : > "$PF_DECOY/theme.css"
# Captured, not hardcoded: run.sh may be invoked from any directory, so the leak guard
# below has to compare against where we actually started, not against $ROOT.
PF_CWD_BEFORE=$(pwd)

# [13a] NON-VACUITY GUARD — prove the trap is actually armed. If the decoy files were
# not created, [13b]/[13c] would pass for the wrong reason and read as a false green.
expanded=$(cd "$PF_DECOY" && set +f && for p in *.py; do printf '%s' "$p"; done)
assert_eq "decoy dir really does expand *.py (trap armed)" "decoy.py" "$expanded"

# [13b] a metacharacter pattern must match by its PATTERN, not by what cwd contains
pf_fresh pf15
out=$(cd "$PF_DECOY" && pf_run "$(pf_cfg warn '*.py')" pf15 "cd $PF_CODE && git commit -m x")
assert_eq "deny pattern survives a cwd that would expand it" "1" "$(pf_has '"deny"' "$out")"

# [13c] a leading-* suffix pattern must keep its leading *, so it still matches a
# path SEGMENT rather than only a bare basename
PF_NEST="$PF_TMP/nested"; mkdir -p "$PF_NEST/sub"; pf_repo "$PF_NEST"
: > "$PF_NEST/sub/theme.css"
git -C "$PF_NEST" add . 2>/dev/null
pf_fresh pf16
out=$(cd "$PF_DECOY" && pf_run "$(pf_cfg warn '*theme.css')" pf16 "cd $PF_NEST && git commit -m x")
assert_eq "leading-* pattern still matches a nested path" "1" "$(pf_has '"deny"' "$out")"

# [13d] the suite itself must not leak cwd into the cases that follow (run.sh SOURCES
# every test-*.sh into one shell, so a stray `cd` or `set -f` contaminates siblings)
assert_eq "no cwd leak from the expansion cases" "$PF_CWD_BEFORE" "$(pwd)"

# --- preflight_deny_repos — escalation scoped to a REPOSITORY ----------------
# preflight_deny_paths cannot express "always gate this repo": staged paths are
# repo-relative, so the repo name appears nowhere in the string a pattern matches.
# This key matches the resolved absolute toplevel instead. Substring, deliberately:
# it OVER-matches (a `-fork` sibling also matches), and for a gate that is the safe
# direction — under-matching is exactly the silent-stop failure [13b] guards against.

PF_GATED="$PF_TMP/gated-repo"; mkdir -p "$PF_GATED"; pf_repo "$PF_GATED"
echo code > "$PF_GATED/app.py"; git -C "$PF_GATED" add . 2>/dev/null

# [14a] a matching repo denies from the WARN baseline (escalation, not a sub-setting)
pf_fresh pf17
out=$(pf_run "$(pf_cfg warn '' 'gated-repo')" pf17 "cd $PF_GATED && git commit -m x")
assert_eq "warn + matching repo -> denies" "1" "$(pf_has '"deny"' "$out")"
assert_eq "repo deny cites preflight_deny_repos" "1" "$(pf_has 'preflight_deny_repos' "$out")"

# [14b] a non-matching repo is untouched
pf_fresh pf18
out=$(pf_run "$(pf_cfg warn '' 'some-other-repo')" pf18 "cd $PF_GATED && git commit -m x")
assert_eq "warn + non-matching repo -> warns" "1" "$(pf_has 'additionalContext' "$out")"
assert_eq "warn + non-matching repo does NOT deny" "0" "$(pf_has '"deny"' "$out")"

# [14c] empty list = no escalation (regression guard: an empty key must stay inert)
pf_fresh pf19
out=$(pf_run "$(pf_cfg warn '' '')" pf19 "cd $PF_GATED && git commit -m x")
assert_eq "empty deny_repos -> no escalation" "0" "$(pf_has '"deny"' "$out")"

# [14d] REPO_DIR defaults to "." when the command carries no `cd` / `git -C`, so the
# toplevel must be RESOLVED before matching or the key silently never fires
pf_fresh pf20
out=$(cd "$PF_GATED" && pf_run "$(pf_cfg warn '' 'gated-repo')" pf20 "git commit -m x")
assert_eq "repo match works with an implicit (cwd) repo dir" "1" "$(pf_has '"deny"' "$out")"

# [14e] attribution precedence — gate=deny is the baseline and owns the message even
# when a repo token also matches. Blaming the key that did not decide sends the user
# to edit the wrong thing.
pf_fresh pf21
out=$(pf_run "$(pf_cfg deny '' 'gated-repo')" pf21 "cd $PF_GATED && git commit -m x")
assert_eq "gate=deny outranks repos in attribution" "1" "$(pf_has 'preflight_gate is set to deny' "$out")"

# [14f] gate=off outranks everything — a disabled gate stays disabled
pf_fresh pf22
out=$(pf_run "$(pf_cfg off '' 'gated-repo')" pf22 "cd $PF_GATED && git commit -m x")
assert_eq "gate=off silences a repo match" "" "$out"

# [14g] a docs-only commit stays silent even in a gated repo. Q4 (2026-08-01): this is
# the DELIBERATE residual — "always gate this repo" does not extend to docs, because a
# gate that fires on a README edit is the one that gets disabled wholesale.
PF_GATED_DOCS="$PF_TMP/gated-repo-docs"; mkdir -p "$PF_GATED_DOCS"; pf_repo "$PF_GATED_DOCS"
echo doc > "$PF_GATED_DOCS/README.md"; git -C "$PF_GATED_DOCS" add . 2>/dev/null
pf_fresh pf23
out=$(pf_run "$(pf_cfg warn '' 'gated-repo')" pf23 "cd $PF_GATED_DOCS && git commit -m x")
assert_eq "docs-only commit silent even in a gated repo" "" "$out"

# --- the admission guard admits a git commit, not a literal substring ---------
# The guard was `case "$COMMAND" in *"git commit"*)`, which is wrong in BOTH directions:
# it MISSED every `git -C <dir> commit` (a real commit whose text never contains the
# substring `git commit`) and MATCHED `git commit-tree` (because `git commit` is a prefix
# of it, contradicting the comment that claimed otherwise). Measured two-sided on one repo
# with one staged file: `cd <repo> && git commit` denied while `git -C <repo> commit` was
# silent.
#
# The false negative is the serious half — a scripted or `git -C` commit bypassed the gate
# entirely, including in a repo named by preflight_deny_repos, the strongest setting there
# is. The hook's own REPO_DIR extractor is written for exactly the `git -C` form and was
# therefore unreachable: the admission `case` had already exited. That unreachable branch is
# what proves the wider unit was intended rather than deliberately narrowed.
#
# `case` cannot express the distinction. Any pattern loose enough to admit
# `git -C /d commit` (e.g. `*"git "*" commit"*`) also admits `git status -m "commit "`.

# [15a] THE FALSE NEGATIVE — a `git -C` commit must be gated like any other
pf_fresh pf24
out=$(pf_run "$(pf_cfg warn '' 'gated-repo')" pf24 "git -C $PF_GATED commit -m x")
assert_eq "git -C <repo> commit denies in a gated repo" "1" "$(pf_has '"deny"' "$out")"

# [15b] and it reaches the warn baseline too, not just the deny escalation
pf_fresh pf25
out=$(pf_run "$CFG_WARN" pf25 "git -C $PF_CODE commit -m x")
assert_eq "git -C <repo> commit warns at the warn baseline" "1" "$(pf_has 'additionalContext' "$out")"

# [15c] THE FALSE POSITIVE — commit-tree is plumbing, not a commit
pf_fresh pf26
out=$(pf_run "$(pf_cfg deny '' '')" pf26 "cd $PF_CODE && git commit-tree HEAD^{tree}")
assert_eq "git commit-tree is not a commit" "" "$out"

# [15d] same for commit-graph — `commit` must match as a whole word
pf_fresh pf27
out=$(pf_run "$(pf_cfg deny '' '')" pf27 "cd $PF_CODE && git commit-graph write")
assert_eq "git commit-graph is not a commit" "" "$out"

# [15e] FUTURE-OVER-BROADENING GUARD — deliberately green in BOTH arms, so it is NOT
# evidence this change landed (the old guard also passes it: `git status -m "commit "`
# contains no `git commit` substring). It earns its place by failing against a naively
# widened FUTURE rewrite, which is the shape a `case`-based fix would have had.
pf_fresh pf28
out=$(pf_run "$(pf_cfg deny '' '')" pf28 "cd $PF_CODE && git status -m \\\"commit \\\"")
assert_eq "a subcommand merely mentioning commit is not a commit" "" "$out"

# [15f] the `-c key=value` global-option form is a real commit. Note the `cd` prefix is
# load-bearing for the FIXTURE, not for the guard: with neither `cd` nor `git -C` in the
# command, REPO_DIR falls back to `.` — the test RUNNER's cwd — so the repo token could
# never match and the assertion would fail for a reason unrelated to the admission guard.
pf_fresh pf29
out=$(pf_run "$(pf_cfg warn '' 'gated-repo')" pf29 "cd $PF_GATED && git -c user.email=t@t.t commit -m x")
assert_eq "git -c k=v commit denies in a gated repo" "1" "$(pf_has '"deny"' "$out")"

# [15g] REGRESSION GUARD — the form that already worked must keep working
pf_fresh pf30
out=$(pf_run "$(pf_cfg warn '' 'gated-repo')" pf30 "cd $PF_GATED && git commit -m x")
assert_eq "cd && git commit still denies in a gated repo" "1" "$(pf_has '"deny"' "$out")"
