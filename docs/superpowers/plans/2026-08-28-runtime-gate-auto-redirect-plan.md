# Plan — runtime gates self-correct; bare forms belong to Code

**Status:** GATED — `/prospect` run 2026-08-28, verdict PROCEED-WITH-CHANGES; all three required
changes applied below. Gate log:
`knowledge/logs/prospect/2026-08-28-file-runtime-gate-auto-redirect.md`
**Spec:** `docs/superpowers/specs/2026-08-28-runtime-gate-auto-redirect-design.md` (read it first)
**Target version:** 2.51.0 · **Baseline:** `origin/main` = `f813278` (v2.50.0, released + live)

## Cold-start orientation

A dual-port skill exists twice: `plugin-claude-code/skills/<x>/` and
`plugin-claude-cowork/skills/<x>/`. Each carries a `## Runtime Gate (per ADR-094)` section that
detects "wrong runtime" and **asks `y/n`**. This arc makes it **redirect automatically**, both
directions, and fixes the one cowork skill that advertises a bare slash form.

⛔ **Re-measure every count below before acting — the tree moves.** The `--- re-derive ---`
commands are the instruments, not the numbers.

## Tasks

- **T0 — baseline.** Record: plugin suite total (`plugin-claude-code/tests/run.sh`), hook-repro
  total (`tests/run.sh`), Gate B bytes, and re-derive the file sets:
  ```
  # in-scope gates, per side (a gate is in scope iff the counterpart skill EXISTS)
  CW=$(ls plugin-claude-cowork/skills/); for f in plugin-claude-code/skills/*/SKILL.md; do
    grep -q "Runtime Gate" "$f" || continue; n=$(basename $(dirname $f))
    echo "$CW" | grep -qx "$n" && echo "CODE-INSCOPE $n" || echo "CODE-EXCLUDED $n"; done
  ```
  Expected at baseline: 22 in scope / 7 excluded per side (cowork: 22 / 0).
  ⚠ A count that disagrees means a skill was added or ported since — reconcile before sweeping.

- **T1 — author the transform, prove it on ONE file first.** The gate body varies per skill (each
  carries its own mismatch rationale). Only the *scaffolding* is uniform. The transform must
  **preserve each skill's rationale sentence** and replace only: the `⚠️ Runtime mismatch` ask
  block's closing question, the `Wait for an explicit reply` list, and the auto-mode paragraph
  (D7). Run it on `plugin-claude-cowork/skills/wrapup/SKILL.md`, read the whole resulting section
  by eye, and only then sweep. ⛔ Do not sweep first and inspect after.

- **T2 — cowork sweep (22).** 19 uniform + **3 by hand**: `foundational-review`, `interview`,
  `readiness-audit` (no `Wait for an explicit reply` block — different scaffolding).

- **T3 — Code sweep (22).** 21 uniform + **1 by hand**: `interview`.
  ⛔ **Do NOT touch the 7 excluded gates** — `audit`, `audit-rules`, `audit-style`, `audit-usage`,
  `auto`, `recap`, `roadmap`. They have no counterpart; see spec D4.

- **T4 — D1, one file.** `plugin-claude-cowork/skills/interview/SKILL.md`: remove `'/interview'`
  from the description's trigger list, replace with `'/aria-cowork:interview'`, and append the
  `(Cowork variant — namespaced-only.)` marker its 21 siblings carry.
  ⛔ Leave `aria-setup` and `daily-audit` alone — their names are deliberately distinct from
  Code's, so there is no bare collision and the missing marker is correct.

- **Task 4a: Sibling-surface sync.** ⛔ **Added by the gate, which falsified the plan's original
  file list — it enumerated `skills/` only.** Two repo-level instruction surfaces describe the y/n
  gate and would, after this arc, document a branch that no longer exists. `CLAUDE.md` is
  always-loaded for this repo, so a stale claim there fires every session.
  - `CLAUDE.md` — locate and rewrite the runtime-gate description.
  - `AGENTS.md` — same.
  - **Verification step:** `grep -rn "Runtime mismatch\|Use \`/aria-cowork" CLAUDE.md AGENTS.md`
    returns only text consistent with auto-redirect.
  ⚠ **Ports are OUT of scope, by ruling not by silence.** `plugin-antigravity/skills/{auto,audit}`
  and `plugin-openai-codex/skills/audit` carry gate copies. Ports lag canonical deliberately —
  judgment ledger `2026-08-17-port-drift-live-lag-judgments.md` **J2**, accepted by Mike, records
  Gate C as advisory on exactly these grounds. Do not re-litigate; do not sweep them.

- **T5 — tests (new file; there are currently ZERO).** `plugin-claude-code/tests/test-runtime-gates.sh`:
  - every in-scope gate names its counterpart invocation and contains **no** `y` / `n` wait;
  - **the D4 guard:** each of the 7 excluded gates contains **no** auto-redirect — this is what
    stops D4 decaying the next time someone sweeps;
  - `interview`'s cowork description advertises **no** bare form, with a **positive control**
    proving the check can see one (plant a bare form in a temp copy; it must red).
  - ⛔ Every assertion must be **seen red** before it is trusted. Reference for how a gate can be
    green and worthless: v2.50.0's `[AR11]`, which grepped a phrase an unrelated sentence
    satisfied and survived deletion of the whole section it guarded.

- **T6 — gates.** Both suites bare exit 0; Gate B under budget; `./release.sh` builds.

- **T7 — version + CHANGELOG.** 2.51.0. State that the `n`-branch (force the mismatched variant)
  is gone and why (spec D3), since that is a removed capability.

- **T8 — release + site.** Standard ceremony (`RELEASING.md`): build all 5 artifacts →
  `gh release create` with the **full 40-char SHA** as `--target` (an abbreviation is rejected) →
  `./publish-release.sh --apply` → verify the **published** zip byte-identical + content-check.
  ⛔ **The site DOES mention `aria-cowork` — measured, not assumed: `closing.jsx` and `hero.jsx`.**
  The plan originally guessed it did not. Census both files for any y/n-gate description and update
  what is stale; sync the version badge in `brand.jsx` regardless. Site deploy is
  `promote.sh` → `deploy.sh --apply`, then read the change back off the live host.

## Acceptance

- AC1 — every in-scope gate (both sides) redirects without asking, and names its counterpart.
- AC2 — each redirect announces itself in one line (spec D6); no silent swap.
- AC3 — the 7 excluded gates are byte-unchanged, asserted by test, not by inspection.
- AC4 — `cowork/interview` advertises no bare form; positive control fires.
- AC5 — both suites bare exit 0; every new assertion seen red first.
- AC6 — published zip content-verified; live badge read back from `ariaknowledge.com`.
- AC7 — `CLAUDE.md` and `AGENTS.md` carry no surviving description of the y/n branch, verified by
  the Task 4a grep.

## Traps carried in (paid for already — do not re-derive)

1. ⛔ **`--target` on `gh release create` needs the FULL 40-char SHA.** An abbreviation returns
   *"Release.target_commitish is invalid"*.
2. ⛔ **Two independent test trees.** `tests/` (hook repros) and `plugin-claude-code/tests/`
   (skill units) — neither runner invokes the other, so "the suite passed" is ambiguous unless you
   name which. Run both.
3. ⛔ **Never pipe a command whose exit code you will cite** — `$?` becomes the pipe's last stage.
   Redirect to a file, read the bare exit.
4. ⛔ **`release.sh` stages from the WORKING TREE.** Confirm nothing is dirty under `plugin-*/`
   before building, or a parallel session's WIP ships into a public artifact with no error.
5. ⛔ **A `git commit -m` message containing backticks is command-substituted by zsh and silently
   emptied.** Use `git commit -F -` with a quoted heredoc.
6. ⚠ **`.gitignore` is dirty with an unrelated `PM-REVIEW.md` line from another session** — do not
   stage it.
7. ⚠ Verify any push by `ls-remote` + an ancestor check, never the push command's exit code.
