# The demote gate's `sessionId` conjunct — design

**Status:** **GATED** — gate 1 (`/prospect file`) run 2026-09-11: **PROCEED-WITH-CHANGES**, all six
changes **G1-C1 … G1-C6 folded in place**. Log: `knowledge/logs/prospect/2026-09-11-file-demote-gate-sessionid-conjunct.md`.
Next: the plan, then gate 2 (`/prospect file <plan>`). No code until gate 2 has run.
**Origin:** a live near-miss during a `/wrapup` on proj-a, 2026-09-11. The operator read Step 6.5's
gate, found it false, demoted anyway on the *body* test, and reported the discrepancy. Had the gate
been followed literally, the full rewrite would have destroyed a 61-line unconsumed pickup carrying an
undone `nextAction`. **Validated by measurement, not by reading** — see §1.4 and §1.5.
**Target:** v2.52.5 (current released: v2.52.4).

⛔ **Public-repo hygiene:** this file ships. Project directories are `proj-a` / `proj-b` placeholders
per the repo's Gate D convention. Do not substitute real names.

## Gate-1 changes folded (2026-09-11)

Where each change landed, so a reader can find it without the log:

| # | Change | Landed in |
|---|---|---|
| **G1-C1** | `AC4` was unachievable — a behavioural test of the *gate decision* is structurally impossible (model-executed; the suite's own dogfood ceiling). Split into `AC4a` runtime precondition + `AC4b` documentation, with the ceiling recorded as **not owed**. | §6 |
| **G1-C2** | The runtime-drift note is **FALSE at HEAD**. antigravity wrapup *has* the demote and *has* this bug; only codex wrapup lacks the step. `AC7` becomes "correct a false claim", and OQ1's scope splits into two remediations. | §6 `AC7`, §7 OQ1 |
| **G1-C3** | The replacement assertion's **positive arm** must not be satisfiable by §2.2's own explanatory prose (`own-comment-enters-the-text-its-guard-reads`; this file already warns about it for C1/H1). | §2.3 |
| **G1-C4** | Name the **transfer**: the peer gate's HIGH-confidence finding is about the ledger's idempotency *key*, not this gate. Same proposition, different consumer. | §1.5 |
| **G1-C5** | §2.2's stated reason was **falsified** — `by:` *is* a preserved front-matter field. Replaced with the stronger measured result (both identity fields fail, for different reasons) plus an explicit falsifier. | §2.2 |
| **G1-C6** | §3's *"invented twice independently"* → instrument named; one machine, and one instance *is* this incident. Convention claim sound, independence claim not. | §3 |

⚑ **G1-C5 is the one to read if you read only one.** The conclusion never moved; only its justification
was wrong — which is exactly the case where a correction is easiest to skip and most expensive to skip,
because a false reason under a correct rule survives every later review of the rule.

## 0. Summary

`D1` of `2026-08-27-session-ledger-integrity.md` fixed **one of the demote gate's two conjuncts**. The
gate is a conjunction across two axes — `lastEvent` and `sessionId` — and v2.48.2 widened the first
while leaving the second untouched. The clause now states **two disagreeing tests in adjacent
sentences**, and a passing control asserts the wrong one. The `lastEvent` half of D1 is closed; this is
the same defect on the other axis, still live, still destroying data.

## 1. The defect

### 1.1 The gate as it stands

`plugin-claude-code/skills/wrapup/SKILL.md`, Step 6.5, item 1 — the trigger is a conjunction:

> unconsumed entry **AND** carrying a non-empty prompt block **AND** *whatever its `lastEvent`*
> **AND** *(different or absent `sessionId`)*

`plugin-claude-code/skills/handoff/SKILL.md`, the `**Multi-session ledger` clause, states the same
conjunction and makes its premise explicit:

> …and its `sessionId` differs from this session's (or is absent — **treat an unidentifiable handoff
> as *someone else's***), DEMOTE it before overwriting the active slot.

That parenthetical is the false premise in one line: it reads `sessionId` as *the handoff's owner*.

### 1.2 The two tests disagree, two sentences apart

The sentence immediately after the trigger, in **both** files, is an *only-if* that reverses it:

> **Skip the demote only for a FRESH `in-progress` marker whose body is just `(session in progress)`**
> — that is the one state in which the stored entry would be empty. ⛔ **A `lastEvent: in-progress`
> marker that carries a real prompt MUST be demoted.**

And the sentence after *that* names the mechanism which guarantees the conjunct is wrong:

> `kt_ss_mark_inprogress` rewrites only the front-matter keys and passes the body through with a bare
> `{ print }` … and `post-edit-check.sh` creates that state **automatically** whenever a second
> session edits in a project holding a handoff.

So the clause documents the mechanism, writes the correct body predicate, and leaves the conjunct that
the mechanism falsifies. A reader picks by scroll position. The operator picked correctly; the literal
gate did not.

⚠ **The `lastEvent` and `sessionId` conjuncts fail the SAME WAY for the SAME REASON** — both read a
front-matter key as a statement about the body. That is why fixing one and not the other reads as a
completed fix.

### 1.3 Why it survived v2.48.2 — provenance

`git log -S 'different or absent'` on the wrapup skill returns **one** commit: `6183609` (2026-08-26),
the original demote fix. It has not been touched since. `c057c79` (2026-08-27, v2.48.2, *"fix the
demote gate, the matchers, and the block boundary"*) changed only the entry-type clause:

- before: ``an unconsumed `handoff` entry (different or absent `sessionId`)``
- after: ``an unconsumed entry carrying a **non-empty prompt block** — whatever its `lastEvent` — (different or absent `sessionId`)``

Two axes in one gate; the fix moved one and carried the other forward verbatim.

### 1.4 Why nothing caught it: **a control asserts the defect**

`tests/repros/wrapup-demotes-before-rewrite.sh`, assertion **B**:

```sh
printf '%s' "$WSEC" | grep -qiE 'different or absent .?sessionId|different .?sessionId' \
  && ok  "B  demote is conditioned on a different/absent sessionId" \
  || bad "B  sessionId guard" "unconditional demote would demote the session's OWN entry"
```

**Deleting the conjunct reddens B, and B's failure message argues to restore it.** Measured
2026-09-11: the suite is **16 passed, 0 failed, bare exit 0** — B (conjunct present) and C2 (body
predicate present) pass *simultaneously on one clause* while disagreeing about the reported case. B
sits ~25 lines above the C-block, whose own comments spend fifteen lines explaining the mechanism that
falsifies B's premise.

⚠ This is the **third** unfalsifiable assertion in this one file, and its own comments record the
other two (`A1b` matched the section heading; the retired `C` matched a word shared by the false rule
and its correction). B is the first that failed *outward* — it did not merely fail to catch the
defect, it mandated it.

**Class:** `guard-scoped-to-the-wrong-unit`, one level up from code. The gate is a **conjunction**;
the control tests each conjunct's *presence* independently. Presence-of-both can be green while their
**joining** is wrong, and no per-clause assertion can see a contradiction that lives in the AND.

### 1.5 The library already rules the premise false

`plugin-claude-code/bin/lib-session-state.sh:197-203`, on the ledger's idempotency key:

> ⛔⛔ THE KEY IS THE BLOCK, NEVER `(sessionId, at)`. That pair is **NOT a handoff's identity** … a
> second pair's sid is recorded in the file itself as *"a HOOK ARTIFACT, not attribution —
> post-edit-check.sh stamped session 1cabb22b onto this entry's front-matter"*. **So the key can hold
> a value a HOOK wrote rather than the author.**

The layer that does the work already ruled, with a measured instance, that a front-matter `sessionId`
is not attribution. The skill's gate treats it as attribution. **The two layers disagree in writing,
and the library is the one that is right** — so §2 is not a fresh judgment call, it is propagating a
ruling that already exists (U5's rule-doc ↔ enforcer drift, with the enforcer correct).

⭐ **Independently corroborated by a gate, not only by a code comment.** The 2026-09-08 gate on the
merged session-ledger Unit B spec carried the hypothesis *"RC-3 must be keyed on the block, not on
`(sessionId, at)`"* at **Confidence: HIGH**, with **Evidence AGAINST: none found**, and its one
counter-reading (*"they diverged later by hand annotation"*) tested against git and **refuted**.

⚠ **Name the transfer rather than borrowing the verdict.** That gate's subject is the ledger's
**idempotency key**; this one's is the **demote gate**. The *proposition* is identical — a front-matter
`sessionId` is not a handoff's identity — and the *consumer* is not. Two independent sources for the
proposition (the library comment + that gate) is what puts §2's assumption at ✅ Pre-validated;
**neither source examined this gate**, which is why this spec exists rather than citing them and stopping.

Confirmed mechanism, not inferred: `post-edit-check.sh:107` calls
`kt_ss_mark_inprogress "$SS_ROOT" "$SS_SID" "$SS_AUTHOR"`, and `lib-session-state.sh:112` is the bare
`{ print }` that carries the body across.

## 2. D-A — drop the `sessionId` conjunct; gate on the body alone

**The question the gate exists to answer** is *"would the full rewrite destroy work that is not mine
to destroy?"* The `sessionId` test tries to answer it via ownership. Ownership of the **front matter**
is not ownership of the **body**, and the hook makes them diverge as routine.

### 2.1 Every reachable state

| # | State | front-matter sid | body | Today | Body-only gate |
|---|---|---|---|---|---|
| 1 | Fresh in-progress, no prior pickup | mine | `(session in progress)` | skip | skip — unchanged |
| 2 | Prior session's handoff, untouched | theirs | real prompt | demote | demote — unchanged |
| 3 | Prior session's handoff, my edit fired the hook | **mine** | **their real prompt** | **skip ⇒ DESTROYS** | **demote** |
| 4 | I ran `/handoff`, then `/wrapup`, same session | mine | **my** real prompt | skip ⇒ destroys my own | demote |
| 5 | No SESSION.md | — | — | create | create — unchanged |
| 6 | in-progress marker, sid absent | absent | real prompt | demote | demote — unchanged |

Only **3** and **4** change. 3 is the reported defect. 4 is the judgment.

### 2.2 Case 4 is settled: demote

Two readings existed — *preserve* (the prompt was written deliberately; a later close should not erase
it) versus *erase* (`/wrapup` is an authoritative close, so running it after a handoff signals the work
is done). **Preserve wins, and not on the reversibility tie-breaker:**

⛔ **Cases 3 and 4 do not differ on any identity field the gate can read.** Both present as *my sid
over a real prompt*. **So no `sessionId` test can demote case 3 without erasing case 4** — any gate
that erases 4 also erases 3. That forecloses the *erase* reading rather than merely losing to it.

⚠ **A first draft of this section gave the wrong reason, and it is corrected at source rather than
quietly** — the decision survived, so leaving it would hand the next reader a false justification for
a correct rule. It read: *"the distinguishing fact … is not observable from the file."* **That is
false. The front matter carries `by:`** — it is in the canonical contract
(`tests/fixtures/session-contract-vendored/in-progress.SESSION.md:8`) and `kt_ss_mark_inprogress`
**preserves** it: the `awk` rewrites only `lastEvent` / `at` / `branch` / `headCommit` / `sessionId`
and passes `by:` through the bare `{ print }`. So a hook-stamped file carries a **stamped `sessionId`
beside an original `by:`**.

⭐ **The measured result is stronger than the claim it replaces: BOTH front-matter identity fields
fail to discriminate, for different reasons.** `sessionId` fails because the hook **overwrites** it.
`by:` fails because it is **person-granular** — measured, **20 of 20** live SESSION.md files carry one
author — while case 3's generator is *the same person in a second session*. So `by:` is not a
candidate replacement gate either, and that is a measurement rather than an inference.

⚠ **Explicit falsifier.** In a **multi-author** project where `by:` differs between the two sessions,
cases 3 and 4 *are* distinguishable on `by:`. The gate should still not test it — `by:` cannot separate
two sessions of one author, which is the generator here — but the foreclosure above is then no longer
absolute. **The clause must therefore state the condition, not the absolute.**

Supporting, in order of weight: the asymmetry is real (an unwanted pending entry is one manual
deletion; an erased prompt is git archaeology); and Step 6.5 already declares the safe direction —
*"If you are unsure whether another session owns the file, demote, prune, and write: that is the safe
direction, not the risky one."* The conjunct contradicts the clause's own stated posture.

⚠ **Case 4's consequence must be stated in the clause as chosen behaviour, not left as a side
effect** — otherwise the next reader finds their own handoff demoted and repairs the "bug".

⚠ Step 6.5's *"adds NO pending entry for the wrapped session itself (there is no next-session prompt
to retain)"* is a **statement about adding a NEW entry**, and its parenthetical is false in case 4.
The parenthetical needs qualifying; the rule does not change.

### 2.3 The control is re-pointed, not deleted

Assertion B's concern — *"unconditional demote would demote the session's OWN entry"* — is now the
**intent**. B must assert the **body** predicate and, in the `absent` form used by C1/H1, that the
`sessionId` conjunct is **gone**. Absence of an exact string is the one form that cannot be satisfied
by accident; C1 and H1 are built on exactly that reasoning, in the same file.

⛔ **Deleting B outright is wrong** — it would leave the demote gate with no assertion on its trigger
at all, which is how a one-sided set stops detecting a regression from the other end (the reason this
suite is two-sided by design).

⛔⛔ **The replacement's POSITIVE arm must not be satisfiable by the corrected clause's own prose.**
§2.2's replacement text necessarily *mentions* `sessionId` in order to explain why the gate does not
test it — so a positive arm keyed on that word is satisfied by the explanation rather than by the gate.
Key the positive arm on a string that cannot occur in explanatory prose, and carry the retired
conjunct as **exact-string absence**. Pattern `own-comment-enters-the-text-its-guard-reads`; this file
**already carries that warning for C1/H1** (*"DO NOT quote that retired sentence … not even to explain
that it was wrong"*), so violating it here would be the third instance in one file.

## 3. D-B — the demoted entry's attribution is forged

`kt_ss_ledger_add` takes the prior `sessionId` as an argument, and both clauses instruct reading it
from the prior file's front matter. **In case 3 that value is the demoting session's own id**, so a
correctly-demoted entry is misattributed to whoever demoted it. Rule 38: same lines, known-reachable,
close it here.

⭐ **The convention already exists — written twice, by hand, weeks apart.** Measured on proj-a: two
live pending entries carry a warning in the **`focus`** field, each written because the sid was forged.

⚠ **Instrument named, because the independence claim does not hold:** one machine, one corpus, and
**one of the two IS the 2026-09-11 near-miss that produced this spec**. So the *convention* claim is
sound — a human reached for this shape unprompted, twice — and an *independent-discovery* claim is not.
Shape:

> `- focus: ⚠ sid is a post-edit-check.sh HOOK ARTIFACT, not attribution — <what this pickup really is>`

⇒ **The clause instructs that annotation** when the demoting session's own id equals the front-matter
id while the prompt block is not one it wrote. Cost: one sentence, **zero** helper changes.

⛔ **It goes in `focus`, never in the sid.** The sid is what `kt_ss_ledger_mark_consumed` (`^### .*<sid>`)
and `is_entry_header` key on, and the cross-repo checker's `ENTRY_RE` captures everything before the
first `·` as the id — so sid-field prose pollutes three matchers at once. `focus` is free text, so
this is **not** a ledger format change and needs no consumer census.

⚠ Measured for completeness: a parenthetical *after* the sid is tolerated and occurs live, but in only
**2 of 144** real headers (control: 144 `### <sid>` headers). Tolerated is not a reason to use it.

## 4. Scope — five clause sites, one control

| Site | occurrences | in this spec? |
|---|---|---|
| `plugin-claude-code/skills/wrapup/SKILL.md` Step 6.5 | 1 | yes |
| `plugin-claude-code/skills/handoff/SKILL.md` — 3f summary line | 1 | yes |
| `plugin-claude-code/skills/handoff/SKILL.md` — `Multi-session ledger` clause | 1 | yes |
| `tests/repros/wrapup-demotes-before-rewrite.sh` assertion **B** | 1 | yes |
| `plugin-antigravity/skills/{wrapup,handoff}/SKILL.md` | 1 each | **OQ1** |
| `plugin-openai-codex/skills/handoff/SKILL.md` | 1 | **OQ1** |

⛔ **The handoff clause carries the conjunct TWICE** — the 3f summary line and the ledger clause are
two separate slices, guarded by two separate `awk` ranges (`HSEC`, `HCLAUSE`). Editing 3f alone is a
partial fix; the prior round measured exactly this (*"3 of the 4 D1 sites had no assertion at all"*).

`plugin-claude-cowork` carries **no** demote step (`kt_ss_ledger_add` = 0 occurrences), and neither
does codex `wrapup` — that is the drift Step 6.5's own note already tracks, not a missing site.

## 5. Explicitly NOT in this spec

- **`kt_ss_ledger_prune`'s boundary handling** — fixed at `d1175a6`, verified installed, out of scope.
- **Recovering the true author** of a hook-stamped entry. Unrecoverable from the file; D-B annotates
  the uncertainty rather than pretending to resolve it.
- **Any helper change.** D-A and D-B are both clause + control. `lib-session-state.sh` is already
  correct on this axis (§1.5) and must not be edited to match a skill that was wrong.
- **The `## Pending handoffs` heading-scope / terminator class.** Separate, tracked elsewhere.

## 6. Acceptance criteria

- **AC1** The `sessionId` conjunct is absent from all three claude-code clause sites, asserted by
  exact-string absence.
- **AC2** Both clauses state the body-only gate **and** case 4's consequence as chosen behaviour.
- **AC3** Assertion B asserts the body predicate positively **and** the conjunct's absence; the suite
  is two-sided across wrapup and handoff as before.
- **AC4a** *(runtime, testable)* A repro proves **case 3's state is constructible and routine**: seed a
  SESSION.md whose body holds a real prompt, call `kt_ss_mark_inprogress <root> <new-sid>`, and assert
  the result carries the **new** `sessionId` **and** still holds the prompt text. The harness already
  supports this — `tests/repros/session-state.sh` seeds arbitrary front matter and calls the helper
  directly. This is the load-bearing half: it establishes that the state the gate must handle is
  produced by ordinary operation, not by an edge case.
- **AC4b** *(documentation)* Both clauses instruct demote for that state, and skip only the fresh
  `(session in progress)` body.
- ⛔ **NOT owed — a behavioural test of the gate DECISION, and this is a stated ceiling rather than a
  gap.** The demote decision is executed by a **model reading SKILL.md**, not by code, so no repro can
  assert it. The suite's own header already names this: *"(Dogfood ceiling — asserts the SKILL.md
  DOCUMENTS the contract, not runtime behaviour.)"* Do not write an AC that requires it, and do not
  record its absence as an open item.
- **AC5** Mutation-verified — re-inserting the conjunct into either clause reddens **the named
  assertion**, and the pre-existing assertions stay green. Every mutation names its control first, and
  is confirmed to have *created* the condition.
- **AC6** D-B's annotation is instructed at both claude-code sites, in `focus`, never in the sid.
- **AC7** Step 6.5's runtime-drift note is **corrected**, not merely re-pointed — **it is FALSE at
  HEAD.** It claims *"`plugin-antigravity` and `plugin-openai-codex` carry this same step **without**
  the step-1 demote."* Measured 2026-09-11 (control: claude-code wrapup `kt_ss_ledger_add` = 1):

  | runtime / skill | `kt_ss_ledger_add` | carries the conjunct |
  |---|---|---|
  | antigravity wrapup | 1 — **has the demote** | **yes — has THIS bug** |
  | antigravity handoff | 2 — has it | **yes** |
  | codex handoff | 2 — has it | **yes** |
  | codex wrapup | **0 — lacks the step** | n/a |

  ⭐ So the port situation is **three sites carrying this bug** plus **one site missing the step** — two
  different remediations, not one gap. The replacement note states per-runtime state **with its
  measurement date**, because a per-runtime claim goes stale on the next parity pass; pattern
  `a-stale-measured-label-suppresses-the-recheck` is exactly what happened to the current one.
- **AC8** Full suite: **38 suites, 0 failed, bare exit 0**; assertion count ≥ 498 baseline, and any
  delta reconciles to assertions this unit added or retired.

## 7. Open questions

- **OQ1 — runtime parity.** Close antigravity + codex in this round, or at the next parity pass as
  v2.48.2 chose? Step 6.5 declares claude-code canonical. The conjunct is a **data-loss** path, which
  argues for closing all four now; against it, those ports have their own drift backlog and a partial
  parity pass is worse than a tracked gap (U16). **Recommendation: fix claude-code + re-point AC7's
  drift note to name the conjunct explicitly, and close the ports in one deliberate parity unit.**
- **OQ2 — release.** Does this ride the next release, or does a live data-loss path in an
  always-loaded skill warrant its own v2.52.5? **Recommendation: its own patch release** — the clause
  is loaded into every session, and the near-miss is one operator's careful reading away from loss.
