# Spec — SESSION.md ledger integrity (four defects)

**Status:** GATED 2026-08-27 — **PROCEED-WITH-CHANGES**; all four changes (C1 measured port census,
C2 split D3 out, C3 bind D2+D4, C4 reuse the existing inversion control) applied in this revision.
Gate: `knowledge/logs/prospect/2026-08-27-file-session-ledger-integrity.md`.
⛔ **D2 AND D4 SHIP AS ONE CHANGE — gate change C3.** D4's terminator-respecting fix is what makes D2's
looser header match safe; shipping D2 alone widens a live hazard rather than closing one.
⛔ **HOLD BEFORE EXECUTE** — this arc stops at a gated plan by instruction. No code.
**Origin:** two independent reports from a reviewer, both **validated by reproduction** rather than by
reading, plus two further defects found while validating them.
**Target:** v2.48.2 (current released: v2.48.1).

⛔ **Public-repo hygiene:** this file ships. Project directories are referred to as `proj-a` / `proj-b`
placeholders throughout, per the repo's Gate D convention. Do not substitute real names.

## 0. Why one spec and not four tickets

All four live in the SESSION.md ledger and three of them are in the same two functions. They are also
**causally coupled through operator behaviour, not through code**: D1's escape clause forces a human to
demote by hand, and a hand-written entry is precisely the format D2's matchers cannot see. Fixing either
alone leaves the loop turning. D3 and D4 are additional failure modes of the same matchers, found while
reproducing D2, and repairing those matchers without closing them would leave known-reachable bugs in
lines being edited anyway (Rule 38).

## 1. D1 — the demote gate rests on a false premise · **LIVE, destroys data**

`/wrapup` and `/handoff` both demote a prior session's pickup into `## Pending handoffs` before
overwriting the active slot. Both carve out an exception, verbatim in both files:

> **Never demote a `lastEvent: in-progress` marker.** That is a live session's own breadcrumb, not a
> handoff — **it carries no prompt, so a ledger entry for it would be empty.** Overwrite it and move on.

**The premise is false.** `kt_ss_mark_inprogress` rewrites **only** frontmatter keys — its `awk` matches
`lastEvent:` / `at:` / `branch:` / `headCommit:` / `sessionId:` inside the first fence and passes
everything after it through with a bare `{ print }`. So an in-progress marker routinely carries the
previous session's entire `## Next session prompt`, and `post-edit-check.sh` creates that state
automatically whenever a second session edits in a project holding a handoff. The consequence is not
stale state — it is **overwriting a live pickup**.

⛔ **Four edit sites, not one, and this is the load-bearing part.** The escape clause appears twice, but
the *positive* gate keys on `handoff` in three places, so an `in-progress` entry never reaches the demote
path at all. **Editing only the clause is a no-op.**

| # | file | what keys on it |
|---|---|---|
| 1 | `skills/wrapup/SKILL.md` | the gate (`holds an unconsumed handoff entry`) **and** the clause, in one step |
| 2 | `skills/handoff/SKILL.md` | the gate (`has lastEvent: handoff and its sessionId differs`) |
| 3 | `skills/handoff/SKILL.md` | the clause |
| 4 | `skills/handoff/SKILL.md` | step 3f (`If a prior unconsumed handoff entry exists`) |

**The clause was right about one case and over-generalised.** A *fresh* marker written by
`kt_ss_mark_inprogress`'s else-branch has a body of exactly `## Where we left off` + `(session in
progress)` — demoting that really would create an empty entry. So the correct rule is not *"always
demote in-progress"* but **"demote when the prompt block is non-empty"**, which preserves the clause's
original intent while closing the data loss.

## 2. D2 — the matchers only accept the exact format `add` writes · **LIVE, entries never clear**

`kt_ss_ledger_mark_consumed` requires `^### <sid><space>` **and** `· unconsumed` anchored at end-of-line.
`kt_ss_ledger_prune` requires the literal `· consumed `. Any hand-written header is invisible to both;
they return 0 and change nothing, so the fail-safe contract hides the class.

**Reproduced on fixtures, asserting on file bytes, with a control proving the probe can succeed:**

| header form | `mark_consumed` |
|---|---|
| canonical (control) | **marked** |
| backticks round the sid | unchanged |
| trailing ` · title` after the status | unchanged |
| bold `**unconsumed**` | unchanged |
| truncated sid + parenthetical | unchanged |

⚠ **Self-perpetuating:** the failed automatic mark forces a manual one, and the manual one reintroduces
the format that breaks it.

⛔ **THE INVERSION TRAP — the obvious fix is worse than the bug.** A naive `/consumed/` also matches
`unconsumed`, which would make `prune` **delete live handoffs**. The current code is safe from this only
because it requires the literal `· consumed ` with its trailing space.

**Verified fix direction** (the reporter's, tested in both directions before adoption):

```awk
$0 ~ ("^### .*" sid) && /(^|[^a-z])unconsumed([^a-z]|$)/     # mark_consumed
$0 ~ /(^|[^a-z])consumed([^a-z]|$)/                          # prune
```

Measured against four real status strings: `· unconsumed` → mark only; `· consumed TS by BY` and
`· **consumed** TS` → prune only. The word-boundary form is what makes it safe, and a control asserting
a live `unconsumed` entry **survives** prune is mandatory in the suite.

⚠ **One caution on the looser header match.** `^### .*<sid>` matches the sid anywhere in the line. That is
the point — but it also widens what a stored prompt could collide with. It composes with D4 below and the
two must be designed together.

## 3. D3 — a status verb outside `{unconsumed, consumed}` is permanently stuck · **LIVE, 1 entry**

Found while validating D2; **not in either report**. A live file carries:

```
### <sid> · 2026-07-30T17:21:30Z · handoff · ⛔ RETIRED 2026-08-15
```

That status is neither `unconsumed` nor `consumed`, so it can never be marked *and* never be pruned —
it is stuck forever. Verified against the fix direction in §2: the word-boundary regexes match **neither**,
so **D2's fix does not close D3.**

This is a different class from D2: D2 is about tolerating header *decoration*; D3 is about a human using
a status *verb* the system does not know.

⛔ **D3 IS SPLIT OUT OF THIS ARC — gate change C2.** Its acceptance criterion read *"implemented as
ruled"* against a ruling that does not exist, which would have produced a plan step nobody could execute
cold. It **blocks nothing else** — D1, D2 and D4 are independent of it — so gating them on a pending
decision would be the expensive error, and inventing the contract to make the plan look complete would
be the worse one.

**Carried as an open decision with its evidence attached.** Three options, each with a consequence:

| option | consequence |
|---|---|
| **closed set** — reject a write whose status is outside `{unconsumed, consumed}` | prevents the state; does nothing for the entry already stuck |
| **prunable-if-not-unconsumed** | clears the stuck entry, and **widens prune's blast radius**: any status a human invents becomes deletable |
| **deliberately permanent** | costs nothing, and is defensible if `⛔ RETIRED` means *"keep this visible"* — but then say so at the writer, so the next person does not read it as a bug |

⚠ Whichever is chosen, the fix belongs at the **writer** as much as the matcher: nothing today stops a
status verb being written that neither matcher can ever act on.

## 4. D4 — a stored prompt containing a column-0 `### ` line hijacks the block boundary · **LATENT**

Found while validating D2; **not in either report**. `kt_ss_ledger_prune`'s terminator branch resets
`drop` on **any** line matching `^### `, so a consumed block whose stored prompt contains a column-0
`### ` heading loses its boundary and leaks its tail into the file.

**Reproduced:** a consumed block with one `### ` line inside its prompt left **2 lines** of that block in
the file after pruning. The adjacent live entry survived, so this is leakage, not deletion.

⚑ **This is the same failure the function's own comment says it fixed** — *"The previous version reset
`drop` on `/^## /`, so a consumed block containing such a line lost its boundary and leaked its tail into
the file — reproduced, not theorised."* The `## ` case was closed; `### ` was not, and the explicit
`<!-- aria:entry-end -->` terminator exists precisely so boundaries need not be inferred.

⚠ **Status: LATENT, and one demote away from live.** Measured across every `SESSION.md` in the workspace:
**0** stored blocks currently contain a column-0 `### ` line. But at least one live file's *active body*
does contain such headings, and demoting that body is exactly what would store them. Priority is
therefore below D1/D2/D3 — but it sits in the function being edited, so leaving it is a knowing choice.

## 5. Acceptance criteria

- **AC1** An `in-progress` marker whose body carries a non-empty prompt block **is demoted** before the
  active slot is overwritten (D1). Control: the *fresh* marker (`(session in progress)`, no prompt) is
  **not** demoted and yields no empty entry.
- **AC2** All four D1 sites are changed; a test asserts the *positive gate* no longer keys on `handoff`
  alone. ⛔ A test that only checks the clause text passes while the bug is live.
- **AC3** `mark_consumed` fires on all four non-canonical header forms in §2's table, and on the canonical
  one (control).
- **AC4** `prune` removes canonical and bold `consumed`, and **leaves a live `unconsumed` entry intact**.
  ⛔ **Gate change C4 — reuse the control that already exists, do not write a new one.**
  `tests/repros/session-state.sh` already carries **`M4 unconsumed block survives prune`**: that IS the
  guard against the inversion. The obligation is therefore to **see M4 go red** under a naive
  `/consumed/` before adopting the word-boundary form — a control that has only ever been green does
  not yet prove the trap is guarded, and this one has never been fired against the fix it protects.
- **AC5** *(retired — D3 split out per C2; carried as an open decision in §3, not as an acceptance
  criterion. Numbering left intact so cross-references to AC6–AC8 do not shift.)*
- **AC6** A consumed block whose stored prompt contains a column-0 `### ` line is removed **whole**, with
  an adjacent live entry surviving byte-identical (D4).
- **AC7** Every control is mutation-verified — each seen red for its own named reason.
- **AC8** No behaviour change for files already in the canonical format: the existing 49 session-state
  assertions stay green.

## 6. Non-goals

- The reporter's optional third item (having `post-edit-check.sh` demote before flipping the marker). It
  is the root cause of D1's bad *state* rather than of the data loss, and it is a separate mechanism.
- Port propagation **beyond canonical**. ⛔ **The census is DONE — gate change C1.** The earlier text
  deferred it as "needs its own census, not an assumption", which is a finding rather than a deferral,
  and running it changed the arc's shape:

  | port | carries the false clause | library |
  |---|---|---|
  | `plugin-antigravity` | yes | **byte-identical to canonical** (`93d0eeb3…`) |
  | `plugin-openai-codex` | yes | differs — hand-sync |
  | `plugin-cursor-template` | yes | differs; **demote lives in a COMPILED `.mdc`** → needs `port-skills-to-mdc.py`, not an edit |
  | `plugin-claude-cowork` | no | none — skills-only, no session-state |

  So **three** ports carry the clause, and the library half propagates to antigravity for free via
  `build.sh` because the file is identical. What remains out of scope here is the two ports needing
  their own edit or recompile, each with its own verification.

  ⚠ **Correct at source while here:** an always-loaded project doc records that "all four runtimes carry
  this library and the four copies have four DISTINCT md5s". Measured today that is **three** distinct
  md5s across four copies. A stale count in an always-loaded surface is how a future arc mis-sizes this
  same work.
- Any change to `kt_ss_ledger_add`'s written format. Widening what the matchers *accept* is the fix;
  changing what is *written* would strand every existing entry.

## 7. Open questions for `/prospect`

- **OQ1** D3's contract — closed set, prunable-if-not-unconsumed, or deliberately permanent?
- **OQ2** Does the looser `^### .*<sid>` header match (§2) create a collision with stored prompt content,
  and does D4's fix make it safe or merely narrower?
- **OQ3** Do the ports' skills carry the demote step, and does fixing canonical alone leave them worse?
