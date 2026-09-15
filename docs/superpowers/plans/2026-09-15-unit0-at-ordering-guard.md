# Unit 0 — the `at`-ordering guard and self-demote (D10)

**Spec:** `docs/superpowers/specs/2026-09-15-handoff-resume-and-provenance-token-merged-design.md`
(GATED 2026-09-15). **Gate:** `knowledge/logs/prospect/2026-09-15-file-handoff-resume-and-provenance-token-merged.md`
— S9 `✅ Pre-validated`, `PROCEED`, ruled to ship **first and alone**.
**Scope:** `plugin-claude-code` only. Ports are Unit P, not interleaved (U16).
**Status:** ✅ **GATED 2026-09-15 — `/prospect` verdict PROCEED-WITH-CHANGES; the one change is
applied in T2 above (shape gate narrowed to second-precision `Z` only, on a re-measurement of the
correct population).** Gate log: `knowledge/logs/prospect/2026-09-15-file-unit0-at-ordering-guard.md`.

---

## Why this unit is separable

Measured at the gate: D10 needs **no token, no parser, no new format, no new global state**. It reads
a front-matter field present in **8 of 8** tracked ledgers, compares two strings, and on one branch
calls `kt_ss_ledger_add`, which already exists and is already called by both skills.

## The defect, restated in one line

`bin/lib-session-state.sh` contains **0** comparisons of the incumbent's `at` (measured). The
front-matter is a single-valued, last-writer-wins record written by N concurrent sessions, so an
older session's close-out silently regresses a newer session's state. Demote protects the
incumbent's **prompt**; nothing protects its **state**.

## Design

### T1 — `kt_ss_read_active_at <root>` (new reader)

Mirrors `kt_ss_read_active_sid` **exactly** — same guard, same front-matter awk walk, same
`return 0`. Only the key differs (`at:` instead of `sessionId:`). Deliberately a sibling rather
than a generalised `kt_ss_read_front_matter <key>`: two call sites do not earn a parameterised
reader (Rule 13), and the existing one is the house shape.

### T2 — `kt_ss_active_is_newer <root> <my_at>` (the verdict)

```
exit 0  → the incumbent IS strictly newer  ⇒ caller MUST NOT rewrite
exit 1  → anything else                    ⇒ caller rewrites exactly as today
```

⛔ **Fail direction is load-bearing and is the conservative one.** Incumbent absent, `at` missing,
either value unparseable, or the file missing → **exit 1** → today's behaviour. A brand-new guard
must not be able to block a write that works today; the damage it then fails to prevent is the
damage that already exists, which is strictly better than a new way to lose a write.

**Comparison is a plain string compare on ISO-8601 `Z`.** No `date` parsing — `date -d` is GNU-only
and this library is POSIX `sh` targeting BSD userland. ⛔ **A stamp that is not `Z`-normalised must
be REJECTED (exit 1), never compared** — a local-offset stamp compares lexicographically against a
`Z` stamp and silently mis-orders.

**Shape gate — SECOND-PRECISION `Z` ONLY:** `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`.

✅ **SHRUNK BY THE GATE, and the first draft was over-engineered off the wrong population.** It
required accepting minute-precision too, citing `2026-09-13T09:40Z` in `cs/SESSION.md`. Two errors:
that stamp was an **entry header**, and this guard reads the **front-matter** — different populations
— and it was an entry **this session had already renamed away**, so the citation was to evidence my
own earlier edit had removed.

Re-measured on the correct population: **8 of 8 tracked ledgers carry a second-precision `Z`
front-matter `at:`.** Minute-precision appears only in entry headers (6, all in `cs`), which D10 never
reads. So dual-precision handling is untested surface serving no live case — and if a minute-precision
front-matter ever does appear, it falls through the shape gate to **exit 1 = today's behaviour**,
which is the safe direction by construction.

⚑ **The rejection is NOT hypothetical, which is why it stays:** a live local-offset stamp exists in
the corpus — `2026-09-02T00:20:21+09:00`, measured in a `cs` entry header. That is precisely the shape
that compares wrong against a `Z` stamp while looking entirely reasonable.

### T3 — the clause, in `/wrapup` Step 6.5 and `/handoff` Step 3f

Both skills gain the same branch, sited immediately **before** the full rewrite:

1. Read the incumbent's `at`; call `kt_ss_active_is_newer`.
2. **exit 1** → proceed exactly as today (demote its prompt, prune, rewrite).
3. **exit 0** → ⛔ **do not rewrite.** Call `kt_ss_ledger_add` with **your own** sid/at/focus/next/prompt
   so your work lands in `## Pending handoffs`, leave the active front-matter untouched, and **state
   it in the closing report** — naming the owning session and both timestamps.

⚠ A `/wrapup` reaching branch 3 has no next-session prompt of its own to store. It still records the
close (focus + next) as a Pending entry so the session leaves a trace, which is the whole point —
the failure being fixed is a session that wrote *nothing*.

---

## Tasks (TDD — red before green,每 task one commit)

| # | Task | Gate |
|---|---|---|
| **T0** | Baseline: run `tests/repros/session-state.sh`, record `PASS`/`FAIL` counts and the **bare** exit code | a number to compare against |
| **T1** | Write the failing tests for `kt_ss_read_active_at` + `kt_ss_active_is_newer` (AC18 arms a/b/c + the non-`Z` rejection). **See them RED.** | red for the right reason |
| **T2** | Implement both helpers | suite green, count = baseline + new |
| **T3** | Mutation-verify **each** new assertion | every one seen red, and the *named* control fires |
| **T4** | Clause edits in `/wrapup` + `/handoff` | Gate B re-measured (449 B headroom; trim, never raise) |
| **T5** | Full suite + `release.sh` gates A–D | all bare exit 0 |

### Acceptance (spec AC18, made executable)

- **a** incumbent `at` **newer** → active front-matter **byte-unchanged**; caller's prompt present as a
  new `### ` entry.
- **b** incumbent `at` **older** → rewrite proceeds exactly as today. ⛔ **The non-regression arm** —
  without it a guard that always self-demotes passes (a) and breaks the normal path.
- **c** incumbent `at` **absent / unparseable / file missing** → treated as older, rewrite proceeds, no crash.
- **d** incumbent `at` **non-`Z`** (e.g. `2026-09-15T10:00:00+09:00`) → rejected, exit 1, no compare.
- **e** ⛔ **equal `at`** → NOT newer → exit 1 → rewrite. Named explicitly because `>` vs `>=` is the
  one-character defect this shape invites, and a fixture using distinct stamps cannot catch it.

### Test-isolation constraints (inherited, non-negotiable)

⛔ `KT_SS_RECEIPTS` is already redirected into the scratch dir at the top of the suite — **any new
test must stay inside `$TMP`.** The suite was measured writing the user's real receipts file on all
11 prune calls before that redirect landed; 20 of 22 live entries were its temp paths. The new tests
add no global-state writer, and that must stay true (`red-team-that-mutates-shared-state`).

---

## Out of scope for Unit 0

The token (D4) · the picker (D1–D3) · the SessionStart branch (D5/D7) · the structural check (D8) ·
receipts on demote (D9) · **all ports** — `plugin-antigravity` and `plugin-cursor-template` carry the
same 8 helpers and `plugin-openai-codex` carries only **2** (no ledger functions at all, measured),
so parity is its own unit with its own dispositions.

## Known residual, carried not closed

`kt_ss_mark_inprogress` rewrites the front-matter on a session's first edit, so `at` tracks **last
touch**, not last meaningful state — a session that edited one file outranks a session holding a real
handoff. **Benign under self-demote and only under self-demote:** the handoff still lands in Pending
rather than being dropped. Recorded in the spec at D10; not fixed here.
