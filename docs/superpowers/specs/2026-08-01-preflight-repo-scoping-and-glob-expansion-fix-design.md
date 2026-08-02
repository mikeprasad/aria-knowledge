# Preflight gate — repo scoping + glob-expansion fix (design)

**Date:** 2026-08-01
**Status:** IMPLEMENTED — all four questions ruled by Mike 2026-08-01; shipped as **2.44.1**,
a patch on top of the unpushed 2.44.0 (Q1 — no history rewrite). Tests red-first, 105/0 green.
**Uncommitted and unpushed** — awaiting a separate go. See §9 for the implementation record,
including two corrections to this spec found during execution.
**Port:** `plugin-claude-code` only (sole carrier of the hook; verified by `find`).
**Baseline:** local `main` @ `aad5fd3`, **4 commits ahead of `origin/main`, unpushed.**
**Trigger:** `/setup` run on 2026-08-01 (v2.43.1 → v2.44.0) surfaced `preflight_gate` /
`preflight_deny_paths` as absent from the live config. Populating them exposed both defects below.

---

## 1. Why this exists

Two defects in `bin/pre-commit-preflight-check.sh`, both **measured, not inferred**, and both in
**unreleased** code — commits `012f6e0` / `9ec038a` / `aad5fd3` are unpushed, so no user has ever
run the broken version. That is the cheapest possible moment to fix this.

### D1 — deny-path patterns are expanded against the hook's cwd (silent under-coverage)

```sh
elif [ -n "$KT_PREFLIGHT_DENY_PATHS" ]; then
  for f in $CODE_FILES; do
    for pat in $KT_PREFLIGHT_DENY_PATHS; do     # <-- unquoted: PATHNAME EXPANSION
      case "$f" in $pat) MATCHED="yes"; break 2 ;; esac
```

`for pat in $KT_PREFLIGHT_DENY_PATHS` is an unquoted expansion, so each pattern word is subject to
pathname expansion **before `case` ever sees it**. Measured:

| cwd | configured pattern | what the loop actually iterates | consequence |
|---|---|---|---|
| `cs/commonspace-ui-v3` | `src/*` | **17 literal words** (`src/App.js`, `src/assets`, …) | staged `src/components/Foo.jsx` matches none → **no deny** |
| `df/df-ui/df-working/src/designframe` | `*df-input.css` | `df-input.css` (leading `*` lost) | staged `df-working/src/designframe/df-input.css` → **no deny** |
| a cwd with no matching entry | `*df-input.css` | `*df-input.css` (unchanged) | denies correctly |

So the gate's behaviour depends on **where the Bash tool happened to be**, and the failure direction
is *fail-open* — it silently stops denying. Any pattern containing a glob metacharacter is affected;
metacharacter-free literals are safe but cannot express a directory or a suffix.

This is `guard_scoped_to_the_wrong_unit`: the guard is green because its scope is wrong, and no
threshold or pattern change fixes it.

### D2 — there is no way to scope the gate to a repository

Mike's actual requirement: *"always gate on anything in `commonspace-app` and `commonspace-ui-v3`."*

`preflight_deny_paths` cannot express it. `REPO_DIR` is resolved (lines 51–58) **solely** to run
`git -C "$REPO_DIR" diff --cached --name-only`; it never enters the matching. Staged paths are
repo-relative, so committing in `commonspace-app` yields `payment_gateway/views.py` — the repo name
appears nowhere in the string a pattern is matched against. `*commonspace-app/*` matches nothing.

The only mechanism that satisfies "always" today is `preflight_gate: deny`, which gates **every code
commit in every repo** — correct but a blunt superset, and it discards the per-repo intent.

---

## 2. Scope

**In:** the two defects above, their tests, and the config/doc surfaces that enumerate the keys.

**Out (explicitly):**
- The docs filter's exclusion of `*.md` — see Q4; a real residual, but a separate decision.
- Any change to gate semantics (`off`/`warn`/`deny`), the session marker, the circuit breaker, or
  the fail-open contract. All are correct and tested.
- Cross-port propagation. `plugin-antigravity` and `plugin-openai-codex` do **not** carry this hook.

---

## 3. Design

### D1 fix — `set -f`

Disable pathname expansion once, immediately after `STAGED` is captured:

```sh
STAGED=$(git -C "$REPO_DIR" diff --cached --name-only 2>/dev/null) || exit 0
[ -z "$STAGED" ] && exit 0
set -f   # path lists and deny patterns are DATA; never re-glob them against cwd
```

Why here and not around the deny block alone: the docs-filter loop (`for f in $STAGED`) has the
same latent flaw, and `CODE_FILES` is built from it. One `set -f` covers every list iteration.

Verified safe for the remainder of the script: `case` glob-matching is **unaffected** by `set -f`
(only word-expansion globbing is), and lines 85–148 use only `printf`/`tr`/`grep`/`head`. No
`set +f` restore is needed inside the hook — it runs as its own process.

**But the test suite needs one.** `tests/run.sh` *sources* every `test-*.sh` into a single shell
(`for t in "$DIR"/test-*.sh; do . "$t"; done`), so any `set -f` leaked by a test contaminates the
tests that follow. New tests that manipulate cwd or shell options must run in a subshell or restore
explicitly. This is itself a test case (T3).

### D2 — new key `preflight_deny_repos`

Comma-separated substrings matched against the target repo's **absolute toplevel path**:

```
preflight_deny_repos: commonspace-app,commonspace-ui-v3
```

Semantics, deliberately mirroring `preflight_deny_paths`:

- An **escalation**, independent of the baseline — it denies from `warn` exactly as the path list
  does. Not a sub-setting of `gate: deny`. (This is the lesson `aad5fd3` already encoded: a key
  gated behind another setting is a key the user sets, sees no effect from, and calls broken.)
- Empty / absent = no escalation. **No default**, same as `critical_paths` and `preflight_deny_paths`.
- Inert when `gate: off` (the hook exits at line 46 before any matching).

Implementation sketch — insert as a third arm, preserving the existing "name the ACTUAL reason"
discipline so the message sends the user to the key that actually denied:

```sh
REPO_TOP=$(git -C "$REPO_DIR" rev-parse --show-toplevel 2>/dev/null)
[ -z "$REPO_TOP" ] && REPO_TOP="$REPO_DIR"

if [ "$GATE" = "deny" ]; then
  MATCHED="yes"; WHY_KEY="gate"
elif [ -n "$KT_PREFLIGHT_DENY_REPOS" ] && repo_matches "$REPO_TOP"; then
  MATCHED="yes"; WHY_KEY="repos"
elif [ -n "$KT_PREFLIGHT_DENY_PATHS" ]; then
  ... existing path loop ...      # WHY_KEY="paths"
fi
```

`REPO_TOP` resolution matters: `REPO_DIR` defaults to `.` when the command carries no `cd` or
`git -C` (line 57), so the raw value is frequently `.` and must be resolved before matching.

**Matching is substring, on the absolute path, case-sensitive.** Consequences, accepted knowingly:

- `commonspace-app` matches `/Users/…/cs/commonspace-app` ✓
- `cs/commonspace` covers both CS repos in one token ✓
- a sibling like `commonspace-app-fork` would **also** match ✗

The over-match is the correct failure direction for a gate: it fails **closed**. Under-matching is
what D1 already proved dangerous — a gate that silently stops gating. Exact-basename equality is the
alternative; see Q3.

---

## 4. Rejected alternatives

| Alternative | Why rejected |
|---|---|
| `IFS=' ' read -ra PATS` + `"${PATS[@]}"` | **Not POSIX.** The hook declares `# shellcheck shell=sh` and the suite invokes it via `sh "$HOOK"`. Bash arrays would break both. (This was proposed in the /setup dialog preview and is wrong.) |
| Quote the pattern (`case "$f" in "$pat")`) | Kills glob-matching entirely — `*df-input.css` would only match that literal string. Fixes expansion by removing the feature. |
| Glob list approximating the two repos' top-level dirs | Fails on D1 (all such patterns contain `*`), **and** silently stops covering a newly-added Django app dir. Under-covers by construction. |
| `preflight_gate: deny` as the answer to D2 | Works and cannot silently miss, but gates every repo and throws away the per-repo requirement. Retained as the documented interim posture — see Q2. |
| Custom `PreToolUse` hook in `Projects/.claude/settings.json` | Precise, but duplicates plugin logic into user settings and leaves the plugin defect live for every other user. |
| Match repo by `git config remote.origin.url` | More precise than a path substring, but breaks for local-only repos (which several of Mike's are) and costs another subprocess. |

---

## 5. Test plan — every assertion seen RED before the fix

Extends `tests/test-preflight-gate.sh` (139 lines, already covers docs exclusion, `gate: off`,
marker satisfaction, baseline/escalation independence, typo→warn, circuit breaker, fail-open).
The existing suite never runs a metacharacter pattern from a cwd where it expands — **that gap is
exactly why D1 survived.**

| # | Case | Expected | Red before fix? |
|---|---|---|---|
| T1 | cwd holds `decoy.py`; `deny_paths=*.py`; staged `app.py` | DENY | yes — expands to `decoy.py`, no match |
| T2 | cwd holds `df-input.css`; `deny_paths=*df-input.css`; staged `sub/df-input.css` | DENY | yes — leading `*` lost |
| T3 | after a hook run, globbing still enabled in the sourcing shell | no leak | n/a — guards the fix |
| T4 | `deny_repos=commonspace-app`; repo toplevel under a dir of that name | DENY | yes — key does not exist |
| T5 | `deny_repos=other-repo`; non-matching repo | warn, **not** deny | yes |
| T6 | denial message cites `preflight_deny_repos`, not gate or paths | correct attribution | yes |
| T7 | command with no `cd` / `git -C` (so `REPO_DIR="."`) still resolves + matches | DENY | yes |
| T8 | `deny_repos` empty → no escalation | warn | regression guard |

T1/T2 must be written so the decoy file placement is explicit and the cwd is controlled — a test
that inherits an arbitrary cwd would pass or fail by accident, which is the same class of bug.

---

## 6. Propagation set (7 surfaces)

Derived by `grep -rl 'preflight_deny_paths'` plus the config-table survey — not from memory.

1. `bin/pre-commit-preflight-check.sh` — `set -f`; third escalation arm; reason attribution.
2. `bin/config.sh` — parse `preflight_deny_repos`; no default; extend the "independent of the gate"
   comment block that already documents `preflight_deny_paths`.
3. `tests/test-preflight-gate.sh` — T1–T8.
4. `skills/setup/SKILL.md` — Advanced Options bundle (Step 6), config template (Step 7),
   round-trip validation list (Step 7b). **Step 7e's field count moves 38 → 39.**
5. `skills/preflight/SKILL.md` — references `preflight_deny_paths`; add the repo key.
6. `CONFIG.md` — **currently documents none of the preflight keys.** Its "Hook-parsed fields" table
   is missing `preflight_gate` and `preflight_deny_paths` as well; this closes all three at once.
7. `.claude-plugin/plugin.json` — version. See Q1.

---

## 7. Open questions

**Q1 — RULED 2026-08-01: ship as 2.44.1, a patch on top.** The unpushed 2.44.0 commits
(`012f6e0` / `9ec038a` / `aad5fd3`) are **not** rewritten. Rejected: folding the fix into them, which
would have meant no broken 2.44.0 ever existed publicly but required rewriting unpushed history
against `forward_fix_over_history_rewrite`. Consequence to carry: 2.44.0 exists in local history as
a version whose deny-path matching is cwd-dependent — the CHANGELOG entry for 2.44.1 should say so
plainly rather than describe the fix as a refinement.

**Q2 — RULED 2026-08-01: clear the live value.** `preflight_deny_paths` is now empty in
`~/.claude/aria-knowledge.local.md`; `preflight_gate` stays `warn`. Rejected: leaving the fragile
value (false confidence), and `gate: deny` (would have satisfied the CS requirement immediately but
gated every repo). ⚠ **Interim posture is therefore WARN-ONLY — nothing is hard-gated until 2.44.1
lands.** This is a knowing acceptance, not an oversight: the requirement that prompted all of this
is unmet in the meantime.

**Q3 — RULED 2026-08-01: substring on the absolute path.** Implemented as specced in §3. Rejected:
exact-basename equality — more precise, but it fails OPEN on a renamed or nested repo, the same
direction as the D1 bug. Accepted cost: a same-named `-fork` sibling also matches.

**Q4 — RULED 2026-08-01: leave docs excluded.** The docs filter is unchanged; no
`preflight_include_docs` key. **The consequence is deliberate and must not be forgotten: a
docs-only commit in a gated repo still passes silently**, so "always gate anything in this repo"
is satisfied for code and not for documentation, and the original `CLAUDE.md` / `rules/*` intent
from the /setup dialog stays out of reach. Test `[14g]` pins this as intended behaviour rather
than leaving it to be rediscovered as a bug.

---

## 9. Implementation record — 2026-08-01

Shipped as **2.44.1**, all four questions ruled. Tests written first; **every new positive
assertion was observed FAILING before the corresponding fix** (5 red → green), and the suite
finished **105 passed / 0 failed**.

What the red-first run actually proved, and one thing it caught in the tests themselves:

- D1's two cases and D2's three failed exactly as predicted. The non-vacuity guard `[13a]`
  passed from the start, confirming the decoy directory really does expand `*.py` — without it,
  `[13b]` could have gone green for the wrong reason.
- A sixth failure was **my own test bug**: the no-leak guard compared `pwd` against `$ROOT`, a
  directory `run.sh` does not guarantee. Fixed by capturing cwd before the cases and comparing
  against that.
- **Case `[8]` in the pre-existing suite was the same D1 bug lying dormant** — it configures
  `*.py` and passed only because the runner's cwd happened to hold no `.py` file. `set -f` makes
  it deterministic. The test written to prove the feature worked was itself cwd-dependent.

Two corrections to this spec, both found during execution:

1. **§6 undercounted the propagation set at 7 — it is 8.** `CHANGELOG.md` was missing because §6
   was derived from `grep -rl 'preflight_deny_paths'`, and a file that never mentioned the feature
   cannot appear in that census. The instrument bounded the result. (`CHANGELOG.md` had no 2.44.0
   entry either, so 2.44.1 carries one combined entry rather than inventing a release that never
   shipped.)
2. **`/setup` Step 6 never offered the preflight keys at all** — they appeared only in the Step 7
   write template and Step 7b validation. That is *why* a config could run for months without them
   and only surface via Step 7e's dynamic sweep. The Advanced Options bundle now lists all three.

### 9a. Follow-on — `/auto` must satisfy the gate, not collide with it

Requested by Mike immediately after implementation, and a real hazard: `/auto` had **zero**
awareness of the commit gate. Under a configured `preflight_deny_repos`, an unattended arc would
not stall politely — it would take three denials, **trip the circuit breaker, and degrade the
user's gate to allow-with-warning for the rest of the session**, then carry on. The failure mode
is not a stuck arc; it is a silently disabled guard.

`/auto` now runs `/preflight` for real before the first gated commit (one session-scoped run
clears the arc), with three prohibitions stated explicitly because each is a tempting shortcut
that *looks* like progress: never write the marker file, never flip `preflight_gate: off` or edit
the user's config to widen its own permissions, never let the breaker do the work. A recorded FAIL
satisfies the gate and is **not** a stop. Added to Commit discipline, the Pre-answered set, and the
Step 0.5 arc contract; guarded by 7 new assertions in `tests/repros/auto-modes.sh`.

**Two of those 7 assertions were tautologies on first write** and were caught only by running them
against the pre-edit file: `circuit breaker|degrade` matched an unrelated "Degrade gracefully"
paragraph, and `pre-answered|handle and keep going` matched the section heading. Both would have
passed no matter what `/auto` said about the gate. Re-anchored on wording unique to the new
guidance; all 7 now verified red-on-HEAD, green-on-edit. Suites: **142 repro + 105 plugin**.

### 9c. The `/auto preflight` collision — RESOLVED, retired not repurposed

Flagged in this spec as out-of-scope, then ruled by Mike the same session. `/auto preflight` was a
long-standing alias for `/auto config` (the settings picker); once `/preflight` shipped as a real
skill, one word named a settings picker in one place and a verification gate in another.

**Retired, not repurposed** — every candidate new meaning is already owned. "Run the checklist" is
`/preflight` standalone, and an arc now runs it automatically when the commit gate demands it
(§9a); "check the plan before executing" is `/prospect`, already in the chain. A third spelling
would add a word and no capability, which is verbatim the reasoning that retired the `loop`
modifier in v2.43.0.

**Retired ≠ deleted, and that distinction is the whole point.** Bare removal lets `preflight` fall
through to `mode = arc`, so `/auto full preflight` would silently launch an autonomous arc to build
something called "preflight" — a retired word turning into a work order, which is strictly worse
than the collision it replaced. The parser now recognises the token, runs nothing, and routes to
`/preflight` or `/auto config`. Tombstoned in the same italic-parenthetical form as `loop`, so the
two retirements read as one convention.

Guarded by a new `Y2` group in `auto-modes.sh` (alias gone · not a mode keyword · cannot fall
through to a goal · tombstone present), all four verified red-on-HEAD.

⚠ **This also exposed a test the §9a work had silently weakened.** Assertion `Y` proved "config
mode present" via `grep -qiE '/auto config|`config`|preflight'` — and the ~10 `/preflight`
references added in §9a made that third alternative match unconditionally, so `Y` could no longer
fail. Adding prose to a file can neuter a grep-based guard elsewhere in the suite: the guard did not
change, its corpus did. Alternative dropped; `Y` now matches only on the config spellings.

### 9b. Activation

Installed to `~/.claude/plugins/marketplaces/local-desktop-app-uploads/aria-knowledge/` (prior
2.44.0 cache backed up first; `diff -r --exclude=tests` against source returns identical), and
`preflight_deny_repos: commonspace-app,commonspace-ui-v3` set in the live config. Verified against
the **installed** hook and the **real** config: both repos deny with correct attribution, an
unrelated repo warns only, a recorded preflight clears the gate, and a docs-only commit in a gated
repo stays silent (the Q4 residual, behaving as ruled).

Verification boundary — what was NOT run: `./release.sh` (Gates A/B/C) was blocked by the auto-mode
classifier and is release ceremony, outside the granted scope. **Gate B was verified directly
instead**: it measures skill frontmatter descriptions only, and `git diff` confirms no
`description:`/`name:`/`allowed-tools:` line was added or removed. Both edited shell scripts pass
`sh -n`; shellcheck is not installed on this machine, so no lint run was performed. Nothing is
committed or pushed.

---

## 8. Related

- `feedback_guard_scoped_to_the_wrong_unit` — D1's failure shape.
- `feedback_grep_call_sites_not_presence_declared_unwired_is_systemic` — the hook *is* wired
  (`.claude-plugin/plugin.json:82`, PreToolUse); the plugin ships no `hooks/` dir, so a hooks-dir
  grep returns exit 2 and must not be read as unwired.
- `feedback_regression_test_needs_its_own_mutation_check` — §5's red-before-fix requirement.
- Commit `aad5fd3` — established the baseline-vs-escalation independence that `deny_repos` inherits.
