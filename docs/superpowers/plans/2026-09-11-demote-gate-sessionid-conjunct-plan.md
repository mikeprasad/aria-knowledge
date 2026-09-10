# Plan — close the demote gate's `sessionId` conjunct

**Status:** **GATED ×2** — gate 2 run 2026-09-11: **PROCEED-WITH-CHANGES**, all six changes
**G2-C1 … G2-C6 folded in place**. Log: `knowledge/logs/prospect/2026-09-11-file-demote-gate-sessionid-conjunct-plan-gate2.md`.
**EXECUTABLE.**
**Spec:** `docs/superpowers/specs/2026-09-11-demote-gate-sessionid-conjunct-design.md` (GATED, G1-C1…C6 folded)
**Gate 1 log:** `knowledge/logs/prospect/2026-09-11-file-demote-gate-sessionid-conjunct.md`
**Target:** v2.52.5 (current released: v2.52.4) — pending OQ2.

⛔ **Public-repo hygiene:** this file ships. `proj-a` / `proj-b` placeholders only.

⛔ **Working surface:** `main`, directly. The repo's own history lands `feat:`/`fix:` on `main`, there is
one worktree, and the tree was clean at planning time. **Re-check both at T0** — a parallel session can
have arrived, and this repo's `release.sh` stages from the **working tree**, so an unrelated dirty file
inside `plugin-claude-code/` can ship into a public artifact with no error.

---

## T0 — trip-wire (read-only; run first, abort on any mismatch)

⛔ **Every figure below is a planning-time measurement and each one can move.** Re-derive, do not quote.
Abort and re-scope if any differs.

| # | Check | Expected at planning time |
|---|---|---|
| 0a | `git status --porcelain` in the repo | 0 lines |
| 0b | `git worktree list` | 1 entry |
| 0c | `sh tests/run.sh`, bare exit | `0` — **38 suites, 498 `^PASS` assertions, 0 `^FAIL`** |
| 0d | conjunct per site: wrapup Step 6.5 / handoff 3f line / handoff ledger clause | `1 / 1 / 1` |
| 0e | `git log -S 'different or absent' -- plugin-claude-code/skills/wrapup/SKILL.md` | exactly one commit (`6183609`) |
| 0f | assertion `B` still requires the conjunct (`tests/repros/wrapup-demotes-before-rewrite.sh`) | present, line ~70 |
| 0g | runtime table (AC7's subject) — `kt_ss_ledger_add` per port | ag-wrapup 1 · ag-handoff 2 · codex-handoff 2 · **codex-wrapup 0** |
| 0h | latest tag | `v2.52.4` |

⚠ **0c's assertion count is the one most likely to have moved** (any parallel doc/test work changes it).
A moved baseline is not an abort on its own — record the new number and reconcile T6's delta against it.

---

## T1 — AC4a: prove case 3's state is constructible (additive; lands FIRST, alone)

**File:** `tests/repros/session-state.sh` (its idiom: seeds front matter via `cat > … <<'EOF'`, calls
`kt_ss_mark_inprogress` directly).

⛔⛔ **SHRUNK AT GATE 2 (G2-C1) — half of what this task originally proposed ALREADY EXISTS.** Block `D`
of the same suite seeds a real `## Next session prompt`, calls `kt_ss_mark_inprogress`, and asserts
*"D preserved Next session prompt"*. So **body preservation is already guarded** and re-asserting it
would be a duplicate that splits recall.

⭐ **What is guarded NOWHERE is the discriminating half: `D`'s fixture carries NO `sessionId:` line**, so
it proves *insertion-when-absent*. **Overwrite-when-present** — the exact case-3 signature — is asserted
by nothing (block `K` has a `sessionId` but never calls `kt_ss_mark_inprogress`).

⛔ **Do NOT close the gap by adding a `sessionId:` line to `D`'s fixture.** That silently converts `D`
from the absent→inserted case and **drops that coverage** — a coverage regression wearing the costume of
a smaller diff. Add a **sibling block** and leave `D` byte-unchanged.

**Assertion (the one novel claim + one labelled control):** seed a SESSION.md whose front matter carries
`sessionId: sess-prior` **and** whose body holds a `## Next session prompt` with a distinctive sentinel;
call `kt_ss_mark_inprogress "$TMP/x" "sess-mine"`; then assert:

1. **the claim** — `^sessionId: sess-mine$`, i.e. an EXISTING id is **overwritten**; and
2. **the non-vacuity control** — the sentinel survives. Labelled as a control in the code, because `D`
   owns this claim; here it exists only so arm 1 cannot pass against a file the helper mangled.

⭐ **This is a CHARACTERIZATION test and it must pass in BOTH worlds — before and after T2.** It does not
guard the fix; it establishes that the state the gate must handle is produced by *ordinary operation*.
Declaring it "should go red after the fix" would be wrong, and expecting that is the tell that the
mutation set contains no characterization arm.

**Why it lands first and alone:** it is green on the pre-fix tree, so landing it separately proves the
precondition **independently of** the clause change. Bundled with T2 it would be untestable in the
pre-fix world.

---

## T2 — AC1 + AC2 + AC3: drop the conjunct, state the reason, re-point the control ⛔ **ATOMIC**

⛔⛔ **These MUST be one commit.** Dropping the conjunct **reddens assertion B**, whose message argues to
restore it. A clause-only commit leaves the suite red with a guard recommending the defect; an
assertion-only commit leaves the suite green over an unfixed clause. Neither intermediate state is
acceptable on a shared branch.

### T2.1 — `plugin-claude-code/skills/wrapup/SKILL.md`, Step 6.5 item 1

Trigger — replace the conjunct with a positive statement:

> …holds an unconsumed entry carrying a **non-empty prompt block** — **whatever its `lastEvent`, and
> whatever its `sessionId`** — call `kt_ss_ledger_add` …

Then, immediately after the existing *"Skip the demote only for a FRESH `in-progress` marker…"* sentence,
add:

> ⛔ **The gate does NOT test `sessionId`, and that is deliberate.** A front-matter `sessionId` names
> whoever last **touched** the file, not whoever wrote the **body**: `post-edit-check.sh` stamps the
> current session's id onto the front matter while `kt_ss_mark_inprogress` passes the body through, so
> **your own id sitting over another session's prompt is the routine state, not an edge case.**
> `bin/lib-session-state.sh` records the same finding for the ledger key — *"the key can hold a value a
> HOOK wrote rather than the author."* ⚠ **`by:` does not rescue it either:** that field IS preserved by
> `kt_ss_mark_inprogress`, but it is **person-granular**, and this state is produced by the *same person
> in a second session*. ⇒ **A prompt you wrote yourself and a prompt a hook re-badged as yours are
> indistinguishable here, so both are demoted.** A pending entry you did not want is one deletion; an
> erased prompt is git archaeology.
>
> ⚠ **Consequence, chosen rather than incidental:** if you ran `/handoff` earlier in **this** session,
> `/wrapup` demotes **your own** pickup into `## Pending handoffs` rather than erasing it. Delete the
> pending entry by hand if you meant to discard the prompt. (The *"there is no next-session prompt to
> retain"* parenthetical below is about not adding a **new** entry for the wrapped session — it is not a
> claim that no prompt exists.)

### T2.2 — `plugin-claude-code/skills/handoff/SKILL.md` — **both** sites

⛔ **Two sites in one file, guarded by two different `awk` slices** (`HSEC` = the 3f summary line,
`HCLAUSE` = the `**Multi-session ledger` clause). Editing one is a partial fix — the prior round measured
exactly this shape.

- **3f summary line:** `…carrying a non-empty prompt block exists (different or absent \`sessionId\`)` →
  `…carrying a non-empty prompt block exists (whatever its \`lastEvent\`, and whatever its \`sessionId\`)`
- **Ledger clause:** drop `and its \`sessionId\` differs from this session's (or is absent — treat an
  unidentifiable handoff as *someone else's*)`, and carry a one-sentence pointer to T2.1's reason.
  ⛔ That parenthetical is the false premise stated outright — it must go, not be softened.

### T2.3 — `tests/repros/wrapup-demotes-before-rewrite.sh`, assertion `B`

Replace in place. ⛔ **Do not delete it** — that leaves the trigger unguarded and is how the invariant
later breaks from the other end.

```sh
# ── B: the gate is the BODY, not an identity field ───────────────────────────────────────────────
# ⛔ THE PREVIOUS VERSION OF THIS CHECK ASSERTED THE DEFECT. It required the phrase
# "different or absent sessionId" and its failure message argued for it ("unconditional demote would
# demote the session's OWN entry"). That premise is false: post-edit-check.sh stamps the CURRENT
# session's id onto front-matter while kt_ss_mark_inprogress passes the body through, so "the
# session's OWN entry" is not a state this gate can observe. See the design spec §2.2.
_B_RETIRED='different or absent'
printf '%s' "$WSEC" | grep -qF "$_B_RETIRED" \
  && bad "B1 retired sessionId conjunct" "the gate still conjoins a sessionId test, so a hook-stamped marker carrying another session's prompt is never demoted" \
  || ok  "B1 wrapup: retired sessionId conjunct absent"
printf '%s' "$WSEC" | grep -qiE 'whatever its .?sessionId' \
  && ok  "B2 wrapup: gate is explicit that sessionId is not tested" \
  || bad "B2 sessionId non-test" "the gate no longer STATES that sessionId is untested, so the next reader re-adds it"
```

Plus the handoff-side mirror on `HCLAUSE` **and** on `HSEC` — two separate assertions, so M2 and M3
below can be told apart.

⛔⛔ **`B2`'s positive arm is keyed on `whatever its .?sessionId`, NOT on the bare word `sessionId`.**
T2.1's explanation necessarily *mentions* `sessionId` — a bare-word arm would be satisfied by the prose
rather than the gate. Pattern `own-comment-enters-the-text-its-guard-reads`; this file **already** carries
that warning for C1/H1, so a third instance is not excusable.

---

## T3 — AC6: the hook-artifact annotation (D-B) — own commit, after T2

Add to the `kt_ss_ledger_add` instruction at **both** claude-code sites:

> ⚠ **`<prior sessionId>` may be a hook artifact — annotate it when it is.** If the value you are about
> to pass equals **this** session's id while the prompt block is not one you wrote, the front matter was
> stamped by `post-edit-check.sh` and the true author is **not recoverable from the file**. Prefix
> `<prior currentFocus>` with `⚠ sid is a post-edit-check.sh HOOK ARTIFACT, not attribution —` so the
> entry does not read as yours. ⛔ **It goes in `focus`, never in the sid** — the sid is what
> `kt_ss_ledger_mark_consumed` (`^### .*<sid>`) and `is_entry_header` key on, and a cross-repo checker
> captures everything before the first `·` as the id.

Assertion: exact-string presence of `HOOK ARTIFACT, not attribution` in both slices.

⚑ **Grepping prose is correct HERE and wrong in T2.3, and the distinction is the point:** in T2.3 the
prose is *explanation* and the gate is the deliverable, so prose satisfying the arm is a false pass. In
T3 the **instruction IS the deliverable** — there is nothing else to assert.

---

## T4 — AC7: correct the runtime-drift note (own commit)

Replace SKILL.md:190's note with the per-runtime state from T0's `0g`, **stamped with its measurement
date**, and stating the two remediations separately (three sites carry the conjunct; codex wrapup lacks
the step). ⛔ Do not restate the current claim in softened form — it is false, not vague.

⛔ **CONSTRAINED BY assertion `F` (G2-C5):** `F` runs `grep -qiE 'antigravity|codex'` over the Step 6.5
slice, so **the replacement must retain both words.** The per-runtime table does; a terser rewrite
("the ports carry this too") would redden `F` — and `F`'s message would then blame a missing drift note
rather than a missing keyword.

---

## T5 — mutation ledger ⛔ **pre-declared before any is run**

Every mutation names the control that must catch it, and each is confirmed to have **created** the
condition — not merely to have applied.

| M | Mutation | Named control that must fire | Expected |
|---|---|---|---|
| **M1** | re-insert the conjunct into wrapup Step 6.5 | `B1 wrapup: retired sessionId conjunct absent` | **RED** |
| **M2** | re-insert it into handoff's **ledger clause** | the `HCLAUSE` absence arm | **RED** |
| **M3** | re-insert it into handoff's **3f summary line** | the `HSEC` absence arm — **a different assertion than M2** | **RED** |
| **M4** | delete `non-empty prompt` from wrapup's trigger | pre-existing `C2` | **RED** — proves T2 did not weaken the surviving guard |
| **M5** | in `bin/lib-session-state.sh`, flip the **existing-`sessionId` branch** to preserve instead of overwrite: `if ($0 ~ /^sessionId:/) { print; ssid=1; next }` | **T1 arm 1 only** | **RED** — and reddens *nothing else* |
| **M6** | delete T3's annotation sentence from wrapup | **only** T3's presence arm; every other assertion stays green | **RED (scoped)** — a scope test, not a redundancy test |

⛔ **M3 is the load-bearing one.** If M2 and M3 fire the *same* assertion, the two handoff sites are not
separately guarded and "editing 3f alone is a partial fix" is undetectable — the exact failure the prior
round measured.

⛔⛔ **M5 WAS REPLACED AT GATE 2 (G2-C2).** It originally read *"make `mark_inprogress` drop the body"* —
which reddens **block `D`'s existing assertion as well as T1**, so it could not confirm that the NAMED
control fired. The replacement mutates the branch T1 exists to assert: `D`'s fixture has no `sessionId:`
line, so it takes the *insert* path (`infm == 2`) and is untouched ⇒ the mutation reddens **only** T1
arm 1. It is also the faithful real-world regression, which the original was not.

✅ **M5's blast radius is otherwise CLEAR, measured (G2-C4):** the library port-parity assertion `N`
covers `_SS_PARITY_FNS="kt_ss_ledger_add kt_ss_ledger_prune"` — **`kt_ss_mark_inprogress` is not in the
set**, so mutating it does not trip `N`.

⛔ **M5 mutates a shipped library.** Byte-backup first (`cp`), restore, then verify with **both** `cmp`
against the backup **and** `git diff --exit-code` on that path. ⛔ Never restore with `git checkout --`
— it reverts to HEAD and would discard any uncommitted work in the file.

---

## T6 — gate

- `sh tests/run.sh` → bare exit **0**; suite count **38**; `^FAIL` **0**.
- Assertion delta vs T0's `0c` reconciles **exactly** to the enumerated table below. ⛔ **A running
  total in prose is what gate 2 falsified here (G2-C3)** — the earlier figure did not close, and a gate
  whose expected value is wrong fails on correct work or passes on incorrect work.

  | axis | assertions | note |
  |---|---|---|
  | wrapup — conjunct **absence** + **positive** | +2 | `B1`, `B2` |
  | handoff `HCLAUSE` — absence + positive | +2 | |
  | handoff `HSEC` — absence only | +1 | ⛔ **no positive arm, deliberately** — its one-line form carries the same phrase, and a second near-identical arm splits recall for no coverage |
  | T3 annotation presence × 2 slices | +2 | |
  | T1 claim + labelled control | +2 | |
  | retire the old `B` | **−1** | |
  | **net** | **+8** | baseline 498 ⇒ **expect 506** |
- `git diff --stat` touches only: 2 SKILL.md, 2 test files. **Zero** changes under `bin/`.
- Every mutation in T5 restored and verified.

---

## Explicitly NOT in this plan

- **OQ1 — port parity** (antigravity wrapup + handoff, codex handoff carry the conjunct; codex wrapup
  lacks the step). Two different remediations, both Mike's scheduling call.
  ✅ **Its technical precondition is CHECKED and CLEAR (G2-C6) — recorded so nobody re-investigates.**
  The corrected clause's stated *reason* ports: `kt_ss_mark_inprogress` cksums identical across
  claude-code / antigravity / cursor, and codex's copy differs **only in its `.gitignore` block** —
  **both carry exactly one `{ print }`**, so the body passthrough is the same everywhere.
  ⚠ **One residual belongs to whoever closes OQ1, not to this plan:** `kt_ss_mark_inprogress` is
  **absent from the library parity set** *and* has drifted on one port. The function the corrected
  reason depends on is unguarded for cross-port drift.
- **OQ2 — release cadence.** Mike's.
- **Any change under `bin/`.** `lib-session-state.sh` is already correct on this axis and must not be
  edited to match a skill that was wrong. M5 touches it only as a mutation, restored.
- **A behavioural test of the gate decision.** Structurally unavailable (model-executed; the suite's own
  dogfood ceiling). Recorded as a ceiling, **not** an open item.
- **The `## Pending handoffs` heading-scope / terminator class.** Tracked separately.
- **Recovering the true author** of a hook-stamped entry. Unrecoverable; T3 annotates the uncertainty.

---

## Ordering

```
T0 (read-only, abort on mismatch)
 └─ T1                      additive, green in BOTH worlds, lands alone
     └─ T2  ⛔ ATOMIC        clauses + assertion B together, never split
         └─ T3              annotation
             └─ T4          drift note
                 └─ T5      mutations (declared first, restored, verified)
                     └─ T6  gate
```

⚠ **Nothing here is rendered or model-executed by the gate.** Every check is a shell assertion or a
static census. The one thing no gate in this plan can establish is whether a *model reading the
corrected clause* now demotes correctly — that is the dogfood ceiling, and the honest acceptance for it
is the next real `/wrapup` on a project holding a foreign handoff.
