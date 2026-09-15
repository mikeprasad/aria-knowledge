# Unit B — the `resume` command surface and the candidate picker (D1 · D2 · D3)

**Spec:** `docs/superpowers/specs/2026-09-15-handoff-resume-and-provenance-token-merged-design.md` (GATED).
**Gate:** `knowledge/logs/prospect/2026-09-15-file-handoff-resume-and-provenance-token-merged.md` — S3 `✅`,
S4 `⚠ theory-driven`, ruled **SPLIT into unit B, re-measure its driver first**.
**Scope:** `plugin-claude-code` only. Ports are Unit P.
**Predecessors shipped:** Unit 0 (`f358628`), Unit A (`78c6a01`, D4, `bcd3ab5`).
**Status:** ✅ **GATED 2026-09-16 — `/prospect` PROCEED-WITH-CHANGES; the change is applied at T3
below (the parser is a READ HELPER, not prose).** Gate log:
`knowledge/logs/prospect/2026-09-16-file-unitb-resume-mode-and-picker.md`.

---

## 0. Drivers, re-measured 2026-09-16 — and one of them moved because of us

| Driver | 2026-08-25 | 2026-09-16 | Consequence |
|---|---|---|---|
| projects with ≥2 candidates | 5 of 6 | **4 of 8** | still half the corpus — the picker is justified |
| largest candidate set | ~3 | **41 (`cs`)** | ⛔ a full numbered table is unusable — the design assumed a handful |
| live stale share | 62% | archived out | staleness gating still required, but the live list is now mostly fresh |
| offered entries lacking a terminator | 37.5% | **2.4% (1 of 42)** | ⛔ **DO NOT DROP THE FALLBACK — see below** |

⛔⛔ **THE TERMINATOR FIGURE FELL BECAUSE OF OUR OWN ARCHIVING, NOT BECAUSE THE HAZARD WENT AWAY.**
The 37.5% came largely from `aria` (2 unconsumed, 0 terminators) and `df` (1, 0) — **precisely the
entries archived on 2026-09-15**. They still exist in their files; they are simply no longer
*offered*. Anything that parses the whole file still meets them.

⇒ **The legacy fallback's justification is AC5's mutation, never the incidence number.** A future
reader re-deriving 2.4% could reasonably conclude the fallback is dead weight. It is not. Record the
cause beside the number or the next measurement lies by being accurate.

⚠ `cs` moved 39 → 41 offered entries within the hour, from a concurrent session. Every count here is
a sample, not a constant.

---

## 1. Decisions carried (already ratified — not re-opened here)

- **D1** staleness shown at summarization **and** gated at selection; `[resume / keep]` only —
  ⛔ `archive` stays split out, because `kt_ss_ledger_archive` does not exist and inventing it here
  is new write machinery inside a unit that promised none.
- **D2** combine offered **only** on same-root + disjoint `next:`, never auto-selected.
- **D3** the active prompt and pending entries are **one candidate set** — which is what closes G3
  (a pending entry with no active sibling currently surfaces nothing).

## 2. What Unit B adds

### T1 — declare the mode (spec AC1)

`argument-hint`, the description trigger, Step 0's parse, and ⚠ **Step 0's fallback string, which
enumerates the valid modes VERBATIM** — miss it and the error message lists 4 of 5.

⛔ **Budget: 449 B.** Gate B measures summed `description:` bytes against 19,968 and currently reads
19,519. `argument-hint` is **not** counted (the awk stops at the next top-level key), so only the
description edit spends. Per the gate's own instruction, an overrun is answered by **trimming, never
by raising**.

### T2 — the candidate set (D3)

Sources, in one list: the active `## Next session prompt` (when non-empty) **plus** every
`unconsumed` entry under `## Pending handoffs` **or** the legacy `## Prior sessions`.
⛔ **Archived sections are excluded** — that is what archiving means, and it is now load-bearing:
89 entries were archived out of `cs` on 2026-09-15 precisely so they would stop being offered.

### T3 — the parser: `kt_ss_ledger_candidates <root>` — a READ helper, **not prose**

⛔ **CHANGED BY THE GATE. The first draft said "parser implementation" without naming an artifact,
and that ambiguity is fatal to AC5.** AC5 requires a fixture yielding 2 candidates plus a mutation
that reddens, in `tests/repros/session-state.sh` — and **a shell suite cannot exercise a parser that
exists as prose in a SKILL.md**. Measured: `lib-session-state.sh` carries 10 helpers and none
enumerates candidates (negative control on candidate/list/enumerate symbols: 0).

⇒ **Contract:** `kt_ss_ledger_candidates <root>` emits one line per candidate,
`<sid>|<at>|<status>|<source>` where `source` is `active` or `pending`. Read-only; it never writes.

Three reasons this is the right shape, not merely the testable one:
- it makes **AC5 real** rather than aspirational;
- it puts the four-axis parse in **one place**, instead of resume, the picker and Unit C's token
  lookup each re-deriving it from prose — three call sites, one defect (Rule 38);
- it is a **READ** path, so it honours the 2026-08-25 design's "this unit introduces no new write
  path" while giving the unit something a suite can hold.

⚠ Cost, acknowledged here rather than discovered at Unit P: a new helper is new surface in the
three ports that carry `lib-session-state.sh` (codex carries only 2 of the 8 and no ledger
functions at all).

**The four axes it must absorb** (spec §4); a naive parse silently drops candidates:
two headings · two terminators (explicit marker, or **nothing**) · two prompt serializations
(`- prompt: |` + indented block scalar, vs `- prompt:` + raw lines) · three-plus header state forms.

⛔ A terminator-only parse must fall back to **"next `### ` or next `## `"**.
⛔ Acceptance needs the **negative control**: a parser that finds 5 of 8 looks exactly like a
`SESSION.md` that has 5 entries.

### T4 — the presentation (D1/D2) — ⭐ **this is where the re-measurement changes the design**

The ratified shape is a numbered table of `focus` / `next` / age / freshness, built from stored
fields with **no synthesis**. At 41 candidates that is unusable.

⇒ **Cap the rendered list.** Show the **5 most recent** candidates, newest first, each with its
freshness verdict, then one line: `… and N more (M stale) — say "all" to list them`.

⚑ **The cap is the one judgment in this unit and it is declared as such.** 5 is chosen to fit a
terminal without scrolling, not derived. What is *not* a judgment is that a cap must exist: 41 rows
of `focus` + `next` cannot be read, and no reading of D1 or D2 argues for rendering them.
⚠ **Capping is a RENDERING decision only.** Selection still accepts any candidate, and the count of
what is hidden is always shown — a cap that silently hides candidates is the failure this ledger
exists to prevent.

---

## 3. Tasks (TDD — red before green, one commit per task)

| # | Task | Gate |
|---|---|---|
| **T0** | Baseline: `tests/repros/session-state.sh`, `tests/run.sh`, plugin suite — counts + **bare** exit codes | numbers to compare against |
| **T1** | Failing tests for the parser: legacy + current in one fixture ⇒ **2** candidates | red for the right reason |
| **T2** | Implement `kt_ss_ledger_candidates` (read-only) | suite green |
| **T3** | Mutation-verify **each** new assertion — name the control, prove the condition was created | every arm seen red |
| **T4** | Mode declaration + description edit | ⛔ Gate B re-measured; trim, never raise |
| **T5** | Picker clause: candidate set, freshness, cap, combine, selection | clause self-consistent with T2's parser |
| **T6** | Full gates: session-state, `tests/run.sh`, plugin suite, Gate B | all bare exit 0 |

### Acceptance (spec AC1–AC7, made executable)

- **AC1** `resume` declared in `argument-hint`, description, Step 0 parse **and Step 0's verbatim
  mode-list string**.
- **AC2** one candidate → states `focus` + age, confirms, executes. Zero → says so, **does not error**.
- **AC3** ≥2 → numbered rows from stored fields, **no synthesis**, then a pick.
- **AC4** every row carries a freshness verdict; a stale pick requires `[resume / keep]`.
- **AC5** ⛔ **legacy parity** — a fixture holding one legacy entry (`## Prior sessions`, no
  terminator) **and** one current entry yields **2**. Mutation: remove the fallback → red, naming the
  dropped entry. ✅ Extend the existing
  `tests/fixtures/session-contract-vendored/handoff-multi-session.SESSION.md`; do not author a new one.
- **AC6** pending entries with **no** active prompt are still listed (G3).
- **AC7** combine offered only under D2's predicate; never auto-selected; absence ≠ error.
- **AC8** `[new]` **the cap shows what it hides** — a fixture with more than 5 candidates renders 5
  rows **and** a remainder line carrying the true total. *Red if:* the remainder is absent or wrong.
- **AC9** `[new]` **archived entries are NOT offered** — a fixture with entries under
  `## Archived sessions` yields zero candidates from that section. *Red if:* any appears. This is the
  arm that protects the 2026-09-15 archiving from being silently undone.

---

## 4. Out of scope

`archive` as a verb and `kt_ss_ledger_archive` (D1, its own unit) · the token fast path (D5/D7,
Unit C) · all ports (Unit P) · the two malformed `## Archived — superseded …` headings in
`cs/SESSION.md`, which the checker already warns about and which are a pre-existing two-word fix.
