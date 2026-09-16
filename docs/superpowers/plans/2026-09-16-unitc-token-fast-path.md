# Unit C — the token fast path (D5) and operator precedence (D7)

**Spec:** `docs/superpowers/specs/2026-09-15-handoff-resume-and-provenance-token-merged-design.md` (GATED).
**Gate:** `knowledge/logs/prospect/2026-09-15-file-handoff-resume-and-provenance-token-merged.md` — S5 ruled
**SPLIT into unit C, last; the only step depending on both A and B.**
**Predecessors shipped:** Unit 0 `f97542d` · Unit A `7f1d9e6` `bcd3ab5` + D4 · Unit B `126d015` + the picker.
**Scope:** `plugin-claude-code` only. Ports are Unit P.
**Status:** ✅ **GATED 2026-09-16 — `/prospect` PROCEED-WITH-CHANGES; the change is applied at AC-C6
(assert the EMITTED directive, not the file source).** Gate log:
`knowledge/logs/prospect/2026-09-16-file-unitc-token-fast-path.md`.

---

## 0. ⛔ First finding — J1's receipt obligation has no host, and that CLOSES it

J1 was accepted with the disposition *"the receipt obligation is carried into Unit C's promote path
(D5 step 3)."* Carrying it out, the obligation **dissolves**:

- D5's five steps are **locate · mark consumed · report**. Step 3 turns the active prompt into a
  `### ` entry marked consumed — it **ADDS** a key.
- `kt_ss_ledger_add` is purely additive (measured 2026-09-15).
- `kt_ss_ledger_prune` already writes receipts.

⇒ **After D4, no sanctioned operation removes an entry key while preserving its content.** A receipt
covers exactly that operation, so there is nothing for it to cover.

⭐ **And the consequence is stronger than "no work needed."** If no sanctioned operation does it, then
a key vanishing with its content preserved is an **unsanctioned hand-edit** — the `bc3579b` shape —
and the detector reporting it is a **TRUE POSITIVE**. The "third false-positive shape" recorded on
2026-09-14 is, after this arc, largely not a false positive at all.

⛔ **Therefore this unit builds NO promote helper.** Nothing in the spec requires promoting a pending
entry into the active slot; inventing one to host a receipt would be building a capability to satisfy
a bookkeeping obligation that its own absence already discharges (Rule 13).

⚠ **Recorded, not silently revised.** J1 was accepted with a different disposition. This is the
follow-through, logged beside it; Mike's ruling stands and this says what happened when it was
executed.

---

## 1. What Unit C adds

### C1 — `kt_ss_token_locate <root> <token>` (read helper)

Emits `<sid>|<at>|<status>|<source>` for the candidate whose stored prompt carries `<token>`, or
nothing. Same contract as `kt_ss_ledger_candidates`, same reasons: a shell suite can hold it, and
the alternative is a third hand-rolled parse.

⛔ **Locate by the TOKEN STRING, not by sid.** The token resolves whether the prompt is still active
or has since been demoted — and that relocation is not hypothetical: `13ad7ba` demoted a prompt 14
minutes after it was written.

⚠ Reuses the fence/heading walk. ⛔ An archived section is still excluded: a token found there is
**located but not offered**, which is a different answer from *not found* and the two must not be
collapsed.

### C2 — the SessionStart token branch (D5)

A token branch **above** the existing word-`handoff` branch in the SESSION STATE directive:

1. token in the opening message → `kt_ss_token_locate`
2. found, live → resume it, then mark consumed with the **exact `(sid, at)`** (D6's fifth argument)
3. found, already terminal → ⛔ **surface and STOP.** The concrete hazard: a prompt sat `unconsumed`
   while its work shipped as an irreversible migration, so resuming it would re-apply an applied drop.
4. not found → say so plainly. ⛔ **Do not fabricate an entry.**
5. no token → the existing behaviour, unchanged. 152 stored prompts carry none.

### C3 — operator precedence (D7) — ⭐ the requirement that came from Mike, not from the corpus

Mike copies the whole fence **"but sometimes adds a sentence preceding it."** Two consequences:

- **R1 — scan the WHOLE opening message.** A preamble pushes the token off line 1.
- **R2 — ⛔ operator text accompanying the paste is an INSTRUCTION and outranks the stored prompt.**
  The directive currently says *"execute that prompt directly (no confirmation)"*, which would drive
  straight past *"before you start, see the parallel session's work"*. That sentence shape is a
  mandatory pre-execution state-verify gate (user rule U14). ⇒ when the opening message carries text
  beyond the pasted block, **surface it and reconcile before executing**.

⚑ R2 is the one requirement in this whole arc that no amount of corpus reading would have produced.
It came from one clause of one answer about how he actually pastes.

---

## 2. Tasks

| # | Task | Gate |
|---|---|---|
| **C0** | Baseline the three suites — counts + **bare** exit codes | numbers to compare |
| **C1** | Failing tests for `kt_ss_token_locate` | red for the right reason |
| **C2** | Implement it | suite green |
| **C3** | Mutation-verify each arm — name the control, prove the condition | every arm seen red |
| **C4** | SessionStart directive: token branch + R1/R2 | emitted-text guard |
| **C5** | Full gates + Gate B | all bare exit 0 |

### Acceptance

- **AC-C1** a tokened prompt in the ACTIVE slot is located and tagged `active`.
- **AC-C2** the same token after DEMOTION is still located, now tagged `pending` — the relocation case.
- **AC-C3** a token in an ARCHIVED section is located but reported not-offered — ⛔ distinct from
  not-found; collapsing them would silently resurrect archived work.
- **AC-C4** an absent token yields nothing and **does not error**.
- **AC-C5** ⛔ **non-regression** — a file with no tokens at all yields nothing, and
  `kt_ss_ledger_candidates` is unaffected. The 152 tokenless prompts must behave exactly as today.
- **AC-C6** ⭐ **STRENGTHENED BY THE GATE.** The draft conceded a weak bound — "guards the clause's
  presence in the file" — without checking whether a stronger one was already available. It was:
  `tests/repros/autonomy-posture.sh` and `picker-gating.sh` already drive `session-start-check.sh`
  via a `KT_CONFIG` stub and capture **stdout**. ⇒ assert the token branch and R2's precedence clause
  in the **EMITTED** directive, using the technique this suite already owns.
  ⚠ **The bound that genuinely remains:** this guards what the hook PRODUCES, never an agent's
  obedience to it. That is stated rather than implied — a criterion claiming coverage it lacks is the
  `comment-is-not-a-guard` shape. ⚑ A conceded limitation is a claim like any other and takes the
  same sourcing; this one was wrong.

---

## 3. Out of scope

A promote helper (§0) · the `archive` verb · all ports (Unit P) · any change to the picker shipped in
Unit B · retro-fitting tokens onto existing prompts.
