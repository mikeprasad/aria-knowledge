# Plan — user-rule lead extraction, one definition

**Status:** GATED — gate 2 run 2026-09-05, verdict PROCEED-WITH-CHANGES; P1–P3 + M7 applied in
this revision. Report: `knowledge/logs/prospect/2026-09-05-file-user-rule-lead-extraction-plan-gate2.md`
**EXECUTED 2026-09-05 — STAMPED SPENT, do not re-execute a task.**
Gates: G1 331 passed / failure set identical BY NAME to baseline ([AR14] only, pre-existing,
out of scope) · G2 **7/7 mutations RED for their named control**, both files restored and
`cmp`-verified · G3 byte-identical on the frozen corpus WITH a firing positive control
(`OK U1 67 bytes` -> `NOLEAD U1`) · G4 aria-knowledge drift 4 -> 5 as predicted
(`check-rule-lead-bytes.sh` was previously in sync and is now changed).
⚑ M4 came back GREEN on first run: the MUTATION was unfaithful, not the guard — no fixture led
with `Why`, so adding it to the skip set changed nothing observable. A `Why`-led fixture
(UD18e) was added and M4 then failed two independent controls.
**Spec:** `docs/superpowers/specs/2026-09-05-user-rule-lead-extraction-one-definition-design.md` (GATED, C1–C4 applied)
**Gate 1:** `knowledge/logs/prospect/2026-09-05-file-user-rule-lead-extraction-one-definition.md` — PROCEED-WITH-CHANGES
**Rolls into:** v2.52.0 (unreleased). ⛔ C4 anchor: re-verify the slot at T5, never trust this line.

## Baseline (re-measure at execute time; these are 2026-09-05 readings at HEAD `9f46c43`)

| Quantity | Value | Command |
|---|---|---|
| plugin suite | **315 passed, 1 failed, bare exit 1** — `[AR14]` pre-existing | `sh plugin-claude-code/tests/run.sh` |
| digest suite assertions | 20 | `tests/test-user-rules-digest.sh` |
| audit-rules gate assertions | 5 (AR1–AR5) + AR7 text | `tests/test-audit-rules.sh` |
| real corpus, gate output | **15 OVER / 12 OK**, exit 1 — ⚠ MOVING, see T0 note | against the FROZEN fixture, not the live file |
| metadata-first rules in real corpus | **0** | awk probe, §T0 |
| Origin-first rules in real corpus | **0** | awk probe, §T0 |

## T0 — trip-wire (no edits)

Re-derive the six baseline rows above. **Any disagreement halts the plan** — in particular a
non-zero metadata-first or Origin-first count invalidates AC5's precondition (C1) and the plan
must be re-gated, not adjusted.

⛔ **T0 RAN 2026-09-05 AND HALTED TWICE. Both resolved; recorded because the corrections are
load-bearing:**

1. **The suite baseline was wrong — it was taken from the CHANGELOG's claim, never from a run.**
   Measured: **315 passed, 1 failed, bare exit 1**. The failure is `[AR14] MC2 ratchet: zero
   unadvertised hyphen command forms`, caused by two committed `/audit-config` hyphen forms at
   `skills/setup/SKILL.md:732,734` from `2da33ce` (2026-09-01) — **pre-existing, and outside this
   plan's scope** (my working tree touches zero plugin files; AR14's scan root is
   `$PCC/{skills,bin,template,rules}`, which excludes `docs/`). ⇒ **G1 is restated below as
   failure-set-identical-BY-NAME, not bare exit 0.** Reported separately to the maintainer.
2. **The corpus is MOVING.** `knowledge/rules/user-rules.md` is modified in the working tree by a
   parallel session (` M`, mtime 00:07); the gate's OVER count moved **13 → 15 within this
   session**. ⇒ **T4 runs against a FROZEN snapshot**, not the live file. This follows the existing
   suite's own precedent — `tests/test-user-rules-digest.sh:108-110` already freezes a fixture for
   exactly this reason ("this workspace runs concurrent sessions").
   ⚑ AC5's preconditions were re-measured on the frozen copy and **both still hold: 0 metadata-first,
   0 Origin-first.** That is the row AC5 actually depends on; the OVER/OK split does not affect it.

⛔ The counts are in the unit *rules whose FIRST non-blank paragraph matches*, not *files
containing the marker* — every rule file contains exactly one `**Last updated:` (its header).
Comparing those units is the `a-count-carried-across-a-change-of-unit` error.

## T1 — generator: allow-list metadata skip (`bin/lib-user-rules.sh`)

Replace the single `**Origin:` arm at `:157` with a shared marker set.

- Skip set: `Origin` · `Last updated` · `Status` · `Superseded`.
- Semantics preserved exactly: a skip-marker paragraph that **leads** is skipped; one that
  **follows** the lead ends the lead (both arms already exist for `Origin`).
- ⛔ **(P1) An empty lead needs its OWN guard — branch (iv) does NOT cover it.** Gate 2 measured
  the actual output: `- **U1 — Metadata-only rule** — `, a **dangling separator with an empty
  body**. Mechanism: `flush()` computes `length(p)` on an empty `p` = 0, which satisfies
  `length(p) <= window`, so **branch (i)** fires; branch (iv)'s guard is `length(p) > ceiling`
  and an empty lead is the smallest possible value, so it is unreachable.
  ⇒ Add an explicit guard at the top of `flush()` — after the `tag == ""` return and after
  `gsub` — emitting the branch-(iv) form `printf "%s- **%s — %s**"` (no separator) and returning.
  ⚑ This fixes a defect present **at HEAD**: `**Origin:` is already skipped, so an Origin-only
  rule renders that dangling line today.
- ⛔ C3: `Why` / `How to apply` are NOT in the set and a comment must say why.

## T2 — gate: same set + two new outcomes (`bin/check-rule-lead-bytes.sh`)

- Same skip set, same leading/following semantics — the gate currently has **none**.
- New `NOLEAD U<n>` line + non-zero exit when a rule's only paragraph(s) are skip-markers.
- ⛔ **(P2) The skip and NOLEAD MUST land in the SAME edit.** `report()` opens with
  `if (tag == "" || lead == "") return`, so adding the skip alone makes a metadata-only rule's
  lead empty and the rule **vanishes from gate output entirely** — no line, no exit change.
  That converts a wrong-number bug into a silent missing-rule bug, which is strictly worse.
- New `UNKNOWNLABEL U<n>` **warning** line when the lead matches `^\*\*[A-Z][A-Za-z ]*:` but is
  not in the skip set. Non-fatal — does not change exit status.
- Exit contract: `0` clean · `1` any OVER **or** any NOLEAD · `2` usage. AR5's exit-2 arm untouched.

## T3 — tests (`tests/test-user-rules-digest.sh`, extend)

- **UD8 agreement (the class close):** for each shape in a matrix — plain / Origin-first /
  `Last updated`-first / `Status`-first / unknown-label-first / metadata-only — assert the gate's
  measured byte count equals the byte length of the paragraph the generator actually rendered.
  This is the assertion that fails if the two ever diverge again.
- **UD9** Origin-first: gate reads the lead (71 B), not the Origin block (62 B). *(AC2)*
- **UD10** `Last updated`-first: gate emits `NOLEAD`, exit non-zero; generator renders title-only. *(AC3)*
- **UD11** `Status`-first behaves as UD10; **unknown label** (`**Never do X:**`) is treated as the
  LEAD and warned about, never skipped. *(AC4, C3)*

## T4 — corpus byte-identity (AC5, as reworded by C1)

Capture gate output + generator output on the real 27-rule corpus **before** T1, and diff after.
Expect byte-identical. ⛔ Also re-assert the **precondition** (0 metadata-first, 0 Origin-first) —
a clean diff with a changed precondition is not evidence.

## T5 — CHANGELOG (AC7)

Amend the **existing open 2.52.0 entry**; do not open a new version.
⛔ C4 first: `head -5 CHANGELOG.md` and `git ls-remote --tags origin | tail`. If v2.52.0 has been
released or the slot reassigned in the interim, **stop and re-gate** — do not silently retarget.

## Mutations (each must be RED for its NAMED control, restored from a byte backup verified by `cmp`)

| # | Mutation | Named control that must fire | Would-be-silent without it |
|---|---|---|---|
| M1 | Remove `Last updated` from the gate's skip set | UD10 (NOLEAD) | the reported defect returns |
| M2 | Remove `Last updated` from the **generator's** set | UD8 agreement | gate and generator diverge again |
| M3 | Remove `Origin` from the gate's set only | UD9 | the live Origin-first divergence returns |
| M4 | Add `Why` to the skip set | UD11 | real rule content silently discarded |
| M5 | Make `UNKNOWNLABEL` fatal | AR1/AR4 (must stay exit 0) | legitimate leads start failing the gate |
| M6 | Make NOLEAD exit 0 | UD10 | a metadata-only rule passes silently |
| M7 | Remove the T1 empty-lead guard (P1) | a new assertion that **no digest line ends with a dangling `— ` separator** | the P1 guard is untested and silently revertible |

⚠ **M2 is the one that matters most and is the easiest to get wrong.** UD8 asserts the two
*agree*; if it is written to compare each side against a hard-coded expected number instead of
against *each other*, it stays green under M2 and the whole class-close is decorative.

## Gates

- G1 `sh plugin-claude-code/tests/run.sh` — the **failure set is IDENTICAL BY NAME to the T0
  baseline** (i.e. `[AR14]` only; zero NEW failures). ⛔ Not bare exit 0 — the tree is already red
  for a pre-existing, out-of-scope reason, and demanding exit 0 would either block a correct change
  or tempt an unrelated fix into this arc. The assertion count **increases** and
  all four new named cases (UD8–UD11) appear in output. ⛔ **(P3) Do NOT pin a numeric delta.**
  UD8 is a matrix over six shapes, so the exact count depends on how many of them assert
  individually — an implementation choice. Pinning `+4` guards spelling and would fail a correct
  implementation (`a-count-carried-across-a-change-of-unit`).
- G2 all six mutations RED for their named control, then restored and `cmp`-verified
- G3 T4 byte-identity + precondition re-assert
- G4 `bash tools/check-plugin-drift.sh` unchanged for aria-knowledge (still `differ=4`) —
  this plan does not close install drift, and must not appear to

## Out of scope (restated so it cannot drift in)

The 240 value · the four-way rendering · releasing v2.52.0 (OQ1, maintainer's) · the ports
(`lib-user-rules.sh` is `plugin-claude-code`-only; the antigravity build carries an explicit skip arm).
