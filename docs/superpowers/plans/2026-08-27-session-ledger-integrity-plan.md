# Plan — SESSION.md ledger integrity (D1, D2∧D4)

**Status:** GATED 2026-08-27 — **PROCEED-WITH-CHANGES**; both changes (C1 three edits not two,
C2 one-mutation-one-named-control) applied in this revision.
**Gate 2:** `knowledge/logs/prospect/2026-08-27-file-session-ledger-plan-gate2.md`.
⛔ **EXECUTION-READY BUT HELD.** Both gates are green and no code has been written, by instruction.
**Spec:** `docs/superpowers/specs/2026-08-27-session-ledger-integrity.md` (GATED, C1–C4 applied).
**Gate 1:** `knowledge/logs/prospect/2026-08-27-file-session-ledger-integrity.md`.
⛔ **THIS ARC HOLDS AT A GATED PLAN BY INSTRUCTION.** Do not execute without a fresh go.
**Scope:** D1 and D2∧D4. **D3 is split out** and carried as an open decision in the spec §3.

## Baseline to establish FIRST (T0)

⛔ Record before touching anything, or a later failure cannot be attributed.
- `sh tests/run.sh` — **bare exit code**, never through a pipe. Record suite count.
- `sh tests/repros/session-state.sh` alone — record `N passed, M failed`.
  ⛔ **CORRECTED 2026-08-27 — this line said "expect 49 assertions" and 49 is WRONG in both units.**
  Measured at `daf3b61`: **44 passed, 0 failed, bare exit 0**, and the source carries **44** `ok "`
  call sites, so it is not a source-vs-executed mismatch — the figure was simply wrong. A session
  comparing against 49 at T5 would read 5 assertions as **vanished**, which in this workspace is the
  tell for a shared-test-DB collision, and would chase a phantom. **Re-measure rather than trusting
  this number**; T3 adds controls, so T5's expected total is 44 + however many land.
- `git -C . rev-parse --short HEAD`; confirm the tree is clean apart from any parallel-session file,
  which must be left alone.
- **Acceptance:** two recorded numbers to compare against at T5.

## T1 — D1: the demote gate, all FOUR sites

⛔ **Editing only the clause is a proven no-op.** The positive gate keys on `handoff`, so an
`in-progress` entry never reaches the demote path. All four must change together.

| # | file | what to change |
|---|---|---|
| 1a | `skills/wrapup/SKILL.md` | the gate — *"holds an unconsumed `handoff` entry"* → holds an unconsumed entry **carrying a non-empty prompt block**, whatever its `lastEvent` |
| 1b | `skills/wrapup/SKILL.md` | the clause — replace the false rationale |
| 2 | `skills/handoff/SKILL.md` | the gate — *"has `lastEvent: handoff` and its `sessionId` differs"* → same widening |
| 3 | `skills/handoff/SKILL.md` | the clause — replace the false rationale |
| 4 | `skills/handoff/SKILL.md` | step 3f — *"If a prior unconsumed `handoff` entry exists"* → same widening |

**Replacement rationale** (both clause sites, same text): demote any prior entry whose prompt block is
non-empty; skip **only** the fresh marker whose body is just `(session in progress)`, because that is
the sole state that would yield an empty ledger entry. State *why* the old rationale was wrong —
`kt_ss_mark_inprogress` rewrites only frontmatter and preserves the body — so the next reader does not
restore it.

- **Acceptance:** AC1 + AC2. A control asserts the gate no longer keys on `handoff` alone; a second
  asserts the fresh-marker case still skips.

### ⛔ AMENDMENT A1 (2026-08-27, found at T0 — NOT covered by either gate)

**A fifth subject exists and the plan named none of it: `tests/repros/wrapup-demotes-before-rewrite.sh`.**
It slices wrapup Step 6.5 — the exact text site 1a/1b edits — behind a vacuity floor, and carries
**9 assertions** that ran green in the T0 baseline. Two of them bear on D1:

| assertion | what it actually tests | effect of T1 |
|---|---|---|
| **C** `in-progress marker exception carried across` | `grep -qiE 'in-progress'` over Step 6.5 — the **string only** | ⛔ **cannot fail either way** — see below |
| **D** `unqualified survival claim absent` | absence of one exact old sentence | unaffected (already absent) |

⛔ **Assertion C is a control that cannot distinguish the bug from the fix, and BOTH of its outcomes
mislead.** The current false clause contains `in-progress`; any corrected clause will too, so C passes
having verified nothing. And if the corrected wording shifts to the parenthetical `(session in
progress)` form, C **fails** — while its failure message asserts the false premise verbatim
(*"a live session's breadcrumb carrying no prompt — demoting it stores an empty entry"*), i.e. the
suite would argue for restoring the defect.

⭐ **The structural point: C and AC2 are the same assertion at two different scopes.** AC2 wants
*"the positive gate no longer keys on `handoff` alone"*; C wants *"the exception survives the port"*.
Discharging AC2 by adding a control **elsewhere** would leave two guards on one clause, one of which
cannot fail — the dead-by-construction shape. **So AC2 is discharged by REWRITING C in place.**

**Disposition — REWRITE, not delete** (a check proven unable to fail is one or the other, and which
must be named): the invariant C guards is real — a *fresh* marker with an empty prompt must still be
skipped — it is the **unit** that is wrong. C must assert the **condition** (the clause names a
non-empty-prompt test and no longer gates on `handoff` alone), not the presence of a hyphenated word.
Its failure message must be rewritten in the same edit; leaving it is how the false premise survives
its own removal.

⚠ **This is a gate delta.** Neither gate examined this file, so T1's site count is unchanged (still
four edit sites) but its **test** surface grows by one file, and T3/T5 below gain the rows marked A1.
⚠ **Floor check, already verified:** both `awk` slices (`/^## Step 6.5/,/^## Step 7/` and
`/^5\. \*\*3f:/,/^$/`) are guarded by explicit length floors, so if a T1 edit changes a heading the
suite fails loudly at the floor rather than passing over empty text. Do not remove those floors.

## T2 — D2 ∧ D4: the matchers, as ONE change

⛔ Bound together by gate change C3: D4's fix is what makes D2's looser header safe.

**D2 — `bin/lib-session-state.sh`. ⛔ THREE edits, not two — gate change C1.**

| # | edit | why it is not optional |
|---|---|---|
| a | `mark_consumed` match → `$0 ~ ("^### .*" sid) && /(^\|[^a-z])unconsumed([^a-z]\|$)/` | tolerates decorated headers |
| b | `mark_consumed` **write** → `sub(/unconsumed/, "consumed " ts " by " by)` | replaces the WORD, not the anchored phrase |
| c | `prune` header test → `/(^\|[^a-z])consumed([^a-z]\|$)/` | word boundary; **this is what keeps `unconsumed` safe** |

⛔ **Edit (b) is the one the reviewer's brief does not name, and without it the fix is a half-fix that
reads as a whole one.** Measured with (a) and (c) applied but not (b):

```
canonical  -> · consumed TS by BY      (rewritten)
backticks  -> · consumed TS by BY      (rewritten)
bold       -> · **unconsumed**         MATCHED, NOT REWRITTEN
trailing   -> · unconsumed · my title  MATCHED, NOT REWRITTEN
```

The entry now *matches*, so instrumentation and review both read "handled", and the file is unchanged —
**the same silent no-op, relocated one layer in.** With all three edits, all four forms mark and then
prune to zero, and the live `unconsumed` entry survives. **Assert the WRITE lands, never only that the
pattern fires.**

**D4 — same function:** inside the terminator branch, do **not** reset `drop` on `^### ` while a block
is open. The `<!-- aria:entry-end -->` terminator is the declared boundary; the header test is only for
*starting* a block. Leave the legacy branch alone — it has no terminator and its single-line-prompt
invariant makes the old inference sound.

- **Acceptance:** AC3, AC4, AC6.

## T3 — Controls, RED FIRST

⛔ **Red-first against the CURRENT code, which exists** — unlike a new-file arc, every subject here is
already present, so each control reds for its own reason with no stub needed.

| control | asserts | expected RED before |
|---|---|---|
| D1-a | in-progress + non-empty prompt IS demoted | yes |
| D1-b | fresh `(session in progress)` marker is NOT demoted | **no — green both sides** (non-regression only; label it) |
| D2-a…d | mark_consumed fires on backticks / trailing title / bold / truncated-sid+parenthetical | yes ×4 |
| D2-e | mark_consumed still fires on the canonical form | **no — control** |
| D2-f | the rewrite actually lands on a bold header (not just the match) | yes |
| D4-a | consumed block with a column-0 `### ` in its prompt is removed WHOLE | yes |
| D4-b | the adjacent live entry survives byte-identical | **no — control** |
| **A1-C** *(rewrite of the existing `C`)* | Step 6.5's clause names a **non-empty-prompt** condition and does not gate on `handoff` alone | **yes** — reds against the current false clause; **this discharges AC2, do not add a separate AC2 control** |
| **A1-floor** | the two `awk` slices stay above their length floors | **no — pre-existing vacuity guard** |

⛔ **AC4 is discharged by an EXISTING control, not a new one.** `session-state.sh` already carries
`M4 unconsumed block survives prune`. The obligation is to **fire it red** by temporarily using the
naive `/consumed/` form, observe it, then adopt the word-boundary form. It has never been seen red
against the fix it guards.

## T4 — Port propagation (canonical + the free half only)

- Run `plugin-antigravity/build.sh`. Its library is **byte-identical** to canonical, so the D2∧D4 half
  propagates for free; confirm by `md5` afterwards rather than assuming.
- ⛔ **codex and cursor are OUT OF SCOPE here** (spec §6): codex is a hand-sync, cursor's demote is
  compiled into an `.mdc` and needs `port-skills-to-mdc.py`. Note them as named residuals — do not
  half-do them.
- **Acceptance:** antigravity's library md5 matches canonical after the build; no other port changed.

## T5 — Mutation-verify (AC7)

Against a **copy** in the scratchpad — the live hooks are called by other sessions.

| mutation | must redden |
|---|---|
| revert the gate widening at 1a only | D1-a (proves all four sites are needed) |
| revert the clause only, keep the gates | **nothing** — records the no-op explicitly |
| naive `/consumed/` in prune | **M4** (the pre-existing inversion control) |
| drop the word boundary from mark_consumed's match | **D2-c** (bold), and *only* D2-c |
| reset `drop` on `^### ` again | **D4-a** |
| restore the anchored `sub(/· unconsumed$/…)` | **D2-f** (the write-lands control) |
| **A1** restore the old false clause verbatim in wrapup Step 6.5 | **A1-C** (the rewritten in-progress control), and *only* A1-C. ⛔ Prove the condition was created by grepping the restored sentence — the ORIGINAL `C` passes under this mutation, which is precisely why it was rewritten |

⛔ **One mutation, one NAMED control — gate change C2.** The earlier table read *"D2-e **or** M4"*, which
lets either outcome be read as success. Each row above names exactly one control, and each must be shown
to (a) fire, and (b) fire **because the mutation created the condition** — not merely because something
went red.

Each restore verified byte-identical with `cmp`. Re-run `tests/run.sh`; compare to T0.

## T6 — Version + CHANGELOG

`2.48.1` → `2.48.2`; CHANGELOG entry naming both defects, the split-out D3 decision, and the two
port residuals. Grep for stray version strings.

## Risks carried into execution

- **R1** T2 is two fixes in one function. If a control fails, isolate which — the mutation table is
  built so each maps to one.
- **R2** `SESSION.md` files are written by parallel sessions constantly. Never use a live file as a
  fixture; the reproduction corpus is fixtures only.
- **R3** The looser header match is deliberately wide. D4 bounds it; if D4 is dropped, **stop** — do
  not ship D2 alone.

## Explicitly NOT in this plan
- D3 (unknown status verbs) — split out, needs a ruling.
- The reviewer's optional `post-edit-check.sh` root fix.
- codex / cursor port edits.
- Any change to what `kt_ss_ledger_add` **writes**.
