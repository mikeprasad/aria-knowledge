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

pf_cfg() { # GATE DENY_PATHS -> path to a config fixture
  printf -- '---\nknowledge_folder: %s/kf\npreflight_gate: %s\npreflight_deny_paths: %s\n---\n' \
    "$PF_TMP" "$1" "$2" > "$PF_TMP/cfg.md"
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

# [7] gate=deny with no paths named = deny on all code (strictest reading of opt-in)
pf_fresh pf7
out=$(pf_run "$(pf_cfg deny "")" pf7 "cd $PF_CODE && git commit -m x")
assert_eq "deny + no paths -> denies" "1" "$(pf_has '"deny"' "$out")"

# [8] gate=deny only bites the paths the user named; everything else still warns
pf_fresh pf8
out=$(pf_run "$(pf_cfg deny "payments/*")" pf8 "cd $PF_CODE && git commit -m x")
assert_eq "deny + non-matching path -> warns" "1" "$(pf_has 'additionalContext' "$out")"
assert_eq "deny + non-matching path does NOT deny" "0" "$(pf_has '"deny"' "$out")"

pf_fresh pf9
out=$(pf_run "$(pf_cfg deny "*.py")" pf9 "cd $PF_CODE && git commit -m x")
assert_eq "deny + matching path -> denies" "1" "$(pf_has '"deny"' "$out")"

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

out=$(pf_run "$CFG_DENY" pf13 "cd /nonexistent-repo-xyz && git commit -m x")
assert_eq "nonexistent repo -> fail open" "" "$out"

# [12] nothing staged (e.g. `git commit -a`, which cannot be enumerated safely)
PF_EMPTY="$PF_TMP/empty"; mkdir -p "$PF_EMPTY"; pf_repo "$PF_EMPTY"
pf_fresh pf14
out=$(pf_run "$CFG_DENY" pf14 "cd $PF_EMPTY && git commit -m x")
assert_eq "nothing staged -> fail open" "" "$out"
