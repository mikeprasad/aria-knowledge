# Unit P — port parity for the handoff-resume + provenance-token arc

**Spec:** `docs/superpowers/specs/2026-09-15-handoff-resume-and-provenance-token-merged-design.md` (GATED).
**Predecessors shipped (all `plugin-claude-code`):** Unit 0 `f97542d` · Unit A `7f1d9e6` `bcd3ab5` ·
Unit B `126d015` · Unit C `6c0c5f8`.
**Ruling inherited:** one deliberate parity unit, **not interleaved** (U16 — a partial parity pass is
worse than a tracked gap).
**Status:** ✅ **GATED 2026-09-16 — `/prospect` PROCEED-WITH-CHANGES; applied at AC-P5.** Gate log:
`knowledge/logs/prospect/2026-09-16-file-unitp-port-parity.md`.

---

## 0. What shipped, and where it has to land

| Change | Kind |
|---|---|
| `kt_ss_read_active_at`, `kt_ss_active_is_newer` | new front-matter readers |
| `kt_ss_ledger_candidates`, `kt_ss_ledger_token_locate` | new ledger readers |
| `kt_ss_ledger_mark_consumed` — literal `index()` + optional `at` | changed matcher |
| `session-start-check.sh` — token branch + R1/R2 | changed directive |
| `handoff` / `wrapup` SKILL.md — at-guard, token, resume mode, picker | changed clauses |

## 1. Port dispositions — measured 2026-09-16, one line of evidence each

| Port | `lib-session-state.sh` | Disposition |
|---|---|---|
| **antigravity** | 8 fns, **generated** | ⭐ **Run `build.sh`.** `build.sh:164` copies canonical `bin/` scripts *and* skills. Everything lands by generation. ⛔ Do NOT hand-patch. |
| **cursor** | 8 fns, **hand-synced** | Run `port-skills-to-mdc.py` for the `.mdc` rules, **and hand-sync `scripts/aria/lib-session-state.sh`** — the generator writes only `RULES_DIR`, it never touches `scripts/aria/`. |
| **codex** | **2 fns** (`find_root`, `mark_inprogress`) | ⛔ **EXCLUDED, and not merely "skipped".** See §2. |
| **cowork** | **absent entirely** | ⛔ **EXCLUDED.** Its skills reference zero ledger helpers (measured `kt_ss_ledger_add` = 0 in both). Consistent today; porting a clause that calls a helper it does not ship would break that. |

## 2. ⛔ codex is excluded, and the reason is a PRE-EXISTING defect this unit must not deepen

Measured: codex ships `kt_ss_find_root` and `kt_ss_mark_inprogress` — **no ledger functions at all** —
while its **`handoff` SKILL.md references `kt_ss_ledger_add` twice and `wrapup` once**. Those calls
cannot succeed on that port today. The demote silently does not run, and the subsequent rewrite
destroys a prior pickup.

⇒ **Porting the at-guard there would add a SECOND reference to a helper the port does not ship.** It
would make the file look more correct while being no more runnable — the
`gate-hosted-where-its-subject-does-not-exist` shape.

⛔ **This unit does not fix that defect either.** It predates this arc, it is already recorded in
`aria-knowledge/CLAUDE.md`, and fixing it means either shipping six helpers to codex or removing the
clauses — both real decisions with their own blast radius, neither of which belongs inside a parity
pass. **Report it; do not absorb it.**

## 3. ⚠ The known hazard of running a generator — budget for it, do not be surprised by it

Recorded: release 2.52.7 ran **neither** generator, both port worktrees read **clean** the whole time,
and running them later changed **38 files** — cursor was 473 lines behind and antigravity was missing
an entire skill.

⇒ **A generator run will very likely sync changes that are NOT mine.** That is the generator working
correctly, not a defect. But it means:

- **T1 must capture the pre-run state** so the diff can be split into *this arc's changes* and
  *inherited drift*.
- ⛔ **Inherited drift is REPORTED, never silently shipped inside this unit's commit.** A parity
  commit that quietly carries a stranger's 400-line backlog is unreviewable.

⭐ **And a clean `git status` answers "has anyone edited this?", never "does this generated file match
its generator?"** Running the generator is the only way to find out.

---

## 4. Tasks

| # | Task | Gate |
|---|---|---|
| **P0** | Baseline: three suites, plus a snapshot of each port's pre-run state | numbers + a diff baseline |
| **P1** | Run `plugin-antigravity/build.sh`; diff and CLASSIFY every changed file as mine vs inherited | classification, not a count |
| **P2** | Run `port-skills-to-mdc.py`; classify the same way | as above |
| **P3** | Hand-sync `plugin-cursor-template/scripts/aria/lib-session-state.sh` from canonical | the 5 symbols present |
| **P4** | Verify parity by SYMBOL, per port, with a firing negative control | ⛔ not by `diff -q` |
| **P5** | Full gates + port suites | all bare exit 0 |

### Acceptance

- **AC-P1** every port that carries `lib-session-state.sh` **and ships ledger functions** carries all
  five new/changed symbols. Measured per symbol, per port.
- **AC-P2** ⛔ **the excluded ports stay excluded** — codex still ships no ledger helpers, cowork still
  has no `lib-session-state.sh`. *Red if* either gained one by accident: a generator that "helpfully"
  fills them in is a silent scope breach.
- **AC-P3** the negative control fires — a symbol that exists nowhere must report absent in every
  port, proving the census can detect absence at all.
- **AC-P4** inherited drift is **named in the report**, file by file, and not folded into this unit's
  commit message as though it were part of the arc.
- **AC-P5** ⛔ **CORRECTED BY THE GATE — the draft named a cursor test suite that DOES NOT EXIST.**
  That is this plan's own §2 pattern landing in its own acceptance criterion. Measured: antigravity
  has 8 `.bats` files and `bats` is installed at `/opt/homebrew/bin/bats` ⇒ runnable; codex has
  `tests/run.sh` ⇒ runnable; **cursor has no test suite at all** (`find` returns empty).
  ⇒ Run antigravity's `.bats` suite, codex's `tests/run.sh` (unchanged — as a control that the
  exclusion held), and the three canonical gates. **Cursor is verified by the per-symbol census
  (AC-P1) plus the canonical gates**, and that bound is stated rather than implied.

## 5. Out of scope

Fixing codex's pre-existing broken ledger references (§2) · the `archive` verb · any behaviour change
to the shipped units · version bumps or a release (this unit changes ports, not versions).
