# Plan — preflight admission guard: admit `git -C … commit`, reject `commit-tree`

**Date:** 2026-08-16
**Target release:** v2.46.1 (patch — bugfix, no schema change, no new config key)
**Surface:** `plugin-claude-code/bin/pre-commit-preflight-check.sh` (one runtime only; verified
byte-identical to the installed copy, so there is no source-vs-installed drift to reconcile)

## Problem — measured, not inferred

The hook's admission test is a literal substring:

```sh
# Only `git commit`. Not `git commit-tree`, not a message that mentions committing.
case "$COMMAND" in
  *"git commit"*) : ;;
  *) exit 0 ;;
esac
```

It is wrong in **both** directions. Measured two-sided against the same repo with the same
staged file, config `preflight_gate: warn` + `preflight_deny_repos: commonspace-app`:

| Command form | Observed | Expected |
|---|---|---|
| `cd <repo> && git commit -m x` | **DENY** | DENY |
| `git -C <repo> commit -m x` | **SILENT** | DENY |
| `git commit-tree HEAD^{tree}` | **DENY** | silent |

Two consequences worth stating separately:

1. **The false negative is the serious one.** Any scripted or `git -C` commit bypasses the
   gate entirely — including in a repo named by `preflight_deny_repos`, the strongest
   setting available.
2. **The hook's own code proves the wider unit was intended.** Lines 54–56 extract
   `REPO_DIR` from a `git -C` pattern. That branch is unreachable: line 38 has already
   exited on every command that would need it. This is not a deliberate narrowing that
   someone later forgot to document — it is a guard scoped to the wrong unit.

The false positive (`commit-tree`) contradicts the comment directly above the guard.
`git commit` is a prefix of `git commit-tree`, so the pattern never excluded it.

## Not in scope

**Q4 (the `docs/` path filter) is settled by ruling and is NOT touched.** Test case `[14g]`
pins docs-only silence as intended — "a gate that fires on a README edit is the one that
gets disabled wholesale" (Mike, 2026-08-01). Re-measured this session and it is also
*narrower* than the memory rows record: the `exit 0` is on `[ -z "$CODE_FILES" ]`, so a
**mixed** commit (docs + code) still denies. Latent regardless — 0 non-doc tracked files
under any `docs/` in commonspace-app, 3 in commonspace-ui-v3, all `.json`/`.html`.

## The fix

Replace the `case` with an ERE that encodes the actual grammar: `git`, then zero or more
option-like tokens (each starting with `-`, optionally followed by a non-`-` value), then
`commit` as a whole word.

```sh
printf '%s' "$COMMAND" | grep -qE \
  '(^|[[:space:];&|(])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$)' \
  || exit 0
```

Why not `case`: it cannot express "only option-like tokens between `git` and `commit`".
Any `case` pattern loose enough to admit `git -C /d commit` (e.g. `*"git "*" commit"*`)
also admits `git status -m "commit "`. That distinction is the whole point of the change.

Why the trailing `([[:space:]]|$)`: it is what rejects `commit-tree` and `commit-graph`.

Why the leading `(^|[[:space:];&|(])`: `git` must start a word, so `mygit commit` does not
match, and a compound `cd /a && git commit` does.

**Accepted residual, unchanged from today:** a command that merely *quotes* the phrase —
`echo "run git commit later"` — still matches. This is pre-existing, and it is the safe
direction for a gate that any single recorded `/preflight` satisfies for the whole session.

## Tasks

- **T1** — Add assertions to `plugin-claude-code/tests/test-preflight-gate.sh` and observe
  each RED against unmodified `HEAD`:
  - `[15a]` `git -C <repo> commit` denies in a deny-listed repo *(currently SILENT → RED)*
  - `[15b]` `git -C <repo> commit` warns at the warn baseline with code staged *(RED)*
  - `[15c]` `git commit-tree` is silent *(currently DENY → RED)*
  - `[15d]` `git commit-graph write` is silent *(RED)*
  - `[15e]` `git status -m "commit "` is silent — **FUTURE-over-broadening guard, NOT
    landing evidence.** Amended after `/prospect` falsified the original label: the old
    guard is `*"git commit"*`, and this command does not contain that substring, so the
    assertion is **green before AND after** and carries zero information about this change.
    It earns its place by failing against a naively-widened future rewrite (e.g. a `case`
    pattern like `*"git "*" commit"*`), not against today's code. The landing evidence is
    `[15a]`–`[15d]` going RED→GREEN.
  - `[15f]` `git -c user.email=t commit` denies — the `-c k=v` global-option form
  - `[15g]` `cd <repo> && git commit` still denies — regression guard on the working form
- **T2** — Apply the guard change + rewrite the comment to describe what it now does and
  why `case` was insufficient.
- **T3** — Run **both Gate A suites** and require **bare exit 0** on each (not piped — the
  exit code is the claim being made). Amended after `/prospect`: `release.sh:49-55` runs
  `tests/run.sh` *and* `plugin-claude-code/tests/run.sh`; the original plan baselined only
  the second. Baselines captured before any edit: **36 repro suites / 0 failed** and
  **139 passed / 0 failed**.
- **T4** — Mutation-check the new guard: revert the ERE to the old `case`, confirm
  `[15a]`–`[15d]` go RED and `[15e]`/`[15g]` stay GREEN; restore **byte-identically via
  `cmp`** from a worktree backup, never `git checkout` (which would discard the parallel
  session's uncommitted work).
- **T5** — Version bump `2.46.0 → 2.46.1` in
  `plugin-claude-code/.claude-plugin/plugin.json`; CHANGELOG entry.
- **T6** — Commit. Release from a **detached `git worktree` at the release commit**, not
  the working tree: a parallel session currently has 11 modified + 7 untracked files
  (a cursor-template port and an index-generator spec), and `release.sh` stages from
  `REPO_ROOT`, so a normal build would ship their WIP into a public artifact with no error.
  Verify two-sided: the worktree copy matches the **committed** file and **differs** from
  the dirty one.
- **T6b** *(new, added by `/prospect`)* — Copy the worktree-built canonical zip to the
  **main repo root**.
- **T7** — Push, `gh release create`, attach the 6 stable aliases, content-verify the
  **published** zip (download it; do not trust the upload).
  ⛔ **Run `publish-release.sh` from the MAIN REPO ROOT, never from the worktree.** The
  original plan said "release from a detached worktree" and did not separate build from
  publish. `publish-release.sh:71-80` requires four port stable aliases at `REPO_ROOT`
  (`aria-knowledge-antigravity.zip`, `-codex.zip`, `-cursor.zip`,
  `plugin-claude-cowork/aria-cowork.plugin`); all four are **untracked and gitignored**
  (`.gitignore:9` → `aria-knowledge-*.zip`, confirmed with
  `git ls-files --error-unmatch`), so a fresh worktree does not contain them and the
  publish would attach an incomplete set. The site's five `/latest/download/` links resolve
  through those aliases — the v2.45.1 record shows what a missed alias set costs
  (`/latest/` served a stale version for 12 days). **The isolation that makes the BUILD
  safe is exactly what makes the PUBLISH fail** — hence the split.
  Success signal is the six attached assets plus a downloaded, content-verified zip; **not**
  the exit code of `gh release create`.

## Ports

Claude-Code-canonical. This hook exists in **exactly one** runtime — confirmed by grepping
the guard pattern across all five `plugin-*/` trees, which returned 1. Nothing to
propagate; no PORT-LEDGER change.
